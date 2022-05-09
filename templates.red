Red [
	title:   "Draw-based widgets (Spaces) definitions"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires `for` loop from auxi.red, layouts.red, export


;@@ TODO: also a `spaces` context to wrap everything, to save it from being overridden (or other name, or under system/)


#macro [#on-change-redirect] func [s e] [				;@@ see REP #115
	copy/deep [											;-- copy so it can be bound to various contexts
		on-change*: func [word [any-word!] old [any-type!] new [any-type!]] [
			~/on-change self word :old :new
		]
	]
]


exports: [make-space make-template space?]

space-object!: object [									;@@ workaround for #3804
	;; this slows down space creation a little but lightens it's `draw` which is more important
	;; because if on-change can't be relied upon, all initialization has to be done inside draw
	;; see label template for an example of the related house keeping
	on-change*: func [word old [any-type!] new [any-type!]] []
]

make-space: function [
	"Create a space from a template TYPE"
	type [word!]  "Looked up in templates"
	spec [block!] "Extension code"
	/block "Do not instantiate the object"
	/name "Return a word referring to the space, rather than space object"
][
	base: templates/:type
	#assert [any [
		block? base
		unless base [#print "*** Non-existing template '(type)'"]
		#print "*** Template '(type)' is of type (type? base)"
	]]
	r: append copy/deep base spec
	unless block [r: make space-object! r]
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
	r: make [] round/ceiling/to (1.5 * length? map) 1	;-- 3 draw tokens per 2 map items
	foreach [name box] map [
		all [list  not find list name  continue]		;-- skip names not in the list if it's provided
		; all [limits  not boxes-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
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


templates: #()											;-- map for extensibility

;; On limits:
;; to waste less RAM (each range is 468 bytes), a single range is used instead of two (X+Y)
;; this limits us a little bit but not much:
;;   no /limits defined in a space -- same as limits=none (any size is possible)
;;   limits: 'fixed                                   -- size is locked and not to be touched
;;   limits: none                                     -- size is unconstrained (no limits, default)
;;   limits: make range! [min: none  max: none]       -- ditto
;;   limits: make range! [min: 0x0   max: none]       -- ditto
;;   limits: make range! [min: 0x100 max: 999999x100] -- Y axis is fixed, X is practically unconstrained
;;   limits: make range! [min: 50    max: 200]        -- main axis is constrained, secondary is not
;; this allows to set each limit to a pair/number/none, where `none` means "fixed"
;; but it's impossible to have e.g. min-x = none, but min-y = 100
;; in this case zero (e.g. 0x100) should be used
;@@ doc this semantics once it's proven

templates/space: [										;-- minimum basis to build upon
	draw: []
	size: 0x0
	limits: none
	cache?: on
	; rate: none
]
space?: func [obj [any-type!]] [all [object? :obj  in obj 'draw  in obj 'size]]

templates/timer: make-template 'space [rate: none]		;-- template space for timers

;; has to be an object so these words have binding and can be placed as words into content field
generic: object [										;-- holds commonly used spaces ;@@ experimental
	empty: make-space 'space []							;-- used when no content is given
]

rectangle-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		unless :old =? :new [invalidate-cache space]
	]
	
	templates/rectangle: make-template 'space [
		size:   20x10
		margin: 0
		draw:   does [compose [box (margin * 1x1) (size - margin)]]
		#on-change-redirect
	]
]

triangle-ctx: context [
	~: self
	draw: function [space [object!]] [
		set [p1: p2: p3:] select [
			n [0x2 1x0 2x2]								;--   n
			e [0x0 2x1 0x2]								;-- w   e
			w [2x0 0x1 2x2]								;--   s
			s [0x0 1x2 2x0]
		] space/dir
		m: space/margin * 1x1
		r: space/size / 2 - m
		compose/deep [
			translate (m) [triangle (p1 * r) (p2 * r) (p3 * r)]
		]
	]
		
	; on-change*: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		; any [
			; :old =? :new
			; find select space 'quiet-words word			;@@ better name? 
			; set-quiet 'cache? 'invalid					;@@ reconsider if reactivity becomes possible
		; ]
	; ]
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		unless :old =? :new [invalidate-cache space]
	]
		
	templates/triangle: make-template 'space [
		size:    16x10						;@@ use canvas instead?
		dir:     'n
		margin:  0
		;@@ after the design is settled, maybe make cache the default and remove from everywhere?
		;@@ and provide a default on-change?
		; cache?:  off
		
		;@@ need `into` here? or triangle will be a box from the clicking perspective?
		draw: does [~/draw self]
		#on-change-redirect
	]
]

