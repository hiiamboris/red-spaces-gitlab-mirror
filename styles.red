Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ needs: map-each, anonymize, reshape, export


styles: none											;-- reserve names in the spaces/ctx context
exports: [set-style]

set-style: function [name [word! path!] style [block! function!]] [
	name: to path! name
	pos: any [											;-- `put` does not support paths/blocks so have to reinvent it
		find/only/tail styles name
		insert/only tail styles name
	]
	change/only pos :style
]

do with [
	;@@ TODO: ideally colors & fonts should not be inlined - see REP #105
	svm: system/view/metrics
	unless svm/colors [svm/colors: copy #()]			;@@ MacOS fix for #4740
	svmc: system/view/metrics/colors
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
				bgnd: compose/deep [
					push [
						fill-pen !(svmc/text + 0.0.0.120)
						pen off
						box 0x0 (window/size)
					]
				]
				compose [(bgnd) (drawn)]
			]
		]

		cell [
			function [cell /on canvas] [
				drawn: cell/draw/on canvas				;-- draw to obtain the size
				compose/only/deep [
					push [
						line-width 1
						fill-pen !(svmc/panel)
						box 1x1 (cell/size - 1x1)		;@@ add frame (pair) field and use here?
					]
					(drawn)
				]
			]
		]
		
		;@@ for this name to work, layout should prefer 'hint' keyword over 'hint' template
		hint [
			function [cell] [
				drawn: cell/draw						;-- draw to obtain the size
				compose/only/deep [
					push [
						line-width 1
						fill-pen !(svmc/panel)
						box 1x1 (cell/size - 1x1) 3
					]
					(drawn)
				]
			]
		]
		
		; grid/cell [
			; function [cell /on canvas] [
				; drawn: cell/draw/on canvas				;-- draw to obtain the size ;@@ TODO
				; drawn: cell/draw						;-- draw to obtain the size
				; compose/only/deep [
					; push [
						; line-width 1
						; fill-pen !(svmc/panel)
						; box 1x1 (cell/size - 1x1)		;@@ add frame (pair) field and use here?
					; ]
					; (drawn)
				; ]
			; ]
		; ]
	]
	

	map-each/only/self [w [word! ]] styles [to path! w]	;-- replace words with paths
	map-each/only/self [b [block!]] styles [			;-- extract blocks, construct functions
		either 'function = first b [do b][b]
	]

]


export exports