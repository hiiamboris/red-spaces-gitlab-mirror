Red [
	title:   "List test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
cd %..
do %everything.red

view/no-wait/options [
	below
	b: host focus [
		list with [axis: 'y] [
			button with [data: "button 1"]
			button with [data: "button 2"]
			button with [data: "button 3"]
		]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

dump-tree
either system/build/config/gui-console? [print "---"][do-events]