image-ctx: context [
	~: self
	
	draw: function [image [object!] canvas [pair! none!]] [
		;@@ haven't figured out image stretching yet... and limits - who should enforce them? and how should it be scaled?
		;@@ besides such stretching may be harmful: image has it's optimum size
		;@@ and stretching it by default would require one to work around it in most cases
		;@@ using fixed /size is a viable option but is a bit of a hack and I'm worried about consistency with other spaces
		; case [
			; not image? data [size: 0x0]
			; canvas [
				; size: subtract-canvas canvas 2x2 * margin
				; ?? size
				; case [
					; canvas +< infxinf ['nothing]
					; size/x >= infxinf/x [
						; size/x: either size/y = 0 [data/size/x][round/ceiling/to size/y * data/size/x / data/size/y 1]
					; ]
					; size/y >= infxinf/y [
						; size/y: either size/x = 0 [data/size/y][round/ceiling/to size/x * data/size/y / data/size/x 1]
					; ]
				; ]
				; ?? size
				; #assert [size +< infxinf]
			; ]
			; 'else [size: data/size]
		; ]
		; probe self/size: 2x2 * margin + size
		either image? image/data [
			maybe image/size: 2x2 * image/margin + image/data/size
			reduce ['image image/data 1x1 * image/margin image/data/size + image/margin]
		][
			maybe image/size: 2x2 * image/margin
			[]
		]
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if switch to word! word [
			margin [:old <> :new]
			data   [true] 								;-- can't know if image bits were changed, better to update
		] [invalidate-cache space]
	]
	
	templates/image: make-template 'space [
		size: none										;@@ should fixed size be used as an override?
		margin: 0
		; data: make image! 1x1			;@@ 0x0 dummy image is probably better but triggers too many crashes
		data: none										;-- images are not recyclable, so `none` by default
		draw: func [/on canvas [pair! none!]] [~/draw self canvas]
		#on-change-redirect
	]
]


cell-ctx: context [
	~: self

	allowed-alignments: make hash! [
		-1x-1 -1x0 -1x1
		 0x-1  0x0  0x1
		 1x-1  1x0  1x1
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			align [
				unless find allowed-alignments :new [	;@@ this is just an idea, not sure if worth it (maybe #debug?)
					set-quiet in space word :old
					ERROR "Invalid alignment specified: (mold/part :new 100)"
				]
				invalidate-cache space
			]
			;; `weight` invalidates parents by invalidating this cell
			limits weight content [invalidate-cache space]
		]
	]
	
	draw: function [space [object!] canvas [pair! none!]] [
		#assert [space/content]
		drawn:  render/on space/content if canvas [subtract-canvas canvas 2x2 * space/margin]
		cspace: get space/content
		size: 2x2 * space/margin + cspace/size
		if pair? canvas [								;-- canvas is already constrained by render
			;; canvas can be infinite or half-infinite: inf dimensions should be replaced by space/size
			mask: 1x1 - (canvas / infxinf)				;-- 0x0 (infinite) to 1x1 (finite)
			size: max size canvas * mask
		]												;-- no canvas = no alignment, minimal appearance
		space/size: constrain size space/limits
		
		free:   space/size - cspace/size
		offset: max 0x0 free * (space/align + 1) / 2
		unless tail? drawn [
			drawn: compose/only [translate (offset) (drawn)]
			; drawn: compose/only [clip 0x0 (space/size) translate (offset) (drawn)]
		]
		space/map/1: space/content
		space/map/2/offset: offset
		space/map/2/size: space/size
		drawn
	]
	
	templates/box: make-template 'space [
		align:   0x0									;@@ consider more high level VID-like specification of alignment
		margin:  0x0									;-- useful for drawing inner frame, which otherwise would be hidden by content
		weight:  1										;@@ what default weight to use? what default alignment?
		content: in generic 'empty						;@@ consider `content: none` optimization if it's worth it
		map:     reduce [content [offset 0x0 size 0x0]]
		;; cannot be cached, as content may change at any time and we have no way of knowing
		; cache?:  off
		
		#on-change-redirect
		
		;; draw/only can't be supported, because we'll need to translate xy1-xy2 into content space
		;; but to do that we'll have to render content fully first to get it's size and align it
		;; which defies the meaning of /only...
		;; the only way to use /only is to apply it on top of current offset, but this may be harmful
		draw: function [/on canvas [pair! none!]] [
			~/draw self canvas
		]
	]
	
	templates/cell: make-template 'box [margin: 1x1]	;-- same thing just with a border and background ;@@ margin - in style?
]

;@@ TODO: externalize all functions, make them shared rather than per-object
;@@ TODO: automatic axis inferrence from size?
scrollbar: context [
	~: self
	
	into: func [space [object!] xy [pair!] name [word! none!]] [
		any [space/axis = 'x  xy: reverse xy]
		into-map space/map xy name
	]
	
	draw: function [space [object!]] [
		size2: either space/axis = 'x [space/size][reverse space/size]
		h: size2/y  w-full: size2/x
		w-arrow: to 1 size2/y * 0.9
		w-inner: w-full - (2 * w-arrow)
		;-- in case size is too tight to fit the scrollbar - compress inner first, arrows next
		if w-inner < 0 [w-arrow: to integer! w-full / 2  w-inner: 0]
		w-thumb: case [						;-- 3 strategies for the thumb
			w-inner >= (2 * h) [max h w-inner * space/amount]	;-- make it big enough to aim at
			w-inner >= 8       [      w-inner * space/amount]	;-- better to have tiny thumb than none at all
			'else              [0]								;-- hide thumb, leave just the arrows
		]
		w-pgup:  w-inner - w-thumb + (w-inner * space/amount) * space/offset
		w-pgdn:  w-inner - w-pgup - w-thumb
		space/map/back-arrow/size:  quietly space/back-arrow/size:   sz: as-pair w-arrow h
		space/map/back-page/offset: o: sz * 1x0		;@@ TODO: this space filling algorithm can be externalized probably
		space/map/back-page/size:   quietly space/back-page/size:    sz: as-pair w-pgup  h
		space/map/thumb/offset:     o: sz * 1x0 + o
		space/map/thumb/size:       quietly space/thumb/size:        sz: as-pair w-thumb h
		space/map/forth-page/offset:   sz * 1x0 + o
		space/map/forth-page/size:  quietly space/forth-page/size:   sz: as-pair w-inner - w-thumb - w-pgup h	;-- compensates for previous rounding errors
		space/map/forth-arrow/offset:  w-full - w-arrow * 1x0		;-- arrows should stick to sides even for uneven sizes
		space/map/forth-arrow/size: quietly space/forth-arrow/size:  as-pair w-arrow h
		foreach [name _] space/map [invalidate-cache/only get name]
		compose/deep [
			push [
				matrix [(select [x [1 0 0 1] y [0 1 1 0]] space/axis) 0 0]
				(compose-map space/map)
			]
		]
	]
	
	on-change: function [bar [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [offset amount size axis [invalidate-cache bar]]
	]
				
	templates/scrollbar: make-template 'space [
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
		into: func [xy [pair!] /force name [word! none!]] [~/into self xy name]
		;@@ TODO: styling/external renderer
		draw: does [~/draw self]
		#on-change-redirect
	]
]

;@@ rename this to just `scrollable`?
;; it's not `-ctx` because move-by and move-to functions are meant of outside use
scrollable-space: context [
	~: self

	;@@ or /line /page /forth /back /x /y ?
	;@@ TODO: less awkward spec
	move-by: function [spc amnt "'line or 'page or offset in px" dir "forth or back" axis "x or y" /scale factor "1 by default"] [
		if word? spc [spc: get spc]
		dir:  select [forth 1 back -1] dir
		unit: select [x 1x0 y 0x1] axis
		default factor: 1
		switch amnt [line [amnt: 10] page [amnt: spc/map/(spc/content)/size]]
		spc/origin: spc/origin - (amnt * factor * unit * dir)
		; invalidate-cache spc
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
		; invalidate-cache spc
	]

	into: function [space [object!] xy [pair!] name [word! none!]] [
		if r: into-map space/map xy name [
			if r/1 =? space/content [
				cspace: get space/content
				r/2: r/2 - space/origin
				unless any [name  within? r/2 0x0 cspace/size] [r: none]
			]
		]
		r
	]

	draw: function [space [object!] canvas [none! pair!]] [
		;; find area of 'size' unobstructed by scrollbars - to limit content rendering
		;; canvas takes priority (for auto sizing), but only along constrained axes
		;@@ TODO: this size to canvas relationship is still tricky - need smth simpler
		box: either canvas [
			as-pair either canvas/x < 2e9 [canvas/x][space/size/x]
					either canvas/y < 2e9 [canvas/y][space/size/y]
		][
			space/size
		]
		origin: space/origin
		cspace: get space/map/1: space/content
		#debug grid-view [
			#print "scrollable/draw: renders content from (max 0x0 0x0 - origin) to (box - origin); box=(box)"
		]
		;; scroller's area is reserved, otherwise we'll see X scroller on vertical lists and vice versa:
		scrollers: space/vscroll/size/x by space/hscroll/size/y
		ccanvas: subtract-canvas max 1x1 box scrollers			;-- don't subtract from "infinite" pair
		;; render it before 'size' can be obtained, also render itself may change origin (in `roll`)!
		cdraw: render/only/on space/content		
			max 0x0 0x0 - origin
			box - origin
			ccanvas
		csz: cspace/size
		; #assert [0x0 +< (origin + csz)  "scrollable/origin made content invisible!"]
		;; ensure that origin doesn't go beyond content/size (happens when content changes e.g. on resizing)
		maybe space/origin: max origin box - scrollers - csz
		
		;; determine what scrollers to show
		p2: csz + p1: origin
		full: max 1x1 csz + (max 0x0 origin)
		clip-p1: max 0x0 p1
		loop 2 [										;-- each scrollbar affects another's visibility
			clip-p2: min box p2
			shown: min 100x100 (clip-p2 - clip-p1) * 100 / max 1x1 csz
			if hdraw?: shown/x < 100 [box/y: space/size/y - space/hscroll/size/y]
			if vdraw?: shown/y < 100 [box/x: space/size/x - space/vscroll/size/x]
		]
		
		;; set scrollers but avoid multiple recursive invalidation when changing srcollers fields
		;; (else may stack up to 99% of all rendering time)
		quietly space/hscroll/offset: ofs: 100% * (clip-p1/x - p1/x) / max 1 csz/x
		quietly space/hscroll/amount: min 100% - ofs 100% * box/x / full/x
		quietly space/vscroll/offset: ofs: 100% * (clip-p1/y - p1/y) / max 1 csz/y
		quietly space/vscroll/amount: min 100% - ofs 100% * box/y / full/y
		
		;@@ TODO: fast flexible tight layout func to build map? or will slow down?
		space/map/(space/content)/size: box
		space/map/hscroll/offset: box * 0x1
		space/map/vscroll/offset: box * 1x0
		space/hscroll/size/x: either hdraw? [box/x][0]
		space/vscroll/size/y: either vdraw? [box/y][0]
		space/map/hscroll/size: space/hscroll/size
		space/map/vscroll/size: space/vscroll/size
		
		; invalidate/only [hscroll vscroll]
		invalidate-cache/only space/hscroll
		invalidate-cache/only space/vscroll
		
		#debug grid-view [#print "origin in scrollable/draw: (origin)"]
		compose/deep/only [
			translate (origin) [						;-- special geometry for content
				clip (0x0 - origin) (box - origin)
				(cdraw)
			]
			(compose-map/only space/map [hscroll vscroll])
		]
	]
		
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		;@@ clip origin here or clip inside event handler? box isn't valid until draw is called..
		; print [mold word mold :old "->" mold :new]
		switch to word! word [
			;@@ problem: changing origin requires up to date content (no sync guarantee)
			;@@ maybe we shouldn't clip it right here?
			origin [
				#debug grid-view [#print "on-change origin: (mold :old) -> (mold :new)"]
				if all [pair? :new  word? space/content] [
					cspace: get space/content
					new: clip [(space/map/(space/content)/size - cspace/size) 0x0] new 
					set-quiet in space 'origin new
					#debug grid-view [#print "on-change clipped to: (space/origin)"]
					invalidate-cache space
				]
			]
			content [
				space/map/1: :new
				invalidate-cache space
			]
		]
	]
		
	templates/scrollable: make-template 'space [
		; cache?: off
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

		into: func [xy [pair!] /force name [word! none!]] [
			~/into self xy name
		]

		draw: function [/on canvas [none! pair!]] [~/draw self canvas]

		#on-change-redirect
	]
]

