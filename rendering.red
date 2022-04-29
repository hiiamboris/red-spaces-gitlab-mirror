Red [
	title:   "Rendering and caching engine for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


render: invalidate: invalidate-cache: none				;-- reserve names in the spaces/ctx context
exports: [render invalidate]

current-path: as path! []								;-- used as a stack during draw composition

style-typeset!: make typeset! [block! function!]		;@@ hide this

;@@ TODO: profile & optimize this a lot
;@@ devise some kind of style cache tree if it speeds it up
get-current-style: function [
	"Fetch styling code object for the current space being drawn"
	/named path [path! block!] "Path to look for (defaults to current-style)"
][
	path: tail as path! either named [path][current-path]
	#assert [not head? path]
	until [												;-- look for the most specific fitting style
		p: back path
		style: any [find/only styles p  style]
		head? path: p
	]
	unless style [return []]
	style: first find style style-typeset!				;-- style groups support
	#debug styles [#print "Style for (p) is (mold/flat :style)"]
	:style
]


context [
	;; render cache format: [space-object [children] last-write-index 4x [canvas space-size drawn] ...] (a tree of hashes)
	;;   it holds rendered draw block of all spaces that have /cache? = true
	;;   such cache only has slots for 4 canvas sizes, which should be enough for most cases hopefully
	;;   otherwise we'll have to iterate over all cached canvas sizes which is not great for performance
	;;   last write index helps efficiently fill the cache (other option - use random 4, which is less efficient)
	;;   space-size is required because `draw` usually changes space/size and if draw is avoided, /size still must be set
	;;   unused slots contain 'free word to distinguish committed canvas=none case from unused cache slot
	;; parent cache format: [space-object [containing-node parent-object ...] ...] (flat 2-leveled)
	;;   parent cache is used by `invalidate` to go up the tree and invalidate all parents so the target space gets re-rendered
	;;   it holds rendering tree of parent/child relationships on the last rendered frame
	
	;; caching workflow:
	;; - drawn spaces draw blocks are committed to the cache if they have /cache? enabled
	;; - render checks cache first, and only performs draw if cache is not found
	;;   each block corresponds to a particular canvas size (usually 3: unlimited, half-unlimited and limited, but tube uses 3 except none)
	;; - spaces should detect changes in their data that require new rendering effort and call `invalidate`
	;;   invalidate uses last rendered parents tree to locate upper nodes and invalidate them all
	;;   (there can be multiple parents to the same space)
	;@@ TODO: document this in a proper place
	
	; hash!: :block!
	slots:          12									;-- must be x3! triple max number of cache slots per single space
	;@@ TODO: both render-cache and parents-list require cleanup on highly dynamic layouts, or they slow down
	;@@ will need a flat registry of still valid spaces
	render-cache:   make hash! slots + 3 * 3
	parents-list:   make hash! 2048
	
	visited-nodes:  make block! 32						;-- stack of nodes currently visited by render
	visited-spaces: make block! 32						;-- stack of spaces currently visited by render
	append/only visited-nodes render-cache				;-- currently rendered node (hash) where to look up spaces
	
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
	
	invalidation-stack: make hash! []
	
	set 'invalidate-cache function [
		"If SPACE's draw caching is enabled, enforce next redraw of it and all it's ancestors"
		space [object! tag!] "Use <everything> to affect all spaces"
		/only "Do not invalidate parents (e.g. if they are invalid already)"
	][
		#debug profile [prof/manual/start 'invalidation]
		either tag? space [
			#assert [space = <everything>]
			; dump-parents-list parents-list render-cache
			;@@ what method to prefer? parse or radical?
			clear render-cache
			clear parents-list
			; parse render-cache rule: [any [skip into rule skip slots change skip 'free]]
		][
			unless find/same invalidation-stack space [			;-- stack overflow protection for cyclic trees 
				#debug cache [#print "Invalidating space=[(mold/part/only/flat body-of space 80)]"]
				if pos: find/same parents-list space [			;-- no matter if cache?=yes or no, parents still have to be invalidated
					append invalidation-stack space
					foreach [node parent] pos/2 [
						while [node: find/same/tail node space] [
							change/dup at node 3 'free slots	;-- remove cached draw blocks but not the children node!
						]
						#assert [not space =? parent]
						all [
							not only
							parent								;-- can be none if upper-level space
							invalidate-cache parent
						]
					]
					remove top invalidation-stack
				]
			]
		]
		#debug profile [prof/manual/end 'invalidation]
	]
	
	find-cache: function [
		"Find location of SPACE in the currently rendered cache node"
		space [object!]
	][
		find/same last visited-nodes space
	]
	
	get-cache: function [
		"If SPACE's draw caching is enabled and valid, return it's cached draw block"
		space [object! word!] canvas [pair! none!]		;-- word helps debugging
	][
		if word? space [space: get name: space]			;@@ remove me once cache is stable to speed it up
		r: all [
			cache: find-cache space								;-- must have a cache
			find/skip/part skip cache 3
				any [canvas 'none] 3 slots						;@@ workaround for #5126
			; find/skip/part skip cache 3 canvas 3 slots			;-- search for the same canvas among 3 options
			; print mold~ copy/part cache >> 2 slots
		]
		; if cache [print rejoin ["cache=" map-each/eval [a b _] copy/part skip cache 3 slots [[a b]]]]
		#debug cache [
			name: any [name 'space]
			either r [
				#print "Found cache for (name) size=(space/size) on canvas=(canvas): (mold/flat/only/part to [] r 40)"
			][
				reason: case [
					cache [rejoin ["cache=" mold to [] extract copy/part skip cache 3 slots 3]]
					not space/size ["never drawn"]
					not select space 'cache? ["cache disabled"]
					'else ["not cached or invalidated"]
					; 'else [probe~ last visited-nodes "not cached or invalidated"]
				]
				#print "Not found cache for (name) size=(space/size) on canvas=(canvas), reason: (reason)"
			]
		]
		r
	]
	
	commit-cache: function [
		"Save SPACE's Draw block on this CANVAS in the cache"
		space  [object! word!]							;-- word helps debugging
		canvas [pair! none!]
		drawn  [block!]
	][
		if word? space [space: get name: space]			;@@ remove me once cache is stable to speed it up
		unless select space 'cache? [exit]				;-- do nothing if caching is disabled
		cache: find/same last visited-nodes space
		#assert [cache]
		canvas: any [canvas 'none]						;@@ workaround for #5126
		unless pos: find/skip/part skip cache 3 canvas 3 slots [
			pos: skip cache 3 + (cache/3 * 3)
			change at cache 3 cache/3 + 1 % (slots / 3)			;@@ #5120
			; pos/1: canvas								;@@ #5120
			change pos canvas
		]
		; pos/2: drawn									;@@ #5120
		#assert [pair? space/size]
		change/only change next pos space/size drawn
		#debug cache [
			name: any [name 'space]
			#print "Saved cache for (name) size=(space/size) on canvas=(canvas): (mold/flat/only/part drawn 40)"
		]
	]
	
	set-parent: function [
		"Mark parent/child relationship in the new parents cache"
		child  [object!]
		parent [object! none!]							;-- parent=none is allowed to mark top level spaces as cacheable
	][
		#assert [not child =? parent]
		node: last visited-nodes						;-- tree node where current `child` is found
		either parents: select/same parents-list child [
			pos: any [
				find/same/only parents node				;-- do not duplicate parents
				tail parents
			]
			change change/only pos node parent			;-- each parent contains different node with this child 
		][
			repend parents-list [child reduce [node parent]]
		]
	]
	
	enter-cache-branch: function [
		"Descend down the render cache tree into SPACE's branch"
		space [object!] "Branch is created if doesn't exist"
	][
		set-parent space last visited-spaces 			;-- once set, next renders will look it up in the cache
		append visited-spaces space
		append/only visited-nodes any [
			select/same level: last visited-nodes space
			also branch: make hash! 3 + slots * 2
				append/dup repend level [space branch 0] 'free slots
		]
	]
	
	leave-cache-branch: function [
		"Ascend up the render cache tree"
	][
		remove top visited-nodes
		remove top visited-spaces
	]

	#debug cache [										;-- for cache creep detection
		cache-size?: function [node [any-block!]] [
			size: length? node
			forall node [
				inner: node/2
				size: size + cache-size? inner
				node: skip node 2 + slots
			]
			size
		]
		parents-size?: function [] [
			size: length? parents-list
			foreach [_ block] parents-list [size: size + length? block]
		]
	]

	#if true = get/any 'disable-space-cache? [
		clear body-of :invalidate-cache
		append clear body-of :get-cache none
		clear body-of :commit-cache
		clear body-of :set-parent
		clear body-of :enter-cache-branch
		clear body-of :leave-cache-branch
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
		/only xy1 [pair! none!] xy2 [pair! none!]
	][
		#debug styles [#print "render-face on (face/type) with current-path: (mold current-path)"]
		#assert [
			is-face? :face
			face/type = 'base
			in face 'space
			empty? current-path
		]

		host: face										;-- required for `same-paths?` to have a value (used by cache)
		with-style 'host [
			style: compose/deep bind get-current-style face	;-- host style can only be a block
			drawn: render-space/only/on face/space xy1 xy2 face/size
			#assert [block? :drawn]
			unless face/size [								;-- initial render: define face/size
				face/size: select get face/space 'size
				#assert [face/size]
				style: compose/deep bind get-current-style face	;-- reapply the host style using new size
			]
			render: reduce [style drawn]
		]
		#debug cache [#print "cache size=(cache-size? render-cache) parents size=(parents-size?)"]
		any [render copy []]
	]

	render-space: function [
		name [word!] "Space name pointing to it's object"
		/only xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!]
	][
		; if name = 'cell [?? canvas]
		#debug profile [prof/manual/start 'render]	
		space: get name
		; if canvas [canvas: max 0x0 canvas]				;-- simplifies some arithmetics; but subtract-canvas is better
		#assert [space? :space]
		#assert [not is-face? :space]					;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face
		#assert [
			any [
				none = canvas canvas +<= (1e6 by 1e6) canvas/x = 2e9 canvas/y = 2e9
				also no #print "(name): canvas=(canvas)" 
			] "Oversized canvas detected!"
		]
		#assert [
			any [
				none = canvas  0x0 +<= canvas
				also no #print "(name): canvas=(canvas)" 
			] "Negative canvas detected!"
		]

		with-style name [
			style: get-current-style
			;@@ this does not allow the style code to invalidate the cache
			;@@ which is good for resource usage, but limits style power
			;@@ so maybe compose styles first, then check the cache?
			
			either all [
				not xy1 not xy2							;-- usage of region is not supported by current cache model
				cache: get-cache name canvas
			][
				set [size: render:] next cache
				#assert [pair? size]
				maybe space/size: size
				set-parent space last visited-spaces	;-- mark it as cached in the new parents tree
				#debug cache [							;-- add a frame to cached spaces after committing
					render: compose/only [(render) pen green fill-pen off box 0x0 (space/size)]
				]
			][
				; if name = 'list [print ["canvas:" canvas mold space/item-list]]
				#debug profile [prof/manual/start name]
				enter-cache-branch space
				
				either block? :style [
					style: compose/deep bind style space	;@@ how slow this bind will be? any way not to bind? maybe construct a func?
					draw: select space 'draw
					
					;@@ this basically cries for FAST `apply` func!!
					if all [function? :draw  any [xy1 xy2 canvas]] [
						spec: spec-of :draw
						either find spec /only [only: any [xy1 xy2]][set [xy1: xy2: only:] none]
						canvas': either find spec /on [canvas][on: none]		;-- must not affect `canvas` used by cache
						if canvas' [canvas': constrain canvas' space/limits]	;-- `none` canvas should never be constrained
						code: case [						;@@ workaround for #4854 - remove me!!
							all [canvas' only] [[draw/only/on xy1 xy2 canvas']]
							only               [[draw/only    xy1 xy2        ]]
							canvas'            [[draw/on              canvas']]
						]
					]
					draw: either code [do copy/deep code][draw]	;-- call the draw function if not called yet
					#assert [block? :draw]
					
					if empty? style [unset 'style]
					render: compose/only [(:style) (:draw)]		;-- compose removes style if it's unset
				][
					#assert [function? :style]
					;@@ this basically cries for FAST `apply` func!!
					either any [xy1 xy2 canvas] [
						spec: spec-of :style
						either find spec /only [only: any [xy1 xy2]][set [xy1: xy2: only:] none]
						canvas': either find spec /on [canvas][on: none]	;-- must not affect `canvas` used by cache
						if canvas' [canvas': constrain canvas' space/limits]
						code: case [					
							all [canvas' only] [[style/only/on space xy1 xy2 canvas']]
							only               [[style/only    space xy1 xy2        ]]
							canvas'            [[style/on      space         canvas']]
						]
						render: either code [do copy/deep code][style space]	;@@ workaround for #4854 - remove me!!
					][
						render: style space
					]
					#assert [block? :render]
				]
				
				leave-cache-branch
				unless any [xy1 xy2] [commit-cache name canvas render]
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
		/only "Limit rendering area to [XY1,XY2] if space supports it"
			xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!] "Specify canvas size as sizing hint"
	][
		; render: either word? space [:render-space][:render-face]
		; render/only/on space xy1 xy2 canvas
		drawn: either word? space [					;@@ workaround for #4854 - remove me!!
			render-space/only/on space xy1 xy2 canvas
		][
			render-face/only space xy1 xy2
		]
		#debug draw [									;-- test the output to figure out which style has a Draw error
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