Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

append spaces/keyboard/focusable 'grid-view

view/no-wait/options [
	below
	b: host [
		gv: grid-view focus 400x400 
		source= #(1x2 "1x2" 2x2 "2x2" 1x1 "1x1" size: 10x10)
		with [
			; grid/bounds: 10x10
			; grid/bounds: [x: 10 y: auto]
			grid/set-span 1x1 2x1
			grid/set-span/force 2x2 3x2
			; set-span/force 1x1 1x3
			grid/heights/default: 100
			grid/heights/2: 200
			; grid/widths/default: 300
			; grid/heights/default: 300
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]

