Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

;; this fully disables all caching because it's pointless in this case:
;; each invalidation will have to traverse the whole tree, slowing it down significantly
;; (because the same space appears on it thousands of times)
;; and nothing can be cached anyway as all cells are unique and thus form unique branches
#do [disable-space-cache?: yes]

#include %../everything.red

append spaces/keyboard/focusable 'grid-view
;@@ use (wrapped) data!
;@@ make set up grid spaces for common scenarios

; system/view/auto-sync?: no
spaces/ctx/traversal/depth-limit: 4
max-depth: 1											;-- display layout with a smaller depth first
t0: now/precise
view/no-wait/options [
	below
	text 500 center white red font-size 20 "Rendering this should take a while..."
	b: host [
		grid-view with [
			size: 500x300
			; grid/pinned: 2x1
			; grid/bounds: [x: #[none] y: #[none]]
			; cell-size: 200x150
			ratio: 1.2
			cell-size: size - 5 / ratio - 5		;-- considers margins/spacing
			grid/widths/default:  cell-size/x
			grid/heights/default: cell-size/y
			grid-view: self
			grid/cells: func [/pick xy /size] [
				either pick ['grid-view][1x1 * ratio + 1]
			]
			depth: 0
			old-draw: :draw
			draw: function [/extern depth] [
				r: []
				;-- this gets quite slow to render :)
				;-- depth<=7 even if 4 cells are visible means 4**7=16384 cells! and about ~1G of RAM
				if depth < max-depth [
					depth: depth + 1
					r: old-draw
					depth: depth - 1
					if depth > 0 [
						zx: cell-size/x / size/x
						zy: cell-size/y / size/y
						r: compose/only [scale (zx) (zy) (r)]
					]
				]
				r
			]
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x100
	rate 0:0:1 on-time [prof/show prof/reset]
	text hidden rate 50 on-time [						;-- can't set host/rate to none; used to delay full render after layout display
		face/rate: none max-depth: 4 b/draw: render b
	]
] [offset: 10x10]

; b/draw: render b

prof/show
prof/reset
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [print "---"][do-events]
