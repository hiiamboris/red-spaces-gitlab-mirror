Red [
	title:   "Hovering test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
	notes: {
		Victory conditions: 
		1. when pointer leaves the host,
		   the crosshair should start rotating when not it's not dragged,
		   but stick to the pointer when it is
		2. box color should indicate when pointer is in or out of it
		   even if no physical pointer movement happens
		   (because box rotates, there is movement in its own coordinate space)
		3. no over events occur when pointer is held in place outside the rotating box
		   except when dragging out of the box, when it should keep receiving the events
	}
]

#include %../everything.red

do/expand with spaces/ctx [
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
	box: [
		on-over [space path event] [
			; status/text: mold probe hittest host/space event/offset
			quietly status/text: mold hittest host/space event/offset
			space/color: either inside?: 0x0 +<= path/2 +< space/size [magenta][brick]
		]
	]
]

view/no-wait/options [
	below
	host: host 300x300 [
		w: wheel [
			box 150x150 brick [paragraph 70 cyan "crosshair should stay near the pointer, with or without dragging"]
		] rate= 67 on-time function [space path event delay] [
			space/angle: space/angle + (1 + delay)
		] 
	]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 300x40
] [offset: 10x10]

either system/build/config/gui-console? [print "---"][do-events]
prof/show
];; do with spaces/ctx [
