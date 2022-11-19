Red [
	title:   "Draw-based widgets (Spaces) definitions"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires `for` loop from auxi.red, layouts.red, export, `timers/on-rate-change` to enable it
exports: [make-space declare-template space?]


space-object!: copy classy-object!

templates: #()											;-- map for extensibility

;; default on-change function to avoid replicating it in every template
invalidates: function [space [object!] word [word!] value [any-type!]] [
	#debug changes [#print "change/size of (space/type)/(word) to (mold/flat/part :value 40)"]
	invalidate space
]

invalidates-look: function [space [object!] word [word!] value [any-type!]] [
	#debug changes [#print "change/look of (space/type)/(word) to (mold/flat/part :value 40)"]
	invalidate/info space none 'look
]

templates/space: declare-class 'space [					;-- minimum basis to build upon
	type:	'space	#type [word!] =						;-- used for styling and event handler lookup, may differ from template name!
	size:   0x0		#type [pair! (0x0 +<= size)] =?		;-- none (infinite) must be allowed explicitly by templates supporting it
	parent: none	#type [object! none!]
	draw:   []   	#type [block! function!]
	;-- `drawn` is an exception and not held in the space, so just `size`
	cache:  [size]	#type [block! none!]
	cached: tail copy [0.0 #[none]]	#type [block!]		;-- used internally to check if space is connected to the tree, and holds cached facets
	limits: none	#type [object! (range? limits)  none!] =? :invalidates
	; rate: none
]

;; a trick not to enforce some facets (saves RAM) but still provide default typechecks for them:
;; (specific values are only for readability here and they have no effect)
modify-class 'space [
	map:     []		#type [block!]
	into:    none	#type [function!]
	rate:    none	#type =? :timers/on-rate-change
					[none! integer! float! time!]
					(any [rate =? none  rate >= 0])
	color:   none	#type =? :invalidates-look [tuple! none!]
	margin:  0		#type =? :invalidates [integer! pair!] (0x0 +<= (margin * 1x1))
	spacing: 0		#type =? :invalidates [integer! pair!] (0x0 +<= (spacing * 1x1))
	weight:  0		#type =? :invalidates [number!] (weight >= 0)
	origin:  0x0	#type =? :invalidates-look [pair!]
	font:    none	#type =? :invalidates [object! none!]	;-- can be set in style, as well as margin ;@@ check if it's really a font
	command: []		#type [block! paren!]
	on-invalidate: 	#type [function! none!]
]	

space?: func ["Determine of OBJ is a space! object" obj [any-type!]] [
	all [
		object? :obj
		any [
			templates/(class? obj)						;-- fast check, but will fail for e.g. list-in-list-view
			all [										;-- duck check ;@@ what words are strictly required to qualify?
				in obj 'cached							;-- starts with less common words ;@@ needs REP #102
				in obj 'cache
				in obj 'limits
				in obj 'parent
				in obj 'type
				in obj 'size
				in obj 'draw
			]
		]
	]
]

make-space: function [
	"Create a space from a template TYPE"
	type [word!]  "Looked up in templates"
	spec [block!] "Extension code"
	/block "Do not instantiate the object"
][
	base: templates/:type
	#assert [any [
		block? base
		unless base [#print "*** Non-existing template '(type)'"]
		#print "*** Template '(type)' is of type (type? base)"
	]]
	r: append copy/deep base spec
	unless block [
		;; without trapping it's impossible to tell where the error happens during creation if it's caused e.g. by on-change
		trap/catch [r: make space-object! r] [			;@@ slower than `try` by 5% on make-space 'space []
			#print "*** Unable to make space of type (type):"
			do thrown
		]
		;; replace the type if it was not enforced by the template:
		;; `class?` is used instead of `type` to force `<->` have type `stretch`
		if r/type = 'space [quietly r/type: class? r]
	]
	r
]

make-template: function [
	"Create a space template"
	base [word!]  "Type it will be based on"  
	spec [block!] "Extension code"
][
	make-space/block base spec
]

declare-template: function [
	"Declare a named class and put into space templates"
	name-base [path!] "template-name/prototype-name"
	spec      [block!]
][
	set [name: base:] name-base
	templates/:name: make-template base declare-class name-base spec
]


