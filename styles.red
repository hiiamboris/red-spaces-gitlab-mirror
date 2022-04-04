Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ needs: map-each, anonymize, reshape, export

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

;; cache format for now: [space-object canvas xy1 xy2 drawn ...]
;@@ once #5116 gets fixed, check if find/same .. #static-reduce [..] is going to be faster
space-cache: make hash! 4096

context [
	find-cache: function [space [object!] canvas [pair! none!] xy1 [pair! none!] xy2 [pair! none!]] [
		cached: space-cache
		while [cached: find/only/same/tail cached space] [		;@@ watch out for #5116 fix, or use for-each
			all [												;@@ also maybe search in reverse?
				cached/1 =? canvas
				cached/2 =? xy1
				cached/3 =? xy2
				return back cached
			]
		]
		none
	]
	
	get-cache: function [space [object!] canvas [pair! none!] xy1 [pair! none!] xy2 [pair! none!]] [
		all [
			true =? select space 'cache?
			space/size
			cached: find-cache space canvas xy1 xy2
			cached/5
		]
	]
	
	;@@ TODO: limit number of caches per single space somehow, e.g. for list which has limitless xy1/xy2 combos!
	set-cache: function [space [object!] canvas [pair! none!] xy1 [pair! none!] xy2 [pair! none!] drawn [block!]] [
		either cached: find-cache space canvas xy1 xy2 [
			cached/5: drawn
		][
			repend space-cache [space canvas xy1 xy2 drawn]
		]
	]
	
	clear-cache: function [space [object!]] [
		while [pos: find/same/only space-cache space] [
			other: skip tail space-cache -5
			unless pos =? other [change pos other]
			clear other
		]
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
		any [render copy []]
	]

	render-space: function [
		name [word!] "Space name pointing to it's object"
		/only xy1 [pair! none!] xy2 [pair! none!]
		/on canvas [pair! none!]
	][
		space: get name
		#assert [space? :space]
		#assert [not is-face? :space]					;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face

		with-style name [
			unless render: get-cache space canvas xy1 xy2 [
				#debug profile [prof/manual/start name]
				style: get-style							;-- call it before calling draw or draw/only, in case it modifies smth
				either block? :style [
					style: compose/deep bind style space	;@@ how slow this bind will be? any way not to bind? maybe construct a func?
					draw: select space 'draw
					
					;@@ this basically cries for FAST `apply` func!!
					if all [function? :draw  any [xy1 xy2 canvas]] [
						spec: spec-of :draw
						either find spec /only [only: any [xy1 xy2]][set [xy1: xy2: only:] none]
						unless find spec /on   [on: canvas: none]
						if canvas [constrain canvas: canvas space/limits]
						code: case [						;@@ workaround for #4854 - remove me!!
							all [canvas only] [[draw/only/on xy1 xy2 canvas]]
							only              [[draw/only    xy1 xy2       ]]
							canvas            [[draw/on              canvas]]
						]
						draw: either code [do copy/deep code][draw]
					]
					draw: draw								;-- call the draw function if not called yet
					#assert [block? :draw]
					
					if empty? style [unset 'style]
					render: compose/only [(:style) (:draw)]	;-- compose removes style if it's unset
				][
					#assert [function? :style]
					;@@ this basically cries for FAST `apply` func!!
					either any [xy1 xy2 canvas] [
						spec: spec-of :style
						either find spec /only [only: any [xy1 xy2]][set [xy1: xy2: only:] none]
						unless find spec /on   [on: canvas: none]
						if canvas [constrain canvas: canvas space/limits]
						code: case [					
							all [canvas only] [[style/only/on space xy1 xy2 canvas]]
							only              [[style/only    space xy1 xy2       ]]
							canvas            [[style/on      space         canvas]]
						]
						render: either code [do copy/deep code][style space]	;@@ workaround for #4854 - remove me!!
					][
						render: style space
					]
					#assert [block? :render]
				]
				if cache?: select space 'cache? [
					if cache? = 'invalid [clear-cache space]	;-- clear all the other renders on invalidation
					set-cache space canvas xy1 xy2 render
					space/cache?: true							;-- mark cache as valid until invalidated
				]
				#debug profile [prof/manual/end name]
				#assert [space/size "render must set the space's size"]
			]
		]
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