paragraph-ctx: context [
	~: self
	
	;@@ font won't be recreated on `make paragraph!`, but must be careful
	lay-out: function [space [object!] width [integer! none!] "wrap margin"] [
		unless space/layout [space/layout: rtd-layout [""]]
		layout: space/layout
		layout/text: as string! space/text
		layout/font: space/font						;@@ careful: fonts are not collected by GC, may run out of them easily
		either width [									;-- wrap
			layout/size: (max 1 width - (2 * space/margin/x)) by 2e9	;-- width has to be set to determine height
			#assert [0 < layout/size/x]						;@@ crashes on 0 - see #4897
		][												;-- no wrap
			layout/size: none
		]
		;; NOTE: #4783 to keep in mind
		layout/extra: size-text layout					;-- 'size-text' is slow, has to be cached (by using on-change)
	]

	draw: function [space [object!] canvas [pair! none!]] [
		layout: space/layout
		old-width: all [layout layout/size layout/size/x]		;@@ REP #113
		new-width: all [canvas canvas/x]
		if any [												;-- redraw if:
			none = layout										;-- some facet changed
			old-width <> new-width								;-- canvas width changed
		] [lay-out space new-width]
		
		;; size can be adjusted in various ways:
		;;  - if rendered < canvas, we can report either canvas or rendered
		;;  - if rendered > canvas, the same
		;; it's tempting to use canvas width and rendered height,
		;; but if canvas is huge e.g. 2e9, then it's not so useful,
		;; so just the rendered size is reported
		;; and one has to wrap it into a data-view space to stretch
		text-size: constrain space/layout/extra space/limits	;-- don't make it narrower than min limit
		maybe space/size: space/margin * 2x2 + text-size		;-- full size, regardless if canvas height is smaller?
		
		;; this is quite hacky: rich-text is embedded directly into draw block
		;; so when layout/text is changed, we don't need to call `draw`
		;; just reassigning host's `draw` block to itself is enough to update it
		;; (and we can't stop it from updating)
		;; direct changes to /text get reflected into /layout automatically long as it scales
		;; however we wish to keep size up to date with text content, which requires a `draw` call
		compose [text (1x1 * space/margin) (space/layout)]
	]

	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if all [
			find [text font margin] to word! word
			not :old =? :new
		][
			invalidate-cache space
			space/layout: none							;-- will be laid out on next `draw`
		]
	]
	
	;; every `make font!` brings View closer to it's demise, so it has to use a shared font
	;; styles may override `/font` with another font created in advance 
	;@@ BUG: not deeply reactive
	shared-font: make font! [name: system/view/fonts/sans-serif size: system/view/fonts/size]

	templates/paragraph: make-template 'space [
		size:   none									;-- only valid after `draw` because it applies styles
		text:   ""
		margin: 0x0										;-- default = no margin
		font:   none									;-- can be set in style, as well as margin

		layout: none									;-- internal, text size is kept in layout/extra
		; cache?: true
		draw: func [/on canvas [pair! none!]] [~/draw self canvas]
		#on-change-redirect
	]

	;; unlike paragraph, text is never wrapped
	templates/text: make-template 'paragraph [
		draw: does [~/draw self none]
	]

	;; url is underlined in style; is a paragraph for it's often long and needs to be wrapped
	templates/url: make-template 'paragraph []
]


