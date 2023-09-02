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
		list-view 200x200 with [list/spacing: 0]		;-- zero spacing for equal zebra bands
		source= map-each i 15 [i] wrap-data= function [i] [
			color: opaque 'text pick [10% 0%] even? i
			first lay-out-vids [box margin= 4x2 left color= color [label image= #"0" + i text= `"label text (i)"`]]
		]
	]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 300x40
] [offset: 10x10]

either system/build/config/gui-console? [run-console][do-events]

