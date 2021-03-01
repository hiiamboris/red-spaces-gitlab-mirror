Red [
	title:   "Draw-based widgets (Spaces) definitions"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires `for` loop from auxi.red


;@@ TODO: also a `spaces` context to wrap everything, to save it from being overridden (or other name, or under system/)


;@@ rename to standard-spaces ?

make-space: function [
	"Create a space from a template TYPE"
	type [word!]  "Looked up in spaces"	;@@ TODO: need an encompassing namespace for everything
	spec [block!] "Extension code"
	/block "Do not instantiate the object"
	/name "Return a word referring to the space, rather than space object"
][
	base: spaces/:type
	#assert [block? base]
	r: append copy/deep base spec
	unless block [r: object r]
	if name [r: anonymize type r]
	r
]

;-- helps having less boilerplate when `map` is straightforward
compose-map: function [
	"Build a Draw block from MAP"
	map "List of [space-name [offset XxY size XxY] ...]"
	/only list [block!] "Select which spaces to include"
][
	r: make [] 10
	foreach [name box] map [
		all [only  not find list name  continue]		;-- skip names not in the list if it's provided
		cmds: render name
		unless empty? cmds [							;-- don't spawn empty translate/clip structures
			compose/deep/only/into [
				translate (box/offset) [
					clip 0x0 (box/size) (cmds)
				]
			] tail r
		]
	]
	r
]


spaces: #()												;-- map for extensibility

spaces/space: [											;-- minimum basis to build upon
	draw: []
	size: 0x0
]
space?: func [obj] [all [object? :obj  in obj 'draw  in obj 'size]]

spaces/rectangle: make-space/block 'space [
	size: 20x10
	margin: 0
	draw: func [] [compose [box (margin * 1x1) (size - margin)]]
]

spaces/triangle: make-space/block 'space [
	size: 16x10
	dir: 'n
	margin: 0
	;@@ need `into` here? or triangle will be a box from the clicking perspective?
	draw: function [] [
		set [p1: p2: p3:] select [
			n [0x2 1x0 2x2]								;--   n
			e [0x0 2x1 0x2]								;-- w   e
			w [2x0 0x1 2x2]								;--   s
			s [0x0 1x2 2x0]
		] dir
		m: margin * 1x1
		r: size / 2 - m
		compose/deep [
			translate (m) [triangle (p1 * r) (p2 * r) (p3 * r)]
		]
	]
]

;@@ TODO: externalize all functions, make them shared rather than per-object
scrollbar: context [
	spaces/scrollbar: make-space/block 'space [
		size: 100x16										;-- opposite axis defines thickness
		axis: 'x
		offset: 0%
		amount: 100%
		;@@ TODO: `init-map` func that fills all these from spaces found in the object!
		;@@ and document what a map is and how to create it manually or using init-map
		map: [												;-- clickable areas:
			back-arrow  [offset 0x0 size 0x0]				;-- go back a step
			back-page   [offset 0x0 size 0x0]				;-- go back a page
			thumb       [offset 0x0 size 0x0]				;-- draggable
			forth-page  [offset 0x0 size 0x0]				;-- go forth a page
			forth-arrow [offset 0x0 size 0x0]				;-- go forth a step
		]
		back-arrow:  make-space 'triangle  [margin: 2  dir: 'w]
		back-page:   make-space 'rectangle [draw: []]
		thumb:       make-space 'rectangle [margin: 2x1]
		forth-page:  make-space 'rectangle [draw: []]
		forth-arrow: make-space 'triangle  [margin: 2  dir: 'e]
		into: func [xy [pair!] /force name] [
			any [axis = 'x  xy: reverse xy]
			into-map map xy name
		]
		;@@ TODO: styling/external renderer
		draw: function [] [
			size2: either axis = 'x [size][reverse size]
			h: size2/y  w-full: size2/x
			w-arrow: to 1 size2/y * 0.9
			w-inner: w-full - (2 * w-arrow)
			;-- in case size is too tight to fit the scrollbar - compress inner first, arrows next
			if w-inner < 0 [w-arrow: to 1 w-full / 2  w-inner: 0]
			w-thumb: max h w-inner * amount			;-- thumb shouldn't become too thin to aim at
			w-pgup:  w-inner - w-thumb + (w-inner * amount) * offset
			w-pgdn:  w-inner - w-pgup - w-thumb
			map/back-arrow/size:  back-arrow/size:   sz: as-pair w-arrow h
			map/back-page/offset: o: sz * 1x0		;@@ TODO: this space filling algorithm can be externalized probably
			map/back-page/size:   back-page/size:    sz: as-pair w-pgup  h
			map/thumb/offset:     o: sz * 1x0 + o
			map/thumb/size:       thumb/size:        sz: as-pair w-thumb h
			map/forth-page/offset:   sz * 1x0 + o
			map/forth-page/size:  forth-page/size:   sz: as-pair w-inner - w-thumb - w-pgup h	;-- compensates for previous rounding errors
			map/forth-arrow/offset:  w-full - w-arrow * 1x0		;-- arrows should stick to sides even for uneven sizes
			map/forth-arrow/size: forth-arrow/size:  as-pair w-arrow h
			compose/deep [
				push [
					matrix [(select [x [1 0 0 1] y [0 1 1 0]] axis) 0 0]
					(compose-map map)
				]
			]
		]
	]
]

