Red [
	title:   "Document demo toolbar template"
	author:  @hiiamboris
	license: BSD-3
]

do/expand with spaces/ctx [

;; helper function to draw some icons for alignment & list toggling
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

]; do/expand with spaces/ctx [
