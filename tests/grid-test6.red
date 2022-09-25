Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

{
	Draw is the bottleneck of this test - see #5130
	22M draw file, 2666 clip commands (~30% spent on clipping)
	
	<4>      0%      .47   ms       1'877 B [timers]
	<2>      0%     1.03   ms      26'868 B [fps-meter]
	<6>      0%      .167  ms       2'273 B [render]
	<4>     100%  466      ms      17'610 B [drawing]
	<2>      0%     0      ms       1'102 B [zoomer]
	CPU load of profiled code: 100%
}

; #do [disable-space-cache?: yes] 
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

;@@ is this useful out of the box?
declare-template 'zoomer/cell [
	zoom: [x: 1.0 y: 1.0]
	; pivot: ?
	draw: function [] [
		drawn: render content
		maybe self/size: select get content 'size
		compose/only/deep [
			clip 0x0 (self/size) [
				translate (size / 2)					;-- zoom in effect
				scale (zoom/x) (zoom/y)
				translate (size / -2)
				(drawn)
			]
		]
	]
]

; system/view/auto-sync?: no
spaces/ctx/traversal/depth-limit: 4
t0: now/utc/precise
view/no-wait/options [
	below
	b: host [
		vlist [
			fm: fps-meter								;-- has to be on the same host to invalidate it
			z: zoomer [
				gv: grid-view 500x300 with [
					grid/autofit: none
					; grid/pinned: 2x1
					; grid/bounds: [x: #[none] y: #[none]]
					grid/set-span 6x1 1x5					;-- unify outside cells for more fps
					grid/set-span 1x6 6x1
					; grid/set-span 4x4 2x2
					; grid/set-span/force 2x2 3x2
					; set-span/force 1x1 1x3
					ratio: 5
					cell-size: limits/min - (grid/margin * 2) - (ratio - 1 * grid/spacing) / ratio
					grid/widths/default:  cell-size/x
					grid/heights/default: cell-size/y
					grid-view: self
					grid/cells: func [/pick xy /size] [
						either pick ['grid-view][1x1 * ratio + 1]
					]
					set-style 'grid/grid-view function [gview] reshape [
						drawn: gview/draw
						compose/only [
							fill-pen !(system/view/metrics/colors/panel) box 0x0 (cell-size)
							scale (cell-size/x / gview/size/x) (cell-size/y / gview/size/y) (drawn)
						]
					]
					old-draw: :draw
					;; this calls draw recursively and creates a self-containing draw block
					;; but at the top level it is clipped at certain depth level,
					;; so face/draw receives a truncated draw tree which it is able to render without deadlocking
					;; copying depth has to be adjusted manually to a reasonable amount
					;; with 6x6=36 cells, at depth 2 it becomes 1296 (~40fps), at depth 3 - 46656 cells (~1fps)
					depth: 0
					draw: function [/on canvas /extern depth] [
						r: []
						if 1 = depth: depth + 1 [				;-- only zoom the topmost grid
							append clear r old-draw/on canvas
							prof/manual/start 'truncation
							; r: copy-deep-limit r 33				;-- 3 levels - 15625 grids
							r: copy-deep-limit r 22				;-- 2 levels - 625 grids
							prof/manual/end 'truncation
						]
						depth: depth - 1
						r
					]
				]
			]
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x100
	rate 0:0:1 on-time [prof/show prof/reset]
	text hidden rate 99 on-time [
		elapsed: to float! difference now/utc/precise t0
		z/zoom/x: exp (1 * elapsed) // log-e (gv/size/x / gv/cell-size/x)
		z/zoom/y: z/zoom/x * (gv/size/y / gv/cell-size/y) / (gv/size/x / gv/cell-size/x)
		invalidate z
	]
] [offset: 10x10]
prof/show
prof/reset
; ??~ z
; dump-tree
; debug-draw
either system/build/config/gui-console? [print "---"][do-events]
