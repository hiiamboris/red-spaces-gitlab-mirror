Red [
	title:   "Spiral Field test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
cd %..
do %everything.red


lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
lorem10: append/dup {} lorem 10


counter: 0
; system/view/capturing?: yes
view/no-wait/options [
	below
	b: host [
		rotor [
			spiral with [
				field/text: lorem10
				size: 300x300
			]
		]
	] with [color: system/view/metrics/colors/panel]
	on-created [b/draw: render b]
	; b: host with [color: system/view/metrics/colors/panel size: test/size space: 'test]
	; draw b/space/draw
	; on-detect [probe event/type]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]
foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [halt][do-events]

