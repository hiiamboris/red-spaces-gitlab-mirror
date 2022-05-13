Red [
	title:   "Spiral Field test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

;; Fun facts:
;; - the text string in this demo is circa 25000px long
;; - it takes ~100ms to lay out the text, but 400-600ms to draw it (see #5130)

#include %../everything.red

;; this code is a bit messy and I'm lazy to clean it up
spaces/templates/spiral: make-template 'space [
	size: 100x100
	content: 'field			;-- reuse field to apply it's event handlers
	field: make-space 'field [size: 999999999x9999]		;-- it's infinite
	map: [field [offset 0x0 size 999x999]]

	into: function [xy [pair!] /force name [word! none!]] [
		;@@ TODO: unify this with `draw` code somehow
		render/on in field 'paragraph infxinf	;-- produce layout 
		r: field/paragraph/layout
		#assert [r]

		len: length? text: field/text
		if empty? text [return none]		;-- case of empty string
		full: caret-to-offset/lower r len	;-- full size: line height and average char width
		p: size / 2 * 0x-1					;-- start at upper center
		decay: (p/y + full/y) / p/y			;-- orbit decay per cycle (< 1)
		rmax: absolute p/y					;-- outer radius
		rmid: full/y / -2 + absolute p/y	;-- radius of the middle line of the string
		wavg: full/x / len					;-- average char width
		p: p - (wavg / 2)					;-- offset the typesetter to center the average char

		;@@ TODO: initial angle
		xy: xy - (size / 2)
		rad: xy/x ** 2 + (xy/y ** 2) ** 0.5
		angle: 90 + arctangent2 xy/y xy/x
		correction: decay ** (angle / 360)
		cycles: attempt [to 1 (log-e rad / rmax / correction) / log-e decay]
		unless cycles [return none]			;-- math failed :(
		cycles: cycles + (angle / 360)
		length: cycles * 2 * pi * rmid
		reduce ['field as-pair length 1]
	]

	draw: function [] [
		maybe field/paragraph/width: none		;-- disable wrap
		maybe field/paragraph/text: field/text
		unless r: field/paragraph/layout [
			;; render is needed to produce layout and cached parents tree
			;; so on key press paragraph invalidates also spiral itself
			render/on in field 'paragraph infxinf		;-- produce layout 
			r: field/paragraph/layout
			#assert [r]
		]

		len: length? text: field/text
		if empty? text [return []]			;-- case of empty string
		full: caret-to-offset/lower r len	;-- full size: line height and average char width
		p: size / 2 * 0x-1					;-- start at upper center
		decay: (p/y + full/y) / p/y			;-- orbit decay per cycle (< 1)
		rmid: full/y / -2 + absolute p/y	;-- radius of the middle line of the string
		wavg: full/x / len					;-- average char width
		p: p - (wavg / 2)					;-- offset the typesetter to center the average char
		drawn: clear []		;@@ this is a bug, really
		;@@ TODO: initial angle
		append drawn compose [translate (size / 2)]
		repeat i len [			;@@ should be for-each [/i c]
			c: text/:i
			bgn: caret-to-offset r i
			cycles: bgn/x / 2 / pi / rmid
			scale: decay ** cycles
			box: []
			if all [field/active?  i - 1 = field/caret-index] [
				box: compose [box (p) (p + as-pair field/caret-width full/y)]
			]
			compose/deep/into [
				push [
					rotate (cycles * 360)
					scale (scale) (scale)
					(box)
					text (p) (form c)
				]
			] tail drawn
		]
		drawn
	]
]


lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
lorem10: append/dup {} lorem 10


counter: 0
view/no-wait/options [
	below
	b: host [
		rotor [
			spiral with [
				field/text: lorem10
				size: 300x300
			]
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

prof/show prof/reset
either system/build/config/gui-console? [halt][do-events]
prof/show


