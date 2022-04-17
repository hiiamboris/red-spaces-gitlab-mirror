Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ needs: map-each, anonymize, reshape, export

;@@ TODO: split render and styles

current-style: as path! []	;-- used as a stack during draw composition

styles: none											;-- reserve names in the spaces/ctx context
render: none

exports: [render set-style]

do with [
	;@@ TODO: ideally colors & fonts should not be inlined - see REP #105
	svm: system/view/metrics
	unless svm/colors [svm/colors: copy #()]			;@@ MacOS fix for #4740
	svmc: copy system/view/metrics/colors
	unless svmc/text [svmc/text: black]					;@@ GTK fix for #4740
	unless svmc/panel [svmc/panel: white - svmc/text]	;@@ GTK fix for #4740
	svf:  system/view/fonts
	serif-12: make font! [name: svf/serif size: 12 color: svmc/text]	;@@ GTK fix for #4901

	;-- very experimental `either` shortener: logic | true-result | false-result
	|: make op! func [a b] [
		switch/default :a [
			#[true] [:b]
			#[false][true]
		] [:a]
	]

	;-- very experimental `either` shortener: value |y true-result |n false-result
	; |y: make op! func [a b] [either :a [:b][:a]]
	; |n: make op! func [a b] [either :a [:a][:b]]
][

	;-- styles should balance between readability, ease of extension and lookup speed
	;-- benchmarks prove that if we define styles as words sequences, lookups are 5x slower (find, parse)
	;-- (because find [a b c [style]] [b] finds the wrong style and requires another inner loop)
	;-- so we should either use paths ('item/subitem) or blocks [item subitem]
	;-- using paths we get another benefit: we can apply the same style to multiple spaces (e.g. hscroll vscroll [style..])
	;-- drawback is that we have to convert words into paths at startup to keep it both readable and efficient
	set 'styles reshape [		;-- styles come before the main drawing code
		host [
			pen off
			fill-pen !(svmc/panel)
			font !(make font! [name: svf/system size: svf/size])
			line-width 2
			box 0x0 (any [size 0x0])	;-- makes host background opaque otherwise it loses mouse clicks on most of it's part
			pen !(svmc/text)
		]

		#if system/platform = 'Linux [					;@@ GTK fix for #4901
			paragraph [
				;-- font can be set in the style!:
				;-- but impossible to debug it, as probe draw lists font with thousands of parents
				(self/font: serif-12 ())				;@@ #3804 - requires self/ or won't work
				; pen blue
			]
		]

		; list/item [[pen cyan]]

		button [
			function [btn] [
				drawn: btn/draw
				bgnd: either btn/pushed? [svmc/text + 0.0.0.120]['off]
				if focused? [
					focus: compose/deep [
						line-width 1
						fill-pen off
				        ; pen pattern 6x6 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0 12x12 fill-pen (svmc/panel) box 3x0 9x3 box 3x9 9x12 box 0x3 3x9 box 9x3 12x9]
				        pen pattern 4x4 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0  8x8  fill-pen (svmc/panel) box 1x0 5x1 box 1x5 5x8  box 0x1 1x5 box 5x1  8x5]
				        ; pen pattern 2x2 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0  4x4  fill-pen (svmc/panel) box 1x0 3x1 box 1x3 3x4  box 0x1 1x3 box 3x1  4x3]
						box 4x4 (btn/size - 4) (max 0 btn/rounding - 2)
					]
				]
				compose/only [
					; shadow 2x4 5 0 (green)			;@@ not working - see #4895; not portable (Windows only)
					fill-pen (bgnd)
					push (drawn)
					(any [focus ()])
				]
			]
		]

		grid-view/window [
			function [window /only xy1 xy2] [
				drawn: window/draw/only xy1 xy2
				bgnd: compose [
					fill-pen !(svmc/text + 0.0.0.120)
					pen off
					box 0x0 (window/size)
				]
				compose [(bgnd) (drawn)]
			]
		]

		cell [
			fill-pen !(svmc/panel)
			box 0x0 (size)
			pen      !(svmc/text)			;-- restore pen after `pen off` in grid
		]
	]
	

	map-each/only/self [w [word! ]] styles [to path! w]	;-- replace words with paths
	map-each/only/self [b [block!]] styles [			;-- extract blocks, construct functions
		either 'function = first b [do b][b]
	]

]


style-typeset!: make typeset! [block! function!]	;@@ hide this

;@@ TODO: profile & optimize this a lot
;@@ devise some kind of style cache tree if it speeds it up
;@@ rename current-style to current-path? as it's not really a style per se..
get-style: function [
	"Fetch styling code object for the current space being drawn"
	/named path [path! block!] "Path to look for (defaults to current-style)"
][
	path: tail as path! either named [path][current-style]
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

set-style: function [name [word! path!] style [block! function!]] [
	name: to path! name
	pos: any [											;-- `put` does not support paths/blocks so have to reinvent it
		find/only/tail styles name
		insert/only tail styles name
	]
	change/only pos :style
]

context [
	;; render cache format: [space-object [children] last-write-index 3x [canvas drawn] ...] (a tree of hashes)
	;;   such cache only has slots for 3 canvas sizes, which should be enough for most cases hopefully
	;;   otherwise we'll have to iterate over all cached canvas sizes which is not great for performance
	;;   last write index helps efficiently fill the cache (other option - use random 3, which is less efficient)
	;; parent cache format: [space-object [containing-node parent-object ...] ...] (flat 2-leveled)
	;;   (one tree is last valid one - for invalidation, another is the one being built currently)
	; hash!: :block!
	render-cache:   make hash! 27						;@@ TODO: cleanup of it?
	parents-list:   make hash! 2048
	
	visited-nodes:  make block! 32						;-- stack of nodes currently visited by render
	visited-spaces: make block! 32						;-- stack of spaces currently visited by render
	append/only visited-nodes render-cache				;-- currently rendered node (hash) where to look up spaces
	
	;; rendering workflow:
	;; render has a name, checks if it exists in render-cache - lookup in visited-nodes by object
	;;   and if it exists in last-parents - which serves as a quick registry of still valid spaces
	;;   if exists and allows caching - returns drawn-code
	;;   if not - renders it again, adds to cache if allows caching
	;; invalidation workflow:
	;; got a space, it's removed from last-parents repeat for parents in last-parents, then their parents
	;; process does not repeat on every `set` since it will be absent in render-cache after 1st invalidation
	
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
			select space 'cache?						;-- must be enabled for caching
			space/size									;-- must have been rendered
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
	

	;-- draw code has to be evaluated after current-style changes, for inner calls to render to succeed
	with-style: function [
		"Draw calls should be wrapped with this to apply styles properly"
		name [word!] code [block!]
	][
		append current-style name
		trap/all/catch code [
			msg: form/part thrown 1000					;@@ should be formed immediately - see #4538
			#print "*** Failed to render (name)!^/(msg)^/"
		]
		take/last current-style
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
		#debug styles [#print "render-face on (face/type) with current-style: (mold current-style)"]
		#assert [
			is-face? :face
			face/type = 'base
			in face 'space
			empty? current-style
		]

		host: face										;-- required for `same-paths?` to have a value (used by cache)
		with-style 'host [
			host-drawn: compose/deep bind get-style face	;-- host style can only be a block
			space-drawn: render-space/only/on face/space xy1 xy2 face/size
			#assert [block? :space-drawn]
			unless face/size [								;-- initial render: define face/size
				face/size: select get face/space 'size
				#assert [face/size]
				host-drawn: compose/deep bind get-style face	;-- reapply the host style using new size
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
			style: get-style
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