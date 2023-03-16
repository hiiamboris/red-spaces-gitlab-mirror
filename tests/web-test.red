Red [
	title:   "Web test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

;@@ TODO: beautify it and draw a spider at random location, or leave it to the others as a challenge
;@@ TODO: explore fractals this way :D
declare-template 'web/inf-scrollable [
	web: self
	canvas: make-space 'space [
		type: 'canvas
		available?: function [axis dir from requested] [requested]
	
		draw: function [/window xy1 xy2 /on canvas] [
			#assert [window]
			center: 100x100
			sectors: 12
			t: tangent (sec: 360 / sectors) / 2
			size: xy2 - xy1
			corners: map-each corner 2x2 [corner - 1x1 * size + xy1 - center]
			radii: minmax-of map-each/eval c corners [1.0 * spaces/ctx/vec-length? c]
			either within? 0x0 corners/1 size + 1 [
				angles: [0 360]
				radii/1: 0
			][
				angles: minmax-of map-each c corners [
					(arctangent2 c/y c/x) // 360
				]
				;-- try to determine the closest radius approximately
				reserve: max size/x / 2 size/y / 2		;-- for when center gets out of the viewport
				radii/1: sqrt max 0 radii/1 ** 2 - (reserve ** 2)
				radii/1: radii/1 * cosine sec / 2		;-- for when looking at distant web joint points
			]
			sec-draw: map-each/drop i sectors [
				a: i - 1 * sec
				unless all [angles/1 <= (a + sec) a <= angles/2] [continue]
				lvl1: round/to/floor   sqrt radii/1 1
				lvl2: round/to/ceiling sqrt radii/2 1
				levels: map-each/eval lvl lvl2 - lvl1 + 1 [
					r: lvl + lvl1 ** 2
					p: as-pair r r * t
					['line p p * 1x-1]
				]
				compose/deep/only [
					rotate (a) [line (radii/1 * 1x0) (radii/2 * 1x0)]
					rotate (a + (sec / 2)) (levels)
				]
			]
			set-quiet in self 'size none				;-- circumvent pair type check without declaring a new class
			compose/only [translate (center) (sec-draw)]
		]
	]

	window/content: canvas
]


define-handlers [
	web: extends 'inf-scrollable [
		; on-time [space path event] [space/roll update]
	]
]
append spaces/focus/focusable 'web

view/no-wait/options [
	below
	b: host [web 900x550]
	on-over [
		status/text: mold as path! hittest face/space event/offset
	]
	; rate 3 on-time [b/draw: render b]
	status: text 900x40
] [offset: 10x10]
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [halt][do-events]
prof/show
