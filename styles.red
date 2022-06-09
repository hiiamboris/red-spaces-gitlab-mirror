Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;; needs: map-each, anonymize, reshape, export, contrast-with


styles: none											;-- reserve names in the spaces/ctx context
exports: [set-style remove-style]

set-style: function [
	"Define a named style"
	name [word! path!]
	style [block! function!]
][
	name: to path! name
	pos: any [											;-- `put` does not support paths/blocks so have to reinvent it
		find/only/tail styles name
		insert/only tail styles name
	]
	change/only pos :style
	:style
]

remove-style: function [
	"Forget a named style"
	name [word! path!]
][
	name: to path! name
	remove/part find/only styles name 2
]

do with [
	;@@ TODO: ideally colors & fonts should not be inlined - see REP #105
	svm: system/view/metrics
	unless svm/colors [svm/colors: copy #()]			;@@ MacOS fix for #4740
	svmc: system/view/metrics/colors
	unless svmc/text [svmc/text: black]					;@@ GTK fix for #4740
	unless svmc/panel [svmc/panel: white - svmc/text]	;@@ GTK fix for #4740
	svf:  system/view/fonts
	; serif-12: make font! [name: svf/serif size: 12 color: svmc/text]	;@@ GTK fix for #4901

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
		'code      make font! [name: svf/fixed  size: svf/size]
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
			font !(fonts/text)
			line-width 2
			pen !(svmc/text)
		]

		text paragraph link fps-meter [
			(when select self 'color [compose [pen (color)]])
			(maybe/same font: fonts/text ())					;@@ hate this syntax! find a better one
			; #if system/platform = 'Linux [(font: serif-12 ())]	;@@ GTK fix for #4901
		]

		field [
			(when select self 'color [compose [pen (color)]])
			(maybe/same font: fonts/text ())
		]
		field/caret [
			; pen off fill-pen !(contrast-with svmc/panel)
			pen off fill-pen !(svmc/text)
		]
		field/selection [
			pen off fill-pen !(svmc/text + 0.0.0.200)
		]
		
		tube list box [									;-- allow color override for containers
			function [space /only xy1 xy2 /on canvas] [
				drawn: either find spec-of :space/draw /only [	;-- draw to get the size
					space/draw/on/only canvas xy1 xy2			;@@ this needs apply
				][	space/draw/on      canvas
				]
				unless color: select space 'color [return drawn]
				compose/deep/only [push [pen off fill-pen (color) box 0x0 (space/size)] (drawn)]
			]
		]
		
		;; cell is a box with a border around it; while general box is widely used in borderless state
		menu/list cell [
			function [cell /on canvas] [
				drawn: do copy/deep [cell/draw/on canvas]		;-- draw to get the size ;@@ #4854 workaround - remove me
				color: select cell 'color
				bgnd: compose/deep [
					push [
						(when color [compose [fill-pen (color)]])
						line-width 1
						box 1x1 (cell/size - 1x1)		;@@ add frame (pair) field and use here?
					]
				]
				compose/only [(bgnd) (drawn)]
			]
		]
		
		grid/cell [										;-- has no frame since frame is drawn by grid itself
			function [cell /on canvas] [
				drawn: cell/draw/on canvas
				;; when cell content is not compressible, cell/size may be bigger than canvas
				if canvas [canvas: min canvas cell/size]
				color: any [
					select cell 'color
					if grid-ctx/pinned? [mix svmc/panel svmc/text + 0.0.0.220]
				]
				bgnd: compose/deep [
					push [
						pen off
						(when color [compose [fill-pen (color)]])
						box 0x0 (canvas)
					]
				]
				compose/only [(bgnd) (drawn)]
			]
		]
		
		grid/cell/paragraph grid/cell/text [			;-- make pinned text bold
			function [text /on canvas] [
				maybe text/flags: either grid-ctx/pinned?
					[union   text/flags [bold]]
					[exclude text/flags [bold]]
				text/draw/on canvas
			]
		]
		
		
		; list/item [[pen cyan]]
		
		;; ☒☐ make lines too big! needs custom draw code, not symbols
		switch [										;-- clickable
			function [space] [
				space/size: 16x16
				compose [
					line-width 1
					box 1x1 (space/size - 1)
					(when space/state [[line 3x3 13x13 line 13x3 3x13]])
				]
			]
		]
		logic  [(										;-- readonly
			maybe/same data/font: fonts/text
			maybe data/data: either state ["✓"]["✗"]
			()
		)]
		
		label [(
			if spaces/image-box/content = 'sigil [
				spaces/sigil/font: either (spaces/body/content/2) = 'comment [
					spaces/sigil/limits/min: 32
					fonts/sigil-big
				][
					spaces/sigil/limits/min: 20
					fonts/sigil
				] 
			]
			when select self 'color [compose [pen (color)]]
		)]
		label/text-box/body/text    [(font: fonts/label ())]
		label/text-box/body/comment [(font: fonts/comment ())]

		button [
			function [btn /on canvas] [
				drawn: btn/draw/on canvas
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

		menu/list/clickable [(
			when self =? :highlight [
				compose/deep [push [
					pen off
					fill-pen !(svmc/text + 0.0.0.220)
					box 0x0 (size)						;@@ render to get size?
				] pen !(enhance svmc/panel svmc/text 125%)]
			]
		)]
		
		menu/ring/clickable [
			function [space] [
				drawn: space/draw
				compose/deep/only [box 0x0 (space/size) (drawn)]
			]
		]
		
		menu/ring/round-clickable [
			function [space] [
				drawn: space/draw
				compose/deep/only [box 0x0 (space/size) 50 (drawn)]
			]
		]
		
		hint [
			function [box] [
				drawn: box/draw							;-- draw to obtain the size
				m: box/margin / 2
				matrix: arrow: []						;-- no arrow if hint was adjusted by window borders
				if o: box/origin [
					;@@ TODO: arrow can be placed anywhere really, just more math needed
					if o <> 0x0 [matrix: compose/deep [matrix [1 0 0 -1 0 (box/size/y)]]]
					arrow: compose/deep [shape [move (m + 4x1) line 0x0 (m + 1x4)]] 
				]
				compose/only/deep [
					push [
						line-width 1
						box (1x1 + m) (box/size - 1 - m) 3
						(matrix) (arrow)
					]
					(drawn)
				]
			]
		]
		
		;@@ scrollbars should prefer host color
		;@@ as stylesheet grows, need to automatically check for dupes and report!
	]
	

	map-each/only/self [w [word! ]] styles [to path! w]	;-- replace words with paths
	do with [paths: block: none] [						;-- separate grouped styles
		mapparse [copy paths some path! set block block!] styles [
			map-each/eval path paths [[path copy/deep block]]	;@@ copy/deep works around #4854
		] 
	]
	map-each/only/self [b [block!]] styles [			;-- extract blocks, construct functions
		either 'function = first b [do b][b]
	]

]


export exports
