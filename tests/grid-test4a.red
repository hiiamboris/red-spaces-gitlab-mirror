Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

;@@ use (wrapped) data!
;@@ make set up grid spaces for common scenarios

; system/view/auto-sync?: no

view/no-wait/options [
	below
	host [fps-meter]
	b: host [
		grid-view 1000x500 with [
			grid/pinned: 2x1
			; grid/bounds: [x: #[none] y: #[none]]
			; grid/bounds: [x: 20 y: 20]
			; grid/content/(1x2): make-space/name 'button [data: "button1"]
			; grid/content/(2x2): make-space/name 'button  [size: 80x80]
			; grid/content/(1x1): make-space/name 'button [data: "button2"]
			data: func [/pick xy /size] [
				; either pick [xy][[x: #[none] y: #[none]]]
				either pick [xy][[x: 50 y: 50]]
				; either pick [xy][[x: 2 y: 1]]
			]
			grid/set-span 1x1 2x1
			grid/set-span/force 2x2 3x2
			; set-span/force 1x1 1x3
			grid/heights/2: 100
			grid/widths/default: 100
			grid/heights/default: 30
		]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

prof/show
prof/reset
print "==================="
; foreach-*ace/next path system/view/screens/1 [probe path]
do-events
prof/show

