Red [
	title:   "Glossy stylesheet demo"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		These styles are purely vector-based and simple.
		Which also limits them, as gradient options in Draw aren't enough to draw complex shaders.
		E.g. I've no idea how to create the shape of a rectangular button's sheen, except going pixel by pixel.
		Using images would allow for far more expressive freedom here, at the cost of having a resource bundle and fixed sizes.
		
		USAGE: #include this file after %everything.red 
	}
]
#include %../../common/setters.red							;-- required to import `quietly` which is otherwise not imported
#include %../../common/step.red
; #include %../everything.red

context with spaces/ctx [

	;; helpful shades used in style composition
	
	w0: white + 0.0.0.255
	w1: white + 0.0.0.192
	w2: white + 0.0.0.128
	w3: white + 0.0.0.64
	w4: white
	
	op: 0.0.0.200
	s0: black + op
	s1: white / 4 + op
	s2: white / 2 + op
	s3: white / 4 * 3 + op
	s4: white + op
			
	; screen: system/view/screens/1
	
	
	
	;; functions to draw shiny shapes
	
	draw-frame: function [
		"Draw a glossy frame"
		size     [pair!]
		rounding [integer!] "Corner rounding radius"
		bgnd     [tuple!]   "Background color"
	][
		compose/deep [
			pen off fill-pen radial (bgnd) 0.0 (opaque bgnd 50%) 1.0
			box 2x2 (size - 2) (rounding)
			
			line-width 1 fill-pen off
			pen s4
			box 2x1 (size - 2x3) (rounding)
			box 1x2 (size - 3x2) (rounding)
			pen s0
			box 3x2 (size - 1x2) (rounding)
			box 2x3 (size - 2x1) (rounding)
			pen w1
			box 2x2 (size - 2)   (rounding)
			; box 2x2 (size - 3) (rounding)
			
			; line-width 1 fill-pen off
			; pen s4
			; box 2x1 (size - 3x4) (rounding)
			; box 1x2 (size - 4x3) (rounding)
			; pen s0
			; box 3x2 (size - 2x3) (rounding)
			; box 2x3 (size - 3x2) (rounding)
			; pen w1
			; box 2x2 (size - 3)   (rounding)
		]
	]
	
	draw-sheen: function [
		"Draw a bumpy sheen"
		size     [pair!]
		rounding [integer!]        "Corner rounding radius"
		sheen    [percent! float!] "How pronounced is the sheen, 0-100%"
	][
		edge: max size/x size/y
		base: 100% - sheen
		tints: map-each/eval i 5 [[
			0.0.0.255 * (base + (i - 1 / 4 * sheen)) + white
			i - 1.0 / 4 ** 2
		]]
		compose/deep [
			pen off
			fill-pen radial (tints) (1x1 * edge / 2) (to integer! 1.3 * edge / 2) (size / 4 - (1x1 * edge / 2))
			box 0x0 (size - 1) (rounding)
		]
	]
	
	draw-text: function [
		"Draw shiny text"
		space  [object!]
		canvas [pair! none!]
		text   [string! url!]
		font   [object! none!]
		bgnd   [tuple!]
		color  [tuple!]
	][
		shade:  opaque black 75%
		blur:   opaque color 20%
		blur2:  opaque color 10%
		drawn: space/draw/on canvas no no
		if empty? text [return []]						;-- optimization
		layout: space/layout							;-- set by draw
		if override: select space 'color [color: override]
		compose/deep/only [
			translate (space/margin) [
				pen (shade)								;-- outline to make text more legible on gray bgnd
				text  1x0 (layout) text 0x1  (layout)
				text -1x0 (layout) text 0x-1 (layout)
				pen (blur)
				text  1x0 (layout) text 0x1  (layout)
				text -1x0 (layout) text 0x-1 (layout)
				pen (blur2)
				text -3x0 (layout) text 3x0 (layout)
				text -2x0 (layout) text 2x0 (layout)
				pen (color) text 0x0 (layout)
			]
			(drawn)
		]
	]

	draw-text-box: function [
		"Draw shiny centered text"
		canvas [pair! none!]
		text   [string!]
		font   [object! none!]
		bgnd   [tuple!]
		color  [tuple!]
	][
		if empty? text [return []]							;-- optimization
		rt: new-rich-text
		quietly rt/font: font
		quietly rt/text: text
		quietly rt/size: canvas
		text-size: size-text rt
		text-ofs:  either canvas [canvas - text-size / 2][0x0]
		compose/deep [
			pen  s4 text (text-ofs + 1x0) (rt)
			pen  s0 text (text-ofs - 1x1) (rt)
			pen  (bgnd + 0.0.0.100)
			text (text-ofs) (rt)							;-- in case text color is transparent, draw embossed background first
			pen  (color)
			text (text-ofs) (rt)
		]
	]
	
	draw-glossy-box: function [
		"Draw an empty glossy rounded box"
		size     [pair!]
		bgnd     [tuple!]
		rounding [integer!]
		sheen    [percent!]
	][
		compose/deep [
			(draw-frame size rounding bgnd) 
			(draw-sheen size rounding sheen)
		]
	]
	
	draw-glossy-text-box: function [
		"Draw a glossy rounded box with text"
		size     [pair!]
		text     [string!]
		font     [object! none!]
		bgnd     [tuple!]
		color    [tuple!]
		rounding [integer!]
		sheen    [percent!]
	][
		compose/deep [
			(draw-frame     size rounding bgnd) 
			(draw-sheen     size rounding 80% * sheen)
			(draw-text-box  size text font bgnd color) 
			(draw-sheen     size rounding 70% * sheen)			;-- will affect text too 
		]
	]
	
	
	
	;; the stylesheet

	svf: system/view/fonts
	; system-font: make font! [name: svf/system size: 30]
	system-font: make font! [name: svf/system style: 'bold]		;-- uses bold font by default
	
	bgnd-image: load %glossy-bgnd.jpg
	define-styles [
		base: [
			below: [
				(when not find [hint menu radial-menu] space/type (compose [image (bgnd-image) 0x0 (size)]))
				fill-pen off
				font (system-font)
				pen  (silver)
				line-width 1
			]
		]
		label/text-box/body/text: label/text-box/body/comment:
		text: paragraph: link: function [self /on canvas fill-x fill-y] [
			default self/font: system-font
			draw-text self canvas self/text self/font glass silver	;-- sets the size in draw-text/draw
		]
		grid/cell/text: grid/cell/paragraph: function [self /on canvas fill-x fill-y] [
			default self/font: system-font
			draw-text self canvas self/text self/font glass			;-- sets the size in draw-text/draw
				either self/parent/pinned? [linen][silver]
		]
		cell: function [self /on canvas fill-x fill-y] [
			drawn: self/draw/on canvas fill-x fill-y
			frame: draw-frame self/size 5 any [select self 'color glass]
			reduce [frame drawn]
		]
		grid/cell: function [self /on canvas fill-x fill-y] [
			drawn: self/draw/on canvas fill-x fill-y
			bgnd: compose [
				pen off fill-pen (either self/pinned? [w1][s0])
				box 0x0 (min canvas self/size) 5
			]
			reduce [bgnd drawn]
		]
		button: function [self /on canvas fill-x fill-y] [		;-- ignores result of native /draw, draws own text
			default self/font: system-font
			self/margin: 15x8
			self/rounding: 20
			self/draw/on canvas fill-x fill-y			;-- only to obtain the size
			color: any [select self 'color black]
			bgnd: either self/pushed? [opaque #fc6 100%][glass]
			draw-glossy-text-box self/size self/data self/font bgnd color self/rounding 100%
		]
		vscroll: hscroll: function [self] [
			quietly self/arrow-size: 0%					;-- disable arrows, for fun and to avoid drawing triangles
			maybe self/size/(ortho self/axis): 20
			self/draw
			reverse?: either self/axis = 'x [:do][:reverse]
			thumb-geom: select/same self/map self/thumb
			compose/deep/only [
				translate (reverse? 0x4) [
					(draw-frame self/size 10 glass)
					translate (reverse? thumb-geom/offset)
						(draw-glossy-box reverse? self/thumb/size glass 10 100%) 
				]
			]
		] 
		grid-view/window: []
		scrollable: list-view: grid-view: function [self /on canvas fill-x fill-y] [
			;; scrollables do not directly support margin, so I'm reducing their canvas instead
			pad: 10
			inner: subtract-canvas canvas pad * 2x2
			drawn: self/draw/on inner fill-x fill-y
			shift: pad * 1x1
			foreach [_ geom] self/map [geom/offset: geom/offset + shift]
			if hscroll-geom: select/same self/map self/hscroll [step/by 'hscroll-geom/offset 0x4]
			if vscroll-geom: select/same self/map self/vscroll [step/by 'vscroll-geom/offset 4x0]
			quietly self/size: self/size + (pad * 2)
			reduce [
				draw-frame self/size pad * 2 opaque black 50%
				'translate shift drawn
			]
		]
		switch: function [self] [
			maybe self/size: 20x20
			color: either self/state [yello][glass]
			draw-glossy-box 20x20 color 10 100%
		]
		field: function [self /on canvas fill-x fill-y] [
			maybe self/margin: mrg: 6x5
			drawn: self/draw/on canvas fill-x fill-y
			compose/deep/only [
				; push [clip 0x0 (self/size) fill-pen off pen green box 0x0 (self/size)] 
				(draw-frame self/size 5 glass)
				translate 0x-1 (drawn)
			]
		]
		;; size of caret & selection are set by field/draw
		field/text/caret: function [self] [
			maybe self/width: 1
			compose/deep [
				shape [
					pen w1 fill-pen w3
					move -3x0 'line 3x4 3x-4
					move (self/size/y * 0x1 + -3x-1) 'line 3x-4 3x4
				]
			]
		]
		field/text/selection: function [self] [
			compose [
				fill-pen linear w1 w2 0x0 2x4 reflect
				pen off box 0x0 (self/size) 5
			]
		]
	]

]
