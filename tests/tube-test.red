Red [needs: view]

;; fun: this demo contains 7840 spaces!
;; (as shown by dump-tree output, most of it comes from `field` usage, which has hidden scrollers)
;; as a result, just physically drawing it takes 15-20ms! and it's a bit laggy

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
set-style 'field [push [fill-pen (c: contrast-with svmc/text) pen (contrast-with c) line-width 1 box 0x0 (size)]]
set-style 'field/caret [fill-pen (svmc/text)]
set-style 'tube function [tube /on canvas [pair! none!]] [
	drawn: tube/draw/on canvas
	#assert [drawn]
	#assert [tube/size]
	compose/only/deep [
		push [fill-pen off pen blue box 0x0 (tube/size)]
		(drawn)
	]
]

spaces/templates/heading: make-template 'data-view []

boxes: lay-out-vids [
	field size= 60x30 "A"
	field size= 50x40 "B"
	field size= 40x50 "C"
	field size= 30x60 "D"
	field size= 20x20 "E"
	field size= 30x10 "F"
	field size= 10x10 "G"
]

; aligns: map-each/only x [-1 0 1] [ map-each y [-1 0 1] [as-pair x y] ]
aligns: map-each/only y [↑ #[none] ↓] [ map-each/only x [← #[none] →] [trim reduce [x y]] ]
tubes: collect [
	; for-each [/i axes] [ [e s] [e n]  [s w] [s e]  [w n] [w s]  [n e] [n w] ] [
	keep [
		style vlist: vlist margin= 5x5 spacing= 5x5
		style tube:  tube  margin= 5x5 spacing= 5x5 width= 130 item-list= boxes
	]
	for-each [/i axes] [ [→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
		if i > 1 [keep [<-> 1x30]]		;-- delimiter
		keep compose [heading data=(#composite "axes: (mold axes)")]
		for-each group aligns [
			keep [hlist tight]
			keep/only map-each align group [
				compose/deep/only [
					vlist [
						text text=(#composite "align: (mold align)")
						tube axes=(axes) align=(align)
					]
				]
			]
		]
	]
]

; system/view/auto-sync?: no
view/no-wait compose/only/deep [
	h: host [
		vlist [
			fps-meter									;-- constantly forces redraws which can be CPU intensive (due to Draw mostly)
			;; list-view doesn't work here because it accepts data, not spaces
			scrollable 540x500 [
				list: vlist (tubes)
			]
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	return status: text 500x40
]

; dump-tree
out: none
save %tube-test-output.png out: draw list/size render/on 'list list/size
if exists? ref: %tube-test-reference.png [
	ref: load ref
	unless ref = out [print "!! LAYOUT HAS CHANGED !!"]
]
prof/show
prof/reset
; debug-draw
either system/build/config/gui-console? [print "---"][do-events]
prof/show
