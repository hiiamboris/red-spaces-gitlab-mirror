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
	/window xy1 [pair!] xy2 [pair!] "Specify viewport"	;@@ it's unused; remove it?
][
	r: make [] round/ceiling/to (1.5 * length? map) 1	;-- 3 draw tokens per 2 map items
	foreach [name box] map [
		all [list  not find list name  continue]		;-- skip names not in the list if it's provided
		; all [limits  not boxes-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
		if zero? area? box/size [continue]				;-- don't render empty elements (also works around #4859)
		cmds: either window [
			render/window name xy1 xy2
		][	render        name
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
;@@ map is used to work around #5137 when compiling with -e!
generic: construct to [] make map! reduce [				;-- holds commonly used spaces ;@@ experimental
	'empty make-space 'space []							;-- used when no content is given
	'<-> none 'stretch none								;-- set after box definition
]

;; empty stretching space used for alignment (static version and template)
templates/stretch: put templates '<-> make-template 'space [	;@@ affected by #5137
	weight: 1
	draw: function [/on canvas [pair! none!]] [
		set [canvas: fill:] decode-canvas canvas
		self/size: constrain (finite-canvas canvas) * max 0x0 fill limits
		[]
	]
]
generic/stretch: set in generic '<-> make-space 'stretch []

rectangle-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		all [
			find [size margin] word
			not :old =? :new
			invalidate-cache space
		]
		space/space-on-change word :old :new
	]
	
	templates/rectangle: make-template 'space [
		size:   20x10
		margin: 0
		draw:   does [compose [box (margin * 1x1) (size - margin)]]
		space-on-change: :on-change*
		#on-change-redirect
	]
]

;@@ maybe this should be called `arrow`? because it doesn't have to be triangle-styled
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
		
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		unless :old =? :new [invalidate-cache space]
		space/space-on-change word :old :new
	]
		
	templates/triangle: make-template 'space [
		size:    16x10
		dir:     'n
		margin:  0
		
		;@@ need `into` here? or triangle will be a box from the clicking perspective?
		draw: does [~/draw self]
		space-on-change: :on-change*
		#on-change-redirect
	]
]

image-ctx: context [
	~: self
	
	draw: function [image [object!] canvas [pair! none!]] [
		either image? image/data [
			default canvas: infxinf
			set [canvas: _:] decode-canvas canvas		;-- image does not respect fill flag; scale is more important
			mrg:       image/margin * 1x1 
			limits:    image/limits
			isize:     image/data/size
			;; `constrain` isn't applicable here because doesn't preserve the ratio, and because of canvas handling
			low-lim:   1x1 * any [if limits [limits/min] 0x0]	;-- default to 0x0 as min size; * 1x1 in case it's integer
			;; infinite canvas is fine here - it just won't affect the scale
			high-lim:  1x1 * min-safe canvas if limits [limits/max]	;@@ REP #113 & 122 ;-- if no canvas, will be unscaled
			;; for uniform scaling, compute min/max scale applicable
			lim:       max 1x1 low-lim - mrg - mrg
			min-scale: max  lim/x / isize/x  lim/y / isize/y
			if high-lim [
				lim: max 1x1 high-lim - mrg - mrg
				max-scale: min  lim/x / isize/x  lim/y / isize/y
			]
			;; then choose
			scale: case [
				min-scale > 1 [min-scale]						;-- upscale if limits/min requires only
				all [max-scale max-scale < 1] [max-scale]		;-- downscale if canvas or limits/max requires
				'unconstrained [1]
			]
			maybe image/size: isize * scale + (2 * mrg)
			reduce ['image image/data mrg image/size - mrg]
		][
			maybe image/size: 2x2 * image/margin				;@@ can't be constrained further; or call constrain again?
			[]
		]
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if switch to word! word [
			margin [:old <> :new]
			data   [true] 								;-- can't know if image bits were changed, better to update
		] [invalidate-cache space]
		space/space-on-change word :old :new
	]
	
	templates/image: make-template 'space [
		size:   none									;@@ should fixed size be used as an override?
		margin: 0
		data:   none									;-- images are not recyclable, so `none` by default
		draw: func [/on canvas [pair! none!]] [~/draw self canvas]
		space-on-change: :on-change*
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
	
	draw: function [space [object!] canvas [pair! none!]] [
		#assert [space/content]
		#debug sizing [print ["cell/draw with" space/content "on" canvas]]
		default canvas: infxinf
		set [canvas: fill:] decode-canvas canvas
		canvas: constrain canvas space/limits
		mrg2:   2x2 * space/margin
		drawn:  render/on space/content encode-canvas (subtract-canvas canvas mrg2) fill
		cspace: get space/content
		size:   mrg2 + cspace/size
		;; canvas can be infinite or half-infinite: inf dimensions should be replaced by space/size (i.e. minimize it)
		size:   max size (finite-canvas canvas) * fill	;-- only extends along fill-enabled axes
		maybe space/size: constrain size space/limits
		; #print "size: (size) space/size: (space/size) fill: (fill)"
		
		free:   space/size - cspace/size - mrg2
		offset: space/margin + max 0x0 free * (space/align + 1) / 2
		unless tail? drawn [
			; drawn: compose/only [translate (offset) (drawn)]
			drawn: compose/deep/only [clip 0x0 (space/size) [translate (offset) (drawn)]]
		]
		space/map: compose/deep [(space/content) [offset: (offset) size: (space/size)]]
		#debug sizing [print ["box with" space/content "on" canvas "->" space/size]]
		drawn
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
		space/space-on-change word :old :new
	]
	
	templates/box: make-template 'space [
		align:   0x0									;@@ consider more high level VID-like specification of alignment
		margin:  0x0									;-- useful for drawing inner frame, which otherwise would be hidden by content
		weight:  1										;@@ what default weight to use? what default alignment?
		content: in generic 'empty						;@@ consider `content: none` optimization if it's worth it
		map:     reduce [content [offset 0x0 size 0x0]]
		;; cannot be cached, as content may change at any time and we have no way of knowing
		; cache?:  off
		
		;; draw/only can't be supported, because we'll need to translate xy1-xy2 into content space
		;; but to do that we'll have to render content fully first to get it's size and align it
		;; which defies the meaning of /only...
		;; the only way to use /only is to apply it on top of current offset, but this may be harmful
		draw: function [/on canvas [pair! none!]] [~/draw self canvas]
		
		space-on-change: :on-change*
		#on-change-redirect
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
	
	arrange: function [content [block!]] [				;-- like list layout but simpler/faster
		map: make block! 2 * length? content
		pos: 0x0
		foreach name content [	;@@ should be map-each
			size: select get name 'size
			append map compose/deep [
				(name) [offset: (pos) size: (size)]
			]
			pos: size * 1x0 + pos
		]
		map
	]
	
	draw: function [space [object!]] [
		size2: either space/axis = 'x [space/size][reverse space/size]
		h: size2/y  w-full: size2/x
		w-arrow: to integer! size2/y * space/arrow-size
		w-inner: w-full - (2 * w-arrow)
		;-- in case size is too tight to fit the scrollbar - compress inner first, arrows next
		if w-inner < 0 [w-arrow: to integer! w-full / 2  w-inner: 0]
		w-thumb: to integer! case [						;-- 3 strategies for the thumb
			w-inner >= (2 * h) [max h w-inner * space/amount]	;-- make it big enough to aim at
			w-inner >= 8       [      w-inner * space/amount]	;-- better to have tiny thumb than none at all
			'else              [0]								;-- hide thumb, leave just the arrows
		]
		w-pgup: to integer! w-inner - w-thumb + (w-inner * space/amount) * space/offset
		w-pgdn: w-inner - w-pgup - w-thumb
		quietly space/back-arrow/size:  w-arrow by h
		quietly space/back-page/size:   w-pgup  by h
		quietly space/thumb/size:       w-thumb by h
		quietly space/forth-page/size:  w-inner - w-thumb - w-pgup by h	;-- compensates for previous rounding errors
		quietly space/forth-arrow/size: w-arrow by h
		space/map: arrange with space list: [back-arrow back-page thumb forth-page forth-arrow]
		
		foreach name list [invalidate-cache/only get name]
		compose/deep [
			push [
				matrix [(select [x [1 0 0 1] y [0 1 1 0]] space/axis) 0 0]
				(compose-map space/map)
			]
		]
	]
	
	on-change: function [bar [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [offset amount size axis arrow-size [invalidate-cache bar]]
		bar/space-on-change word :old :new
	]
				
	templates/scrollbar: make-template 'space [
		;@@ maybe leverage canvas size?
		size:       100x16								;-- opposite axis defines thickness
		axis:       'x
		offset:     0%
		amount:     100%
		arrow-size: 90%									;-- arrow length in percents of scroller's thickness 
		map:        []
		back-arrow:  make-space 'triangle  [margin: 2  dir: 'w] ;-- go back a step
		back-page:   make-space 'rectangle [draw: []]           ;-- go back a page
		thumb:       make-space 'rectangle [margin: 2x1]        ;-- draggable
		forth-page:  make-space 'rectangle [draw: []]           ;-- go forth a page
		forth-arrow: make-space 'triangle  [margin: 2  dir: 'e] ;-- go forth a step
		into: func [xy [pair!] /force name [word! none!]] [~/into self xy name]
		;@@ TODO: styling/external renderer
		draw: does [~/draw self]
		space-on-change: :on-change*
		#on-change-redirect
	]
]

