Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
change-dir %..
do %everything.red
append spaces/keyboard/focusable 'grid-view

view/no-wait/options [
	below
	b: host [
		grid-view with [
			size: 400x400
			; grid/limits: 10x10
			; limits: [x: 10 y: auto]
			source/(1x2): "1x2"
			source/(2x2): "2x2"
			source/(1x1): "1x1"
			source/size: 10x10
			grid/set-span 1x1 2x1
			grid/set-span/force 2x2 3x2
			; set-span/force 1x1 1x3
			grid/heights/2: 200
			; grid/widths/default: 300
			; grid/heights/default: 300
		]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]

