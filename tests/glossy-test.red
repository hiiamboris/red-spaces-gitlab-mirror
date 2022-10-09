Red [
	title:   "Glossy stylesheet test"
	author:  @hiiamboris
	license: BSD-3
]

#include %../everything.red

#process off											;@@ hack to avoid #include bugs
do/expand [#include %../stylesheets/glossy.red]
#process on
	
view/flags [
	title "Glossy stylesheet test"
	host 700x400 [
		column [
			hlist [
				vlist [
					button "OK"     hint= "Hint OK"
					button "Cancel" hint= "Hint Cancel"
					hlist tight [switch state= on  text "Option 1"]
					hlist tight [switch state= off text "Option 2"]
					field "Entry field" focus
				]
				cell color= opaque black 50% [
					vlist [
						box [text white "Grid"]
						grid spacing= 10x10 bounds= 2x2 widths= #(default 70) [
							text "Cell 1x1" text "Cell 2x1" return
							text "Cell 1x2" text "Cell 2x2"
						]
					]
				]
				cell color= opaque black 50% [
					vlist [
						box [text white "Grid-view"]
						grid-view 180x130 with [
							grid/widths: #(default 70)
							grid/pinned: 0x1
						]
						source= map-each/only y 10 [map-each x 2 [rejoin ["Data " x by y]]]
					]
				]
			]
			column tight weight= 1 [					;@@ make row/col weight=1 by default?
				box [text white "List-view"]
				list-view source= read %.
			]
		]
	] react [
		face/size: face/parent/size - 20
		invalidate get face/space
	]
] 'resize

