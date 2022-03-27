Red [needs: view]

;; fun: this demo contains 7830 spaces!
;; (as shown by dump-tree output, most of it comes from `field` usage, which has hidden scrollers)

; recycle/off					
#include %../../common/include-once.red
; #include %../../common/assert.red
; #include %../../common/debug.red
; #include %../../common/composite.red
#include %../../common/contrast-with.red
#include %../everything.red

svmc: system/view/metrics/colors
bigfont: make font! [size: 20]
set-style 'heading function [self /on canvas [pair! none!]] [
	self/font: bigfont
	drawn: self/draw/on canvas 1x1
	width: either canvas [canvas/x][self/size/x]
	compose [
		fill-pen (svmc/text + 0.0.0.200)
		pen off box 0x0 (width by 50)
		(drawn) 
	]
	; self/size/x: self/layout/size/x
]
; set-style 'heading [
	; (unless bigfont =? font [self/font: bigfont] ())
	; fill-pen (svmc/text + 0.0.0.200) pen off box 0x0 (as-pair size/x 50)
; ]
set-style 'field [fill-pen (contrast-with svmc/text) pen off box 0x0 (size)]
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

boxes: map-each spec [
	[size: 60x30 text: "A"]
	[size: 50x40 text: "B"]
	[size: 40x50 text: "C"]
	[size: 30x60 text: "D"]
	[size: 20x20 text: "E"]
	[size: 30x10 text: "F"]
	[size: 10x10 text: "G"]
] [make-space/name 'field spec]

aligns: map-each/only x [-1 0 1] [ map-each/eval/only y [-1 0 1] [[x y]] ]
tubes: collect [
	for-each [/i axes] [ [s e] [s w]  [w s] [w n]  [n w] [n e]  [e n] [e s] ] [
		if i > 1 [keep [space with [size: 1x30]]]		;-- delimiter
		keep compose/deep [heading with [data: (#composite "axes: (mold axes)")]]
		for-each group aligns [
			keep [list with [axis: 'x]]
			keep/only map-each align group [
				compose/deep/only [
					list with [axis: 'y] [
						paragraph with [width: 130 text: (#composite "align: (mold align)")]
						tube with [axes: (axes) align: (align) width: 130 item-list: boxes]
					]
				]
			]
		]
	]
]

view/no-wait compose/only/deep [
	h: host [
		scrollable with [size: 540x500] [
			list with [axis: 'y] (tubes)
		]
	]
]

; dump-tree
list: do fix-paths [h/scrollable/list]
save %tube-test-output.png out: draw list/size render/on 'list list/size
if exists? ref: %tube-test-reference.png [
	ref: load ref
	unless ref = out [print "!! LAYOUT HAS CHANGED !!"]
]
either system/build/config/gui-console? [print "---"][do-events]