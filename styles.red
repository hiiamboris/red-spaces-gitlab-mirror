Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ needs: map-each, anonymize, reshape, export, contrast-with


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
	;@@ fill this with some more ;@@ should it be part of system/view/metrics/fonts?
	fonts: make map! reduce [
		'text      make font! [name: svf/system size: svf/size]
		'label     make font! [name: svf/system size: svf/size + 1]
		'switch    make font! [name: svf/system size: svf/size + 6]
		'sigil     make font! [name: svf/system size: svf/size + 1]
		'sigil-big make font! [name: svf/system size: svf/size + 8]
		'comment   make font! [name: svf/system size: svf/size]
	]

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
			;; makes host background opaque otherwise it loses mouse clicks on most of it's part:
			;; (except for some popups that must be partially transparent)
			(compose/deep either space = 'ring-menu [
				[push [
					fill-pen !(svmc/panel + 0.0.0.254)
					box 0x0 (any [size 0x0])
				]]
			][
				[box 0x0 (any [size 0x0])]
			])
			pen !(svmc/text)
		]

		#if system/platform = 'Linux [					;@@ GTK fix for #4901
			text paragraph fps-meter [
				;-- font can be set in the style!:
				;-- but impossible to debug it, as probe draw lists font with thousands of parents
				(font: serif-12 ())
				; pen blue
			]
		]
		
		url [
			function [url /on canvas] [
				drawn: url/draw/on canvas				;-- must create /layout which can otherwise be none
				url/layout/data: reduce [1 by length? url/text  'underline]
				compose/only [pen blue (drawn)]			;@@ color should be taken from the OS theme
			]
		]

		; list/item [[pen cyan]]
		
		switch [(data/font: fonts/switch data/data: either state ["☒"]["☐"] ())]	;-- clickable
		logic  [(data/font: fonts/switch data/data: either state ["✓"]["✗"] ())]	;-- readonly
		
		label [(
			if spaces/image-box/content = 'sigil [
				spaces/sigil/font: either (spaces/body/item-list/2) = 'comment [
					spaces/sigil/limits/min: 32
					fonts/sigil-big
				][
					spaces/sigil/limits/min: 20
					fonts/sigil
				] 
			] ()
		)]
		label/text-box/body/text    [(font: fonts/label ())]
		label/text-box/body/comment [(font: fonts/comment ())]

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
					push (drawn)
					fill-pen (bgnd)
					box 1x1 (btn/size - 1) (btn/rounding)
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

		;; cell is a box with a border around it; while general box is widely used in borderless state
		menu cell [
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
		
		menu/list/clickable [(
			when self =? :highlight [
				compose/deep [push [
					pen off
					fill-pen !(svmc/text + 0.0.0.220)
					box 0x0 (size)						;@@ render to get size?
				] pen !(enhance svmc/panel svmc/text 125%)]
			]
		)]
		
		ring-menu/ring/round-clickable [
			function [space] [
				drawn: space/draw
				compose/deep/only [
					box 0x0 (space/size) 50
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