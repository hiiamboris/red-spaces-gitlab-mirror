Red [
	title:   "Draw-based widgets (Spaces) definitions"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires `for` loop from auxi.red, layouts.red, export


;@@ TODO: also a `spaces` context to wrap everything, to save it from being overridden (or other name, or under system/)

;@@ rename to standard-spaces ?


exports: [make-space make-template space?]

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

make-template: function [
	"Declare a space template"
	base [word!]  "Type it will be based on"  
	spec [block!] "Extension code"
][
	make-space/block base spec
]

;-- helps having less boilerplate when `map` is straightforward
compose-map: function [
	"Build a Draw block from MAP"
	map "List of [space-name [offset XxY size XxY] ...]"
	/only list [block!] "Select which spaces to include"
	/limits xy1 [pair!] xy2 [pair!] "Specify viewport"
][
	r: make [] round/ceiling/to (1.5 * length? map) 1
	foreach [name box] map [
		all [list  not find list name  continue]		;-- skip names not in the list if it's provided
		; all [limits  not bbox-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
		all [box/size/x * box/size/y = 0  continue]		;-- don't render empty elements (also works around #4859)
		cmds: either limits [
			render/only name xy1 xy2
		][	render      name
		]
		unless empty? cmds [							;-- don't spawn empty translate/clip structures
			compose/only/into [
				translate (box/offset) (cmds)
				; clip 0x0 (box/size) (cmds)			;@@ TODO: remove `clip`
			] tail r
		]
	]
	r
]


spaces: #()												;-- map for extensibility

spaces/space: [											;-- minimum basis to build upon
	draw: []
	size: 0x0
	; rate: none
]
space?: func [obj] [all [object? :obj  in obj 'draw  in obj 'size]]

spaces/timer: make-template 'space [rate: none]		;-- template space for timers

spaces/rectangle: make-template 'space [
	size: 20x10
	margin: 0
	draw: func [] [compose [box (margin * 1x1) (size - margin)]]
]

spaces/triangle: make-template 'space [
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

spaces/image: make-template 'space [
	size: none											;-- set automatically unless `autosize?` = off
	autosize?: true										;-- if off, `size` should be defined
	margin: 0
	data: make image! 1x1			;@@ 0x0 dummy image is probably better but triggers too many crashes
	draw: function [] [
		if autosize? [self/size: 2x2 * margin + data/size]
		#assert [size]
		compose [image (data) (1x1 * margin) (size - margin)]
	]
]

;@@ TODO: externalize all functions, make them shared rather than per-object
;@@ TODO: automatic axis inferrence from size?
scrollbar: context [
	spaces/scrollbar: make-template 'space [
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
		into: func [xy [pair!] /force name [word! none!]] [
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
	spaces/scrollable: make-template 'space [
		origin: 0x0					;-- at which point `content` to place: >0 to right below, <0 to left above
		content: make-space/name 'space []			;-- should be defined (overwritten) by the user
		hscroll: make-space 'scrollbar [axis: 'x]
		vscroll: make-space 'scrollbar [axis: 'y size: reverse size]
		scroll-timer: make-space 'timer [rate: 16]	;-- how often it scrolls when user presses & holds one of the arrows

		map: compose [
			(content) [offset 0x0 size 0x0]
			hscroll   [offset 0x0 size 0x0]
			vscroll   [offset 0x0 size 0x0]
			scroll-timer [offset 0x0 size 0x0]		;-- timer currently has to be in the map to fire, else can't have a path
		]

		into: function [xy [pair!] /force name [word! none!]] [
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
			#debug grid-view [#print "scrollable/draw: renders content from (max 0x0 0x0 - origin) to (box - origin); box=(box)"]
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
			#debug grid-view [#print "origin in scrollable/draw: (origin)"]
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
					#debug grid-view [#print "on-change origin: (mold :old) -> (mold :new)"]
					if all [pair? :new  word? content] [
						cspace: get content
						set-quiet 'origin clip [(map/:content/size - cspace/size) 0x0] new
						#debug grid-view [#print "on-change clipped to: (origin)"]
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

	spaces/paragraph: make-template 'space [
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
				#assert [0 < width]							;-- else crashes - see #4897
				; layout/size: size-text layout		;@@ BUG #4783		;-- 'size-text' is slow, has to be cached (by setting size)
				layout/size/y: second size-text layout		;-- 'size-text' is slow, has to be cached (by using on-change)
			][											;-- no wrap
				layout/size: none
				layout/size: size-text layout
			]
		]

		draw: function [] [
			unless layout [lay-out]
			self/size: margin * 2x2 + layout/size
			compose [text (1x1 * margin) (layout)]
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


;-- layout-agnostic template for list, ring & other layout using space collections
container-ctx: context [
	~: self

	draw: function [cont [object!] layout [object!] xy1 [pair! none!] xy2 [pair! none!]] [
		#assert [(none? xy1) = none? xy2]				;-- /only is ignored to simplify call in absence of `apply`
		r: make [] 4 * len: cont/items/size
		;-- to support layouts that reposition previous items we have to fill the layout first, collect it later
		drawn: make [] len
		repeat i len [
			item: get name: cont/items/pick i
			append/only drawn unless item/size [render name]	;-- prerender to get the size, for layout
														;-- this allows to not render skipped items
														;@@ TODO: think on such caching applicability
														;@@ TODO: a cache of sizes to faster skip to the first visible item, or in layout?
			layout/place name
		]
		map: layout/map									;-- call if it's a function
		i: 0 foreach [name geom] map [					;@@ should be for-each [/i name geom] but it's slower
			i: i + 1
			set [_: pos: _: siz: _: org:] geom
			skip?: all [xy2  not bbox-overlap?  pos pos + siz  xy1 xy2]
			unless skip? [
				; compose/only/into [translate (pos + org) (idrawn)] tail r
				compose/deep/only/into [
					clip (pos) (pos + siz) [			;-- clip is required to support origin ;@@ but do we need origin?
						translate (pos + any [org 0]) 
						(any [drawn/:i  render name])
					]
				] tail r
			]
		]
		append clear cont/map map						;-- compose-map cannot be used because it calls render an extra time
		maybe cont/size: layout/size
		r
	]

	spaces/container: make-template 'space [
		size: none				;-- only available after `draw` because it applies styles
		item-list: []
		items: function [/pick i [integer!] /size] [
			either pick [item-list/:i][length? item-list]
		]
		map: []

		draw: function [/only xy1 [pair! none!] xy2 [pair! none!] /layout lobj [object!]] [
			#assert [layout]							;-- has to be provided by the wrapping space
			~/draw self lobj xy1 xy2
		]
	]
]