;@@ rename this to just `scrollable`? definitely need standardization in these context names
;; it's not `-ctx` because move-by and move-to functions are meant of outside use
scrollable-space: context [
	~: self

	;@@ or /line /page /forth /back /x /y ?
	;@@ TODO: less awkward spec
	move-by: function [
		spc
		amnt "'line or 'page or offset in px"
		dir "forth or back"
		axis "x or y"
		/scale factor "1 by default"
	][
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
		spc [object!]
		xy [pair! word!] "offset or: head, tail"
		/margin "how much space to reserve around XY"
			mrg [integer! pair!] "default: 0"
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
		set [canvas: fill:] decode-canvas canvas
		;; stretch to finite dimensions of the canvas, but minimize across the infinite
		maybe space/size: box: constrain finite-canvas canvas space/limits
		if zero? area? box [
			;@@ this complains if I override default 50x50 limit with e.g. `100` (no vertical limit)
			;@@ I need to make it work on zero canvas too
			#assert [false "Somehow scrollable has no size!"]
			return quietly space/map: []
		]
		origin: space/origin
		cspace: get space/content
		#debug grid-view [
			#print "scrollable/draw: renders content from (max 0x0 0x0 - origin) to (box - origin); box=(box)"
		]
		;; render it before 'size' can be obtained, also render itself may change origin (in `roll`)!
		;; fill flag passed through as is: may be useful for 1D scrollables like list-view ?
		cdraw: render/on space/content encode-canvas box fill
		if all [
			axis: switch space/content-flow [vertical ['y] horizontal ['x]]
			cspace/size/:axis > box/:axis
		][												;-- have to add the scroller and subtract it from canvas width
			scrollers: space/vscroll/size/x by space/hscroll/size/y
			ccanvas: max 0x0 box - (scrollers * axis2pair ortho axis)		;-- valid since box is finite
			cdraw: render/on space/content encode-canvas ccanvas fill
		]
		csz: cspace/size		
		; #assert [0x0 +< (origin + csz)  "scrollable/origin made content invisible!"]
		;; ensure that origin doesn't go beyond content/size (happens when content changes e.g. on resizing)
		;@@ origin clipping in tube makes it impossible to scroll to the bottom because of window resizes!
		;@@ I need a better idea, how to apply it without breaking things, until then - not clipped
		; maybe space/origin: clip [origin 0x0] box - scrollers - csz
		; maybe space/origin: origin
		; print [space/content csz space/origin]
		
		;; determine what scrollers to show
		p2: csz + p1: origin
		clip-p1: max 0x0 p1
		loop 2 [										;-- each scrollbar affects another's visibility
			clip-p2: min box p2
			shown: min 100x100 (clip-p2 - clip-p1) * 100 / max 1x1 csz
			if hdraw?: shown/x < 100 [box/y: space/size/y - space/hscroll/size/y]
			if vdraw?: shown/y < 100 [box/x: space/size/x - space/vscroll/size/x]
		]
		space/hscroll/size/x: hx: either hdraw? [box/x][0]
		space/vscroll/size/y: vy: either vdraw? [box/y][0]
		full: max 1x1 max box - origin - (hx by vy) csz + (max 0x0 origin)
		
		;; set scrollers but avoid multiple recursive invalidation when changing srcollers fields
		;; (else may stack up to 99% of all rendering time)
		quietly space/hscroll/offset: ofs: 100% * (clip-p1/x - p1/x) / max 1 full/x
		quietly space/hscroll/amount: min 100% - ofs 100% * box/x / full/x
		quietly space/vscroll/offset: ofs: 100% * (clip-p1/y - p1/y) / max 1 full/y
		quietly space/vscroll/amount: min 100% - ofs 100% * box/y / full/y
		
		;@@ TODO: fast flexible tight layout func to build map? or will slow down?
		quietly space/map: compose/deep [				;@@ should be reshape (to remove scrollers) but it's too slow
			(space/content) [offset: 0x0 size: (box)]
			(in space 'hscroll) [offset: (box * 0x1) size: (space/hscroll/size)]
			(in space 'vscroll) [offset: (box * 1x0) size: (space/vscroll/size)]
			(in space 'scroll-timer) [offset: 0x0 size: 0x0]	;-- list it for tree correctness
		]
		maybe space/scroll-timer/rate: either any [hdraw? vdraw?] [16][0]	;-- turns off timer when unused!
		render in space 'scroll-timer					;-- scroll-timer has to appear in the tree for timers
		
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
					;; hardcoded 2 offset, because content may change and get out of sync with the frame
					visible-size: either empty? space/map [0x0][space/map/2/size]
					new: clip [(visible-size - cspace/size) 0x0] new 
					maybe space/origin: new				;-- can't set quietly - watched by grid-view to set grid/origin
					#debug grid-view [#print "on-change clipped to: (space/origin)"]
					invalidate-cache space
				]
			]
			content [invalidate-cache space]
		]
		space/space-on-change word :old :new
	]
	
	;@@ TODO: maybe make triangles *shared* for more juice? they always have the same size.. but this may limit styling
	templates/scrollable: make-template 'space [
		; cache?: off
		;@@ make limits a block to save some RAM?
		limits: 50x50 .. none		;-- in case no limits are set, let it not be invisible
		weight: 1
		origin: 0x0					;-- at which point `content` to place: >0 to right below, <0 to left above
		content: in generic 'empty						;-- should be defined (overwritten) by the user
		content-flow: 'planar							;-- one of: planar, vertical, horizontal ;@@ doc this!
		hscroll: make-space 'scrollbar [axis: 'x]
		vscroll: make-space 'scrollbar [axis: 'y size: reverse size]
		;; timer that scrolls when user presses & holds one of the arrows
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		scroll-timer: make-space 'timer [rate: 0]

		map: reduce [content [offset: 0x0 size: 0x0]]

		into: func [xy [pair!] /force name [word! none!]] [
			~/into self xy name
		]

		draw: function [/on canvas [none! pair!]] [~/draw self canvas]

		space-on-change: :on-change*
		#on-change-redirect
	]
]

paragraph-ctx: context [
	~: self
	
	ellipsize: function [layout [object!] text [string!] canvas [pair!]] [
		;; save existing buffer for reuse (if it's different from text)
		buffer: unless layout/text =? text [layout/text]
		len: length? text
		
		;; measuring "..." (3 dots) is unreliable
		;; because kerning between the last letter and first "." is not accounted for, resulting in random line wraps
		quietly layout/text: "...."
		ellipsis-width: first size-text layout
		
		quietly layout/text: text
		text-size: size-text layout						;@@ required to renew offsets/carets because I disabled on-change in layout!
		tolerance: 1									;-- prefer insignificant clipping over ellipsization ;@@ ideally, font-dependent
		if any [										;-- need to ellipsize if:
			text-size/y - tolerance > canvas/y				;-- doesn't fit vertically (for wrapped text)
			text-size/x - tolerance > canvas/x				;-- doesn't fit horizontally (unwrapped text)
		][
			;; find out what are the extents of the last visible line:
			last-visible-char: -1 + offset-to-caret layout canvas
			last-line-dy: -1 + second caret-to-offset/lower layout last-visible-char
			
			;; if last visible line is too much clipped, discard it an choose the previous line (if one exists)
			if over?: last-line-dy - tolerance > canvas/y [
				;; go 1px above line's top, but not into negative (at least 1 line should be visible even if fully clipped)
				last-line-dy: max 0 -1 + second caret-to-offset layout last-visible-char
			]
			
			;; this only works if text width is >= ellipsis, otherwise ellipsis itself gets wrapped to an invisible line
			;@@ more complex logic could account for ellipsis itself spanning 2-3 lines, but is it worth it?
			ellipsis-location: (max 0 canvas/x - ellipsis-width) by last-line-dy
			last-visible-char: -1 + offset-to-caret layout ellipsis-location
			unless buffer [buffer: make string! last-visible-char + 3]		;@@ use `obtain` or rely on allocator?
			quietly layout/text: append append/part clear buffer text last-visible-char "..."
			text-size: size-text layout
		]
		text-size
	]
	
	;; flags effect:
	;; wrap=elli=off -> canvas=inf
	;; wrap=on elli=off -> canvas=fixed
	;; wrap=off elli=on -> canvas=fixed, but wrapping should be off, i.e. layout/size=inf (don't use none! draw relies on this)
	;; wrap=elli=on -> canvas=fixed
	;@@ font won't be recreated on `make paragraph!`, but must be careful
	lay-out: function [space [object!] canvas [pair!] "positive!" ellipsize? [logic!] wrap? [logic!]] [
		#assert [0x0 +<= canvas]
		canvas: subtract-canvas canvas mrg2: 2x2 * space/margin
		width:  canvas/x								;-- should not depend on the margin, only on text part of the canvas
		;; cache of layouts is needed to avoid changing live text object! ;@@ REP #124
		layout: any [space/layouts/:width  space/layouts/:width: new-rich-text]
		unless empty? flags: space/flags [
			flags: compose [(1 by length? space/text) (space/flags)]
			remove find flags 'wrap						;-- leave no custom flags, otherwise rich-text throws an error
			remove find flags 'ellipsize				;-- this is way faster than `exclude`
		]
		;; every setting of layout value is slow, ~12us, while set-quiet is ~0.5us, size-text is 5+ us
		;; set width to determine height; but special case is ellipsization without wrapping: limited canvas but infinite layout
		quietly layout/size: either wrap? [max 1x1 canvas][infxinf]
		quietly layout/font: space/font					;@@ careful: fonts are not collected by GC, may run out of them easily
		quietly layout/data: flags						;-- support of font styles - affects width
		either all [ellipsize? canvas +< infxinf] [		;-- size has to be limited from both directions for ellipsis to be present
			quietly layout/extra: ellipsize layout (as string! space/text) canvas
		][
			quietly layout/text:  as string! space/text
			;; NOTE: #4783 to keep in mind
			quietly layout/extra: size-text layout		;-- 'size-text' is slow, has to be cached (by using on-change)
		]
		quietly space/layout: layout					;-- must return layout
	]

	draw: function [space [object!] canvas [pair! none!]] [
		ellipsize?: to logic! find space/flags 'ellipsize
		wrap?:      to logic! find space/flags 'wrap
		layout:     space/layout
		|canvas|: either any [wrap? ellipsize?][
			default canvas: infxinf						;-- none canvas is treated as infinity (need numbers for the layouts cache)
			constrain abs canvas space/limits			;-- could care less about fill flag for text
		][
			infxinf
		]
		
		;; this relies that layout/size is a pair! - lay-out should not assign none to it
		if any [										;-- redraw if:
			none? layout												;-- facet changed?
			if any [wrap? ellipsize?] [|canvas|/x <> layout/size/x]		;-- width changed and matters?
			if all [wrap? ellipsize?] [|canvas|/y <> layout/size/y]		;-- height changed and matters?
		][
			lay-out space |canvas| ellipsize? wrap?
		]
		
		;; size can be adjusted in various ways:
		;;  - if rendered < canvas, we can report either canvas or rendered
		;;  - if rendered > canvas, the same
		;; it's tempting to use canvas width and rendered height,
		;; but if canvas is huge e.g. 2e9, then it's not so useful,
		;; so just the rendered size is reported
		;; and one has to wrap it into a data-view space to stretch
		mrg2: space/margin * 2x2
		text-size: max 0x0 (constrain space/layout/extra + mrg2 space/limits) - mrg2	;-- don't make it narrower than min limit
		maybe space/size: mrg2 + text-size		;-- full size, regardless if canvas height is smaller?
		#debug sizing [#print "paragraph=(space/text) on (canvas) -> (space/size)"]
		
		;; this is quite hacky: rich-text is embedded directly into draw block
		;; so when layout/text is changed, we don't need to call `draw`
		;; just reassigning host's `draw` block to itself is enough to update it
		;; (and we can't stop it from updating)
		;; direct changes to /text get reflected into /layout automatically long as it scales
		;; however we wish to keep size up to date with text content, which requires a `draw` call
		compose [text (1x1 * space/margin) (space/layout)]
	]

	watched: make hash! [text font margin flags weight color]	;@@ maybe put color change into space-object?
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if all [
			find watched word
			not :old =? :new
		][
			invalidate space
		]
		space/space-on-change word :old :new
	]
	
 	templates/paragraph: make-template 'space [
		size:   none									;-- only valid after `draw` because it applies styles
		text:   ""
		margin: 0x0										;-- default = no margin
		;; NOTE: every `make font!` brings View closer to it's demise, so it has to use a shared font
		;; styles may override `/font` with another font created in advance 
		font:   none									;-- can be set in style, as well as margin
		; color:  none									;-- placeholder for user to control
		flags:  [wrap]									;-- [bold italic underline wrap] supported
		weight: 1

		;; this is required because rich-text object is shared and every change propagates onto the draw block 
		layouts: make map! 10							;-- map of width -> rich-text object
		layout:  none									;-- last chosen layout, text size is kept in layout/extra
		draw: func [/on canvas [pair! none!]] [~/draw self canvas]
		invalidate: does [quietly layout: none]			;-- will be laid out on next `draw`
		space-on-change: :on-change*
		#on-change-redirect
	]

	;; unlike paragraph, text is never wrapped
	templates/text: make-template 'paragraph [
		weight: 0
		flags:  []
	]

	;; url is underlined in style; is a paragraph for it's often long and needs to be wrapped
	templates/link: make-template 'paragraph [
		flags:   [wrap underline]
		color:   50.80.255								;@@ color should be taken from the OS theme
		command: [browse as url! text]
	]
]


