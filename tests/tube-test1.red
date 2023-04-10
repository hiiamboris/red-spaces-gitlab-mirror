Red [needs: view]

;; fun: this demo contains 1787 spaces! and no lag except for the initial tree construction delay!

; recycle/off					
#include %../../common/include-once.red
; #include %../../common/assert.red
; #include %../../common/debug.red
#include %../../common/composite.red
#include %../../common/contrast-with.red
; #do [disable-space-cache?: on]
#include %../everything.red

svmc: system/view/metrics/colors
bigfont: make font! [size: 20]
set-style 'heading function [self /on canvas [pair! none!] fill-x fill-y] [
	maybe/same self/font: bigfont
	drawn: self/draw/on canvas fill-x fill-y
	compose [
		fill-pen (svmc/text + 0.0.0.200)
		pen off box 0x0 (self/size)
		(drawn) 
	]
]
set-style 'field function [field /on canvas fill-x fill-y] [
	drawn: field/draw/on canvas fill-x fill-y
	compose/deep/only [push [
		fill-pen (c: contrast-with svmc/text)
		pen (contrast-with c)
		line-width 1
		box 0x0 (field/size)
	] (drawn)]
]
; set-style 'field/caret [[fill-pen (svmc/text)]]
set-style 'tube function [tube /on canvas [pair! none!] fill-x fill-y] [
	drawn: tube/draw/on canvas fill-x fill-y
	#assert [drawn]
	#assert [tube/size]
	compose/only/deep [
		push [fill-pen off pen blue box 0x0 (tube/size)]
		(drawn)
	]
]

declare-template 'heading/data-view []

boxes: [
	field 60x30 "A"
	field 50x40 "B"
	field 40x50 "C"
	field 30x60 "D"
	field 20x20 "E"
	field 30x10 "F"
	field 10x10 "G"
]

width: 130
; aligns: map-each/only x [-1 0 1] [ map-each y [-1 0 1] [as-pair x y] ]
aligns: map-each/only y [↑ #[none] ↓] [ map-each/only x [← #[none] →] [trim reduce [x y]] ]
; aligns: [[[← ↑]]]
tubes: collect [
	; for-each [/i axes] [ [e s] [e n]  [s w] [s e]  [w n] [w s]  [n e] [n w] ] [
	keep compose [
		style vlist: vlist margin= 5x5 spacing= 5x5
		style tube:  tube  margin= 5x5 spacing= 5x5
	]
	for-each [/i axes] [ [→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←] ] [
	; for-each [/i axes] [ [↓ →] ][
		do with spaces/ctx [
			lim2: extend-canvas
				lim1: width by width
				anchor2axis axes/2
		]
		if i > 1 [keep [<-> 1x30]]		;-- delimiter
		keep compose [heading data=(#composite "axes: (mold axes)")]
		for-each group aligns [
			keep [hlist tight]
			keep/only map-each align group [
				compose/deep/only [
					vlist [
						text text=(#composite "align: (mold align)")
						tube axes=(axes) align=(align) limits=(lim1 .. lim2) content= lay-out-vids boxes 
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
			scrollable 540x500 vertical [
				list: vlist (tubes)
			]
		]
	]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	return status: text 500x40
]

; dump-tree
out: none
save %tube-test-output.png out: draw list/size render/on list list/size no no
if exists? ref: %tube-test-reference.png [
	ref: load ref
	unless ref = out [print "!! LAYOUT HAS CHANGED !!"]
]
prof/show
prof/reset
; debug-draw
either system/build/config/gui-console? [print "---"][do-events]
prof/show