;@@ rename this to just `scrollable`?
scrollable-space: context [
	;@@ or /line /page /forth /back /x /y ?
	;@@ TODO: less awkward spec
	move-by: function [spc amnt "'line or 'page or offset in px" dir "forth or back" axis "x or y" /scale factor "1 by default"] [
		if word? spc [spc: get spc]
		dir:  select [forth 1 back -1] dir
		unit: select [x 1x0 y 0x1] axis
		default factor: 1
		switch amnt [line [amnt: 10] page [amnt: spc/map/(spc/content)/size]]
		spc/origin: spc/origin - (amnt * factor * unit * dir)
	]

	move-to: function [
		"ensure point XY of content is visible, scroll only if required"
		spc [object!] xy [pair! word!] "offset or: head, tail"
		/margin "how much space to reserve around XY" mrg [integer! pair!] "default: 0"
	][
		if word? spc [spc: get spc]
		mrg: 1x1 * any [mrg 0]
		cspace: get cname: spc/content
		csize: cspace/size
		switch xy [
			head [xy: 0x0]
			tail [xy: csize * 0x1]				;-- no right answer here, csize or csize*0x1
		]
		box: spc/map/:cname/size
		mrg: min mrg box - 1 / 2				;-- at least 1 pixel should be between margins or this fails
		xy1: mrg - spc/origin
		xy2: xy1 + box - mrg
		dxy: 0x0
		foreach x [x y] [
			dxy/:x: xy/:x - case [
				xy1/:x <  xy/:x [xy1/:x]
				xy2/:x >= xy/:x [xy2/:x]
				'else           [xy/:x]
			]
		]
		maybe spc/origin: spc/origin - dxy
	]

	;@@ TODO: just moving content around could be faster than rebuilding draw block when scrolling
	;@@ although how to guarantee that it *can* be cached?
	spaces/scrollable: make-space/block 'space [
		origin: 0x0					;-- at which point `content` to place: >0 to right below, <0 to left above
		content: make-space/name 'space []			;-- should be defined (overwritten) by the user
		hscroll: make-space 'scrollbar [axis: 'x]
		vscroll: make-space 'scrollbar [axis: 'y size: reverse size]
		rate: 16					;-- how often it scrolls when user presses & holds one of the arrows
		map: compose [
			(content) [offset 0x0 size 0x0]
			hscroll   [offset 0x0 size 0x0]
			vscroll   [offset 0x0 size 0x0]
		]

		into: function [xy [pair!] /force name [word!]] [
			if r: into-map map xy name [
				if r/1 =? content [
					cspace: get content
					r/2: r/2 - origin
					unless any [force  within? r/2 0x0 cspace/size] [r: none]
				]
			]
			r
		]

		draw: function [] [
			box: size					;-- area of 'size' unobstructed by scrollbars
			cspace: get map/1: content
			cdraw:
				render/only content		;-- render it before 'size' can be obtained
					max 0x0 0x0 - origin
					box - origin
			csz: cspace/size
			p2: csz + p1: origin
			full: max 1x1 csz + (max 0x0 origin)
			clip-p1: max 0x0 p1
			loop 2 [					;-- each scrollbar affects another's visibility
				clip-p2: min box p2
				shown: min 100x100 (clip-p2 - clip-p1) * 100 / max 1x1 csz
				if hdraw?: shown/x < 100 [box/y: size/y - hscroll/size/y]
				if vdraw?: shown/y < 100 [box/x: size/x - vscroll/size/x]
			]
			hscroll/offset: 100% * (clip-p1/x - p1/x) / max 1 csz/x
			vscroll/offset: 100% * (clip-p1/y - p1/y) / max 1 csz/y
			hscroll/amount: min 100% 100% * box/x / full/x
			vscroll/amount: min 100% 100% * box/y / full/y
			;@@ TODO: fast flexible tight layout func to build map? or will slow down?
			map/:content/size: box
			map/hscroll/offset: box * 0x1
			map/vscroll/offset: box * 1x0
			hscroll/size/x: either hdraw? [box/x][0]
			vscroll/size/y: either vdraw? [box/y][0]
			map/hscroll/size: hscroll/size
			map/vscroll/size: vscroll/size
			compose/deep/only [
				translate (origin) [						;-- special geometry for content
					clip (0x0 - origin) (box - origin)
					(cdraw)
				]
				(compose-map/only map [hscroll vscroll])
			]
		]

		on-change*: function [word old [any-type!] new [any-type!]] [	;@@ clip origin here or clip inside event handler? box isn't valid until draw is called..
			; print [mold word mold :old "->" mold :new]
			switch to word! word [						;-- sometimes it's a set-word
				;@@ problem: changing origin requires up to date content (no sync guarantee)
				;@@ maybe we shouldn't clip it right here?
				origin [
					if all [pair? :new  word? content] [
						cspace: get content
						set-quiet 'origin min 0x0 max (map/:content/size - cspace/size) new
					]
				]
				content [map/1: new]
			]
		]
	]
]