;-- helps having less boilerplate when `map` is straightforward
compose-map: function [
	"Build a Draw block from MAP"
	map "List of [space [offset XxY size XxY] ...]"
	/only list [block!] "Select which spaces to include"
	/window xy1 [pair!] xy2 [pair!] "Specify viewport"	;@@ it's unused; remove it?
][
	r: make [] round/ceiling/to (1.5 * length? map) 1	;-- 3 draw tokens per 2 map items
	foreach [space box] map [
		all [list  not find/same list space  continue]	;-- skip names not in the list if it's provided
		; all [limits  not boxes-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
		if zero? area? box/size [continue]				;-- don't render empty elements (also works around #4859)
		cmds: either window [
			render/window space xy1 xy2
		][	render        space
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


declare-template 'timer/space [							;-- template space for timers
	rate:  0											;-- unlike space, must always have a /rate facet
	cache: none
]		

;@@ move to auxi?
constrain-canvas: function [canvas [pair!] fill [pair!] limits [object! none!]] [
	constrain  (finite-canvas canvas) * max 0x0 fill  limits
]

;; used internally for empty spaces size estimation
set-empty-size: function [space [object!] canvas [pair!]] [
	set [canvas: fill:] decode-canvas canvas
	space/size: either positive? space/weight [
		constrain-canvas canvas fill space/limits
	][
		constrain 0x0 space/limits						;-- don't stretch what isn't supposed to stretch
	]
]

;; empty stretching space used for alignment ('<->' alias still has a class name 'stretch')
put templates '<-> declare-template 'stretch/space [	;@@ affected by #5137
	weight: 1
	cache:  none
	draw: function [/on canvas [pair!]] [
		set-empty-size self canvas
		[]
	]
]

rectangle-ctx: context [
	~: self
	
	declare-template 'rectangle/space [
		size:   20x10	#on-change :invalidates
		margin: 0
		draw:   does [compose [box (margin * 1x1) (size - margin)]]
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
		
	declare-template 'triangle/space [
		size:    16x10	#on-change :invalidates
		dir:     'n		#type =    :invalidates [word!] (find [n s w e] dir)
		margin:  0
		
		;@@ need `into` here? or triangle will be a box from the clicking perspective?
		draw: does [~/draw self]
	]
]

image-ctx: context [
	~: self
	
	draw: function [image [object!] canvas: infxinf [pair! none!]] [
		either image? image/data [
			set [canvas: fill:] decode-canvas canvas
			mrg2: 2 * mrg: image/margin * 1x1 
			limits:        image/limits
			isize:         image/data/size
			;; `constrain` isn't applicable here because doesn't preserve the ratio, and because of canvas handling
			if all [limits  limits/min  low-lim:  max 0x0 limits/min - mrg2] [	;@@ REP #113 & 122
				min-scale: max  low-lim/x / isize/x  low-lim/y / isize/y	;-- use bigger one to not let it go below low limit
			]
			if all [limits  limits/max  high-lim: max 0x0 limits/max - mrg2] [	;@@ REP #113 & 122
				max-scale: min  high-lim/x / isize/x  high-lim/y / isize/y	;-- use lower one to not let it go above high limit
			]
			if all [image/weight > 0  canvas <> infxinf] [		;-- if inf canvas, will be unscaled, otherwise uses finite dimension
				set-pair [cx: cy:] subtract-canvas canvas mrg2
				if cx = infxinf/x [cx: 1.#inf]
				if cy = infxinf/x [cy: 1.#inf]
				canvas-max-scale: min  cx / isize/x  cy / isize/y	;-- won't be bigger than the canvas
				if fill/x <= 0 [cx: 1.#inf]						;-- don't stick to dimensions it's not supposed to fill
				if fill/y <= 0 [cy: 1.#inf]  
				canvas-scale: min  cx / isize/x  cy / isize/y	;-- optimal scale to fill the chosen canvas dimensions
				canvas-scale: min canvas-scale canvas-max-scale
			]
			default min-scale:    0.0
			default max-scale:    1.#inf
			default canvas-scale: 1.0
			scale: clip canvas-scale min-scale max-scale 
			; echo [canvas fill low-lim high-lim scale min-scale max-scale lim isize]
			image/size: isize * scale + (2 * mrg)
			reduce ['image image/data mrg image/size - mrg]
		][
			image/size: 2x2 * image/margin				;@@ can't be constrained further; or call constrain again?
			[]
		]
	]

	declare-template 'image/space [
		margin: 0
		weight: 0
		data:   none	#type =? :invalidates			;-- images are not recyclable, so `none` by default
		
		draw: func [/on canvas [pair!]] [~/draw self canvas]
	]
]


cell-ctx: context [
	~: self

	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		#debug sizing [print ["cell/draw with" space/content "on" canvas]]
		unless space/content [
			set-empty-size space canvas
			return quietly space/map: []
		]
		set [canvas: fill:] decode-canvas canvas
		canvas: constrain canvas space/limits
		mrg2:   2x2 * space/margin
		cspace: space/content
		drawn:  render/on cspace encode-canvas (subtract-canvas canvas mrg2) fill
		size:   mrg2 + cspace/size
		;; canvas can be infinite or half-infinite: inf dimensions should be replaced by space/size (i.e. minimize it)
		size:   max size (finite-canvas canvas) * fill	;-- only extends along fill-enabled axes
		space/size: constrain size space/limits
		; #print "size: (size) space/size: (space/size) fill: (fill)"
		
		free:   space/size - cspace/size - mrg2
		offset: space/margin + max 0x0 free * (space/align + 1) / 2
		unless tail? drawn [
			; drawn: compose/only [translate (offset) (drawn)]
			drawn: compose/deep/only [clip 0x0 (space/size) [translate (offset) (drawn)]]
		]
		quietly space/map: compose/deep [(space/content) [offset: (offset) size: (space/size)]]
		#debug sizing [print ["box with" space/content "on" canvas "->" space/size]]
		drawn
	]
	
	allowed-alignments: make hash! [
		-1x-1 -1x0 -1x1
		 0x-1  0x0  0x1
		 1x-1  1x0  1x1
	]
	
	declare-template 'box/space [
		;; margin is useful for drawing inner frame, which otherwise would be hidden by content
		margin:  0
		weight:  1										;@@ what default weight to use? what default alignment?
		;@@ consider more high level VID-like specification of alignment
		align:   0x0	#type =? :invalidates-look (find allowed-alignments align)
		content: none	#type =? :invalidates [object! none!]
		
		map:     []
		cache:   [size map]
		
		;; draw/only can't be supported, because we'll need to translate xy1-xy2 into content space
		;; but to do that we'll have to render content fully first to get it's size and align it
		;; which defies the meaning of /only...
		;; the only way to use /only is to apply it on top of current offset, but this may be harmful
		draw: function [/on canvas [pair!]] [~/draw self canvas]
	]
	
	declare-template 'cell/box [margin: 1x1]			;-- same thing just with a border and background ;@@ margin - in style?
]

;@@ TODO: externalize all functions, make them shared rather than per-object
;@@ TODO: automatic axis inferrence from size?
scrollbar: context [
	~: self
	
	into: func [space [object!] xy [pair!] child [object! none!]] [
		any [space/axis = 'x  xy: reverse xy]
		into-map space/map xy child
	]
	
	arrange: function [content [block!]] [				;-- like list layout but simpler/faster
		map: make block! 2 * length? content
		pos: 0x0
		foreach name content [	;@@ should be map-each
			space: get name
			append map compose/deep [
				(space) [offset: (pos) size: (space/size)]
			]
			pos: space/size * 1x0 + pos
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
		
		foreach item list [invalidate/only get item]
		compose/deep [
			push [
				matrix [(select [x [1 0 0 1] y [0 1 1 0]] space/axis) 0 0]
				(compose-map space/map)
			]
		]
	]
	
	declare-template 'scrollbar/space [
		;@@ maybe leverage canvas size?
		size:       100x16	#type =? :invalidates		;-- opposite axis defines thickness
		axis:       'x		#type =  :invalidates [word!] (find [x y] axis)
		offset:     0%		#type =? :invalidates-look [number!] (all [0 <= offset offset <= 1])
		amount:     100%	#type =? :invalidates-look [number!] (all [0 <= amount amount <= 1])
		;; arrow length in percents of scroller's thickness:
		arrow-size: 90%		#type =? :invalidates-look [number!] (0 <= arrow-size) 
		
		map:         []
		cache:       [size map]
		back-arrow:  make-space 'triangle  [type: 'back-arrow  margin: 2  dir: 'w] #type (space? back-arrow)	;-- go back a step
		back-page:   make-space 'rectangle [type: 'back-page   draw: []]           #type (space? back-page)		;-- go back a page
		thumb:       make-space 'rectangle [type: 'thumb       margin: 2x1]        #type (space? thumb)			;-- draggable
		forth-page:  make-space 'rectangle [type: 'forth-page  draw: []]           #type (space? forth-page)	;-- go forth a page
		forth-arrow: make-space 'triangle  [type: 'forth-arrow margin: 2  dir: 'e] #type (space? forth-arrow)	;-- go forth a step
		
		into: func [xy [pair!] /force space [object! none!]] [~/into self xy space]
		draw: does [~/draw self]
	]
]

;@@ rename this to just `scrollable`? definitely need standardization in these context names
;; it's not `-ctx` because move-by and move-to functions are meant of outside use
scrollable-space: context [
	~: self

	set-origin: function [
		space  [object!]
		origin [pair! word!]
	][
		csize: space/content/size
		box:   min csize space/viewport					;-- if viewport > content, let origin be 0x0 always
		space/origin: clip origin box - csize 0x0
	]
	
	;@@ or /line /page /forth /back /x /y ? not without apply :(
	;@@ TODO: less awkward spec possible?
	move-by: function [
		space  [object!]
		amount [word! integer!]
		dir    [word!]
		axis   [word!]
		scale  [number! none!]
	][
		dir:  select [forth 1 back -1] dir
		unit: axis2pair axis
		default scale: either amount = 'page [0.8][1]
		switch amount [line [amount: 16] page [amount: space/size]]
		set-origin space space/origin - (amount * scale * unit * dir)
	]

	move-to: function [
		space  [object!]
		xy     [pair! word!]
		margin [integer! pair! none!]					;-- space to reserve around XY
	][
		mrg: 1x1 * any [margin 0]
		csize: select space/content 'size
		switch xy [
			head [xy: 0x0]
			tail [xy: csize * 0x1]						;-- no right answer here, csize or csize*0x1
		]
		box: space/viewport
		mrg: clip 0x0 mrg box - 1 / 2					;-- if box < 2xmargin, choose half box size as margin
		xy1: mrg - space/origin							;-- left top margin point in content's coordinates
		xy2: xy1 + box - mrg							;-- right bottom margin point
		dxy: 0x0
		foreach x [x y] [
			case [
				xy/:x < xy1/:x [dxy/:x: xy/:x - xy1/:x]
				xy/:x > xy2/:x [dxy/:x: xy/:x - xy2/:x]
			]
		]
		set-origin space space/origin - dxy
	]

	into: function [space [object!] xy [pair!] child [object! none!]] [
		if r: into-map space/map xy child [
			if r/1 =? space/content [
				r/2: r/2 - space/origin
				unless any [child  0x0 +<= r/2 +< space/content/size] [r: none]
			]
		]
		r
	]

	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		;; sizing policy (for cell, scrollable, window):
		;; - use content/size if it fits the canvas (no scrolling needed) and no fill flag is set
		;; - use canvas/size if it's less than content/size or if fill flag is set
		set [canvas: fill:] decode-canvas canvas
		if any [
			not space/content 
			zero? area? canvas
		][
			set-empty-size space canvas
			return quietly space/map: []
		]
		box: canvas: constrain canvas space/limits		;-- 'box' is viewport - area not occupied by scrollbars
		cspace: space/content
		;; render it before 'size' can be obtained, also render itself may change origin (in `roll`)!
		;; fill flag passed through as is: may be useful for 1D scrollables like list-view ?
		cdraw: render/on cspace encode-canvas box fill
		if all [
			axis: switch space/content-flow [vertical ['y] horizontal ['x]]
			cspace/size/:axis > box/:axis
		][												;-- have to add the scroller and subtract it from canvas width
			scrollers: space/vscroll/size/x by space/hscroll/size/y
			box: max 0x0 box - (scrollers * axis2pair ortho axis)	;-- valid since canvas is finite
			cdraw: render/on cspace encode-canvas box fill
		]
		csz: cspace/size
		origin: space/origin							;-- must be read after render (& possible roll)
		;; no origin clipping can be done here, otherwise it's changed during intermediate renders
		;; and makes it impossible to scroll to the bottom because of window resizes!
		;; clipping is done by /clip-origin, usually in event handlers where size & viewport are valid
		
		;; determine what scrollers to show
		loop 2 [										;-- each scrollbar affects another's visibility
			if hdraw?: box/x < csz/x [box/y: max 0 canvas/y - space/hscroll/size/y]
			if vdraw?: box/y < csz/y [box/x: max 0 canvas/x - space/vscroll/size/x]
		]
		space/hscroll/size/x: box/x * hmask: pick [1 0] hdraw?
		space/vscroll/size/y: box/y * vmask: pick [1 0] vdraw?
		
		;; size is canvas along fill=1 dimensions and min(canvas,csz+scrollers) along fill=0
		scrollers: as-pair
			space/vscroll/size/x * vmask
			space/hscroll/size/y * hmask
		sz1: min canvas csz + scrollers  sz2: canvas
		space/size: (max 0x0 sz2 - sz1) * (max 0x0 fill) + sz1
		; echo [sz1 sz2 canvas csz space/size]
		box: min box (space/size - scrollers)			;-- reduce viewport
		
		;; 'full' is viewport(box) + hidden (in all directions) part of content
		end:  max box csz + bgn: min 0x0 origin
		full: max 1x1 end - bgn
		
		;; set scrollers but avoid multiple recursive invalidation when changing srcollers fields
		;; (else may stack up to 99% of all rendering time)
		quietly space/hscroll/amount: 100% * box/x / full/x
		quietly space/hscroll/offset: 100% * (negate bgn/x) / full/x
		quietly space/vscroll/amount: 100% * box/y / full/y
		quietly space/vscroll/offset: 100% * (negate bgn/y) / full/y
		
		;@@ TODO: fast flexible tight layout func to build map? or will slow down?
		quietly space/map: compose/deep [				;@@ should be reshape (to remove scrollers) but it's too slow
			(space/content) [offset: 0x0 size: (box)]
			(space/hscroll) [offset: (box * 0x1) size: (space/hscroll/size)]
			(space/vscroll) [offset: (box * 1x0) size: (space/vscroll/size)]
			(space/scroll-timer) [offset: 0x0 size: 0x0]	;-- list it for tree correctness
		]
		space/scroll-timer/rate: either any [hdraw? vdraw?] [16][0]	;-- turns off timer when unused!
		render space/scroll-timer						;-- scroll-timer has to appear in the tree for timers
		
		; invalidate/only [hscroll vscroll]
		invalidate/only space/hscroll
		invalidate/only space/vscroll
		
		#debug grid-view [#print "origin in scrollable/draw: (origin)"]
		compose/deep/only [
			translate (origin) [						;-- special geometry for content
				clip (0x0 - origin) (box - origin)
				(cdraw)
			]
			(compose-map/only space/map reduce [space/hscroll space/vscroll])
		]
	]
		
	declare-template 'scrollable/space [
		;@@ make limits a block to save some RAM?
		; limits: 50x50 .. none		;-- in case no limits are set, let it not be invisible
		
		;; at which point `content` to place: >0 to right below, <0 to left above:
		origin:       0x0
		weight:       1
		content:      none		#type =? :invalidates [object! none!]	;-- should be defined (overwritten) by the user
		content-flow: 'planar	#type =  :invalidates [word!] (find [planar horizontal vertical] content-flow)
		
		hscroll:  make-space 'scrollbar [type: 'hscroll axis: 'x]						#type (space? hscroll)
		vscroll:  make-space 'scrollbar [type: 'vscroll axis: 'y size: reverse size]	#type (space? vscroll)
		;; timer that scrolls when user presses & holds one of the arrows
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		scroll-timer: make-space 'timer [type: 'scroll-timer]							#type (space? scroll-timer)

		map:   []
		cache: [size map]

		into: func [xy [pair!] /force child [object! none!]] [
			~/into self xy child
		]
		
		viewport: does [								;-- much better than subtracting scrollers; avoids exposing internal details
			any [all [map/2 map/2/size] 0x0]			;@@ REP #113
		] #type [function!]

		move-by: func [
			"Offset viewport by a fixed amount"
			amount [word! integer!] "'line or 'page or offset in pixels"
			dir    [word!]          "'forth or 'back"
			axis   [word!]          "'x or 'y"
			/scale factor [number!] "Default: 0.8 for page, 1 for the rest"
		][
			~/move-by self amount dir axis factor
		] #type [function!]

		move-to: function [
			"Ensure point XY of content is visible, scroll only if required"
			xy          [pair! word!]    "'head or 'tail or an offset pair"
			/margin mrg [integer! pair!] "How much space to reserve around XY (default: 0)"
		][
			~/move-to self xy mrg
		] #type [function!]
		
		clip-origin: function [
			"Change the /origin facet, ensuring no empty area is shown"
			origin [pair!] "Clipped between (viewport - scrollable/size) and 0x0"
		][
			~/set-origin self origin
		] #type [function!]
	
		draw: function [/on canvas [pair!]] [~/draw self canvas]
	]
]