;-- layout-agnostic template for list, ring & other layout using space collections
container-ctx: context [
	~: self

	;; all rendering is done by layout, because container by itself doesn't have enough info to perform it
	draw: function [
		cont [object!]
		type [word!]
		settings [block!]
		; xy1 [pair! none!]								;@@ unlikely window can be supported by general container
		; xy2 [pair! none!]
		; canvas [pair! none!]
	][
		; #assert [(none? xy1) = none? xy2]				;-- /only is ignored to simplify call in absence of `apply`
		len: cont/items/size
		#assert [len "container/draw works only for containers of limited items count"]
		r: make [] 4 * len
		
		drawn: make [] len * 6
		items: make [] len
		repeat i len [append items name: cont/items/pick i]		;@@ use map-each
		set [size: map: origin:] make-layout type items settings
		default origin: 0x0
		i: 0 foreach [name geom] map [					;@@ should be for-each [/i name geom]
			i: i + 1
			pos: geom/offset
			siz: geom/size
			drw: geom/drawn
			#assert [drw]
			remove/part find geom 'drawn 2				;-- no reason to hold `drawn` in the map anymore
			; skip?: all [xy2  not boxes-overlap?  pos pos + siz  0x0 xy2 - xy1]
			; unless skip? [
			org: any [geom/origin 0x0]
			compose/only/deep/into [
				;; clip has to be followed by a block, so `clip` of the next item is not mixed with previous
				; clip (pos) (pos + siz) [			;-- clip is required to support origin ;@@ but do we need origin?
				translate (pos + org) (drw)
				; ]
			] tail drawn
			; ]
		]
		quietly cont/map: map	;-- compose-map cannot be used because it renders extra time ;@@ maybe it shouldn't?
		maybe cont/size: constrain size cont/limits		;@@ is this ok or layout needs to know the limits?
		maybe cont/origin: origin
		compose/only [translate (negate origin) (drawn)]
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if find [items content origin] to word! word [invalidate-cache space]
		space/space-on-change word :old :new
	]

	templates/container: make-template 'space [
		size:    none									;-- only available after `draw` because it applies styles
		origin:  0x0									;-- used by ring layout to center itself around the pointer
		content: []
		items: function [/pick i [integer!] /size] [
			either pick [content/:i][length? content]
		]
		map: []
		into: func [xy [pair!] /force name [word! none!]] [
			into-map map xy + origin name
		]

		draw: function [
			; /on canvas [pair! none!]					;-- not used: layout gets it in settings instead
			/layout type [word!] settings [block!]
		][
			#assert [layout "container/draw requires layout to be provided"]
			~/draw self type settings; xy1 xy2
		]

		space-on-change: :on-change*
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
		draw: function [/on canvas [pair! none!]] [
			settings: [axis margin spacing canvas limits]
			container-draw/layout 'list settings; xy1 xy2
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
		round?: no

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
			set 'content [image box]
		]
		
		list-on-change: :on-change*
		#on-change-redirect
	]
]



tube-ctx: context [
	~: self

	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		if find [margin spacing axes align] word [invalidate-cache space]
		space/container-on-change word :old :new
	]
	
	templates/tube: make-template 'container [
		margin:  0x0
		spacing: 0x0
		axes:    [e s]
		align:   -1x-1
		
		container-draw: :draw
		draw: function [/on canvas [pair! none!]] [
			settings: [margin spacing align axes canvas limits]
			drawn: container-draw/layout 'tube settings
			#debug sizing [print ["tube with" content "on" canvas "->" size]]
			drawn
		]

		container-on-change: :on-change*
		#on-change-redirect
	]
]


switch-ctx: context [
	~: self
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			; command [bind space/command space]
			state [
				if :old <> :new [
					; do space/command
					invalidate-cache space
				]
			]
		]
		space/space-on-change word :old :new
	]
	
	templates/switch: make-template 'space [
		state: off
		; command: []
		data: make-space 'data-view []					;-- general viewer to be able to use text/images
		draw: func [/on canvas [none! pair!]] [
			also data/draw/on canvas					;-- draw avoids extra 'data-view' style in the tree
			size: data/size
		]
		space-on-change: :on-change*
		#on-change-redirect
	]
	
	templates/logic: make-template 'switch []			;-- uses different style
]


label-ctx: context [
	~: self
	
	on-change: function [label [object!] word [any-word!] old [any-type!] new [any-type!]] [
			spaces: label/spaces
		switch to word! word [
			image [
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
				type: either newline: find label/text #"^/" [
					spaces/text/text: copy/part label/text newline
					spaces/comment/text: copy next newline
					'comment
				][
					spaces/text/text: label/text
					'text
				]
				spaces/body/content: spaces/lists/:type	;-- invalidated by container
			]
			flags [
				spaces/text/flags: spaces/comment/flags: label/flags
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
		flags:   []										;-- transferred to text and comment
		
		spaces: object [								;-- all lower level spaces used by label
			image:      make-space 'image []
			sigil:      make-space 'text [limits: 20 .. none]	;-- 20 is for alignment of labels under each other ;@@ should be set in style?
			image-box:  make-space 'box  [content: in generic 'empty]	;-- needed for centering the image/sigil
			text:       make-space 'text []						;-- 1st line of text
			comment:    make-space 'text []						;-- lines after the 1st
			body:       make-space 'list [margin: 0x0 spacing: 0x0 axis: 'y  content: [text comment]]
			text-box:   make-space 'box  [content: 'body]		;-- needed for text centering
			lists: [text: [text] comment: [text comment]]		;-- used to avoid extra bind in on-change
			set 'content [image-box text-box]
		]
		
		list-on-change: :on-change*
		#on-change-redirect
	]
]



;; a polymorphic style: given `data` creates a visual representation of it
;; `content` can be used directly to put a space into it (useful in clickable, button)
data-view-ctx: context [
	~: self

	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		; print ["data-view/on-change" word mold/flat/part :old 40 "->" mold/flat/part :new 40]
		push-font: [
			cspace: get space/content
			if all [in cspace 'font  not cspace/font =? space/font] [
				cspace/font: space/font
				invalidate space
			]
		]
		switch to word! word [
			spacing [invalidate-cache space]
			font [do push-font]
			data [
				space/content: VID/wrap-value :new space/wrap?	;@@ maybe reuse the old space if it's available?
				do push-font
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
		wrap?:   off									;-- controls choice between text (off) and paragraph (on)
		
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
		space     [object!]
		axis      [word!]   
		dir       [integer!]
		from      [integer!]
		requested [integer!]
	][
		cspace: get space/content
		either function? cavail?: select cspace 'available? [	;-- use content/available? when defined
			cavail? axis dir from requested
		][														;-- otherwise deduce from content/size
			csize: any [cspace/size 0x0]						;@@ or assume infinity if no /size in content?
			clip [0 requested] either dir < 0 [from][csize/:axis - from]
		]
	]

	;; window always has to render content on it's whole size,
	;; otherwise how does it know how big it really is
	;; (considering content can be smaller and window has to follow it)
	;; but only xy1-xy2 has to appear in the render result block and map!
	;; area outside of canvas and within xy1-xy2 may stay not rendered as long as it's size is guaranteed
	draw: function [window [object!] canvas [pair! none!]] [
		#debug grid-view [#print "window/draw is called on canvas=(canvas)"]
		#assert [word? window/content]
		-org: negate org: window/origin
		;; there's no size for infinite spaces so pages*canvas is used as drawing area
		;; no constraining by /limits here, since window is not supposed to be limited ;@@ should it be constrained?
		set [canvas': fill:] decode-canvas canvas
		size: window/pages * finite-canvas canvas'
		unless zero? area? size [						;-- optimization ;@@ although this breaks the tree, but not critical?
			cspace: get content: window/content
			cdraw: render/window/on content -org -org + size canvas
			;; once content is rendered, it's size is known and may be less than requested,
			;; in which case window should be contracted too, else we'll be scrolling over an empty window area
			if cspace/size [size: min size cspace/size - org]	;-- size has to be finite
		]
		maybe window/size: size
		#debug sizing [#print "window resized to (window/size)"]
		;; let right bottom corner on the map also align with window size
		quietly window/map: compose/deep [(content) [offset: (org) size: (size)]]
		compose/only [translate (org) (cdraw)]
	]
	
	on-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			origin limits pages content [invalidate-cache space]
		]
		space/space-on-change word :old :new
	]
		
	templates/window: make-template 'space [
		;; when drawn auto adjusts it's `size` up to `canvas * pages` (otherwise scrollbars will always be visible)
		pages:  10x10							;-- window size multiplier in canvas sizes (= size of inf-scrollable)
		origin: 0x0								;-- content's offset (negative)
		
		;; window does not require content's size, so content can be an infinite space!
		content: generic/empty
		map: []

		available?: func [
			"Should return number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
			axis      [word!]    "x/y"
			dir       [integer!] "-1/1"
			from      [integer!] "axis coordinate to look ahead from"
			requested [integer!] "max look-ahead required"
		][
			~/available? self axis dir from requested
		]
	
		draw: func [/on canvas [none! pair!]] [~/draw self canvas]
		
		space-on-change: :on-change*
		#on-change-redirect
	]
]

