Red [
	title:   "Layout functions for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ TODO: layouts/ context where all of these should reside; and `layouts/make type` smth to not repeat optimizations

;-- requires export

exports: [layouts]

layouts: context [

	list: none											;-- reserve names
	tube: none

	;@@ TODO: free list of these
	list-layout-ctx: context [
		~: self

		place: function [layout [object!] item [word!]] [	;-- held separately to minimize the size of list-layout itself
			sz: select get item 'size
			#assert [sz]									;-- item must have a size
			guide: select [x 1x0 y 0x1] layout/axis
			cs: layout/content-size
			if 0x0 <> cs [cs: cs + (layout/spacing * guide)]
			ofs: cs * guide + layout/margin + layout/origin
			cs: cs + (sz * guide)
			cs: max cs sz
			layout/content-size: cs
			compose/deep/into [(item) [offset (ofs) size (sz)]] tail layout/map
		]

		set 'list object [
			origin:  0x0			;-- used by list-view
			margin:  0x0
			spacing: 0x0
			axis:    'x

			content-size: 0x0
			size: does [margin * 2 + content-size]
			map: []			;-- accumulated map so far
			place: func [item [word!]] [~/place self item]
		]
	]

	tube-layout-ctx: context [
		~: self

		fill-cache: function [layout [object!]] [
			data: tail layout/raw-map
			y: anchor2axis layout/axes/1
			x: anchor2axis layout/axes/2
			xvec: axis2pair x
			yneg?: find [n w] layout/axes/1
			xneg?: find [n w] layout/axes/2
			#assert [y <> x]								;-- have to be normal to each other
			cs: layout/content-size
			sp: layout/spacing
			maxw: layout/width - (layout/margin/:x * 2)

			cache-names: [data x y cs sp maxw xvec xneg? yneg?]
			reduce/into cache-names layout/cache
		]


		place: function [layout [object!] item [word!]] [
			sz: select get item 'size
			#assert [sz]									;-- item must have a size
			if empty? layout/cache [fill-cache layout]
			set [data: x: y: cs: sp: maxw: xvec: xneg?: yneg?:] layout/cache
			rsz: data/-1									;-- row size accumulated so far
			first?: 0 = rw: rsz/:x							;-- row width accumulated so far
			
			rw: rw + sz/:x
			unless first? [
				rw: rw + sp/:x
				if rw > maxw [								;-- jump to next row if needed
					cs/:y: cs/:y + sp/:y
					data: insert insert/only data copy [] rsz: 0x0
					rw: sz/:x
					first?: yes
				]
			]
			if 0 < added: sz/:y - rsz/:y [cs/:y: cs/:y + added]
			rsz: max rsz sz									;-- update row size
			rsz/:x: rw
			layout/content-size: max data/-1: rsz cs		;-- update content size (x from row-size, y from cs)

			ofs: rsz - sz * xvec
			if yneg? [ofs/:y: 0 - ofs/:y - sz/:y]
			if xneg? [ofs/:x: 0 - ofs/:x - sz/:x]
			reduce/into [data x y cs sp maxw xvec xneg? yneg?] clear layout/cache
			compose/deep/into [(item) [offset (ofs) size (sz)]] tail data/-2
		]

		build-map: function [layout] [
			al: layout/align
			set [data: x: y: cs: sp: maxw: xvec: xneg?: yneg?:] layout/cache
			ox: anchor2pair layout/axes/2
			oy: anchor2pair layout/axes/1
			shift: 0x0
			if ox/:x < 0 [shift/:x: maxw]
			if oy/:y < 0 [shift/:y: cs/:y]
			pos: shift + mg: layout/margin
			move-items: al/2 + 1 / 2
			move-rows:  al/1 + 1 / 2
			r: make [] length? layout/raw-map
			foreach [row row-size] layout/raw-map [
				gap: maxw - row-size/:x						;-- can be negative, still correct
				row-shift: gap * move-rows * ox
				if move-items <> 0 [
					foreach [name geom] row [
						gap: row-size - geom/size * oy
						geom/offset: geom/offset + (move-items * gap)
					]
				]
				foreach [name geom] row [
					geom/offset: geom/offset + pos + row-shift
				]
				append r row
				pos: pos + (sp + row-size * oy)
			]
			r
		]

		size: function [layout [object!]] [
			;-- does not contract size if it's > width
			;-- does not expand it either if some item is > width, otherwise can get this picture:
			;-- [  ] = width
			;-- XXXXXXXXXX
			;-- X X        <- if expanded, these rows will look like they're half filled
			;-- X X           instead, let the big item stick out
			sz: layout/margin * 2 + layout/content-size
			switch layout/axes/1 [
				n s [layout/width by sz/y]
				w e [sz/x by layout/width]
			]
		]

		set 'tube object [
			;-- interface
			width:   100
			; origin:  0x0			;@@ TODO - if needed
			margin:  0x0
			spacing: 0x0
			align:   [-1 -1]		;-- 2 alignments: list within row (-1/0/1), then item within list (-1/0/1)
			axes:    [s e]			;-- default placement order: top-down rows, left-right items

			content-size: 0x0
			place: func [item [word!]] [~/place self item]
			map:   does [~/build-map self]
			size:  does [~/size self]

			;-- used internally
			cache: []				;-- various values used by `place`
			raw-map: [[] 0x0]		;-- accumulated rows and row-sizes so far (make object! copies this deeply)
		]

		#assert [not same? tube/raw-map/1 (first select make tube [] 'raw-map)]
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

]

export exports