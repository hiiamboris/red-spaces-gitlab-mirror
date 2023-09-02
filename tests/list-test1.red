Red [
	title:   "List test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

view/no-wait/options [
	below
	b: host focus [
		vlist [
			button "button 1" focus
			button "button 2"
			button "button 3"
		]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

dump-tree
either system/build/config/gui-console? [run-console][do-events]

