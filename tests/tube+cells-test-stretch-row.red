Red [needs: view]

; recycle/off					
; #include %../../common/include-once.red
#include %../everything.red
; #include %../../common/assert.red
; #include %../../common/debug.red
#process off
do/expand [
#include %../../common/composite.red
#include %../../common/contrast-with.red

svmc: system/view/metrics/colors
bigfont: make font! [size: 20]
set-style 'heading function [self /on canvas [point2D! none!] fill-x fill-y] [
	self/font: bigfont
	drawn: self/draw/on canvas fill-x fill-y
	width: either canvas [canvas/x][self/size/x]
	compose [
		fill-pen (svmc/text + 0.0.0.200)
		pen off box 0x0 (width . self/size/y)
		(drawn) 
	]
]
set-style 'field [[fill-pen (contrast-with svmc/text) pen off box 0x0 (size)]]
set-style 'field/caret [fill-pen (svmc/text)]
set-style 'tube function [tube /on canvas [point2D! none!] fill-x fill-y] [
	drawn: tube/draw/on canvas fill-x fill-y
	#assert [drawn]
	#assert [tube/size]
	compose/only/deep [
		push [fill-pen off pen blue box 1x1 (tube/size - 1x1)]
		(drawn)
	]
]

declare-template 'heading/data-view []

boxes: map-each spec [
	[size: (60,30) text: "A"]
	[size: (50,40) text: "B"]
	[size: (40,50) text: "C"]
	[size: (30,60) text: "D"]
	[size: (20,20) text: "E"]
	[size: (30,10) text: "F"]
	[size: (10,10) text: "G"]
][
	; make-space 'rectangle spec
	; make-space 'field spec
	make-space 'cell [
		weight: 1
		content: make-space 'field spec
	]
]

tubes: collect [
	; for-each [/i axes] [ [→ ↓] [→ ↑] ][;] [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
	for-each [/i axes] [ [→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
	; for-each [/i axes] [ [e s] [e n]  [s w] [s e]  [w n] [w s]  [n e] [n w] ] [
		keep reshape [
			; cell with [limits: 170x200 .. 170x200] [
			cell none .. 150x200 [
				vlist [
					heading data= @[#composite "axes: (mold axes)"]
					; tube with [axes: @[axes] width: 130 content: boxes]
				]
			]
			; space with [size: 1x30]		/if even? i		;-- delimiter
		]
	]
]

; system/view/auto-sync?: no
view/no-wait compose/only/deep [
	h: host [
		vlist [
			fps-meter									;-- constantly forces redraws which can be CPU intensive (due to Draw mostly)
			;; list-view doesn't work here because it accepts data, not spaces
			scrollable 500x240 [
				tube spacing= 5x10 (tubes)
			]
		]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	return status: text 500x40
]

; dump-tree
prof/show
prof/reset
; debug-draw
either system/build/config/gui-console? [run-console][do-events]
prof/show
]