;@@ `list` is too common a name - easily get overridden and bugs ahoy
;@@ need to stash all these contexts somewhere for external access
list-ctx: context [
	spaces/list: make-template 'container [
		axis: 'x
		margin: 5x5
		spacing: 5x5
		;@@ TODO: alignment?
		;@@ this requires /size caching - ensure it is cached (e.g. as `content` which is generic and may be a list)
		;@@ or use on-deep-change to update size - what will incur less recalculations?

		make-layout: function [] [
			also r: make layouts/list []
			foreach w [axis margin spacing] [r/:w: self/:w]
		]

		container-draw: :draw
		draw: function [/only xy1 [pair! none!] xy2 [pair! none!]] [
			container-draw/layout/only make-layout xy1 xy2
		]
	]
]


row-ctx: context [
	spaces/row: make-template 'list [
		
	]
]


tube-ctx: context [
	spaces/tube: make-template 'container [
		width:   100
		margin:  5x5
		spacing: 5x5
		align:   [-1 -1]
		axes:    [s e]

		make-layout: function [] [
			also r: make layouts/tube []
			foreach w [width margin spacing align axes] [r/:w: self/:w]
		]

		container-draw: :draw
		draw: function [/only xy1 [pair! none!] xy2 [pair! none!]] [
			container-draw/layout/only make-layout xy1 xy2
		]
	]
]



