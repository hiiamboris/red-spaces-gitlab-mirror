Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red


view/no-wait/options [
	below
	b: host [
		grid 5x5 [; bounds=[x: 10 y: auto]
			; below 
			; button "button1"
			; button 80x80 .. none
			; return
			; button "button2"
			at 1x2 button "button1"
			at 2x2 .. 4x3 button 80x80 .. none
			at 1x1 .. 2x1 button "button2"
		] heights= #(2 100 default 40)
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

dump-tree
either system/build/config/gui-console? [print "---"][do-events]

