Red [
	title:   "Hovering test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

do with spaces/ctx [
declare-template 'wheel/space [
	content: none
	angle:   0	#type :invalidates
	point:   none
	into: function [offset /force child] [
		center: size / 2
		radius: (min size/x size/y) - (distance? 0x0 content/size) / 2  
		offset: offset - center
		offset: as-pair
			(offset/x * cosine angle) + (offset/y * sine angle)
			(offset/x * sine negate angle) + (offset/y * cosine angle)
		offset: offset + (content/size / 2) - (radius by 0)
		self/point: offset
		if any [force  0x0 +<= offset +< content/size] [reduce [content offset]]
	]
	
	draw: function [/on canvas] [
		self/size: finite-canvas first decode-canvas canvas
		unless content [return []]
		drawn: render content
		left: size - content/size
		radius: (min size/x size/y) - (distance? 0x0 content/size) / 2
		compose/deep [
			rotate (angle) (size / 2)
			translate (left / 2 + (radius by 0))
			(drawn)
			(when point (compose [pen blue line-width 1 fill-pen cyan box (point - 2) (point + 2)]))
		]
	]
]

define-handlers [
	wheel: [
		on-down [space path event] [start-drag path]
		on-up   [space path event] [stop-drag]
	]
]

view/no-wait/options [
	below
	b: host 300x300 [
		w: wheel rate= 67 on-time [space/angle: space/angle + 1] [
			box 150x150 brick [paragraph 70 cyan "point should stay near the cursor, with or without dragging"]
		] 
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

either system/build/config/gui-console? [print "---"][do-events]
]