paragraph-ctx: context [
	~: self
	
	size-text2: function [layout [object!]] [			;@@ it's a workaround for #4841
		size1: size-text layout
		size2: caret-to-offset/lower layout 1 + length? layout/text
		max size1 size2
	]
	
	ellipsize: function [layout [object!] text [string!] canvas [pair!]] [
		;; save existing buffer for reuse (if it's different from text)
		buffer: unless layout/text =? text [layout/text]
		len: length? text
		
		;; measuring "..." (3 dots) is unreliable
		;; because kerning between the last letter and first "." is not accounted for, resulting in random line wraps
		quietly layout/text: "...."
		ellipsis-width: first size-text layout
		
		quietly layout/text: text
		text-size: size-text layout						;@@ size-text required to renew offsets/carets because I disabled on-change in layout!
		tolerance: 1									;-- prefer insignificant clipping over ellipsization ;@@ ideally, font-dependent
		if any [										;-- need to ellipsize if:
			text-size/y - tolerance > canvas/y				;-- doesn't fit vertically (for wrapped text)
			text-size/x - tolerance > canvas/x				;-- doesn't fit horizontally (unwrapped text)
		][
			;; find out what are the extents of the last visible line:
			last-visible-char: -1 + offset-to-char layout canvas
			last-line-dy: -1 + second caret-to-offset/lower layout last-visible-char
			
			;; if last visible line is too much clipped, discard it an choose the previous line (if one exists)
			if over?: last-line-dy - tolerance > canvas/y [
				;; go 1px above line's top, but not into negative (at least 1 line should be visible even if fully clipped)
				last-line-dy: max 0 -1 + second caret-to-offset layout last-visible-char
			]
			
			;; this only works if text width is >= ellipsis, otherwise ellipsis itself gets wrapped to an invisible line
			;@@ more complex logic could account for ellipsis itself spanning 2-3 lines, but is it worth it?
			ellipsis-location: (max 0 canvas/x - ellipsis-width) by last-line-dy
			last-visible-char: -1 + offset-to-char layout ellipsis-location
			unless buffer [buffer: make string! last-visible-char + 3]		;@@ use `obtain` or rely on allocator?
			quietly layout/text: append append/part clear buffer text last-visible-char "..."
			; system/view/platform/update-view layout
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
	whitespace!: charset " ^-"								;-- wrap on tabs as well, although it's glitch-prone (sizing is hard)
	lay-out: function [space [object!] canvas [pair!] (0x0 +<= canvas) "positive!" ellipsize? [logic!] wrap? [logic!]] [
		canvas: subtract-canvas canvas mrg2: 2x2 * space/margin
		width:  canvas/x								;-- should not depend on the margin, only on text part of the canvas
		;; cache of layouts is needed to avoid changing live text object! ;@@ REP #124
		layout: new-rich-text
		; layout: any [space/layouts/:width  space/layouts/:width: new-rich-text]	@@ this creates unexplainable random glitches!
		unless empty? flags: space/flags [
			;@@ unfortunately this way 'wrap & 'ellipsize cannot precede low-level flags, or pair test fails
			flags: either pair? :flags/1 [				;-- flags may be already provided in low-level form 
				copy flags
			][
				compose [(1 by length? space/text) (space/flags)]
			]
			;; remove only after copying!
			remove find flags 'wrap						;-- leave no custom flags, otherwise rich-text throws an error
			remove find flags 'ellipsize				;-- this is way faster than `exclude`
		]
		;; every setting of layout value is slow, ~12us, while set-quiet is ~0.5us, size-text is 5+ us
		;; set width to determine height; but special case is ellipsization without wrapping: limited canvas but infinite layout
		quietly layout/font: space/font					;@@ careful: fonts are not collected by GC, may run out of them easily
		quietly layout/data: flags						;-- support of font styles - affects width
		either all [ellipsize? canvas +< infxinf] [		;-- size has to be limited from both directions for ellipsis to be present
			;; ellipsization prioritizes the canvas, so may split long words
			quietly layout/size:  max 1x1 canvas
			quietly layout/extra: ellipsize layout (as string! space/text)
				either wrap? [canvas][canvas * 1x0]		;-- without wrapping should be a single line
		][
			;; normal mode prioritizes words, so have to estimate min. width from the longest word
			quietly layout/size: infxinf
			if all [wrap? canvas/x < infxinf/x] [		;@@ perhaps this too should be a flag?
				words: append clear "" as string! space/text
				parse/case words [any [to whitespace! p: skip (change p #"^/")]]
				quietly layout/text: words
				min-width: 1x0 * size-text2 layout
				quietly layout/size: max 1x1 max canvas min-width
			]
			quietly layout/text:  as string! space/text
			; system/view/platform/update-view layout
			;; NOTE: #4783 to keep in mind
			quietly layout/extra: size-text2 layout		;-- 'size-text' is slow, has to be cached (by using on-change)
		]
		quietly space/layout: layout					;-- must return layout
	]

	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		if canvas [										;-- no point in wrapping/ellipsization on inf canvas
			ellipsize?: find space/flags 'ellipsize
			wrap?:      find space/flags 'wrap
		]
		layout:     space/layout
		|canvas|: either any [wrap? ellipsize?][
			constrain abs canvas space/limits			;-- could care less about fill flag for text
		][
			infxinf
		]
		reuse?: all [not wrap?  not ellipsize?  space/layout  space/layout/size =? canvas]	;@@ REP #113
		layout: any [
			if reuse? [space/layout]					;-- text can reuse it's layout on any canvas
			lay-out space |canvas| to logic! ellipsize? to logic! wrap?
		]

		;; size can be adjusted in various ways:
		;;  - if rendered < canvas, we can report either canvas or rendered
		;;  - if rendered > canvas, the same
		;; it's tempting to use canvas width and rendered height,
		;; but if canvas is huge e.g. 2e9, then it's not so useful,
		;; so just the rendered size is reported
		;; and one has to wrap it into a data-view space to stretch
		mrg2: space/margin * 2x2
		text-size: max 0x0 (constrain layout/extra + mrg2 space/limits) - mrg2	;-- don't make it narrower than min limit
		space/size: mrg2 + text-size					;@@ full size, regardless if canvas height is smaller?
		#debug sizing [#print "paragraph=(space/text) on (canvas) -> (space/size)"]
		
		;; this is quite hacky: rich-text is embedded directly into draw block
		;; so when layout/text is changed, we don't need to call `draw`
		;; just reassigning host's `draw` block to itself is enough to update it
		;; (and we can't stop it from updating)
		;; direct changes to /text get reflected into /layout automatically long as it scales
		;; however we wish to keep size up to date with text content, which requires a `draw` call
		compose [text (1x1 * space/margin) (layout)]
	]
	
 	declare-template 'text/space [
		text:   ""		#type    :invalidates [any-string!]	;-- every assignment counts as space doesn't know if string itself changed
		flags:  []		#type    :invalidates [block!]	;-- [bold italic underline wrap] supported ;@@ typecheck that all flags are words
		;; NOTE: every `make font!` brings View closer to it's demise, so it has to use a shared font
		;; styles may override `/font` with another font created in advance 
		font:   none									;-- can be set in style, as well as margin
		color:  none									;-- placeholder for user to control
		margin: 0
		weight: 0										;-- no point in stretching single-line text as it won't change

		layout: none	#type [object! none!]			;-- last rendered layout, text size is kept in layout/extra
		quietly cache:  [size layout]
		quietly draw: func [/on canvas [pair!]] [~/draw self canvas]
	]

	;; unlike paragraph, text is never wrapped
	declare-template 'paragraph/text [
		quietly weight: 0								;-- used by tube, should trigger a re-render
		quietly flags:  [wrap]
	]

	;; url is underlined in style; is a paragraph for it's often long and needs to be wrapped
	declare-template 'link/paragraph [
		quietly flags: [wrap underline]
		quietly color: 50.80.255						;@@ color should be taken from the OS theme
		command: [browse as url! text]					;-- can't use 'quietly' or no set-word = no facet
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
		
		drawn: make [] len * 6
		items: make [] len
		repeat i len [append items cont/items/pick i]	;@@ use map-each
		set [size: map: origin:] make-layout type items settings
		default origin: 0x0
		foreach [_ geom] map [
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
		cont/size: constrain size cont/limits			;@@ is this ok or layout needs to know the limits?
		cont/origin: origin
		compose/only [translate (negate origin) (drawn)]
	]

	declare-template 'container/space [
		origin:  0x0									;-- used by ring layout to center itself around the pointer
		content: []		#type :invalidates				;-- no type check as user may redefine it and /items freely
		
		items: function [/pick i [integer!] /size] [
			either pick [content/:i][length? content]
		] #type :invalidates [function!]
		
		map:   []
		cache: [size map]
		into: func [xy [pair!] /force child [object! none!]] [
			into-map map xy + origin child
		]

		draw: function [
			; /on canvas [pair! none!]					;-- not used: layout gets it in settings instead
			/layout type [word!] settings [block!]
		][
			#assert [layout "container/draw requires layout to be provided"]
			~/draw self type settings; xy1 xy2
		]
	]
]

;@@ `list` is too common a name - easily get overridden and bugs ahoy
;@@ need to stash all these contexts somewhere for external access
list-ctx: context [
	~: self
		
	declare-template 'list/container [
		size:    0x0	#type [pair! (0x0 +<= size) none!]		;-- 'none' to allow infinite lists
		axis:    'x		#type =  :invalidates [word!] (find [x y] axis)
		;; default spacing/margins must be tight, otherwise they accumulate pretty fast in higher level widgets
		margin:  0
		spacing: 0
		;@@ TODO: alignment?

		container-draw: :draw	#type [function!]
		draw: function [/on canvas [pair!]] [
			settings: [axis margin spacing canvas limits]
			container-draw/layout 'list settings
		]
	]
]

ring-ctx: context [
	~: self
	
	declare-template 'ring/container [
		;; in degrees - clockwise direction to the 1st item (0 = right, aligns with math convention on XY space)
		angle:  0	#type =? :invalidates-look [integer! float!]
		;; minimum distance (pixels) from the center to the nearest point of arranged items
		radius: 50	#type =? :invalidates [integer! float!]
		;; whether items should be considered round, not rectangular
		round?: no	#type =? :invalidates [logic!]

		container-draw: :draw	#type [function!]
		draw: does [container-draw/layout 'ring [angle radius round?]]
	]
]


icon-ctx: context [
	~: self
		
	declare-template 'icon/list [
		axis:   'y
		margin: 0
		
		;@@ TODO: image should be also aligned by a box, when icon fills the canvas
		;@@ or set icon weight to 0 and don't let list stretch zero-weight spaces
		spaces: context [
			image: make-space 'image []
			text:  make-space 'paragraph []
			box:   make-space 'box [content: text]		;-- used to align paragraph
			set 'content reduce [image box]
		] #type [object!]
		
		;; exposed inner facets for easier access
		image:  none	#on-change [space word value] [space/spaces/image/data: value]
		text:   ""		#on-change [space word value] [space/spaces/text/text:  value]
	]
]



tube-ctx: context [
	~: self

	declare-template 'tube/container [
		margin:  0
		spacing: 0
		align:   -1x-1	#type =? :invalidates-look
		axes:    [e s]	#type :invalidates [block!]
						(find/only [					;-- literal listing allows it to appear in the error output
							[n e] [n w]  [s e] [s w]  [e n] [e s]  [w n] [w s]
							[→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←]
						] axes)
		
		container-draw: :draw	#type [function!]
		draw: function [/on canvas [pair!]] [
			settings: [margin spacing align axes canvas limits]
			drawn: container-draw/layout 'tube settings
			#debug sizing [#print "tube with (content/type) on (mold canvas) -> (size)"]
			drawn
		]
	]
]


context [
	~: self

	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		settings: with space [margin spacing align canvas limits breakpoints]
		set [size: map: rows:] make-layout 'paragraph :space/items settings
		quietly space/size: constrain size space/limits	;-- size may be bigger than limits if content doesn't fit
		quietly space/rows: rows
		quietly space/map:  map
		
		count: space/items/size
		#assert [count]
		
		;; I clip every row separately from the hanging out parts,
		;; as wrapping margin doesn't have to align with total width
		;; e.g. row may be visibly smaller than canvas but contain "hidden" parts duped on another row
		scaled-row: [
			translate (row-offset * 0x1 + mrg) [
				scale (size/x / used) 1.0				;-- can be both zooming in and out (<1 or >1)
				translate (clip-start * -1x0)
				clip 0x0 (clip-end) (copy row-drawn)
			]
		]
		normal-row: [
			translate (row-offset + mrg) [
				clip (clip-start) (clip-end) (copy row-drawn)
			]
		]
		
		mrg:   space/margin * 1x1
		drawn: make [] (length? rows) / 4 * 3
		foreach [row-offset clip-start clip-end row] rows [
			row-drawn: clear []
			foreach [item item-offset item-drawn] row [
				compose/only/into [
					translate (item-offset) (item-drawn)
				] tail row-drawn
			]
			fill?: all [
				space/align = 'fill
				0 < used: clip-end/x - clip-start/x
				not row =? last rows					;-- don't stretch the last row! ;@@ though it should be optional
			]
			blueprint: either fill? [scaled-row][normal-row]
			compose/deep/only/into blueprint tail drawn
		]
		; space/origin: origin							;-- unused
		compose/only [clip (mrg) (size - mrg) (drawn)]	;-- clip the hanging out parts
	]
	
	;; /into required because /map cannot contain duplicates, but /rows can; plus this considers scaling
	into: func [space [object!] xy [pair!] child [object! none!]] [
		xy: xy - space/margin							;@@ margin may get out of sync with frame data
		mrg2: space/margin along 'x * 2
		scaled-xy: [										;-- correct xy/x for scaling if it's applied
			either all [
				space/align = 'fill						;@@ this should be held in /rows, or may get out of sync with the layout
				not row =? last space/rows
			][
				scale: clip-end/x - clip-start/x / max 1 (space/size/x - mrg2) 
				(round/to xy/x * scale 1) by xy/y 
			][
				xy
			]
		]
		either child [
			foreach [row-offset clip-start clip-end row] space/rows [
				if child-offset: select/skip/same row child 3 [	;-- relies on [space offset drawn] row layout
					return reduce [child (do scaled-xy) - row-offset - child-offset]
				]
			]
		][
			foreach [row-offset clip-start clip-end row] space/rows [
				row-xy: (do scaled-xy) - row-offset
				if clip-start +<= row-xy +< clip-end [
					foreach [child child-offset _] row [
						child-xy: row-xy - child-offset
						if 0x0 +<= child-xy +< child/size [
							return reduce [child child-xy]
						]
					]
					break
				]
			]
		]
		none
	]
		
	declare-template 'rich-paragraph/container [		;-- used as a base for higher level rich-content
		margin:      0
		spacing:     0
		align:       'left	#type = [word!] :invalidates-look
		breakpoints: []		#type  [block!] :invalidates
		
		rows:        []		#type  [block!]				;-- internal frame data used by /into
		cache:       [size map rows]
		into: func [xy [pair!] /force child [object! none!]] [~/into self xy child]
		
		;; container-draw is not used due to tricky geometry
		draw: function [/on canvas [pair!]] [~/draw self canvas]
	]
]


