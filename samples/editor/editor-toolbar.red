Red [
	title:   "Document demo toolbar template"
	author:  @hiiamboris
	license: BSD-3
]

do/expand with spaces/ctx [

;; helper function to draw some icons for alignment & list toggling
;@@ perhaps I should replace it with the result (draw block)?
bands: none
context [
	tiny-font: make font! [size: 6 style: 'bold name: system/view/fonts/sans-serif]
	set 'bands function [size [pair!] widths [block!] /named texts [block! string!]] [
		thickness: 4
		n:         half length? widths
		step:      size/y - thickness / (n - 1)
		if string? texts [
			markers: map-each [/i t] texts [
				compose [text (0 by (i - 1 * step - 6)) (form t)]
			]
		]
		if block? texts [
			markers: map-each i n [
				compose/deep/only [push [translate (0 by (i - 1 * step)) (texts)]]
			]
		]
		lines: map-each [/i x1 x2] widths [
			compose [
				move (size/x * x1 by (i - 1 * step))
				'hline (to float! x2 - x1 * size/x)
			]
		]
		compose/deep [
			push [
				line-width (thickness)
				font (tiny-font)
				translate (0 by (thickness / 2))
				(only markers)
				shape (wrap lines)
			]
		]
	]
]

;; icons for buttons that have no unicode glyph
font-20: make font! [size: 20]
icons: object [
	lists: object [
		numbered: bands/named 30x20 [25% 1  25% 1  25% 1] "123"
		bullet:   bands/named 30x20 [25% 1  25% 1  25% 1] [line-width 1 circle 2x0 1.5]
	]
	aligns: object [
		left:   bands 24x20 [0   80%  0 1  0   70%]
		right:  bands 24x20 [20% 1    0 1  30% 1  ]
		center: bands 24x20 [10% 90%  0 1  15% 85%]
		fill:   bands 24x20 [0   1    0 1  0   1  ]
	]
]

;; since document contains other documents, a toolbar button must know which one to affect
;; this tracks which document was the last one in focus and affects it 
last-focused-document: none
define-handlers [
	editor: extends 'editor [
		document: extends 'editor/document [
			on-focus [doc path event] [set 'last-focused-document doc]	;-- simplifies toolbar actors
		]
	]
]

;@@ need a simpler way to put styles into global sheet
extend VID/styles reshape [

	;; attr is a text-based button style used in the toolbar
	attr [
		template: data-clickable
		spec: [
			weight: 0
			margin: 4x2
			font:   font-20
			color:  none
			actors: object [
				on-over: function [space path event] [
					space/color: if path/2 inside? space [opaque 'text 20%]
				]
			]
		]
		facets: [string! data image! data block! command @(VID/props/font-styles)]
	]
	
	;; icon is an image-based button style used in the toolbar
	icon [
		template: clickable
		spec: [
			weight: 0
			margin: 5x10
			color:  none
			actors: object [
				on-over: function [space path event] [
					space/color: if path/2 inside? space [opaque 'text 20%]
				]
			]
		]
	]
	
	;; toolbar style that inserts whole layout (as payload) into it, as if it was declared using `style` VID/S keyword
	editor-toolbar [
		template: tube
		spec:     [axes: [e s] weight: 0]
		payload:  [[
			attr "B" bold      [editor-tools/toggle-flag last-focused-document 'bold]      hint="Toggle bold"
			attr "U" underline [editor-tools/toggle-flag last-focused-document 'underline] hint="Toggle underline"
			attr "i" italic    [editor-tools/toggle-flag last-focused-document 'italic]    hint="Toggle italic"
			attr "S" strike    [editor-tools/toggle-flag last-focused-document 'strike]    hint="Toggle strikethrough"
			attr "𝓕⏷"         [editor-tools/change-selected-font last-focused-document 'pick] flags= [1x1 bold] hint="Change font"
			attr "🎨⏷"         [editor-tools/change-selected-color last-focused-document 'pick] hint="Change color"
			attr "🔗"          [editor-tools/linkify-selected last-focused-document 'pick] hint="Convert into an URL"
			attr "[c]"         [editor-tools/codify-selected last-focused-document] font= make code-font [size: 20] hint="Convert into code"
			attr "⤆"           [batch last-focused-document [indent-range selected -20]]       hint="Decrease indentation"
			attr "⤇"           [batch last-focused-document [indent-range selected  20]]       hint="Increase indentation"
			attr "▦"           [editor-tools/insert-grid last-focused-document 'pick]      hint="Insert table"
			icon [image 24x20 data= icons/aligns/fill   ] on-click [batch last-focused-document [align-range selected 'fill]]   hint="Align to fill the row"
			icon [image 24x20 data= icons/aligns/left   ] on-click [batch last-focused-document [align-range selected 'left]]   hint="Align to the left"
			icon [image 24x20 data= icons/aligns/center ] on-click [batch last-focused-document [align-range selected 'center]] hint="Align to the center"
			icon [image 24x20 data= icons/aligns/right  ] on-click [batch last-focused-document [align-range selected 'right]]  hint="Align to the right"
			icon [image 30x20 data= icons/lists/numbered] on-click [editor-tools/enumerate-selected last-focused-document] hint="Numbered list"
			icon [image 30x20 data= icons/lists/bullet  ] on-click [editor-tools/bulletify-selected last-focused-document] hint="Unordered list"
		]]
	]
	
]; extend VID/styles [
]; do/expand with spaces/ctx [