;-- layout-agnostic template for list, ring & other layout using space collections
container-ctx: context [
	~: self

	;; all rendering is done by layout, because container by itself doesn't have enough info to perform it
	draw: function [
		cont [object!]
		type [word!]
		settings [block!]
		xy1 [pair! none!]
		xy2 [pair! none!]
		; canvas [pair! none!]
	][
		#assert [(none? xy1) = none? xy2]				;-- /only is ignored to simplify call in absence of `apply`
		len: cont/items/size
		#assert [len "container/draw works only for containers of limited items count"]
		r: make [] 4 * len
		
		drawn: make [] len * 6
		items: make [] len
		repeat i len [append items name: cont/items/pick i]		;@@ use map-each
		set [size: map:] make-layout type items settings
		i: 0 foreach [name geom] map [					;@@ should be for-each [/i name geom]
			i: i + 1
			pos: geom/offset
			siz: geom/size
			drw: geom/drawn
			#assert [drw]
			remove/part find geom 'drawn 2				;-- no reason to hold `drawn` in the map anymore
			skip?: all [xy2  not boxes-overlap?  pos pos + siz  xy1 xy2]
			unless skip? [
				org: any [geom/origin 0x0]
				compose/only/deep/into [
					;; clip has to be followed by a block, so `clip` of the next item is not mixed with previous
					; clip (pos) (pos + siz) [			;-- clip is required to support origin ;@@ but do we need origin?
						translate (pos + org) (drw)
					; ]
				] tail drawn
			]
		]
		cont/map: map									;-- compose-map cannot be used because it renders extra time ;@@ maybe it shouldn't?
		maybe cont/size: size
		drawn
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if find [items item-list] to word! word [invalidate-cache space]
	]

	templates/container: make-template 'space [
		size: none				;-- only available after `draw` because it applies styles
		item-list: []
		items: function [/pick i [integer!] /size] [
			either pick [item-list/:i][length? item-list]
		]
		map: []

		draw: function [
			/only xy1 [pair! none!] xy2 [pair! none!]
			; /on canvas [pair! none!]					;-- not used: layout gets it in settings instead
			/layout type [word!] settings [block!]
		][
			#assert [layout "container/draw requires layout to be provided"]
			~/draw self type settings xy1 xy2
		]
		#on-change-redirect
	]
]

;@@ `list` is too common a name - easily get overridden and bugs ahoy
;@@ need to stash all these contexts somewhere for external access
list-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		all [
			find [axis margin spacing] to word! word
			:old <> :new
			invalidate-cache space
		]
		space/container-on-change word :old :new
	]
	
	templates/list: make-template 'container [
		axis:    'x
		;; default spacing/margins must be tight, otherwise they accumulate pretty fast in higher level widgets
		;@@ VID layout styles may include nonzero spacing as defaults, unless tight option is used
		margin:  0x0
		spacing: 0x0
		;@@ TODO: alignment?
		; cache?:    off

		container-draw: :draw
		draw: function [/only xy1 [pair! none!] xy2 [pair! none!] /on canvas [pair! none!]] [
			settings: [axis margin spacing canvas]
			container-draw/layout/only 'list settings xy1 xy2
		]
		
		container-on-change: :on-change*
		#on-change-redirect
	]
]

ring-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		all [
			find [angle radius round?] to word! word
			:old <> :new
			invalidate-cache space
		]
		space/container-on-change word :old :new
	]
	
	templates/ring: make-template 'container [
		;; in degrees - clockwise direction to the 1st item (0 = right, aligns with math convention on XY space)
		angle:  0
		;; minimum distance (pixels) from the center to the nearest point of arranged items
		radius: 50
		;; whether items should be considered round, not rectangular
		round?: yes

		container-draw: :draw
		draw: does [container-draw/layout 'ring [angle radius round?]]
		
		container-on-change: :on-change*
		#on-change-redirect
	]
]


icon-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			; axis margin spacing [invalidate-cache space]		;-- handled by list itself
			image       [space/spaces/image/data: new]	;-- invalidation is done by inner spaces
			text        [space/spaces/text/text:  new]
		]
		space/list-on-change word :old :new
	]
	
	templates/icon: make-template 'list [
		axis:   'y
		margin: 0x0
		image:  none
		text:   ""
		
		spaces: context [
			image: make-space 'image []
			text:  make-space 'paragraph []
			box:   make-space 'box [content: 'text]	;-- used to align paragraph
			set 'item-list [image box]
		]
		
		list-on-change: :on-change*
		#on-change-redirect
	]
]



tube-ctx: context [
	~: self

	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if find [margin spacing axes align width] word [invalidate-cache space]
		space/container-on-change word :old :new
	]
	
	templates/tube: make-template 'container [
		margin:  0x0
		spacing: 0x0
		axes:    [e s]
		align:   -1x-1
		width:   none			;@@ this seems required, but maybe a mandatory cell can replace it? or limits?
		; cache?:  off
		
		container-draw: :draw
		;; canvas for tube cannot be none as it controls tube's width
		;@@ or we need an explicit width
		draw: function [/only xy1 [pair! none!] xy2 [pair! none!] /on canvas [pair! none!]] [
			if width [canvas: width * 1x1]				;-- override canvas if width is set (only 1 dimension matters)
			settings: [margin spacing align axes canvas]
			container-draw/layout/only 'tube settings xy1 xy2
		]

		container-on-change: :on-change*
		#on-change-redirect
	]
]


switch-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		all [
			word = 'state
			:old <> :new
			invalidate-cache space
		]
	]
	
	templates/switch: make-template 'space [
		state: off
		data: make-space 'data-view []
		draw: does [also data/draw size: data/size]
		#on-change-redirect
	]
	
	templates/logic: make-template 'switch []			;-- uses different style
]