context [
	~: self
	
	;@@ will need source editing facilities too
	
	on-source-change: function [space [object!] word [word!] value [any-type!] /local attr char string] [
		if unset? :space/ranges [exit]					;-- not initialized yet
		clear ranges:  space/ranges
		clear content: space/content
		; bold: italic: underline: strike: none
		buffer: clear ""
		offset: 0										;-- using offset, not indexes, I avoid applying just opened (empty) ranges
		start: clear #()								;-- offset of each attr's opening
		get-range-blueprint: [
			switch attr [
				bold italic underline strike [[pair attr]]
				color size font command [[pair get attr]]
				backdrop [[pair 'backdrop get attr]]
			]
		]
		flush: [
			if 0 < text-len: length? buffer [
				text-ofs: offset - text-len				;-- offset of the buffer
				command:  none
				flags: parse ranges [collect any [		;-- add closed ranges if they intersect with text
					set range pair! if (range/2 > text-ofs)		;-- nonzero intersection found
					not [set command block!]					;-- command is RTD dialect extension
					keep (max 1 range - text-ofs) keep to [pair! | end]
				|	to pair!
				]]
				foreach [attr-ofs attr] start [			;-- add all open ranges
					if attr-ofs >= offset [continue]	;-- empty range yet, shouldn't apply
					either attr = 'command [
						command: get attr
					][
						pair: as-pair (max 1 1 + attr-ofs - text-ofs) len
						value: get attr
						repend flags do get-range-blueprint
					]
				]
				
				;@@ whether to commit whole buffer or split it into many spaces by words - I'm undecided
				;@@ less spaces = faster, but if single space spans all the lines it's many extra renders
				;@@ only benchmark can tell when splitting should occur
				append content obj: make-space either command ['link]['text] []
				quietly obj/text:  copy buffer
				quietly obj/flags: flags
				if command [quietly obj/command: command]
				clear buffer
			]
		]
		commit-attr: [
			attr: to word! attr
			if start/:attr [
				pair: as-pair  1 + any [start/:attr attr]  offset
				if pair/2 > pair/1 [repend ranges do get-range-blueprint]
			]
		]
		=open-attr=:  [(do commit-attr  start/:attr: offset)]
		=close-attr=: [(do commit-attr  start/:attr: none)]
		
		parse/case space/source [any [
			ahead word! set attr ['bold | 'italic | 'underline | 'strike] (
				unless start/:attr [start/:attr: offset]
			)
		|	ahead refinement! set attr [
				/bold | /italic | /underline | /strike
			|	/color | /backdrop | /size | /font | /command
			] =close-attr=
		|	ahead set-word! [
				set attr quote color:    =open-attr= [
					set color word! (color: get color #assert [tuple? color])
				|	set color #expect tuple!
				]
			|	set attr quote backdrop: =open-attr= [
					set backdrop word! (backdrop: get backdrop #assert [tuple? backdrop])
				|	set backdrop #expect tuple!
				]
			|	set attr quote size:     =open-attr= set size    #expect integer!
			|	set attr quote font:     =open-attr= set font    #expect string!
			|	set attr quote command:  =open-attr= set command #expect block!
			]
		|	set string string! (
				append buffer string
				offset: offset + length? string
			)
		|	set char char! (
				append buffer char
				offset: offset + 1
			)
		; |	paren! reserved
		; |	block! TODO grouping
		|	set obj2 object! (
				do flush
				#assert [space? obj2]
				append content obj2
				offset: offset + 1
			)
		|	end | p: (ERROR "Unexpected (type? :p/1) value at: (mold/part/flat p 40)")
		] end]
		do flush										;-- commit last string
		
		invalidate space
	]
	
	space!: charset " ^-"
	
	;; custom draw fills /breakpoints, which requires preliminary content rendering
	;; so it's done inside draw to avoid out of tree renders
	;; however ranges and breakpoints do not depend on canvas, so no need put them into cache
	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		breaks: clear space/breakpoints
		
		;@@ keep stripe in sync with paragraph layout, or find another way to avoid double rendering:
		set [canvas': fill:] decode-canvas canvas
		ccanvas: subtract-canvas constrain canvas' space/limits 2x2 * space/margin
		stripe:  encode-canvas infxinf/x by ccanvas/y -1x-1
		
		vec: clear []
		foreach item space/content [
			;; this way I won't be able to distinguish produced text spaces from those coming from /source
			;; but then, maybe it's fine to have them all breakable...
			entry: none
			if all [
				find [link text] item/type
				not empty? item/text
			][
				render/on item stripe					;-- produces /layout to measure text on
				h1: second size-text item/layout
				h2: second caret-to-offset/lower item/layout 1
				if h1 = h2 [							;-- avoid breakpoints if text has multiple lines
					pos: item/text
					unless find space! pos/1 [append vec 0]
					while [pos: find/tail pos space!] [
						index: -1 + index? pos
						left:  first caret-to-offset       item/layout index
						right: first caret-to-offset/lower item/layout index
						repend vec [left '- right]
					]
					unless find space! last item/text [
						append vec first caret-to-offset/lower item/layout 1 + length? item/text
					]
					if 2 < length? vec [entry: copy vec]
					clear vec
				]
			]
			append/only breaks entry
		]
		space/rich-paragraph-draw/on canvas
	]
	
	declare-template 'rich-content/rich-paragraph [
		;; data flow: source -> breakpoints & (content -> items) -> make-layout
		source: []	#type [block!] :on-source-change	;-- holds high-level dialected data
		ranges: []	#type [block!]						;-- internal attribute range data
		
		rich-paragraph-draw: :draw	#type [function!]
		draw: func [/on canvas [pair!]] [~/draw self canvas]
	]
]


switch-ctx: context [
	~: self
	
	declare-template 'switch/space [
		state: off		#type =? :invalidates-look [logic!]
		; command: []
		data: make-space 'data-view []	#type (space? data)		;-- general viewer to be able to use text/images
		draw: func [/on canvas [pair!]] [
			also data/draw/on canvas					;-- draw avoids extra 'data-view' style in the tree
			size: data/size
		]
	]
	
	declare-template 'logic/switch []					;-- uses different style
]


label-ctx: context [
	~: self
	
	on-image-change: function [label [object!] word [word!] value [any-type!]] [
		spaces: label/spaces
		spaces/image-box/content: case [				;-- invalidated by cell
			image? label/image [
				spaces/image/data: label/image
				spaces/image
			]
			string? label/image [
				spaces/sigil/text: label/image
				spaces/sigil
			]
			char? label/image [
				spaces/sigil/text: form label/image
				spaces/sigil
			]
			'else [none]
		]
	]

	on-text-change: function [label [object!] word [word!] value [any-type!]] [
		spaces: label/spaces
		type: either newline: find label/text #"^/" [
			spaces/text/text: copy/part label/text newline
			spaces/comment/text: copy next newline
			'comment
		][
			spaces/text/text: label/text
			'text
		]
		spaces/body/content: reduce spaces/lists/:type			;-- invalidated by container
	]
	
	on-flags-change: function [label [object!] word [word!] value [any-type!]] [
		spaces: label/spaces
		label/spaces/text/flags: label/spaces/comment/flags: label/flags
	]
	
	declare-template 'label/list [
		axis:    'x
		margin:  0x0
		spacing: 5x0
		
		spaces: object [								;-- all lower level spaces used by label
			image:      make-space 'image []
			sigil:      make-space 'text [limits: 20 .. none]	;-- 20 is for alignment of labels under each other ;@@ should be set in style?
			image-box:  make-space 'box  [content: none]		;-- needed for centering the image/sigil
			text:       make-space 'text []						;-- 1st line of text
			comment:    make-space 'text []						;-- lines after the 1st
			body:       make-space 'list [margin: 0x0 spacing: 0x0 axis: 'y  content: reduce [text comment]]
			text-box:   make-space 'box  [content: body]		;-- needed for text centering
			lists: [text: [text] comment: [text comment]]		;-- used to avoid extra bind in on-change
			set 'content reduce [image-box text-box]
		]

		image: none		#type :on-image-change [image! string! char! none!]
		text:  ""		#type :on-text-change  [any-string!]
		flags: []		#type :on-flags-change [block!]			;-- transferred to text and comment
	]
]



;; a polymorphic style: given `data` creates a visual representation of it
;; `content` can be used directly to put a space into it (useful in clickable, button)
data-view-ctx: context [
	~: self

	push-font: function [space [object!]] [
		if space/content [
			if all [in space/content 'font  not space/content/font =? space/font] [
				space/content/font: space/font					;-- should trigger invalidation
			]
		]
	]
	
	reset-content: function [space [object!]] [
		space/content: VID/wrap-value :space/data space/wrap?	;@@ maybe reuse the old space if it's available?
		push-font space									;-- push current font into newly created content space
	]
	
	declare-template 'data-view/box [					;-- inherit margin, content, map from the box
		align:        -1x-1								;-- left-top aligned by default; on-change inherited from box
		
		;@@ not used currently, maybe it should be
		; #on-change [space word value] [
			; if all [block? :space/data] ...
		; ]
		; #type =?   spacing: 5x5			;-- used only when data is a block
		
		;; font can be set in style, unfortunately required here to override font of rich-text face
		;; (because font for rich-text layout cannot be set with a draw command - we need to measure size)
		font: none	#on-change [space word value] [push-font space]
		
		wrap?: off	#type =? [logic!]							;-- controls choice between text (off) and paragraph (on)
		#on-change [space word value] [
			if :space/data = either value ['text]['paragraph] [	;-- switches from text to paragraph and back
				reset-content space
			] 
		] 
		
		data: none	#on-change [space word value [any-type!]] [reset-content space]		;-- ANY red value
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
		cspace: space/content
		either function? cavail?: select cspace 'available? [	;-- use content/available? when defined
			cavail? axis dir from requested
		][														;-- otherwise deduce from content/size
			csize: any [cspace/size infxinf]
			clip 0 requested (either dir < 0 [from][csize/:axis - from])
		]
	]

	;; window always has to render content on it's whole size,
	;; otherwise how does it know how big it really is
	;; (considering content can be smaller and window has to follow it)
	;; but only xy1-xy2 has to appear in the render result block and map!
	;; area outside of canvas and within xy1-xy2 may stay not rendered as long as it's size is guaranteed
	draw: function [window [object!] canvas: infxinf [pair! none!]] [
		#debug grid-view [#print "window/draw is called on canvas=(canvas)"]
		unless content: window/content [
			set-empty-size window canvas
			return quietly window/map: []
		]
		#assert [space? content]
		-org: negate org: window/origin
		;; there's no size for infinite spaces so pages*canvas is used as drawing area
		;; no constraining by /limits here, since window is not supposed to be limited ;@@ should it be constrained?
		set [canvas': fill:] decode-canvas canvas
		size: window/pages * finite-canvas canvas'
		unless zero? area? size [						;-- optimization ;@@ although this breaks the tree, but not critical?
			cdraw: render/window/on content -org -org + size canvas
			;; once content is rendered, it's size is known and may be less than requested,
			;; in which case window should be contracted too, else we'll be scrolling over an empty window area
			if content/size [size: min size content/size - org]	;-- size has to be finite
		]
		window/size: size
		#debug sizing [#print "window resized to (window/size)"]
		;; let right bottom corner on the map also align with window size
		quietly window/map: compose/deep [(content) [offset: (org) size: (size)]]
		either cdraw [ compose/only [translate (org) (cdraw)] ][ []]
	]
	
	declare-template 'window/space [
		;; window size multiplier in canvas sizes (= size of inf-scrollable)
		;; when drawn, auto adjusts it's `size` up to `canvas * pages` (otherwise scrollbars will always be visible)
		pages:   10x10	#type =? :invalidates [pair! integer! float!]
		origin:  0x0									;-- content's offset (negative)
		
		;; window does not require content's size, so content can be an infinite space!
		content: none	#type =? :invalidates [object! none!]
		
		map:     []
		cache:   [size map]
		
		available?: func [
			"Returns number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
			axis      [word!]    "x/y"
			dir       [integer!] "-1/1"
			from      [integer!] "axis coordinate to look ahead from"
			requested [integer!] "max look-ahead required"
		][
			~/available? self axis dir from requested
		] #type [function!]
	
		draw: func [/on canvas [pair!]] [~/draw self canvas]
	]
]