paragraph-ctx: context [
	;-- every `make font!` brings View closer to it's demise, so it have to use a shared font
	;@@ BUG: not deeply reactive
	shared-font: make font! [name: system/view/fonts/sans-serif size: system/view/fonts/size]

	spaces/paragraph: make-space/block 'space [
		size: none				;-- only valid after `draw` because it applies styles
		text: ""
		margin: 0x0				;-- default = no margin
		font: none				;-- can be set in style, as well as margin
		width: 100				;-- wrap margin; set to none to disable wrap

		layout: none			;-- internal
		;@@ font won't be recreated on `make paragraph!`, but must be careful
		lay-out: does [
			unless layout [layout: rtd-layout [""]]
			layout/text: text
			layout/font: font							;@@ careful: fonts are not collected by GC, may run out of them easily
			either width [								;-- wrap
				layout/size/x: width						;-- width has to be set to determine height
				; layout/size: size-text layout		;@@ BUG #4783		;-- 'size-text' is slow, has to be cached (by setting size)
				layout/size/y: second size-text layout		;-- 'size-text' is slow, has to be cached (by using on-change)
			][											;-- no wrap
				layout/size: none
				layout/size: size-text layout
			]
		]

		draw: function [] [
			unless layout [lay-out]
			self/size: margin * 2 + layout/size
			compose [text (margin) (layout)]
		]

		on-change*: func [word old [any-type!] new [any-type!]] [
			all [
				find [text width font] word				;-- words affecting layout
				not :old =? :new						;-- useful to shorten `font:` change in styles ;@@ though not helpful when forcing update after on-deep-change ;@@ use on-deep-change?
				layout: none
			]
		]
	]
]


;@@ TODO: free list of these
list-layout-ctx: context [
	place: function [layout [object!] item [pair!]] [
		guide: select [x 1x0 y 0x1] layout/axis
		cs: layout/content-size
		if 0x0 <> cs [cs: cs + (layout/spacing * guide)]
		ofs: cs * guide + layout/margin
		cs: cs + (item * guide)
		cs: max cs item
		layout/content-size: cs
		reduce/into [ofs item 0x0] tail layout/items
	]

	set 'list-layout object [
		margin: 0x0
		spacing: 0x0
		axis: 'x

		content-size: 0x0
		size: does [margin * 2 + content-size]
		items: []			;-- list of: [offset size origin] for each item
		place: function [item [pair!]] [list-layout-ctx/place self item]
	]
]