inf-scrollable-ctx: context [
	~: self
	
	roll: function [space [object!]] [
		#debug grid-view [#print "origin in inf-scrollable/roll: (space/origin)"]
		window: space/window
		wofs': wofs: negate window/origin				;-- (positive) offset of window within it's content
		#assert [window/size "window must be rendered before it's rolled"]
		wsize:  window/size
		before: negate space/origin						;-- area before the current viewport offset
		#assert [space/map/window]						;-- roll attempt on an empty viewport, or map is invalid?
		viewport: space/map/window/size
		#assert [0x0 +< viewport]						;-- roll on empty viewport is most likely an unwanted roll
		if zero? area? viewport [return no]
		after:  wsize - (before + viewport)				;-- area from the end of viewport to the end of window
		foreach x [x y] [
			any [										;-- prioritizes left/up jump over right/down
				all [
					before/:x <= space/look-around
					0 < avail: window/available? x -1 wofs'/:x space/jump-length
					wofs'/:x: wofs'/:x - avail
				]
				all [
					after/:x  <= space/look-around
					0 < avail: window/available? x  1 wofs'/:x + wsize/:x space/jump-length
					wofs'/:x: wofs'/:x + avail
				]
			]
		]
		;; transfer offset from scrollable into window, in a way detectable by on-change
		if wofs' <> wofs [
			;; effectively viewport stays in place, while underlying window location shifts
			#debug sizing [#print "rolling (space/size) with (space/content) by (wofs' - wofs)"]
			maybe space/origin: space/origin + (wofs' - wofs)
			maybe window/origin: negate wofs'
		]
		wofs' <> wofs									;-- should return true when updates origin - used by event handlers ;@@ or not?
	]
	
	draw: function [space [object!] canvas [none! pair!]] [
		#debug sizing [#print "inf-scrollable draw is called on (canvas)"]
		render in space 'roll-timer						;-- timer has to appear in the tree for timers to work
		drawn: space/scrollable-draw/on canvas
		any-scrollers?: not zero? add area? space/hscroll/size area? space/vscroll/size
		maybe space/roll-timer/rate: either any-scrollers? [4][0]	;-- timer is turned off when unused
		;; scrollable/draw removes roll-timer, have to restore
		;; the only benefit of this is to count spaces more accurately:
		repend space/map [in space 'roll-timer [offset 0x0 size 0x0]]
		#debug sizing [#print "inf-scrollable with (space/content) on (canvas) -> (space/size) window: (space/window/size)"]
		#assert [space/window/size]
		drawn
	]
	
	templates/inf-scrollable: make-template 'scrollable [	;-- `infinite-scrollable` is too long for a name
		jump-length: 200						;-- how much more to show when rolling (px) ;@@ maybe make it a pair?
		look-around: 50							;-- zone after head and before tail that triggers roll-edge (px)

		window: make-space 'window [size: none]			;-- size is set by window/draw
		content: 'window

		;; timer that calls `roll` when dragging
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		roll-timer: make-space 'timer [rate: 0]

		roll: does [~/roll self]

		scrollable-draw: :draw
		draw: function [/on canvas [pair! none!]] [~/draw self canvas]
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
		canvas [pair!]    "Canvas on which it is rendered; positive!"
		level  [integer!] "Offset in pixels from the 0 of main axis"
	][
		#assert [0x0 +<= canvas]						;-- shouldn't happen - other funcs must pass positive canvas here
		x: list/axis
		if level < list/margin/:x [return compose [margin 1 (level)]]
		#debug list-view [level0: level]				;-- for later output
		canvas: encode-canvas canvas make-pair [1x1 x -1]	;-- list items will be filled along secondary axis
		
		; either empty? list/map [
			i: 1
			level: level - list/margin/:x
		; ][
			;@@ this needs reconsideration, because canvas is not guaranteed to have persisted! plus it has a bug now
			;@@ ideally I'll have to have a map of item (object) -> list of it's offsets on variuos canvases
			;@@ invalidation conditions then will become a big question
			; ;; start off the previously rendered first item's offset
			; #assert [not empty? list/icache]
			; #assert ['item = list/map/1]
			; item-spaces: reduce values-of list/icache
			; i: pick keys-of list/icache j: index? find/same item-spaces get list/map/1
			; level: level - list/map/2/offset/:x
		; ]
		imax: list/items/size
		space: list/spacing								;-- return value is named "space"
		fetch-ith-item: [								;-- sets `item` to size
			obj: get name: list/items/pick i
			;; presence of call to `render` here is a tough call
			;; existing previous size is always preferred here, esp. useful for non-cached items
			;; but `locate-line` is used by `available?` which is in turn called:
			;; - when determining initial window extent (from content size)
			;; - every time window gets scrolled closer to it's borders (where we have to render out-of-window items)
			;; so there's no easy way around requiring render here, but for canvas previous window size can be used
			render/on name canvas
			item: obj/size
		]
		;@@ should this func use layout or it will only complicate things?
		;@@ right now it independently of list-layout computes all offsets
		;@@ which saves some CPU time, because there's no need in final render here
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

	item-length?: function [list [object!] i [integer!]] [
		#assert [0 < i]
		#assert [list/icache/:i]
		item: get list/icache/:i						;-- must be cached by previous locate-line call
		r: item/size/(list/axis)
		#debug list-view [#print "item-length? (i) -> (r)"]
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
			space [h-ofs: h-ofs + item-length? list h-idx]
			margin [
				either h-idx = 1 [
					h-idx: none
				][
					h-idx: list/items/size				;-- can't be none since right margin is present
					either h-idx <= 0 [					;-- data/size can be 0, then there's no item to draw
						h-idx: none
					][
						h-ofs: h-ofs + item-length? list h-idx
					]
				]
			]
		]
		r: reduce [l-idx l-ofs h-idx h-ofs]
		#debug list-view [#print "locate-range (low-level),(high-level) -> (mold r)"]
		r
	]
	
	available?: function [list [object!] canvas [pair!] "positive!" axis [word!] dir [integer!] from [integer!] requested [integer!]] [
		#assert [0x0 +<= canvas]						;-- shouldn't happen
		if axis <> list/axis [
			;; along secondary axis there is no absolute width: no way to know some distant unrendered item's width
			;; so just previously rendered width is used (and will vary as list is rolled, if some items are bigger than canvas)
			#assert [list/size]
			return either dir < 0 [from][min requested list/size/:axis - from]
		]
		set [item: idx: ofs:] locate-line list canvas from + (requested * dir)
		r: max 0 requested - switch item [
			space item [0]
			margin [either idx = 1 [0 - ofs][ofs - list/margin/:axis]]
		]
		#debug list-view [#print "available? dir=(dir) from=(from) req=(requested) -> (r)"]
		r
	]
			
	;; container/draw only supports finite number of `items`, infinite needs special handling
	;; it's also too general, while this `draw` can be optimized better
	list-draw: function [lview [object!] canvas [pair! none!] xy1 [pair!] xy2 [pair!]] [
		#debug sizing [#print "list-view/list draw is called on (canvas), window: (xy1)..(xy2)"]
		set [canvas: _:] decode-canvas canvas			;-- fill is not used: X is infinite, Y is always filled along if finite
		; canvas: constrain canvas lview/limits			;-- must already be constrained; this is list, not list-view (smaller by scrollers)
		list: lview/list
		worg: negate lview/window/origin				;-- offset of window within content
		axis: list/axis
		; #assert [canvas/:axis > 0]						;-- some bug in window sizing likely
		#assert [canvas +< infxinf]						;-- window is never infinite
		;; i1 & i2 will be used by picker func (defined below), which limits number of items to those within the window
		set [i1: o1: i2: o2:] locate-range list canvas worg/:axis worg/:axis + xy2/:axis - xy1/:axis
		unless all [i1 i2] [							;-- no visible items (see locate-range)
			maybe list/size: list/margin * 2x2
			return quietly list/map: []
		]
		#assert [i1 <= i2]

		canvas:   extend-canvas canvas axis				;-- infinity will compress items along the main axis
		guide:    axis2pair axis
		origin:   guide * (xy1 - o1 - list/margin)
		settings: with [list 'local] [axis margin spacing canvas origin]
		set [new-size: new-map:] make-layout 'list :list-picker settings
		;@@ make compose-map generate rendered output? or another wrapper
		;@@ will have to provide canvas directly to it, or use it from geom/size
		drawn: make [] 3 * (length? new-map) / 2
		foreach [name geom] new-map [
			#assert [geom/drawn]						;@@ should never happen?
			if drw: geom/drawn [						;-- invisible items don't get re-rendered
				remove/part find geom 'drawn 2			;-- no reason to hold `drawn` in the map anymore
				compose/only/into [translate (geom/offset) (drw)] tail drawn
			]
		]
		maybe list/size: new-size
		quietly list/map: new-map
		drawn
	]

	;; hack to avoid recreation of this func inside list-draw
	list-picker: func [/size /pick i] with :list-draw [
		either size [i2 - i1 + 1][list/items/pick i + i1 - 1]
	]
	
	list-on-change: function [lview [object!] word [word! set-word!] old [any-type!] new [any-type!]] [
		if all [
			word = 'axis
			lview/size									;-- do not trigger during initialization
		][
			#assert [find [x y] :new]
			lview/content-flow: switch new [x ['horizontal] y ['vertical]]
			if :old <> :new [invalidate-cache lview/list]
		]
		lview/list/list-on-change word :old :new
	]
		
	templates/list-view: make-template 'inf-scrollable [
		; reversed?: no		;@@ TODO - for chat log, map auto reverse
		; size:   none									;-- avoids extra triggers in on-change
		pages:  10
		source: []
		data: function [/pick i [integer!] /size] [		;-- can be overridden
			either pick [source/:i][length? source]		;-- /size may return `none` for infinite data
		]
		
		wrap-data: function [item-data [any-type!]][
			spc: make-space 'data-view [wrap?: on]
			set/any 'spc/data :item-data
			anonymize 'item spc
		]

		window/content: 'list
		list: make-space 'list [
			axis: 'y
			
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

			available?: function [axis [word!] dir [integer!] from [integer!] requested [integer!]] [
				;; must pass positive canvas (uses last rendered list-view size)
				~/available? self size axis dir from requested
			]
			
			list-on-change: :on-change*
		]

		list/on-change*: func [word [any-word!] old [any-type!] new [any-type!]] [
			~/list-on-change self word :old :new
		]
		list/draw: function [/window xy1 [pair!] xy2 [pair!] /on canvas [pair! none!]] [
			~/list-draw self canvas xy1 xy2
		]
	]
]


;@@ TODO: list-view of SPACES?
;@@ TODO: grid layout?

