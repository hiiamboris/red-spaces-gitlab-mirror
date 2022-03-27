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
	row:  none
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
		
		place: function [layout [object!] item [word!]] [
			append layout/items item
		]
		
		build-map: function [layout [object!]] [
			;; to support automatic sizing, each item's constraints has to be analyzed
			;; obviously there can be two strategies:
			;;  1. fill everything with max size, then shrink, and rearrange as possible
			;;  2. fill everything with min size, then expand within a single row
			;;  2nd option seems more predictable and easier to implement
			;; constraint presence does not mean that space can reach that size,
			;; so it should only be used as hint (canvas size) to obtain min size
			;; then, every item that has a nonzero weight has to be rendered twice:
			;; once to get it's minimum appearance, second time to expand it
			;; other items also has to be rendered twice - to fill the row height
			
			;; obtain constraints info
			;@@ info can't be static since render may call another build-map; use block-stack!
			info: make block! length? layout/items
			i: 0 foreach item layout/items [			;@@ use for-each when becomes native
				i: i + 1
				space: get item
				min-size: all [space/limits space/limits/min]	;@@ REP #113
				max-size: all [space/limits space/limits/max]	;@@ REP #113
				;@@ this is inconsistent with list which does NOT render it's items:
				drawn: render/on item min-size			;-- needed to obtain space/size
				#assert [pair? space/size]
				weight: any [select space 'weight 0.0]
				#assert [number? weight]
				available: case [
					weight <= 0  [0]					;-- fixed size
					not max-size [2e9]					;-- unlimited extension possible
					'else [max-size/x - space/size/x / weight]	;@@ REP #113
				]
				append/only info reduce [				;@@ use block stack
					i item space drawn space/size max-size 1.0 * available weight
				]
			]
			
			;; split info into rows
			rows: copy []								;@@ use block-stack
			row:  copy []
			row-size: layout/spacing/x * -1x0			;@@ not gonna work for empty rows
			row-max-width: layout/width - (2 * layout/margin/x)
			; canvas: layout/width - (2 * layout/margin/x) by 2e9		;@@ use canvas ?
			foreach item info [
				set [_: name: _: _: item-size:] item
				new-row-size: as-pair
					row-size/x + item-size/x + layout/spacing/x
					max row-size/y item-size/y
				row-size: either all [					;-- row is full, but has at least 1 item?
					new-row-size/x > row-max-width
					not tail? row
				][
					reduce/into [row-size copy row] tail rows
					clear row
					item-size
				][
					new-row-size
				]
				append/only row item
			]
			reduce/into [row-size row] tail rows
			
			;; expand row items - facilitates a second render cycle of the row
			foreach [row-size row] rows [
				free: row-max-width - row-size/x
				if free > 0 [							;-- any space left to distribute?
					;; free space distribution mechanism relies on continuous resizing!
					;; render itself doesn't have to occupy max-size or the size we allocate to it
					;; and since we don't know what render is up to,
					;; we can only "fix" it by re-rendering until we fill whole row space
					;; but this will be highly inefficient, and not even guaranteed to ever finish
					;; so a proper solution in this case should be to use a custom layout or resize hook
					;@@ this needs to be documented, and maybe another sizing type should be possible: a list of valid sizes
					weights: clear []
					extras:  clear []
					foreach item row [
						append weights item/8
						append extras  item/7
					]
					exts: distribute free weights extras
					
					i: 0 foreach item row [				;@@ should be for-each
						i: i + 1
						set [_: name: space: drawn: item-size: max-size: available: weight:] item
						new-size: item-size/x + exts/:i by row-size/y
						item/4: render/on name new-size
						item/5: space/size				;@@ or use new-size in a map?
					]
				]
			]
			
			map: clear []
			margin:  layout/margin
			spacing: layout/spacing
			row-y: margin/y
			total-length: 0
			foreach [row-size row] rows [
				ofs: margin/x by row-y
				foreach item row [
					set [_: name: space: drawn: item-size: max-size: available: weight:] item
					ofs/y: to integer! row-size/y - item-size/y / 2 + row-y
					geom: reduce ['offset ofs 'size item-size]
					repend map [name geom]
					ofs/x: ofs/x + spacing/x + item-size/x
				]
				total-length: total-length + row-size/y + spacing/y
				row-y: margin/y + total-length
			]
			total-length: total-length - spacing/y
			layout/content-size: row-max-width by total-length
			layout/size: 2x2 * margin + layout/content-size
			copy map
		]

		; size: function [layout [object!]] [
			; ;-- does not contract size if it's > width
			; ;-- does not expand it either if some item is > width, otherwise can get this picture:
			; ;-- [  ] = width
			; ;-- XXXXXXXXXX
			; ;-- X X        <- if expanded, these rows will look like they're half filled
			; ;-- X X           instead, let the big item stick out
			; sz: layout/margin * 2 + layout/content-size
			; switch layout/axes/1 [
				; n s [layout/width by sz/y]
				; w e [sz/x by layout/width]
			; ]
		; ]

		set 'tube object [
			;-- interface
			width:   100			;@@ TODO: use canvas instead?
			; origin:  0x0			;@@ TODO - if needed
			margin:  0x0
			spacing: 0x0
			align:   [-1 -1]		;-- 2 alignments: list within row (-1/0/1), then item within list (-1/0/1)
			axes:    [s e]			;-- default placement order: top-down rows, left-right items

			content-size: 0x0
			place: func [item [word!]] [~/place self item]
			map:   does [~/build-map self]
			size:  0x0

			;-- used internally
			items: []
		]
	]

	row-layout-ctx: make tube-layout-ctx [
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

		set 'row object [
			origin:  0x0			;-- used by list-view
			margin:  0x0
			spacing: 0x0
			axis:    'x				;-- vast majority of rows will be X-rows
			divisable?: yes			;-- whether it can split into 2 or more rows when tight on space

			content-size: 0x0
			size: does [margin * 2 + content-size]
			map: []			;-- accumulated map so far
			place: func [item [word!]] [~/place self item]
		]
	]

]

export exports