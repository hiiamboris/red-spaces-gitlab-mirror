Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
#include %everything.red


lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
lorem10: append/dup {} lorem 10

list2d: []
; lst/source: messages: []
list1d: map-each/only i 50 [
	reduce [
		rejoin ["message " i * 2 - 1 ": " copy/part lorem random length? lorem]
		rejoin ["message " i * 2     ": " copy/part lorem random length? lorem]
	]
]
list2d: map-each/only i 50 [
	map-each c "ABCDEFGHIJ" [
		either i = 1 [form c][rejoin ["cell " c i - 1]]
	]
]

;-- drunken scrollbars animation
angle: 0
set-style 'back-arrow  [rotate (angle) (size / 2)]
set-style 'forth-arrow [rotate (angle) (size / 2)]
; set-style 'thumb [translate (size * 0x1 / 2) skew (angle / -2) translate (size * 0x-1 / 2)]
; render/as 'test 'root

;-- waving table rows animation
phase: 0
set-style 'table/headers [(t: now/time/precise phase: (to float! t) % 12 * 30 ())]
set-style 'row [(phase: phase + 60  margin/x: to 1 5 * sine phase ())]

counter: 0
; view [host [grid]]
; quit
; system/view/capturing?: yes
view/no-wait/options [
	below
	b: host [
		rotor [
			; list with [axis: 'y] [
				; field with [text: "field"]
				; spiral with [
				; 	field/text: lorem10
				; 	size: 300x300
				; ]
				; list-view with [size: 200x100 source: list1d] ;["1" "2" "3" "4" "5" "6" "7"]]
				; button with [data: "button"]
				; table with [size: 200x70 source: list2d] ;[ ["1" "2"] ["3" "4"] ["5" "6"] ["7" "8"] ["9" "A"] ["B" "C"] ["D" "E"] ["F" "G"]]]
				grid with [;[size: 200x200]
					cells/(1x2): make-space/name 'button [data: "button1"]
					cells/(3x3): make-space/name 'space [draw: [] size: 80x80]
					cells/(3x1): make-space/name 'button [data: "button2"]
					set-span 2x2 2x2
					set-span/force 1x2 2x2
					;@@ need a bunch of table demos to test against - then refactor it
					heights/default: 'auto
				]
			; ]
		]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
	rate 3 on-time [
		counter: counter + 1
		angle: pick [0 -13 -20 -13 0 13 20 13] counter % 8 + 1
		b/draw: render/as b/space 'root
	]
] [offset: 10x10]
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]

