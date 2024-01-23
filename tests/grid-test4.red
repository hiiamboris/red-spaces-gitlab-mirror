Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#do [disable-space-cache?: yes]
#include %../everything.red

;@@ use (wrapped) data!
;@@ make set up grid spaces for common scenarios

; system/view/auto-sync?: no

view/no-wait/options/flags [
	below
	host: host 1000x500 [
		column [
			fps-meter
			grid-view focus with [
				grid/pinned: 2x1
				grid/bounds: [x: #[none] y: #[none]]
				; grid/content/(1x2): make-space/name 'button [data: "button1"]
				; grid/content/(2x2): make-space/name 'button  [size: 80x80]
				; grid/content/(1x1): make-space/name 'button [data: "button2"]
				data: func [/pick xy /size] [
					either pick [xy][[x: #[none] y: #[none]]]
				]
				grid/set-span 1x1 2x1
				grid/set-span/force 2x2 3x2
				; set-span/force 1x1 1x3
				grid/heights/2: 100
				grid/widths/default: 100
				grid/heights/default: 30
			]
		]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x40
] [
	offset: 250x10
	actors: object [
		on-resize: on-resizing: function [window event] [
			host/size: window/size - 20x60
			if host/space [invalidate-tree host]
		]
	]
] 'resize

prof/show
prof/reset
; foreach-*ace/next path system/view/screens/1 [probe path]
do-events
prof/show