inf-scrollable-ctx: context [
	~: self
	
	;; must be called from within render so `available?`-triggered renders belong to the tree and are styled correctly
	roll: function [space [object!] path [path!] "inf-scrollable should be the last item"] [
		#debug grid-view [#print "origin in inf-scrollable/roll: (space/origin)"]
		window: space/window
		unless find/same/only space/map window [exit]	;-- likely window was optimized out due to empty canvas 
		wofs': wofs: negate window/origin				;-- (positive) offset of window within it's content
		#assert [window/size]
		wsize:  window/size
		before: negate space/origin						;-- area before the current viewport offset
		#assert [find/same space/map window]			;-- roll attempt on an empty viewport, or map is invalid?
		viewport: space/viewport
		#assert [0x0 +< viewport]						;-- roll on empty viewport is most likely an unwanted roll
		if zero? area? viewport [return no]
		after:  wsize - (before + viewport)				;-- area from the end of viewport to the end of window
		path: rejoin [path space/window window/content] 
		with-style path [								;-- spoof rendered path, needed for /available?'s inner renders
			foreach x [x y] [
				any [									;-- prioritizes left/up jump over right/down
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
		]
		;; transfer offset from scrollable into window, in a way detectable by on-change
		if wofs' <> wofs [
			;; effectively viewport stays in place, while underlying window location shifts
			#debug sizing [#print "rolling (space/size) with (space/content) by (wofs' - wofs)"]
			space/origin: space/origin + (wofs' - wofs)	;-- may be watched (e.g. by grid-view)
			window/origin: negate wofs'					;-- invalidates both scrollable and window
		]
	]
	
	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		#debug sizing [#print "inf-scrollable draw is called on (canvas)"]
		timer: space/roll-timer
		render timer									;-- timer has to appear in the tree for timers to work
		drawn: space/scrollable-draw/on canvas
		any-scrollers?: not zero? add area? space/hscroll/size area? space/vscroll/size
		timer/rate: either any-scrollers? [4][0]		;-- timer is turned off when unused
		;; scrollable/draw removes roll-timer, have to restore
		;; the only benefit of this is to count spaces more accurately:
		;; (can't use repend, as map may be a static block)
		quietly space/map: compose [
			(space/map)
			(timer) [offset 0x0 size 0x0]
		]
		#debug sizing [#print "inf-scrollable with (space/content/type) on (mold canvas) -> (space/size) window: (space/window/size)"]
		#assert [any [not find/same space/map space/window  space/window/size]  "window should have a finite size if it's exposed"]
		drawn
	]
	
	declare-template 'inf-scrollable/scrollable [		;-- `infinite-scrollable` is too long for a name
		jump-length: 200	#type [integer!] (jump-length > 0)	;-- how much more to show when rolling (px) ;@@ maybe make it a pair?
		look-around: 50		#type [integer!] (look-around > 0)	;-- zone after head and before tail that triggers roll-edge (px)

		content: window: make-space 'window []	#type (space? window)

		;; timer that calls `roll` when dragging
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		roll-timer: make-space 'timer [type: 'roll-timer]	#type (space? roll-timer)
		roll: function [/in path: (as path! []) [path!] "Inject subpath into current styling path"] [
			~/roll self path
		] #type [function!]

		scrollable-draw: :draw	#type [function!]
		draw: function [/on canvas [pair!]] [~/draw self canvas]
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
		canvas [pair!]    "Canvas on which it is rendered; positive!" (0x0 +<= canvas)	;-- other funcs must pass positive canvas here
		level  [integer!] "Offset in pixels from the 0 of main axis"
	][
		#assert [list =? last current-path  "Out of tree rendering detected!"]
		x: list/axis
		if level < mrgx: list/margin along 'x [return compose [margin 1 (level)]]
		#debug list-view [level0: level]				;-- for later output
		canvas: encode-canvas canvas make-pair [1x1 x -1]	;-- list items will be filled along secondary axis
		
		; either empty? list/map [
			i: 1
			level: level - mrgx
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
			obj: list/items/pick i
			;; presence of call to `render` here is a tough call
			;; existing previous size is always preferred here, esp. useful for non-cached items
			;; but `locate-line` is used by `available?` which is in turn called:
			;; - when determining initial window extent (from content size)
			;; - every time window gets scrolled closer to it's borders (where we have to render out-of-window items)
			;; so there's no easy way around requiring render here, but for canvas previous window size can be used
			;@@ ensure at least that this is an in-tree render
			render/on obj canvas
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

	item-length?: function [list [object!] i [integer!] (i > 0)] [
		#assert [list/icache/:i]
		item: list/icache/:i							;-- must be cached by previous locate-line call
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
		sp: list/spacing along list/axis
		mg: list/margin  along list/axis
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
	
	available?: function [
		list [object!] canvas [pair!] (0x0 +<= canvas) "positive!" axis [word!] dir [integer!] from [integer!] requested [integer!]
	][
		if axis <> list/axis [
			;; along secondary axis there is no absolute width: no way to know some distant unrendered item's width
			;; so just previously rendered width is used (and will vary as list is rolled, if some items are bigger than canvas)
			#assert [list/size]
			return either dir < 0 [from][min requested list/size/:axis - from]
		]
		set [item: idx: ofs:] locate-line list canvas from + (requested * dir)
		r: max 0 requested - switch item [
			space item [0]
			margin [either idx = 1 [0 - ofs][ofs - (list/margin along axis)]]
		]
		#debug list-view [#print "available? dir=(dir) from=(from) req=(requested) -> (r)"]
		r
	]
			
	;; container/draw only supports finite number of `items`, infinite needs special handling
	;; it's also too general, while this `draw` can be optimized better
	list-draw: function [lview [object!] canvas [pair!] "Always finite" xy1 [pair!] xy2 [pair!]] [
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
			list/size: list/margin * 2x2
			return quietly list/map: []
		]
		#assert [i1 <= i2]

		canvas:   extend-canvas canvas axis				;-- infinity will compress items along the main axis
		guide:    axis2pair axis
		origin:   guide * (xy1 - o1 - list/margin)
		settings: with [list 'local] [axis margin spacing canvas origin limits]
		set [new-size: new-map:] make-layout 'list :list-picker settings
		;@@ make compose-map generate rendered output? or another wrapper
		;@@ will have to provide canvas directly to it, or use it from geom/size
		drawn: make [] 3 * (length? new-map) / 2
		foreach [_ geom] new-map [
			#assert [geom/drawn]						;@@ should never happen?
			if drw: geom/drawn [						;-- invisible items don't get re-rendered
				remove/part find geom 'drawn 2			;-- no reason to hold `drawn` in the map anymore
				compose/only/into [translate (geom/offset) (drw)] tail drawn
			]
		]
		list/size: new-size
		quietly list/map: new-map
		drawn
	]

	;; hack to avoid recreation of this func inside list-draw
	list-picker: func [/size /pick i] with :list-draw [
		either size [i2 - i1 + 1][list/items/pick i + i1 - 1]
	]
		
	;; new class needed to type icache & available facets
	;; externalized, otherwise will recreate the class on every new list-view
	list-template: declare-class/manual 'list-in-list-view/list [
		axis: 'y
		
		;; cache of last rendered item spaces (as words)
		;; this persistency is required by the focus model: items must retain sameness
		;; an int->word map! - for flexibility in caching strategies (which items to free and when)
		;@@ when to forget these? and why not keep only focused item?
		icache: make map! 16	#type [map!]
		
		available?: function [axis [word!] dir [integer!] from [integer!] requested [integer!]] [
			;; must pass positive canvas (uses last rendered list-view size)
			~/available? self size axis dir from requested
		] #type [function!]

		classify-object self 'list-in-list-view			;-- on-change is not primed until /list-view is set
	]

	declare-template 'list-view/inf-scrollable [
		; reversed?: no		;@@ TODO - for chat log, map auto reverse
		; size:   none									;-- avoids extra triggers in on-change
		pages:  10
		source: []	#on-change :invalidates				;-- no type check for it can be freely overridden
		data: function [/pick i [integer!] /size] [		;-- can be overridden
			either pick [source/:i][length? source]		;-- /size may return `none` for infinite data
		] #type [function!]
		
		wrap-data: function [item-data [any-type!]][	;-- can be overridden (but with care)
			spc: make-space 'data-view [
				quietly type:  'item
				quietly wrap?:  on
			]
			set/any 'spc/data :item-data
			spc
		] #type [function!]

		window/content: list: make-space 'list list-template	#type (space? list)
		content-flow: does [
			select [x horizontal y vertical] list/axis
		] #type [function!]
		
		list/items: function [/pick i [integer!] /size] with list [
			either pick [
				any [
					icache/:i
					icache/:i: wrap-data data/pick i
				]
			][data/size]
		]
		
		list/draw: function [/window xy1 [pair!] xy2 [pair!] /on canvas [pair!]] [
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
	
	into: func [grid [object!] xy [pair!] cell [object! none!]] [	;-- faster than generic map-based into
		if cell [return into-map grid/map xy cell]		;-- let into-map handle it ;@@ slow! need a better solution!
		set [cell: offset:] locate-point grid xy yes
		mcell: grid/get-first-cell cell
		if cell <> mcell [
			offset: offset + grid/get-offset-from mcell cell	;-- pixels from multicell to this cell
		]
		all [
			mcspace: grid/frame/cells/:mcell
			reduce [mcspace offset]
		]
	]
	
	calc-bounds: function [grid [object!]] [
		if lim: grid/frame/bounds [return lim]			;-- already calculated
		bounds: grid/bounds								;-- call it in case it's a function
		unless any ['auto = bounds/x  'auto = bounds/y] [	;-- no auto limit set (but can be none)
			#debug grid-view [#print "grid/calc-bounds [no auto] -> (bounds)"]
			return grid/frame/bounds: bounds
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
		grid/frame/bounds: lim
		lim
	]

	break-cell: function [cell1 [pair!]] [				;-- `cell1` must be the starting cell
		if 1x1 <> span: grid/get-span cell1 [
			#assert [1x1 +<= span]						;-- ensure it's a first cell of multicell
			xyloop xy span [							;@@ should be for-each
				remove/key grid/spans xy': cell1 + xy - 1x1
				invalidate-xy grid xy' 
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
			xy': cell1 + xy - 1x1
			#assert [1x1 = grid/get-span xy']
			grid/spans/:xy': 1x1 - xy					;-- each span points to the first cell
			invalidate-xy grid xy' 
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
			x1: min c1/:x c2/:x
			x2: max c1/:x c2/:x
			if x1 = x2 [continue]
			wh?: get/any wh?							;@@ workaround for #4988
			for xi: x1 x2 - 1 [r/:x: r/:x + wh? xi]		;@@ should be sum map
			r/:x: r/:x + (x2 - x1 * (grid/spacing along x))
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
		mg: grid/margin along axis
		if level < mg [return reduce ['margin 1 level]]		;-- within the first margin case
		level: level - mg

		bounds: grid/calc-bounds
		sp:     grid/spacing along axis
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
				space [ofs: ofs - (grid/spacing along x)  idx: idx + 1]
				margin [
					either idx = 1 [
						ofs: ofs - (grid/margin along x)
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
			r: any [grid/frame/heights/:y  grid/frame/heights/:y: calc-row-height grid y]
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
				set-quiet 'rendered-xy cell1			;@@ temporary kludge until apply!
				render/on grid/wrap-space cell1 content canvas	;-- render to get the size
				height1: content/size/y
			]
			case [
				span/y = 1 [
					#assert [0 < span/x]
					append hmin height1
				]
				span/y + y = cell1/y [					;-- multi-cell vertically ends after this row
					for y2: cell1/y y - 1 [
						height1: height1 - (grid/spacing along 'y) - grid/row-height? y2
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
		r + (xspan - 1 * (grid/spacing along 'x))
	]
		
	cell-height?: function [grid [object!] xy [pair!]] [
		#assert [xy = grid/get-first-cell xy]	;-- should be a starting cell
		#debug grid-view [						;-- assertion doesn't hold for self-containing grids
			#assert [grid/frame/cells/:xy]		;-- cell should be rendered already (for row-heights to return immediately)
		]
		yspan: second grid/get-span xy
		r: 0 repeat y yspan [r: r + grid/row-height? y - 1 + xy/y]
		r + (yspan - 1 * (grid/spacing along 'y))
	]
		
	cell-size?: function [grid [object!] xy [pair!]] [
		as-pair  cell-width? grid xy  cell-height? grid xy 
	]
		
	calc-size: function [grid [object!]] [
		if r: grid/size [return r]						;-- already calculated
		#debug grid-view [#print "grid/calc-size is called!"]
		#assert [not grid/infinite?]
		bounds: grid/calc-bounds
		bounds: bounds/x by bounds/y					;-- turn block into pair
		#debug grid-view [#assert [0 <> area? bounds]]
		r: grid/margin * 2 + (grid/spacing * max 0x0 bounds - 1)
		repeat x bounds/x [r/x: r/x + grid/col-width?  x]
		repeat y bounds/y [r/y: r/y + grid/row-height? y]
		#debug grid-view [#print "grid/calc-size -> (r)"]
		grid/size: r
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
				not content: grid/cells/pick mcell		;-- cell is not defined? skip the draw
			] [continue]
			done/:mcell: true							;-- mark it as drawn
			
			set-quiet 'rendered-xy cell						;@@ temporary kludge until apply!
			pinned?: grid/is-cell-pinned? cell
			mcell-to-cell: grid/get-offset-from mcell cell	;-- pixels from multicell to this cell
			draw-ofs: start + cell1-to-cell - mcell-to-cell	;-- pixels from draw's 0x0 to the draw box of this cell
			
			mcspace: grid/wrap-space mcell content
			canvas: (cell-width? grid mcell) by infxinf/y	;-- sum of spanned column widths
			render/on mcspace encode-canvas canvas 1x-1		;-- render content to get it's size - in case it was invalidated
			mcsize: canvas/x by cell-height? grid mcell		;-- size of all rows/cols it spans = canvas size
			set-quiet 'rendered-xy cell						;@@ temporary kludge until apply! (could have been reset by inner grids)
			mcdraw: render/on mcspace encode-canvas mcsize 1x1	;-- re-render to draw the full background
			;@@ TODO: if grid contains itself, map should only contain each cell once - how?
			geom: compose [offset (draw-ofs) size (mcsize)]
			repend map [mcspace geom]					;-- map may contain the same space if it's both pinned & normal
			compose/only/into [							;-- compose-map calls extra render, so let's not use it here
				translate (draw-ofs) (mcdraw)			;@@ can compose-map be more flexible to be used in such cases?
			] tail drawn
		]
		reduce [map drawn]
	]

	;; uses canvas only to figure out what cells are visible (and need to be rendered)
	draw: function [grid [object!] canvas: infxinf [pair! none!] wxy1 [none! pair!] wxy2 [none! pair!]] [
		#debug grid-view [#print "grid/draw is called with window xy1=(wxy1) xy2=(wxy2)"]
		#assert [any [not grid/infinite?  all [canvas +< infxinf wxy1 wxy2]]]	;-- bounds must be defined for an infinite grid
		
		set [canvas: fill:] decode-canvas new-canvas: canvas	;-- new-canvas should remember the fill flag too
		do-invalidate grid
		frame: grid/frame
		frame/canvas: new-canvas

		;; prepare column widths before any offset-to-cell mapping, and before hcache is filled
		if all [fill/x = 1  grid/autofit  not grid/infinite?] [
			autofit grid canvas/x grid/autofit
		]
 	
		frame/bounds: grid/cells/size					;-- may call calc-size to estimate number of cells
		#assert [frame/bounds]
		;-- locate-point calls row-height which may render cells when needed to determine the height
		default wxy1: 0x0
		unless wxy2 [wxy2: wxy1 + calc-size grid]
		xy1: max 0x0 wxy1 - grid/origin
		xy2: max 0x0 min xy1 + canvas wxy2

		;; affects xy1 so should come before locate-point
		unless (pinned: grid/pinned) +<= 0x0 [			;-- nonzero pinned rows or cols?
			xy0: grid/margin + xy1						;-- location of drawn pinned cells relative to grid's origin
			set [map: drawn-common-header:] draw-range grid 1x1 pinned xy0
			xy1: xy1 + grid/get-offset-from 1x1 (pinned + 1x1)	;-- location of unpinned cells relative to origin
		]
		#debug grid-view [#print "drawing grid from (xy1) to (xy2)"]

		xy2: max xy1 xy2
		set [cell1: offs1:] grid/locate-point xy1
		set [cell2: offs2:] grid/locate-point xy2
		all [none? grid/size  not grid/infinite?  calc-size grid]
		#assert [any [grid/infinite? grid/size]]		;-- must be set by calc-size or carried over from the previous render

		quietly grid/map: make block! 2 * area? cell2 - cell1 + 1
		if map [append grid/map map  stash map]
		
		;@@ create a grid layout?
		if pinned/x > 0 [
			set [map: drawn-row-header:] draw-range grid
				(1 by cell1/y) (pinned/x by cell2/y)
				xy0/x by (xy1/y - offs1/y)
			append grid/map map  stash map
		]
		if pinned/y > 0 [
			set [map: drawn-col-header:] draw-range grid
				(cell1/x by 1) (cell2/x by pinned/y)
				(xy1/x - offs1/x) by xy0/y
			append grid/map map  stash map
		]

		set [map: drawn-normal:] draw-range grid cell1 cell2 (xy1 - offs1)
		append grid/map map  stash map
		;; note: draw order (common -> headers -> normal) is important
		;; because map will contain intersections and first listed spaces are those "on top" from hittest's POV
		;; as such, map doesn't need clipping, but draw code does

		reshape [
			;-- headers also should be fully clipped in case they're multicells, so they don't hang over the content:
			clip  0x0         !(xy1)            !(drawn-common-header)	/if drawn-common-header
			clip !(xy1 * 1x0) !(xy2/x by xy1/y) !(drawn-col-header)		/if drawn-col-header
			clip !(xy1 * 0x1) !(xy1/x by xy2/y) !(drawn-row-header)		/if drawn-row-header
			clip !(xy1)       !(xy2)            !(drawn-normal)
		]
	]
	
	;; NOTE: to properly apply styles this should only be called from within draw
	measure-column: function [
		"Measure single column's extent on the canvas of WIDTHxINF (returned size/x may be less than WIDTH)"
		grid  [object!]  "Uses only Y part from margin and spacing"
		index [integer!] "Column's index, >= 1"
		width [integer!] "Allowed column width in pixels"
		row1  [integer!] "Limit estimation to a given row span"
		row2  [integer!]
	][
		canvas: encode-canvas width by infxinf/y -1x-1	;-- no fill flag is set
		size: grid/margin * 0x2
		spc:  grid/spacing along 'y
		if row2 > row1 [size/y: size/y - spc]
		for irow row1 row2 [
			cell: index by irow
			unless space: grid/cells/pick cell [continue]
			cspace: grid/wrap-space cell space			;-- apply cell style too (may influence min. size by margin, etc)
			canvas': either integer? h: any [grid/heights/:irow grid/heights/default] [	;-- row may be fixed
				render/on cspace encode-canvas width by h -1x-1	;-- fixed rows only affect column's width, no filling
			][
				render/on cspace canvas
				h: cspace/size/y
			]
			span: grid/get-span cell1: grid/get-first-cell cell
			irow: cell1/y + span/y - 1
			;@@ make an option to ignore spanned cells?
			;@@ and theoretically I could subtract spacing from the spanned cells (in case it's big), but lazy for now
			size/y: size/y + spc + to integer! h / span/x		;-- span/x is accounted for only approximately
			size/x: max size/x cspace/size/x
		]
		size
	]
	
	;@@ when I document these, need a few showcase tables (text, text+images, fields maybe) and how each one works
	;@@ big image + text cell will be a good showcase for hyperbolic algo
	;@@ need a flag for paragraph to never wrap partial words
	;; fast stable content-agnostic column width fitter
	;; NOTE: to properly apply styles this should only be called from within draw (doesn't invalidate for that reason)
	autofit: function [
		"Automatically adjust GRID column widths to minimize grid height"
		grid        [object!]
		total-width [integer!] "Total grid width to fit into"
		method      [word!]    "One of supported fitting methods: [hyperbolic weighted simple-weighted]"	;@@
	][
		#assert [not grid/infinite? "Adjustment of infinite grid will take infinite time!"]
		;; does not modify grid/heights - at least some of them must be `auto` for this func to have effect
		bounds: grid/cells/size
		nx: bounds/x  ny: bounds/y
		if any [nx <= 1 ny <= 0] [exit]					;-- nothing to fit - single column or no rows
		
		margin:    1x1 * grid/margin
		spacing:   1x1 * grid/spacing
		widths:    grid/widths							;-- modifies widths map in place
		min-width: any [widths/min 5]					;@@ make an option to control this?
				
		set [W1 H1 W2 H2] grid/frame/limits				;-- if W1/H1/W2/H2 are cached, use them
		new-vector: [add -1.0 make vector! reduce ['float! 64 nx]]	;-- negative or it will be considered cached
		
		loop 1 [										;-- needed to use `break`
			;; render all columns on zero, get their min widths W1i and heights H1i
			W1: any [W1  do new-vector]
			H1: any [H1  do new-vector]
			repeat i nx [
				if all [W1/:i >= 0 H1/:i >= 0] [continue]		;-- cached, still valid
				size: measure-column grid i 0 1 ny
				W1/:i: 1.0 * max min-width size/x
				H1/:i: 1.0 * size/y
			]
			
			;; estimate space left SL = TW - sum(W1i), TW is total-width requested
			TW: total-width - (2 * margin/x) - (nx - 1 * spacing/x)
			SL: TW - TW1: sum W1
			
			;; if SL <= 0, end here, set widths to found amounts
			if SL <= 0 [W: W1  break]
			
			;; SL > 0 case: render all columns on infinite canvas, now I have min heights H2i and max widths W2i
			W2: any [W2  do new-vector]
			H2: any [H2  do new-vector]
			repeat i nx [
				if all [W2/:i >= 0 H2/:i >= 0] [continue]		;-- cached, still valid
				size: measure-column grid i infxinf/x 1 ny
				W2/:i: max W1/:i 1.0 * size/x		;-- ensure monotony:
				H2/:i: min H1/:i 1.0 * size/y		;-- W2 >= W1, H2 <= H1
			]
			TW2: sum W2
			
			;; if maximum possible width is less than requested, use it
			;@@ maybe make an option to stretch the grid to TW even if there's no point?
			if TW2 <= TW [W: W2  break]
			
			;; now given initial W1-W2/H1-H2 bounds, find an optimum
			switch/default method [
				;; free space (over W1) is distributed by weights=(W2-W1)
				width-difference [						;-- this is what browsers are using, at least PaleMoon
					weights: W2 - W1
					W: weights / (sum weights) * SL + W1
				]
				
				;; total width is distributed by weights=W2, but no less than W1
				;@@ externalize this algo
				width-total [
					weights:  W2
					norm-W1:  W1 / weights
					w-vector: make block! nx * 4
					repeat i nx [						;@@ use map-each
						repend w-vector [norm-W1/:i  W1/:i  weights/:i  i]
					]
					sort/reverse/skip w-vector 4		;-- sorted from most oversized to most relaxed
					left: TW
					W:    copy W2
					wsum: sum weights
					foreach [_ wmin wgt i] w-vector [
						we:   wgt / wsum * left			;-- estimated weighted width for the column
						W/:i: max wmin we				;-- don't let it go lower than W1 (wmin)
						wsum: wsum - wgt				;-- next time normalize to the new sum of weights
						left: left - W/:i
					]
				]
				
				;; unlike width-total, area-total may assign width > W2, so have to clip it, which complicates the algorithm
				area-total			;-- assumes constant (W*H) for each column (equals W2*H2), special case of area-difference
				area-difference [	;-- assumes constant (W*H+C) for each column (equals both W2*H2 and W1*H1)
					either total?: method = 'area-total [
						C:  0.0
						W2*H2: W2 * H2					;-- weights basically
						H+: maximum-of W2*H2 / W1		;-- height where all width estimates become <= W1
					][
						C:  (H2 * W2) - (H1 * W1) / (H1 - H2 + 1e-6)	;-- hyperbolae offsets, +epsilon to avoid zero division
						H+: maximum-of H1
					]
					H-: minimum-of H2
					
					;; total width estimation (im)precision; @@ should be a controllable parameter I guess
					;; bigger requires less iterations but is more "jumpy" when resizing,
					;; since it adds pixels to all columns
					tolerance: 1
					
					WE: copy W1							;-- shortcut for make vector! reduce ['float! 64 length]
					HE2TWE: pick [[						;-- function TWE(HE) as F(x) for binary search
						; WE: (copy W2*H2) / HE
						WE: WE * 0.0 + W2*H2 / HE		;-- this spares me an extra copy on each iteration
						sum clip-vector WE W1 W2		;-- clip within [W1i,W2i] since hyperbola extends outside this segment
					][
						; WE: (copy W2) + C * H2 / HE - C
						WE: WE * 0.0 + W2 + C * H2 / HE - C
						sum clip-vector WE W1 W2
					]] total?
					
					;; now find height estimate HE corresponding to the closest width to TW using binary search
					set [H-: TW+: HE: TWE:]						;-- use lower width as estimate since it's <= TW
						binary-search/with HE H- H+ TW tolerance HE2TWE TW2 TW1		;@@ use `apply` to make it readable!
					#assert [(abs TWE - TW) <= tolerance]
									
					;; find final widths W from height estimate HE
					W: (copy W2) + C * H2 / HE - C
					W: clip-vector W W1 W2
					W: W + (TW - TWE / length? W)				;-- evenly distribute remaining space
				]
			] [ERROR "Unknown fitting method: (method)"]
			#assert [TW ~= sum W  "widths should in total sum to TW"]
		]
		
		if grid/frame/limits [grid/frame/limits: reduce [W1 H1 W2 H2]]	;-- save min/max sizes
		
		;; set widths map to found W vector
		W: quantize W
		changed?: no
		repeat i nx [
			if widths/:i <> W/:i [
				changed?: yes
				widths/:i: W/:i
			]
		]
		if changed? [
			quietly grid/size: none						;-- size is no longer valid
			clear grid/frame/heights					;-- line height cache is no longer valid after widths have changed
		]
	]
	
	on-invalidate: function [
		grid  [object!]
		cell  [none! object!]
		scope [none! word!]
	][
		repend grid/frame/invalid [cell scope]
		cache/invalidate grid							;-- clears the cached canvas+sizes block so render will be called again
	]
	
	invalidate-xy: function [grid [object!] xy [pair!]] [
		remove/key grid/frame/heights xy/y
		foreach vector grid/frame/limits [vector/(xy/x): -1.0]
		quietly grid/size: none
	]
	
	do-invalidate: function [grid [object!]] [
		foreach [cell scope] grid/frame/invalid [
			if scope = 'size [
				either cell [
					invalidate-xy grid pick find/same grid/frame/cells cell -1
				][
					quietly grid/size: none
				]
			]
		]
	]
	
	pinned?: function [cell [object!] ('cell = select cell 'type)] [	;-- used by cell/pinned?
		grid: cell										;-- sometimes grid is not an immediate parent
		while [grid: grid/parent] [if grid/type = 'grid [break]]
		to logic! all [
			grid
			found: find/same grid/frame/cells cell
			grid/is-cell-pinned? found/-1
		]
	]
	
	;@@ add simple proportional algorithm?
	fit-types: [width-total width-difference area-total area-difference]	;-- for type checking
	
	declare-template 'grid/space [
		;; grid's /size can be 'none' in two cases: either it's infinite, or it's size was invalidated and needs a calc-size() call
		size: none	#type [pair! none!]
		
		margin:  5
		spacing: 5
		origin:  0x0			;-- scrolls unpinned cells (should be <= 0x0), mirror of grid-view/window/origin ;@@ make it read-only
		content: make map! 8	#on-change :invalidates			;-- XY coordinate -> space (not cell, but cells content)
		spans:   make map! 4	#type [map!]					;-- XY coordinate -> it's XY span (not user-modifiable!!)
		;; widths/min used in `autofit` func to ensure no column gets zero size even if it's empty
		widths:  make map! [default 100 min 10]					;-- map of column -> it's width
			#type [map!] :invalidates
		;; heights/min used when heights/default = auto, in case no other constraints apply
		;; set to >0 to prevent rows of 0 size (e.g. if they have no content)
		heights: make map! [default auto min 0]					;-- height can be 'auto (row is auto sized) or integer (px)
			#type [map!] :invalidates
		autofit: 'area-total									;-- automatically adjust column widths? method name or none
			#type = :invalidates [word! (find ~/fit-types autofit) none!]
		pinned:  0x0						;-- how many rows & columns should stay pinned (as headers), no effect if origin = 0x0
			#type =? :invalidates-look (0x0 +<= pinned)
		bounds:  [x: auto y: auto]								;-- max number of rows & cols
			#type :invalidates [block! function! pair!]
			(all [										;-- 'auto=bound /cells, integer=fixed, none=infinite (only within a window!)
				bounds: bounds							;-- call it if it's a function
				any [none =? bounds/x  'auto = bounds/x  all [integer? bounds/x  bounds/x >= 0]]
				any [none =? bounds/y  'auto = bounds/y  all [integer? bounds/y  bounds/y >= 0]]
			])
			
		;; data about the last rendered frame, may be used by /draw to avoid extra recalculations
		frame: context [								;@@ hide it maybe from mold? unify with /last-frame ?
			;@@ maybe cache size too here? just to avoid setting grid/size to none in case it's relied upon by some reactors
			;@@ maybe cache drawn and map and only remake the changed parts? is it worth it?
			;@@ maybe width not canvas?
			canvas:  none								;@@ support more than one canvas? canvas/x affects heights, limits if autofit is on
			bounds:  none								;-- WxH number of cells (pair), used by draw & others to avoid extra calculations
			heights: make map!   4						;-- cached heights of rows marked for autosizing
			;; "cell cache" - cached `cell` spaces: [XY cell ...] and [space XY geometry ...]
			;; persistency required by the focus model: cells must retain sameness, i.e. XY -> cell
			;@@ TODO: changes to content must invalidate ccache! but no way to detect those changes, so only manually possible
			cells:   make hash!  8						;-- cells that wrap content, filled by render and height estimator
			;; min & max column widths & heights cache (if not cached, spends 2 more rendering attempts on each render with autofit)
			limits:  make block! 4						;-- either none(disabled) or block; block is filled by autofit: [W1 H1 W2 H2]
			invalid: make block! 8						;-- invalidation list for the next frame
		] #type [object!]
		
		on-invalidate: :~/on-invalidate					;-- grid uses custom invalidation or it's too slow
		
		;@@ TODO: margin & spacing - in style??
		;@@ TODO: alignment within cells? when cell/size <> content/size..
		;@@       and how? per-row or per-col? or per-cell? or custom func? or alignment should be provided by item wrapper?
		;@@       maybe just in lay-out-grid? or as some hacky map that can map rows/columns/cells to alignment?
		map: []
		
		;; ccache cannot be stashed/replaced because otherwise it's possible to press a button in a cell,
		;; and upon release there will be another cell, the old one will be lost, so hittest will be confused
		;@@ so when and how to invalidate ccache? makes most sense on content change and when it gets out of the viewport
		; cache: [size map hcache fitcache size-cache]
		cache: []

		wrap-space: function [xy [pair!] space [object! none!]] [	;-- wraps any cells/space into a lightweight "cell", that can be styled
			unless cell: frame/cells/:xy [
				cell: make-space 'cell [pinned?: does [grid-ctx/pinned? self]]
				repend frame/cells [xy cell] 
			]
			quietly cell/parent: none					;-- prevent grid invalidation in case new space is assigned
			cell/content: space
			cell
		] #type [function!] :invalidates

		cells: func [/pick xy [pair!] /size] [			;-- up to user to override
			either pick [content/:xy][calc-bounds]
		] #type [function!] :invalidates				;@@ should clear frame/cells too!
		
		into: func [xy [pair!] /force child [object! none!]] [~/into self xy child]
		
		;-- userspace functions for `spans` reading & modification
		;-- they are required to be able to get any particular cell's multi-cell without full `spans` traversal
		get-span: function [
			"Get the span value of a cell at XY"
			xy [pair!] "Column (x) and row (y)"
		][
			any [spans/:xy  1x1]
		] #type [function!]

		get-first-cell: function [
			"Get the starting row & column of a multicell that occupies cell at XY"
			xy [pair!] "Column (x) and row (y); returns XY unchanged if no such multicell"
		][
			span: get-span xy
			if span +< 1x1 [xy: xy + span]
			xy
		] #type [function!]

		set-span: function [
			"Set the SPAN of a FIRST cell, breaking it if needed"
			cell1 [pair!] "Starting cell of a multicell or normal cell that should become a multicell"
			span  [pair!] "1x1 for normal cell, more to span multiple rows/columns"
			/force "Also break all multicells that intersect with the given area"
		][
			~/set-span self cell1 span force
		] #type [function!]
		
		get-offset-from: function [
			"Get pixel offset of left top corner of cell C2 from that of C1"
			c1 [pair!] c2 [pair!]
		][
			~/get-offset-from self c1 c2
		] #type [function!]
		
		locate-point: function [
			"Map XY point on a grid into a cell it lands on, return [cell-xy offset]"
			xy [pair!]
			/screen "Point is on rendered viewport, not on the grid"
			; return: [block!] "offset can be negative for leftmost and topmost cells"
		][
			~/locate-point self xy screen
		] #type [function!]

		row-height?: function [
			"Get height of row Y (only calculate if necessary)"
			y [integer!]
		][
			~/row-height? self y
		] #type [function!]

		col-width?: function [
			"Get width of column X"
			x [integer!]
		][
			any [widths/:x widths/default]
		] #type [function!]

		cell-size?: function [
			"Get the size of a cell XY or a multi-cell starting at XY (with the spaces)"
			xy [pair!]
		][
			~/cell-size? self xy
		] #type [function!]

		is-cell-pinned?: func [
			"Check if XY is within pinned row or column"
			xy [pair!]
		][
			not pinned +< xy
		] #type [function!]

		infinite?: function ["True if not all grid dimensions are finite"] [
			bounds: self/bounds							;-- call it in case it's a function
			not all [bounds/x bounds/y]
		] #type [function!]

		;; returns a block [x: y:] with possibly `none` (unlimited) values ;@@ REP #116 could solve this
		;@@ maybe obsolete (hide) this, since now there's valid /size? although /size can't account for half-infinite bounds
		;@@ I also don't like the name, 'bounds' is too confusing (how is it different from /size?)
		calc-bounds: function ["Estimate total size of the grid in cells (in case bounds set to 'auto)"] [
			~/calc-bounds self
		] #type [function!]
	
		;; hidden because /size should be valid now, and this function triggered out of tree rendering
		; calc-size: function ["Estimate total size of the grid in pixels"] [~/calc-size self]

		draw: function [/on canvas [pair!] /window xy1 [none! pair!] xy2 [none! pair!]] [
			~/draw self canvas xy1 xy2
		]
	]
]


grid-view-ctx: context [
	~: self
	
	;; gets called before grid/draw by window/draw to estimate the max window size and thus config scrollbars accordingly
	available?: function [grid [object!] axis [word!] dir [integer!] from [integer!] (from >= 0) requested [integer!] (requested >= 0)] [	
		#debug grid-view [print ["grid/available? is called at" axis dir from requested]]	
		bounds: grid/bounds
		#assert [bounds "data/size is none!"]
		r: case [
			dir < 0 [from]
			bounds/:axis [
				size: grid-ctx/calc-size grid			;@@ maybe /size will be enough?
				max 0 size/:axis - from
			]
			'infinite [requested]
		]
		#assert [r >= 0]
		r: clip 0 r requested
		#debug grid-view [#print "avail?/(axis) (dir) = (r) of (requested)"]
		r
	]
	
	declare-template 'grid-view/inf-scrollable [
		;@@ TODO: jump-length should ensure window size is bigger than viewport size + jump
		;@@ situation when jump clears a part of a viewport should never happen at runtime
		;@@ TODO: maybe a % of viewport instead of fixed jump size?
		size: 0x0	#type =? #on-change [space word value] [quietly space/jump-length: min value/x value/y]
		
		;; reminder: window/roll may change this (together with window/origin) when rolling
		;; grid/origin mirrors grid-view/origin: former is used to relocate pinned cells, latter is normal part of scrollable
		origin: 0x0	#type =? #on-change [space word value] [space/grid/origin: value]	;-- grid triggers invalidation
		
		content-flow: 'planar
		source: make map! [size: 0x0]	#on-change :invalidates	;-- map is more suitable for spreadsheets than block of blocks
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
				'else [ERROR "Unsupported data source type: (mold type? :source)"]
			]
		] #type [function!] :invalidates

		;; only called initially or after invalidate-range
		wrap-data: function [item-data [any-type!]] [
			spc: make-space 'data-view [				;@@ 'quietly' used as optimization but must be in sync with data-view/on-change
				quietly type:  'cell
				quietly wrap?:  on						;-- will be considered upon /data change
				quietly margin: 3x3
				quietly align: -1x0
				pinned?: does [grid-ctx/pinned? self]
			]
			set/any 'spc/data :item-data
			spc
		] #type [function!] :invalidates

		;; cacheability requires window to be fully rendered but
		;; full window render is too slow (many seconds), can't afford it
		;; so instead, grid redraws visible part every time
		window/cache: none
		
		window/content: grid: make-space 'grid [
			;; while this should not pose a danger of extra invalidation, since cells are not under user's control,
			;; currently cells is a hash (for reverse lookups), while content is a map
			; frame/cells: content
		
			;; no need to wrap data-view because it's already a box/cell
			wrap-space: function [xy [pair!] space [object!]] [
				; put frame/cells xy get space
				pos: any [find frame/cells xy  tail frame/cells]
				rechange pos [xy space]					;-- used by grid for reverse lookups (e.g. during styling)
				space
			]
			
			available?: function [axis [word!] dir [integer!] from [integer!] requested [integer!]] [	
				~/available? self axis dir from requested
			]
			
			;; currently the only way to make grid forget it's rendered content, since we can't "watch" /data
			invalidate-range: function [xy1 [pair!] xy2 [pair!]] [
				xyloop xy xy2 - xy1 + 1 [				;@@ should be for-each
					remove/key grid/content xy + xy1 - 1
				]
				invalidate self
			]
		] #type (space? grid)
		
		grid/cells: func [/pick xy [pair!] /size] [
			either pick [
				any [
					grid/content/:xy					;@@ need to think when to free this up, maybe when cells get hidden
					grid/content/:xy: grid/wrap-space xy wrap-data data/pick xy
				]
			][data/size]
		]
		grid/calc-bounds: grid/bounds: does [grid/cells/size]
	]
]


button-ctx: context [
	~: self
	
	declare-template 'clickable/box [					;-- low-level primitive, unlike data-view
		;@@ should pushed be in button rather?
		align:    0x0									;-- center by default
		command:  []									;-- code to run on click (on up: when `pushed?` becomes false)
		
		pushed?:  no	#type =? [logic!]				;-- becomes true when user pushes it; triggers `command`
		#on-change [space word value] [
			invalidate space
			unless value [do space/command]				;-- trigger when released
		]
		;@@ should command be also a function (actor)? if so, where to take event info from?
	]
	
	declare-template 'data-clickable/data-view [		;@@ any better name?
		;@@ should pushed be in button rather?
		align:    0x0									;-- center by default
		command:  []									;-- code to run on click (on up: when `pushed?` becomes false)
		
		pushed?:  no	#type =? [logic!]				;-- becomes true when user pushes it; triggers `command`
		#on-change [space word value] [
			invalidate space
			unless value [do space/command]				;-- trigger when released
		]
		;@@ should command be also a function (actor)? if so, where to take event info from?
	]
	
	declare-template 'button/data-clickable [			;-- styled with decor
		weight:   0										;-- button should not be stretched by tubes
		margin:   10x5
		rounding: 5	#type [integer!] (rounding >= 0)	;-- box rounding radius in px
	]
]


;@@ this should not be generally available, as it's for the tests only - remove it!
declare-template 'rotor/space [
	content: none	#type =? :invalidates [object! none!]
	angle:   0		#type =  :invalidates-look [integer! float!]

	ring: make-space 'space [type: 'ring size: 360x10]
	tight?: no
	;@@ TODO: zoom for round spaces like spiral

	map: reduce [							;-- unused, required only to tell space iterators there's inner faces
		ring [offset 0x0 size 999x999]					;-- 1st = placeholder for `content` (see `draw`)
	]
	cache: [size map]
	
	into: function [xy [pair!] /force child [object! none!]] [
		unless spc: content [return none]
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
		r2: r1 + 10
		c: cosine angle  s: negate sine angle
		p0: p: xy - (size / 2)							;-- p0 is the center
		p: as-pair  p/x * c - (p/y * s)  p/x * s + (p/y * c)	;-- rotate the coordinates
		xy: p + (size / 2)
		xy1: size - spc/size / 2
		if any [child =? content  r1 > distance? 0x0 p] [
			return reduce [content xy - xy1]
		]
		r: p/x ** 2 + (p/y ** 2) ** 0.5
		a: (arctangent2 0 - p0/y p0/x) // 360					;-- ring itself does not rotate
		if any [child =? ring  all [r1 <= r r <= r2]] [
			return reduce [ring  as-pair a r2 - r]
		]
		none
	]

	draw: function [] [
		unless content [return []]
		map/1: spc: content				;-- expose actual name of inner face to iterators
		drawn: render content			;-- render before reading the size
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
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


caret-ctx: context [
	~: self
	
	declare-template 'caret/rectangle [					;-- caret has to be a separate space so it can be styled
		visible?:    no		#type =? :invalidates-look [logic!]	;-- controlled by focus
		look-around: 10		#type =? [integer!] (look-around >= 0)	;-- how close caret is allowed to come to field borders
		
		width:       1		#type =? [integer!] (width > 0)		;-- width in pixels
			#on-change [space word value] [space/size: value by space/size/y]
			
		;; [0..length] should be kept even when not focused, so tabbing in leaves us where we were
		offset:      0		#type =? [integer!] (offset >= 0)
			#on-change [space word value] [if space/visible? [invalidate space]]
		
		rectangle-draw: :draw	#type [function!]
		draw: does [when visible? (rectangle-draw)]
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
			field/caret/offset: offset
		]
	]
	
	redo: function [field [object!]] [
		unless tail? field/history [
			set [text: offset:] field/history
			field/history: next next field/history
			append clear field/text text
			field/caret/offset: offset
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
					co: clip 0 len co + n
					sel: (min co other) by (max co other)
				]
				field/caret/offset: co
				field/selected: sel
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
				pos: skip text field/caret/offset: co: clip 0 len co
				field/selected: sel: none				;-- `select` should be used to keep selection
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
					field/caret/offset: co
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
		;; layout may be invalidated by a series of keys, second key will call `adjust` with no layout
		;; also changes to text in the event handler effectively make current layout obsolete for caret-to-offset estimation
		;; field can just rebuild it since canvas is always known (infinite) ;@@ area will require different canvas..
		layout: paragraph-ctx/lay-out field/spaces/text infxinf no no
		#assert [object? layout]
		view-width: field/size/x - first (2x2 * field/margin)
		text-width: layout/extra/x
		cw: field/caret/width
		if view-width - cmargin - cw >= text-width [return 0]	;-- fully fits, no origin offset required
		co: field/caret/offset + 1
		cx: first system/words/caret-to-offset layout co
		min-org: min 0 cmargin - cx
		max-org: clip min-org 0 view-width - cx - cw - cmargin
		clip field/origin min-org max-org
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

	draw: function [field [object!] canvas: infxinf [pair! none!]] [
		ctext: field/spaces/text						;-- text content
		invalidate/only ctext							;-- ensure text is rendered too ;@@ TODO: maybe I can avoid this?
		drawn: render/on field/spaces/text infxinf		;-- this sets the size
		set [canvas: fill:] decode-canvas canvas
		; #assert [field/size/x = canvas/x]				;-- below algo may need review if this doesn't hold true
		cmargin: field/caret/look-around
		;; fill the provided canvas, but clip if text is larger (adds cmargin to optimal size so it doesn't jump):
		width: first either fill/x = 1 [canvas][min ctext/size + cmargin canvas]	
		field/size: constrain width by ctext/size/y field/limits
		viewport: field/size - (2 * mrg: field/margin * 1x1)
		co: field/caret/offset + 1
		cxy1: caret-to-offset       ctext/layout co
		cxy2: caret-to-offset/lower ctext/layout co
		csize: field/caret/width by (cxy2/y - cxy1/y)
		unless field/caret/size = csize [
			quietly field/caret/size: csize
			invalidate/only field/caret
		]
		;; draw does not adjust the origin, only event handlers do (this ensures it's only adjusted on a final canvas)
		if sel: field/selected [
			sxy1: caret-to-offset       ctext/layout sel/1 + 1
			sxy2: caret-to-offset/lower ctext/layout sel/2
			field/selection/size: ssize: sxy2 - sxy1
			sdrawn: render field/selection
		]
		cdrawn: render field/caret
		#assert [ctext/layout]							;-- should be set after draw, others may rely
		ofs: field/origin by 0
		quietly field/map: reshape-light [
			@[field/spaces/text]      [offset: @(ofs) size: @(ctext/size)]
		/?	@[field/spaces/selection] [offset: @(ofs + mrg + sxy1) size: @(ssize)]		/if sel
			@[field/spaces/caret]     [offset: @(ofs + mrg + cxy1) size: @(csize)]
		]
		reshape-light [									;@@ can compose-map be used without re-rendering?
			clip @(mrg) @(field/size - mrg) [
				translate @(ofs) [
				/?	translate @(mrg + sxy1) @[sdrawn]	/if sel
					translate 0x0 @[drawn]
					translate @(mrg + cxy1) @[cdrawn]
					;@@ workaround for #4901 which draws white background under text over the selection:
					#if linux? [
					/?	translate @(mrg + sxy1) @[sdrawn]	/if sel
					]
				]
			]
		]
	]
		
	on-change: function [field [object!] word [word!] value [any-type!]] [
		set/any 'field/spaces/text/:word :value			;-- sync these to text space; invalidated by text
		if word = 'text [
			field/caret/offset: length? value			;-- auto position at the tail
			mark-history field
		]
	]
	
	;@@ field will need on-change handler & actor support for better user friendliness!
	declare-template 'field/space [
		;; own facets:
		weight:   1		#type =? :invalidates [number!] (weight >= 0)
		origin:   0		#type =? :invalidates-look [integer!] (origin <= 0)		;-- offset(px) of text within the field
		selected: none	#type =? :invalidates-look [pair! none!]	;-- none or pair (offsets of selection start & end)
		history:  make block! 100	#type [block!]		;-- saved states
		map:      []
		cache:    [size map]

		spaces: object [
			text:      make-space 'text      [color: none]		;-- by exposing it, I simplify styling of field
			caret:     make-space 'caret     []
			selection: make-space 'rectangle [type: 'selection]	;-- can be styled
		] #type [object!]
		
		;; shortcuts
		caret:     spaces/caret		#type (space? caret)
		selection: spaces/selection	#type (space? selection)
		
		;; these mirror spaces/text facets:
		margin: 0					#type =? :on-change	;-- default = no margin
		flags:  []					#type    :on-change	;-- [bold italic underline] supported ;@@ TODO: check for absence of `wrap`
		text:   spaces/text/text	#type    :on-change
		font:   spaces/text/font	#type =? :on-change
		color:  none				#type =? :on-change	;-- placeholder for user to control
		
		offset-to-caret: func [offset [pair!]] [~/offset-to-caret self offset]
		#type [function!]
		
		edit: func [
			"Apply a sequence of edits to the text"
			plan [block!]
		][
			~/edit self plan
		] #type [function!]
		
		draw: func [/on canvas [pair!]] [~/draw self canvas]
	]
	
]

;@@ native area when wrapped supports caret both at the end of the line and beginning of the next
;@@ so just integer offset is not enough! but should I bother?
; area-ctx: context [
	; ~: self
	
	; draw: function [area [object!] canvas [pair! none!]] [
		; #assert [pair? canvas]
		; #assert [canvas +< infxinf]						;@@ whole code needs a rewrite here
		; quietly area/size: canvas
		; size: finite-canvas canvas
		; area/paragraph/width: if area/wrap? [size/x]
		; area/paragraph/text:  area/text
		; pdrawn: paragraph/draw								;-- no `render` to not start a new style
		; pdrawn: render/on in area 'paragraph size
		; area/size: constrain max size area/paragraph/size area/limits
		; xy1: caret-to-offset       area/paragraph/layout area/caret-index + 1
		; xy2: caret-to-offset/lower area/paragraph/layout area/caret-index + 1
		; area/caret/size: as-pair area/caret-width xy2/y - xy1/y
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
	; declare-template 'area/scrollable [
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
			; invalidate paragraph
		; ]
	
		; draw: func [/on canvas [pair! none!]] [~/draw self canvas]
		
		; scrollable-on-change: :on-change*
		; #on-change-redirect
	; ]
	
; ]

declare-template 'fps-meter/text [
	; cache:     off
	rate:      100
	text:      "FPS: 100.0"		#on-change :invalidates	;-- longest text used for initial sizing of it's host
	init-time: now/precise/utc	#type [date!]
	frames:    make [] 400		#type [block!]
	aggregate: 0:0:3			#type [time!]
]

export exports
