Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red


;@@ should be cells in the grid map!
view/no-wait/options [
	below
	b: host [
		grid [
			at 1x2 button "button1"
			; at 3x3 stretch 80x80
			at 3x1 button "button2"
		] with [autofit: none]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [run-console][do-events]