;-- a polymorphic style: given `data` creates a visual representation of it
;@@ TODO: complex types should leverage table style
spaces/data-view: make-template 'space [
	size:    none					;-- only available after `draw` because it applies styles
	data:    none					;-- ANY red value
	width:   none					;-- when set, forces output to have fixed width (can be a list)
	margin:  0x0
	spacing: 5x5					;-- used only when data is a block
	;@@ TODO: add `/font`?
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
			block? :data [								;-- only recreates item spaces as necessary
				unless content = 'list [set-quiet 'content make-space/name 'list []]
				list: get content
				maybe list/margin: 0x0					;-- fit the list contents tightly, as we already have a margin
				maybe list/spacing: spc: spacing * 1x1	;-- ensure a pair value
				mrg: margin * 1x1
				n: length? data
				;-- evenly distribute the items	only when width is fixed:  ;@@ any better idea??
				;@@ also how to or should we apply width to images?
				item-width: all [width  to 1 width - (n - 1 * spc/x) - (2 * mrg/x) / n]
				repeat i n [
					value: :data/:i
					unless item: list/item-list/:i [
						append list/item-list item: anonymize 'item make-space 'data-view []
					]
					item: get item
					maybe item/width: item-width
					set/any 'item/data :value
					item/set-content
				]
				clear skip list/item-list n
			]
			image? :data [
				unless content = 'image [set-quiet 'content make-space/name 'image []]
				img: get content
				img/data: data			;@@ copy or not? images consume RAM easily; need them at least GC-able to copy
				; img/data: copy data
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
		sz: (mrg: margin * 1x1) * 2 + obj/size
		case/all [
			lim: limits/min/x [sz/x: max lim sz/x]
			lim: limits/min/y [sz/y: max lim sz/y]
			lim: limits/max/x [sz/x: min lim sz/x]
			lim: limits/max/y [sz/y: min lim sz/y]
		]
		self/size: sz
		change/only change map content compose [offset: (mrg) size: (sz - mrg)]
		compose/deep/only [
			clip 0x0 (sz) [				;@@ clipping should be done automatically somewhere for all spaces
				translate (mrg) (cdraw)
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


window-ctx: context [
	spaces/window: make-template 'space [
		;-- when drawn auto adjusts it's `size` up to `max-size` (otherwise scrollbars will always be visible)
		max-size: 1000x1000

		;-- window does not require content's size, so content can be an infinite space!
		content: make-space/name 'space []
		map: [space [offset 0x0 size 0x0]]				;-- 'space' will be replaced by space content refers to
		map/1: content

		;-- should be defined in content
		;-- should return how much more window can be scrolled in specified direction (from it's edge, not current origin!)
		;-- if it returns more than requested, returned value is added
		available?: function [
			"Should return number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
			axis      [word!]    "x/y"
			dir       [integer!] "-1/1"
			from      [integer!] "axis coordinate to look ahead from"
			requested [integer!] "max look-ahead required"
		][
			cspace: get content
			either function? cavail?: select cspace 'available? [	;-- use content/available? when defined
				cavail? axis dir from requested
			][														;-- otherwise deduce from content/size
				csize: any [cspace/size 0x0]						;@@ or assume infinity if no /size in content?
				clip [0 requested] either dir < 0 [from][csize/:axis - from]
			]
		]

		cached-offset: none
		draw: function [/only xy1 [pair!] xy2 [pair!]] [
			#debug grid-view [#print "window/draw is called with xy1=(xy1) xy2=(xy2)"]
			#assert [word? content]
			map/1: content								;-- rename it properly
			cspace: get content
			geom: map/:content
			o: geom/offset
			;-- there's no size for infinite spaces so we use `available?` to get the drawing size
			s: max-size
			o': cached-offset							;-- geom/offset during previous draw
			if o <> o' [								;-- don't resize window unless it was moved
				foreach x [x y] [s/:x: available? x 1 (0 - o/:x) s/:x]
				self/size: s							;-- limit window size by content size
				#debug list-view [#print "window resized to (s)"]
				set-quiet in self 'cached-offset o
			]
			default xy1: 0x0
			default xy2: s
			geom/size: xy2 - o							;-- enough to cover the visible area
			cdraw: render/only content xy1 - o xy2 - o
			compose/only [translate (o) (cdraw)]
		]
	]
]

inf-scrollable-ctx: context [
	spaces/inf-scrollable: make-template 'scrollable [	;-- `infinite-scrollable` is too long for a name
		jump-length: 200						;-- how much more to show when rolling (px) ;@@ maybe make it a pair?
		look-around: 50							;-- zone after head and before tail that triggers roll-edge (px)
		pages: 10x10							;-- window size multiplier in sizes of inf-scrollable

		content: 'window
		window: make-space 'window [size: none]			;-- size is set by window/draw
		#assert [map/1 = 'space]
		map/1: 'window

		roll-timer: make-space 'timer [rate: 4]			;-- how often to call `roll` when dragging
		append map [roll-timer [offset 0x0 size 0x0]]

		roll: function [] [
			#debug grid-view [#print "origin in inf-scrollable/roll: (origin)"]
			wo: wo0: 0x0 - window/map/(window/content)/offset	;-- (positive) offset of window within it's content
			#assert [window/size]
			ws: window/size
			before: 0x0 - origin
			after:  ws - (before + map/window/size)
			foreach x [x y] [
				any [		;-- prioritizes left/up jump over right/down
					all [
						before/:x <= look-around
						0 < avail: window/available? x -1 wo/:x jump-length
						wo/:x: wo/:x - avail
					]
					all [
						after/:x  <= look-around
						0 < avail: window/available? x  1 wo/:x + ws/:x jump-length
						wo/:x: wo/:x + avail
					]
				]
			]
			maybe self/origin: origin + (wo - wo0)	;-- transfer offset from scrollable into window, in a way detectable by on-change
			maybe window/map/(window/content)/offset: 0x0 - wo
			wo <> wo0								;-- should return true when updates origin - used by event handlers
		]

		autosize-window: function [] [
			#assert [all [size size/x > 0 size/y > 0]]
			maybe window/max-size: pages * self/size
			#debug list-view [#print "autosized window to (window/max-size)"]
		]

		scrollable-draw: :draw
		draw: function [] [
			unless window/size [autosize-window]		;-- 1st draw call automatically sizes the window
			scrollable-draw
		]
	]
]


