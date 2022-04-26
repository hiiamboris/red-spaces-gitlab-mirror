Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
change-dir %..
do %everything.red


;@@ should be cells in the grid map!
view/no-wait/options [
	below
	b: host [
		grid with [
			cell-map/(1x2): make-space/name 'button [data: "button1"]
			; cell-map/(3x3): make-space/name 'space [draw: [] size: 80x80]
			cell-map/(3x1): make-space/name 'button [data: "button2"]
			; set-span 2x2 2x2
			; set-span/force 1x2 2x2
			heights/default: 'auto
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]

