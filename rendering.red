Red [
	title:   "Rendering and caching engine for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


render: none				;-- reserve names in the spaces/ctx context
exports: [render]

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
	path: copy current-path
	forall path [path/1: path/1/type]
	get-style as path! path
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
	check-parent-override: function [space [object!] new-parent [object!]] [	;-- only used before changing the /parent
		all [
			last-gen: cache/last-generation space
			next-gen: cache/current-generation
			last-gen = next-gen
			:space/parent
			unless :space/parent =? :new-parent [
				print `"*** Warning on rendering of (space/type):"`
				assert [:space/parent =? :new-parent "Parent sharing detected!"]
			]
		]
	]

	;; this is very important to see in profile results, as it's the main cause for slowdown
	;; so I moved this from 'changes' to 'profile' category (must be synced with render-face)
	#debug profile [
		;; checks after full face render for any invalidated spaces (have /cache enabled but /cached empty):
		verify-validity: function [host [object!] (host? host)] [
			paths: sift list-spaces host/space [		;-- obtain a list of possibly invalidated spaces
				path .. obj: last path
				obj/cache								;-- cache enabled?
				empty? obj/cached						;-- no cached slots?
				obj/size								;-- has a finite size? (else can't be cached)
				not zero? area? obj/size				;-- not empty size? (may have no cached slots otherwise)
				not :obj/on-invalidate					;-- not using custom cache? (otherwise this heuristic doesn't apply)
			]
			unless empty? paths [
				print "*** Unwanted invalidation of the following spaces detected during render: ***"
				print mold/only new-line/all paths on
			]
		]
	]
	
	;; draw code has to be evaluated after current-path changes, for inner calls to render to succeed
	set 'with-style function [							;-- exported for an ability to spoof the tree (for roll, basically)
		"Draw calls should be wrapped with this to apply styles properly"
		space [object! path!]							;-- path support is useful for out of tree renders (like roll)
		code  [block!]
	][
		top: tail current-path
		append current-path space
		
		thrown: try/all [do code  ok?: yes]				;-- result is ignored for simplicity
		unless ok? [
			msg: form/part thrown 1000					;@@ should be formed immediately - see #4538
			#print "*** Failed to render (space/type)!^/(msg)^/"
		]
		;@@ would be great to use trap here instead, but it slows down cached renders obviously
		; trap/all/catch code [
			; msg: form/part thrown 1000					;@@ should be formed immediately - see #4538
			; #print "*** Failed to render (space/type)!^/(msg)^/"
		; ]
		clear top
	]
	
	render-face: function [
		face [object!] "Host face"
	][
		#debug styles [#print "render-face on (face/type) with current-path: (mold current-path)"]
		#assert [
			host? :face
			empty? current-path
		]

		cache/with-generation face/generation + 1.0 [
			without-GC [								;-- speeds up render by 60%
				with-style face [
					style: apply-current-style face		;-- host style can only be a block
					canvas: if face/size [encode-canvas face/size 1x1]	;-- fill by default
					drawn: render-space/on face/space canvas
					#assert [block? :drawn]
					unless face/size [					;-- initial render: define face/size
						#assert [face/space/size]
						face/size: face/space/size
						style: apply-current-style face	;-- reapply the host style using new size
					]
					drawn: combine-style drawn style
				]
			]
			face/generation: cache/current-generation	;-- only updated if no error happened during render
		]
		#debug profile [verify-validity face]			;-- check for unwanted invalidations during render, which may loop it
		any [drawn copy []]								;-- drawn=none in case of error during render
	]

	render-space: function [
		space [object!] (space? space)
		/window xy1 [pair! none!] xy2 [pair! none!]
		/on canvas: infxinf [pair! none!]
	][
		; if name = 'cell [?? canvas]
		#debug profile [prof/manual/start 'render]
		name: space/type
		#debug cache [#print "Rendering (name)"]	
		; if canvas [canvas: max 0x0 canvas]				;-- simplifies some arithmetics; but subtract-canvas is better
		#assert [
			space? :space
			not host? :space							;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face
			any [
				(abs canvas) +<= (1e6 by 1e6)
				canvas/x = infxinf/x
				canvas/y = infxinf/y
				also no #print "(name): canvas=(canvas)" 
			] "Oversized canvas detected!"
			(negate infxinf) +< canvas	"Negative infinity canvas detected!"
		]

		unless tail? current-path [						;-- can be at tail on out-of-tree renders
			#debug [check-parent-override space last current-path]
			quietly space/parent: last current-path		;-- should be set before any child render call! so styles can access /parent
		]
		with-style space [
			window?: all [
				any [xy1 xy2]
				function? draw: select space 'draw
				find spec-of :draw /window
				;@@ this should also check if style func supports /window but it's already too much hassle, maybe later
			]
			
			either all [
				not window?								;-- usage of region is not supported by current cache model
				set [words: slot:] cache/fetch space canvas
			][
				drawn: slot/1
				do-atomic [								;-- prevent reactions from invalidating the cache while it's used by `set`
					set words next slot					;-- size map etc..
				]
				cache/update-generation space 'cached
				#debug cache [							;-- add a frame to cached spaces after committing
					if space/size [
						drawn: compose/only [(drawn) pen green fill-pen off box 0x0 (space/size)]
					]
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
				
				unless any [xy1 xy2] [cache/commit space canvas drawn]
				cache/update-generation space 'drawn
				
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
		space [object!] "Space or host face as object"
		/window "Limit rendering area to [XY1,XY2] if space supports it"
			xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!] "Specify canvas size as sizing hint"
	][
		drawn: either host? space [
			render-face space
		][
			render-space/window/on space xy1 xy2 canvas
		]
		#debug draw [									;-- test the output to figure out which style has a "Draw error"
			if error? error: try/keep [draw 1x1 drawn] [
				prin "*** Invalid draw block: "
				attempt [copy/deep drawn]				;@@ workaround for #5111
				probe drawn
				do error
			]
		]
		drawn
	]
]


export exports