;@@ just for testing ;@@ TODO: beautify it and draw a spider at random location, or leave it to the others as a challenge
;@@ TODO: explore fractals this way :D
spaces/web: make-template 'inf-scrollable [
	canvas: make-space 'space [
		available?: function [axis dir from requested] [requested]
	
		draw: function [/only xy1 xy2] [
			#assert [only]
			center: 100x100
			sectors: 12
			t: tangent (sec: 360 / sectors) / 2
			size: xy2 - xy1
			corners: map-each corner 2x2 [corner - 1x1 * size + xy1 - center]
			radii: minmax-of map-each/eval c corners [vec-length? c]
			either within? 0x0 corners/1 size + 1 [
				angles: [0 360]
				radii/1: 0
			][
				angles: minmax-of map-each c corners [
					(arctangent2 c/y c/x) // 360
				]
				;-- try to determine the closest radius approximately
				reserve: max size/x / 2 size/y / 2		;-- for when center gets out of the viewport
				radii/1: sqrt max 0 radii/1 ** 2 - (reserve ** 2)
				radii/1: radii/1 * cosine sec / 2		;-- for when looking at distant web joint points
			]
			sec-draw: map-each i sectors [
				a: i - 1 * sec
				unless all [angles/1 <= (a + sec) a <= angles/2] [continue]
				lvl1: round/to/floor   sqrt radii/1 1
				lvl2: round/to/ceiling sqrt radii/2 1
				levels: map-each/eval lvl lvl2 - lvl1 + 1 [
					r: lvl + lvl1 ** 2
					p: as-pair r r * t
					['line p p * 1x-1]
				]
				compose/deep/only [
					rotate (a) [line (radii/1 * 1x0) (radii/2 * 1x0)]
					rotate (a + (sec / 2)) (levels)
				]
			]
			compose/only [translate (center) (sec-draw)]
		]
	]

	window/content: 'canvas
]