label-ctx: context [
	~: self
	
	on-change: function [label [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			image [
				spaces: label/spaces
				spaces/image-box/content: bind case [	;-- invalidated by cell
					image? label/image [
						spaces/image/data: label/image
						'image
					]
					string? label/image [
						spaces/sigil/text: label/image
						'sigil
					]
					char? label/image [
						spaces/sigil/text: form label/image
						'sigil
					]
					'else [in generic 'empty]
				] spaces
			]
			text [
				spaces: label/spaces
				type: either newline: find label/text #"^/" [
					spaces/text/text: copy/part label/text newline
					spaces/comment/text: copy next newline
					'comment
				][
					spaces/text/text: label/text
					'text
				]
				spaces/body/item-list: spaces/lists/:type	;-- invalidated by container
			]
		]
		label/list-on-change word :old :new				;-- handles axis margin spacing
	]
	
	templates/label: make-template 'list [
		axis:    'x
		margin:  0x0
		spacing: 5x0
		image:   none									;-- can be a string! as well
		text:    ""
		
		spaces: object [								;-- all lower level spaces used by label
			image:      make-space 'image []
			sigil:      make-space 'text [limits: 20 .. none]	;-- 20 is for alignment of labels under each other ;@@ should be set in style?
			image-box:  make-space 'box  [content: in generic 'empty]	;-- needed for centering the image/sigil
			text:       make-space 'text []						;-- 1st line of text
			comment:    make-space 'text []						;-- lines after the 1st
			body:       make-space 'list [margin: 0x0 spacing: 0x0 axis: 'y  item-list: [text comment]]
			text-box:   make-space 'box  [content: 'body]		;-- needed for text centering
			lists: [text: [text] comment: [text comment]]		;-- used to avoid extra bind in on-change
			set 'item-list [image-box text-box]
		]
		
		list-on-change: :on-change*
		#on-change-redirect
	]
]



;; a polymorphic style: given `data` creates a visual representation of it
;; `content` can be used directly to put a space into it (useful in clickable, button)
;@@ TODO: complex types should leverage table style
data-view-ctx: context [
	~: self

	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			spacing [invalidate-cache space]
			font [
				cspace: get space/content
				if all [in cspace 'font  not cspace/font =? space/font] [
					cspace/font: space/font
					invalidate-cache space
				]
			]
			data [
				space/content: either block? :new [
					anonymize 'tube lay-out-data new	;@@ use `row`?
				][
					wrap-value :new
				] 
			]
		]
		space/box-on-change word :old :new
	]
			
	templates/data-view: make-template 'box [			;-- inherit margin, content, map from the box
		align:   -1x-1									;-- left-top aligned by default
		data:    none									;-- ANY red value
		spacing: 5x5									;-- used only when data is a block
		;; font can be set in style, unfortunately required here to override font of rich-text face
		;; (because font for rich-text layout cannot be set with a draw command - we need to measure size)
		font:    none									
		
		box-on-change: :on-change*
		#on-change-redirect
	]
]


window-ctx: context [
	~: self

	;; `available?` should be defined in content
	;; should return how much more the window can be scrolled in specified direction (from it's edge, not current origin!)
	;; if it returns more than requested, window is expanded by returned value
	;; (e.g. user scrolls a chat up, whole message height is added to it, not just 20 pixels of the message)
	available?: function [
		content   [word!]
		axis      [word!]   
		dir       [integer!]
		from      [integer!]
		requested [integer!]
	][
		cspace: get content
		either function? cavail?: select cspace 'available? [	;-- use content/available? when defined
			cavail? axis dir from requested
		][														;-- otherwise deduce from content/size
			csize: any [cspace/size 0x0]						;@@ or assume infinity if no /size in content?
			clip [0 requested] either dir < 0 [from][csize/:axis - from]
		]
	]

	draw: function [window [object!] xy1 [pair! none!] xy2 [pair! none!]] [
		#debug grid-view [#print "window/draw is called with xy1=(xy1) xy2=(xy2)"]
		#assert [word? window/content]
		window/map/1: window/content					;-- rename it properly
		geom: window/map/2
		cspace: get window/content
		o:  geom/offset
		;; there's no size for infinite spaces so we use `available?` to get the drawing size
		s:  window/max-size
		o': window/cached-offset						;-- geom/offset during previous draw
		if o <> o' [									;-- don't resize window unless it was moved
			foreach x [x y] [s/:x: window/available? x 1 (0 - o/:x) s/:x]
			window/size: s								;-- limit window size by content size (so we don't scroll over)
			#debug list-view [#print "window resized to (s)"]
			set-quiet in window 'cached-offset o
		]
		default xy1: 0x0
		default xy2: s
		geom/size: xy2 - o								;-- enough to cover the visible area
		cdraw: render/only/on window/content xy1 - o xy2 - o xy2 - xy1
		compose/only [translate (o) (cdraw)]
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			limits content [invalidate-cache space]
		]
	]
		
	templates/window: make-template 'space [
		;; when drawn auto adjusts it's `size` up to `max-size` (otherwise scrollbars will always be visible)
		;; but `max-size` itself is set by `inf-scrollable`, to a multiple of it's own size!
		max-size: 1000x1000
		; cache?: off

		;; window does not require content's size, so content can be an infinite space!
		content: make-space/name 'space []
		map: [space [offset 0x0 size 0x0]]				;-- 'space' will be replaced by space content refers to
		map/1: content

		available?: func [
			"Should return number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
			axis      [word!]    "x/y"
			dir       [integer!] "-1/1"
			from      [integer!] "axis coordinate to look ahead from"
			requested [integer!] "max look-ahead required"
		][
			~/available? content axis dir from requested
		]
	
		cached-offset: none
		draw: func [/only xy1 [pair!] xy2 [pair!]] [
			~/draw self xy1 xy2
		]
		
		#on-change-redirect
	]
]

