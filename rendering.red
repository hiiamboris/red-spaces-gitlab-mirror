Red [
	title:   "Rendering and caching engine for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


render: invalidate: paths-from-space: none				;-- reserve names in the spaces/ctx context
exports: [render invalidate]

current-path: as path! []								;-- used as a stack during draw composition

style-typeset!: make typeset! [block! function!]		;@@ hide this

;@@ TODO: profile & optimize this a lot
;@@ devise some kind of style cache tree if it speeds it up
get-style: function [
	"Fetch style for some tree path"
	path [path! block!]
][
	#assert [not empty? head path]
	path: tail path
	until [												;-- look for the most specific fitting style
		p: back path
		style: any [select/only/skip styles p 2  :style]
		head? path: p
	]
	default style: [[]]									;-- for `do` to return empty block
	#debug styles [#print "Style for (p) is (mold/flat :style)"]
	:style
]
	
get-current-style: function [
	"Fetch styling code object for the current space being drawn"
][
	get-style as path! current-path
]


empty-context: context []

apply-current-style: function [
	"Apply relevant style to current space being drawn"
	space [object!] "Face or space object"
][
	case [
		function? style: get-current-style [:style]		;-- function is not applied here, only in render
		style-ctx: all [
			pos: any [find style 'above  find style 'below]
			context? first pos
		] [
			set style-ctx none							;-- clean the context from old values
			do bind style space							;-- eval the style to preset facets
			copy/deep style-ctx							;-- return the context for later above/below lookup & composition
		]
		'else [
			do bind style space							;-- eval the style to preset facets
			empty-context								;-- returns empty context if no /above or /below defined
		]
	]
]

combine-style: function [
	"Combine style & draw code into final block"
	drawn [block!] "Draw code produced by space/draw"
	style [object!] "Styling context from apply-current-style"
][
	reduce [
		compose/deep only select style 'below 
		drawn
		compose/deep only select style 'above
	]
]

