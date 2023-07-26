Red [
	title:   "List test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red


lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}

list1d: map-each i 100 [
; list1d: map-each i 20 [
	rejoin ["message " i ": " copy/part lorem random length? lorem]
	; rejoin ["message " i ": " copy/part lorem 800]
]

;-- drunken scrollbars animation
angle: 0
define-styles [
	back-arrow:  [below: [rotate (angle) (size / 2)]]
	forth-arrow: [below: [rotate (angle) (size / 2)]]
	hscroll/thumb: vscroll/thumb: [
		below: [translate (size * 0x1 / 2) skew (angle / -2) translate (size * 0x-1 / 2)]
	]
]

counter: 0
; system/view/capturing?: yes
view/no-wait/options [
	below
	b: host [
		; lv: list-view focus selectable 300x400 source= list1d
		lv: list-view focus multi-selectable 300x400 source= list1d
			; with [list/margin: 80x0]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
	rate 3 on-time [
		counter: counter + 1
		angle: pick [0 -13 -20 -13 0 13 20 13] counter % 8 + 1
		invalidate lv; <everything>
		b/draw: render b
	]
] [offset: 10x10]
;foreach-*ace/next path system/view/screens/1 [probe path]
; dump-tree
; debug-draw
either system/build/config/gui-console? [print "---"][do-events]

