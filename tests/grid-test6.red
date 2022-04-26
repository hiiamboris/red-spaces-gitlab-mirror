Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

{
	22M draw file, 2666 clip commands (~ 100ms spent on clipping)
	<4>      0%      .47   ms       1'877 B [timers]
	<2>      0%     1.03   ms      26'868 B [fps-meter]
	<6>      0%      .167  ms       2'273 B [render]
	<4>     100%  466      ms      17'610 B [drawing]
	<2>      0%     0      ms       1'102 B [zoomer]
	CPU load of profiled code: 100%
}

#include %../everything.red

append spaces/keyboard/focusable 'grid-view
;@@ use (wrapped) data!
;@@ make set up grid spaces for common scenarios

; spaces/templates/cell/margin: 0x0

copy-deep-limit: function [b n] [
	if negative? n: n - 1 [return []]
	b: copy b
	forall b [
		unless block? :b/1 [continue]
		change/only b copy-deep-limit b/1 n
	]
	b
]

spaces/templates/zoomer: make-template 'cell [
	zoom: 1.0
	; pivot: ?
	draw: function [] [
		drawn: render content
		maybe self/size: select get content 'size
		compose/only [
			translate (size / 2)						;-- zoom in effect
			scale (zoom) (zoom)
			translate (size / -2)
			(drawn)
		]
	]
]

; system/view/auto-sync?: no
spaces/ctx/traversal/depth-limit: 4
t0: now/utc/precise
view/no-wait/options [
	below
	host [fps-meter]
	b: host [
		zoomer [
			grid-view with [
				size: 500x300
				; grid/pinned: 2x1
				; grid/bounds: [x: #[none] y: #[none]]
				; grid/cell-map/(1x2): make-space/name 'button [data: "button1"]
				; grid/cell-map/(2x2): make-space/name 'button  [size: 80x80]
				; grid/cell-map/(1x1): make-space/name 'button [data: "button2"]
				; grid/set-span 1x1 2x2
				; grid/set-span 4x4 2x2
				; grid/set-span/force 2x2 3x2
				; set-span/force 1x1 1x3
				ratio: 5
				cell-size: size - (grid/margin * 2) - (ratio - 1 * grid/spacing) / ratio
				grid/widths/default:  cell-size/x
				grid/heights/default: cell-size/y
				grid-view: self
				grid/cells: func [/pick xy /size] [
					either pick ['grid-view][1x1 * ratio + 1]
				]
				set-style 'cell function [cell /on canvas] reshape [
					drawn: cell/draw/on size				;-- constant size to ensure caching
					compose/only [
						fill-pen !(system/view/metrics/colors/panel) box 0x0 (cell-size)
						scale (cell-size/x / size/x) (cell-size/y / size/y) (drawn)
					]
				]
				old-draw: :draw
				;; this calls draw recursively and creates a self-containing draw block
				;; but at the top level it is clipped at certain depth level,
				;; so face/draw receives a truncated draw tree which it is able to render without deadlocking
				;; copying depth has to be adjusted manually to a reasonable amount
				;; depth<=7 even if 4 cells are visible means 4**7=16384 cells! and about ~1G of RAM
				depth: 0
				draw: function [/extern depth] [
					r: []
					if 1 = depth: depth + 1 [				;-- only zoom the topmost grid
						append clear r old-draw
						prof/manual/start 'truncation
						; r: copy-deep-limit r 36
						r: copy-deep-limit r 23
						prof/manual/end 'truncation
					]
					depth: depth - 1
					r
				]
			]
		]
	] rate 99 on-time [
		z: get b/space
		elapsed: to float! difference now/utc/precise t0
		gv: get z/content
		z/zoom: exp (1 * elapsed) // log-e (gv/size/x / gv/cell-size/x)
		invalidate z
		prof/manual/start 'drawing
		b/draw: render b
		prof/manual/end 'drawing
		; unless exists? %drawn.txt [save %drawn.txt b/draw]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x100
	rate 0:0:1 on-time [prof/show prof/reset]
] [offset: 10x10]

prof/show
prof/reset
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]
