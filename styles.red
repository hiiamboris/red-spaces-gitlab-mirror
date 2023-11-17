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

;; needs: map-each, anonymize, reshape, export, contrast-with

exports: [set-style remove-style define-styles]

styles: make hash! 50

;; used to keep above/below words from leaking out
style-ctx: context [below: above: none]
	
#assert [
	1 = index? in style-ctx 'below						;-- combine-style relies on this, for less allocation
	2 = index? in style-ctx 'above
]

;; reminder: set-style 'a get-style 'b should work without any nasty tricks, binding errors, shared state, etc.
;; `style-ctx` is shared by functions, but gets read before evaluation, so it's fine
set-style: function [
	"Define a named style"
	name [word! path!]
	style [block! function!]
	/unique "Warn about duplicates"
][
	name: to path! name
	either pos: find/only/tail styles name [					;-- `put` does not support paths/blocks so have to reinvent it
		if unique [ERROR "Duplicate style found named `(mold name)`"]
	][
		pos: insert/only tail styles name
	]
	either block? :style [
		;; let it collect set-words, to prevent leakage and bind-related errors caused by words being shared by some object:
		;; also bind above/below words so even if function uses `return`, they are still set
		style: function [/extern above below] bind style style-ctx	;-- function copies the body deeply
	][
		style: func spec-of :style body-of :style
	]
	change pos :style
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
			set-style/:unique name :style
		]
	)]
	parse styles [any [=names= =expr= =commit=]]
]