row-layout-ctx: context [
	place: function [layout [object!] item [pair!]] [
		set [ofs: siz: org:] list-layout-ctx/place layout item
		guide: select [x 1x0 y 0x1] x: layout/axis
		index: (length? layout/items) / 3
		if w: layout/widths/:index  [siz/x: w]			;-- enforce size if provided
		if h: layout/heights/:index [siz/y: h]
		if index > pinned: layout/pinned [				;-- offset and clip unpinned items
			either pinned > 0 [
				plim: skip items pinned - 1 * 3
				lim: plim/1 + plim/2 + layout/spacing * guide
			][
				lim: 0x0
			]
			ofs: ofs + (layout/origin * guide)
			if ofs/:x < lim/:x [
				org: org - dx: (lim - ofs) * guide
				siz: max 0x0 siz - dx
				ofs/:x: lim/:x
			]
		]
		layout/content-size/:x: ofs/:x + siz/:x - layout/margin/:x
		;-- content-size height accounts for all items, even clipped (by design)
		reduce/into [ofs siz org] clear skip tail layout/items -3
	]

	set 'row-layout make list-layout [
		origin: 0
		pinned: 0
		widths: []				;-- can be a map: index -> integer width
		heights: []				;-- same

		place: function [item [pair!]] [row-layout-ctx/place self item]
	]
]

;@@ `list` is too common name - easily get overridden and bugs ahoy
list-ctx: context [
	spaces/list: make-space/block 'space [
		size: none				;-- only available after `draw` because it applies styles
		items: []				;-- user-controlled
		axis: 'x
		margin: 5x5
		spacing: 5x5
		;@@ TODO: alignment?
		;@@ this requires /size caching - ensure it is cached (e.g. as `content` which is generic and may be a list)
		;@@ or use on-deep-change to update size - what will incur less recalculations?
		;@@ TODO: margin & spacing - in style??
		;@@ TODO: appendable-list? smth that caches items' size so append is fast
		map: []

		draw: function [/only xy1 xy2 /layout lobj [object!]] [
			;@@ keep this in sync with `grid/draw`
			r: make [] 10
			unless layout: lobj [
				layout: make list-layout []
				layout/axis:    axis
				layout/margin:  margin
				layout/spacing: spacing
			]
			clear map
			foreach name items [
				item: get name
				drawn: unless item/size [render name]		;-- prerender to get the size
				set [p1: siz: org:] layout/place item/size
				isec: siz									;-- intersection size (siz can be zero initially)
				if only [isec: (min p1 + siz xy2) - (max p1 xy1)]
				unless skip?: isec <> max isec 1x1 [		;-- optimized `any [isec/x <= 0 isec/y <= 0]`
					;@@ TODO: style selected-item?
					compose/deep/only/into [clip (p1) (p1 + siz) [translate (p1 + org) (any [drawn  render name])]] r
					compose/deep/into [(name) [offset (p1) size (siz)]] tail map
				]
			]
			self/size: layout/size
			r
		]
	]
]



