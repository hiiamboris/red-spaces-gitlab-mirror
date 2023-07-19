Red [
	title:   "Rendering and caching engine for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;; uses timers (to prime them) at runtime

render: none				;-- reserve names in the spaces/ctx context
exports: [render]

current-path: as path! []								;-- used as a stack during draw composition

style-typeset!: make typeset! [block! function!]		;@@ hide this

empty-style: does []

;@@ TODO: profile & optimize this a lot
;@@ devise some kind of style cache tree if it speeds it up
get-style: function [
	"Fetch style for some tree path"
	path [path! block!]
][
	#assert [not empty? head path]
	path: tail path
	until [												;-- look for the most specific fitting style
		p: back path									;@@ use for-each/reverse when fast
		style: any [select/only/skip styles p 2  :style]
		head? path: p
	]
	default style: :empty-style
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


apply-current-style: function [
	"Apply relevant style to current space being drawn"
	space [object!] "Face or space object"
][
	;; fast way to check if it accepts arguments (a function style) or not (a block style):
	style-func?: any-word? first spec-of style: get-current-style
	unless style-func? [								;-- function style is not applied here, only in render
		set style-ctx none								;-- clean the shared style context from old values
		bind body-of :style space
		(style)											;-- eval the style to preset facets
		style: copy/deep values-of style-ctx			;-- block is much smaller than copying the context; deep copy avoids rebind on nesting!
	]
	:style
]

combine-style: function [
	"Combine style & draw code into final block"
	drawn [block!] "Draw code produced by space/draw"
	style [block!] "Styling block from apply-current-style"
][
	reduce [
		compose/deep only style/1 
		drawn
		compose/deep only style/2
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
	;@@ apply at least host style when path is given; other styles carryover should not be endorsed
	set 'with-style function [							;-- exported for an ability to spoof the tree (for slide, basically)
		"Draw calls should be wrapped with this to apply styles properly"
		space [block! path! (parse space [any object!]) object!]
			;@@ maybe when path given it should override the current one?
			"Inserted into current rendering path (if any)"		;-- path support is useful for out of tree renders (like slide)
		code  [block!]
	][
		top: tail current-path
		; #assert [any [object? space not find space pair!]  "style path can't contain pairs!"]
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
	
	;; format: [child canvas ...]
	children-stack: make hash! 100						;-- used to track lists of children for each canvas size in the cache
	
	render-face: function [
		face [object!] "Host face"
	][
		#debug styles [#print "render-face on (face/type) with current-path: (mold current-path)"]
		#assert [
			host? :face
			empty? current-path
		]

		children-mark: tail children-stack
		cache/with-generation face/generation + 1.0 [
			without-GC [								;-- speeds up render by 60%
				with-style face [
					style: apply-current-style face		;-- host style can only be a block
					drawn: render-space/on face/space face/size yes yes	;-- fill by default
					#assert [block? :drawn]
					unless face/size [					;-- initial render: define face/size
						#assert [face/space/size]
						face/size: face/space/size
						drawn: render-space/on face/space face/size yes yes	;-- re-render since it couldn't fill the infinite canvas
						style: apply-current-style face	;-- reapply the host style using new size
					]
					drawn: combine-style drawn style
				]
			]
			face/generation: cache/current-generation	;-- only updated if no error happened during render
		]
		clear children-mark
		#debug profile [verify-validity face]			;-- check for unwanted invalidations during render, which may loop it
		any [drawn copy []]								;-- drawn=none in case of error during render
	]

	restore-from-cache: function [space [object!] words [block!] slot [block!] deep? [logic!]] [
		set words skip slot 2 							;-- skip [children drawn]: at [size map etc..]
		if deep? [
			foreach [child ccanvas] slot/1 [
				all [
					ccanvas <> cache/last-canvas child
					set [words': slot':] cache/fetch child ccanvas
					restore-from-cache child words' slot' yes
					cache/update-generation child 'cached ccanvas
				] 
			] 
			#debug cache [#print "restored (half length? slot/1) immediate children states of (space-id space): (mold/flat slot/1)"]
		]
	]

	add-child: function [space [object!] canvas [pair!]] [		;-- list child in its parent's children list
		either pos: find/same/skip/tail children-stack space 2 [
			change pos canvas
		][
			append append children-stack space canvas
		]
	]
				
	;@@ since 'apply' doesn't support silently ignoring refinements not present in the function, have to manually dispatch :(
	safe-draw: function [
		draw   [function!]
		space  [object! none!]
		xy1    [pair! none!]
		xy2    [pair! none!]
		canvas [pair!]
		fill-x [logic!]
		fill-y [logic!]
	][
		window: in :draw /window
		if on:  in :draw /on [
			if canvas/x = infxinf/x [fill-x: no]		;-- inf canvas cannot be filled (result of canvas extension)
			if canvas/y = infxinf/y [fill-y: no]
		]
		index:  (either on [1][0]) + (either window [2][0]) + (either space [4][0])
		do pick [
			[draw                                             ]
			[draw/on                      canvas fill-x fill-y]
			[draw/window          xy1 xy2                     ]
			[draw/window/on       xy1 xy2 canvas fill-x fill-y]
			[draw           space                             ]
			[draw/on        space         canvas fill-x fill-y]
			[draw/window    space xy1 xy2                     ]
			[draw/window/on space xy1 xy2 canvas fill-x fill-y]
		] index + 1
	]
					
	render-space: function [
		space [object!] (space? space)
		/window xy1 [pair! none!] xy2 [pair! none!]
		/on canvas: infxinf [pair! none!] fill-x: no [logic!] fill-y: no [logic!]
		/crude
	][
		; if name = 'cell [?? canvas]
		#debug profile [prof/manual/start 'render]
		name: space/type
		#assert [
			(finite-canvas canvas) +<= (1e6 by 1e6)	"Oversized canvas detected!"
			0x0 +<= canvas							"Negative canvas detected!"
		]
		encoded-canvas: encode-canvas canvas fill-x fill-y
		#debug cache [#print "Rendering (color-name select space 'color) (name) on (encoded-canvas)"]	
		; #print "Rendering (color-name select space 'color) (name) on (encoded-canvas)"	

		unless tail? current-path [						;-- can be at tail on out-of-tree renders
			#debug [check-parent-override space last current-path]
			quietly space/parent: last current-path		;-- should be set before any child render call! so styles can access /parent
		]
		with-style space [
			window?: all [
				any [xy1 xy2]
				in :space/draw /window
				;@@ this should also check if style func supports /window but it's already too much hassle, maybe later
			]
			
			either all [
				not window?								;-- usage of region is not supported by current cache model
				set [words: slot:] cache/fetch space encoded-canvas
			][
				set [children: drawn:] slot
				do-atomic [								;-- prevent reactions from invalidating the cache while it's used by `set`
					#debug profile [prof/manual/start 'deep-restore]
					restore-from-cache space words slot not crude
					#debug profile [prof/manual/end 'deep-restore]
				]
				cache/update-generation space 'cached encoded-canvas
				add-child space encoded-canvas
				#debug cache [							;-- add a frame to cached spaces after committing
					if space/size [
						drawn: compose/only [(drawn) pen green fill-pen off box 0x0 (space/size)]
					]
				]
			][
				; if name = 'list [print ["canvas:" canvas mold space/content]]
				#debug profile [prof/manual/start name]
				style: apply-current-style space
				children-mark: tail children-stack
				
				either block? :style [
					drawn: safe-draw :space/draw none xy1 xy2 canvas fill-x fill-y
					drawn: combine-style :drawn style
				][
					drawn: safe-draw :style space xy1 xy2 canvas fill-x fill-y
					#assert [block? :drawn]
				]
				
				unless any [xy1 xy2] [cache/commit space encoded-canvas to [] children-mark drawn]
				cache/update-generation space 'drawn encoded-canvas
				clear children-mark								;-- forget children of this space
				add-child space encoded-canvas
				
				if select space 'rate [timers/prime space]		;-- render enables timer for this space if /rate facet is set
				
				#debug profile [prof/manual/end name]
				#assert [any [space/size find [grid canvas] name] "render must set the space's size"]	;@@ should grid be allowed to have infinite size?
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
		/on canvas: infxinf [pair! none!] "Specify canvas size as sizing hint"
			fill-x: no [logic!] "Try to fill finite canvas width"
			fill-y: no [logic!] "Try to fill finite canvas height"
		/crude "For spaces only - speed up caching on intermediate canvases"	;-- children may be out of sync!
	][
		drawn: either host? space [
			render-face space
		][
			render-space/window/on/:crude space xy1 xy2 canvas fill-x fill-y
		]
		#debug draw [									;-- test the output to figure out which style has a "Draw error"
			if error? error: try/keep [draw 1x1 drawn] [
				prin "*** Invalid draw block: " probe drawn
				do error
			]
		]
		drawn
	]
]


export exports