;; grid's key differences from list of lists:
;; * it aligns columns due to fixed column size
;; * it CAN make cells spanning multiple rows (impossible in list of lists)
;; * it uses fixed row heights, and because of that it CAN have infinite width (but requires separate height inferrence)
;;   (by "infinite" I mean "big enough that it's unreasonable to scan it to infer the size (or UI becomes sluggish)")
;; * grid is better for big empty cells that user is supposed to fill,
;;   while list is better for known autosized content
grid-ctx: context [
	~: self
	
	into: func [grid [object!] xy [pair!] name [word! none!]] [	;-- faster than generic map-based into
		if name [return into-map grid/map xy name]		;-- let into-map handle it ;@@ slow! need a better solution!
		set [cell: offset:] locate-point grid xy yes
		mcell: grid/get-first-cell cell
		if cell <> mcell [
			offset: offset + grid/get-offset-from mcell cell	;-- pixels from multicell to this cell
		]
		all [
			name: grid/cells/pick mcell
			name: grid/wrap-space mcell name
			reduce [name offset]
		]
	]
	
	calc-bounds: function [grid [object!]] [
		if lim: grid/size-cache/bounds [return lim]		;-- already calculated
		bounds: grid/bounds								;-- call it in case it's a function
		unless any ['auto = bounds/x  'auto = bounds/y] [	;-- no auto limit set (but can be none)
			#debug grid-view [#print "grid/calc-bounds [no auto] -> (bounds)"]
			return bounds
		]
		lim: copy bounds
		xymax: either empty? grid/content [
			0x0
		][
			remove find xys: keys-of grid/spans 'default	;-- if `spans` is correct, it contains the lowest rightmost multicell coordinate
			append xys keys-of grid/content
			second minmax-of xys						;@@ should be `accumulate`
		]
		if 'auto = lim/x [lim/x: xymax/x]				;-- pass `none` as is
		if 'auto = lim/y [lim/y: xymax/y]
		#debug grid-view [#print "grid/calc-bounds [auto] -> (lim)"]
		lim
	]

	break-cell: function [cell1 [pair!]] [				;-- `cell1` must be the starting cell
		if 1x1 <> span: grid/get-span cell1 [
			#assert [1x1 +<= span]						;-- ensure it's a first cell of multicell
			xyloop xy span [							;@@ should be for-each
				remove/key grid/spans xy': cell1 + xy - 1x1
			]
		]
	]

	unify-cells: function ["Mark cell range as spanned" grid [object!] cell1 [pair!] span [pair!]] [
		if 1x1 <> old: grid/get-span cell1 [
			if old +< 1x1 [
				ERROR "Cell (cell1 + old) should be broken before (cell1)"	;@@ or break silently? probably unexpected move..
			]
			break-cell grid cell1
		]
		xyloop xy span [								;@@ should be for-each
			#assert [1x1 = grid/get-span cell1 + xy - 1x1]
			grid/spans/(cell1 + xy - 1x1): 1x1 - xy		;-- each span points to the first cell
		]
		grid/spans/:cell1: span
	]
	
	set-span: function [grid [object!] cell1 [pair!] span [pair!] force [logic!]] [
		if span = grid/get-span cell1 [exit]
		#assert [1x1 +<= span]							;-- forbid setting of span to non-positives
		xyloop xy span [								;-- break all multicells within the area
			cell: cell1 + xy - 1
			old-span: grid/get-span cell
			if old-span <> 1x1 [
				all [
					not force
					any [cell <> cell1  1x1 +<= old-span]	;-- only `cell1` is broken silently if it's a multicell
					ERROR "Cell (cell1 + old-span) should be broken before (cell1)"
				]
				break-cell grid cell + min 0x0 old-span
			]
		]
		unify-cells grid cell1 span
	]

	get-offset-from: function [grid [object!] c1 [pair!] c2 [pair!]] [
		r: 0x0
		foreach [x wh?] [x grid/col-width? y grid/row-height?] [
			x1: min c1/:x c1/:x
			x2: max c1/:x c2/:x
			if x1 = x2 [continue]
			wh?: get/any wh?							;@@ workaround for #4988
			for xi: x1 x2 - 1 [r/:x: r/:x + wh? xi]		;@@ should be sum map
			r/:x: r/:x + (x2 - x1 * grid/spacing/:x)
			if x1 > x2 [r/:x: negate r/:x]
		]
		r
	]
		
	;; fast row/col locator assuming that widths/heights array size is smaller than the row/col number
	;; returns any of:
	;;   [margin 1 offset] - within the left margin (or if point is negative, then to the left of it)
	;;   [cell   1 offset] - within 1st cell
	;;   [space  1 offset] - within space between 1st and 2nd cells
	;;   [cell   2 offset] - within 2nd cell
	;;   [space  2 offset]
	;;   ...
	;;   [cell   N offset]
	;;   [margin 2 offset] - within the right margin (only when limit is defined),
	;;                       offset can be bigger(!) than right margin if point is outside the space's size
	;@@ TODO: maybe cache offsets for faster navigation on bigger data
	;; doesn't care about pinned cells, treats grid as continuous
	locate-line: function [
		grid  [object!]
		level [integer!] "pixels from 0"
		array [map!]     "widths or heights"
		axis  [word!]    "x or y"
	][
		mg: grid/margin/:axis
		if level < mg [return reduce ['margin 1 level]]		;-- within the first margin case
		level: level - mg

		bounds: grid/calc-bounds
		sp:     grid/spacing/:axis
		lim:    bounds/:axis
		def:    array/default
		#assert [def]									;-- must always be defined
		whole:  0				;@@ what if lim = 0?	;-- number of whole rows/columns subtracted
		size:   none
		keys:   sort keys-of array
		remove find keys 'min
		either 1 = len: length? keys [					;-- 1 = special case - all cells are of their default size
			catch [sub-def* 0 level]					;@@ assumes default size > 0 (at least 1 px) - need to think about 0
		][
			keys: sort keys-of array
			remove find keys 'default
			#assert [0 < keys/1]						;-- no zero or negative row/col numbers expected
			key: 0
			catch [
				repeat i len - 1 [						;@@ should be for-each/stride [/i prev-key key]
					prev-key: key
					key: keys/:i
					
					before: key - 1 - prev-key			;-- default-sized cells to subtract (may be 'auto)
					if before > 0 [sub-def* prev-key before]
					
					if 'auto = size: array/:key [		;-- row is marked for autosizing
						#assert [array =? heights]
						size: grid/row-height? key		;-- try to fetch it from the cache or calculate
					]
					if 0 = sub* 1 size + sp [throw 1]	;-- this cell contains level
				]
				sub-def* key level						;@@ assumes default size > 0 (at least 1 px) - need to think about 0
			]
		]
		unless size [
			size: either axis = 'x [grid/col-width? 1 + whole][grid/row-height? 1 + whole]	;@@ optimize this?
		]
		reduce case [
			level < size              [['cell   1 + whole level]]
			all [lim lim - 1 = whole] [['margin 2         level - size]]
			'else                     [['space  1 + whole level - size]]
		]
	]
		
	;; funcs used internally by locate-line (to avoid recreation of them every time)
	sub*: func [n size] with :locate-line [
		if lim [n: min n lim - 1 - whole]
		n: min n to 1 level / size
		whole: whole + n
		level: level - (n * size)
		#debug grid-view [#print "sub (n) (size) -> whole: (whole) level: (level)"]
		n
	]
	sub-def*: func [from n /local r j] with :locate-line [
		#debug grid-view [#print "sub-def (from) (n) def: (def)"]
		either integer? def [
			if n <> sub* n sp + def [size: def throw 1]	;-- point is within a row/col of default size
		][											;-- `default: auto` case where each row size is different
			#assert [array =? grid/heights]
			repeat j n [
				size: grid/row-height? from + j
				if 0 = sub* 1 sp + size [throw 1]	;-- point is within the last considered row (size is valid)
			]
		]
	]

	locate-point: function [grid [object!] xy [pair!] screen? [logic!]] [
		if screen? [
			unless (pinned: grid/pinned) +<= pinned-area: 0x0 [	;-- nonzero pinned rows or cols?
				pinned-area: grid/spacing + grid/get-offset-from 1x1 (pinned + 1x1)
			]
			;; translate heading coordinates into the beginning of the grid
			unless (pinned-area - grid/origin) +<= xy [xy: xy + grid/origin]
		]
		
		bounds: grid/calc-bounds
		r: copy [0x0 0x0]
		foreach [x array wh?] reduce [
			'x grid/widths  :grid/col-width?
			'y grid/heights :grid/row-height?
		][
			set [item: idx: ofs:] locate-line grid xy/:x array x
			#debug grid-view [#print "locate-line/(x)=(xy/:x) -> [(item) (idx) (ofs)]"]
			switch item [
				space [ofs: ofs - grid/spacing/:x  idx: idx + 1]
				margin [
					either idx = 1 [
						ofs: ofs - grid/margin/:x
					][
						idx: bounds/:x
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

	row-height?: function [grid [object!] y [integer!]][
		if 'auto = r: any [grid/heights/:y grid/heights/default] [
			r: any [grid/hcache/:y  grid/hcache/:y: calc-row-height grid y]
		]
		r
	]
		
	;@@ ensure it's only called from within render
	;@@ ensure it's called top-down only, so it can get upper row sizes from the cache
	calc-row-height: function [
		"Render row Y to obtain it's height"
		grid [object!] y [integer!]
	][
		#assert ['auto = any [grid/heights/:y grid/heights/default]]	;-- otherwise why call it?
		bounds: grid/calc-bounds
		; #assert [size-cache/bounds]
		xlim: bounds/x
		#assert [integer? xlim]							;-- row size cannot be calculated for infinite grid
		hmin: obtain block! xlim + 1					;-- can't be static because has to be reentrant!
		#leaving [stash hmin]
		append hmin any [grid/heights/min 0]
		for x: 1 xlim [
			canvas: encode-canvas (as-pair grid/col-width? x infxinf/y) 1x1		;-- fill the cell
			span: grid/get-span xy: as-pair x y
			if span/x < 0 [continue]					;-- skip cells of negative x span (counted at span = 0 or more)
			cell1: grid/get-first-cell xy
			height1: 0
			if content: grid/cells/pick cell1 [
				render/on grid/wrap-space cell1 content canvas	;-- render to get the size
				cspace: get content
				height1: cspace/size/y
			]
			case [
				span/y = 1 [
					#assert [0 < span/x]
					append hmin height1
				]
				span/y + y = cell1/y [					;-- multi-cell vertically ends after this row
					for y2: cell1/y y - 1 [
						height1: height1 - grid/spacing/y - grid/row-height? y2
					]
					append hmin height1
				]
				;-- else just ignore this and use heights/min
			]
			x: x + max 0 span/x - 1						;-- skip horizontal span
		]
		height: second minmax-of hmin					;-- choose biggest of constraints
		#debug grid-view [#print "calc-row-height (y) -> (height)"]
		height
	]

	;; unlike `cell-height?` this does nothing complex, just sums widths, does not require cached row height
	cell-width?: function [grid [object!] xy [pair!]] [
		#assert [xy = grid/get-first-cell xy]	;-- should be a starting cell
		xspan: first grid/get-span xy
		r: 0 repeat x xspan [r: r + grid/col-width? x - 1 + xy/x]
		r + (xspan - 1 * grid/spacing/x)
	]
		
	cell-height?: function [grid [object!] xy [pair!]] [
		#assert [xy = grid/get-first-cell xy]	;-- should be a starting cell
		#debug grid-view [						;-- assertion doesn't hold for self-containing grids
			#assert [grid/ccache/:xy]			;-- cell should be rendered already (for row-heights to return immediately)
		]
		yspan: second grid/get-span xy
		r: 0 repeat y yspan [r: r + grid/row-height? y - 1 + xy/y]
		r + (yspan - 1 * grid/spacing/y)
	]
		
	cell-size?: function [grid [object!] xy [pair!]] [
		as-pair  cell-width? grid xy  cell-height? grid xy 
	]
		
	calc-size: function [grid [object!]] [
		if r: grid/size-cache/size [return r]			;-- already calculated
		#debug grid-view [#print "grid/calc-size is called!"]
		#assert [not grid/infinite?]
		bounds: grid/calc-bounds
		bounds: bounds/x by bounds/y					;-- turn block into pair
		#debug grid-view [#assert [0 <> area? bounds]]
		r: grid/margin * 2 + (grid/spacing * max 0x0 bounds - 1)
		repeat x bounds/x [r/x: r/x + grid/col-width?  x]
		repeat y bounds/y [r/y: r/y + grid/row-height? y]
		#debug grid-view [#print "grid/calc-size -> (r)"]
		grid/size-cache/size: r
	]
		
	;@@ TODO: at least for the chosen range, cell/drawn should be invalidated and cell/size recalculated
	draw-range: function [
		"Used internally by DRAW. Returns map slice & draw code for a range of cells"
		grid [object!] cell1 [pair!] cell2 [pair!] start [pair!] "Offset from origin to cell1"
	][
		size:  cell2 - cell1 + 1
		drawn: make [] size: area? size
		map:   obtain block! size * 2					;-- draw appends it, so it can be obtained
		done:  obtain map! size							;-- local to this range of cells
		#leaving [stash done]
														;-- sometimes the same mcell may appear in pinned & normal part
		for cell: cell1 cell2 [
			cell1-to-cell: either cell/x = cell1/x [	;-- pixels from cell1 to this cell
				grid/get-offset-from cell1 cell
			][
				cell1-to-cell + grid/get-offset-from cell - 1x0 cell	;-- faster to get offset from the previous cell
			]

			mcell: grid/get-first-cell cell				;-- row/col of multicell this cell belongs to
			if any [
				done/:mcell								;-- skip mcells that were drawn for this group
				not content-name: grid/cells/pick mcell		;-- cell is not defined? skip the draw
			] [continue]
			done/:mcell: true							;-- mark it as drawn
			
			pinned?: grid/is-cell-pinned? cell
			mcell-to-cell: grid/get-offset-from mcell cell	;-- pixels from multicell to this cell
			draw-ofs: start + cell1-to-cell - mcell-to-cell	;-- pixels from draw's 0x0 to the draw box of this cell
			
			mcspace: get mcname: grid/wrap-space mcell content-name
			canvas: (cell-width? grid mcell) by infxinf/y	;-- sum of spanned column widths
			render/on mcname encode-canvas canvas 1x-1		;-- render content to get it's size - in case it was invalidated
			mcsize: canvas/x by cell-height? grid mcell		;-- size of all rows/cols it spans = canvas size
			mcdraw: render/on mcname encode-canvas mcsize 1x1	;-- re-render to draw the full background
			;@@ TODO: if grid contains itself, map should only contain each cell once - how?
			geom: compose [offset (draw-ofs) size (mcsize)]
			repend map [mcname geom]					;-- map may contain the same space if it's both pinned & normal
			compose/only/into [							;-- compose-map calls extra render, so let's not use it here
				translate (draw-ofs) (mcdraw)			;@@ can compose-map be more flexible to be used in such cases?
			] tail drawn
		]
		reduce [map drawn]
	]
	;@@ this hack allows styles to know whether this cell is pinned or not
	pinned?: does [get bind 'pinned? :draw]

	;; uses canvas only to figure out what cells are visible (and need to be rendered)
	draw: function [grid [object!] canvas [none! pair!] wxy1 [none! pair!] wxy2 [none! pair!]] [
		#debug grid-view [#print "grid/draw is called with window xy1=(wxy1) xy2=(wxy2)"]
		#assert [any [not grid/infinite?  all [canvas wxy1 wxy2]]]	;-- bounds must be defined for an infinite grid
	
		set [canvas: fill:] decode-canvas canvas
		cache: grid/size-cache
		set cache none

		cache/bounds: grid/cells/size					;-- may call calc-size to estimate number of cells
		#assert [cache/bounds]
		;-- locate-point calls row-height which may render cells when needed to determine the height
		default wxy1: 0x0
		unless wxy2 [wxy2: wxy1 + grid/calc-size]
		xy1: wxy1 - grid/origin
		xy2: min xy1 + canvas wxy2

		;; affects xy1 so should come before locate-point
		pinned?: yes									;@@ hack for styles - need a better design!
		unless (pinned: grid/pinned) +<= 0x0 [			;-- nonzero pinned rows or cols?
			xy0: grid/margin + xy1						;-- location of drawn pinned cells relative to grid's origin
			set [map: drawn-common-header:] draw-range grid 1x1 pinned xy0
			xy1: xy1 + grid/get-offset-from 1x1 (pinned + 1x1)	;-- location of unpinned cells relative to origin
		]
		#debug grid-view [#print "drawing grid from (xy1) to (xy2)"]

		set [cell1: offs1:] grid/locate-point xy1
		set [cell2: offs2:] grid/locate-point xy2
		all [none? cache/size  not grid/infinite?  grid/calc-size]
		#assert [any [grid/infinite? cache/size]]		;-- must be set by calc-size
		maybe grid/size: cache/size

		;@@ create a grid layout?
		stash grid/map
		new-map: obtain block! 2 * area? cell2 - cell1 + 1
		if map [append new-map map  stash map]			;-- add previously drawn pinned corner
		
		if pinned/x > 0 [
			set [map: drawn-row-header:] draw-range grid
				(1 by cell1/y) (pinned/x by cell2/y)
				xy0/x by (xy1/y - offs1/y)
			append new-map map  stash map
		]
		if pinned/y > 0 [
			set [map: drawn-col-header:] draw-range grid
				(cell1/x by 1) (cell2/x by pinned/y)
				(xy1/x - offs1/x) by xy0/y
			append new-map map  stash map
		]

		pinned?: no
		set [map: drawn-normal:] draw-range grid cell1 cell2 (xy1 - offs1)
		append new-map map  stash map
		;-- note: draw order (common -> headers -> normal) is important
		;-- because map will contain intersections and first listed spaces are those "on top" from hittest's POV
		;-- as such, map doesn't need clipping, but draw code does

		quietly grid/map: new-map
		reshape [
			;-- headers also should be fully clipped in case they're multicells, so they don't hang over the content:
			clip  0x0         !(xy1)            !(drawn-common-header)	/if drawn-common-header
			clip !(xy1 * 1x0) !(xy2/x by xy1/y) !(drawn-col-header)		/if drawn-col-header
			clip !(xy1 * 0x1) !(xy1/x by xy2/y) !(drawn-row-header)		/if drawn-row-header
			clip !(xy1)       !(xy2)            !(drawn-normal)
		]
	]
	
	;; this should not use hcache, or it will have to be cleared all the time
	col-height?: function [grid [object!] col [integer!] width [integer!] rows [integer!]] [	;-- used by autofit only
		r: 0
		canvas: encode-canvas width by infxinf/y 1x-1
		repeat i rows [
			xy: col by i
			h: any [grid/heights/:i grid/heights/default]		;-- row may be fixed
			unless integer? h [
				space: get name: any [grid/ccache/:xy  grid/wrap-space xy grid/cells/pick xy]
				render/on name canvas
				h: space/size/y
			]
			r: r + h									;-- does not use any spacing or margins
		]
		r
	]
	
	;; stochastic content-agnostic column width fitter
	;@@ should also account for minimum cell width - don't make columns less than that (at least optionally)
	;@@ make it available from grid/ or grid-view/
	autofit: function [
		"Automatically adjust GRID column widths for best look"
		grid  [object!]
		width [integer!] "Total grid width to fit into"
	][
		#assert [not grid/infinite? "Adjustment of infinite grid will take infinite time!"]
		;; does not modify grid/heights - at least some of them must be `auto` for this func to have effect
		bounds: grid/cells/size
		nx: bounds/x  ny: bounds/y
		if any [nx <= 1 ny <= 0] [exit]					;-- nothing to fit - single column or no rows
		
		widths: grid/widths
		w0: to integer! width / nx
		repeat i nx [widths/:i: w0]						;-- starting point - uniform
		
		min-width: any [grid/widths/min 5]
		precision: 5									;-- limit when to stop adjusting (pixels)
		loop 10 [										;-- prevent deadlocks
			adjustment: 0
			h2: col-height? grid 1 widths/1 ny
			for x: 2 nx [
				w1: widths/(x - 1)  w2: widths/:x
				h1: h2  h2: col-height? grid x w2 ny
				if h1 = h2 [continue]					;-- balanced - don't touch this time
				;@@ maybe make a few attempts? e.g. 50% 100% 150% 200% of dw, or a few random points?
				;@@ random might be bad for result stability, but more reliable in case of big spaces within
				dh: clip [5% 50%] 50% * (h2 - h1) / (max 1 min h1 h2)
				dw: to integer! (min w1 w2) * dh
				w1: max min-width w1 - dw
				w2: max min-width w2 + dw
				new-h1: col-height? grid x - 1 w1 ny
				new-h2: col-height? grid x     w2 ny
				; print [h1 h2 '-> new-h1 new-h2]
				if positive? win: (max h1 h2) - (max new-h1 new-h2) [	;@@ maybe also smaller attempts?
					h2: new-h2
					widths/(x - 1): w1
					widths/:x:      w2
					adjustment: max adjustment win
				]
			]
			; ?? adjustment
			if adjustment <= precision [break]
		]
		invalidate grid									;-- also clears hcache
	]
	
	;; called by global invalidate
	invalidate*: function [grid [object!] cell [pair! none!]] [
		either cell [
			remove/key grid/hcache cell/y
			remove/key grid/ccache cell
			grid/size-cache/size: none
		][
			clear grid/hcache							;-- clear should never be called on big datasets
			set grid/size-cache none					;-- reset calculated bounds
		]
	]
	
	on-change: function [grid [object!] word [word! set-word!] old [any-type!] new [any-type!]] [
		;@@ protect widths, spans, heights? - not for tampering
		switch to word! word [
			cells margin spacing pinned bounds [invalidate grid]
		]
		grid/space-on-change word :old :new
	]
		
	templates/grid: make-template 'space [
		size:    none				;-- only available after `draw` because it applies styles
		margin:  5x5
		spacing: 5x5
		origin:  0x0						;-- scrolls unpinned cells (should be <= 0x0), mirror of grid-view/window/origin
		content: make map! 8				;-- XY coordinate -> space-name
		spans:   make map! 4				;-- XY coordinate -> it's XY span (not user-modifiable!!)
		;@@ all this should be in the reference docs instead
		;; widths/min used in `autofit` to ensure no column gets zero size even if it's empty
		widths:  make map! [default 100 min 10]	;-- map of column -> it's width
		;; heights/min used when heights/default = auto, in case no other constraints apply
		;; set to >0 to prevent rows of 0 size (e.g. if they have no content)
		heights: make map! [default auto min 0]	;-- height can be 'auto (row is auto sized) or integer (px)
		pinned:  0x0						;-- how many rows & columns should stay pinned (as headers), no effect if origin = 0x0
		;@@ bounds/.. = none means unlimited, but it will render scrollers useless
		;@@ and cannot be drawn without /only - will need a window over it anyway (used by grid-view)
		bounds:  [x: auto y: auto]			;-- max number of rows & cols, auto=bound `cells`, integer=fixed
											;-- 'auto will have a problem inside infinite grid with a sliding window

		hcache:  make map! 20				;-- cached heights of rows marked for autosizing ;@@ TODO: when to clear/update?
		;; "cell cache" - cached `cell` spaces: [XY name ...] and [space XY geometry ...]
		;; persistency required by the focus model: cells must retain sameness, i.e. XY -> name
		ccache:  make map!  20				;-- filled by render and height estimator
		
		;@@ TODO: margin & spacing - in style??
		;@@ TODO: alignment within cells? when cell/size <> content/size..
		;@@       and how? per-row or per-col? or per-cell? or custom func? or alignment should be provided by item wrapper?
		;@@       maybe just in lay-out-grid? or as some hacky map that can map rows/columns/cells to alignment?
		map: []

		wrap-space: function [xy [pair!] space [word!]] [	;-- wraps any cells/space into a lightweight "cell", that can be styled
			name: any [ccache/:xy  ccache/:xy: make-space/name 'cell []]
			cell: get name
			maybe/same cell/content: space				;-- prevent unnecessary invalidation
			name
		]

		cells: func [/pick xy [pair!] /size] [					;-- up to user to override
			either pick [content/:xy][calc-bounds]
		]

		into: func [xy [pair!] /force name [word! none!]] [~/into self xy name]
		
		;-- userspace functions for `spans` reading & modification
		;-- they are required to be able to get any particular cell's multi-cell without full `spans` traversal
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

		set-span: function [
			"Set the SPAN of a FIRST cell, breaking it if needed"
			cell1 [pair!] "Starting cell of a multicell or normal cell that should become a multicell"
			span  [pair!] "1x1 for normal cell, more to span multiple rows/columns"
			/force "Also break all multicells that intersect with the given area"
		][
			~/set-span self cell1 span force
		]
		
		get-offset-from: function [
			"Get pixel offset of left top corner of cell C2 from that of C1"
			c1 [pair!] c2 [pair!]
		][
			~/get-offset-from self c1 c2
		]
		
		locate-point: function [
			"Map XY point on a grid into a cell it lands on, return [cell-xy offset]"
			xy [pair!]
			/screen "Point is on rendered viewport, not on the grid"
			; return: [block!] "offset can be negative for leftmost and topmost cells"
		][
			~/locate-point self xy screen
		]

		row-height?: function [
			"Get height of row Y (only calculate if necessary)"
			y [integer!]
		][
			~/row-height? self y
		]

		col-width?: function [
			"Get width of column X"
			x [integer!]
		][
			any [widths/:x widths/default]
		]

		cell-size?: function [
			"Get the size of a cell XY or a multi-cell starting at XY (with the spaces)"
			xy [pair!]
		][
			~/cell-size? self xy
		]

		is-cell-pinned?: func [
			"Check if XY is within pinned row or column"
			xy [pair!]
		][
			not pinned +< xy
		]

		infinite?: function ["True if not all grid dimensions are finite"] [
			bounds: self/bounds							;-- call it in case it's a function
			not all [bounds/x bounds/y]
		]

		;; returns a block [x: y:] with possibly `none` (unlimited) values ;@@ REP #116 could solve this
		calc-bounds: function ["Estimate total size of the grid in cells (in case bounds set to 'auto)"] [
			~/calc-bounds self
		]
	
		calc-size: function ["Estimate total size of the grid in pixels"] [
			~/calc-size self
		]

		;; used by draw & others to avoid extra recalculations
		;; valid up to the next `draw` or `invalidate` call
		;; care should be taken so that grid can contain itself (draw has to be reentrant)
		size-cache: context [
			bounds: none
			size:   none
		]

		;; since there's absolutely no way grid can track changes in the data or spaces within itself
		;; invalidate should be used to mark those changes
		;@@ interface is messy though: global invalidate calls this and invalidate-cache
		;@@ but this doesn't call the latter... so tangled if one wants to inval only /cell
		invalidate: func [
			"Clear the internal cache of the grid to redraw it anew"
			/cell xy [pair!] "Only for a particular cell"
		][
			~/invalidate* self xy
		]


		;; does not use canvas, dictates it's own size
		draw: function [/on canvas [pair! none!] /window xy1 [none! pair!] xy2 [none! pair!]] [
			~/draw self canvas xy1 xy2
		]
	
		space-on-change: :on-change*
		#on-change-redirect
	]
]


grid-view-ctx: context [
	~: self
	
	;; gets called before grid/draw by window/draw to estimate the max window size and thus config scrollbars accordingly
	available?: function [grid [object!] axis [word!] dir [integer!] from [integer!] requested [integer!]] [	
		#debug grid-view [print ["grid/available? is called at" axis dir from requested]]	
		bounds: grid/bounds
		#assert [
			bounds "data/size is none!"
			from >= 0
			requested >= 0
		]
		r: case [
			dir < 0 [from]
			bounds/:axis [
				size: grid/calc-size					;@@ optimize calc-size?
				max 0 size/:axis - from
			]
			'infinite [requested]
		]
		#assert [r >= 0]
		r: clip [0 r] requested
		#debug grid-view [#print "avail?/(axis) (dir) = (r) of (requested)"]
		r
	]
	
	on-change: function [gview [object!] word [word! set-word!] old [any-type!] new [any-type!]] [
		switch to word! word [
			;@@ TODO: jump-length should ensure window size is bigger than viewport size + jump
			;@@ situation when jump clears a part of a viewport should never happen at runtime
			size [quietly gview/jump-length: min gview/size/x gview/size/y]
			axis [
				if :old <> :new [
					#assert [find [x y] :new]
					invalidate-cache gview
				]
			]
			origin [gview/grid/origin: new]
		]
		gview/inf-scrollable-on-change word :old :new
	]
	
	templates/grid-view: make-template 'inf-scrollable [
		content-flow: 'planar
		source: make map! [size: 0x0]					;-- map is more suitable for spreadsheets than block of blocks
		data: function [/pick xy [pair!] /size] [
			switch type?/word :source [
				block! [
					case [
						pick [:source/(xy/2)/(xy/1)]
						0 = n: length? source [0x0]
						'else [as-pair length? :source/1 n]
					]
				]
				map! [either pick [source/:xy][source/size]]
				'else [#assert [no "Unsupported data format"]]
			]
		]

		;@@ this is super slow because setting data -> font reset -> full invalidation (same probably for other values)
		;@@ need to somehow avoid invalidation while still ensuring state correctness
		wrap-data: function [item-data [any-type!]] [
			spc: make-space 'data-view [wrap?: on margin: 3x3 align: -1x0]
			set/any 'spc/data :item-data
			anonymize 'cell spc
		]

		;; cacheability requires window to be fully rendered but
		;; full window render is too slow (many seconds), can't afford it
		;; so instead, grid redraws visible part every time
		window/cache?: off
		
		window/content: 'grid
		grid: make-space 'grid [
			;; grid-view does not use ccache, but sets it for the grid
			ccache: content
			
			;; no need to wrap data-view because it's already a box/cell
			wrap-space: function [xy [pair!] space [word!]] [space]
			
			available?: function [axis [word!] dir [integer!] from [integer!] requested [integer!]] [	
				~/available? self axis dir from requested
			]
		]
		
		grid/cells: func [/pick xy [pair!] /size] [
			either pick [
				any [
					grid/content/:xy					;@@ need to think when to free this up, maybe when cells get hidden
					grid/content/:xy: wrap-data data/pick xy
				]
			][data/size]
		]
		grid/calc-bounds: grid/bounds: does [grid/cells/size]
		
		inf-scrollable-draw: :draw
		draw: function [/on canvas [pair! none!]] [
			inf-scrollable-draw/on canvas
		]
		
		inf-scrollable-on-change: :on-change*
		#on-change-redirect
	]
]


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
		weight:   0
		margin:   10x5
		rounding: 5										;-- box rounding radius in px
	]
]


;@@ this should not be generally available, as it's for the tests only - remove it!
templates/rotor: make-template 'space [
	content: none
	angle: 0

	ring: make-space 'space [size: 360x10]
	tight?: no
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
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
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
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
		maybe self/size: r1 + 10 * 2x2
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


caret-ctx: context [
	~: self
	
	on-change: function [caret [object!] word [any-word!] old [any-type!] new [any-type!]] [
		unless :old =? :new [
			switch to word! word [
				width [maybe caret/size: new by caret/size/y]	;-- rectangle invalidates itself
				visible? [invalidate-cache caret]
				offset [if caret/visible? [invalidate-cache caret]]
			]
		]
		caret/rectangle-on-change word :old :new
	]
	
	templates/caret: make-template 'rectangle [		;-- caret has to be a separate space so it can be styled
		offset:      0				;-- [0..length] should be kept even when not focused, so tabbing in leaves us where we were
		width:       1				;-- width in pixels
		look-around: 10				;-- how close caret is allowed to come to field borders
		anchor:      0.0			;-- [0..1] viewport-relative location of caret within field
		visible?:    no				;-- controlled by focus
		
		rectangle-draw: :draw
		draw: does [when visible? (rectangle-draw)]
		
		rectangle-on-change: :on-change*
		#on-change-redirect 
	]
]

;@@ TODO: can I make `frame` some kind of embedded space into where applicable? or a container? so I can change frames globally in one go (margin can also become a kind of frame)
;@@ if embedded, map composition should be a reverse of hittest: if something is drawn first then it's at the bottom of z-order
field-ctx: context [
	~: self
	
	non-ws: negate ws: charset " ^-"
		
	find-prev-word: function [field [object!] from [integer!]] [
		rev: reverse append/part clear {} field/text from
		parse rev [any ws some non-ws rev: (return from - skip? rev)]
		0
	]
	
	find-next-word: function [field [object!] from [integer!]] [
		pos: skip field/text from
		parse pos [any ws some non-ws pos: (return skip? pos)]
		length? field/text
	]
	
	;@@ TODO: limit history length!
	mark-history: function [field [object!]] [
		field/history: clear rechange field/history [copy field/text field/caret/offset]
	]
	
	;@@ TODO: group edits somehow instead of char by char saves
	undo: function [field [object!]] [
		if 4 < index? field/history [					;-- at least 2 states needed: initial and unrolled
			field/history: skip field/history -2		;-- state *after* the previous change
			set [text: offset:] skip field/history -2
			append clear field/text text
			maybe field/caret/offset: offset
		]
	]
	
	redo: function [field [object!]] [
		unless tail? field/history [
			set [text: offset:] field/history
			field/history: next next field/history
			append clear field/text text
			maybe field/caret/offset: offset
		]
	]
	
	edit: function [field [object!] plan [block!] /local n p] [
		len: length? text: field/text
		pos: skip text co: field/caret/offset
		sel: field/selected
		
		parse/case plan [any [plan:
			['undo (undo field) | 'redo (redo field)] (
				pos: skip text co: field/caret/offset
				len: length? text: field/text
			)
			
			;@@ special case may be needed for NxN selection (should it become `none`?) need more usage data
		|	'select [(n: none)
				'none (sel: none)
			|	'all  (sel: 0 by co: len)
			|	'head (n: negate co)
			|	'tail (n: len - co)
			|	'prev-word (n: (find-prev-word field co) - co)
			|	'next-word (n: (find-next-word field co) - co)
			|	'to set n integer! (n: n - co)
			|	'by set n integer!
			|	set p pair! (sel: p  co: p/1)
			] (
				if n [									;-- this only works if caret is at selection edge
					other: case [
						not sel    [co]
						co = sel/1 [sel/2]
						co = sel/2 [sel/1]
						'else      [co]					;-- shouldn't happen, but just in case
					]
					co: clip [0 len] co + n
					sel: (min co other) by (max co other)
				]
				maybe field/caret/offset: co
				maybe field/selected: sel
			)
			
		|	'copy [
				set p pair! 
			|	'selected (p: sel)
			] (if p [write-clipboard copy/part text p + 1])
			
		|	'move [
				'head (co: 0)
			|	'tail (co: len)
			|	'prev-word (co: find-prev-word field co)
			|	'next-word (co: find-next-word field co)
			|	'sel-bgn   (if sel [co: sel/1])
			|	'sel-end   (if sel [co: sel/2])
			|	'to set co integer!
			|	'by set n  integer! (co: co + n)
			] (
				pos: skip text maybe field/caret/offset: co: clip [0 len] co
				maybe field/selected: sel: none			;-- `select` should be used to keep selection
			)
			
		|	'insert [set s string!] (
				unless empty? s [
					field/caret/offset: co: skip? pos: insert pos s
					len: length? text
					mark-history field
				]
			)
			
		|	'remove [
				'prev-word (n: (find-prev-word field co) - co)
			|	'next-word (n: (find-next-word field co) - co)
			|	'selected  (n: 0  if sel [
					n: sel/2 - co: sel/1
					sel: field/selected: none
				])
			|	set n integer!
			] (
				if n < 0 [								;-- reverse negative removal
					co: co - n: abs n
					if co < 0 [n: n + co  co: 0]		;-- don't let it go past the head
				]
				n: min n len - co						;-- don't let it go past the tail
				if n <> 0 [
					maybe field/caret/offset: co
					remove/part pos: skip text co n
					len: length? text
					mark-history field
				]
			)
		|	end
		|	(ERROR "Unexpected edit command at: (mold/flat/part plan 50)")
		]]
	]
	
	adjust-origin: function [
		"Return field/origin adjusted so that caret is visible"
		field [object!]
	][
		cmargin: field/caret/look-around
		#assert [field/size]							;-- must be rendered first!
		;; layout may be invalidated by a series of keys, second key will call `adjust` with no layout
		;; also changes to text in the event handler effectively make current layout obsolete for caret-to-offset estimation
		;; field can just rebuild it since canvas is always known (infinite) ;@@ area will require different canvas..
		layout: paragraph-ctx/lay-out field/spaces/text infxinf/x
		#assert [object? layout]
		view-width: field/size/x - first (2x2 * field/margin)
		text-width: layout/extra/x
		cw: field/caret/width
		if view-width - cmargin - cw >= text-width [return 0]	;-- fully fits, no origin offset required
		co: field/caret/offset + 1
		cx: first system/words/caret-to-offset layout co
		min-org: min 0 cmargin - cx
		max-org: clip [min-org 0] view-width - cx - cw - cmargin
		clip [min-org max-org] field/origin
	]
			
	offset-to-caret: func [
		"Get caret location [0..length] closest to given OFFSET within FIELD"
		field [object!] offset [pair! integer!]
	][
		if integer? offset [offset: offset by 0]
		-1 + system/words/offset-to-caret
			field/spaces/text/layout
			offset - field/margin - (field/origin by 0)
	]

	draw: function [field [object!] canvas [none! pair!]] [
		ctext: field/spaces/text						;-- text content
		invalidate-cache/only ctext						;-- ensure text is rendered too ;@@ TODO: maybe I can avoid this?
		drawn: render/on in field/spaces 'text infxinf	;-- this sets the size
		default canvas: infxinf
		set [canvas: fill:] decode-canvas canvas
		; #assert [field/size/x = canvas/x]				;-- below algo may need review if this doesn't hold true
		cmargin: field/caret/look-around
		;; fill the provided canvas, but clip if text is larger (adds cmargin to optimal size so it doesn't jump):
		width: first either fill/x = 1 [canvas][min ctext/size + cmargin canvas]	
		maybe field/size: constrain width by ctext/size/y field/limits
		viewport: field/size - (2 * mrg: field/margin * 1x1)
		co: field/caret/offset + 1
		cxy1: caret-to-offset       ctext/layout co
		cxy2: caret-to-offset/lower ctext/layout co
		csize: field/caret/width by (cxy2/y - cxy1/y)
		unless field/caret/size = csize [
			quietly field/caret/size: csize
			invalidate-cache/only field/caret
		]
		;; draw does not adjust the origin, only event handlers do (this ensures it's only adjusted on a final canvas)
		if sel: field/selected [
			sxy1: caret-to-offset       ctext/layout sel/1 + 1
			sxy2: caret-to-offset/lower ctext/layout sel/2
			maybe field/selection/size: ssize: sxy2 - sxy1
			sdrawn: compose/only [(render in field 'selection)]
		]
		cdrawn: render in field 'caret
		#assert [ctext/layout]							;-- should be set after draw, others may rely
		ofs: field/origin by 0
		quietly field/map: compose/deep [
			(in field/spaces 'text)          [offset: (ofs) size: (ctext/size)]
			(when sel (compose/deep [					;@@ use reshape when it gets fast enough, what a mess
				(in field/spaces 'selection) [offset: (ofs + mrg + sxy1) size: (ssize)]
			]))
			(in field/spaces 'caret)         [offset: (ofs + mrg + cxy1) size: (csize)]
		]
		compose/only/deep [								;@@ can compose-map be used without re-rendering?
			clip (mrg) (field/size - mrg) [
				translate (ofs) [
					(when sel (compose [translate (mrg + sxy1) (sdrawn)]))
					translate 0x0 (drawn)
					translate (mrg + cxy1) (cdrawn)
					;@@ workaround for #4901 which draws white background under text over the selection:
					#if linux? [(when sel (compose [translate (mrg + sxy1) (sdrawn)]))]
				]
			]
		]
	]
		
	on-change: function [field [object!] word [any-word!] old [any-type!] new [any-type!]] [
		switch word: to word! word [
			origin selected [invalidate-cache field]	;-- invalidating just cache in enough since text is the same
			margin text font flags color [
				set/any 'field/spaces/text/:word :new	;-- sync these to text space; invalidated by text
				if word = 'text [
					field/caret/offset: length? new		;-- auto position at the tail
					mark-history field
				]
			]
		]
		field/space-on-change word :old :new
	]
	
	;@@ field will need on-change handler & actor support for better user friendliness!
	templates/field: make-template 'space [
		;; own facets:
		weight:   1
		origin:   0										;-- non-positive, offset(px) of text within the field
		selected: none									;-- none or pair (offsets of selection start & end)
		history:  make block! 100						;-- saved states
		map:      []

		spaces: object [
			text:      make-space 'text      [color: none]		;-- by exposing it, I simplify styling of field
			caret:     make-space 'caret     []
			selection: make-space 'rectangle []			;-- can be styled
		]
		caret:     spaces/caret							;-- shortcuts
		selection: spaces/selection
		
		;; these mirror spaces/text facets:
		margin: 0x0										;-- default = no margin
		; color:  none									;-- placeholder for user to control
		flags:  []										;-- [bold italic underline] supported ;@@ TODO: check for absence of `wrap`
		text:   spaces/text/text
		font:   spaces/text/font
		
		offset-to-caret: func [offset [pair!]] [~/offset-to-caret self offset]
		
		edit: func [
			"Apply a sequence of edits to the text"
			plan [block!]
		][
			~/edit self plan
		]
		
		draw: func [/on canvas [none! pair!]] [~/draw self canvas]
		
		space-on-change: :on-change*
		#on-change-redirect
	]
	
]

; area-ctx: context [
	; ~: self
	
	; draw: function [area [object!] canvas [pair! none!]] [
		; #assert [pair? canvas]
		; #assert [canvas +< infxinf]						;@@ whole code needs a rewrite here
		; quietly area/size: canvas
		; size: finite-canvas canvas
		; maybe area/paragraph/width: if area/wrap? [size/x]
		; maybe area/paragraph/text:  area/text
		; pdrawn: paragraph/draw								;-- no `render` to not start a new style
		; pdrawn: render/on in area 'paragraph size
		; maybe area/size: constrain max size area/paragraph/size area/limits
		; xy1: caret-to-offset       area/paragraph/layout area/caret-index + 1
		; xy2: caret-to-offset/lower area/paragraph/layout area/caret-index + 1
		; maybe area/caret/size: as-pair area/caret-width xy2/y - xy1/y
		; cdrawn: []
		; if area/active? [
			; cdrawn: compose/only [translate (xy1) (render in area 'caret)]
		; ]
		; compose [(cdrawn) clip 0x0 (area/size) (pdrawn)]		;@@ use margin? otherwise there's no space for inner frame
	; ]
		
	; watched: make hash! [text selected caret-index caret-width wrap? active?]
	; on-change: function [area [object!] word [any-word!] old [any-type!] new [any-type!]] [
		; if find watched word [area/invalidate]
		; area/scrollable-on-change word :old :new
	; ]
	
	; ;@@ TODO: only area should be scrollable
	; templates/area: make-template 'scrollable [
		; text: ""
		; selected: none		;@@ TODO
		; caret-index: 0		;-- should be kept even when not focused, so tabbing in leaves us where we were
		; caret-width: 1		;-- in px
		; limits: 60x20 .. none
		; paragraph: make-space 'paragraph []
		; caret: make-space 'rectangle []		;-- caret has to be a separate space so it can be styled
		; content: 'paragraph
		; wrap?: no           ;@@ must be a flag
		; active?: no			;-- whether it should react to keyboard input or pass thru (set on click, Enter)
		; ;@@ TODO: render caret only when focused
		; ;@@ TODO: auto scrolling when caret is outside the viewport
		; invalidate: does [				;@@ TODO: use on-deep-change to watch `text`??
			; paragraph/layout: none
			; invalidate-cache paragraph
		; ]
	
		; draw: func [/on canvas [pair! none!]] [~/draw self canvas]
		
		; scrollable-on-change: :on-change*
		; #on-change-redirect
	; ]
	
; ]

templates/fps-meter: make-template 'text [
	cache?:    off
	rate:      100
	text:      "FPS: 100.0"								;-- longest text used for initial sizing of it's host
	init-time: now/precise/utc
	frames:    make [] 400
	aggregate: 0:0:3
]

export exports
