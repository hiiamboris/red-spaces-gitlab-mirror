Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
change-dir %..
do %everything.red


view/no-wait/options [
	below
	b: host [
		grid with [
			limits: 10x10
			; limits: [x: 10 y: auto]
			cell-map/(1x2): make-space/name 'button [data: "button1"]
			cell-map/(2x2): make-space/name 'button [size: 80x80]
			cell-map/(1x1): make-space/name 'button [data: "button2"]
			set-span 1x1 2x1
			set-span/force 2x2 3x2
			; set-span/force 1x1 1x3
			heights/2: 100
			heights/default: 40
		]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]
