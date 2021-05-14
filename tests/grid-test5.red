Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
change-dir %..
do %everything.red

append keyboard/focusable 'grid-view
;@@ use (wrapped) data!
;@@ make set up grid spaces for common scenarios


copy-deep-limit: function [b n] [
	if negative? n: n - 1 [return []]
	b: copy b
	forall b [
		unless block? :b/1 [continue]
		change/only b copy-deep-limit b/1 n
	]
	b
]

; system/view/auto-sync?: no
traversal/depth-limit: 4
depth: 0
max-depth: 1
t0: now/precise
view/no-wait/options [
	below
	text 500 center white red font-size 20 "Rendering this should take a while..."
	b: host [
		grid-view with [
			size: 500x300
			; grid/pinned: 2x1
			; grid/limits: [x: #[none] y: #[none]]
			; grid/cell-map/(1x2): make-space/name 'button [data: "button1"]
			; grid/cell-map/(2x2): make-space/name 'button  [size: 80x80]
			; grid/cell-map/(1x1): make-space/name 'button [data: "button2"]
			; grid/set-span 1x1 2x2
			; grid/set-span 4x4 2x2
			; grid/set-span/force 2x2 3x2
			; set-span/force 1x1 1x3
			; cell-size: 200x150
			ratio: 1.2
			cell-size: size - 5 / ratio - 5		;-- considers margins/spacing
			grid/widths/default:  cell-size/x
			grid/heights/default: cell-size/y
			; old-cleanup: :grid/draw-ctx/cleanup
			; grid/draw-ctx/cleanup: does [
			; 	if depth <= 2 [old-cleanup]
			; ]
			grid-view: self
			grid/cells: func [/pick xy /size] [
				either pick ['grid-view][1x1 * ratio + 1]
			]
			old-draw: :draw
			draw: function [] [
				r: []
				set 'depth 1 + old: depth
				;-- this gets quite slow to render :)
				;-- depth<=7 even if 4 cells are visible means 4**7=16384 cells! and about ~1G of RAM
				if depth <= max-depth [r: old-draw]
				set 'depth old
				either old = 0 [
					r
				][
					zx: cell-size/x / size/x
					zy: cell-size/y / size/y
					compose/only [scale (zx) (zy) (r)]
				]
			]
		]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x100
	rate 50 on-time [face/rate: none max-depth: 6 b/draw: render b]
] [offset: 10x10]

; gv/grid/draw-ctx/cleanup
; gv/grid/calc-size
; quit
; b/draw: render b

; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]
