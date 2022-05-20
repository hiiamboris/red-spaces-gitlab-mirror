Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

append spaces/keyboard/focusable 'grid-view
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
	host [fps-meter]
	b: host [
		grid-view with [
			size: 500x300
			ratio: 5
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
			cell-size: size - (grid/margin * 2) - (ratio - 1 * grid/spacing) / ratio
			grid/widths/default:  cell-size/x
			grid/heights/default: cell-size/y
			grid-view: self
			data: func [/pick xy /size] [
				either pick [xy][1x1 * ratio + 1]
			]
			old-cells: :grid/cells
			grid/cells: func [/pick xy /size] [			;-- cells picker that injects grid itself
				case [
					size [old-cells/size]
					ratio / 2 + 1x1 = xy ['grid-view]
					'else [old-cells/pick xy]
				]
			]
			old-draw: :draw
			depth: 0
			;; trick: this cell style uses the same canvas size to ensure cache hits
			set-style 'cell function [cell /on canvas] reshape [
				unless grid-view =? get cell/content [
					drawn: cell/draw/on canvas				;-- draw to obtain the size
					return compose/only/deep [
						push [
							fill-pen !(system/view/metrics/colors/panel)
							pen off
							box 0x0 (cell/size)
						]
						(drawn)
					]
				]
				drawn: cell/draw/on size				;-- constant size to ensure caching
				compose/only [scale (cell-size/x / size/x) (cell-size/y / size/y) (drawn)]
			]
			;; this calls draw recursively and creates a self-containing draw block
			;; but at the top level it is clipped at certain depth level,
			;; so face/draw receives a truncated draw tree which it is able to render without deadlocking
			;; copying depth has to be adjusted manually to a reasonable amount
			draw: function [/extern depth] [
				r: []
				if 1 = depth: depth + 1 [				;-- only zoom the topmost grid
					append clear r old-draw
					elapsed: to float! difference now/precise t0
					zx: exp elapsed // log-e (size/x / cell-size/x)
					zy: zx * (size/y / cell-size/y) / (size/x / cell-size/x)
					r: copy-deep-limit
						compose/only [
							translate (size / 2)		;-- zoom in effect
							scale (zx) (zy)
							translate (size / -2)
							(r)
						]
						; 100
						55
						; 40
						; 23
				]
				depth: depth - 1
				r
			]
		]
	] on-time [invalidate b/space b/draw: render b]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x100
	rate 0:0:1 on-time [prof/show prof/reset]
] [offset: 10x10]

; dump-tree
prof/show
prof/reset
; debug-draw
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]
