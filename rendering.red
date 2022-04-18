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
	;; render cache format: [space-object [children] last-write-index 3x [canvas drawn] ...] (a tree of hashes)
	;;   it holds rendered draw block of all spaces that have /cache? = true
	;;   such cache only has slots for 3 canvas sizes, which should be enough for most cases hopefully
	;;   otherwise we'll have to iterate over all cached canvas sizes which is not great for performance
	;;   last write index helps efficiently fill the cache (other option - use random 3, which is less efficient)
	;; parent cache format: [space-object [containing-node parent-object ...] ...] (flat 2-leveled)
	;;   parent cache is used by `invalidate` to go up the tree and invalidate all parents so the target space gets re-rendered
	;;   it holds rendering tree of parent/child relationships on the last rendered frame
	
	;; caching workflow:
	;; - drawn spaces draw blocks are committed to the cache if they have /cache? enabled
	;; - render checks cache first, and only performs draw if cache is not found
	;;   each block corresponds to a particular canvas size (usually 3: unlimited, half-unlimited and limited)
	;; - spaces should detect changes in their data that require new rendering effort and call `invalidate`
	;;   invalidate uses last rendered parents tree to locate upper nodes and invalidate them all
	;;   (there can be multiple parents to the same space)
	
	
	;@@ TODO: document this in a proper place
	; hash!: :block!
	render-cache:   make hash! 27						;@@ TODO: cleanup of it?
	parents-list:   make hash! 2048
	
	visited-nodes:  make block! 32						;-- stack of nodes currently visited by render
	visited-spaces: make block! 32						;-- stack of spaces currently visited by render
	append/only visited-nodes render-cache				;-- currently rendered node (hash) where to look up spaces
	
	;@@ a bit of an issue here is that <everything> doesn't call /invalidate() funcs of all spaces
	;@@ but maybe they won't be needed as I'm improving the design?
	set 'invalidate function [
		"Invalidate SPACE content and cache, or use <everything> to affect all spaces' cache"
		space [object! tag!] "If contains `invalidate` func, it is evaluated"
	][
		invalidate-cache space
		all [
			object? space
			any-function? custom: select space 'invalidate
			custom
		]
	]
	
	;; tag is used so I can later add support for referrng to spaces by words
	set 'invalidate-cache function [
		"If SPACE's draw caching is enabled, enforce next redraw of it and all it's ancestors"
		space [object! tag!] "Use <everything> to affect all spaces"
	][
		either tag? space [
			#assert [space = <everything>]
			clear render-cache
		][
			if pos: find/same parents-list space [		;-- no matter if cache?=yes or no, parents still have to be invalidated
				foreach [node parent] pos/2 [
					while [node: find/same/tail node space] [
						change/dup at node 3 none 6		;-- remove cached draw blocks but not the children node!
					]
					if parent [invalidate-cache parent]	;-- can be none if upper-level space
				]
			]
		]
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
			; select space 'cache?						;-- must be enabled for caching - checked by `commit` to lift it off `get-cache`
			; space/size									;-- must have been rendered - should always be true if cache exists
			cache: find-cache space						;-- must have a cache
			select/skip/part skip cache 3 canvas 2 6	;-- search for the same canvas among 3 options
			; print mold~ copy/part cache >> 2 6
		]
		#debug cache [
			name: any [name 'space]
			either r [
				#print "Found cache for (name) size=(space/size) on canvas=(canvas): (mold/flat/only/part r 40)"
			][
				reason: case [
					cache [rejoin ["cache=" mold to [] extract copy/part skip cache 3 6 2]]
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
		unless pos: find/skip/part skip cache 3 canvas 2 6 [
			pos: skip cache 3 + (cache/3 * 2)
			change at cache 3 cache/3 + 1 % 3			;@@ #5120
			; pos/1: canvas								;@@ #5120
			change pos canvas
		]
		; pos/2: drawn									;@@ #5120
		change/only next pos drawn
		#debug cache [
			name: any [name 'space]
			#print "Saved cache for (name) size=(space/size) on canvas=(canvas)"
		]
	]
	
	set-parent: function [
		"Mark parent/child relationship in the new parents cache"
		child  [object!]
		parent [object! none!]							;-- parent=none is allowed to mark top level spaces as cacheable
	][
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
			also branch: make hash! 18
				repend level [space branch 0 none none none none none none]
		]
	]
	
	leave-cache-branch: function [
		"Ascend up the render cache tree"
	][
		remove top visited-nodes
		remove top visited-spaces
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
	
	#debug cache [										;-- for cache creep detection
		cache-size?: function [node [any-block!]] [
			size: length? node
			foreach [_ inner _ _ _ _ _ _ _] node [size: size + cache-size? inner]
			size
		]
		parents-size?: function [] [
			size: length? parents-list
			foreach [_ block] parents-list [size: size + length? block]
		]
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
			host-drawn: compose/deep bind get-current-style face	;-- host style can only be a block
			space-drawn: render-space/only/on face/space xy1 xy2 face/size
			#assert [block? :space-drawn]
			unless face/size [								;-- initial render: define face/size
				face/size: select get face/space 'size
				#assert [face/size]
				host-drawn: compose/deep bind get-current-style face	;-- reapply the host style using new size
			]
			render: reduce [host-drawn space-drawn]
		]
		#debug cache [#print "cache size=(cache-size? render-cache) parents size=(parents-size?)"]
		any [render copy []]
	]

	render-space: function [
		name [word!] "Space name pointing to it's object"
		/only xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!]
	][
		#debug profile [prof/manual/start 'render]	
		space: get name
		#assert [space? :space]
		#assert [not is-face? :space]					;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face
		#assert [
			any [
				none = canvas canvas +<= (1e6 by 1e6) canvas/x = 2e9 canvas/y = 2e9
				also no #print "(name): canvas=(canvas)" 
			] "Oversized canvas detected!"
		]

		with-style name [
			style: get-current-style
			;@@ this does not allow the style code to invalidate the cache
			;@@ which is good for resource usage, but limits style power
			;@@ so maybe compose styles first, then check the cache?
			
			either all [
				not xy1 not xy2							;-- usage of region is not supported by current cache model
				; render: get-cache space canvas
				render: get-cache name canvas
			][
				set-parent space last visited-spaces	;-- mark it as cached in the new parents tree
				#debug cache [							;-- add a frame to cached spaces after committing
					render: compose/only [(render) pen green fill-pen off box 0x0 (space/size)]
				]
			][
				; if name = 'paragraph [print space/text]
				#debug profile [prof/manual/start name]
				enter-cache-branch space
				
				either block? :style [
					style: compose/deep bind style space	;@@ how slow this bind will be? any way not to bind? maybe construct a func?
					draw: select space 'draw
					
					;@@ this basically cries for FAST `apply` func!!
					if all [function? :draw  any [xy1 xy2 canvas]] [
						spec: spec-of :draw
						either find spec /only [only: any [xy1 xy2]][set [xy1: xy2: only:] none]
						canvas': either find spec /on [canvas][on: none]	;-- must not affect `canvas` used by cache
						if canvas' [constrain canvas': canvas' space/limits]
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
						if canvas' [constrain canvas': canvas' space/limits]
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
				#assert [space/size "render must set the space's size"]
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