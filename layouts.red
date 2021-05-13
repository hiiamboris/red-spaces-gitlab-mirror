Red [
	title:   "Layout functions for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ TODO: free list of these
list-layout-ctx: context [
	place: function [layout [object!] item [word!]] [	;-- held separately to minimize the size of list-layout itself
		sz: select get item 'size
		guide: select [x 1x0 y 0x1] layout/axis
		cs: layout/content-size
		if 0x0 <> cs [cs: cs + (layout/spacing * guide)]
		ofs: cs * guide + layout/margin + layout/origin
		cs: cs + (sz * guide)
		cs: max cs sz
		layout/content-size: cs
		compose/deep/into [(item) [offset (ofs) size (sz)]] tail layout/map
	]

	set 'list-layout object [
		origin: 0x0			;-- used by list-view
		margin: 0x0
		spacing: 0x0
		axis: 'x

		content-size: 0x0
		size: does [margin * 2 + content-size]
		map: []			;-- accumulated map so far
		place: function [item [word!]] [list-layout-ctx/place self item]
	]
]

; row-layout-ctx: context [
; 	place: function [layout [object!] item [pair!]] [
; 		set [ofs: siz: org:] list-layout-ctx/place layout item
; 		guide: select [x 1x0 y 0x1] x: layout/axis
; 		index: (length? layout/items) / 3
; 		if w: layout/widths/:index  [siz/x: w]			;-- enforce size if provided
; 		if h: layout/heights/:index [siz/y: h]
; 		if index > pinned: layout/pinned [				;-- offset and clip unpinned items
; 			either pinned > 0 [
; 				plim: skip items pinned - 1 * 3
; 				lim: plim/1 + plim/2 + layout/spacing * guide
; 			][
; 				lim: 0x0
; 			]
; 			ofs: ofs + (layout/origin * guide)
; 			if ofs/:x < lim/:x [
; 				org: org - dx: (lim - ofs) * guide
; 				siz: max 0x0 siz - dx
; 				ofs/:x: lim/:x
; 			]
; 		]
; 		layout/content-size/:x: ofs/:x + siz/:x - layout/margin/:x
; 		;-- content-size height accounts for all items, even clipped (by design)
; 		reduce/into [ofs siz org] clear skip tail layout/items -3
; 	]

; 	set 'row-layout make list-layout [
; 		origin: 0
; 		pinned: 0
; 		widths: []				;-- can be a map: index -> integer width
; 		heights: []				;-- same

; 		place: function [item [pair!]] [row-layout-ctx/place self item]
; 	]
; ]

