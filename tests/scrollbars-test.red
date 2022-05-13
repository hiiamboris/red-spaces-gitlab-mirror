Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red


;-- drunken scrollbars animation
angle: 0
set-style 'back-arrow  [rotate (angle) (size / 2)]
set-style 'forth-arrow [rotate (angle) (size / 2)]
set-style 'thumb [translate (size * 0x1 / 2) skew (angle / -2) translate (size * 0x-1 / 2)]
; render/as 'test 'root

; system/view/capturing?: yes
counter: 0
view/no-wait/options [
	below
	b: host [
		vlist [
			scrollbar with [size: 400x20 amount: 0.5 axis: 'x]
			scrollbar with [size: 200x20 amount: 0.5 axis: 'x]
			scrollbar with [size: 100x20 amount: 0.5 axis: 'x]
			scrollbar with [size: 75x20  amount: 0.5 axis: 'x]
			scrollbar with [size: 50x20  amount: 0.5 axis: 'x]
			scrollbar with [size: 40x20  amount: 0.5 axis: 'x]
			scrollbar with [size: 30x20  amount: 0.5 axis: 'x]
			scrollbar with [size: 20x20  amount: 0.5 axis: 'x]
			scrollbar with [size: 10x20  amount: 0.5 axis: 'x]
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
	rate 3 on-time [
		counter: counter + 1
		angle: pick [0 -13 -20 -13 0 13 20 13] counter % 8 + 1
		b/draw: render b
	]
] [offset: 10x10]
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]