;-- a polymorphic style: given `data` creates a visual representation of it
;@@ TODO: complex types should leverage table style
spaces/data-view: make-space/block 'space [
	size:    none					;-- only available after `draw` because it applies styles
	data:    none					;-- ANY red value
	width:   none					;-- when set, forces output to have fixed width (can be a list)
	margin:  0x0
	spacing: 2x2					;-- used only when data is a block
	limits:  [						;-- min/max size that this space can span
		min [x #[none] y #[none]]	;-- x/y are split so one can be enforced, while another can be free
		max [x #[none] y #[none]]
	]

	content: none
	map: []
	valid?: no						;-- can be reset without losing content so content can be reused
	invalidate: does [set-quiet 'valid? no]

	set-content: function [] [
		case [
			; image! []	;@@ TODO - need image type
			block? :data [								;-- only recreates item spaces as necessary
				unless content = 'list [set-quiet 'content make-space/name 'list []]
				list: get content
				maybe list/margin: 0x0					;-- fit the list contents tightly, as we already have a margin
				maybe list/spacing: spacing
				n: length? data
				;-- evenly distribute the items	only when width is fixed:  ;@@ any better idea??
				;@@ also how to or should we apply width to images?
				item-width: all [width  to 1 width - (n - 1 * spacing/x) - (2 * margin/x) / n]
				repeat i n [
					value: :data/:i
					unless item: list/items/:i [
						append list/items item: anonymize 'item make-space 'data-view []
					]
					item: get item
					maybe item/width: item-width
					set/any 'item/data :value
					item/set-content
				]
				clear skip list/items n
			]
			'else [
				text: either string? :data [copy data][mold :data]		;@@ limit it or not?
				unless content = 'paragraph [set-quiet 'content make-space/name 'paragraph []]
				para: get content
				maybe para/width: width
				maybe para/text: text
			]
		]
		set-quiet 'valid? yes
	]

	draw: function [] [
		unless valid? [set-content]
		obj: get content
		cdraw: render content				;-- apply style to get the size
		sz: margin * 2 + obj/size
		case/all [
			lim: limits/min/x [sz/x: max lim sz/x]
			lim: limits/min/y [sz/y: max lim sz/y]
			lim: limits/max/x [sz/x: min lim sz/x]
			lim: limits/max/y [sz/y: min lim sz/y]
		]
		self/size: sz
		change/only change map content compose [offset: (margin) size: (sz - margin)]
		compose/deep/only [
			clip 0x0 (sz) [				;@@ clipping should be done automatically somewhere for all spaces
				translate (margin) (cdraw)
			]
		]
	]
	
	on-change*: function [word old [any-type!] new [any-type!]] [
		all [
			find [data width] word
			not :old =? :new
			invalidate
		]
	]
]



;@@ TODO: chat will need reverse indexing... though how about `source` function gets -1 -2 -3 ... ?
;-- there's a lot of logic in this space only to make it fast
;-- list items may vary in size, and not knowing the size of each item
;-- we can't just multiply the index by some number, we have to traverse the whole list
;-- but list can be huge, and all these functions try to minimize the size estimation effort
list-view-ctx: context [
	spaces/list-view: make-space/block 'scrollable [
		source: []		;@@ or a function [index]? or support both?
		data: function [/pick i [integer!] /length] [
			either pick [source/:i][length? source]
		]
		index: 1										;-- index of the first item within source
		;-- geometric constraints:
		;-- * it will display at least 1 item but no more than max-items
		;-- * it will drop items starting after max-length along the axis
		;-- setting max-length to big enough value makes list size constant = max-items
		;-- big enough max-items makes list always show all of the items
		max-items:   200
		max-length:  10000
		jump-length: 100								;-- how much more to show when rolling (px)
		look-around: 50									;-- zone after begin and before tail that triggers roll-edge (px)
		timer: make-space 'space [rate: 4]				;-- how often to call roll-edge when dragging (can't override scrollable/rate)
		list:  make-space 'list [axis: 'y]				;-- list/axis can be changed to get a horizontal list
		content: 'list
		;@@ TODO: on-change or assertions should ensure max-items >= 1, and sane values for the rest

		append map [timer [offset 0x0 size 0x0]]		;@@ any better way to have a separate rate?

		filled?: no										;-- true when items are cached
		invalidate: does [set-quiet 'filled? no]		;-- call this to force items update

		wrap-item: function [item-data [any-type!]][
			spc: make-space 'data-view []
			set/any 'spc/data :item-data
			if list/axis = 'y [spc/width: size/x - (list/margin/x * 2)]		;@@ what data width to use for horizontal lists?
			anonymize 'item spc
		]

		scrollable-draw: :draw
		draw: function [] [
			any [filled? fill-items]
			scrollable-draw
		]
		
		add-items: function [
			"Insert items into list from position WHERE"
			where [word!] "head, tail or over"
			ext-len [integer!] "Min extension length in pixels (if enough available)"
			/local idata
		][
			x:         list/axis
			spc:       list/spacing/:x
			items:     list/items
			new:       clear []
			target:    either where = 'over [items][new]
			offset:    switch where [tail [index - 1 + length? items] over [index - 1] head [index]]
			available: either where = 'head [index - 1][data/length - offset]
			if 0 = available [return [0 0]]						;-- optimization
			;@@ it should not know list's internal spacing logic (in case we change the list).. but how?
			added-len: either empty? items [list/margin/:x * 2 - spc][0]
			+-:        either where = 'head [:-][:+]
			repeat i min max-items available [
				set/any 'idata data/pick offset +- i
				either item: target/:i [
					#assert [in get item 'data  "item should have a /data facet to be used in list-view"]
					set/any in get item 'data :idata
				][
					change at target i item: wrap-item :idata
				]
				item: get item
				unless item/size [render 'item]					;-- render it to get the size
				added-len: added-len + spc + item/size/:x
				if added-len >= ext-len [break]
			]
			added-num: any [i 0]
			switch where [
				head [insert items reverse new]
				tail [append items new]
				over [clear skip items added-num]
			]
			reduce [added-num added-len]
		]

		cut-items: function [
			"Remove items until list size is within constraints"
			where [word!] "head or tail"
			limit [integer!] "Enforce min number of items to keep"
		][
			items: list/items
			num1: length? items
			size: list/size
			x: list/axis
			len2: len1: size/:x
			; #assert [max-items >= limit]		;-- min shouldn't be bigger than max
			min-rem: num1 - max-items					;-- num items over max-items
			pick-item: select [head [first items] tail [last items]] where
			rem-item:  select [head [take items]  tail [take/last items]] where
			repeat i num1 - limit [
				item: get do pick-item
				item-size: item/size
				len3: len2 - item-size/:x - (list/spacing/:x)
				all [len3 < max-length  i >= min-rem  break]	;-- check if after removal list will be too short
				do rem-item
				len2: len3
			]
			num2: length? items
			reduce [num1 - num2  len1 - len2]
		]

		at-head?: does [(0 - origin/(list/axis)) <= look-around]
		at-tail?: function [] [
			x:     list/axis
			csize: list/size
			max-origin: csize/:x - map/list/size/:x
			(0 - origin/:x) >= (max-origin - look-around)
		]

		roll-edge: function [
			"Move position of ITEMS within DATA if origin has approached one of the edges"
			/head "Force adding items at the head"
			/tail "Force adding items at the tail"
			; return: [logic!]							;-- whether actually refilled or not
		][
			unless any [head tail] [head: at-head?  tail: at-tail?]
			if all [tail head] [return no]				;-- empty list or less than the viewport
			case [
				head [
					set [add-n: add-len:] add-items 'head jump-length
					cut-items 'tail add-n
					self/origin: origin - (add-len * 0x1)
					set-quiet 'index index - add-n
				]
				tail [
					set [added:] add-items 'tail jump-length
					set [cut-n: cut-len:] cut-items 'head added
					self/origin: origin + (cut-len * 0x1)
					;@@ BUG: we should trigger on-change/index so it can be detected by other spaces
					;@@ OTOH if we do, we cause another add-items/over call and lose the added items
					;@@ so how to solve this?
					set-quiet 'index index + cut-n
				]
				'else [return no]
			]
			yes
		]

		fill-items: does [
			add-items 'over max-length
			set-quiet 'filled? yes
		]

		;-- when to fill?
		;-- - width changes => new length
		;-- - text of one of the items changes => new length -- can't track this automatically
		;-- - source index changes => new content for each item
		scrollable-on-change*: :on-change*
		on-change*: function [word [word! set-word!] old [any-type!] new [any-type!]] [
			scrollable-on-change* word :old :new
			if find [source width index] word [invalidate]
		]
	]
]

