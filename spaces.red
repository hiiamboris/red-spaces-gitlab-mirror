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
	/limits xy1 [pair!] xy2 [pair!] "Specify viewport"
][
	r: make [] 10
	foreach [name box] map [
		all [list  not find list name  continue]		;-- skip names not in the list if it's provided
		; all [limits  not bbox-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
		all [box/size/x * box/size/y = 0  continue]		;-- don't render empty elements (also works around #4859)
		cmds: either limits [
			render/only name xy1 xy2
		][	render      name
		]
		unless empty? cmds [							;-- don't spawn empty translate/clip structures
			compose/deep/only/into [
				translate (box/offset) [
					clip 0x0 (box/size) (cmds)			;@@ TODO: remove `clip`
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
	rate: none											;@@ not sure about it, but it's the only way user can set rate:
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
			w-thumb: case [						;-- 3 strategies for the thumb
				w-inner >= (2 * h) [max h w-inner * amount]		;-- make it big enough to aim at
				w-inner >= 8       [      w-inner * amount]		;-- better to have tiny thumb than none at all
				'else              [0]							;-- hide thumb, leave just the arrows
			]
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
		scroll-timer: make-space 'space [rate: 16]	;-- how often it scrolls when user presses & holds one of the arrows

		map: compose [
			(content) [offset 0x0 size 0x0]
			hscroll   [offset 0x0 size 0x0]
			vscroll   [offset 0x0 size 0x0]
			scroll-timer [offset 0x0 size 0x0]		;-- timer currently has to be in the map to fire, else can't have a path
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
				render/only content		;-- render it before 'size' can be obtained, also render itself may change origin (in `roll`)!
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
		items: []				;-- user-controlled ;@@ TODO: maybe rename to `pane`?
		axis: 'x
		margin: 5x5
		spacing: 5x5
		;@@ TODO: alignment?
		;@@ this requires /size caching - ensure it is cached (e.g. as `content` which is generic and may be a list)
		;@@ or use on-deep-change to update size - what will incur less recalculations?
		;@@ TODO: margin & spacing - in style??
		;@@ TODO: appendable-list? smth that caches items' size so append is fast
		map: []

		make-layout: has [r] [
			r: make list-layout []
			r/axis:    axis
			r/margin:  margin
			r/spacing: spacing
			r
		]

		; measure: func [i [integer!]] [
		; 	render name: items/:i
		; 	select get name 'size
		; ]

		draw: function [/only xy1 xy2 /layout lobj [object!]] [
			;@@ keep this in sync with `grid/draw`
			r: make [] 10
			layout: any [lobj make-layout]
			clear map
			foreach name items [
				item: get name
				drawn: unless item/size [render name]		;-- prerender to get the size, caching previously drawn items
				set [p1: siz: org:] layout/place item/size
				skip?: all [only  not bbox-overlap?  p1 p1 + siz  xy1 xy2]
				unless skip? [
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



; 	{
; 		plan:
; 		2 origins: offset of viewport within a cache window or how to call it
; 			viewport-origin and window-origin
; 		I detect changes in viewport-origin, see when content gets out of window size
; 		when that happens,
; 		either move visible items in the window, or discard them all (when not caching)
; 		window-origin gets offset by jump size
; 		request to draw either part that's freed or all visible items again (request for window to fill the map)

; 		viewport is a part of scrollable
; 		scrollable can be fully reused
; 		it's content will be a data-window that does all the magic
; 	}

;@@ TODO: this is a template space, should it be exposed into global spaces list at all?
window-ctx: context [
	spaces/window-template: make-space/block 'space [
		;-- offset of "content" within the window, or `(absolute 0x0 of content) - (absolute 0x0 of window)`
		;-- <0 if window moves to the right/bottom of it's original position (normal spaces)
		;-- >0 - to the left/top (infinite spaces or generally those that aren't clipped by 0x0 point)
		;-- only affected by `roll`
		origin: 0x0

		caching?: yes					;-- when origin gets moved, can visible content be cached? or has to be redrawn
		map: []
		max-size: 1000x1000				;-- when drawn auto adjusts it's `size` up to max-size (otherwise scrollbars will always be visible)

		;-- should add to the map missing spaces that happen to intersect box xy1-xy2 of window
		fill: func [xy1 [pair!] xy2 [pair!]] []			;-- template; to be provided by the user

		;-- should return how much more window can be scrolled in specified direction (from it's edge, not current origin!)
		;-- if it returns more than requested, returned value is added
		available?: func [dir [word!] "n/e/s/w" requested [integer!]] [requested]		;-- template; by default infinite

		invalidate: does [last-origin: last-size: none]
		last-origin: last-size: none							;-- geometry during previous call to `renew`
		renew: function [] [
			unless all [last-origin last-size = max-size] [		;-- first ever invocation or size changed
				self/last-origin: origin
				self/last-size: max-size
				fill 0x0 max-size
				exit
			]
			if 0x0 = offset: origin - last-origin [exit]		;-- has not been moved
			self/last-origin: origin
			unless caching? [
				clear map
				fill 0x0 max-size
				exit
			]

			remove-each [name geom] map [				;-- clear the map of invisible spaces
				o: geom/offset: geom/offset + offset	;-- and relocate visible ones
				not bbox-overlap?  0x0 max-size  o o + geom/size
			]
			case [										;-- fill top/bottom before left/right (random decision)
				offset/y > 0 [fill  0x0  as-pair max-size/x top: offset/y]
				offset/y < 0 [fill  as-pair 0 btm: max-size/y + offset/y  max-size]
			]
			default top: 0
			default btm: max-size/y
			case [										;-- left/right excludes already drawn top/bottom regions
				offset/x > 0 [fill  as-pair 0 top  as-pair offset/x btm]
				offset/x < 0 [fill  as-pair max-size/x + offset/x top  as-pair max-size/x btm]
			]
		]

		draw: function [/only xy1 [pair!] xy2 [pair!]] [
			old-origin: origin							;-- renew may change origin, in which case we don't wanna miss the viewport
			renew
			either only [
				visible: []
				foreach [name geom] map [				;@@ should be map-each
					if bbox-overlap? 0x0 max-size xy1 xy2 [append visible name]
				]
				r: compose-map/only/limits map visible xy1 - old-origin xy2 - old-origin
				clear visible							;-- let GC free it up
			][
				r: compose-map map
			]
			self/size: either empty? map [
				0x0
			][
				item-last: last map
				min max-size item-last/offset + item-last/size
			]
			r
		]

		; on-change*: function [word [word! set-word!] old [any-type!] new [any-type!]] [
		; ]
	]
]

;@@ make it a template too??
inf-scrollable-ctx: context [
	spaces/inf-scrollable: make-space/block 'scrollable [	;-- `infinite-scrollable` is too long for a name
		jump-length: 100						;-- how much more to show when rolling (px) ;@@ maybe make it a pair?
		look-around: 50							;-- zone after head and before tail that triggers roll-edge (px)

		content: 'window
		window: make-space 'window-template []			;-- should be overridden or `fill` & `available?` defined

		roll: function [] [
			win-org: window/origin  org: origin
			foreach [x fwd bck] [x e w  y s n] [
				if dir: case [
					(0 - org/:x) <= look-around [bck]
					(0 - org/:x) >= (window/max-size/:x - size/:x - look-around) [fwd]
				][
					if 0 < avail: window/available? dir jump-length [
						if bck = dir [avail: 0 - avail]
						win-org/:x: win-org/:x - avail		;-- transfer offset from scrollable into window
						org/:x: org/:x + avail
					]
				]
			]
			maybe self/origin: org						;-- commit changed origins in a way detectable by on-change
			maybe window/origin: win-org
		]
	]
]


;@@ just for testing ;@@ TODO: beautify it and draw a spider at random location, or leave it to the others as a challenge
;@@ TODO: explore fractals this way :D
spaces/web: make-space/block 'inf-scrollable [
	canvas: make-space 'space [
		draw: function [] [
			center: (ws: window/max-size) / 2 + window/origin
			x-axis: when all [0 <= center/y center/y <= ws/y] [
				compose [line (center * 0x1) (as-pair ws/x center/y)]
			]
			y-axis: when all [0 <= center/x  center/x <= ws/x] [
				compose [line (center * 1x0) (as-pair center/x ws/y)]
			]
			xy1: center - (center/x * 1x1)
			xy2: center - (center/x - ws/x * 1x1)
			l-diag: when all [xy2/y >= 0  xy1/y <= ws/y] [
				compose [line (xy1) (xy2)]
			]
			xy1: center - (center/x * 1x-1)
			xy2: center - (center/x - ws/x * 1x-1)
			r-diag: when all [xy1/y >= 0  xy2/y <= ws/y] [
				compose [line (xy1) (xy2)]
			]
			r: compose [(x-axis) (y-axis) (l-diag) (r-diag)]
			nearest: either within? center 0x0 ws [
				0x0
			][
				min absolute center absolute (center - ws)
			]
			min-rad: vec-length? nearest
			min-rad: max 0 round/to/floor min-rad 30
			max-rad: min-rad + vec-length? ws
			rad: min-rad
			append r compose [translate (center)]
			while [rad < max-rad] [
				loop 8 [
					append r compose [
						line (rad * 0x1) (rad * 1x1 * (sqrt 2) / 2)
						rotate 45
					]
				]
				rad: rad + 30
			]
			r
		]
	]

	window/max-size: 1000x1000
	; window/available?: func [dir req] [0]
	window/fill: function [xy1 xy2] [
		if empty? window/map [append window/map [canvas [offset 0x0 size 0x0]]]
		geom: window/map/canvas
		maybe geom/offset: 0x0
		maybe geom/size: window/max-size
	]
]

list-view-ctx: context [
	spaces/list-view: make-space/block 'inf-scrollable [
		source: []		;@@ or a function [index]? or support both?
		data: function [/pick i [integer!] /length] [
			either pick [source/:i][length? source]
		]
		index: 1										;-- index of the first item within source
		
		wrap-data: function [item-data [any-type!]][
			spc: make-space 'data-view []
			set/any 'spc/data :item-data
			if list/axis = 'y [spc/width: window/max-size/x - (list/margin/x * 2)]		;@@ what data width to use for horizontal lists?
			anonymize 'item spc
		]

		roll-timer: make-space 'space [rate: 4]			;-- how often to call `roll` when dragging
		append map [roll-timer [offset 0x0 size 0x0]]
		
		list: make-space 'list [axis: 'y]				;-- list/axis can be changed to get a horizontal list ;@@ but then setup becomes wrong
		window/map: [list [offset 0x0 size 0x0]]

		window/max-size: 1000x1000		;@@ this is where sizing strategy would be cool to have

		extra?: function [dir [word!]] [			;-- measure dangling extra size along any direction
			if empty? map: window/map [return 0]
			#assert [2 = length? map]
			r: max 0x0
				switch dir [
					w n [negate map/2/offset]
					e s [map/2/offset + map/2/size - window/max-size]
				]
			r/x + r/y
		]

		window/available?: function [dir [word!] requested [integer!]] [
			#assert [0 < requested]
			if any [
				all [list/axis = 'y  find [e w] dir]
				all [list/axis = 'x  find [n s] dir]		;@@ not sure about this yet, /width doesn't guarantee it
			] [return 0]
			reserve: extra? dir
			requested: requested - reserve

			r: 0
			if requested > 0 [
				lt: extend-layout dir requested
				r: lt/content-size/(list/axis)
				unless empty? lt/items [r: r + lt/spacing/(list/axis)]
			]
			r: max 0 r + reserve
			; print ["avail?" dir "=" r "of" requested "(reserve:" reserve ")"]
			r
		]

		;@@ ensure this one is called only from inf-scrollable/draw
		extend-layout: function [dir [word!] amount [integer!] /keep where [block!]] [
			; print ["extend" dir amount]
			lt: list/make-layout
			unless empty? list/items [amount: amount - lt/spacing/(list/axis)]
			switch dir [
				n w [+-: :-  n-max: (base: index) - 1]
				s e [+-: :+  n-max: data/length - base: index - 1 + length? list/items]
			]
			#assert [(select [n y s y e x w x] dir) = list/axis]
			repeat i n-max [
				name: wrap-data data/pick base +- i		;-- guarantee at least 1 item (else spacing could be bigger than the requested amount)
				#assert [not find/same list/items name]
				render name
				lt/place select get name 'size
				if keep [append where name]
				if lt/content-size/(list/axis) >= amount [break]
			]
			lt
		]

		;-- this func is quite hard to get right, many aspects to consider
		;-- * window moves list within it's map before calling `fill`,
		;--   but we'll have to move list back and move all items within list accordingly
		;-- * move offset can be used right away to know what spaces will be hidden
		;-- * list may have extra dangling items partially clipped by window (before the move), which now become visible
		;--   i.e. list/size may be > window/max-size because it contains whole items, not necessarily aligning to window borders
		;-- * these hidden parts should be subtracted from the xy1-xy2 area to know how much to extend the list itself
		;-- * there may be no new items to add, just the hidden area to show
		;-- * list may initially be empty (spacing to consider), or not rendered (undefined size)
		;-- * when filling from above, list should be aligned with the top border, when from below - the opposite
		;@@ and I haven't considered the case where window/max-size <= list-view/size (it isn't working)
		window/fill: function [xy1 [pair!] xy2 [pair!]] [
			; ?? size print ["fill" xy1 xy2]
			;@@ TODO: remove these or add x=opposite support
			#assert [0 = xy1/x]
			#assert [window/max-size/x = xy2/x]
			#assert [any [xy1/y = 0  xy2/y = window/max-size/y]]

			unit: select [x 1x0 y 0x1] x: list/axis
			dir: select
				pick [ [x e y s] [x w y n] ] xy2/:x = window/max-size/:x	;-- s/e = tail fill (or head to tail), n/w = head fill (partial)
				x
			negative?: none <> find [n w] dir
			either negative? [											;-- get already rendered parts out of the requested area
				xy2/:x: xy2/:x - extra? dir
			][	xy1/:x: xy1/:x + extra? dir
			]
			lgeom: window/map/list

			;-- xy area now lies purely outside the list, so we can fill it
			lt: extend-layout/keep dir (xy2/:x - xy1/:x) clear new: []

			;-- sometimes it's possible that `new` is empty and `fill` should only move the list to show `extra?` (hidden) area
			unless empty? new [
				;@@ TODO: some automatic extension calculation? right now it won't work for arbitrary layout
				pixels-added: lt/content-size/:x + either empty? list/items [0][lt/spacing/:x]

				offset: lgeom/offset						;-- we can count invisibles right now from list/offset
				initial-fill?: offset = 0x0					;-- on first fill, do not align with the lowest/rightmost edge
				
				n-remove: 0									;-- count how many invisible spaces to remove
				foreach': switch dir [n w [:foreach-reverse] s e [:foreach]]	 ;@@ should be for-each/reverse
				;@@ list should have no timer in the map, else we'll have to check names for `item`
				foreach' [_: geom:] list/map [
					o: geom/offset + offset
					visible?: bbox-overlap?  0x0 window/max-size  o o + geom/size
					either visible? [break][n-remove: n-remove + 1]
				]

				either negative? [									;-- insert new items
					insert list/items reverse new
					self/index: self/index - length? new
				][
					append list/items new
					maybe self/index: self/index + n-remove			;-- n-remove can be 0
				]

				pixels-removed: 0									;-- along the list/axis
				if n-remove > 0 [
					removed: either negative? [						;-- remove invisibles from `items` & `map`
						take/last/part list/items n-remove
						take/last/part list/map n-remove * 2
					][
						remove/part list/items n-remove
						take/part list/map n-remove * 2
					]

					rem-1st: removed/2
					rem-last: last removed
					pixels-removed: rem-last/offset + rem-last/size - rem-1st/offset + lt/spacing		;@@ TODO: automatic calculation if possible?
					pixels-removed: pixels-removed/:x
				]

				;-- now that we know removed size we can calculate how much to shift the list in window/map
				offset: unit * either negative? [pixels-added][pixels-removed * -1]

				foreach [_ geom] list/map [					;-- relocate visible spaces now that we know the offset
					geom/offset: geom/offset - offset
				]

				either new-size: list/size [
					;-- update the size, without re-rendering anything
					new-size/:x: new-size/:x - pixels-removed + pixels-added
					maybe list/size: new-size
				][
					;-- render the list to get it's size - should only be needed first time it's shown
					render/only 'list xy1 xy2
				]
			]
			#assert [list/size]

			;-- update list geometry inside the window
			lgeom/size: list/size
			lgeom/offset: either any [negative? initial-fill?] [
				0x0												;-- align to top-left corner of the window
			][	min 0x0 window/max-size - list/size * unit		;-- to bottom-left, but only if list > window(!)
			]
		]

		setup: function [] [
			if size [									;-- if size is defined, adjust the window (paragraphs adjust to window then)
				pages: 10								;@@ make this configurable?
				unit: select [x 1x0 y 0x1] list/axis
				maybe window/max-size: size + (pages - 1 * size * unit)
			]
		]

		inf-scrollable-draw: :draw
		draw: function [] [
			setup
			inf-scrollable-draw
		]
	]
]


;@@ TODO: list-view of SPACES?  simple layout-ers?  like grid..?

;-- grid's key differences from list of lists:
;-- * it aligns columns due to fixed column size
;-- * it CAN make cells spanning multiple rows (impossible in list of lists)
;-- * it uses fixed row heights, and because of that it CAN have infinite width (but requires separate height inferrence)
;--   (by "infinite" I mean "big enough that it's unreasonable to scan it to infer the size (or UI becomes sluggish)")
;-- * grid is better for big empty cells that user is supposed to fill,
;--   while list is better for known autosized content
;@@ TODO: height & width inferrence
;@@ think on styling: spaces grid should not have visible delimiters, while data grid should
grid-ctx: context [
	spaces/cell: make-space/block 'space [
		map: [space [offset 0x0 size 0x0]]
		cdrawn: none			;-- cached draw block of content to eliminate double redraw - used by row-height? and during draw when extending cell size
		draw: function [] [
			unless cdrawn [self/cdrawn: render map/1]
			spc: get name: map/1
			map/2/size: spc/size
			unless size [self/size: spc/size]
			compose/only [
				; box 0x0 (size)	;-- already done in styles
				(cdrawn)
			]
		]
	]

	spaces/grid: make-space/block 'space [
		size:    none				;-- only available after `draw` because it applies styles
		margin:  5x5
		spacing: 5x5
		cell-map: make map! []				;-- XY coordinate -> space-name  ;@@ TODO: maybe rename to `pane`? ;@@ TODO: support a function instead of map here?
											;@@ or `cmap` for brevity?
		spans:   make map! []				;-- XY coordinate -> it's XY span (not user-modifiable!!)
											;@@ make spans a picker too?? or pointless for infinite data anyway
		widths:  make map! [default 100]	;-- number of column/row -> it's width/height
		heights: make map! [default 100]	;-- height can be 'auto (row is auto sized)
		origin:  0x0						;-- offset of non-pinned cells from 0x0 (negative = to the left and above) (alternatively: offset of pinned cells over non-pinned, but negated)
		pinned:  0x0						;-- how many rows & columns should stay pinned (as headers), no effect if origin = 0x0
		limits:  [x: auto y: auto]			;-- max number of rows & cols, auto=bound `cells`, integer=fixed
											;-- 'auto will have a problem inside infinite grid with a sliding window
											;@@ none for unlimited here, but it will render scrollers useless and cannot be drawn without /only - will need a window over it anyway

		min-row-height: 0					;-- used in autosizing in case no other constraints apply; set to >0 to prevent rows of 0 size
		hcache:  make map! 20				;-- cached heights of rows marked for autosizing ;@@ TODO: when to clear/update?
		
		;@@ TODO: margin & spacing - in style??
		;@@ TODO: alignment within cells? when cell/size <> content/size..
		;@@       and how? per-row or per-col? or per-cell? or custom func? or alignment should be provided by item wrapper?
		map: []

		wrap-space: function [xy [pair!] space [word!]] [	;-- wraps any cells/space into a lightweight "cell", that can be styled
			name: any [
				draw-ctx/ccache/:xy
				draw-ctx/ccache/:xy: make-space/name 'cell []
			]
			cell: get name
			cell/map/1: space
			name
		]

		cells: func [/pick xy [pair!] /size] [				;-- up to user to override
			either pick [cell-map/:xy][calc-limits]
		]

		calc-limits: function [] [
			unless any ['auto = limits/x  'auto = limits/y] [	;-- no auto limit set (but can be none)
				return limits
			]
			lim: copy limits
			xymax: either empty? cell-map [
				0x0
			][
				remove find xys: keys-of spans 'default		;-- if `spans` is correct, it contains the lowest rightmost multicell coordinate
				append xys keys-of cell-map
				second minmax-of xys
			]
			if 'auto = lim/x [lim/x: xymax/x]
			if 'auto = lim/y [lim/y: xymax/y]
			lim
		]

		; make-layout: function [] [	no need ??
		; 	r: make grid-layout []		;@@ make one
		; 	foreach w [margin spacing widths heights spans] [r/:w: self/:w]
		; 	r
		; ]

		;@@ should be faster than generic map-based `into`
		; into: [
		; ]
		;-- userspace functions for `spans` reading & modification
		;-- they are required to be able to get any particular cell's multi-cell without full `spans` traversal
		;@@ TODO: maybe mark all internal funcs & structures with *
		;@@ TODO: docstrings
		get-span: function [cell [pair!]] [
			any [spans/:cell  1x1]
		]

		get-first-cell: function [cell [pair!]] [
			span: get-span cell
			if 0x0 = max 0x0 span [cell: cell + span]
			cell
		]

		break-cell: function [first [pair!]] [
			if 1x1 <> span: get-span first [
				#assert [1x1 = min 1x1 span]			;-- ensure it's a first cell of multicell
				xyloop xy span [
					remove/key spans xy': first + xy - 1x1
					;@@ invalidate content within ccache?
				]
			]
		]

		unify-cells: function [first [pair!] span [pair!]] [
			if 1x1 <> old: get-span first [
				if 0x0 = max 0x0 old [
					ERROR "Cell (first + old) should be broken before (first)"	;@@ or break silently? probably unexpected move..
				]
				break-cell first
			]
			xyloop xy span [							;@@ should be for-each
				#assert [1x1 = get-span first + xy - 1x1]
				spans/(first + xy - 1x1): 1x1 - xy
				;@@ invalidate content within ccache?
			]
			spans/:first: span
		]

		set-span: function [
			"Set the SPAN of a FIRST cell, breaking it if needed"
			first [pair!] "Starting cell of a multicell or normal cell that should become a multicell"
			span  [pair!] "1x1 for normal cell, more to span multiple rows/columns"
			/force "Also break all multicells that intersect with the given area"
		][
			if span = get-span first [exit]
			#assert [1x1 = min 1x1 span]				;-- forbid setting to span to non-positives
			xyloop xy span [							;-- break all multicells within the area
				cell: first + xy - 1
				old-span: get-span cell
				if old-span <> 1x1 [
					all [
						not force
						any [cell <> first  1x1 <> min 1x1 old-span]	;-- only `first` is broken silently if it's a multicell
						ERROR "Cell (first + old-span) should be broken before (first)"
					]
					break-cell cell + min 0x0 old-span
				]
			]
			unify-cells first span
		]

		get-offset-from: function [
			"Get pixel offset of left top corner of cell C2 from that of C1"
			c1 [pair!] c2 [pair!]
		][
			r: 0x0
			foreach [x wh?] [x col-width? y row-height?] [
				x1: min c1/:x c1/:x
				x2: max c1/:x c2/:x
				if x1 = x2 [continue]
				wh?: get wh?
				for xi: x1 x2 - 1 [r/:x: r/:x + wh? xi]		;@@ should be sum map-each
				r/:x: r/:x + (x2 - x1 * spacing/:x)
				if x1 > x2 [r/:x: negate r/:x]
			]
			r
		]

		;-- fast row/col locator assuming that array size is smaller than the row/col number
		;-- returns any of:
		;--   [margin 1 offset] - within the left margin (or if point is negative, then to the left of it)
		;--   [cell   1 offset] - within 1st cell
		;--   [space  1 offset] - within space between 1st and 2nd cells
		;--   [cell   2 offset] - within 2nd cell
		;--   [space  2 offset]
		;--   ...
		;--   [cell   N offset]
		;--   [margin 2 offset] - within the right margin (only when limit is defined),
		;--                       offset can be bigger(!) than right margin if point is outside the space's size
		locate-line: function [
			level [integer!] "pixels from 0"
			array [map!] "widths or heights"
			axis  [word!] "x or y"
		][
			mg: margin/:axis
			if level < mg [return reduce ['margin 1 level]]		;-- within the first margin case
			level: level - mg

			sp: spacing/:axis
			lim: draw-ctx/limits/:axis
			;@@ also - pinned!? or not here?
			def: array/default
			whole: 0			;@@ what if lim = 0?
			sub: func [n size] [	;@@ TODO: get this out
				if lim [n: min n lim - 1 - whole]
				n: min n to 1 level / size
				whole: whole + n
				level: level - (n * size)
				#debug grid-view [#print "sub (n) (size) -> whole: (whole) level: (level)"]
				n
			]
			sub-def: func [from n /local r j] [
				#debug grid-view [#print "sub-def (from) (n) def: (def)"]
				either integer? def [
					if n <> sub n sp + def [size: def throw 1]
				][											;-- `default: auto` case where each row size is different
					#assert [array =? heights]
					repeat j n [
						size: row-height? from + j
						if 0 = sub 1 sp + size [size: def throw 1]
					]
				]
			]

			size: 0
			either 1 = len: length? array [					;-- 1 = special case - all cells are of their default size
				catch [sub-def 0 level]						;@@ assumes default size > 0 (at least 1 px) - need to think about 0
				size: row-height? whole + 1
			][
				keys: sort keys-of array
				remove find keys 'default
				#assert [keys/1 > 0]						;-- no zero or negative row/col numbers expected
				key: 0

				catch [
					also no
					repeat i len - 1 [							;@@ should be for-each/stride [/i prev-key key]
						prev-key: key
						key: keys/:i
						
						before: key - 1 - prev-key				;-- default-sized cells to subtract (may be 'auto)
						if before > 0 [sub-def prev-key before]
						
						if 'auto = size: array/:key [			;-- row is marked for autosizing
							#assert [array =? heights]
							size: row-height? key				;-- try to fetch it from the cache or calculate
						]
						if 0 = sub 1 size + sp [throw 1]		;-- this cell contains level
					]
					sub-def key level						;@@ assumes default size > 0 (at least 1 px) - need to think about 0
				]
			]
			reduce case [
				level < size              [['cell   1 + whole level]]
				all [lim lim - 1 = whole] [['margin 2         level - size]]
				'else                     [['space  1 + whole level - size]]
			]
		]

		locate-point: function [xy [pair!]] [
			r: copy [0x0 0x0]
			foreach [x array wh?] reduce [
				'x widths  :col-width?
				'y heights :row-height?
			][
				set [item: idx: ofs:] locate-line xy/:x array x
				#debug grid-view [#print "locate-line/(x)=(xy/:x) -> [(item) (idx) (ofs)]"]
				switch item [
					space [ofs: ofs - spacing/:x  idx: idx + 1]
					margin [
						either idx = 1 [
							ofs: ofs - margin/:x
						][
							idx: draw-ctx/limits/:x
							ofs: ofs + wh? idx
							#assert [idx]			;-- 2nd margin is only possible if limits are known
						]
					]
				]
				r/1/:x: idx r/2/:x: ofs
			]
			#debug grid-view [#print "locate-point (xy) -> (mold r)"]
			r
		]

		row-height?: function ["Get height of row Y (only calculate if necessary)" y [integer!]] [
			r: any [heights/:y heights/default]
			if r = 'auto [
				r: any [
					hcache/:y
					hcache/:y: calc-row-height y
				]
			]
			r
		]

		col-width?: function ["Get width of column X" x [integer!]] [
			any [widths/:x widths/default]
		]

		;@@ ensure it's only called from within render
		;@@ ensure it's called top-down only, so it can get upper row sizes from the cache
		calc-row-height: function ["Render the row Y to obtain it's height" y [integer!]] [
			#assert ['auto = any [heights/:y heights/default]]	;-- otherwise why call it?
			xlim: draw-ctx/limits/x
			#assert [integer? xlim]						;-- row size cannot be calculated for infinite grid
			hmin: append clear [] min-row-height
			for x: 1 xlim [
				span: get-span xy: as-pair x y
				if span/x < 0 [continue]				;-- skip cells of negative x span (counted at span = 0 or more)
				first: get-first-cell xy
				height1: 0
				if content: cells/pick first [
					unless draw-ctx/ccache/:first [			;-- only render if not cached
						render wrap-space first content		;-- caches drawn content itself
					]
					cspace: get content
					height1: cspace/size/y
				]
				case [
					span/y = 1 [
						#assert [span/x > 0]
						append hmin height1
					]
					span/y + y = first/y [				;-- multi-cell vertically ends after this row
						for y2: first/y y - 1 [
							height1: height1 - spacing/y - row-height? y2
						]
						append hmin height1
					]
					;-- else just ignore this and use min-row-height
				]
				x: x + max 0 span/x - 1					;-- skip horizontal span
			]
			second minmax-of hmin						;-- choose biggest of constraints
		]

		cell-size?: function [
			"Get the size of a cell XY or a multi-cell starting at XY (with the spaces)"
			xy [pair!]
		][
			#assert [xy = get-first-cell xy]	;-- should be a starting cell
			#assert [draw-ctx/ccache/:xy]		;-- cell should be rendered already (for row-heights to return immediately)
			span: get-span xy
			size: 0x0
			repeat x span/x [size/x: size/x + col-width?  x - 1 + xy/x]
			repeat y span/y [size/y: size/y + row-height? y - 1 + xy/y]
			size + (span - 1 * spacing)
		]

		is-cell-pinned?: func [xy [pair!]] [
			xy = min xy pinned
		]

		calc-size: function [] [
			limits: draw-ctx/limits
			unless all [limits/x limits/y] [
				#assert [size]						;-- should be defined before rendering an infinite grid
				return size - origin		;@@ is this gonna work?
			]
			; #assert [all [limits/x limits/y]]		;-- if limits aren't defined - size is infinite
			limits: as-pair limits/x limits/y
			r: margin * 2 + (spacing * max 0x0 limits - 1)
			repeat x limits/x [r/x: r/x + col-width?  x]
			repeat y limits/y [r/y: r/y + row-height? y]
			r
		]

		;-- due to the number of parameters this space has,
		;-- a special context is required to minimize the number of wasted calculations
		draw-ctx: context [
			ccache: make map! 100			;-- cached `cell` spaces (persistency required by the focus model)
			rcache: make map! 100			;-- marks already rendered multicells, so we don't rerender them every time
			limits: none
			size:   none
			cleanup: function [] [
				self/limits: self/size: none
				clear rcache
				foreach [xy name] ccache [
					cell-space: get name
					cell-space/cdrawn: none
					;@@ TODO: clean up cell-spaces themselves that go out of the window
				]
			]
		]

		;@@ need to think more about this.. I don't like it
		invalidate: func [/only row [integer!]] [
			either only [remove/key hcache row][clear hcache]	;-- clear should never be called on big datasets
			;@@ ccache?
		]
; f: does [foreach x [1 2 3] [continue]]

		draw: function [/only xy1 xy2] [
			;@@ keep this in sync with `list/draw`
			; #assert [only]			;@@ TODO: full render mode 
			dc: draw-ctx
			dc/cleanup
			dc/limits: cells/size
			;-- locate-point calls row-height which may render cells when needed to determine the height
			default xy1: 0x0
			unless xy2 [dc/size: xy2: calc-size]
			set [cell1: offs1:] locate-point xy1
			set [cell2: offs2:] locate-point xy2
			dc/size: any [dc/size  calc-size]
			unless self/size [maybe self/size: dc/size]
			clear map
			r-normal: make [] 100
			r-pinned: make [] 100
			rcache: dc/rcache
			origin-to-cell1: xy1 - offs1
			xyloop cofs: cell2 - cell1 + 1 [
				cell: cell1 - 1 + cofs
				cell1-to-cell: either cofs/x = 1 [			;-- pixels from left top cell to this cell
					get-offset-from cell1 cell
				][	cell1-to-cell + get-offset-from cell - 1x0 cell
				]

				mcell: get-first-cell cell					;-- row/col of multicell this cell belongs to
				unless mcell-content-name: cells/pick mcell [continue]	;-- cell is not defined? skip the draw
				if rcache/:mcell [continue]					;-- don't redraw already drawn multi-cells (marked as true below)
				mcell-to-cell: get-offset-from mcell cell	;-- pixels from multicell to this cell
				pinned?: is-cell-pinned? cell
				start: origin-to-cell1 + either pinned? [0x0][origin]
				draw-ofs: start + cell1-to-cell - mcell-to-cell		;-- pixels from 0x0 to the draw box of this cell
				render mcname: wrap-space mcell mcell-content-name	;-- render cell content before getting it's size
				mcspace: get mcname
				mcsize: cell-size? mcell					;-- size of all rows/cols it spans
				mcspace/size: mcsize						;-- update cell's size to cover rows/cols fully
				mcdraw: render mcname						;-- re-render (cached) to draw the full background
				compose/deep/into [
					(anonymize 'cell mcspace) [offset (draw-ofs) size (mcsize)]
					; (cells/pick mcell) [offset (draw-ofs) size (mcsize)]	;-- version without cell/
				] tail map
				compose/only/into [							;-- compose-map calls extra render, so let's not use it here
					translate (draw-ofs) (mcdraw)			;@@ can compose-map be more flexible to be used in such cases?
				] tail either pinned? [r-pinned][r-normal]
				rcache/:mcell: true							;-- mark it as drawn (so the same multi-cell won't be drawn again)
			]
			normal-ofs: origin + margin + get-offset-from 1x1 1x1 + pinned
 			compose/only/deep [
				(r-pinned)
				clip (normal-ofs) (xy2) (r-normal)
			]
		]
	]
]


grid-view-ctx: context [
	spaces/grid-view: make-space/block 'inf-scrollable [
		source: make map! [size: 0x0]					;-- map is more suitable for spreadsheets than block of blocks
		data: function [/pick xy [pair!] /size] [
			switch type?/word :source [
				block! [
					case [
						pick [source/:y/:x]
						0 = n: length? source [0x0]
						'else [as-pair length? :source/1 n]
					]
				]
				map! [either pick [source/:xy][source/size]]
			]
		]

		grid: make-space 'grid []
		grid-cells: :grid/cells
		grid/cells: func [/pick xy [pair!] /size] [
			either pick [
				unless grid/cell-map/:xy [
					grid/cell-map/:xy: wrap-data xy data/pick xy
				]
				grid-cells/pick xy
			][data/size]
		]
		
		wrap-data: function [xy [pair!] item-data [any-type!]] [
			spc: make-space 'data-view []
			set/any 'spc/data :item-data
			spc/width: (grid/col-width? xy/x) - (spc/margin/x * 2)
			anonymize 'item spc
		]

		roll-timer: make-space 'space [rate: 4]			;-- how often to call `roll` when dragging
		append map [roll-timer [offset 0x0 size 0x0]]
		
		window/map: [grid [offset 0x0 size 0x0]]

		window/max-size: 10000x10000		;@@ this is where sizing strategy would be cool to have

		window/available?: function [dir [word!] requested [integer!]] [
			x: select [n y s y e x w x] dir
			r: switch dir [
				n w [max 0 negate grid/origin/:x]
				s e [
					either grid/limits/:x [
						r: grid/origin - window/size + grid/calc-size	;@@ optimize calc-size?
						r/:x
					][
						requested
					]
				]
			]
			r: min r requested
			#debug grid-view [#print "avail? (dir) = (r) of (requested)"]
			r
		]

		window/fill: function [xy1 [pair!] xy2 [pair!]] [
			#debug grid-view [#print "grid window fill (xy1) - (xy2)"]
			geom: window/map/grid
			jump: geom/offset
			grid/origin: grid/origin + jump
			geom/offset: 0x0
			unless grid/size [render 'grid]
			geom/size: min window/max-size grid/size
			render/only 'grid xy1 xy2			;-- should be rendered after(!) origin is set
		]

		setup: function [] [
			if size [									;-- if size is defined, adjust the window
				pages: 10x10							;@@ make this configurable?
				; pages: 3x3							;@@ make this configurable?
				maybe window/max-size: size * pages
				maybe self/jump-length: min size/x size/y
			]
		]

		inf-scrollable-draw: :draw
		draw: function [] [
			setup
			inf-scrollable-draw
		]
	]
]



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

		make-layout: has [r] [
			r: make row-layout [
				pinned: table/pinned/x
				widths: table/widths
				axis: 'x
			]
			r/axis:    axis
			r/margin:  margin
			r/spacing: spacing
			r
		]

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
			list-draw
		]
	]

	;@@ TODO: spacers between pinned and not pinned data
	spaces/table: make-space/block 'list [
		pinned: 0x1							;-- pinned columns x rows (headers)
		margin: 0x0	
		data-columns: [1 2]					;-- indexes of visible DATA columns in the order of appearance
		;-- NOTE: don't use #() here because it's ignored by copy/deep
		widths: make map! [1 100 2 100]		;-- data column index -> it's visible width
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
		headers/wrap-data:
		columns/wrap-data: function [item-data [block!]] [
			anonymize 'row make-space 'table-row compose/only [table: (self) data: (item-data)]
		]

		items: [headers columns]

		list-draw: :draw
		draw: function [] [
			maybe headers/origin: as-pair columns/origin/x headers/origin/y	;-- sync origin/x
			; headers/invalidate
			; columns/invalidate
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
;@@ if embedded, map composition should be a reverse of hittest: if something is drawn first then it's at the bottom of z-order
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
