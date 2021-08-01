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
		host [[
			pen off
			fill-pen !(svmc/panel)
			font !(make font! [name: svf/system size: svf/size])
			line-width 2
			box 0x0 (size)		;-- makes host background opaque otherwise it loses mouse clicks on most of it's part
			pen !(svmc/text)
		]]

		#if system/platform = 'Linux [			;@@ GTK fix for #4901
			paragraph [[
				;-- font can be set in the style!:
				;-- but impossible to debug it, as probe draw lists font with thousands of parents
				(self/font: serif-12 ())			;@@ #3804 - requires self/ or won't work
				; pen blue
			]]
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

		cell [[
			fill-pen !(svmc/panel)
			box 0x0 (size)
			pen      !(svmc/text)			;-- restore pen after `pen off` in grid
		]]
	]
	

	map-each/only/self [w [word! ]] styles [to path! w]	;-- replace words with paths
	map-each/only/self [b [block!]] styles [do b]		;-- extract blocks, construct functions

]


style-typeset!: make typeset! [block! function!]	;@@ hide this

;@@ TODO: profile & optimize this a lot
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

set-style: function [name [word! path!] style [block!]] [
	name: to path! name
	pos: any [											;-- `put` does not support paths/blocks so have to reinvent it
		find/only/tail styles name
		insert/only tail styles name
	]
	change/only pos style
]

context [
	;-- draw code has to be evaluated after current-style changes, for inner calls to render to succeed
	with-style: function [
		"Draw calls should be wrapped with this to apply styles properly"
		name [word!] code [block!]
	][
		append current-style name
		trap/all/catch code [
			msg: form/part thrown 1000						;@@ should be formed immediately - see #4538
			#print "^/*** Failed to render (name)!^/(msg)"
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
			space-drawn: render-space/only face/space xy1 xy2
			render: reduce [host-drawn space-drawn]
		]
		any [render copy []]
	]

	render-space: function [
		name [word!] "Space name pointing to it's object"
		/only xy1 [pair! none!] xy2 [pair! none!]
	][
		space: get name
		#assert [space? :space]
		#assert [not is-face? :space]					;-- catch the bug of `render 'face` ;@@ TODO: maybe dispatch 'face to face

		with-style name [
			style: get-style							;-- call it before calling draw or draw/only, in case it modifies smth
			either block? :style [
				style: compose/deep bind style space	;@@ how slow this bind will be? any way not to bind? maybe construct a func?
				draw: select space 'draw
				all [
					only
					function? :draw
					find spec-of :draw /only
					do copy/deep [draw: draw/only xy1 xy2]	;@@ workaround for #4854 - remove me!!
					; draw: draw/only xy1 xy2
				]
				if empty? style [unset 'style]
				render: compose/only [(:style) (draw)]	;-- call the draw function if not called yet; compose removes `unset`
			][
				#assert [function? :style]
				render: either all [
					only
					find spec-of :style /only
				][
					do copy/deep [style/only space xy1 xy2]	;@@ workaround for #4854 - remove me!!
					; draw: draw/only xy1 xy2
				][
					style space
				]
			]
		]
		either render [
			reduce ['push render]						;-- don't carry styles over to next spaces
		][
			copy []
		]
	]

	set 'render function [
		"Return Draw code to draw a space or host face, after applying styles"
		space [word! object!] "Space name, or host face as object"
		/only "Limit rendering area to [XY1,XY2] if space supports it"
			xy1 [pair! none!] xy2 [pair! none!]
	][
		render: either word? space [:render-space][:render-face]
		do copy/deep [									;@@ workaround for #4854 - remove me!!
			render/only space xy1 xy2
		]
	]
]

export exports