;@@ TODO: list-view of SPACES?  simple layout-ers?  like grid..?

; spacer: make-space 'space [				;-- empty space, used for padding
; 	draw: []
; ]

button-ctx: context [
	spaces/button: make-space/block 'data-view [
		margin: 4x4								;-- change data-view's default
		pushed?: no								;-- becomes true when user pushes it
		rounding: 0								;-- box rounding radius in px
		command: []								;-- code to run on click (on up)

		data-view-draw: :draw
		draw: function [] [
			drawn: data-view-draw				;-- draw content before we know it's size
			self/size: margin * 2 + size
			;-- box has to come before the content, so whatever fill-pen is used by style it won't override the text
			compose/deep/only [
				; clip 0x0 (size) [				;@@ NOT WORKING - #4824
					box 0x0 (size) (rounding)
				; ]
				translate (margin) (drawn)
			]
		]
	]
]


table-ctx: context [
	;@@ TODO: func to automatically balance column widths to minimize table height
	; balance: function [] 

	spaces/table-row: make-space/block 'list [
		spacing: 4x3
		margin: 0x0
		data: none
		table: none				;-- should be set by the table

		;@@ TODO: unify this with data-view block variant somehow
		fill: function [] [
			#assert [block? data]
			n: length? data
			repeat i n [
				value: :data/:i
				unless item: items/:i [
					append items item: anonymize 'item make-space 'data-view []
				]
				item: get item
				maybe item/width: table/widths/:i
				set/any 'item/data :value
				item/set-content
			]
			clear skip items n
		]

		list-draw: :draw
		draw: function [] [
			fill		;@@ TODO: caching
			layout: make row-layout [
				pinned: table/pinned/x
				widths: table/widths
				axis: 'x
			]
			layout/margin: margin		;@@ TODO: auto-copy somehow
			layout/spacing: spacing
			list-draw/layout layout
		]
	]

	;@@ TODO: spacers between pinned and not pinned data
	spaces/table: make-space/block 'list [
		pinned: 0x1							;-- pinned columns x rows (headers)
		margin: 0x0	
		data-columns: [1 2]					;-- indexes of visible DATA columns in the order of appearance
		widths: #(1 100 2 100)				;-- data column index -> it's visible width
		axis: 'y

		source: []										;-- block of blocks or a function returning one
		;-- user can override `data` for more complex `source` layouts support
		data: function [/pick x [integer!] y [integer!] /size] [
			s: source									;-- eval in case it's a function
			case [
				pick [if row: s/:y [row/:x]]			;-- s/:y can be `none`
				empty? s [0x0]
				'else [
					#assert [block? s/1]
					as-pair  length? s/1  length? s
				]
			]
		]

		prep-data-row: function [
			"preps data row for display, independent of `source` format"
			y [integer!]
		][
			dsize: data/size
			if any [y <= 0  y > dsize/y] [return none]	;-- out of data limits case
			ncol: length? data-columns
			if 0 = ncol [return []]						;-- empty row case (no allocation needed)

			;@@ TODO: make a free list of blocks for this
			r: make [] ncol
			repeat x ncol [append/only r data/pick data-columns/:x y]	;@@ should be map-each, but it's slow
			r
		]

		headers: make-space 'list-view [hscroll/size/y: 0]
		columns: make-space 'list-view []
		headers/data: func [/pick i /length] [
			either pick
				[prep-data-row i]
				[min pinned/y second data/size]
		]
		columns/data: func [/pick i /length] [
			either pick
				[prep-data-row i + pinned/y]
				[max 0 (second data/size) - pinned/y]
		]
		headers/wrap-item:
		columns/wrap-item: function [item-data [block!]] [
			anonymize 'row make-space 'table-row compose/only [table: (self) data: (item-data)]
		]

		items: [headers columns]

		list-draw: :draw
		draw: function [] [
			maybe headers/origin: as-pair columns/origin/x headers/origin/y	;-- sync origin/x
			; headers-list/invalidate
			; columns-list/invalidate
			render 'headers
			render 'columns
			;-- don't let headers occupy more than half of height
			maybe headers/size: min headers/list/size size / 1x2 - (margin * 2x1)
			maybe columns/size: size - (headers/size * 0x1) - (margin * 2x2) - (spacing * 0x1)
			list-draw
		]

		;@@ do this as a function called inside draw!
		; on-change*: function [word old [any-type!] new [any-type!]] [
		; 	if word = 'dimensions [						;-- automatically show just added columns
		; 		#assert [pair? :old]
		; 		#assert [pair? :new]
		; 		set-quiet 'columns union columns rng: range old/x new/x
		; 		foreach i rng [widths/:i: 100]			;@@ externalize the default width?
		; 	]
		; ]
	]
]

