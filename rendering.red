Red [
	title:   "Rendering and caching engine for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


render: invalidate: invalidate-cache: paths-from-space: none	;-- reserve names in the spaces/ctx context
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
			do with space style							;-- eval the style to preset facets
			style-ctx									;-- return the context for later above/below lookup & composition
		]
		'else [empty-context]							;-- returns empty context if no /above or /below defined
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
	;; render cache format: [space-object [parent-object name  ...] name [canvas space-size map drawn ...] ...]
	;;   it holds rendered draw block of all spaces that have /cache? = true
	;;   space-size is required because `draw` usually changes space/size and if draw is avoided, /size still must be set
	;;   same for the map: it changes with canvas, has to be fetched from the cache together with the draw block
	;;   unused slots contain 'free word to distinguish committed canvas=none case from unused cache slot
	;;   parent list is used by `invalidate` to go up the tree and invalidate all parents so the target space gets re-rendered
	;;   it holds rendering tree of parent/child relationships on the last rendered frame
	;;   name is the space's name in that particular parent, used by paths-from-space which is used by timers
	
	;; caching workflow:
	;; - drawn spaces draw blocks are committed to the cache if they have /cache? enabled
	;; - render checks cache first, and only performs draw if cache is not found
	;;   each slot group corresponds to a particular canvas size
	;;   (usually 3 slots: unlimited, half-unlimited and limited, but tube uses 3 other except none)
	;; - spaces should detect changes in their data that require new rendering effort and call `invalidate`
	;;   invalidate uses last rendered parents tree to locate upper nodes and invalidate them all
	;;   (there can be multiple parents to the same space, but see comments on limitations)
	;@@ TODO: document this in a proper place
	
	; hash!: :block!
	;; after changing cache format multiple times, I'm using named constants now:
	parents-index:  2									;-- where parents are located
	slots-index:    3									;-- where slots are located
	slot-size:      4									;-- size occupied by a single cached entry
	;@@ TODO: render-cache requires cleanup on highly dynamic layouts, or they slow down
	;@@ will need a flat registry of still valid spaces
	render-cache:   make hash! slots-index * 1024
	
	#debug cache [space-names: make hash! 2048]			;-- used to get space objects names for debug output
	
	memoized-paths: make hash! 2 * 1024					;-- [space paths] - necessary to lighten the timers code!
	
	;@@ WARNING: does not copy! paths may change if not copied by the caller
	;@@ and in case space was invalidated, this will not return anything - needs design improvement, maybe separate tree
	set 'paths-from-space function [
		"Get all paths for SPACE on the last rendered frame"
		space  [object!]
		; return: [path! block!] "May return single path! or a block of"
	][
		; #assert [is-face? host]
		unless result: select/same memoized-paths space [
			result: make [] 10
			path: clear []
			paths-continue* space path result
			repend memoized-paths [space result]
		]
		result
	]
		
	paths-continue*: function [
		space  [object!]
		path   [block!]
		result [block!]
	][
		parents: select/same render-cache space
		either empty? parents [
			unless is-face? space [exit]				;-- not rendered space - cannot be traced to the root
			append/only result reverse copy head path
		][
			append invalidation-stack space				;-- defence from cycles ;@@ rename since it's also used here?
			foreach [parent child-name] parents [
				unless find/same invalidation-stack parent [
					change path child-name
					paths-continue* parent next path result
				]
			]
			remove path
			remove top invalidation-stack
		]
	]
	
	;@@ a bit of an issue here is that <everything> doesn't call /invalidate() funcs of all spaces
	;@@ but maybe they won't be needed as I'm improving the design?
	set 'invalidate function [
		"Invalidate SPACE content and cache, or use <everything> to affect all spaces' cache"
		space [word! object! tag!] "If contains `invalidate` func, it is evaluated"
	][
		if word? space [
			space: get space
			#assert [object? space]
		]
		invalidate-cache space
		all [
			object? space
			any-function? custom: select space 'invalidate
			custom
		]
	]
	
	invalidation-stack: make hash! 32
	
	set 'invalidate-cache function [
		"If SPACE's draw caching is enabled, enforce next redraw of it and all it's ancestors"
		space [object! tag!] "Use <everything> to affect all spaces"
		/only "Do not invalidate parents (e.g. if they are invalid already)"
		/forget "Forget also location on the tree (space won't receive timer events until redrawn)"
		;; /forget should be used to clean up cache from destroyed spaces (e.g. hidden menu)
	][
		#debug profile [prof/manual/start 'invalidation]
		either tag? space [
			#assert [space = <everything>]
			;@@ what method to prefer? parse or radical (clear)? clear is dangerous - breaks timers by destroying parents tree
			clear render-cache
			clear memoized-paths
		][
			unless find/same invalidation-stack space [			;-- stack overflow protection for cyclic trees 
				#debug cache [#print "Invalidating (any [select space-names space 'unknown]) of size=(space/size)"]
				if pos: find/same memoized-paths space [fast-remove pos 2]
				either node: find/same render-cache space [
					;; currently rendered spaces should not be invalidated, or parents get lost:
					unless find/same visited-spaces space [
						unless only [
							;; no matter if cache?=yes or no, parents still have to be invalidated
							#assert [not find/same node/:parents-index space]	;-- normally space should not be it's own parent
							#debug cache [
								;; this may still happen normally, e.g. as a result of a reaction on rendered space
								#assert [empty? visited-spaces "Tree invalidation during rendering cycle detected"]
							]
							append invalidation-stack space
							either forget					;@@ use apply
								[foreach [parent _] node/:parents-index [invalidate-cache/forget parent]]
								[foreach [parent _] node/:parents-index [invalidate-cache parent]]
							remove top invalidation-stack	;@@ not using take/last for #5066
							; if in space 'dirty? [space/dirty?: yes]		;-- mark for redraw
						]
						clear node/:slots-index				;-- clear cached slots
						if forget [
							clear node/:parents-index		;-- clear parents now
							change node 'free				;-- mark free for claiming (so blocks can be reused)
						]
					]
				][
					if in space 'dirty? [space/dirty?: yes]		;-- mark host for redraw
				]
			]
		]
		#debug profile [prof/manual/end 'invalidation]
	]
	
	get-cache: function [
		"If SPACE's draw caching is enabled and valid, return it's cached slot for given canvas"
		space [object!] canvas [pair! none!]
	][
		r: all [
			cache: find/same render-cache space			;-- must have a cache
			find/skip cache/:slots-index canvas slot-size
		]
		; if cache [print rejoin ["cache=" map-each/eval [a b _] copy/part skip cache prefix slots [[a b]]]]
		#debug cache [
			name: any [select space-names space 'unknown]
			either r [
				#print "Found cache for (name) size=(space/size) on canvas=(canvas): (mold/flat/only/part to [] r 40)"
			][
				reason: case [
					cache [rejoin ["cache=" mold to [] extract cache/:slots-index slot-size]]
					not space/size ["never drawn"]
					not select space 'cache? ["cache disabled"]
					'else ["not cached or invalidated"]
				]
				#print "Not found cache for (name) size=(space/size) on canvas=(canvas), reason: (reason)"
			]
		]
		r
	]
	
	commit-cache: function [
		"Save SPACE's Draw block on this CANVAS in the cache"
		space  [object!]
		canvas [pair! none!]
		drawn  [block!]
	][
		unless select space 'cache? [exit]				;-- do nothing if caching is disabled
		#assert [pair? space/size]
		map: select space 'map							;-- doesn't have to exist
		node: find/same render-cache space
		#assert [node "Node has been invalidated during render"]
		either slot: find/skip node/:slots-index canvas slot-size [
			rechange next slot [space/size map drawn]
		][
			repend node/:slots-index [canvas space/size map drawn]
		]
		#debug cache [
			name: any [select space-names space 'unknown]
			#print "Saved cache for (name) size=(space/size) on canvas=(canvas): (mold/flat/only/part drawn 40)"
		]
	]
	
	set-parent: function [
		"Mark parent/child relationship in the parents cache"
		child  [object!] "Space"
		name   [word!]
		parent [object! none!] "Space or host face"
	][
		;; `none` may happen during init phase, e.g. autofit calls render to estimate row sizes
		;; in this case cache slot has still to be created
		#assert [not child =? parent]
		case [
			parents: select/same render-cache child [
				any [
					not parent							;-- happens only when render is called without host
					find/same/only parents parent		;-- do not duplicate parents
					append append parents parent name	;@@ should name be updated if parent is found?
				]
			]
			node: find render-cache 'free [
				change node child
				if parent [append append node/:parents-index parent name]
			]
			'else [
				parents: make hash! 2
				if parent [reduce/into [parent name] parents]
				repend render-cache [child parents make hash! slot-size * 4]
			]
		]
	]
	
	visited-spaces: make block! 50						;-- used to track parent/child relations
	enter-space: function [
		space [object!] name [word!]
	][
		set-parent space name last visited-spaces
		append visited-spaces space
	]
	leave-space: does [remove top visited-spaces]

	cache-size?: function [] [							;-- for cache creep detection
		size: length? render-cache
		for-each [inner [block! hash!]] render-cache [
			size: size + length? inner
		]
		size
	]

	#if true = get/any 'disable-space-cache? [
		clear body-of :invalidate-cache
		append clear body-of :get-cache none
		clear body-of :commit-cache
		clear body-of :set-parent
		clear body-of :enter-space
		clear body-of :leave-space
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
		take/last current-path
	]
	
	render-face: function [
		face [object!] "Host face"
	][
		#debug styles [#print "render-face on (face/type) with current-path: (mold current-path)"]
		#assert [
			is-face? :face
			face/type = 'base
			in face 'space
			empty? current-path
		]

		host: face										;-- required for `same-paths?` to have a value (used by cache)
		append visited-spaces host
		with-style 'host [
			style: apply-current-style face				;-- host style can only be a block
			canvas: if face/size [encode-canvas face/size -1x-1]	;-- fill by default
			drawn: render-space/on face/space canvas
			#assert [block? :drawn]
			unless face/size [									;-- initial render: define face/size
				space: get face/space
				#assert [space/size]
				face/size: space/size
				style: apply-current-style face			;-- reapply the host style using new size
			]
			render: combine-style drawn style
		]
		clear visited-spaces
		; #debug cache [#print "cache size=(cache-size?)"]
		; #print "cache size=(cache-size?)"
		any [render copy []]
	]

	render-space: function [
		name [word!] "Space name pointing to it's object"
		/window xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!]
	][
		; if name = 'cell [?? canvas]
		#debug profile [prof/manual/start 'render]
		space: get name
		#debug cache [any [find/same space-names space repend space-names [space name]]]	
		#debug cache [#print "Rendering (name)"]	
		; if canvas [canvas: max 0x0 canvas]				;-- simplifies some arithmetics; but subtract-canvas is better
		#assert [space? :space]
		#assert [not is-face? :space]					;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face
		#assert [
			any [
				none = canvas (abs canvas) +<= (1e6 by 1e6) canvas/x = 2e9 canvas/y = 2e9
				also no #print "(name): canvas=(canvas)" 
			] "Oversized canvas detected!"
		]
		#assert [
			any [
				none = canvas
				all [
					canvas/x <> negate infxinf/x
					canvas/y <> negate infxinf/y
				]
			] "Negative infinity canvas detected!"
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
				cache: get-cache space canvas
			][
				set [size: map: render:] next cache
				#assert [pair? size]
				maybe space/size: size
				if in space 'map [quietly space/map: map]
				set-parent space name last visited-spaces	;-- mark parent/child relations
				#debug cache [							;-- add a frame to cached spaces after committing
					render: compose/only [(render) pen green fill-pen off box 0x0 (space/size)]
				]
			][
				; if name = 'list [print ["canvas:" canvas mold space/content]]
				#debug profile [prof/manual/start name]
				enter-space space name					;-- mark parent/child relations
				style: apply-current-style space
				
				either object? :style [
					draw: select space 'draw
					
					;@@ this basically cries for FAST `apply` func!!
					if function? :draw [
						spec: spec-of :draw
						either find spec /window [window: any [xy1 xy2]][set [xy1: xy2: window:] none]
						canvas': if find spec /on [canvas]		;-- must not affect `canvas` used by cache, thus new name
						code: case [						;@@ workaround for #4854 - remove me!!
							all [canvas' window] [[draw/window/on xy1 xy2 canvas']]
							window               [[draw/window    xy1 xy2        ]]
							canvas'              [[draw/on                canvas']]
						]
					]
					draw: either code [do copy/deep code][draw]	;-- call the draw function if not called yet
					#assert [block? :draw]
					render: combine-style draw style
				][
					#assert [function? :style]
					;@@ this basically cries for FAST `apply` func!!
					spec: spec-of :style
					either find spec /window [window: any [xy1 xy2]][set [xy1: xy2: window:] none]
					canvas': if find spec /on [canvas]	;-- must not affect `canvas` used by cache, thus new name
					code: case [					
						all [canvas' window] [[style/window/on space xy1 xy2 canvas']]
						window               [[style/window    space xy1 xy2        ]]
						canvas'              [[style/on        space         canvas']]
					]
					render: either code [do copy/deep code][style space]	;@@ workaround for #4854 - remove me!!
					#assert [block? :render]
				]
				
				leave-space
				unless any [xy1 xy2] [commit-cache space canvas render]
				; commit-cache space canvas render
				
				#debug profile [prof/manual/end name]
				#assert [any [space/size name = 'grid] "render must set the space's size"]	;@@ should grid be allowed have infinite size?
			]
		]
		#debug profile [prof/manual/end 'render]	
		either render [
			reduce ['push render]						;-- don't carry styles over to next spaces
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
