Red [
	title:   "List test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

view/no-wait/options expand-directives [
	below
	host focus [
		list-view 200x200 source= map-each i 15 [i] wrap-data= func [i] [
			first lay-out-vids [label image= #"0" + i text= `"label text (i)"`]
		]
	]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 300x40
] [offset: 10x10]

unless system/build/config/gui-console? [do-events]

