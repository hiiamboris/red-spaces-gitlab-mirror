Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

;@@ use (wrapped) data!
;@@ make set up grid spaces for common scenarios

spaces/templates/cell/margin: 0x0

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
spaces/ctx/traversal/depth-limit: 5						;-- doubles fps by lowering event system load on cyclic tree
t0: now/precise
view/no-wait/options [
	below
	b: host [
		vlist [
			fps-meter
			gv: grid-view 500x300 with [
				ratio: 5
				grid/autofit: none
				; cache?: grid/cache?: window/cache?: spaces/templates/cell/cache?: off
				; grid/pinned: 2x1
				; grid/bounds: [x: #[none] y: #[none]]
				grid/set-span 1x1 3x1
				grid/set-span 1x2 2x1
				grid/set-span 4x4 2x1
				grid/set-span 3x5 3x1
				; grid/set-span/force 2x2 3x2
				; set-span/force 1x1 1x3
				; cell-size: 200x150
				cell-size: limits/min - (grid/margin * 2) - (ratio - 1 * grid/spacing) / ratio
				grid/widths/default:  cell-size/x
				grid/heights/default: cell-size/y
				grid-view: self
				data: func [/pick xy /size] [
					either pick [xy][1x1 * ratio + 1]
				]
				old-cells: :grid/cells
				grid/cells: func [/pick xy /size] [			;-- cells picker that injects grid into itself
					case [
						size [old-cells/size]
						ratio / 2 + 1x1 = xy [grid/content/:xy: grid-view]
						'else [old-cells/pick xy]
					]
				]
				old-draw: :draw
				depth: 0
				;; trick: this cell style uses the same canvas size to ensure cache hits
				set-style 'grid/grid-view function [gview] [
					drawn: gview/draw
					compose/only [scale (cell-size/x / max 1 gview/size/x) (cell-size/y / max 1 gview/size/y) (drawn)]
				]
				;; this calls draw recursively and creates a self-containing draw block
				;; but at the top level it is clipped at certain depth level,
				;; so face/draw receives a truncated draw tree which it is able to render without deadlocking
				;; copying depth has to be adjusted manually to a reasonable amount
				draw: function [/on canvas fill-x fill-y /extern depth] [
					r: []
					if 1 = depth: depth + 1 [				;-- only zoom the topmost grid
						append clear r old-draw/on canvas fill-x fill-y
						elapsed: to float! difference now/precise t0
						zx: exp elapsed // log-e (size/x / cell-size/x)
						zy: zx * (size/y / cell-size/y) / (size/x / cell-size/x)
						r: copy-deep-limit
							compose/only/deep [
								clip 0x0 (size) [
									translate (size / 2)		;-- zoom in effect
									scale (zx) (zy)
									translate (size / -2)
									(r)
								]
							]
							; 100
							52
							; 40
							; 28
					]
					depth: depth - 1
					r
				]
			]
		]
	] on-time [invalidate gv]
	on-over [
		status/text: mold hittest face/space event/offset
	]
	status: text 300x100
	rate 0:0:1 on-time [prof/show prof/reset]
] [offset: 10x10]

; dump-tree
prof/show
prof/reset
; debug-draw
; foreach-*ace/next path system/view/screens/1 [probe path]
do-events