inf-scrollable-ctx: context [
	~: self
	
	roll: function [space [object!]] [
		#debug grid-view [#print "origin in inf-scrollable/roll: (space/origin)"]
		window: space/window
		wo: wo0: 0x0 - window/map/(window/content)/offset	;-- (positive) offset of window within it's content
		#assert [window/size]
		ws:     window/size
		before: 0x0 - space/origin
		after:  ws - (before + space/map/window/size)
		foreach x [x y] [
			any [		;-- prioritizes left/up jump over right/down
				all [
					before/:x <= space/look-around
					0 < avail: window/available? x -1 wo/:x space/jump-length
					wo/:x: wo/:x - avail
				]
				all [
					after/:x  <= space/look-around
					0 < avail: window/available? x  1 wo/:x + ws/:x space/jump-length
					wo/:x: wo/:x + avail
				]
			]
		]
		maybe space/origin: space/origin + (wo - wo0)	;-- transfer offset from scrollable into window, in a way detectable by on-change
		maybe window/map/(window/content)/offset: 0x0 - wo
		if wo <> wo0 [invalidate-cache window]
		wo <> wo0								;-- should return true when updates origin - used by event handlers
	]
		
	templates/inf-scrollable: make-template 'scrollable [	;-- `infinite-scrollable` is too long for a name
		jump-length: 200						;-- how much more to show when rolling (px) ;@@ maybe make it a pair?
		look-around: 50							;-- zone after head and before tail that triggers roll-edge (px)
		pages: 10x10							;-- window size multiplier in sizes of inf-scrollable
		; cache?: off

		window: make-space 'window [size: none]			;-- size is set by window/draw
		content: 'window
		#assert [map/1 = 'window]						;-- set by on-change

		roll-timer: make-space 'timer [rate: 4]			;-- how often to call `roll` when dragging
		append map [roll-timer [offset 0x0 size 0x0]]

		roll: does [~/roll self]

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


list-view-ctx: context [
	~: self

	;-- locate-line returns any of:
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
	
	;; helpers for locate-line
	level-sub: function [level [integer!] name [path!] idx [integer!]] [
		if level < size: get name [throw reduce [name/1 idx level]]		;-- will intersect zero, throw >=0
		level - size
	]
	level-add: function [level [integer!] name [path!] idx [integer!]] [
		also level: level + get name
		if level >= 0 [throw reduce [name/1 idx level]]			;-- intersected zero, throw >=0
	]
	
	;; see grid-view for more details on returned format
	locate-line: function [
		"Turn a coordinate along main axis into item index and area type (item/space/margin)"
		list   [object!]  "List object with items"
		canvas [pair!]    "Canvas on which it is rendered"
		level  [integer!] "Offset in pixels from the 0 of main axis"
	][
		x: list/axis
		if level < list/margin/:x [return compose [margin 1 (level)]]
		#debug list-view [level0: level]				;-- for later output
		;; make canvas infinite otherwise single item will occupy it's size
		canvas/:x: 2'000'000'000
		
		either empty? list/map [
			i: 1
			level: level - list/margin/:x
		][
			#assert [not empty? list/icache]
			#assert ['item = list/map/1]
			item-spaces: reduce values-of list/icache
			i: pick keys-of list/icache j: index? find/same item-spaces get list/map/1
			level: level - list/map/2/offset/:x
		]
		imax: list/items/size
		space: list/spacing								;-- return value is named "space"
		fetch-ith-item: [								;-- sets `item` to size
			obj: get name: list/items/pick i
			unless item: obj/size [
				;; presence of call to `render` here is a tough call
				;; existing previous size is always preferred here, esp. useful for non-cached items
				;; but `locate-line` is used by `available?` which is in turn called:
				;; - when determining initial window extent (from content size)
				;; - every time window gets scrolled closer to it's borders
				;; so there's no easy way around requiring render here, and around having a canvas here
				;; for the purpose of this function, last rendered canvas works, as well as window size
				render/on name canvas
				item: obj/size
			]
		]
		;@@ should this func use layout or it will only complicate things?
		;@@ right now it independently of list-layout computes all offsets
		r: catch [
			either level >= 0 [
				imax: any [imax 1.#inf]					;-- if undefined
				forever [
					do fetch-ith-item
					level: level-sub level 'item/:x i
					if i >= imax [throw compose [margin 2 (level)]]
					level: level-sub level 'space/:x i
					i: i + 1
				]
			][
				forever [
					i: i - 1
					#assert [0 < i]
					level: level-add level 'space/:x i
					do fetch-ith-item
					level: level-add level 'item/:x i
				]
			]
		]
		#debug list-view [#print "locate-line (level0) -> (mold r)"]
		#assert [0 < r/2]
		r
	]

	locate-range: function [
		"Turn a range along main axis into list item indexes and offsets from their 0x0"
		list       [object!]  "List object with items"
		canvas     [pair!]    "Canvas on which it is rendered"
		low-level  [integer!] "Top/left line on main axis"
		high-level [integer!] "Bottom/right line on main axis"
	][
		set [l-item: l-idx: l-ofs:] locate-line list canvas  low-level
		set [h-item: h-idx: h-ofs:] locate-line list canvas high-level
		sp: list/spacing/(list/axis)
		mg: list/margin/( list/axis)
		;; intent of this is to return item indexes that fully cover the requested range
		;; so, space and margin before first item is still considered belonging to that item
		;; (as it doesn't require rendering of the previous item)
		;; returned index can be none if low-level lands after the last item's geometry
		switch l-item [
			space  [l-idx: l-idx + 1  l-ofs: l-ofs - sp]
			margin [
				l-ofs: l-ofs - mg
				if l-idx = 2 [l-idx: none]
			]
		]
		;; for the same reason, space/margin after last item belongs to that item
		;; returned index can be none if high-level lands before the last item's geometry
		switch h-item [
			space [h-ofs: h-ofs + list/item-length? h-idx]
			margin [
				either h-idx = 1 [
					h-idx: none
				][
					h-idx: list/items/size				;-- can't be none since right margin is present
					either h-idx <= 0 [					;-- data/size can be 0, then there's no item to draw
						h-idx: none
					][
						h-ofs: h-ofs + list/item-length? h-idx
					]
				]
			]
		]
		r: reduce [l-idx l-ofs h-idx h-ofs]
		#debug list-view [#print "locate-range (low-level),(high-level) -> (mold r)"]
		r
	]

	templates/list-view: make-template 'inf-scrollable [
		; reversed?: no		;@@ TODO - for chat log, map auto reverse
		; cache?: off
		
		pages:  10
		source: []
		data: function [/pick i [integer!] /size] [		;-- can be overridden
			either pick [source/:i][length? source]		;-- /size may return `none` for infinite data
		]
		
		wrap-data: function [item-data [any-type!]][
			spc: make-space 'data-view []
			set/any 'spc/data :item-data
			anonymize 'item spc
		]

		list: make-space 'list [
			axis: 'y
			; cache?: off
			
			;; cache of last rendered item spaces (as words)
			;; this persistency is required by the focus model: items must retain sameness
			;; an int->word map! - for flexibility in caching strategies (which items to free and when)
			;@@ when to forget these? and why not keep only focused item?
			icache: make map! []	

			items: function [/pick i [integer!] /size] [
				either pick [
					any [
						icache/:i
						icache/:i: wrap-data data/pick i
					]
				][data/size]
			]

			;@@ maybe all this should be part of `list` space itself?
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
			
			;; window/max-size serves as list's canvas
			;@@ it should be reset if list-view is resized!
			locate-line: func [level [integer!]] [
				~/locate-line self window/max-size level
			]
			locate-range: func [low-level [integer!] high-level [integer!]] [
				~/locate-range self window/max-size low-level high-level
			]

			item-length?: function [i [integer!]] [
				#assert [0 < i]
				#assert [icache/:i]
				item: get icache/:i							;-- must be cached by previous locate-line call
				r: item/size/:axis
				#debug list-view [#print "item-length? (i) -> (r)"]
				r
			]

			;; container/draw only supports finite number of `items`, infinite needs special handling
			;; it's also too general, while this `draw` can be optimized better
			draw: function [/only xy1 [pair!] xy2 [pair!]] [
				#assert [all [xy1 xy2]]
				clear map
				set [i1: o1: i2: o2:] locate-range xy1/:axis xy2/:axis
				unless all [i1 i2] [return []]				;-- no visible items (see locate-range)
				#assert [i1 <= i2]

				guide: select [x 1x0 y 0x1] axis
				;; make canvas infinite, else single item will occupy it's size
				canvas: window/max-size
				canvas/:axis: 2'000'000'000
				viewport: xy2 - xy1
				origin: guide * (xy1 - o1 - margin)
				cache: 'all
				settings: [axis margin spacing canvas viewport origin cache]
				picker: func [/size /pick i] [
					either size [i2 - i1 + 1][items/pick i + i1 - 1]
				]
				set [new-size: new-map:] make-layout 'list :picker settings
				append clear map new-map
				maybe self/size: new-size				;@@ do we even care about the size of the list itself here?
														;@@ should size/x be that of list-view/size/x ?
				;@@ make compose-map generate rendered output? or another wrapper
				;@@ will have to provide canvas directly to it, or use it from geom/size
				drawn: make [] 3 * (length? map) / 2
				foreach [name geom] map [
					compose/deep/into [
						translate (geom/offset) [
							; clip 0x0 (geom/size) (render/on name geom/size)
							(render/on name geom/size)
						]
					] tail drawn
				]
				drawn
			]
		]
		
		window/content: 'list

		;; this initializes window size to a multiple of list-view sizes (paragraphs adjust to window then)
		;; overrides inf-scrollable's own autosize-window because `list-view` has a linear `pages` interpretation
		autosize-window: function [] [
			unit: axis2pair list/axis
			;; account for scrollers size, since list-view is meant to always display one along main axis
			;; this will make window and it's content adapt to list-view width when possible
			;@@ it's a bit dumb to _always_ subtract scrollers even if they're not visible
			;@@ need more dynamic way of adapting window size
			scrollers: hscroll/size * 0x1 + (vscroll/size * 1x0) * reverse unit
			#assert [0x0 <> size]
			maybe window/max-size: pages - 1 * unit + 1 * size - scrollers
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
				axis size pages [
					if :old <> :new [
						#assert [any [word <> 'axis  find [x y] :new]]
						clear list/map
						autosize-window
						invalidate-cache self
					]
				]
			]
			inf-scrollable-on-change word :old :new
		]
	]
]