do with styling: context [
	;@@ TODO: ideally colors & fonts should not be inlined - see REP #105
	unless svm/colors [svm/colors: copy #()]			;@@ MacOS fix for #4740
	unless svmc/text  [svmc/text: black]				;@@ GTK fix for #4740
	unless svmc/panel [svmc/panel: white - svmc/text]	;@@ GTK fix for #4740
	checkered-pen: reshape [							;-- used for focus indication
		pattern 4x4 [
			scale 0.5 0.5 pen off
			; fill-pen !(svmc/panel)  box 0x0  8x8
			fill-pen !(svmc/text) box 1x0 5x1  box 1x5 5x8  box 0x1 1x5  box 5x1  8x5
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
		size [planar!]
		line [linear!]
		pen [word! tuple! block! none!]
		fill-pen [word! tuple! none!]
		/round radius [linear!]
		/margin mrg: (line . line / 2) [planar!]
	][
		reshape-light [
			push [
			/?	pen      @(pen)				/if pen
			/?	fill-pen @(fill-pen)		/if fill-pen
				line-width @(line)
				box @(mrg) @(size - mrg) @(radius)
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
		base: [
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
		caret: [
			; [pen off fill-pen !(contrast-with svmc/panel)]
			below: [pen off fill-pen !(svmc/text)]
		]
		selection: [
			; below: [pen (checkered-pen) fill-pen !(opaque 'text 30%)]
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
		
		grid/cell: function [cell /on canvas fill-x fill-y] [	;-- has no frame since frame is drawn by grid itself
			#assert [canvas]							;-- grid should provide finite canvas
			drawn: cell/draw/on canvas fill-x fill-y
			;; when cell content is not compressible, cell/size may be bigger than canvas, but we draw up to allowed size only
			canvas: min canvas cell/size
			color: any [
				select cell 'color
				if cell/pinned? [mix 'panel opaque 'text 15%]
			]
			bgnd: make-box canvas 0 'off color			;-- always fill canvas, even if cell is constrained
			reduce [bgnd drawn]
		]
		
		grid/cell/paragraph: grid/cell/text: [			;-- make pinned text bold
			;; careless setting causes full tree invalidation on each render, though if style is applied it's already invalid
			set-flag flags 'bold parent/pinned?
		]
		
		list-view/window/list/selection: [
			below: [(make-box size 0 'off (opaque 'text 10%))]
			; below: [(make-box size 0 'off glass)]
		]
		list-view/window/list/cursor: [
			below: when focused?/above 3 [(make-box size 1 checkered-pen 'off)]
		]
		list-view/window/list/item: [
			lview:  parent/parent/parent				;@@ how to simplify this?
			margin: either lview/selectable [(4,2)][(0,0)]	;-- add little margin to draw frame on
		]
		
		;; "☒☐" make lines too big! needs custom draw code, not symbols
		;; this doesn't use /draw at all (what's there to use?)
		;; it also cannot be written in block style, since draw will nullify the size (given text is empty)
		switch: function [self] [						;-- clickable
			cross?: when self/state [line 3x3 13x13 line 13x3 3x13]
			frame:  make-box self/size: (16,16) 1 none none
			reduce [frame cross?]
		]
		logic: [										;-- readonly
			data/font: fonts/text
			maybe data/data: either state ["✓"]["✗"]	;-- maybe still required here because /data: doesn't check for equality
		]
		
		label: [
			if spaces/image-box/content = 'sigil [
				big?: spaces/body/content/2 = 'comment
				spaces/sigil/limits/min: pick [32 20] big? 
				spaces/sigil/font: select fonts pick [sigil-big sigil] big?
			]
			below: when select self 'color [pen (color)]
		]
		label/text-box/body/text:    [font: fonts/label  ]
		label/text-box/body/comment: [font: fonts/comment]

		clickable: data-clickable: [
			below: when select self 'color [(make-box size 0 'off color)]
		]
		button: [
			fill:    either pushed? [opaque 'text 50%][['off]]
			; below: [shadow 2x4 5 0 (green)]				;@@ not working - see #4895; not portable (Windows only)
			overlay: compose [make-box/round size 1 none (fill) rounding]
			focus?:  when focused? (
				inner-radius: max 0 rounding - 2
				compose [make-box/round/margin size 1 checkered-pen 'off (inner-radius) 4x4]
			)
			above:   reduce [as paren! overlay  as paren! focus?]	;-- paren delays evaluation until 'size' is ready (after render)
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

		menu/ring/clickable: [
			below: [(make-box size 1 none color)]
		]
		
		menu/ring/round-clickable: [
			below: [(make-box/round size 1 none color 50)]
		]
		
		hint: function [box] /skip [
			drawn: box/draw								;-- draw to obtain the size
			m: box/margin / 2
			reshape [
				@(make-box/round/margin box/size 1 none none 3 1x1 + m)
				;@@ TODO: arrow can be placed anywhere really, just more math needed
				push [
					matrix [1 0 0 -1 0 @(box/size/y)]	/if o <> 0x0
					shape [move @(m + 4x1) line 0x0 @(m + 1x4)]
				]							/if o: box/origin	;-- no arrow if hint was adjusted by window borders
				!(drawn)
			]
		]
		
		rich-content: /skip [
			below: reshape-light [
			/?	font @(font)		/if font
			/?	pen @(color)		/if color
			]
		]
		rich-content/text: rich-content/paragraph: [	;-- these override font with their own, so [font] draw command isn't enough
			default font: any [parent/font fonts/text]
			below: when select self 'color [pen (color)]
		]
		;@@ scrollbars should prefer host color
		
		slider: function [slider /on canvas fill-x fill-y] [
			drawn: slider/draw/:on canvas fill-x fill-y
			knob:  slider/knob
			right: slider/size - left: half knob/size/x . slider/size/y
			stop:  right - left * slider/offset * 1x0 + left
			compose/deep [
				push [
					line-width 4
					pen (opaque svmc/text 70%) line (left) (stop)
					pen (opaque svmc/text 30%) line (stop) (right)
				]
				(drawn)
			]
		]
		
		slider/knob: /skip [
			fill:  opaque svmc/text either focused?/parent [100%][40%]
			above: reshape-light [line-width 1 fill-pen @(fill) circle (size / 2) (size/x / 2) (size/y / 2)]
		]
		slider/mark: function [mark /on canvas fill-x fill-y] [
			h: second mark/size: 1 . either canvas [canvas/y][1]
			compose [line-width 1 line (0.5, 0) (0.5 . (h * 0.15)) line (0.5 . (h * 0.85)) (0.5 . h)]
		]
	]
]


export exports
