Red [
	title:   "List test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

wrap1: func [i] [
	first lay-out-vids [
		scrollable content-flow= 'vertical [
			label image= #"0" + i text= rejoin [prefix i]
		]
	]
]
wrap2: func [i] [
	first lay-out-vids [
		scrollable content-flow= 'planar [
			label image= #"0" + i text= rejoin [prefix i]
		]
	]
]

prefix: append/dup {} "label text " 5
w: view/no-wait/options expand-directives [
	below
	host: host focus [
		hlist [
			list-view 200x200 source= map-each i 15 [i] wrap-data= :wrap1
			list-view 200x200 source= map-each i 15 [i] wrap-data= :wrap2
		]
	]
	on-over [status/text: mold hittest face/space event/offset]
	; on-key [
	; print "--->"
		; tabbing/window-walker/forward?: on
		; foreach-node w tabbing/window-walker func [parent child] [
			; print spaces/ctx/space-id child
		; ]
	; print "<---"
	; ]
	status: text 400x70
] [offset: 10x10]

prof/show prof/reset
either system/build/config/gui-console? [run-console][do-events]
prof/show

