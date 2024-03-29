Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red


;; this makes grid/cell look like generic cell, i.e. with a frame
;; otherwise it's hard to visually analyze the layout
remove-style 'grid/cell
	
view/no-wait/options [
	below
	b: host focus [
		grid 5x5 autofit= none [; bounds=[x: 10 y: auto]
			; below 
			; button "button1"
			; button 80x80 .. none
			; return
			; button "button2"
			at 1x2 button "button1"
			at 2x2 .. 4x3 button 80x80
			at 1x1 .. 2x1 button "button2"
		] heights= #[2 100 default 40]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

dump-tree
do-events

