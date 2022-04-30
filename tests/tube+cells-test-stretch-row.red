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
	width: either canvas [canvas/x][self/size/x]
	compose [
		fill-pen (svmc/text + 0.0.0.200)
		pen off box 0x0 (width by self/size/y)
		(drawn) 
	]
]
set-style 'field [fill-pen (contrast-with svmc/text) pen off box 0x0 (size)]
set-style 'field/caret [fill-pen (svmc/text)]
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
	[size: 60x30 text: "A"]
	[size: 50x40 text: "B"]
	[size: 40x50 text: "C"]
	[size: 30x60 text: "D"]
	[size: 20x20 text: "E"]
	[size: 30x10 text: "F"]
	[size: 10x10 text: "G"]
][
	; make-space/name 'rectangle spec
	; make-space/name 'field spec
	make-space/name 'cell [
		weight: 1
		content: make-space/name 'field spec
	]
]

tubes: collect [
	; for-each [/i axes] [ [→ ↓] [→ ↑] ][;] [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
	for-each [/i axes] [ [→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
	; for-each [/i axes] [ [e s] [e n]  [s w] [s e]  [w n] [w s]  [n e] [n w] ] [
		keep reshape [
			; cell with [limits: 170x200 .. 170x200] [
			cell with [limits: none .. 170x200] [
				list with [axis: 'y] [
					heading with [data: !(#composite "axes: (mold axes)")]
					; tube with [axes: !(axes) width: 130 item-list: boxes]
				]
			]
			; space with [size: 1x30]		/if even? i		;-- delimiter
		]
	]
]

; system/view/auto-sync?: no
view/no-wait compose/only/deep [
	h: host [
		list with [axis: 'y] [
			fps-meter									;-- constantly forces redraws which can be CPU intensive (due to Draw mostly)
			;; list-view doesn't work here because it accepts data, not spaces
			scrollable with [size: 540x240] [
				tube with [spacing: 5x10] (tubes)
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