spaces/rotor: make-space/block 'space [
	content: none
	angle: 0

	ring: make-space 'space [size: 360x10]
	;@@ TODO: zoom for round spaces like spiral

	map: [							;-- unused, required only to tell space iterators there's inner faces
		ring ring					;-- 1st = placeholder for `content` (see `draw`)
	]

	into: function [xy [pair!] /force name [word! none!]] [
		unless content [return none]
		spc: get content
		r1: to 1 spc/size/x ** 2 + (spc/size/y ** 2) / 4 ** 0.5
		r2: r1 + 10
		c: cosine angle  s: sine angle
		p0: p: xy - (size / 2)
		p: as-pair  p/x * c - (p/y * s)  p/x * s + (p/y * c)	;-- rotate the coordinates
		xy: p + (size / 2)
		xy1: size - spc/size / 2
		if any [name = content  within? xy xy1 spc/size] [
			return reduce [content xy - xy1]
		]
		r: p/x ** 2 + (p/y ** 2) ** 0.5
		a: (arctangent2 0 - p0/y p0/x) // 360					;-- ring itself does not rotate
		if any [name = 'ring  all [r1 <= r r <= r2]] [
			return reduce ['ring  as-pair a r2 - r]
		]
		none
	]

	draw: function [] [
		unless content [return []]
		map/1: content				;-- expose actual name of inner face to iterators
		spc: get content
		drawn: render content		;-- render before reading the size
		r1: to 1 spc/size/x ** 2 + (spc/size/y ** 2) / 4 ** 0.5
		self/size: r1 + 10 * 2x2
		compose/deep/only [
			push [
				line-width 10
				translate (size / 2)
				rotate (0 - angle)
				(collect [
					repeat i 5 [
						keep compose [arc 0x0 (r1 + 5 * 1x1) (a: i * 72 - 24 - 90) 48]
					]
				])
				; circle (size / 2) (r1 + 5)
			]
			translate (size - spc/size / 2) [
				rotate (0 - angle) (spc/size / 2)
				(drawn)
			]
		]
	]
]