;@@ TODO: list-view of SPACES?  simple layout-ers?  like grid..?

;; grid's key differences from list of lists:
;; * it aligns columns due to fixed column size
;; * it CAN make cells spanning multiple rows (impossible in list of lists)
;; * it uses fixed row heights, and because of that it CAN have infinite width (but requires separate height inferrence)
;;   (by "infinite" I mean "big enough that it's unreasonable to scan it to infer the size (or UI becomes sluggish)")
;; * grid is better for big empty cells that user is supposed to fill,
;;   while list is better for known autosized content
;@@ TODO: height & width inferrence
;@@ think on styling: spaces grid should not have visible delimiters, while data grid should
grid-ctx: context [
	templates/grid: make-template 'space [
		size:    none				;-- only available after `draw` because it applies styles
		margin:  5x5
		spacing: 5x5
		cell-map: make map! []				;-- XY coordinate -> space-name  ;@@ TODO: maybe rename to `pane`?
											;@@ or `cmap` for brevity?
		spans:   make map! []				;-- XY coordinate -> it's XY span (not user-modifiable!!)
											;@@ make spans a picker too?? or pointless for infinite data anyway
		widths:  make map! [default 100]	;-- number of column/row -> it's width/height
		heights: make map! [default 100]	;-- height can be 'auto (row is auto sized)
		origin:  0x0						;-- offset of non-pinned cells from 0x0 (negative = to the left and above) (alternatively: offset of pinned cells over non-pinned, but negated)
		pinned:  0x0						;-- how many rows & columns should stay pinned (as headers), no effect if origin = 0x0
		bounds:  [x: auto y: auto]			;-- max number of rows & cols, auto=bound `cells`, integer=fixed
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
			unless cell/content =? space [cell/content: space]	;-- prevent unnecessary invalidation
			name
		]

		cells: func [/pick xy [pair!] /size] [				;-- up to user to override
			either pick [cell-map/:xy][calc-bounds]
		]

		calc-bounds: function [] [
			bounds: self/bounds								;-- call it in case it's a function
			unless any ['auto = bounds/x  'auto = bounds/y] [	;-- no auto limit set (but can be none)
				#debug grid-view [#print "grid/calc-bounds [no auto] -> (bounds)"]
				return bounds
			]
			lim: copy bounds
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
			#debug grid-view [#print "grid/calc-bounds [auto] -> (lim)"]
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
			if span +< 1x1 [xy: xy + span]
			xy
		]

		break-cell: function [first [pair!]] [
			if 1x1 <> span: get-span first [
				#assert [1x1 +<= span]					;-- ensure it's a first cell of multicell
				xyloop xy span [
					remove/key spans xy': first + xy - 1x1
					;@@ invalidate content within ccache?
				]
			]
		]

		unify-cells: function [first [pair!] span [pair!]] [
			if 1x1 <> old: get-span first [
				if old +< 1x1 [
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
			#assert [1x1 +<= span]						;-- forbid setting to span to non-positives
			xyloop xy span [							;-- break all multicells within the area
				cell: first + xy - 1
				old-span: get-span cell
				if old-span <> 1x1 [
					all [
						not force
						any [cell <> first  1x1 +<= old-span]	;-- only `first` is broken silently if it's a multicell
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
			lim: draw-ctx/bounds/:axis
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
							idx: draw-ctx/bounds/:x
							ofs: ofs + wh? idx
							#assert [idx]			;-- 2nd margin is only possible if bounds are known
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
			bounds: any [draw-ctx/bounds draw-ctx/bounds: cells/size]	;-- may be none if called from calc-bounds before grid/draw
			; #assert [draw-ctx/bounds]
			xlim: bounds/x
			#assert [integer? xlim]						;-- row size cannot be calculated for infinite grid
			hmin: append clear [] min-row-height
			for x: 1 xlim [
				span: get-span xy: as-pair x y
				if span/x < 0 [continue]				;-- skip cells of negative x span (counted at span = 0 or more)
				first: get-first-cell xy
				height1: 0
				if content: cells/pick first [
					render wrap-space first content		;-- render to get the size
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
			not pinned +< xy
		]

		infinite?: function [] [
			bounds: self/bounds							;-- call it in case it's a function
			not all [bounds/x bounds/y]
		]

		calc-size: function [] [
			#debug grid-view [#print "grid/calc-size is called!"]
			#assert [not infinite?]
			bounds: any [draw-ctx/bounds draw-ctx/bounds: cells/size]	;@@ optimize this? cache bounds?
			bounds: as-pair bounds/x bounds/y
			r: margin * 2 + (spacing * max 0x0 bounds - 1)
			repeat x bounds/x [r/x: r/x + col-width?  x]
			repeat y bounds/y [r/y: r/y + row-height? y]
			#debug grid-view [#print "grid/calc-size -> (r)"]
			r
		]

		;-- due to the number of parameters this space has,
		;-- a special context is required to minimize the number of wasted calculations
		;-- however a care should be taken so that grid can contain itself (draw has to be reentrant)
		draw-ctx: context [
			ccache: make map! []		;-- cached `cell` spaces (persistency required by the focus model: cells must retain sameness)
			bounds: none
			size:   none
			cleanup: function [] [
				self/size: self/bounds: none
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
				
				render mcname: wrap-space mcell mcell-name	;-- render content to get it's size - in case it was invalidated
				mcspace: get mcname
				mcsize: cell-size? mcell					;-- size of all rows/cols it spans = canvas size
				mcdraw: render/on mcname mcsize				;-- re-render to draw the full background
				;@@ TODO: if grid contains itself, map should only contain each cell once - how?
				compose/deep/into [							;-- map may contain the same space if it's both pinned & normal
					(mcname) [offset (draw-ofs) size (mcsize)]
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
			#assert [any [not infinite?  all [xy1 xy2]]]	;-- bounds must be defined for an infinite grid

			dc: draw-ctx
			;@@ TODO: only clear dc & map for the outermost draw (in case grid contains itself)
			dc/cleanup
			; clear map
			new-map: make [] 100

			dc/bounds: cells/size
			#assert [dc/bounds]
			;-- locate-point calls row-height which may render cells when needed to determine the height
			default xy1: 0x0
			unless xy2 [dc/size: xy2: calc-size]

			unless pinned +<= 0x0 [
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
	templates/grid-view: make-template 'inf-scrollable [
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
			;@@ should `available?` be in *every* grid? (as a placeholder word)
			available?: function [axis dir from [integer!] requested [integer!]] [	
				;; gets called before grid/draw by window/draw to estimate the max window size and thus config scrollbars accordingly
				#debug grid-view [print ["grid/available? is called at" axis dir from requested]]	
				bounds: self/bounds
				#assert [bounds "data/size is none!"]
				r: case [
					dir < 0 [from]
					bounds/:axis [
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
		grid/calc-bounds: grid/bounds: does [data/size]
		
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
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if all [word = 'pushed?  :old <> :new] [
			invalidate-cache space
			;; prevents command from being evaluated multiple times on key press & hold:
			if :old [do space/command]
		]
		space/data-view-on-change word :old :new
	]
	
	templates/clickable: make-template 'data-view [
		;@@ should pushed be in button rather?
		align:    0x0									;-- center by default
		pushed?:  no									;-- becomes true when user pushes it; triggers `command`
		command:  []									;-- code to run on click (on up: when `pushed?` becomes false)
		;@@ should command be also a function (actor)? if so, where to take event info from?

		data-view-on-change: :on-change*
		#on-change-redirect
	]
	
	templates/button: make-template 'clickable [		;-- styled with decor
		margin: 4x4
		rounding: 5										;-- box rounding radius in px
	]
]


;@@ this should not be generally available, as it's for the tests only - remove it!
templates/rotor: make-template 'space [
	content: none
	angle: 0

	ring: make-space 'space [size: 360x10]
	;@@ TODO: zoom for round spaces like spiral

	map: [							;-- unused, required only to tell space iterators there's inner faces
		ring [offset 0x0 size 999x999]					;-- 1st = placeholder for `content` (see `draw`)
	]
	
	on-change*: function [word [any-word!] old [any-type!] new [any-type!]] [
		if find [angle content] word [
			invalidate-cache self
		]
	]

	into: function [xy [pair!] /force name [word! none!]] [
		unless content [return none]
		spc: get content
		r1: to 1 spc/size/x ** 2 + (spc/size/y ** 2) / 4 ** 0.5
		r2: r1 + 10
		c: cosine angle  s: negate sine angle
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
				rotate (angle)
				(collect [
					repeat i 5 [
						keep compose [arc 0x0 (r1 + 5 * 1x1) (a: i * 72 - 24 - 90) 48]
					]
				])
				; circle (size / 2) (r1 + 5)
			]
			translate (size - spc/size / 2) [
				rotate (angle) (spc/size / 2)
				(drawn)
			]
		]
	]
]


;@@ TODO: can I make `frame` some kind of embedded space into where applicable? or a container? so I can change frames globally in one go
;@@ if embedded, map composition should be a reverse of hittest: if something is drawn first then it's at the bottom of z-order
field-ctx: context [
	~: self
	
	draw: function [field [object!]] [
		maybe field/paragraph/width: if field/wrap? [field/size/x]
		maybe field/paragraph/text:  field/text
		; pdrawn: paragraph/draw								;-- no `render` to not start a new style
		pdrawn: render/on in field 'paragraph field/size
		xy1: caret-to-offset       field/paragraph/layout field/caret-index + 1
		xy2: caret-to-offset/lower field/paragraph/layout field/caret-index + 1
		field/caret/size: as-pair field/caret-width xy2/y - xy1/y
		cdrawn: []
		if field/active? [
			cdrawn: compose/only [translate (xy1) (render in field 'caret)]
		]
		compose [(cdrawn) clip 0x0 (field/size) (pdrawn)]		;@@ use margin? otherwise there's no space for inner frame
	]
		
	;@@ TODO: only area should be scrollable
	templates/field: make-template 'scrollable [
		text: ""
		selected: none		;@@ TODO
		caret-index: 0		;-- should be kept even when not focused, so tabbing in leaves us where we were
		caret-width: 1		;-- in px
		size: 100x25		;@@ good enough idea or not?
		paragraph: make-space 'paragraph []
		caret: make-space 'rectangle []		;-- caret has to be a separate space so it can be styled
		content: 'paragraph
		wrap?: no
		active?: no			;-- whether it should react to keyboard input or pass thru (set on click, Enter)
		;@@ TODO: render caret only when focused
		;@@ TODO: auto scrolling when caret is outside the viewport
		invalidate: does [				;@@ TODO: use on-deep-change to watch `text`??
			paragraph/layout: none
			invalidate-cache paragraph
		]
	
		draw: does [~/draw self]
	]
]

templates/fps-meter: make-template 'text [
	cache?:    off
	rate:      100
	text:      "FPS: 100.0"								;-- longest text used for initial sizing of it's host
	init-time: now/precise/utc
	frames:    make [] 400
	aggregate: 0:0:3
]

export exports