list-view-ctx: context [
	spaces/list-view: make-template 'inf-scrollable [
		; reversed?: no		;@@ TODO - for chat log, map auto reverse
		; cached?: no			;@@ TODO - cache of rendered code of items, to make it more realtime (will need invalidation after resize)
		pages: 10
		source: []
		data: function [/pick i [integer!] /size] [		;-- can be overridden
			either pick [source/:i][length? source]		;-- /size may return `none` for infinite data
		]
		
		wrap-data: function [item-data [any-type!]][
			spc: make-space 'data-view []
			set/any 'spc/data :item-data
			if list/axis = 'y [							;@@ what data width to use for horizontal lists?
				spc/width: max 1 window/max-size/x - (list/margin/x * 2)	;-- has to be positive
			]
			anonymize 'item spc
		]

		list: make-space 'list [
			axis: 'y
			icache: make map! []	;-- cache of last rendered item spaces (persistency required by the focus model: items must retain sameness)
									;-- an int->word map! - for flexibility in caching strategies (which items to free and when)
									;@@ when to forget these?
			rcache: make map! []	;-- cache of rendering code saved by locate-line

			items: function [/pick i [integer!] /size] [
				either pick [
					any [
						icache/:i
						icache/:i: wrap-data data/pick i
					]
				][data/size]
			]

			available?: function [axis dir from [integer!] requested [integer!]] [
				if axis <> self/axis [
					return either dir < 0 [from][window/max-size/:axis - from]
				]
				set [item: idx: ofs:] locate-line from + (requested * dir)
				r: max 0 requested - switch item [
					space item [0]
					margin [either idx = 1 [0 - ofs][ofs - margin/:axis]]
				]
				#debug list-view [#print "available? dir=(dir) from=(from) req=(requested) -> (r)"]
				r
			]

			;-- returns any of:
			;--   [margin 1 offset] - within the left margin (or if point is negative, then to the left of it)
			;--   [item   1 offset] - within 1st cell
			;--   [space  1 offset] - within space between 1st and 2nd cells
			;--   [item   2 offset] - within 2nd cell
			;--   [space  2 offset]
			;--   ...
			;--   [item   N offset]
			;--   [margin 2 offset] - within the right margin
			;--                       offset can be bigger(!) than right margin if point is outside the space's size
			;-- location is done from the first item in the map, not from the beginning
			;-- so eventually if previous items change size, list origin may drift from 0x0
			;@@ will this cause problems?
			locate-line: function [level [integer!] "pixels from 0"] [
				x: axis
				if level < margin/:x [return compose [margin 1 (level)]]
				#debug list-view [level0: level]		;-- for later output

				either empty? map [
					i: 1
					level: level - margin/:x
				][
					#assert [not empty? icache]
					#assert ['item = map/1]
					item-spaces: reduce values-of icache
					i: pick keys-of icache j: index? find/same item-spaces get map/1
					level: level - map/2/offset/:x
				]
				imax: data/size
				space: spacing							;-- return value is named "space"
				;@@ should this func use layout at all or it will only complicate things?
				sub: function [name idx] [		;@@ move these funcs out
					size: get name
					if level < size/:x [throw reduce [name idx level]]
					set 'level level - size/:x
				]
				add: function [name idx] [
					size: get name
					set 'level level + size/:x
					if level >= 0 [throw reduce [name idx level]]
				]
				render-item: [
					rcache/:i: render name: items/pick i
					item: select get name 'size
				]
				r: catch [
					either level >= 0 [
						imax: any [imax 1.#inf]			;-- if undefined
						forever [
							do render-item
							sub 'item i
							if i >= imax [throw compose [margin 2 (level)]]
							sub 'space i
							i: i + 1
						]
					][
						forever [
							i: i - 1
							#assert [0 < i]
							add 'space i
							do render-item
							add 'item i
						]
					]
				]
				#debug list-view [#print "locate-line (level0) -> (mold r)"]
				#assert [0 < r/2]
				r
			]

			item-length?: function [i [integer!]] [
				#assert [0 < i]
				#assert [icache/:i]
				item: get icache/:i							;-- must be cached by previous locate-line call
				r: item/size/:axis
				#debug list-view [#print "item-length? (i) -> (r)"]
				r
			]

			locate-range: function [low-level [integer!] high-level [integer!]] [
				set [l-item: l-idx: l-ofs:] locate-line  low-level
				set [h-item: h-idx: h-ofs:] locate-line high-level
				sp: spacing/:axis
				mg: margin/:axis
				switch l-item [
					space  [l-idx: l-idx + 1  l-ofs: l-ofs - sp]
					margin [
						l-ofs: l-ofs - mg
						if l-idx = 2 [l-idx: none]
					]
				]
				switch h-item [
					space [h-ofs: h-ofs + item-length? h-idx]
					margin [
						either h-idx = 1 [
							h-idx: none
						][
							h-idx: data/size				;-- can't be none since right margin is present
							either h-idx <= 0 [				;-- data/size can be 0, then there's no item to draw
								h-idx: none
							][
								h-ofs: h-ofs + item-length? h-idx
							]
						]
					]
				]
				r: reduce [l-idx l-ofs h-idx h-ofs]
				#debug list-view [#print "locate-range (low-level),(high-level) -> (mold r)"]
				r
			]

			;-- leverages certain list properties as an optimization, so is not based on container/draw
			draw: function [/only xy1 [pair!] xy2 [pair!]] [
				#assert [all [xy1 xy2]]
				clear rcache								;-- may be filled by locate-range
				set [i1: o1: i2: o2:] locate-range xy1/:axis xy2/:axis
				unless all [i1 i2] [return []]				;-- no visible items (see locate-range)
				#assert [i1 <= i2]

				layout: make-layout
				guide: select [x 1x0 y 0x1] axis
				layout/origin: guide * (xy1 - o1 - margin)
				r: make [] 4 * (i2 - i1 + 1)
				clear map
				for i: i1 i2 [
					item: get name: items/pick i
					drawn: any [rcache/:i  render name]		;-- render to get the size, for layout
					placed: layout/place name
					compose/only/into [translate (placed/2/2) (drawn)] tail r
				]
				append map layout/map						;-- compose-map cannot be used because it calls render an extra time
				self/size: xy1 - margin - o1 + layout/size	;@@ do we even care about the size of the list itself here?
															;@@ should size/x be that of list-view/size/x ?
				r
			]
		]

		window/content: 'list

		autosize-window: function [] [						;-- initially, adjust the window (paragraphs adjust to it then)
			unit: select [x 1x0 y 0x1] list/axis
			#assert [0x0 <> size]
			maybe window/max-size: size + (pages - 1 * size * unit)
			#assert [0x0 <> window/max-size]
			#debug list-view [#print "autosized window to (window/max-size)"]
		]

		; inf-scrollable-draw: :draw
		; draw: function [] [
		; 	inf-scrollable-draw							;-- calls list/draw/only eventually
		; ]

		inf-scrollable-on-change: :on-change*
		on-change*: function [word [word! set-word!] old [any-type!] new [any-type!]] [
			switch to word! word [
				axis [
					if :old <> :new [
						#assert [find [x y] :new]
						clear list/map					;-- see `setup`: this changes window/max-size
					]
				]
			]
			inf-scrollable-on-change word :old :new
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
	spaces/cell: make-template 'space [
		map: [space [offset 0x0 size 0x0]]
		; map/1: make-space/name 'space []
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

	spaces/grid: make-template 'space [
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
			limits: self/limits								;-- call it in case it's a function
			unless any ['auto = limits/x  'auto = limits/y] [	;-- no auto limit set (but can be none)
				#debug grid-view [#print "grid/calc-limits [no auto] -> (limits)"]
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
			#assert [all [lim/x lim/y]]
			#debug grid-view [#print "grid/calc-limits [auto] -> (lim)"]
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
		get-span: function [
			"Get the span value of a cell at XY"
			xy [pair!] "Column (x) and row (y)"
		][
			any [spans/:xy  1x1]
		]

		get-first-cell: function [
			"Get the starting row & column of a multicell that occupies cell at XY"
			xy [pair!] "Column (x) and row (y); returns XY unchanged if no such multicell"
		][
			span: get-span xy
			if span ◄ 1x1 [xy: xy + span]
			xy
		]

		break-cell: function [first [pair!]] [
			if 1x1 <> span: get-span first [
				#assert [1x1 ◄= span]					;-- ensure it's a first cell of multicell
				xyloop xy span [
					remove/key spans xy': first + xy - 1x1
					;@@ invalidate content within ccache?
				]
			]
		]

		unify-cells: function [first [pair!] span [pair!]] [
			if 1x1 <> old: get-span first [
				if old ◄ 1x1 [
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
			#assert [1x1 ◄= span]						;-- forbid setting to span to non-positives
			xyloop xy span [							;-- break all multicells within the area
				cell: first + xy - 1
				old-span: get-span cell
				if old-span <> 1x1 [
					all [
						not force
						any [cell <> first  1x1 ◄= old-span]	;-- only `first` is broken silently if it's a multicell
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
		;@@ TODO: maybe cache offsets for faster navigation on bigger data
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
					if n <> sub n sp + def [size: def throw 1]	;-- point is within a row/col of default size
				][											;-- `default: auto` case where each row size is different
					#assert [array =? heights]
					repeat j n [
						size: row-height? from + j
						if 0 = sub 1 sp + size [throw 1]	;-- point is within the last considered row (size is valid)
					]
				]
			]

			size: none
			either 1 = len: length? array [					;-- 1 = special case - all cells are of their default size
				catch [sub-def 0 level]						;@@ assumes default size > 0 (at least 1 px) - need to think about 0
			][
				keys: sort keys-of array
				remove find keys 'default
				#assert [0 < keys/1]						;-- no zero or negative row/col numbers expected
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
			unless size [
				size: either axis = 'x [col-width? 1 + whole][row-height? 1 + whole]	;@@ optimize this?
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
			limits: any [draw-ctx/limits draw-ctx/limits: cells/size]	;-- may be none if called from calc-limits before grid/draw
			; #assert [draw-ctx/limits]
			xlim: limits/x
			#assert [integer? xlim]						;-- row size cannot be calculated for infinite grid
			hmin: append clear [] min-row-height
			for x: 1 xlim [
				span: get-span xy: as-pair x y
				if span/x < 0 [continue]				;-- skip cells of negative x span (counted at span = 0 or more)
				first: get-first-cell xy
				height1: 0
				if content: cells/pick first [
					unless draw-ctx/ccache/:first [			;-- only render if not cached
						render wrap-space first content		;-- cell caches drawn content by itself
					]
					cspace: get content
					height1: cspace/size/y
				]
				case [
					span/y = 1 [
						#assert [0 < span/x]
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
			not pinned ◄ xy
		]

		infinite?: function [] [
			limits: self/limits							;-- call it in case it's a function
			not all [limits/x limits/y]
		]

		calc-size: function [] [
			#debug grid-view [#print "grid/calc-size is called!"]
			#assert [not infinite?]
			limits: any [draw-ctx/limits draw-ctx/limits: cells/size]	;@@ optimize this? cache limits?
			limits: as-pair limits/x limits/y
			r: margin * 2 + (spacing * max 0x0 limits - 1)
			repeat x limits/x [r/x: r/x + col-width?  x]
			repeat y limits/y [r/y: r/y + row-height? y]
			#debug grid-view [#print "grid/calc-size -> (r)"]
			r
		]

		;-- due to the number of parameters this space has,
		;-- a special context is required to minimize the number of wasted calculations
		;-- however a care should be taken so that grid can contain itself (draw has to be reentrant)
		draw-ctx: context [
			ccache: make map! []		;-- cached `cell` spaces (persistency required by the focus model: cells must retain sameness)
			limits: none
			size:   none
			cleanup: function [] [
				self/size: self/limits: none
				foreach [xy name] ccache [
					cspace: get name
					cspace/cdrawn: none
					;@@ TODO: clean up cell-spaces themselves that go out of the window
				]
			]

		]

		;@@ need to think more about this.. I don't like it
		invalidate: func [/only row [integer!]] [
			either only [remove/key hcache row][clear hcache]	;-- clear should never be called on big datasets
			;@@ ccache?
		]

		;@@ TODO: at least for the chosen range, cell/drawn should be invalidated and cell/size recalculated
		draw-range: function [
			"Used internally by DRAW. Returns map slice & draw code for a range of cells"
			cell1 [pair!] cell2 [pair!] start [pair!] "Offset from origin to cell1"
		][
			size:  cell2 - cell1 + 1
			drawn: make [] size: size/x * size/y
			map:   make [] size * 2
			done:  make map! size						;-- local to this range of cells
														;-- sometimes the same mcell may appear in pinned & normal part
			for cell: cell1 cell2 [
				cell1-to-cell: either cell/x = cell1/x [	;-- pixels from cell1 to this cell
					get-offset-from cell1 cell
				][
					cell1-to-cell + get-offset-from cell - 1x0 cell		;-- faster to get offset from the previous cell
				]

				mcell: get-first-cell cell					;-- row/col of multicell this cell belongs to
				unless mcell-name: cells/pick mcell [continue]	;-- cell is not defined? skip the draw
				if done/:mcell [continue]					;-- skip mcells that were drawn for this group
				done/:mcell: true							;-- mark it as drawn
				
				pinned?: is-cell-pinned? cell
				mcell-to-cell: get-offset-from mcell cell	;-- pixels from multicell to this cell
				draw-ofs: origin + start + cell1-to-cell - mcell-to-cell	;-- pixels from draw's 0x0 to the draw box of this cell
				
				mcname: wrap-space mcell mcell-name
				mcspace: get mcname
				mcspace/cdrawn: none						;@@ allows grid to contain itself, but may be a resource waste?
				render mcname								;-- render cell content before getting it's size
															;-- cell caches it's rendered content by itself
															;@@ TODO: invalidate this cache in dc/cleanup or somewhere
				mcsize: cell-size? mcell					;-- size of all rows/cols it spans
				mcspace/size: mcsize						;-- update cell's size to cover it's rows/cols fully,
															;-- not just the size of it's content
				mcdraw: render mcname						;-- re-render (cached) to draw the full background
				;@@ TODO: if grid contains itself, map should only contain each cell once - how?
				compose/deep/into [							;-- map may contain the same space if it's both pinned & normal
					(anonymize 'cell mcspace) [offset (draw-ofs) size (mcsize)]
				] tail map
				compose/only/into [							;-- compose-map calls extra render, so let's not use it here
					translate (draw-ofs) (mcdraw)			;@@ can compose-map be more flexible to be used in such cases?
				] tail drawn
			]
			reduce [map drawn]
		]

		;@@ remove origin and infer it from xy1
		draw: function [/only xy1 xy2] [
			#debug grid-view [#print "grid/draw is called with xy1=(xy1) xy2=(xy2)"]
			;@@ keep this in sync with `list/draw`
			#assert [any [not infinite?  all [xy1 xy2]]]	;-- limits must be defined for an infinite grid

			dc: draw-ctx
			;@@ TODO: only clear dc & map for the outermost draw (in case grid contains itself)
			dc/cleanup
			; clear map
			new-map: make [] 100

			dc/limits: cells/size
			#assert [dc/limits]
			;-- locate-point calls row-height which may render cells when needed to determine the height
			default xy1: 0x0
			unless xy2 [dc/size: xy2: calc-size]

			unless pinned ◄= 0x0 [
				set [map: drawn-common-header:] draw-range 1x1 pinned (margin + xy1)
				xy1: (xy0: xy1 + margin) + get-offset-from 1x1 (pinned + 1x1)
				append new-map map
			]
			#debug grid-view [#print "drawing grid from (xy1) to (xy2)"]

			set [cell1: offs1:] locate-point xy1
			set [cell2: offs2:] locate-point xy2
			all [none? dc/size  not infinite?  dc/size: calc-size]
			; unless self/size [maybe self/size: dc/size]
			maybe self/size: dc/size

			if pinned/x > 0 [
				set [map: drawn-row-header:] draw-range
					(1 by cell1/y) (pinned/x by cell2/y)
					xy0/x by (xy1/y - offs1/y)
				append new-map map
			]
			if pinned/y > 0 [
				set [map: drawn-col-header:] draw-range
					(cell1/x by 1) (cell2/x by pinned/y)
					(xy1/x - offs1/x) by xy0/y
				append new-map map
			]

			set [map: drawn-normal:] draw-range cell1 cell2 (xy1 - offs1)
			append new-map map
			;-- note: draw order (common -> headers -> normal) is important
			;-- because map will contain intersections and first listed spaces are those "on top" from hittest's POV
			;-- as such, map doesn't need clipping, but draw code does

			append clear self/map new-map				;-- this trick allows grid to contain itself
 			reshape [
				;-- headers also should be fully clipped in case they're multicells, so they don't hang over the content:
				clip  0x0         !(xy1)            !(drawn-common-header)	/if drawn-common-header
				clip !(xy1 * 1x0) !(xy2/x by xy1/y) !(drawn-col-header)		/if drawn-col-header
				clip !(xy1 * 0x1) !(xy1/x by xy2/y) !(drawn-row-header)		/if drawn-row-header
				clip !(xy1)       !(xy2)            !(drawn-normal)
			]
		]

		on-change*: function [word [word! set-word!] old [any-type!] new [any-type!]] [
			switch to word! word [
				;@@ TODO: think on what other words incur cache invalidation
				cells [draw-ctx/cleanup]			;-- cache becomes invalid
			]
		]
	]
]


grid-view-ctx: context [
	spaces/grid-view: make-template 'inf-scrollable [
		source: make map! [size: 0x0]					;-- map is more suitable for spreadsheets than block of blocks
		data: function [/pick xy [pair!] /size] [
			switch type?/word :source [
				block! [
					case [
						pick [source/(xy/2)/(xy/1)]
						0 = n: length? source [0x0]
						'else [as-pair length? :source/1 n]
					]
				]
				map! [either pick [source/:xy][source/size]]
				'else [#assert [no "Unsupported data format"]]
			]
		]

		grid: make-space 'grid [
			available?: function [axis dir from [integer!] requested [integer!]] [	;@@ should `available?` be in *every* grid? (as a placeholder word)
				;; gets called before grid/draw by window/draw to estimate the max window size and thus config scrollbars accordingly
				#debug grid-view [print ["grid/available? is called at" axis dir from requested]]	
				limits: self/limits
				#assert [limits "data/size is none!"]
				r: case [
					dir < 0 [from]
					limits/:axis [
						size: calc-size		;@@ optimize calc-size?
						size/:axis - from
					]
					'infinite [requested]
				]
				r: clip [0 r] requested
				#debug grid-view [#print "avail?/(axis) (dir) = (r) of (requested)"]
				r
			]
		]
		grid-cells: :grid/cells
		grid/cells: func [/pick xy [pair!] /size] [
			either pick [
				unless grid/cell-map/:xy [			;@@ need to think when to free this up, maybe when cells get hidden
					grid/cell-map/:xy: wrap-data xy data/pick xy
				]
				grid-cells/pick xy
			][data/size]
		]
		grid/calc-limits: grid/limits: does [data/size]
		
		wrap-data: function [xy [pair!] item-data [any-type!]] [
			spc: make-space 'data-view []
			set/any 'spc/data :item-data
			spc/width: (grid/col-width? xy/x) - (spc/margin/x * 2)
			anonymize 'item spc
		]

		window/content: 'grid

		setup: function [] [
			if size [
				;@@ TODO: jump-length should ensure window size is bigger than viewport size + jump
				;@@ situation when jump clears a part of a viewport should never happen at runtime
				maybe self/jump-length: min size/x size/y
			]
		]

		inf-scrollable-draw: :draw
		draw: function [] [
			#debug grid-view [#print "grid-view/draw is called! passing to inf-scrollable"]
			setup
			; grid/origin: self/origin		;@@ maybe remove grid/origin and make it inferred from /only xy1 ?
			inf-scrollable-draw
		]
	]
]



; spacer: make-space 'space [				;-- empty space, used for padding
; 	draw: []
; ]

button-ctx: context [
	spaces/button: make-template 'data-view [
		; width: none								;-- when not 'none', forces button width in pixels - defined by data-view
		margin: 4x4								;-- change data-view's default
		pushed?: no								;-- becomes true when user pushes it; triggers `command`
		rounding: 5								;-- box rounding radius in px
		command: []								;-- code to run on click (on up: when `pushed?` becomes false)
		;@@ TODO: shadow? or in styles? and for what other spaces?

		data-view-draw: :draw
		draw: function [] [
			drawn: data-view-draw				;-- draw content before we know it's size
			new: margin * 2 + size
			self/size: as-pair any [width new/x] new/y
			;-- box has to come before the content, so whatever fill-pen is used by style it won't override the text
			compose/deep/only [
				box 1x1 (size - 1) (rounding)
				translate (margin) (drawn)
			]
		]

		data-view-on-change: :on-change*
		on-change*: function [word [word!] old [any-type!] new [any-type!]] [
			switch to word! word [
				;-- special handling to prevent command from being evaluated multiple times on key press & hold:
				pushed? [if all [:old not :new] [do command]]
			]
			data-view-on-change word :old :new
		]
	]
]



spaces/rotor: make-template 'space [
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
spaces/field: make-template 'scrollable [
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
		pdrawn: para/draw								;-- no `render` to not start a new style
		xy1: caret-to-offset       para/layout caret-index + 1
		xy2: caret-to-offset/lower para/layout caret-index + 1
		caret/size: as-pair caret-width xy2/y - xy1/y
		cdrawn: []
		if active? [
			cdrawn: compose/only [translate (xy1) (render 'caret)]
		]
		compose [(cdrawn) (pdrawn)]
	]
]

spaces/spiral: make-template 'space [
	size: 100x100
	content: 'field			;-- reuse field to apply it's event handlers
	field: make-space 'field [size: 999999999x9999]		;-- it's infinite

	into: function [xy [pair!] /force name [word! none!]] [
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
		render: clear []		;@@ this is a bug, really
		;@@ TODO: initial angle
		append render compose [translate (size / 2)]
		repeat i len [			;@@ should be for-each [/i c]
			c: text/:i
			bgn: caret-to-offset r i
			cycles: bgn/x / 2 / pi / rmid
			scale: decay ** cycles
			box: []
			if all [field/active?  i - 1 = field/caret-index] [
				box: compose [box (p) (p + as-pair field/caret-width full/y)]
			]
			compose/deep/into [
				push [
					rotate (cycles * 360)
					scale (scale) (scale)
					(box)
					text (p) (form c)
				]
			] tail render
		]
		render
	]
]

export exports