;@@ what may speed everything up is a rendering mode that only sets the size and nothing else
context [
	get-space-name: function [space [object!]] [
		any [all [block? :space/last-frame space/last-frame/1] 'unknown]		;@@ REP #113
	]
	check-owner-override: function [space [object!] new-owner [word!]] [	;-- only used before changing the /owner
		all [
			block? space/last-frame
			last-gen: space/last-frame/2
			next-gen: attempt [current-generation]
			last-gen = next-gen
			word? :space/owner
			assert [(get space/owner) =? (get new-owner) "Owner sharing detected!"]
		]
	]

	;@@ move this somewhere else
	set 'get-full-path function [
		"Get path for SPACE on the last rendered frame, or none if it's not there"
		space  [object!]
		; return: [path! none!]
	][
		; #assert [is-face? host]
		#assert [space/owner]
		host: first parents: reverse list-parents space
		; #assert [is-face? host]							;-- let there be a warning for now
		unless is-face? host [return none]				;-- fails on self-containing grid ;@@ need a faster check
		gen:  host/generation
		path: clear []
		append path parents/1/parent					;-- faster than anonymizing 'host
		foreach obj next parents [
			frame: obj/last-frame
			unless all [name: frame/1  gen <= frame/2] [return none]
			append path name
			if frame/3 = 'cached [gen: 0.0]				;-- don't check generation numbers inside cached subtree
		]
		append path space/last-frame/1
		#assert [not find path none]
		as path! copy path
	]
		
	
	set 'invalidate-tree function [face [object!]] [	;@@ or accept space instead?
		#assert [is-face? face]
		foreach-space [path space] face/space [invalidate/only space]
	]
	
	;@@ a bit of an issue here is that <everything> doesn't call /invalidate() funcs of all spaces
	;@@ but maybe they won't be needed as I'm improving the design?
	;@@ space/invalidate should be called on-invalidate for less confusion
	
	;@@ should have a global safe wrapper
	parents-list: make hash! 32
	list-parents: function [space [object!]] [			;-- order is bubbling: immediate-parent first, host last
		clear parents-list
		while [
			all [
				; word? :space/owner
				word? select space 'owner				;@@ workaround for #5216 - fixed already, remove me
				space: get space/owner					;@@ REP #113
				not find/same parents-list space
			]
		] [append parents-list space]
		parents-list
	]
	
	set 'invalidate-cache function [space [object!]][	;-- to be used by custom invalidators
		if space/cache = 'valid [
			#debug cache [#print "Invalidating (get-space-name space) of size=(space/size)"]
			clear get word: space/cache
			quietly space/cache: bind 'invalid context? word
		]
	]
	
	;@@ move this out, it's no longer part of render
	set 'invalidate function [
		"Invalidate SPACE cache, to force next redraw"
		space [object!]
		/only "Do not invalidate parents (e.g. if they are invalid already)"
		/info "Provide info about invalidation"
			cause [none! object!] "Invalidated child object or none"	;@@ support word that's changed? any use outside debugging?
			scope [none! word!]   "Invalidation scope: 'size or 'look"
		/local custom									;-- can be unset during construction
	][
		#assert [not is-face? space]
		#assert [not unset? :space/cache  "cache should be initialized before other fields"] 
		unless block? space/cache [						;-- block means space is not created yet; early exit
			#debug profile [prof/manual/start 'invalidation]
			default scope: 'size
			either function? custom: select space 'on-invalidate [
				custom space cause scope				;-- custom invalidation procedure
			][
				invalidate-cache space					;-- generic (full) invalidation
			]
			unless only [								;-- no matter if cache=yes/valid/invalid, parents have to be invalidated
				host: last parents: list-parents space	;-- no need to invalidate the host, as it has no cache
				;; check if space is already connected to the tree (traceable to a host face):
				if all [host  in host 'generation] [	;@@ more reliable host check needed to detect if space belongs to the tree
					clear top parents					;-- no need to invalidate the host, as it has no cache
					#debug changes [
						path: as path! reverse map-each obj parents [get-space-name obj]
						append path get-space-name space
						cause-name: if cause [get-space-name cause]
						#print "invalidating from (path), scope=(scope), cause=(cause-name)"
					]			
					foreach space parents [
						invalidate/only/info space cause scope
						cause: space					;-- parent becomes the new child
					]
				]
			]
			#debug profile [prof/manual/end 'invalidation]
		]
	]
	
	get-cache: function [
		"If SPACE's draw caching is enabled and valid, return it's cached slot for given canvas"
		space [object!] canvas [pair! none!]
	][
		#debug profile [prof/manual/start 'cache]
		result: all [
			'valid = space/cache
			cache: get space/cache
			node: find/same/skip cache canvas 2 + length? cache/-1
			reduce [cache/-1 node]
		]
		;@@ get rid of `none` canvas! it's just polluting the cache, should only be infxinf
		#debug cache [
			name: get-space-name space
			if cache [period: 2 + length? cache/-1]
			either node [
				n: (length? cache) / period
				#print "Found cache for (name) size=(space/size) on canvas=(canvas) out of (n): (mold/flat/only/part to [] node 40)"
			][
				reason: case [
					cache [rejoin ["cache=" mold to [] extract cache period]]
					not space/size ["never drawn"]		;@@ use /parent=none
					not word? space/cache ["cache disabled"]
					space/cache = 'invalid ["invalidated"]
					'else ["unknown reason"]
				]
				#print "Not found cache for (name) size=(space/size) on canvas=(canvas), reason: (reason)"
			]
		]
		#debug profile [prof/manual/end 'cache]
		result
	]
	
	commit-cache: function [
		"Save SPACE's Draw block on this CANVAS in the cache"
		space  [object!]
		canvas [pair! none!]
		drawn  [block!]
	][
		;@@ problem with this is that not cached spaces cannot have timers as they're not connected to the tree!
		unless word? word: space/cache [exit]			;-- do nothing if caching is disabled
		#debug profile [prof/manual/start 'cache]
		#assert [pair? space/size]						;@@ won't be needed once I remove size=none support
		cache:  get word
		period: 2 + length? cache/-1					;-- custom words + canvas + drawn
		node:   any [find/same/skip cache canvas period  tail cache]
		words:  [canvas drawn]							;-- [canvas drawn size map ...] bound names
		clear change next next words cache/-1
		#assert [period = length? words]
		rechange node words
		quietly space/cache: bind 'valid context? word
		#debug cache [
			name: get-space-name space
			#print "Saved cache for (name) size=(space/size) on canvas=(canvas): (mold/flat/only/part drawn 40)"
		]
		#debug profile [prof/manual/end 'cache]
	]
	
	#if true = get/any 'disable-space-cache? [
		clear body-of :invalidate
		append clear body-of :get-cache none
		clear body-of :commit-cache
	]
	
	;-- draw code has to be evaluated after current-path changes, for inner calls to render to succeed
	with-style: function [
		"Draw calls should be wrapped with this to apply styles properly"
		name [word!] code [block!]
	][
		append current-path name
		trap/all/catch code [
			msg: form/part thrown 1000					;@@ should be formed immediately - see #4538
			#print "*** Failed to render (name)!^/(msg)^/"
		]
		remove top current-path							;@@ workaround for #5066
	]
	
	render-face: function [
		face [object!] "Host face"
	][
		#debug styles [#print "render-face on (face/type) with current-path: (mold current-path)"]
		; unless is-face? :face [??~ face]
		#assert [
			is-face? :face								;@@ simplify this using classes!
			'base = select face 'type
			in face 'space
			empty? current-path
		]

		current-generation: face/generation + 1.0
		with-style anonymize 'host face [				;-- required for `same-paths?` to have a value (used by cache)
			style: apply-current-style face				;-- host style can only be a block
			canvas: if face/size [encode-canvas face/size -1x-1]	;-- fill by default
			drawn: render-space/on face/space canvas
			#assert [block? :drawn]
			unless face/size [							;-- initial render: define face/size
				space: get face/space
				#assert [space/size]
				face/size: space/size
				style: apply-current-style face			;-- reapply the host style using new size
			]
			drawn: combine-style drawn style
		]
		face/generation: current-generation
		any [drawn copy []]								;-- drawn=none in case of error during render
	]

	;; this needs to be wrapped in a `try` since some renders can be out-of-tree (e.g. during available? call)
	;; these should not affect the tree
	current-generation: does with :render-face [current-generation]		;-- exported for use in render-space
	
	render-space: function [
		name [word!] "Space name pointing to it's object"
		/window xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!]
	][
		; if name = 'cell [?? canvas]
		#debug profile [prof/manual/start 'render]
		space: get name
		#debug cache [#print "Rendering (name)"]	
		; if canvas [canvas: max 0x0 canvas]				;-- simplifies some arithmetics; but subtract-canvas is better
		#assert [
			space? :space
			not is-face? :space							;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face
			any [
				none = canvas (abs canvas) +<= (1e6 by 1e6) canvas/x = 2e9 canvas/y = 2e9
				also no #print "(name): canvas=(canvas)" 
			] "Oversized canvas detected!"
			any [
				none = canvas
				all [
					canvas/x <> negate infxinf/x
					canvas/y <> negate infxinf/y
				]
			] "Negative infinity canvas detected!"
		]

		unless tail? current-path [
			#debug [check-owner-override space last current-path]
			quietly space/owner: last current-path
		]
		with-style name [
			window?: all [
				any [xy1 xy2]
				function? draw: select space 'draw
				find spec-of :draw /window
				;@@ this should also check if style func supports /only but it's already too much hassle, maybe later
			]
			
			either all [
				not window?								;-- usage of region is not supported by current cache model
				set [words: node:] get-cache space canvas
			][
				drawn: node/2
				;@@ use set or looped set-quiet here? probably won't matter
				set words next next node				;-- size map etc..
				; node: skip node 2  repeat i length? words [set-quiet words/:i :node/:i]
				try [quietly space/last-frame: reduce [name current-generation 'cached]]
				#debug cache [							;-- add a frame to cached spaces after committing
					drawn: compose/only [(drawn) pen green fill-pen off box 0x0 (space/size)]
				]
			][
				; if name = 'list [print ["canvas:" canvas mold space/content]]
				#debug profile [prof/manual/start name]
				style: apply-current-style space
				
				either object? :style [
					draw: select space 'draw
					;@@ this basically cries for FAST `apply` func!!
					if function? :draw [
						spec:    spec-of :draw
						on?:     find spec /on
						window?: find spec /window
						code: case [
							all [on? window?] [[draw/window/on xy1 xy2 canvas]]
							window?           [[draw/window    xy1 xy2       ]]
							on?               [[draw/on                canvas]]
							'else             [[draw                         ]]
						]
						draw: do copy/deep code			;@@ workaround for #4854 - remove me!!
					]
					#assert [block? :draw]
					drawn: combine-style draw style
				][
					#assert [function? :style]
					;@@ this basically cries for FAST `apply` func!!
					spec:    spec-of :style
					on?:     find spec /on
					window?: find spec /window
					code: case [					
						all [on? window?] [[style/window/on space xy1 xy2 canvas]]
						window?           [[style/window    space xy1 xy2       ]]
						on?               [[style/on        space         canvas]]
						'else             [[style           space               ]]
					]
					drawn: do copy/deep code			;@@ workaround for #4854 - remove me!!
					#assert [block? :drawn]
				]
				
				unless any [xy1 xy2] [commit-cache space canvas drawn]
				try [quietly space/last-frame: reduce [name current-generation 'drawn]]
				
				#debug profile [prof/manual/end name]
				#assert [any [space/size find [grid canvas] name] "render must set the space's size"]	;@@ should grid be allowed have infinite size?
			]
		]
		#debug profile [prof/manual/end 'render]	
		either drawn [									;-- drawn=none in case of error during render
			reduce ['push drawn]						;-- don't carry styles over to next spaces
		][
			[]											;-- never changed, so no need to copy it
		]
	]

	set 'render function [
		"Return Draw code to draw a space or host face, after applying styles"
		space [word! object!] "Space name, or host face as object"
		/window "Limit rendering area to [XY1,XY2] if space supports it"
			xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!] "Specify canvas size as sizing hint"
	][
		drawn: either word? space [
			render-space/window/on space xy1 xy2 canvas
		][
			render-face space
		]
		#debug draw [									;-- test the output to figure out which style has a "Draw error"
			if error? error: try/keep [draw 1x1 drawn] [
				prin "*** Invalid draw block: "
				attempt [copy/deep drawn]				;@@ workaround for #5111
				probe~ drawn
				do error
			]
		]
		drawn
	]
]


export exports
