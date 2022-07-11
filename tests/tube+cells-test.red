Red [needs: view]

; recycle/off					
#include %../../common/include-once.red
; #include %../../common/assert.red
; #include %../../common/debug.red
#include %../../common/composite.red
#include %../../common/contrast-with.red
#include %../everything.red

svmc: system/view/metrics/colors
bigfont: make font! [size: 20]
set-style 'heading function [self /on canvas [pair! none!]] [
	self/font: bigfont
	drawn: self/draw/on canvas
	width: either canvas [abs canvas/x][self/size/x]
	compose [
		fill-pen (svmc/text + 0.0.0.200)
		pen off box 0x0 (width by self/size/y)
		(drawn) 
	]
]
set-style 'field [[fill-pen (contrast-with svmc/text) pen off box 0x0 (size)]]
; set-style 'field/caret [fill-pen (svmc/text)]
set-style 'tube function [tube /on canvas [pair! none!]] [
	drawn: tube/draw/on canvas
	#assert [drawn]
	#assert [tube/size]
	compose/only/deep [
		push [fill-pen off pen blue box 1x1 (tube/size - 1x1)]
		(drawn)
	]
]

spaces/templates/heading: make-template 'data-view []

boxes: map-each spec [
	[60x30 "A"]
	[50x40 "B"]
	[40x50 "C"]
	[30x60 "D"]
	[20x20 "E"]
	[30x10 "F"]
	[10x10 "G"]
][
	; make-space/name 'rectangle spec
	; make-space/name 'field spec
	compose/deep [cell [field (spec)]]
]

width: 130
tubes: collect [
	; for-each [/i axes] [ [→ ↓] ][;] [→ ↑] ][;] [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
	for-each [/i axes] [ [→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
		do with spaces/ctx [
			lim2: extend-canvas
				lim1: width by width
				anchor2axis axes/2
		]
		keep reshape [
			cell none .. 170x200 [
				vlist [
					heading data= !(#composite "axes: (mold axes)")
					row tight spacing= 5x5 axes= !(axes) limits= !(lim1 .. lim2) !(boxes)
				]
			]
		]
	]
]

; system/view/auto-sync?: no
view/no-wait compose/only/deep [
	h: host [
		vlist [
			fps-meter		;-- constantly forces redraws which can be CPU intensive (due to Draw mostly)
			;; list-view doesn't work here because it accepts data, not spaces
			scrollable 540x500 [
				tube spacing= 5x10 (tubes)
			]
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	return status: text 500x40
]

; dump-tree
prof/show
prof/reset
; debug-draw
either system/build/config/gui-console? [print "---"][do-events]
prof/show