;@@ TODO: can I make `frame` some kind of embedded space into where applicable? or a container? so I can change frames globally in one go
spaces/field: make-space/block 'scrollable [
	text: ""
	selected: none		;@@ TODO
	caret-index: 0		;-- should be kept even when not focused, so tabbing in leaves us where we were
	caret-width: 1		;-- in px
	size: 100x25		;@@ good enough idea or not?
	para: make-space 'paragraph []
	caret: make-space 'rectangle []		;-- caret has to be a separate space so it can be styled
	content: 'para
	wrap?: no
	active?: no			;-- whether it should react to keyboard input or pass thru (set on click, Enter)
	;@@ TODO: render caret only when focused
	;@@ TODO: auto scrolling when caret is outside the viewport
	invalidate: does [para/layout: none]		;@@ TODO: use on-deep-change to watch `text`??

	draw: function [] [
		maybe para/width: if wrap? [size/x]
		maybe para/text: text
		pdrawn: para/draw
		xy1: caret-to-offset       para/layout caret-index + 1
		xy2: caret-to-offset/lower para/layout caret-index + 1
		caret/size: as-pair caret-width xy2/y - xy1/y
		cdrawn: []
		if active? [
			cdrawn: compose/only [translate (xy1) (caret/draw)]
		]
		compose [(cdrawn) (pdrawn)]
	]
]

spaces/spiral: make-space/block 'space [
	size: 100x100
	content: 'field			;-- reuse field to apply it's event handlers
	field: make-space 'field [size: 999999999x9999]		;-- it's infinite

	into: func [xy [pair!] /force name] [
		;@@ TODO: unify this with `draw` code somehow
		r: field/para/layout
		#assert [r]

		len: length? text: field/text
		if empty? text [return none]		;-- case of empty string
		full: caret-to-offset/lower r len	;-- full size: line height and average char width
		p: size / 2 * 0x-1					;-- start at upper center
		decay: (p/y + full/y) / p/y			;-- orbit decay per cycle (< 1)
		rmax: absolute p/y					;-- outer radius
		rmid: full/y / -2 + absolute p/y	;-- radius of the middle line of the string
		wavg: full/x / len					;-- average char width
		p: p - (wavg / 2)					;-- offset the typesetter to center the average char

		;@@ TODO: initial angle
		xy: xy - (size / 2)
		rad: xy/x ** 2 + (xy/y ** 2) ** 0.5
		angle: 90 + arctangent2 xy/y xy/x
		correction: decay ** (angle / 360)
		cycles: attempt [to 1 (log-e rad / rmax / correction) / log-e decay]
		unless cycles [return none]			;-- math failed :(
		cycles: cycles + (angle / 360)
		length: cycles * 2 * pi * rmid
		reduce ['field as-pair length 1]
	]

	draw: function [] [
		maybe field/para/width: none		;-- disable wrap
		maybe field/para/text: field/text
		unless r: field/para/layout [
			field/para/lay-out
			r: field/para/layout
			#assert [r]
		]

		len: length? text: field/text
		if empty? text [return []]			;-- case of empty string
		full: caret-to-offset/lower r len	;-- full size: line height and average char width
		p: size / 2 * 0x-1					;-- start at upper center
		decay: (p/y + full/y) / p/y			;-- orbit decay per cycle (< 1)
		rmid: full/y / -2 + absolute p/y	;-- radius of the middle line of the string
		wavg: full/x / len					;-- average char width
		p: p - (wavg / 2)					;-- offset the typesetter to center the average char
		collect/into [
			;@@ TODO: initial angle
			keep compose [translate (size / 2)]
			repeat i len [			;@@ should be for-each [/i c]
				c: text/:i
				bgn: caret-to-offset r i
				cycles: bgn/x / 2 / pi / rmid
				scale: decay ** cycles
				box: []
				if all [field/active?  i - 1 = field/caret-index] [
					box: compose [box (p) (p + as-pair field/caret-width full/y)]
				]
				keep compose/deep [
					push [
						rotate (cycles * 360)
						scale (scale) (scale)
						(box)
						text (p) (form c)
					]
				]
			]
		] clear []		;@@ this is a bug, really
	]
]
