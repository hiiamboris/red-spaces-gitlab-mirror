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
		3. when pointer is held in place outside the rotating box, timer should keep triggering on-over
		   so crosshair should still be around the pointer, save for minor inter-frame lag
		4. up event outside of the rotating box should indicate by color that the pointer is not captured
		5. shift? flag should be reliably reported by synthesized over events
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
		offset: offset + (content/size / 2) - (radius . 0)
		self/point: offset
		if any [force  0x0 +<= offset +< content/size] [reduce [content offset]]
	]
	
	draw: function [/on canvas fill-x fill-y] [
		self/size: finite-canvas canvas
		unless content [return []]
		drawn: render content
		left: size - content/size
		radius: (min size/x size/y) - (distance? 0x0 content/size) / 2
		compose/deep [
			rotate (angle) (size / 2)
			translate (left / 2 + (radius . 0))
			(drawn)
			(when point (compose [pen blue line-width 1 fill-pen cyan box (point - 2) (point + 2)]))
		]
	]
]

define-handlers [
	box: [
		on-down [space path event] [start-drag path]
		on-up   [space path event] [
			stop-drag
			space/color: either path/2 inside? space [magenta][brick]
		]
		on-over [space path event] [
			update-status event
			space/color: either any [path/2 inside? space  dragging?/from space] [magenta][brick]
		]
	]
]

update-status: function [event] [
	status/text: append mold hittest host/space event/offset pick ["^/SHIFT DOWN" ""] event/shift?
]

view/no-wait/options [
	below
	host: host 300x300 [
		w: wheel [
			box 150x150 brick [paragraph 70 cyan "crosshair should stay near the pointer, with or without dragging"]
		] rate= 67 on-time function [space path event delay] [
			update-status event
			space/angle: space/angle + (1 + delay)
		] 
	]
	on-over [update-status event]
	status: text 300x40
] [offset: 10x10]

do-events
prof/show
];; do with spaces/ctx [
