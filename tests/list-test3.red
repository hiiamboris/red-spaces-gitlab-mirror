Red [
	title:   "List test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red
; #do [disable-space-cache?: on]

lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}

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
		lv: list-view multi-selectable focus 300x400 data= function [/pick i /size] [
			either pick [
				rejoin ["message " i ": " copy/part lorem random length? lorem]
			][none]									;-- /size = none for unlimited
		] with [list/margin: 10x20]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
	rate 3 on-time [
		counter: counter + 1
		angle: pick [0 -13 -20 -13 0 13 20 13] counter % 8 + 1
		invalidate lv; <everything>
		; b/draw: render b
	]
	across text "Jump to item:"
	entry: field "1'000'000'000" [batch lv [move-cursor entry/data]]
	button "🔽" [batch lv [frame/move-to/after/no-clip  move-cursor entry/data]]
	button "🔼" [batch lv [frame/move-to/before/no-clip move-cursor entry/data]]
] [offset: 10x10]
; debug-draw
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [run-console][do-events]

