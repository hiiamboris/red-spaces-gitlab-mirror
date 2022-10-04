Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		REMINDER: should be careful when assigning facets in styles
		If facet has no equality test (sometimes by design) but invalidates, `maybe` should be used
		otherwise on each space's render all upper tree will be invalidated and no caching will work
		;@@ TODO: detect such cases automatically and report
	}
]

;; needs: map-each, anonymize, reshape, export, contrast-with, apply

exports: [set-style remove-style define-styles]

styles: make hash! 50

;; used to keep above/below words from leaking out
style-ctx!: context [above: below: none]
	
set-style: function [
	"Define a named style"
	name [word! path!]
	style [block! function!]
	/unique "Warn about duplicates"
][
	name: to path! name
	either pos: find/only/tail styles name [		;-- `put` does not support paths/blocks so have to reinvent it
		if unique [ERROR "Duplicate style found named `(mold name)`"]
	][
		pos: insert/only tail styles name
	]
	style: either block? :style [
		bind copy/deep style copy style-ctx!
	][
		func spec-of :style copy/deep body-of :style	;@@ copy/deep to work around #4854
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

define-styles: function [
	"Define one or multiple styles using Styling dialect"
	styles [block!] "Stylesheet"
	/unique "Warn about duplicates"
	/local style
][
	=style-name=: [set-word! | set-path!]
	=names=:  [not end ahead #expect =style-name= copy names some =style-name=]
	=expr=:   [p: (set/any 'style do/next p 'p) :p]
	=commit=: [(
		foreach name names [
			if set-word? name [name: to word! name]		;-- to path! set-word keeps the colon
			name: to path! name
			apply set-style 'local
		]
	)]
	parse styles [any [=names= =expr= =commit=]]
]

do with [
	;@@ TODO: ideally colors & fonts should not be inlined - see REP #105
	svm: system/view/metrics
	unless svm/colors [svm/colors: copy #()]			;@@ MacOS fix for #4740
	svmc: system/view/metrics/colors
	unless svmc/text  [svmc/text: black]				;@@ GTK fix for #4740
	unless svmc/panel [svmc/panel: white - svmc/text]	;@@ GTK fix for #4740
	svf:  system/view/fonts
	checkered-pen: reshape [							;-- used for focus indication
		pattern 4x4 [
			scale 0.5 0.5 pen off
			fill-pen !(svmc/text)  box 0x0  8x8
			fill-pen !(svmc/panel) box 1x0 5x1  box 1x5 5x8  box 0x1 1x5  box 5x1  8x5
		]
	]
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
	
	make-box: function [
		size [pair!]
		line [integer!]
		pen [word! tuple! block! none!]
		fill-pen [word! tuple! none!]
		/round radius [integer!]
		/margin mrg [pair!]
	][
		mrg:    any [mrg (system/words/round/ceiling/to 1x1 * line 2) / 2]
		pen?:   when pen      (compose [pen      (pen)     ])
		fill?:  when fill-pen (compose [fill-pen (fill-pen)])
		compose/deep [
			push [
				(pen?) (fill?)
				line-width (line)
				box (mrg) (size - mrg) (only radius)
			]
		]
	]
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

	;@@ TODO: organize this internally as a map of nested words-blocks
	define-styles/unique reshape [
		host: [
			below: [
				fill-pen !(svmc/panel)
				font     !(fonts/text)
				line-width 2
				pen      !(svmc/text)
			]
		]

		text: paragraph: link: fps-meter: [
			default font: fonts/text
			; #if linux? [(font: serif-12 ())]	;@@ GTK fix for #4901
			below: when select self 'color [pen (color)]
		]

		field: [
			margin: 3x3									;-- better default when having a frame (and frame comes from style, not template)
			below: [(make-box size 1 select self 'color none)]
		]
		field/caret: [
			; [pen off fill-pen !(contrast-with svmc/panel)]
			below: [pen off fill-pen !(svmc/text)]
		]
		field/selection: [
			below: [pen off fill-pen !(opaque 'text 30%)]
			;@@ workaround for #5133 needed by workaround for #4901: clipping makes fill-pen black
			#if linux? [
				below: [pen !(svmc/text) fill-pen off line-width 1 box 1x1 (size - 2)]
			]
		]
		
		tube: list: box: [									;-- allow color override for containers
			below: when select self 'color [
				; (#assert [size])
				(make-box size 0 'off color)
			]
		]
		
		;; cell is a box with a border around it; while general box is widely used in borderless state
		menu/list: cell: [
			below: [(make-box size 1 none select self 'color)]	;@@ add frame (pair) field and use here?
		]
		
		grid/cell: function [cell /on canvas] [			;-- has no frame since frame is drawn by grid itself
			#assert [canvas]							;-- grid should provide finite canvas
			drawn: cell/draw/on canvas
			;; when cell content is not compressible, cell/size may be bigger than canvas, but we draw up to allowed size only
			canvas: min abs canvas cell/size
			color: any [
				select cell 'color
				if grid-ctx/pinned? [mix 'panel opaque 'text 15%]
			]
			bgnd: make-box canvas 0 'off color			;-- always fill canvas, even if cell is constrained
			reduce [bgnd drawn]
		]
		
		grid/cell/paragraph: grid/cell/text: [			;-- make pinned text bold
			;; careless setting causes full tree invalidation on each render, though if style is applied it's already invalid
			set-flag flags 'bold grid-ctx/pinned?
		]
		
		
		; list/item [[pen cyan]]
		
		;; "☒☐" make lines too big! needs custom draw code, not symbols
		;; this doesn't use /draw at all (what's there to use?)
		;; it also cannot be written in block style, since draw will nullify the size (given text is empty)
		switch: function [self] [						;-- clickable
			cross?: when self/state [line 3x3 13x13 line 13x3 3x13]
			frame:  make-box self/size: 16x16 1 none none
			reduce [frame cross?]
		]
		logic: [										;-- readonly
			data/font: fonts/text
			maybe data/data: either state ["✓"]["✗"]	;-- maybe still required here because /data: doesn't check for equality
		]
		
		label: using [big?] [
			if spaces/image-box/content = 'sigil [
				big?: spaces/body/content/2 = 'comment
				spaces/sigil/limits/min: pick [32 20] big? 
				spaces/sigil/font: select fonts pick [sigil-big sigil] big?
			]
			below: when select self 'color [pen (color)]
		]
		label/text-box/body/text:    [font: fonts/label  ]
		label/text-box/body/comment: [font: fonts/comment]

		button: using [fill overlay focus? inner-radius] [
			fill:    either pushed? [opaque 'text 50%]['off]
			; below: [shadow 2x4 5 0 (green)]				;@@ not working - see #4895; not portable (Windows only)
			overlay: [make-box/round size 1 none fill rounding]	;-- delay evaluation until 'size' is ready (after render)
			focus?:  when focused? (
				inner-radius: max 0 rounding - 2
				[make-box/round/margin size 1 checkered-pen 'off inner-radius 4x4]
			)
			above: [(do overlay) (do focus?)]
		]
		
		hscroll/thumb: vscroll/thumb: [
			above: when focused?/above 2 (
				make-box/margin size 1 checkered-pen none 4x3
			)
		]

		grid-view/window: [
			; #assert [size]
			below: [(make-box size 0 'off !(opaque 'text 50%))]
		]

		menu/list/clickable: [
			below: when self =? :highlight [
				(make-box size 0 'off !(opaque 'text 15%))
				pen !(enhance 'panel 'text 125%)
			]
		]
		
		menu/ring/clickable: [
			below: [(make-box size 1 none none)]
		]
		
		menu/ring/round-clickable: [
			below: [(make-box/round size 1 none none 50)]
		]
		
		hint: function [box] [
			drawn: box/draw								;-- draw to obtain the size
			m: box/margin / 2
			matrix: arrow: []							;-- no arrow if hint was adjusted by window borders
			if o: box/origin [
				;@@ TODO: arrow can be placed anywhere really, just more math needed
				if o <> 0x0 [matrix: compose/deep [matrix [1 0 0 -1 0 (box/size/y)]]]
				arrow: compose/deep [shape [move (m + 4x1) line 0x0 (m + 1x4)]] 
			]
			compose/only/deep [
				(make-box/round/margin box/size 1 none none 3 1x1 + m)
				push [(matrix) (arrow)]
				(wrap drawn)
			]
		]
		
		;@@ scrollbars should prefer host color
	]
]


export exports
