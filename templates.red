Red [
	title:   "Draw-based widgets (Spaces) definitions"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires `for` loop from auxi.red, layouts.red, clipboard.red, export
exports: [make-space declare-template space?]

;@@ I need to move out the core functionality from here out, leave only templates

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

;; normalizes /margin & /spacing to a pair, for easier handling
on-margin-spacing-change: function [space [object!] word [word!] value [linear! planar!] old [any-type!]] [
	if :old <> new: (1,1) * value [
		invalidates space word quietly space/:word: new
	] 
]

templates/space: declare-class 'space [					;-- minimum basis to build upon
	type:	'space		#type = [word!]					;-- used for styling and event handler lookup, may differ from template name!
	size:   (0,0)		#type = [point2D! (0x0 +<= size)]	;-- none (infinite) must be allowed explicitly by templates supporting it
	parent: none		#type   [object! none!]
	draw:   :no-draw  	#type   [function!]
	;; `drawn` is an exception and not held in the space, so just `size`:
	cache:  [size]		#type   [block! none!]
	cached: tail copy [(0,0) 0.0 #[none]]	#type [block!]	;-- used internally to check if space is connected to the tree, and holds cached facets
	limits: none		#type   [object! (range? limits)  none!] :invalidates
	; rate: none
]

;; a trick not to enforce some facets (saves RAM) but still provide default typechecks for them:
;; (specific values are only for readability here and they have no effect)
modify-class 'space [
	map:     []		#type [block!]
	into:    none	#type [function!]
	;; rate change -> invalidation -> next render puts it into rated-spaces list
	rate:    none	#type =  [linear! time! (rate >= 0) none!]
	color:   none	#type =? :invalidates-look [tuple! none!]
	margin:  0x0	#type =  :on-margin-spacing-change [linear! planar!] (0x0 +<= ((1,1) * margin))
	spacing: 0x0	#type =  :on-margin-spacing-change [linear! planar!] (0x0 +<= ((1,1) * spacing))
	weight:  0		#type =  :invalidates [number!] (weight >= 0)
	origin:  (0,0)	#type =  :invalidates-look [point2D!]
	font:    none	#type =? :invalidates [object! none!]	;-- can be set in style, as well as margin ;@@ check if it's really a font
	command: []		#type [block! paren!]
	kit:     none	#type [object!]
	on-invalidate: 	#type [function! none!]
]	

space?: function ["Determine of OBJ is a space! object" obj [any-type!]] [
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
		e: trap/catch [r: make space-object! r] [			;@@ slower than `try` by 5% on make-space 'space []
			#print "*** Unable to make space of type (type):"
			do thrown
		]
		;; replace the type if it was not enforced by the template:
		;; `class?` is used instead of `type` to force `<->` have type `stretch`
		if r/type = 'space [quietly r/type: class? r]
	]
	r
]

remake-space: function [
	"Safely create a space from a template TYPE"
	type [word!]  "Looked up in templates"
	spec [block!] "Extension code - composed, not evaluated"
][
	also r: make-space type []
	do bind compose/only spec r
]

;; doesn't copy objects: font should be shared and child spaces can't be just copied like that ;@@ but /limits?
;; used mainly for copy/paste functionality
copied!: make typeset! [series! bitset! map!]
clone-space: function [
	"Make a space that is a copy of ORIGINAL, carrying data but not state"
	original [object!] (space? original)
	words    [block!] "Only these words are copied, rest is reset to defaults"
][
	clone: make-space original/type []
	clone/size: original/size
	clone/limits: if object? value: original/limits [copy value]	;-- the only object copied
	foreach word words [
		if word: in clone word [						;-- allow specifying more words (e.g. command in link but not text)
			value: select original word					;-- no get/any or set-quiet by design, to maintain consistency via on-change
			set word either find copied! type? :value [copy/deep :value][:value]
		]
	]
	clone
]

make-template: function [
	"Create a space template"
	base [word!]  "Type it will be based on"  
	spec [block!] "Extension code"
][
	make-space/block base spec
]

;; #push directive expands into #on-change directive for classy-object's declare-class func
;;   it pushes every facet change into all targets (used to expose inner facets into outer template)
;;   and then back from targets into the source (because children may modify the source, e.g. convert margin into pair value)
;; syntax:
;;   facet: value  #push target/path							;-- accepts a path
;;   facet: value  #push [target/path1 target/path2 ...]		;-- or block of paths
;; spaces do not export any macros by design, so this function call is required when using #push in declare-class directly
expand-template: function [
	"Expand template directives"
	spec [block!] "Only #push is supported at the moment"
	/local path
][
	mapparse [#push set path [path! | block!]] copy spec [
		paths: either path? path [reduce [path]][path]
		body: collect [
			foreach path paths [
				insert path: copy path 'space
				keep compose [
					(to set-path! path) :value					;-- pushes the value forth
					quietly space/:word: (to get-path! path)	;-- mirrors back its corrected value
				]
			]
		]
		compose/only [#on-change [space word value] (body)]
	]
]

declare-template: function [
	"Declare a named class and put into space templates"
	name-base [path!] "template-name/prototype-name"
	spec      [block!]
][
	set [name: base:] name-base
	templates/:name: make-template base declare-class name-base expand-template spec
]


;-- helps having less boilerplate when `map` is straightforward
compose-map: function [
	"Build a Draw block from MAP"
	map "List of [space [offset XxY size XxY] ...]"
	/only list [block!] "Select which spaces to include"
	/window xy1 [point2D!] xy2 [point2D!] "Specify viewport"	;@@ it's unused; remove it?
][
	r: make [] round/ceiling/to (1.5 * length? map) 1	;-- 3 draw tokens per 2 map items
	foreach [space box] map [
		all [list  not find/same list space  continue]	;-- skip names not in the list if it's provided
		; all [limits  not boxes-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
		if zero? area? box/size [continue]				;-- don't render empty elements (also works around #4859)
		cmds: render/:window space xy1 xy2
		unless empty? cmds [							;-- don't spawn empty translate/clip structures
			compose/only/into [
				translate (box/offset) (cmds)
			] tail r
		]
	]
	r
]


declare-template 'timer/space [							;-- template space for timers
	rate:  0											;-- unlike space, must always have a /rate facet
	cache: none
]		

;; used by some templates that don't draw anything
no-draw: does [[]]

;; used internally for empty spaces size estimation
set-empty-size: function [space [object!] canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
	canvas: either positive? space/weight
		[fill-canvas canvas fill-x fill-y][(0,0)]		;-- don't stretch what isn't supposed to stretch
	space/size: constrain canvas space/limits
]

;; empty stretching space used for alignment ('<->' alias still has a class name 'stretch')
context [
	~: self
	
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		set-empty-size space canvas fill-x fill-y
		[]
	]
	
	put templates '<-> declare-template 'stretch/space [	;@@ affected by #5137
		weight: 1
		cache:  none
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			~/draw self canvas fill-x fill-y
		]
	]
]

rectangle-ctx: context [
	~: self
	
	declare-template 'rectangle/space [
		size:   (20,10)	#on-change :invalidates
		margin: 0
		draw:   does [compose [box (margin) (size - margin)]]
	]
]

;@@ maybe this should be called `arrow`? because it doesn't have to be triangle-styled
triangle-ctx: context [
	~: self
	
	draw: function [space [object!]] [
		set [p1: p2: p3:] select [
			n [(0,2) (1,0) (2,2)]						;--   n
			e [(0,0) (2,1) (0,2)]						;-- w   e
			w [(2,0) (0,1) (2,2)]						;--   s
			s [(0,0) (1,2) (2,0)]
		] space/dir
		rad: space/size / 2 - space/margin
		compose/deep [
			translate (space/margin) [triangle (p1 * rad) (p2 * rad) (p3 * rad)]
		]
	]
		
	declare-template 'triangle/space [
		size:    (16,10)	#on-change :invalidates
		dir:     'n			#type =    :invalidates [word!] (find [n s w e] dir)
		margin:  0
		
		;@@ need `into` here? or triangle will be a box from the clicking perspective?
		draw: does [~/draw self]
	]
]

image-ctx: context [
	~: self
	
	draw: function [image [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		mrg2: 2 * mrg: image/margin
		switch type?/word image/data [
			none! [
				image/size: constrain mrg2 image/limits			;-- empty image should obey constraints too
				[]
			]
			;@@ this feature needs to be doc'd but I'm not sure about it,
			;@@ since it fills all canvas up to /limits but draw code knows nothing about canvas size
			block! [
				image/size: constrain finite-canvas canvas image/limits
				free: subtract-canvas image/size mrg2
				compose/only [translate (mrg) clip 0x0 (free) (image/data)]
			]
			image! [
				limits:        image/limits
				isize:         image/data/size
				;; `constrain` isn't applicable here because doesn't preserve the ratio, and because of canvas handling
				if all [limits  limits/min  low-lim:  max (0,0) limits/min - mrg2] [	;@@ REP #113 & 122
					min-scale: max  low-lim/x / isize/x  low-lim/y / isize/y	;-- use bigger one to not let it go below low limit
				]
				if all [limits  limits/max  high-lim: max (0,0) limits/max - mrg2] [	;@@ REP #113 & 122
					max-scale: min  high-lim/x / isize/x  high-lim/y / isize/y	;-- use lower one to not let it go above high limit
				]
				if all [image/weight > 0  canvas <> infxinf] [		;-- if inf canvas, will be unscaled, otherwise uses finite dimension
					set-pair [cx: cy:] subtract-canvas canvas mrg2
					canvas-max-scale: min  cx / isize/x  cy / isize/y	;-- won't be bigger than the canvas
					if fill-x [cx: 1.#inf]							;-- don't stick to dimensions it's not supposed to fill
					if fill-y [cy: 1.#inf]  
					canvas-scale: min  cx / isize/x  cy / isize/y	;-- optimal scale to fill the chosen canvas dimensions
					canvas-scale: min canvas-scale canvas-max-scale
				]
				default min-scale:    0.0
				default max-scale:    1.#inf
				default canvas-scale: 1.0
				scale: clip canvas-scale min-scale max-scale 
				; echo [canvas fill low-lim high-lim scale min-scale max-scale lim isize]
				image/size: (to point2D! isize) * scale + (2 * mrg)
				reduce ['image image/data mrg image/size - mrg]
			]
		]
	]

	declare-template 'image/space [
		margin: 0
		weight: 0
		data:   none	#type =? :invalidates [none! image! block!]		;-- images are not recyclable, so `none` by default
		
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


cell-ctx: context [
	~: self

	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		#debug sizing [#print "cell/draw with (if space/content [space-id space/content]) on (canvas) (fill-x) (fill-y)"]
		space/sec-cache: copy []						;-- alloc new (minimal) sections block for new canvas
		unless space/content [
			set-empty-size space canvas fill-x fill-y
			return quietly space/map: []
		]
		canvas:  constrain canvas space/limits
		mrg2:    space/margin * 2
		content: space/content
		drawn:   render/on content (subtract-canvas canvas mrg2) fill-x fill-y
		size:    content/size + mrg2
		;; canvas can be infinite or half-infinite: inf dimensions should be replaced by space/size (i.e. minimize it)
		size:    max size fill-canvas canvas fill-x fill-y		;-- only extends along fill-enabled axes
		space/size: constrain size space/limits
		; #print "size: (size) space/size: (space/size) fill: (fill)"
		
		free:   space/size - content/size - mrg2
		offset: (to point2D! space/margin) + max (0,0) free * (space/align + 1) / 2
		unless tail? drawn [
			drawn: compose/only [translate (offset) (drawn)]
			unless fits?: content/size +<= space/size [			;-- only use clipping when required! (for drop-downs)
				drawn: compose/only [clip 0x0 (space/size) (drawn)]
			]
		]
		quietly space/map: compose/deep [(space/content) [offset: (offset) size: (space/size)]]
		#debug sizing [#print "box with (mold space/content) on (canvas) -> (space/size)"]
		drawn
	]
	
	kit: make-kit 'box [
		clone: function [] [
			cloned: clone-space space [align margin weight command]
			all [
				space? child: select space 'content
				object? ckit: select child 'kit
				function? select ckit 'clone
				cloned/content: batch child [clone]
			]
			cloned
		]
		format: function [] [
			format: copy {}								;-- used when child has no format
			all [
				child: space/content
				format: batch child [format]
			]
			format
		]
		frame: object [
			sections: does [generate-sections space/map space/size/x space/sec-cache]
		]
	]
	
	declare-template 'box/space [
		kit:     ~/kit
		;; margin is useful for drawing inner frame, which otherwise would be hidden by content
		margin:  0
		weight:  1										;@@ what default weight to use? what default alignment?
		;@@ consider more high level VID-like specification of alignment
		align:   0x0	#type =? :invalidates-look [pair!] (-1x-1 +<= align +<= 1x1)
		content: none	#type =? :invalidates [object! none!]
		;@@ should /color be always present?
		
		map:     []
		cache:   [size map sec-cache]
		sec-cache: []									;-- holds last valid sections block if computed
		
		;; draw/only can't be supported, because we'll need to translate xy1-xy2 into content space
		;; but to do that we'll have to render content fully first to get it's size and align it
		;; which defies the meaning of /only...
		;; the only way to use /only is to apply it on top of current offset, but this may be harmful
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
	
	declare-template 'cell/box [margin: 1x1]			;-- same thing just with a border and background ;@@ margin - in style?
]

;@@ TODO: externalize all functions, make them shared rather than per-object
;@@ TODO: automatic axis inferrence from size?
scrollbar: context [
	~: self
	
	into: func [space [object!] xy [planar!] child [object! none!]] [
		any [space/axis = 'x  xy: reverse xy]
		into-map space/map xy child
	]
	
	arrange: function [content [block!]] [				;-- like list layout but simpler/faster
		map: make block! 2 * length? content
		pos: (0,0)
		foreach name content [	;@@ should be map-each
			space: get name
			append map compose/deep [
				(space) [offset: (pos) size: (space/size)]
			]
			pos: space/size * (1,0) + pos
		]
		map
	]
	
	draw: function [space [object!]] [
		size2: either space/axis = 'x [space/size][reverse space/size]
		h: size2/y  w-full: size2/x
		w-arrow: size2/y * space/arrow-size
		w-inner: w-full - (2 * w-arrow)
		;-- in case size is too tight to fit the scrollbar - compress inner first, arrows next
		if w-inner < 0 [w-arrow: w-full / 2  w-inner: 0]
		w-thumb: case [									;-- 3 strategies for the thumb
			w-inner >= (2 * h) [max h w-inner * space/amount]	;-- make it big enough to aim at
			w-inner >= 8       [      w-inner * space/amount]	;-- better to have tiny thumb than none at all
			'else              [0]								;-- hide thumb, leave just the arrows
		]
		w-pgup: w-inner - w-thumb + (w-inner * space/amount) * space/offset
		w-pgdn: w-inner - w-pgup - w-thumb
		quietly space/back-arrow/size:  w-arrow . h
		quietly space/back-page/size:   w-pgup  . h
		quietly space/thumb/size:       w-thumb . h
		quietly space/forth-page/size:  w-pgdn  . h
		quietly space/forth-arrow/size: w-arrow . h
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
		;@@ size should not cause invalidation here, or each deep cache fetch sets it, repainting whole tree
		size:       (100,16)	;#type =? :invalidates		;-- opposite axis defines thickness
		axis:       'x		#type =  :invalidates [word!] (find [x y] axis)
		offset:     0%		#type =  :invalidates-look [number!] (all [0 <= offset offset <= 1])
		amount:     100%	#type =  :invalidates-look [number!] (all [0 <= amount amount <= 1])
		;; arrow length in percents of scroller's thickness:
		arrow-size: 90%		#type =  :invalidates-look [number!] (0 <= arrow-size) 
		
		map:         []
		cache:       [size map]
		back-arrow:  make-space 'triangle  [type: 'back-arrow  margin: 2  dir: 'w] #type (space? back-arrow)	;-- go back a step
		back-page:   make-space 'rectangle [type: 'back-page   draw: :no-draw]     #type (space? back-page)		;-- go back a page
		thumb:       make-space 'rectangle [type: 'thumb       margin: 2x1]        #type (space? thumb)			;-- draggable
		forth-page:  make-space 'rectangle [type: 'forth-page  draw: :no-draw]     #type (space? forth-page)	;-- go forth a page
		forth-arrow: make-space 'triangle  [type: 'forth-arrow margin: 2  dir: 'e] #type (space? forth-arrow)	;-- go forth a step
		
		into: func [xy [planar!] /force space [object! none!]] [~/into self xy space]
		draw: does [~/draw self]
	]
]

scrollable-ctx: context [
	~: self

	set-origin: function [
		space   [object!]
		origin  [point2D! word!]
		no-clip [logic!]
	][
		unless no-clip [
			csize: space/content/size
			box:   min csize space/viewport					;-- if viewport > content, let origin be 0x0 always
			origin: clip origin box - csize 0x0
		]
		space/origin: origin
	]
	
	;@@ or /line /page /forth /back /x /y ? not without apply :(
	;@@ TODO: less awkward spec possible?
	move-by: function [
		space   [object!]
		amount  [word! integer!]
		dir     [word!]
		axis    [word!]
		scale   [number! none!]
		no-clip [logic!]
	][
		dir:  select [forth 1 back -1] dir
		unit: axis2pair axis
		default scale: either amount = 'page [0.8][1]
		switch amount [line [amount: 16] page [amount: space/size]]		;@@ hardcoded 16 offset
		set-origin space space/origin - (amount * scale * unit * dir) no-clip
	]

	move-to: function [
		space     [object!]
		xy        [planar! word!] "Point in content coordinates or [head tail]"
		margin: 0 [linear! planar! none!]		;-- space to reserve around XY
		no-clip   [logic!]
	][
		mrg: margin * (1,1)
		switch xy [
			head [xy: (0,0)]
			tail [xy: space/content/size * 0x1]			;-- no right answer here, csize or csize*0x1 ;@@ won't work for infinity
		]
		box: space/viewport
		mrg: clip (0,0) mrg box - 1 / 2					;-- if box < 2xmargin, choose half box size as margin
		xy1: mrg - space/origin							;-- left top margin point in content's coordinates
		xy2: xy1 + box - (mrg * 2)						;-- right bottom margin point
		dxy: (0,0)
		foreach x [x y] [
			case [
				xy/:x < xy1/:x [dxy/:x: xy/:x - xy1/:x]
				xy/:x > xy2/:x [dxy/:x: xy/:x - xy2/:x]
			]
		]
		set-origin space space/origin - dxy no-clip
		; ?? [box mrg xy1 xy2 xy dxy space/origin]
	]

	into: function [space [object!] xy [planar!] child [object! none!]] [
		if r: into-map space/map xy child [
			all [
				r/1 =? space/content
				r/2: r/2 - space/origin
				not any [child  r/2 inside? space/content]
				r: none
			]
		]
		r
	]

	;; sizing policy (for cell, scrollable, window):
	;; - use content/size if it fits the canvas (no scrolling needed) and no fill flag is set
	;; - use canvas/size if it's less than content/size or if fill flag is set
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		;; apply limits in the earnest - canvas size will become the upper limit
		;@@ maybe render should do this?
		canvas: constrain canvas space/limits
		
		;; canvas and fill flags used by scrollable are not the same as those given to its content
		;; content-flow disables filling for inf dimensions to avoid glitches
		;; but leaves canvas finite, mainly for window to properly size itself (it can't on infinity)
		cfill-x: cfill-y: no
		ccanvas: canvas									;-- canvas for the child space - may differ by scroller size
		switch space/content-flow [
			vertical   [cfill-x: fill-x]
			horizontal [cfill-y: fill-y]
		]
		
		;; empty canvas or no content just leads to canvas filled according to content-flow rules (optimization)
		content: space/content
		if any [
			not content 
			zero? area? canvas
		][
			set-empty-size space canvas cfill-x cfill-y
			return quietly space/map: []
		]
		
		;; two rendering flows possible: with scrollbar subtracted and without it
		;; it is more correct to start without it, though this also leads to double render of big content
		;; an unfortunate slowdown, but mostly alleviated by caching
		hscroll:   space/hscroll
		vscroll:   space/vscroll
		scrollers: vscroll/size/x . hscroll/size/y
		cdrawn:    render/on content ccanvas cfill-x cfill-y
		sshow:     0x0											;-- scrollers show mask 0=hidden, 1=visible
		if all [
			axis: switch space/content-flow [vertical ['y] horizontal ['x]]
			content/size/:axis > canvas/:axis
		][														;-- have to add the scroller and subtract it from canvas width
			sshow/:axis: 1										;-- for long vertical reduce xsize and enable vscroll
			ccanvas: subtract-canvas ccanvas (scrollers * reverse sshow)
			cdrawn: render/on content ccanvas cfill-x cfill-y
		]
		
		viewport: min canvas ccanvas							;-- viewport is area not occupied by scrollbars
		csize:    content/size
		origin:   space/origin									;-- must be read after render (& possible roll)
		;; no origin clipping can be done here, otherwise it's changed during intermediate renders
		;; and makes it impossible to scroll to the bottom because of window resizes!
		;; clipping is done by /clip-origin, usually in event handlers where size & viewport are valid (final)
		
		;; determine what scrollers to show
		loop 2 [												;-- each scrollbar affects another's visibility
			if viewport/x < csize/x [sshow/x: 1]
			if viewport/y < csize/y [sshow/y: 1]
			;; 'reverse' because sshow/x means _horizontal_ scroller which eats up _vertical_ space
			viewport: subtract-canvas canvas scrollers * reverse sshow	;-- viewport may be infinite if canvas is
		]
		;; quiet to avoid deep invalidation
		quietly hscroll/size: (viewport/x * sshow/x) . hscroll/size/y	;-- masking avoids infinite size
		quietly vscroll/size: vscroll/size/x . (viewport/y * sshow/y)
		
		;; final size is viewport + free space filled by fill flags + scrollbars
		free:   subtract-canvas viewport csize
		hidden: subtract-canvas csize viewport
		desired-size: (min viewport csize) + (fill-canvas free fill-x fill-y) + (scrollers * reverse sshow)
		space/size: constrain desired-size space/limits			;-- constrain again: with fill=0 limits/min may be missed by canvas
		; ?? [free fill-x fill-y space/size]
		; ?? [canvas ccanvas viewport csize sshow free hidden space/size]
		
		;; set scrollers but avoid multiple recursive invalidation when changing srcollers fields
		;; (else may stack up to 99% of all rendering time)
		;@@ maybe move this into the scrollers?
		csize': max 1x1 csize							;-- avoid division by zero
		quietly hscroll/amount: 100% * amnt: min 1.0 viewport/x / csize'/x
		quietly hscroll/offset: 100% * clip 0 1 - amnt (negate origin/x) / csize'/x
		quietly vscroll/amount: 100% * amnt: min 1.0 viewport/y / csize'/y
		quietly vscroll/offset: 100% * clip 0 1 - amnt (negate origin/y) / csize'/y
		
		;@@ TODO: fast flexible tight layout func to build map? or will slow down?
		unless fits? [render space/scroll-timer]				;-- scroll-timer has to appear in the tree for timers
		space/scroll-timer/rate: pick [0 16] fits?: sshow = 0x0	;-- turns off timer when unused!
		viewport: space/size - (scrollers * reverse sshow)		;-- include 'free' size in the viewport
		quietly space/map: reshape-light [
			@(content) [offset: (0,0) size: @(viewport)]
		/?	@(hscroll) [offset: @(viewport * 0x1) size: @(hscroll/size)]	/if sshow/x = 1
		/?	@(vscroll) [offset: @(viewport * 1x0) size: @(vscroll/size)]	/if sshow/y = 1
		/?	@(space/scroll-timer) [offset: (0,0) size: (0,0)]				/if not fits?	;-- list it for tree correctness
		]
		
		invalidate/only hscroll									;-- let scrollers know they were changed
		invalidate/only vscroll
		
		cdrawn: compose/only [translate (origin) (cdrawn)]
		unless fits? [cdrawn: compose/only [clip 0x0 (viewport) (cdrawn)]]	;-- only use clipping when required! (for drop-down)
		compose/only [(cdrawn) (compose-map/only space/map reduce [hscroll vscroll])]
	]
		
	declare-template 'scrollable/space [
		;@@ make limits a block to save some RAM?
		; limits: 50x50 .. none		;-- in case no limits are set, let it not be invisible
		
		;; at which point `content` to place: >0 to right below, <0 to left above:
		origin:       (0,0)
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

		into: func [xy [planar!] /force child [object! none!]] [
			~/into self xy child
		]
		
		viewport: does [								;-- much better than subtracting scrollers; avoids exposing internal details
			any [all [map/2 map/2/size] size]			;@@ REP #113
		] #type [function!]

		;@@ move these into kit
		move-by: func [
			"Offset viewport by a fixed amount"
			amount [word! integer!] "'line or 'page or offset in pixels"
			dir    [word!]          "'forth or 'back"
			axis   [word!]          "'x or 'y"
			/scale factor [number!] "Default: 0.8 for page, 1 for the rest"
			/no-clip "Allow showing empty regions external to window"
		][
			~/move-by self amount dir axis factor no-clip
		] #type [function!]

		move-to: func [
			"Ensure point XY of content is visible, scroll only if required"
			xy          [planar! word!]    "'head or 'tail or an offset pair"
			/margin mrg [linear! planar!] "How much space to reserve around XY (default: 0)"
			/no-clip "Allow showing empty regions external to window"
		][
			~/move-to self xy mrg no-clip
		] #type [function!]
		
		clip-origin: func [
			"Change the /origin facet, ensuring no empty area is shown"
			origin [point2D!] "Clipped between (viewport - scrollable/size) and (0,0)"
		][
			~/set-origin self origin no
		] #type [function!]
	
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

paragraph-ctx: context [
	~: self
	
	;@@ rich-text also splits after hyphen - should I do this too?
	whitespace!: charset " ^-"							;-- wrap on tabs as well, although it's glitch-prone (sizing is hard)
	non-space!: negate whitespace!
	
	#if linux? [										;@@ workaround for #5353
		caret-to-offset: function [face [object!] pos [integer!] /lower] [
			system/words/caret-to-offset/:lower face max 1 pos
		]
	]
	
	size-text2: function [layout [object!]] [					;@@ see #4841 on all kludges included here
		size1: to point2D! size-text layout
		size2: to point2D! caret-to-offset/lower layout length? layout/text	;-- include trailing whitespaces
		if layout/size [size2/x: min size2/x layout/size/x]		;-- but not beyond the allowed width
		max size1 size2
	]
	
	ellipsize: function [layout [object!] text [string!] canvas [point2D!]] [
		;; save existing buffer for reuse (if it's different from text)
		buffer: unless layout/text =? text [layout/text]
		len: length? text
		
		;; measuring "..." (3 dots) is unreliable
		;; because kerning between the last letter and first "." is not accounted for, resulting in random line wraps
		quietly layout/text: "...."
		ellipsis-width: first ellipsis-size: size-text layout
		canvas: max canvas ellipsis-size				;-- prevent canvas/y=0 from triggering ellipsization
		
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
			ellipsis-location: (max 0 canvas/x - ellipsis-width) . last-line-dy
			last-visible-char: -1 + offset-to-char layout ellipsis-location
			unless buffer [buffer: make string! last-visible-char + 3]
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
	lay-out: function [space [object!] canvas [point2D!] (0x0 +<= canvas) "positive!" ellipsize? [logic!] wrap? [logic!]] [
		canvas: subtract-canvas canvas mrg2: space/margin * 2
		width:  canvas/x								;-- should not depend on the margin, only on text part of the canvas
		;; cache of layouts is needed to avoid changing live text object! ;@@ REP #124
		layout: new-rich-text
		; layout: any [space/layouts/:width  space/layouts/:width: new-rich-text]	@@ this creates unexplainable random glitches!
		unless empty? flags: space/flags [
			;@@ unfortunately this way 'wrap & 'ellipsize cannot precede low-level flags, or pair test fails
			flags: either pair? :flags/1 [				;-- flags may be already provided in low-level form 
				copy flags
			][
				compose [(1 thru length? space/text) (space/flags)]
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
			quietly layout/size:  max (1,1) canvas
			quietly layout/extra: ellipsize layout (as string! space/text)
				either wrap? [canvas][canvas * 1x0]		;-- without wrapping should be a single line
		][
			;; normal mode prioritizes words, so have to estimate min. width from the longest word
			quietly layout/size: infxinf
			if all [wrap? canvas/x < 1.#inf] [			;@@ perhaps this too should be a flag?
				words: append clear "" as string! space/text
				trail: any [find/last/tail words non-space!  words]
				parse/case/part words [any [to whitespace! p: skip (change p #"^/")]] trail
				quietly layout/text: words				;@@ memoize results?
				min-width: (1,0) * size-text2 layout
				quietly layout/size: max (1,1) max canvas min-width
			]
			quietly layout/text:  copy as string! space/text	;-- copy so it doesn't update its look until re-rendered!
			; system/view/platform/update-view layout
			;; NOTE: #4783 to keep in mind
			quietly layout/extra: size-text2 layout		;-- 'size-text' is slow, has to be cached (by using on-change)
		]
		quietly space/layout: layout					;-- must return layout
	]

	;; can be styled but cannot be accessed (and in fact shared)
	;; because there's a selection per every row - can be many in one rich-content
	;@@ unify this with /clone and rich-content
	selection-prototype: make-space 'rectangle [
		type: 'selection
		cache: none										;-- this way I can avoid cloning /cached facet
	]
	draw-box: function [xy1 [planar!] xy2 [planar!]] [
		selection: copy selection-prototype
		quietly selection/size: (to point2D! xy2) - xy1
		compose/only [translate (xy1) (render selection)]		;@@ need to avoid allocation
	]
	
	draw: function [space [object!] canvas: infxinf [point2D! none!]] [	;-- text ignores fill flags
		space/sec-cache: copy []						;-- reset computed sections
		if canvas/x < 1.#inf [							;-- no point in wrapping/ellipsization on inf canvas
			ellipsize?: find space/flags 'ellipsize
			wrap?:      find space/flags 'wrap
		]
		layout:   space/layout
		|canvas|: either any [wrap? ellipsize?][
			constrain canvas space/limits
		][
			infxinf
		]
		layout: lay-out space |canvas| to logic! ellipsize? to logic! wrap?

		;; size can be adjusted in various ways:
		;;  - if rendered < canvas, we can report either canvas or rendered
		;;  - if rendered > canvas, the same
		;; it's tempting to use canvas width and rendered height,
		;; but if canvas is huge e.g. 2e9, then it's not so useful,
		;; so just the rendered size is reported
		;; and one has to wrap it into a data-view space to stretch
		mrg2: 2 * mrg: space/margin
		text-size: max (0,0) (constrain layout/extra + mrg2 space/limits) - mrg2	;-- don't make it narrower than min limit
		space/size: mrg2 + text-size					;@@ full size, regardless if canvas height is smaller?
		#debug sizing [#print "paragraph=(space/text) on (canvas) -> (space/size)"]
		
		;; this is quite hacky: rich-text is embedded directly into draw block
		;; so when layout/text is changed, we don't need to call `draw`
		;; just reassigning host's `draw` block to itself is enough to update it
		;; (and we can't stop it from updating)
		;; direct changes to /text get reflected into /layout automatically long as it scales
		;; however we wish to keep size up to date with text content, which requires a `draw` call
		drawn: compose [text 0x0 (layout)]
		
		if caret: space/caret [
			unless caret/parent =? space [render caret]	;-- this lets caret invalidation (e.g. /visible? change) propagate to text
			if all [caret/visible?  not ellipsize?] [
				box: caret->box space caret/offset caret/side
				quietly caret/size: caret/size/x . second box/2 - box/1	;@@ need an option for caret to be of char's width
				invalidate/only caret
				cdrawn: render caret
				drawn: compose/only [push (drawn) translate (box/1) (cdrawn)]
			]
		]
		;; add selection if enabled
		if all [sel: space/selected  not ellipsize?] [	;@@ I could support selection on ellipsized, but is there a point?
			boxes: batch space [frame/item-boxes sel/1 sel/2]
			sdrawn: make [] 1.5 * length? boxes
			foreach [xy1 xy2] boxes [append sdrawn draw-box xy1 xy2]	;@@ use map-each
			drawn: compose/only [push (drawn) (sdrawn)]
		]
		compose/only [translate (mrg) (drawn)]
	]
	
	get-layout: function [space [object!]] [
		any [space/layout  ERROR "(space/type) wasn't rendered with text=(mold/part space/text 40)"]
	]
	
	caret->box: function [space [object!] offset [integer!] side [word!]] [
		layout: get-layout space
		offset: clip offset 0 n: length? space/text
		index:  clip 1 n offset + pick [0 1] side = 'left
		;; line feed in rich text belongs to the upper line, so caret after it can only have right side:
		if all [layout/text/:index = #"^/" offset = index] [index: min n index + 1]
		box: batch space [frame/item-box index]
		;; make caret box of zero width:
		either left?: index = offset [box/1/x: box/2/x][box/2/x: box/1/x]
		box 
	]
			
	;; TIP: use kit/do [help self] to get help on it
	kit: make-kit 'text [
		clone:  does [clone-space space [text flags color margin weight font command]]
		format: does [copy space/text]
		
		;@@ space/text or space/layout/text here?
		;@@ what isn't drawn doesn't exist and using space/text may lead to offsets > current /size
		;@@ but space/layout/text is not where the edits take place and I want to be in sync with them
		;@@ it also depends if 'length' can be a valid call before space is rendered or not
		length: function ["Get text length"] [
			length? space/text
		]
		
		everything: function ["Get full range of text"] [		;-- used by macro language, e.g. `select everything`
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [
			all [sel: space/selected  sel/1 <> sel/2  sel]
		]
		
		select-range: function ["Replace selection" range [point2D! none!]] [
			space/selected: if range [clip range 0 length]
		]
		
		frame: object [
			line-count: function ["Get line count on last frame"] [
				rich-text/line-count? get-layout space
			]
			
			point->caret: function [
				"Get caret offset and side near the point XY on last frame"
				xy [planar!]
			][
				layout: get-layout space
				caret:  offset-to-caret layout xy			;-- these never fail if layout/text is set
				char:   offset-to-char  layout xy			;-- but -char may return 1 for empty text
				side:   pick [left right] caret > char
				compose [offset: (caret - 1) side: (side)]
			]
			
			caret-box: function [
				"Get box [xy1 xy2] for the caret at given offset and side on last frame"
				offset [integer!] side [word!] (find [left right] side)
			][
				~/caret-box space offset side
			]
			
			item-box: function [							;; named 'item' for consistency with rich text
				"Get box [xy1 xy2] for the char at given index on last frame"
				index [integer!]
			][
				layout: get-layout space
				index:  clip index 0 length
				xy1:    caret-to-offset       layout index 
				xy2:    caret-to-offset/lower layout index 
				reduce [xy1 xy2]
			]
			
			item-boxes: function [
				"Get boxes [xy1 xy2 ...] for all chars in given range on last frame (unifies subsequent boxes)"
				start [integer!] end [integer!]
			][
				layout: get-layout space
				order 'start 'end
				if start = end [return copy []]
				boxes: clear []
				xy1: caret-to-offset       layout start + 1
				xy2: caret-to-offset/lower layout start + 1
				for i start + 2 end [
					xy1': caret-to-offset       layout i
					xy2': caret-to-offset/lower layout i
					either all [								;@@ should grouping be optional?
						xy1'/x = xy2/x
						xy1'/y = xy1/y
						xy2'/y = xy2/y
					][
						xy2/x: xy2'/x
					][
						repend boxes [xy1 xy2]
						xy1: xy1' xy2: xy2'
					]
				]
				repend boxes [xy1 xy2]
				copy boxes
			]
			
			;@@ an issue with this function is that caret-to-offset returns result truncated to pair (integer)
			;@@ and then some rows in rich-paragraph may become offset by 1px, i.e. not perfectly aligned
			sections: function ["Get section widths on last frame as list of integers"] [
				layout: get-layout space
				mrg: space/margin/x
				case [
					not empty? sections: space/sec-cache ['done]	;-- already computed
					empty? space/text [
						if space/size/x > 0 [append sections space/size/x]
					]
					1 <> frame/line-count [						;-- avoid breaking multiline text
						#assert [not negative? space/size/x - (mrg * 2)]
						repend sections pick [
							[mrg space/size/x - (mrg * 2) mrg]
							[space/size/x]
						] mrg > 0
					]
					'else [
						spaces: clear []
						parse/case space/text [collect after spaces any [	;-- collect index interval pairs of all contiguous whitespace
							any non-space! s: any whitespace! e:
							keep (as-pair index? s index? e)
						]]										;-- it often produces an empty interval at the tail (accounted for later)
						
						if mrg > 0 [append sections mrg]
						right: 0
						foreach range spaces [
							left:  first caret-to-offset layout range/1
							if left <> right [append sections left - right]		;-- added as positive - chars up to the whitespace
							right: first caret-to-offset layout range/2
							if left <> right [append sections left - right]		;-- added as negative - whitespace chars
						]
						if mrg > 0 [append sections mrg]
						width: mrg * 2 + first size-text2 layout
						if 0.02 < left: space/size/x - width [append sections left]	;-- additional margin introduced by limits/min
					]
				]
				sections
			]
		];frame: object [
	];kit: make-kit [
	
	
	;@@ in the current design it is rendered by text, so can only be styled as field/text/caret, not field/caret
	;@@ should I move rendering into field? (need to consider document as well)
	declare-template 'caret/rectangle [
		cache:  none
		;; size/y should be set by parent's /draw to line-height
		size:   (1,10)
		width:  1		#type =? :invalidates [integer!] (width > 0)
						#on-change [space word value] [space/size/x: width]
		;; offset and side do not affect the caret itself, but serve for it's location descriptors within the parent
		offset: 0		#type =? :invalidates [integer!]
		side:  'right	#type =  :invalidates [word!] (find/case [left right] side)
		visible?: no	#type =? :invalidates [logic!]	;-- controls caret visibility (necessary focusable spaces wrapping field)
	]
	
 	declare-template 'text/space [
		kit:    ~/kit
		text:   ""		#type    :invalidates [any-string!]	;-- every assignment counts as space doesn't know if string itself changed
		flags:  []		#type    :invalidates [block!]	;-- [bold italic underline strike wrap] supported ;@@ typecheck that all flags are words
		;; NOTE: every `make font!` brings View closer to it's demise, so it has to use a shared font
		;; styles may override `/font` with another font created in advance 
		font:   none									;-- can be set in style, as well as margin
		color:  none									;-- placeholder for user to control
		margin: 0
		weight: 0										;-- no point in stretching single-line text as it won't change
		
		;; caret disabled by default, can be set to a caret space
		caret:     none	#type    :invalidates [object! (space? caret) none!]
		;; there's no /selection facet, because paragraph may have multiple selection boxes
		selected:  none	#type =? :invalidates [pair! none!]

		sec-cache: []	#type [block!]
		
		layout: none	#type [object! none!]			;-- last rendered layout, text size is kept in layout/extra
		quietly cache: [size layout sec-cache]
		quietly draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas]
	]

	;; unlike text, paragraph is wrapped
	declare-template 'paragraph/text [
		quietly weight: 1								;-- used by tube, should trigger a re-render
		quietly flags:  [wrap]
	]

	;; url is underlined in style; wrapped for it's often long
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
		; xy1 [point2D! none!]								;@@ unlikely window can be supported by general container
		; xy2 [point2D! none!]
		; canvas [point2D! none!]
	][
		; #assert [(none? xy1) = none? xy2]				;-- /only is ignored to simplify call in absence of `apply`
		len: cont/items/size
		#assert [len "container/draw works only for containers of limited items count"]
		
		drawn: make [] len * 6
		items: make [] len
		repeat i len [append items cont/items/pick i]	;@@ use map-each
		frame: make-layout type items settings
		foreach [_ geom] frame/map [
			pos: geom/offset
			siz: geom/size
			drw: take remove find geom 'drawn			;-- no reason to hold `drawn` in the map anymore
			#assert [drw]
			; skip?: all [xy2  not boxes-overlap?  pos pos + siz  0x0 xy2 - xy1]
			; unless skip? [
			org: any [geom/origin (0,0)]
			compose/only/deep/into [
				;; clip has to be followed by a block, so `clip` of the next item is not mixed with previous
				; clip (pos) (pos + siz) [			;-- clip is required to support origin ;@@ but do we need origin?
				translate (pos + org) (drw)
				; ]
			] tail drawn
			; ]
		]
		quietly cont/map: frame/map		;-- compose-map cannot be used because it renders extra time ;@@ maybe it shouldn't?
		cont/size: constrain frame/size cont/limits		;@@ is this ok or layout needs to know the limits?
		cont/origin: any [frame/origin (0,0)]
		compose/only [translate (negate cont/origin) (drawn)]
	]
	
	format-items: function [space [object!]] [
		list: map-each i space/items/size [				;-- copy what is visible (items), not what is present (content)
			item: space/items/pick i
			when select item 'format (item/format)		;-- omit items that cannot be formatted
		]
	]
	
	format: function [space [object!] separator [string!]] [
		list: format-items space
		unless empty? separator [list: delimit list separator]
		to {} list
	]
	
	kit: make-kit 'container [
		format: does [~/format space "^-"]
	]

	declare-template 'container/space [
		kit:     ~/kit
		origin:  (0,0)									;-- used by ring layout to center itself around the pointer
		content: []		#type :invalidates 				;-- no type check as user may redefine it and /items freely
		
		items: func [/pick i [integer!] /size] [
			#assert [block? content]					;-- check type in the default items provider instead
			either pick [content/:i][length? content]
		] #type :invalidates [function!]
		
		map:   []
		cache: [size map]
		into: func [xy [planar!] /force child [object! none!]] [
			into-map map xy + origin child
		]

		draw: func [
			; /on canvas [point2D! none!]					;-- not used: layout gets it in settings instead
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
		
	;; map generally has no direction, but list map has, and it can be leveraged
	into: function [list [object!] xy [planar!] item [object! none!]] [
		if item [return into-map list/map xy item]
		y: list/axis
		i: first search/mode/for i: 1 half length? list/map [
			geom: pick list/map i * 2
			geom/offset/:y
		] 'interp xy/:y
		set [item: geom:] skip list/map i - 1 * 2
		; ?? [i geom/offset geom/size xy]
		xy: xy - geom/offset
		if xy +< geom/size [reduce [item xy]]
	]
	
	get-sections: function [list [object!]] [
		case [
			not empty? cache: list/sec-cache ['done]
			list/size/x = 0 ['done]						;-- nothing to dissect (not rendered?)
			list/axis <> 'x	[							;-- can't dissect vertical list
				if 0 <> mrg: list/margin/x [repend cache [mrg mrg]]
			]
			'else [generate-sections list/map list/size/x cache]
		]
		cache
	]

	kit: make-kit 'list [
		clone: function [] [		
			cloned: clone-space space [axis margin spacing]	;-- no /origin since that is state
			clone: []									;-- used when item is not cloneable
			foreach item space/content [
				;@@ is it ok to skip non cloneable items silently?
				append cloned/content batch item [clone]
			]
			cloned
		]
		format: does [container-ctx/format space select [x "^-" y "^/"] axis]
		frame: object [
			sections: does [~/get-sections space]
		]
	]

	draw: function [list [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [		
		list/sec-cache: copy []							;-- reset computed sections
		settings: with list [axis margin spacing canvas fill-x fill-y limits]
		list/container-draw/layout 'list settings
	]
		
	declare-template 'list/container [
		kit:       ~/kit
		size:      (0,0)	#type [point2D! (0x0 +<= size) none!]		;-- 'none' to allow infinite lists
		axis:      'x		#type =  :invalidates [word!] (find [x y] axis)
		;; default spacing/margins must be tight, otherwise they accumulate pretty fast in higher level widgets
		margin:    0
		spacing:   0

		sec-cache: []
		frame:     []									;-- last frame parameters used by kit and list-view
		cache:     [size map frame sec-cache]			;@@ put sec-cache into container or not?
		
		into: func [xy [planar!] /force item [object! none!]] [~/into self xy item]
		container-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

ring-ctx: context [
	~: self
	
	declare-template 'ring/container [
		;; in degrees - clockwise direction to the 1st item (0 = right, aligns with math convention on XY space)
		angle:  0	#type =  :invalidates-look [linear!]
		;; minimum distance (pixels) from the center to the nearest point of arranged items
		radius: 50	#type =  :invalidates [linear!]
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

	kit: make-kit 'tube [
		format: function [] [
			list: container-ctx/format-items space
			if find [n w ↑ ←] space/axes/1 [list: reverse list]
			list: delimit list either find [e w → ←] space/axes/1 ["^-"]["^/"]
			to {} list
		]
	]

	draw: function [tube [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [		
		settings: with tube [margin spacing align axes canvas fill-x fill-y limits]
		drawn:  tube/container-draw/layout 'tube settings
		#debug sizing [#print "tube with (tube/content/type) on (mold canvas) -> (tube/size)"]
		drawn
	]
		
	declare-template 'tube/container [
		kit:     ~/kit
		margin:  0
		spacing: 0
		align:   -1x-1	#type :invalidates-look =? [pair!] (-1x-1 +<= align +<= 1x1)
		axes:    [e s]	#type :invalidates [block!]
						(find/only [					;-- literal listing allows it to appear in the error output
							[n e] [n w]  [s e] [s w]  [e n] [e s]  [w n] [w s]
							[→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←]
						] axes)
		
		container-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


rich-paragraph-ctx: context [							;-- rich paragraph
	~: self

	;; returned point always belongs to the nearest space
	;; 2D: x<0 and x>size/x: projected onto x=0 and x=size/x
	;;     y<0 and y>size/y: these points cannot be meaningfully "unrolled" into x, since height of non-existing rows is unset
	;;       so mapping projects y<0 to y=0 and y>size/y to y=size/y
	;;     y between rows is projected onto the upper row
	;; 1D: x is clipped within [0 size-1D/x]
	;@@ another way is to project y<0 to 0x0 and y>size/y to size - need to think what's better UX-wise
	map-2D->1D: function [
		"Translate a point in 2D (rolled) space into a point in 1D (map) space"
		frame [object!] "Rendered frame data"
		xy    [planar!] "Margin must be subtracted already"
	][
		if empty? frame/map [return (0,0)]
		set-pair [x: y:] xy
		x-2D: clip x 0 frame/size-2D/x
		y-2D: clip y 0 frame/size-2D/y
		rows-above: reproject/truncate frame/y2D->row y-2D
		x-1D': rows-above * frame/size-2D/x + x-2D
		x-1D': clip x-1D' 0 frame/size-1D'/x
		x-1D:  reproject/inverse frame/x1D->x1D' x-1D'
		y0-2D: pick frame/y-levels rows-above * 3 + 1
		y-1D:  clip (y-2D - y0-2D) 0 frame/size-1D/y
		(x-1D . y-1D)
	]
	
	map-x1D->x1D': function [
		frame [object!] "Rendered frame data"
		x-1D  [linear!]
		side  [word!] (find [left right] side) "Skip indentation to left or to right"
	][
		#assert [all [0 <= x-1D x-1D <= frame/size-1D/x]  "Map point must be within total size"]
		apply 'reproject [frame/x1D->x1D' x-1D /up side = 'right]
	]
	
	map-x1D'->row: function [
		"Translate an X offset (without margin) in 1D' (unrolled) space into a closest row number"
		frame [object!]      "Rendered frame data"
		x-1D' [linear!]
		side  [word!] (find [left right] side) "Map contested points to previous or next row"
	][
		rows-above: to integer! rows-above': x-1D' / frame/size-2D/x
		if rows-above = rows-above' [					;-- contested pixel
			rows-above: either side = 'left
				[rows-above - 1]
				[min rows-above frame/nrows - 1]
		]
		1 + max 0 rows-above
	]
	
	map-x1D->row: function [
		"Translate an X offset (without margin) in 1D (map) space into a closest row number"
		frame [object!]      "Rendered frame data"
		x     [linear!]
		side  [word!] (find [left right] side) "Map contested points to previous or next row"
	][
		#assert [all [0 <= x x <= frame/size-1D/x]  "Map point must be within total size"]
		x-1D': map-x1D->x1D' frame x side
		map-x1D'->row frame x-1D' side
	]
	
	;@@ move these funcs into layout/paragraph?
	;; returned point's Y is projected into the 2D row (which is generally smaller than size-1D/y)
	map-1D->2D: function [
		"Translate a point in 1D (map) space into a point in 2D (rolled) space (without margin)"
		frame [object!]      "Rendered frame data"
		xy    [planar!]
		side  [word!] (find [left right] side) "Map contested points to previous or next row"
	][
		if empty? frame/map [return (0,0)]
		set-pair [x-1D: y-1D:] xy
		#assert [all [0 <= x-1D x-1D <= frame/size-1D/x]  "Map point must be within total size"]
		x-1D': map-x1D->x1D' frame x-1D side
		rows-above: -1 + map-x1D'->row frame x-1D' side
		x-2D: x-1D' - (frame/size-2D/x * rows-above)	;-- modulo doesn't work due to left/right duality
		#assert [x-2D >= 0]
		set [y0-2D: y1-2D: y2-2D:] skip frame/y-levels rows-above * 3
		#assert [y0-2D]
		y-2D:  clip y1-2D y2-2D (y0-2D + y-1D)			;-- do not let it step into other rows
		; ?? [rows-above x-1D' side x-2D y-2D]
		(x-2D . y-2D)
	]
	
	;; return row number for the row that is closest to a 2D point
	;@@ or return none if outside the row?
	map-2D->row: function [
		"Translate a point (without margin) in 2D (rolled) space into a closest row number"
		frame [object!]      "Rendered frame data"
		xy    [planar!]
	][
		y-2D: clip xy/y 0 frame/size-2D/y
		1 + reproject/truncate frame/y2D->row xy/y
	]
	
	map-row->box: function [
		"Get a box [XY1 XY2] in 2D (rolled) space (without margin and skipping indent) bounding the given row number"
		frame [object!]  "Rendered frame data"
		row   [integer!] (row >= 1)
		;@@ need a refinement for indent inclusion? it should be as easy as setting xy1/x: 0 though
	][
		#assert [not empty? frame/map  "no rows available"]
		set [y0: y1: y2:] skip frame/y-levels row - 1 * 3
		offset-1D': row - 1 * width: frame/size-2D/x
		;; simplest thing would be to locate row in 2D and map it to 1D and back, but that's ambiguous for zero-height rows
		;; so I need to use 1D'->1D->1D' mapping to detect and skip indentation
		x1-1D:  reproject/inverse frame/x1D->x1D' x1-1D': offset-1D'
		x2-1D:  reproject/inverse frame/x1D->x1D' x2-1D': min (offset-1D' + width) frame/size-1D'/x
		x1-1D': reproject/up      frame/x1D->x1D' x1-1D
		x2-1D': reproject         frame/x1D->x1D' x2-1D
		xy1: x1-1D' - offset-1D' . y1
		xy2: x2-1D' - offset-1D' . y2
		reduce [xy1 xy2]
	]
	
	;; unlike /into this always succeeds if there's a child
	;@@ base /into on this
	locate-child: function [
		"Find a child closest to XY and return: [child child-xy child-2D-origin]"
		space [object!] xy [planar!] "Margin must be subtracted already"
	][
		frame: space/frame
		if empty? frame/map [return none]
		xy: xy - frame/margin
		xy-1D: map-2D->1D frame xy
		map: skip frame/map 2 * reproject/truncate frame/x1D->map xy-1D/1
		if tail? map [map: skip map -2]					;-- map last x1D to last child
		set [child: geom:] map
		#assert [child]
		oxy-2D: map-1D->2D frame geom/offset 'right
		child-xy: xy-1D - geom/offset					;-- point in the child is in 1D space (it can be wrapped!)
		reduce [child child-xy oxy-2D + frame/margin]
	]
		
	;; /map is kept in 1D space, so /into is required for translation from 2D
	into: function [space [object!] xy [planar!] child [object! none!]] [
		unless frame: space/frame [return none]
		;; /frame holds rows data as well alignment and margin used to draw these rows
		;; without it, there's a risk that /into could operate on changed facets not yet synced to rows
		xy-2D: (to point2D! xy) - frame/margin
		either child [
			child-xy: (0,0)
			if geom: select/same frame/map child [		;-- can be none if content changed (see %hovering.red)
				oxy-2D: map-1D->2D frame geom/offset 'right
				child-xy: xy-2D - oxy-2D
			]
			reduce [child child-xy]
		][
			xy-1D:  map-2D->1D frame xy-2D
			xy'-2D: map-1D->2D frame xy-1D 'right		;@@ what side argument to use? doesn't matter?
			; ?? [xy-1D xy-2D xy'-2D]
			if all [									;-- if xy is within 1D range, it back-projects into itself
				xy-2D/1 ~= xy'-2D/1						;-- neglect the rounding error from double conversion
				xy-2D/2 ~= xy'-2D/2
			][
				map: skip frame/map 2 * reproject/truncate frame/x1D->map xy-1D/x
				set [child: geom:] map
				if child [								;-- x-1D = size-1D/x leads to the tail
					child-xy: xy-1D - geom/offset
					if child-xy +< geom/size [reduce [child child-xy]]
				] 
			] 
		]
	]
		
	get-sections: function [space [object!]] [
		if empty? cache: space/sec-cache [
			mrg: space/margin/x							;-- make margin significant
			if 0 <> mrg [append cache mrg]
			if space/frame/nrows = 1 [					;-- not empty or multiline text (/nrows can be none if not rendered)
				append cache space/frame/sections
			]
			if 0 <> mrg [append cache mrg]
		]
		cache
	]
	
	kit: make-kit 'rich-paragraph [
		frame: object [
			sections: does [~/get-sections space]
		]
		format: does [container-ctx/format space ""]
	]
		
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		space/sec-cache: copy []						;-- reset computed sections
		settings: with space [margin spacing align baseline canvas fill-x fill-y limits indent force-wrap?]
		frame: make-layout 'paragraph :space/items settings
		size: (2,2) * space/margin + frame/size-2D
		quietly space/frame: frame
		quietly space/size:  constrain size space/limits	;-- size may be bigger than limits if content doesn't fit
		quietly space/map:   frame/map
		frame/drawn
	]
	
	;; a paragraph layout composed out of spaces, used as a base for higher level rich-content
	declare-template 'rich-paragraph/container [
		kit:         ~/kit
		margin:      0
		spacing:     0		#type =? [integer!] :invalidates	;-- has only vertical row spacing; do not turn it into pair!
		align:       'left	#type = [word!] :invalidates		;-- horizontal alignment
		baseline:    80%	#type = [float! percent!] :invalidates-look		;-- vertical alignment in % of the height
		weight:      1									;-- non-zero default so tube can stretch it
		indent:      none								;-- indent of the paragraph: [first: integer! rest: integer!]
			#type = [block! (parse indent [2 [set-word! integer!]]) none!] :invalidates
		force-wrap?: no		#type =? [logic!] :invalidates		;-- allow splitting words at *any pixel* to ensure canvas is not exceeded
		
		frame:       []		#type  [object! block!]				;-- internal frame data used by /into
		sec-cache:   []
		cache:       [size map frame sec-cache]
		into: func [xy [planar!] /force child [object! none!]] [~/into self xy child]
		
		;; container-draw is not used due to tricky geometry
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


rich-content-ctx: context [								;-- rich content
	~: self
	
	;; returns all xy1-xy2 boxes of carets on 1D space - only empty if no spaces / caret locations, otherwise 2+ boxes
	;@@ or should it just put them into frame?
	;@@ can this be part of the layout? probably not, since uses source data
	list-carets: function [map [block!] ranges [hash! block!]] [
		boxes: clear []
		foreach [child geom] map [
			range: select/same ranges child
			#assert [select/same ranges child]
			xy2: (0,1) * geom/size + xy1: geom/offset
			either 1 >= n: span? range [
				if n = 1 [repend boxes [xy1 xy2]]		;-- span can be zero (empty text), it's not counted then 
			][
				#assert [object? select child 'layout]
				#assert [1 = rich-text/line-count? child/layout]
				xy2: xy1 + (0 . rich-text/line-height? child/layout 1)		;-- caret of line size, ignoring margin
				repeat i n [
					offset: caret-to-offset child/layout i 
					repend boxes [xy1 + offset xy2 + offset]
				]
			]
		]
		offset: 1x0 * geom/size
		repend boxes [xy1 + offset xy2 + offset]		;-- n+1 carets for n items, always at least 1 caret
		copy boxes
	]
	    
	caret->box-1D: function [
		"Get [XY1 XY2] box in 1D space for caret at given offset"
		space [object!] caret [integer!]
	][
		boxes: any [
			space/frame/caret-boxes
			space/frame/caret-boxes: list-carets space/map space/ranges	;@@ remove ranges after this?
		]
		unless tail? boxes: skip boxes caret * 2 [		;-- returns none when outside of range or no carets allowed
			copy/part boxes 2
		]
	]
	
	caret->box-2D: function [
		"Get [XY1 XY2] box in 2D space (with margin) for caret at given offset"	;@@ or not add margin?
		space [object!] caret [integer!] side [word!] (find [left right] side)
	][
		if box-1D: caret->box-1D space caret [
			repeat i 2 [								;@@ use map-each
				xy: rich-paragraph-ctx/map-1D->2D space/frame box-1D/:i side
				box-1D/:i: space/frame/margin + xy
			]
			box-1D										;@@ result is pixel-rounded, need more precision?
		]
	]
	
	;@@ consider removing/splitting this func
	locate-point: function [space [object!] xy [planar!] "with margin"] [
		xy: xy - space/frame/margin
		if set [child: child-xy:] rich-paragraph-ctx/locate-child space xy [
			#assert [find/same space/ranges child]
			crange: select/same space/ranges child
			either 1 = span? crange [
				index: crange/2
				caret: pick crange child-xy/x < (child/size/x / 2)
			][
				index: crange/1     + offset-to-char  child/layout child-xy
				caret: crange/1 - 1 + offset-to-caret child/layout child-xy
			]
			side: pick [left right] index = caret
			reduce [child child-xy index caret side]	;@@ what to return?
		]
	]
	
	xy->caret: function [space [object!] xy [planar!] "with margin"] [
		if found: locate-point space xy [found/4]
	]
	
	caret->row: function [
		"Get row number for specified caret offset (or none if no rows)" 
		space [object!]
		caret [integer!] (caret >= 0)
		side  [word!] (find [left right] side)
	][
		if empty? space/map [return none]
		;; tricky part is zero-height rows - cannot work in 2D space, only in 1D
		if box: caret->box-1D space caret [
			rich-paragraph-ctx/map-x1D->row space/frame box/1/x side	;@@ move mapping into space?
		]
	]
	
	row->box: function [
		"Get bounding box of row's content (offset by margin)"
		space [object!] row-number [integer!]
	][
		box: rich-paragraph-ctx/map-row->box space/frame row-number
		forall box [box/1: box/1 + space/frame/margin]	;@@ use map-each
		box
	]
	
	; ;; these are just `copy`ed, since it's 5-10x faster than full `make-space`
	; linebreak-prototype: make-space 'break [#assert [cache = none]]	;-- otherwise /cached facet should be `clone`d
	; text-prototype:      make-space 'text []
	; link-prototype:      make-space 'link []
	
	;; can be styled but cannot be accessed (and in fact shared)
	;; because there's a selection per every row - can be many in one rich-content
	selection-prototype: make-space 'rectangle [
		type: 'selection
		cache: none										;-- this way I can avoid cloning /cached facet
	]
	
	draw-box: function [xy1 [planar!] xy2 [planar!]] [
		selection: copy selection-prototype
		quietly selection/size: xy2 - xy1
		compose/only [translate (xy1) (render selection)]
	]
	
	draw-selection: function [space [object!]] [
		if any [
			not sel: space/selected
			empty? space/data
		] [return []]
		if sel/1 > sel/2 [sel: reverse sel]
		;@@ this calls fill-row-ranges so many times that it must be super slow
		lrow: caret->row space sel/1 'left  1
		rrow: caret->row space sel/2 'right 1
		set [lcar1: lcar2:] caret->box-2D space sel/1 'left
		set [rcar1: rcar2:] caret->box-2D space sel/2 'right
		; ?? [sel lrow rrow lcar1 lcar2 rcar1 rcar2]
		#assert [lrow <= rrow]
		either lrow = rrow [
			draw-box lcar1 rcar2
		][
			collect [
				set [lrow1: lrow2:] row->box space lrow
				keep draw-box lcar1 lrow2
				for irow lrow + 1 rrow - 1 [
					set [row1: row2:] row->box space irow
					if row1/y < row2/y [				;-- ignore empty lines
						keep draw-box row1 row2
					]
				] 
				set [rrow1: rrow2:] row->box space rrow
				keep draw-box rrow1 rcar2
			]
		]
	]
	
	draw-caret: function [space [object!]] [
		unless all [caret: space/caret  caret/visible?] [return []]
		box: batch space [frame/caret-box here caret/side]
		; ?? [caret/offset caret/side box] 
		#assert [not empty? box]
		#assert [box/1/y < box/2/y]
		quietly caret/size: box/2 - box/1 + (caret/width . 0)
		invalidate/only caret
		drawn: render caret
		compose/only [translate (box/1) (drawn)]
	]
		
	;; adds selection and caret
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		drawn: space/rich-paragraph-draw/on canvas fill-x fill-y
		if space/selected [
			sdrawn: draw-selection space
			drawn: reduce [sdrawn drawn]
		]
		if space/caret [
			cdrawn: draw-caret space
			drawn: reduce ['push drawn cdrawn]
		] 
		drawn
	]
	
	kit: make-kit 'rich-content/rich-paragraph [
		;@@ same Q as for text, length on the frame or length of data?
		length: function ["Get length in items"] [
			half length? space/data
		]
		
		everything: function ["Get full range of text"] [		;-- used by macro language, e.g. `select-range everything`
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [	;-- used by macro language, e.g. `remove-range selected`
			all [sel: space/selected  sel/1 <> sel/2  sel]
		]
		
		here: function ["Get current caret offset"] [
			space/caret/offset
		]
		
		frame: make frame [
			line-count: function ["Get line count on last frame"] [
				space/frame/nrows
			]
			
			point->caret: function [
				"Get caret offset and side near the point XY on last frame"
				xy [planar!]
			][
				set [_: _: index: offset:] ~/locate-point space xy
				side: pick [right left] offset < index
				compose [offset: (offset) side: (side)]
			]
			
			caret->row: function [
				"Get row number for the given caret location on last frame"
				offset [integer!] side [word!]
			][
				~/caret->row space offset side
			]
			
			caret-box: function [
				"Get box [xy1 xy2] for the caret at given offset and side on last frame"
				offset [integer!] side [word!] (find [left right] side)
			][
				~/caret->box-2D space offset side
			]
			
			row-box: function [
				"Get box [xy1 xy2] for the given row on last frame"
				row [integer!]
			][
				~/row->box space row
			]
		]
		
		locate: function [
			"Get offset of a named location"
			name [word!]
		][
			switch/default name [
				head [0]
				tail [length]
			][here]
		]	
		
		format: does [rich/source/format space/data]	;@@ should this format be so different from rich-paragraph's one?
		
		clone: function [] [		
			cloned: clone-space space [margin spacing align baseline weight color font indent force-wrap?]
			clone: none									;-- used when item is not cloneable
			cloned/data: map-each/eval [item [object!] code] space/data [	;-- data may contain spaces
				when item: batch item [clone] [item code]		;-- not cloneable spaces are skipped! together with the code
			]													;-- triggers on-data-change
			cloned
		]
		
		;@@ should source support image! in its content? url! ? anything else?
		deserialize: function [
			"Set up paragraph with high-level dialected data"
			source [block!]
		][
			space/data: rich/source/deserialize source			;-- triggers on-data-change
		]
		serialize: function ["Convert paragraph data into high-level dialected data"] [
			rich/source/serialize space/data
		]
		
		reload: function ["Reload content from data"] [space/data: space/data]	;-- triggers on-data-change
	
		select-range: function [
			"Replace selection"
			range [pair! none!]
		][
			space/selected: if range [clip range 0 length]
		]
	
		pick-attrs: function [
			"Get attributes code for the item at given index"
			index [integer!]
		][
			if code: pick space/data index * 2 [rich/index->attrs code]
		]
		
		pick-attr: function [
			"Get chosen attribute's value for the item at given index"
			index [integer!] attr [word!]
		][
			if code: pick space/data index * 2 [rich/attributes/pick code attr]
		]
		
		;@@ I hate these -range and -items suffixes but without them there's too much risk of name shadowing
		;@@ adding a sigil to all (or only some) funcs is no better
		copy-range: function [
			"Extract and return given range of data"
			range [pair!] /text "Extract as plain text"
		][
			range: clip range 0 length					;-- avoid overflow on inf * 2
			slice: copy/part space/data range * 2 + 1
			if text [slice: rich/source/format slice]
			slice
		]
		
		mark-range: function [
			"Change attribute value over given range"
			range [pair! none!] attr [word!] value "If falsey, attribute is cleared"
		][
			unless all [range  range/1 <> range/2] [exit]
			rich/attributes/mark space/data range attr :value
			reload
		]
	
		insert-items: function [
			"Insert items at given offset"
			offset [word! integer!]
			items  [
				object! (space? items)					;-- rich-content not inlined! for inlining use `insert! ofs para/data`
				block!  (even? length? items)
				string!
			]
		][
			if word? offset [offset: locate offset]
			case [
				object? items [items: reduce [items 0]]	;-- items are not auto-cloned! so undo/redo may work on *same* items
				string? items [items: zip explode items 0]
			]
			offset: clip offset 0 length
			insert skip space/data offset * 2 items
			reload
		]
	
		remove-range: function [
			"Remove given range of items"
			range [pair! none!]
		][
			unless all [range  range/1 <> range/2] [exit]		;-- for `remove selected` transparency
			range: clip range 0 length
			remove/part skip space/data range/1 * 2 2 * span? range
			reload
		]
	
		change-range: function [
			"Remove given range and insert items there"
			range [pair!]
			items [
				object! (space? items)					;-- rich-content not inlined! for inlining use `insert! ofs para/data`
				block!  (even? length? items)
				string!
			]
		][
			remove-range range
			insert-items range/1 items
		]
		
		clip-range: function [
			"Leave only given range of items, removing the rest"
			range [pair!]
		][
			range: clip range 0 length
			if range <> everything [
				space/data: copy/part space/data range * 2 + 1
			]
			space/data
		]
	
	];kit: make-kit 'rich-content/rich-paragraph [
		
	on-data-change: function [space [object!] word [word!] data [block!]] [
		;@@ maybe postpone all this until next render?
		set with space [content ranges] rich/source/to-spaces data	;-- /content triggers invalidation
		if empty? space/content [						;-- let rich-content always have at least one line (mainly for document)
			obj: make-space 'text []					;@@ use prototype for this?
			obj/font: space/font
			append space/content obj
			repend space/ranges [obj 0x0]
		]
	]
	
	;; unlike rich-paragraph, this one is text-aware, so has font and color facets exposed for styling
	;; also since it can count items, it supports /selected and /caret (impossible in rich-paragraph)
	declare-template 'rich-content/rich-paragraph [
		kit:         ~/kit
		color:       none												;-- color & font defaults are accounted for in style
		font:        none
		selected:    none	#type =? [pair! none!] :invalidates-look	;-- current selection (set programmatically - use event handlers)
		
		;; caret disabled by default, can be set to a caret space
		caret:       none	#type [object! (space? caret) none!] :invalidates	
		
		;; user may override this to carry attributes (bold, italic, color, font, etc) to a space from the /source
		;@@ need to think more on this one - disabled for now
		; apply-attributes: func [space [object!] attrs [map!]] [space]	#type [function!]
		
		;; internal data [item code ...], generated by decode or from edit operations
		;; ranges preserve info about what spaces were 'single' in the source, and what spaces were created from text
		;; so caret can skip the single ones but dive into the created ones
		ranges:  [] #type [block! hash!]				;-- filled by on-data-change
		;; ranges have to come before /data or empty block assignment resets them!
		data:    []	#type [block!] (even? length? data) :on-data-change		
		
		rich-paragraph-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


rich-text-span!: make clipboard/text! [
	name:   'rich-text-span
	data:   []
	length: does [half length? data]
	format: function [] [
		to format: {} map-each [item [object!]] extract data 2 [
			batch item [format]
		]
	]
	copy:  does [remake rich-text-span! [data: (system/words/copy data)]]
	clone: function [] [
		clone: none										;-- used when item has no /clone
		data: map-each/eval [item [object!] code] self/data [
			item: batch item [clone]
			when item [item code]						;-- not cloneable spaces are skipped! together with the code
		]
		remake rich-text-span! [data: (data)]
	]
]


switch-ctx: context [
	~: self
	
	declare-template 'switch/space [
		state: off		#type =? :invalidates-look [logic!]
		; command: []
		data: make-space 'data-view []	#type (space? data)		;-- general viewer to be able to use text/images
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			also data/draw/on canvas fill-x fill-y		;-- draw avoids extra 'data-view' style in the tree
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
		all [
			space/content
			in space/content 'font
			maybe/same space/content/font: space/font	;-- should trigger invalidation when changed
		]
	]
	
	push-flags: function [space [object!]] [
		all [
			space/content
			in space/content 'flags
			maybe space/content/flags: space/flags		;-- should trigger invalidation when changed
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
		
		;; used by button to expose text styles
		flags: []	#on-change [space word value] [push-flags space]
		
		;@@ remove this wrap and use flags/wrap?
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
		from      [linear!]
		requested [linear!]
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
	draw: function [window [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		#debug grid-view [#print "window/draw is called on canvas=(canvas)"]
		unless content: window/content [
			set-empty-size window canvas fill-x fill-y
			return quietly window/map: []
		]
		#assert [space? content]
		;; there's no size for infinite spaces so pages*canvas is used as drawing area
		;; no constraining by /limits here, since window is not supposed to be limited ;@@ should it be constrained?
		size: (finite-canvas canvas) * window/pages
		unless zero? area? size [						;-- optimization ;@@ although this breaks the tree, but not critical?
			-org: negate window/origin
			;@@ maybe off fill flags when window is less than content? or off them always?
			cdraw: render/window/on content -org -org + size canvas fill-x fill-y
			;; window/origin may have been modified by render of content! (e.g. list-view)
			
			;; once content is rendered, its size is known and may be less than requested,
			;; in which case window should be contracted too, else we'll be scrolling over an empty window area
			if content/size [							;-- size has to be finite
				size: clip (0,0) size content/size + window/origin
			]
		]
		#debug sizing [if window/size <> size [#print "resizing window to (size)"]]
		window/size: size
		;; map should never contain infinite sizes: clip the drawn child area to window
		mapsize: size - window/origin
		quietly window/map: compose/deep [(content) [offset: (window/origin) size: (mapsize)]]
		when cdraw (compose/only [translate (window/origin) (cdraw)])
	]
	
	declare-template 'window/space [
		;; window size multiplier in canvas sizes (= size of inf-scrollable)
		;; when drawn, auto adjusts it's `size` up to `canvas * pages` (otherwise scrollbars will always be visible)
		pages:   10x10	#type = :invalidates [planar! linear!]
		origin:  (0,0)									;-- content's offset (negative)
		
		;; window does not require content's size, so content can be an infinite space!
		content: none	#type =? :invalidates [object! none!]
		
		map:     []
		cache:   [size map]
		
		available?: func [
			"Returns number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
			axis      [word!]    "x/y"
			dir       [integer!] "-1/1"
			from      [linear!] "axis coordinate to look ahead from"
			requested [linear!] "max look-ahead required"
		][
			~/available? self axis dir from requested
		] #type [function!]
	
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

inf-scrollable-ctx: context [
	~: self
	
	;; must be called from within render so `available?`-triggered renders belong to the tree and are styled correctly
	slide: function [space [object!]] [
		#debug grid-view [#print "origin in inf-scrollable/slide: (space/origin)"]
		window: space/window
		unless find/same/only space/map window [exit]	;-- likely window was optimized out due to empty canvas 
		wofs': wofs: negate window/origin				;-- (positive) offset of window within its content
		#assert [window/size]
		wsize:  window/size
		before: negate space/origin						;-- area before the current viewport offset
		#assert [find/same space/map window]			;-- slide attempt on an empty viewport, or map is invalid?
		viewport: space/viewport
		#assert [0x0 +< viewport]						;-- slide on empty viewport is most likely an unwanted slide
		if zero? area? viewport [return no]
		after:  wsize - (before + viewport)				;-- area from the end of viewport to the end of window
		; ?? [before after space/look-around wsize viewport space/origin window/origin]
		foreach x [x y] [
			any [										;-- prioritizes left/up slide over right/down
				all [
					before/:x <= space/look-around
					0 < avail: window/available? x -1 wofs/:x space/slide-length
					wofs'/:x: wofs'/:x - avail
				]
				all [
					after/:x  <= space/look-around
					0 < avail: window/available? x  1 wofs/:x + wsize/:x space/slide-length
					wofs'/:x: wofs'/:x + avail
				]
			]
		]
		;; transfer offset from scrollable into window, in a way detectable by on-change
		if wofs' <> wofs [
			;; effectively viewport stays in place, while underlying window location shifts
			#debug sizing [#print "sliding (space/size) with (space/content) by (wofs' - wofs)"]
			space/origin: space/origin + (wofs' - wofs)	;-- may be watched (e.g. by grid-view)
			window/origin: negate wofs'					;-- invalidates both scrollable and window
			wofs' - wofs								;-- let caller know that slide has happened
		]
	]
	
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		#debug sizing [#print "inf-scrollable draw is called on (canvas)"]
		timer: space/slide-timer
		render timer									;-- timer has to appear in the tree for timers to work
		drawn: space/scrollable-draw/on canvas fill-x fill-y
		any-scrollers?: not zero? add area? space/hscroll/size area? space/vscroll/size
		timer/rate: either any-scrollers? [4][0]		;-- timer is turned off when unused
		;; scrollable/draw removes slide-timer, have to restore
		;; the only benefit of this is to count spaces more accurately:
		;; (can't use repend, as map may be a static block)
		quietly space/map: compose [
			(space/map)
			(timer) [offset (0,0) size (0,0)]
		]
		#debug sizing [#print "inf-scrollable with (space/content/type) on (mold canvas) -> (space/size) window: (space/window/size)"]
		#assert [any [not find/same space/map space/window  space/window/size]  "window should have a finite size if it's exposed"]
		drawn
	]
	
	declare-template 'inf-scrollable/scrollable [		;-- `infinite-scrollable` is too long for a name
		slide-length: 200	#type [integer!] (slide-length > 0)	;-- how much more to show when sliding (px) ;@@ maybe make it a pair?
		look-around: 50		#type [integer!] (look-around > 0)	;-- zone after head and before tail that triggers slide (px)
		;@@ percents of window height could be supported for look-around? and maybe for slide-length?

		content: window: make-space 'window []	#type (space? window)

		;; timer that calls `slide` when dragging
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		slide-timer: make-space 'timer [type: 'slide-timer]	#type (space? slide-timer)
		slide: does [~/slide self] #type [function!]

		scrollable-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


list-view-ctx: context [
	~: self

	;; constant passed into list layout, just easier to put it here than in draw and available funcs
	;; forbids list width extension by largest item (otherwise width will depend on window/origin, leading to weird UX)
	do-not-extend?: yes								
	
	map-index->list-index: function [
		list      [object!]
		map-index [integer!] (all [0 < map-index map-index <= half length? list/map])
	][
		#assert [list/frame/anchor]
		anchor-item: list/items/pick anchor: list/frame/anchor
		anchor-pos: find/same/skip list/map anchor-item 2
		unless anchor-pos [return none]					;-- list may have been cleared, map not updated
		anchor-map-index: half 1 + index? anchor-pos
		anchor - anchor-map-index + map-index
	]
	
	available?: function [
		list      [object!]
		req-axis  [word!] (find [x y] req-axis)
		dir       [integer!] (1 = abs dir) 
		from      [linear!] 
		requested [linear!] (requested >= 0)
	][
        if req-axis <> list/frame/axis [				;-- along orthogonal axis list doesn't extend
        	return clip 0 requested either dir < 0 [from][list/frame/size/:req-axis - from]
        ]
        
        ;; choose temp. anchor item closest to the direction we're looking out into (avoids redrawing the whole window!)
        set [anchor-item: anchor-geom:] either dir < 0 [
        	map-index: 1
        	list/map
        ][
        	map-index: half length? list/map
        	list/map << 2
        ]
        #assert [anchor-item]
        y:        req-axis
        anchor:   map-index->list-index list map-index
        unless anchor [return 0]						;-- don't try sliding if list was cleared or updated in this frame
        margin:   list/frame/margin
        window:   list/parent
        frame:    construct list/frame					;-- for bind(with) to work
        reverse?: dir < 0
        ;; since 'from' may not align with the 'start' level, add the difference to requested 'length':
        ;; (this relies on list layout counting length *after* the anchor itself and not including the margins)
        start:    anchor-geom/offset/:y + either dir > 0 [anchor-geom/size/:y][0]	;-- from where length is counted
        length:   max 0 requested + (from - start * dir)
		settings: with [frame 'local] [axis margin spacing canvas fill-x fill-y limits anchor length reverse? do-not-extend?]	;-- origin is unused
		path:     when not same? list last current-path (get-host-path list)	;-- ensures proper styling
		#assert [path]
		with-style path [frame: make-layout 'list :list/items settings]
		;; filled includes whole items span + single margin, so bigger than length by anchor size and some
		filled:   frame/filled - anchor-geom/size/:y - (from - start * dir)
		result:   clip 0 requested filled
		; if result <> 0 [?? [window/origin anchor anchor-geom/offset/:y anchor-geom/size/:y start from length frame/filled filled result]]			
		; ?? frame/map
		#debug list-view [#print "available from (from) along (req-axis)/(dir): (result) of (requested)"]
		result
	]
			
	;; can be styled but cannot be accessed (and in fact shared)
	;; because there's a selection per every row - can be many in one rich-content
	;@@ similar to rich-content - possible to unify?
	selection-prototype: make-space 'space [type: 'selection cache: none]	;-- disabled cache to avoid cloning /cached facet
	cursor-prototype:    make-space 'space [type: 'cursor    cache: none]
	draw-box: function [prototype [object!] size [point2D!]] [
		box: copy prototype
		quietly box/size: size
		render box
	]
	
	;@@ this can be optimized more by limiting first (full-width) draw of scrollable to just enough items to ensure we need a scrollbar
	;@@ then only viewport will have to be filled rather than whole window (but it's tricky in this general model)
	;@@ also I shouldn't redraw it fully if possible after a roll, just the new part, somehow, by reusing the old map if canvas is the same
	;; container/draw only supports finite number of `items`, infinite needs special handling
	;; it's also too general, while this `draw` can be optimized better
	list-draw: function [
		lview  [object!]
		canvas [point2D!] (canvas +< infxinf)			;-- window is never infinite
		xy1    [point2D!]
		xy2    [point2D!]
	][
		#debug sizing [#print "list-view/list draw is called on (canvas), window: (xy1)..(xy2)"]
		window:   lview/window
		anchor:   lview/anchor/index
		list:     lview/list
		axis:     list/axis
		fill-x:   axis <> 'x							;-- always filled along finite axis
		fill-y:   axis <> 'y
		reverse?: lview/anchor/reverse?
		length:   xy2/:axis - xy1/:axis
		moved?:   any [									;-- determine if window offset will change
			lview/anchor/offset <> list/frame/anchor-offset
			lview/anchor/index  <> list/frame/anchor
		]
		;; window/origin is unused because window offsets the list by itself
		settings: with [list 'local] [axis margin spacing canvas fill-x fill-y limits anchor length reverse? do-not-extend?]
		; return list/container-draw/layout 'list settings	;@@ how can it support selected and cursor? put them into list?
		frame:    make-layout 'list :list/items settings
		;; cache cleanup only makes sense after a slide, and after recent draw so we have up to date frame/range
		if moved? [clean-item-cache lview]
		;@@ make compose-map generate rendered output? or another wrapper
		;@@ will have to provide canvas directly to it, or use it from geom/size
		drawn:    make [] 3 * (2 + length? frame/map) / 2
		i:        frame/range/1
		foreach [item geom] frame/map [					;@@ use for-each
			#assert [geom/drawn]						;@@ should never happen?
			item-drawn:  take remove find geom 'drawn	;-- no reason to hold `drawn` in the map anymore
			item-offset: geom/offset
			item-size:   geom/size
			;@@ skip invisible items to lighten the draw block (e.g. for inactive lists)? but that will disable list caching
			compose/only/into [translate (item-offset) (item-drawn)] tail drawn
			case/all [
				find lview/selected i [
					compose/only/into [translate (item-offset) (draw-box selection-prototype item-size)] tail drawn
				]
				lview/cursor = i [
					compose/only/into [translate (item-offset) (draw-box cursor-prototype item-size)] tail drawn
				]
			]
			i: i + 1
		]
		
		;; automatic window positioning based on anchor data
		anchor: lview/anchor
		shift: either anchor/reverse? [
			#assert [anchor/offset >= 0]
			#assert [not list/limits]							;-- else /size may be constrained and shouldn't be relied upon
			anchor/offset - (frame/size/:axis - length)			;-- subtract extra part overhanging after the length
		][
			#assert [anchor/offset <= 0]
			anchor/offset
		]
		window/origin: set-axis (0,0) axis shift				;@@ or move the list instead? a bit slower
		
		; ?? [xy1 xy2 length frame/filled shift anchor/index anchor/offset window/origin lview/origin]
		compose/into [
			window-origin: (window/origin)
			anchor-offset: (anchor/offset)
		] tail frame
		list/frame: frame
		list/size:  frame/size
		quietly list/map: frame/map
		drawn
	]
	
	clean-item-cache: function [lview [object!] "Forget outdated items in item-cache"] [
		unless range: lview/list/frame/range [exit]		;-- has to be drawn to clean up
		max-range-distance: 300							;@@ arbitrary constants.. expose them?
		max-item-age: 0:3
		range: range + (max-range-distance * -1x1)
		now-time: now/precise/utc
		pos: lview/item-cache
		while [all [
			not tail? set [i: _: time:] pos
			i <> clip i range/1 range/2
			max-item-age < difference now-time time 
		]] [
			pos: skip pos 3
		]
		remove/part head pos pos
	]

	;@@ review this
	;; new class needed to type item-cache & available facets
	;; externalized, otherwise will recreate the class on every new list-view
	list-template: declare-class 'list-in-list-view/list [
		type: 'list										;-- styled normally
		axis: 'y
		
		available?: func [axis [word!] dir [integer!] from [linear!] requested [linear!]] [
			;; must pass positive canvas (uses last rendered list-view size)
			~/available? self axis dir from requested
		] #type [function!]
	]
	
	slide: function [lview [object!]] [
		list:   lview/list
		window: lview/window
		anchor: lview/anchor
		y:      list/axis
		if list/frame/anchor <> anchor/index [exit]		;-- forbid slide after anchor is changed (otherwise it resets anchor back)
		; if window/origin <> list/frame/window-origin [exit]
		
		;; it's possible that multiple slides occur without a draw, resulting in no visible item suitable as a new anchor
		;; to avoid this I just limit max consecutive slides to half the window
		;@@ there must be a better solution for this, but I don't see a simple one
		if any [
			(abs anchor/offset) > half window/size/:y
			not moved: inf-scrollable-ctx/slide lview
		] [return none]
		
		;; change anchor to first or last (still visible) item, depending on the slide direction
		xy2: window/size + xy1: negate window/origin	;-- new window box inside list map
		extra: lview/look-around + list/spacing/:y
		xy1/:y: xy1/:y - extra							;-- let anchor start a bit outside the window
		xy2/:y: xy2/:y + extra
		set [new-anchor-item: new-anchor-geom:] pos:
			apply 'locate [
				list/map
				[item geom .. boxes-overlap? xy1 xy2 geom/offset geom/offset + geom/size]
				;; if content in window shifted up/left, will draw more items below/right
				;; if content in window shifted down/right, will draw more items above/left:
				/back moved/:y < 0
			]
		#assert [new-anchor-item]
		anchor/index: ~/map-index->list-index list 1 + half skip? pos
		
		;; window/origin is affected indirectly here via anchor/offset,
		;; because only after list/draw it is possible to know full rendered list extent
		anchor/offset: window/origin/:y + new-anchor-geom/offset/:y + 
			either lview/anchor/reverse?: moved/:y < 0 [
				new-anchor-geom/size/:y + list/margin/:y - window/size/:y
			][
				negate list/margin/:y
			]
		#assert [either lview/anchor/reverse? [anchor/offset >= 0][anchor/offset <= 0]]
			
		; ?? [moved xy1 xy2 new-anchor-geom/offset new-anchor-geom/size anchor/index anchor/offset list/frame/size]
		moved
	]

	;@@ move this into list? hardly makes sense to make offsets window-relative
	;@@ OTOH, list is limited and has no continuation around window borders
	;; an item is "before y" if y >= its (offset/y + size/y)
	;; an item is "after y"  if y < its offset/y
	get-next-item: function [
		space  [object!]
		offset [linear! planar!]
		dir    [word!] (find [before after] dir)
	][
		list: space/list
		y:    list/axis
		if planar? offset [offset: offset/:y]
		if empty? map: list/frame/map [return none]
		
		if either dir = 'before [
			first-geom: second map
			offset < (first-geom/offset/:y + first-geom/size/:y)
		][
			last-geom: last map
			offset >= last-geom/offset/:y
		] [return none]
		
		used-size: pick [1 0] dir = 'before
		target: offset - list/frame/window-origin/:y
		if dir <> 'before [target: target + 1]			;-- +1 to ensure strict 'y < offset'
		found: search/mode/for i: 1 n: half length? map [
			geom: pick map i * 2
			geom/offset/:y + (geom/size/:y * used-size)
		] 'interp target
		#assert [found]
		pick found pick [1 3] dir = 'before
	]
				
	axial-shift: function [
		"Find a new item index further along main axis"
		space [object!]
		index [integer!] "From given item (must be in the map)"
		shift [linear!]  "Maximum positive or negative distance to travel"
	][
		list:      space/list
		y:         list/axis
		range:     list/frame/range
		index:     clip range/1 range/2 index			;-- if not visible, choose nearest
		if shift = 0 [return index]
		old-geom:  pick list/map 2 * (index - range/1 + 1)
		#assert [block? old-geom]
		old-y:     old-geom/offset/:y					;-- shift down counts from item's top
		if shift < 0 [old-y: old-y + old-geom/size/:y]	;-- shift up counts from item's bottom
		new-y:     old-y + shift
		new-y:     new-y + list/frame/window-origin/:y	;-- item-before/after requires window-relative coordinates
		sign:      sign? shift
		new-index: clip range/1 range/2 either shift > 0 [
			i: any [
				get-next-item space new-y 'before		;-- may return none if no more items
				range/2									;-- select farthest item then
			]
			max range/1 + i - 1 index + sign			;-- move at least by one item
		][
			i: any [
				get-next-item space new-y 'after		;-- may return none if no more items
				range/1									;-- select farthest item then
			]
			min range/1 + i - 1 index + sign			;-- move at least by one item
		]
	]

	kit: make-kit 'list-view [
		here: function ["Get index of the item under cursor (or nearest within current window)"] [
			range: space/list/frame/range
			either space/cursor [clip range/1 range/2 space/cursor][range/1]
		]
		length:    func ["Get number of items in the list (can be infinite)"] [any [space/data/size 2'000'000'000]]	;@@ not sure about 2e9
		selected:  func ["Get a list of selected items indices"] [space/selected]
	
		slide: func ["If window is near its borders, let it slide to show more data"] [~/slide space]
		
		;@@ should this support rich text (if list items are rich text)?
		copy-items: function [
			"Copy text of given items"
			items [block! hash! (parse items [any integer!]) pair!] "A list or a range of item indices"
			/clip "Write it into clipboard"
			; /text
		][
			items: either pair? items [
				limit: any [space/list/items/size 1.#inf]
				list-range clip 1 limit order-pair items
			][
				sort copy items							;-- copy should always be ordered
			]
			format: copy {}								;-- used when item has no format
			result: to string! map-each/eval/drop i items [
				unless item: space/list/items/pick i [continue]
				text: batch item [format]
				[text #"^/"]
			]
			if clip [write-clipboard result]
			result
		]
		
		locate: function [
			"Get index of a named item"
			name [word!]
		][
			switch/default name [
				far-head  [1]
				far-tail  [length]
				head      [pick frame/displayed 1]
				tail      [pick frame/displayed 2]
				line-up   [max 1 here - 1]
				line-down [either space/cursor [min length here + 1][1]]
				page-up   [frame/page-above here]
				page-down [frame/page-below here]
			] [here]									;-- unknown words assume current index
		]
		
		move-cursor: function [
			"Redefine cursor and move viewport to make it fully visible"
			target [word! integer!]
			/margin mrg [integer!] "How much to reserve around the item"
			/no-clip "Allow panning outside the window"
		][
			if word? target [target: locate target]
			target: clip 1 length target
			frame/move-to/:margin/:no-clip target mrg
			space/cursor: target
		]
		
		select-range: function [
			"Redefine selection or extend up to a given limit"
			limit [word! integer! pair!] "Pair specifies a range of items"
			/mode "Specify selection mode (default: 'replace)"
				sel-mode: 'replace [word!] (find [replace include exclude invert extend] sel-mode)
		][
			if word?    limit [limit: locate limit]
			if integer? limit [limit: here thru limit]
			old: space/selected
			;; a trick to determine selection range start while it does not exist explicitly:
			;; not fully inaccurate, but good enough: uses first selected item as the start
			if sel-mode = 'extend [
				sel-mode: 'replace
				if old/1 [limit/1: old/1]
			]
			#assert [1e6 >= span? limit]				;-- warn about too big selections (as it's most likely a mistake)
			if 1e6 < span? limit [limit/1: limit/2]		;-- also defend from out of memory errors ;@@ clip it within 1M, not reset to 1 item?
			new: make hash! list-range limit/1 limit/2
			new: switch sel-mode [
				replace [new]
				include [union old new]
				exclude [exclude old new]
				invert  [difference old new]
			]
			append clear old new
			trigger 'space/selected
		]
			
		frame: object [
			displayed: func ["Get a range of currently displayed items"] [space/list/frame/range]
		
			item-before: function [
				"Get item index before given window offset along primary axis; or none"
				offset [linear! planar!]
			][
				~/get-next-item space offset 'before
			]
			
			item-after: function [
				"Get item index after given window offset along primary axis; or none"
				offset [linear! planar!]
			][
				~/get-next-item space offset 'after
			]
			
			page-above: function [
				"Get index of an item one page above the given one"
				index [integer!]
			][
				dist: pick space/viewport space/list/axis
				~/axial-shift space index negate max 1 dist
			]
			
			page-below: function [
				"Get index of an item one page below the given one"
				index [integer!]
			][
				dist: pick space/viewport space/list/axis
				~/axial-shift space index max 1 dist
			]
			
			move-to: function [
				"Pan the view to given window offset or item with the given index"
				target [integer! (all [0 < target target <= length]) planar! word!]
					"Item index or window offset"
				;; normally direction is chosen from the current offset
				;@@ /center to be supported down the road
				/after   "Place the viewport so that item or offset is at its top"
				/before  "Place the viewport so that item or offset is at its bottom"
				/margin   mrg [linear!] "How much to reserve around the item"
				/no-clip "When an offset is given, allow panning outside the window"
			][
				#assert [not all [before after]]
				if word? target [target: locate target]
				list:     space/list
				window:   space/window
				viewport: space/viewport
				range:    list/frame/range
				default mrg: mrg': list/margin along y: list/axis	;-- list/margin is already included, will subtract it
				direction: case [after ['after] before ['before]]
				
				unless planar? point: target [
					unless target-within-range?: target = clip target range/1 range/2 [
						; if window/origin <> list/frame/window-origin [exit]
						;; have to move the window (and the anchor)
						default direction: case [				;-- default direction based on direction to target from current window
							target < range/1 ['after]
							target > range/2 ['before]
						]
						space/anchor/index:    target
						space/anchor/offset:   0
						space/anchor/reverse?: back?: direction = 'before
						originy: either back?
							[negate space/window/size/:y - viewport/:y + mrg - mrg']
							[mrg - mrg']
						scrollable-ctx/set-origin space (set-axis (0,0) y originy) yes
						; ?? [direction target space/origin window/origin list/frame/window-origin]
						exit									;-- done here
					]
					
					;; window can stay, just scroll the viewport
					target-geom: pick list/map target - range/1 + 1 * 2
					target-xy1:  target-geom/offset + window/origin + space/origin	;-- target from viewport
					; target-xy1:  target-geom/offset + list/frame/window-origin + space/origin	;-- target from viewport
					target-xy2:  target-xy1 + target-geom/size
					xy1: set-axis (0,0) y mrg - mrg'			;-- viewport with margins considered
					xy1: min xy1 viewport / 2					;-- cap at half viewport to avoid margin inversion
					xy2: viewport - xy1
					if all [
						not direction
						all [xy1/:y <= target-xy1/:y target-xy1/:y <= xy2/:y]
						all [xy1/:y <= target-xy2/:y target-xy2/:y <= xy2/:y]
					][
						exit									;-- already visible and no direction forced, so do nothing
					]
					
					default direction: pick [after before]		;-- default direction based on target center offset from viewport center
						target-xy1/:y + target-xy2/:y < (xy2/:y + xy1/:y)
					point: target-geom/offset + window/origin
					; point: target-geom/offset + list/frame/window-origin
					if direction = 'before [point/:y: point/:y + target-geom/size/:y]
					; ?? target-geom
					; ?? [direction target point mrg space/origin window/origin list/frame/window-origin target-xy1 target-xy2]
				];unless planar? point: target [
				
				if pre-move: case [								;-- trick to enforce /before and /after locations
					after  [set-axis (0,0) y point/:y + viewport/:y]
					before [set-axis (0,0) y point/:y - viewport/:y]
				][
					scrollable-ctx/move-to space pre-move 0x0 yes
				]
				mrg: set-axis (0,0) y mrg						;-- /margin has meaning along main axis only in list-view, since it's a 1D widget
				scrollable-ctx/move-to space point mrg no-clip
				; scrollable-ctx/set-origin space (viewport * 0x1) - point yes
				; ?? space/origin
				;@@ can't call /slide here because it needs to draw the items first... but it would be good for UX
			];move-to: function [
					
		]
	]
	
	invalidates-list: function [lview [object!] word [word!] value [any-type!]] [
		if object? :lview/list [invalidate lview/list]
	]

	on-anchor-change: function [anchor [object!] word [word!] value [any-type!]] [
		if anchor/parent [invalidate anchor/parent/list]
	]
	
	;; not a space! object (unlike caret) because it makes no sense to draw it
	anchor-spec: declare-class 'list-view-anchor [
		;; used for invalidation
		parent:   none		#type =? [object! (space? parent) none!]
		
		;; index of the first (or last if /reverse?) visible item in the window
		index:    1			#type =? [integer!] (index > 0)	:on-anchor-change
		
		;; item filling direction starting at /index
		reverse?: no		#type =? [logic!]				:on-anchor-change
		
		;; offset from margin to the top <=0 (or bottom >=0 if /reverse?) of the anchor item
		offset:   0			#type =  [linear!]				:on-anchor-change
	]
		
	;@@ list-view & grid-view on child focus should scroll to child
	;@@ expose top /margin & /spacing that are reflected into /list
	declare-template 'list-view/inf-scrollable [
		kit:    ~/kit
		pages:  10
		source: []	#on-change [space word value [any-type!]] [	;-- no type check for it can be freely overridden
			invalidates-list space word :value
			if any-list? :space/item-cache [clear space/item-cache]
		]
		data: func [/pick i [integer!] /size] [			;-- can be overridden
			either pick [source/:i][length? source]		;-- /size may return `none` for infinite data
		] #type [function!]
		
		wrap-data: func [item-data [any-type!] /local spc] [	;-- can be overridden (but with care)
			spc: make-space 'data-view [
				quietly type:  'item
				quietly wrap?:  on
			]
			set/any 'spc/data :item-data
			spc
		] #type [function!]
		
		;; selected items indices list
		;; hash by default so it can scale out of the box for the general case ;@@ auto convert block to hash? on >3-4 items?
		selected:    make hash! 4	#type    [hash! block!] :invalidates-list
		
		;; selection mode: only affects event handlers
		;; its still possible to programmatically select anything, but how keys behave highly depends on /selectable
		selectable:  none			#type    [word! (find [single multi] selectable) none!]
		
		;; current item (for keyboard navigation purposes), doesn't have to be selected 
		cursor:      none			#type =? [integer! (cursor > 0) none!] :invalidates-list

		;; see anchor description in the spec above
		anchor: make classy-object! anchor-spec
		anchor/parent: self
		
		; frame:       []				#type    [map! block! object!]
		; cache:       [size map frame]
		cache:       [size map]
		
		window/content: list: make-space 'list list-template	#type (space? list)
		content-flow: does [
			select [x horizontal y vertical] list/axis
		] #type [function!]
		
		item-cache: make hash! 48
		list/items: func [/pick i [integer!] /size /local item] with list [
			either pick [
				all [
					0 < i i <= any [data/size 1.#inf]			;-- since data/pick can return any value, this is the only way to limit it
					any [
						select item-cache i						;-- no /skip needed because datatypes enforce it
						also item: wrap-data data/pick i
							repend item-cache [i item now/utc/precise] 
					]
				]
			][data/size]
		]
		
		list/draw: func [/window xy1 [point2D!] xy2 [point2D!] /on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			~/list-draw self canvas xy1 xy2				;-- doesn't use fill flags (main axis always infinite, secondary fills if finite)
		]
		
		; ;; this wrapper is neede to auto-position window/origin based on /anchor
		; ;; it has to draw the list, calculate new origin and change it in the drawn block
		; ;@@ unfortunately this means knowledge of the block format produced by window-draw, and of its spec
		; ;@@ maybe list-draw should offset the list instead? shift all items
		; window-draw: :window/draw
		; window/draw: function [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			; old-origin: window/origin
			; quietly window/origin: (0,0)
			; drawn: window-draw/:on canvas fill-x fill-y
			; if :drawn/1 = 'translate [					;-- window isn't empty
				; shift: either anchor/reverse? [
					; #assert [anchor/offset >= 0]
					; anchor-geom: last list/map
					; overhang: anchor-geom/offset/y + anchor-geom/size/y + list/margin/y - window/size/y
					; anchor/offset - overhang
				; ][
					; #assert [anchor/offset <= 0]
					; anchor/offset
				; ]
				; ?? [shift overhang anchor/offset]
				; quietly window/origin: window/map/2/offset: drawn/2: set-axis (0,0) list/axis shift
			; ]
			; drawn
		; ]
		
		;@@ remove it and keep the one in the kit?
		slide: does [~/slide self]
		
		; inf-scrollable-draw: :draw
		; draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!] /window xy1 [none! point2D!] xy2 [none! point2D!]] [
			; ~/draw self canvas fill-x fill-y xy1 xy2
		; ]
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
	
	into: function [grid [object!] xy [planar!] cell [object! none!]] [	;-- faster than generic map-based into
		if cell [return into-map grid/map xy cell]				;-- let into-map handle it ;@@ slow! need a better solution!
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
		r: (0,0)
		foreach [x wh?] [x grid/col-width? y grid/row-height?] [
			x1: min c1/:x c2/:x
			x2: max c1/:x c2/:x
			if x1 = x2 [continue]
			wh?: get/any wh?							;@@ workaround for #4988
			for xi: x1 x2 - 1 [r/:x: r/:x + wh? xi]		;@@ should be sum map
			r/:x: r/:x + (x2 - x1 * (grid/spacing/:x))
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
		level [linear!] "pixels from 0"
		array [map!]    "widths or heights"
		axis  [word!]   "x or y"
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
		either linear? def [
			if n <> sub* n sp + def [size: def throw 1]	;-- point is within a row/col of default size
		][												;-- `default: auto` case where each row size is different
			#assert [array =? grid/heights]
			repeat j n [
				size: grid/row-height? from + j
				if 0 = sub* 1 sp + size [throw 1]		;-- point is within the last considered row (size is valid)
			]
		]
	]

	locate-point: function [grid [object!] xy [planar!] screen? [logic!]] [
		if screen? [
			unless (pinned: grid/pinned) +<= pinned-area: 0x0 [	;-- nonzero pinned rows or cols?
				pinned-area: grid/spacing + grid/get-offset-from 1x1 (pinned + 1x1)
			]
			;; translate heading coordinates into the beginning of the grid
			unless (pinned-area - grid/origin) +<= xy [xy: xy + grid/origin]
		]
		
		bounds: grid/calc-bounds
		r: copy [0x0 (0,0)]
		foreach [x array wh?] reduce [
			'x grid/widths  :grid/col-width?
			'y grid/heights :grid/row-height?
		][
			set [item: idx: ofs:] locate-line grid xy/:x array x
			#debug grid-view [#print "locate-line/(x)=(xy/:x) -> [(item) (idx) (ofs)]"]
			switch item [
				space [ofs: ofs - (grid/spacing/:x)  idx: idx + 1]
				margin [
					either idx = 1 [
						ofs: ofs - (grid/margin/:x)
					][
						idx: bounds/:x
						ofs: ofs + wh? idx
						#assert [idx]					;-- 2nd margin is only possible if bounds are known
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
		hmin: make block! xlim + 1						;-- can't be static because has to be reentrant!
		append hmin any [grid/heights/min 0]
		path: when not same? grid last current-path (get-host-path grid)	;-- let cells be rendered with proper style path
		#assert [path] 
		with-style path [
			for x: 1 xlim [
				canvas: (grid/col-width? x) . 1.#inf
				span: grid/get-span xy: x by y
				if span/x < 0 [continue]				;-- skip cells of negative x span (counted at span = 0 or more)
				cell1: grid/get-first-cell xy
				height1: 0
				if content: grid/cells/pick cell1 [
					cspace: grid/wrap-space cell1 content
					render/on cspace canvas yes no		;-- render to get the size; fill the cell's width
					height1: cspace/size/y
				]
				case [
					span/y = 1 [
						#assert [0 < span/x]
						append hmin height1
					]
					span/y + y = cell1/y [				;-- multi-cell vertically ends after this row
						for y2: cell1/y y - 1 [
							height1: height1 - (grid/spacing/y) - grid/row-height? y2
						]
						append hmin height1
					]
					;-- else just ignore this and use heights/min
				]
				x: x + max 0 span/x - 1					;-- skip horizontal span
			]
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
		r + (xspan - 1 * (grid/spacing/x))
	]
		
	cell-height?: function [grid [object!] xy [pair!]] [
		#assert [xy = grid/get-first-cell xy]	;-- should be a starting cell
		#debug grid-view [						;-- assertion doesn't hold for self-containing grids
			#assert [grid/frame/cells/:xy]		;-- cell should be rendered already (for row-heights to return immediately)
		]
		yspan: second grid/get-span xy
		r: 0 repeat y yspan [r: r + grid/row-height? y - 1 + xy/y]
		r + (yspan - 1 * (grid/spacing/y))
	]
		
	cell-size?: function [grid [object!] xy [pair!]] [
		as-point2D (cell-width? grid xy) (cell-height? grid xy) 
	]
		
	calc-size: function [grid [object!]] [
		if r: grid/size [return r]						;-- already calculated
		#debug grid-view [#print "grid/calc-size is called!"]
		#assert [not grid/infinite?]
		bounds: grid/calc-bounds
		bounds: bounds/x by bounds/y					;-- turn block into pair
		#debug grid-view [#assert [0 <> area? bounds]]
		r: (2,2) * grid/margin + (grid/spacing * max (0,0) bounds - 1)
		repeat x bounds/x [r/x: r/x + grid/col-width?  x]
		repeat y bounds/y [r/y: r/y + grid/row-height? y]
		#debug grid-view [#print "grid/calc-size -> (r)"]
		grid/size: r
	]
		
	;@@ TODO: at least for the chosen range, cell/drawn should be invalidated and cell/size recalculated
	draw-range: function [
		"Used internally by DRAW. Returns map slice & draw code for a range of cells"
		grid [object!] cell1 [pair!] cell2 [pair!] start [point2D!] "Offset from origin to cell1"
	][
		size:  cell2 - cell1 + 1
		drawn: make [] size: area? size
		map:   make block! size * 2						;-- draw appends it, so it can be obtained
		done:  make map! size							;-- local to this range of cells
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
			
			pinned?: grid/is-cell-pinned? cell
			mcell-to-cell: grid/get-offset-from mcell cell	;-- pixels from multicell to this cell
			draw-ofs: start + cell1-to-cell - mcell-to-cell	;-- pixels from draw's 0x0 to the draw box of this cell
			
			mcspace: grid/wrap-space mcell content
			canvas: (cell-width? grid mcell) . 1.#inf		;-- sum of spanned column widths
			render/on mcspace canvas yes no					;-- render content to get it's size - in case it was invalidated
			mcsize: canvas/x . cell-height? grid mcell		;-- size of all rows/cols it spans = canvas size
			mcdraw: render/on mcspace mcsize yes yes		;-- re-render to draw the full background
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
	draw: function [
		grid [object!]
		canvas: infxinf [point2D! none!]
		fill-x: no [logic! none!]
		fill-y: no [logic! none!]
		wxy1 [none! point2D!]
		wxy2 [none! point2D!]
	][
		#debug grid-view [#print "grid/draw is called with window xy1=(wxy1) xy2=(wxy2)"]
		#assert [any [not grid/infinite?  all [canvas +< infxinf wxy1 wxy2]]]	;-- bounds must be defined for an infinite grid
		
		do-invalidate grid
		frame: grid/frame
		frame/canvas: encode-canvas canvas fill-x fill-y

		;; prepare column widths before any offset-to-cell mapping, and before hcache is filled
		if all [fill-x  grid/autofit  not grid/infinite?] [
			autofit grid canvas/x grid/autofit
		]
 	
		frame/bounds: grid/cells/size					;-- may call calc-size to estimate number of cells
		#assert [frame/bounds]
		;-- locate-point calls row-height which may render cells when needed to determine the height
		default wxy1: (0,0)
		unless wxy2 [wxy2: wxy1 + calc-size grid]
		xy1: max (0,0) wxy1 - grid/origin
		xy2: max (0,0) min xy1 + canvas wxy2

		;; affects xy1 so should come before locate-point
		unless (pinned: grid/pinned) +<= 0x0 [			;-- nonzero pinned rows or cols?
			xy0: xy1 + grid/margin						;-- location of drawn pinned cells relative to grid's origin
			set [map: drawn-common-header:] draw-range grid 1x1 pinned xy0
			xy1: xy1 + grid/get-offset-from 1x1 (pinned + 1x1)	;-- location of unpinned cells relative to origin
		]
		#debug grid-view [#print "drawing grid from (xy1) to (xy2)"]

		xy2: max xy1 xy2
		set [cell1: offs1:] grid/locate-point xy1
		set [cell2: offs2:] grid/locate-point xy2
		if none? grid/size [
			either grid/infinite? [grid/size: infxinf][calc-size grid]
		]
		#assert [grid/size]								;-- must be set by calc-size or carried over from the previous render

		quietly grid/map: make block! 2 * area? cell2 - cell1 + 1
		if map [append grid/map map]
		
		;@@ create a grid layout?
		if pinned/x > 0 [
			set [map: drawn-row-header:] draw-range grid
				(1 by cell1/y) (pinned/x by cell2/y)
				xy0/x . (xy1/y - offs1/y)
			append grid/map map
		]
		if pinned/y > 0 [
			set [map: drawn-col-header:] draw-range grid
				(cell1/x by 1) (cell2/x by pinned/y)
				(xy1/x - offs1/x) . xy0/y
			append grid/map map
		]

		set [map: drawn-normal:] draw-range grid cell1 cell2 (xy1 - offs1)
		append grid/map map
		;; note: draw order (common -> headers -> normal) is important
		;; because map will contain intersections and first listed spaces are those "on top" from hittest's POV
		;; as such, map doesn't need clipping, but draw code does

		;@@ relax clipping when content fits - for dropdowns to be supported by headers
		;@@ current clipping mode was meant for spanned heading cells mainly, and for normal cells translation
		reshape [
			;-- headers also should be fully clipped in case they're multicells, so they don't hang over the content:
			clip  0x0         !(xy1)           !(drawn-common-header)	/if drawn-common-header
			clip !(xy1 * 1x0) !(xy2/x . xy1/y) !(drawn-col-header)		/if drawn-col-header
			clip !(xy1 * 0x1) !(xy1/x . xy2/y) !(drawn-row-header)		/if drawn-row-header
			clip !(xy1)       !(xy2)           !(drawn-normal)
		]
	]
	
	;; NOTE: to properly apply styles this should only be called from within draw
	measure-column: function [
		"Measure single column's extent on the canvas of WIDTHxINF (returned size/x may be less than WIDTH)"
		grid  [object!]  "Uses only Y part from margin and spacing"
		index [integer!] "Column's index, >= 1"
		width [linear!]  "Allowed column width in pixels"
		row1  [integer!] "Limit estimation to a given row span"
		row2  [integer!]
	][
		size: (0,2) * grid/margin
		spc:  grid/spacing/y
		if row2 > row1 [size/y: size/y - spc]
		for irow row1 row2 [
			cell: index by irow
			unless space: grid/cells/pick cell [continue]
			cspace: grid/wrap-space cell space			;-- apply cell style too (may influence min. size by margin, etc)
			canvas': either integer? h: any [grid/heights/:irow grid/heights/default] [	;-- row may be fixed
				render/on cspace width . h no no		;-- fixed rows only affect column's width, no filling
			][
				render/on cspace width . 1.#inf no no
				h: cspace/size/y
			]
			span: grid/get-span cell1: grid/get-first-cell cell
			irow: cell1/y + span/y - 1
			;@@ make an option to ignore spanned cells?
			;@@ and theoretically I could subtract spacing from the spanned cells (in case it's big), but lazy for now
			size/y: size/y + spc + (h / span/x)			;-- span/x is accounted for only approximately
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
		total-width [linear!] "Total grid width to fit into"
		method      [word!]    "One of supported fitting methods: [hyperbolic weighted simple-weighted]"	;@@
	][
		#assert [not grid/infinite? "Adjustment of infinite grid will take infinite time!"]
		;; does not modify grid/heights - at least some of them must be `auto` for this func to have effect
		bounds: grid/cells/size
		nx: bounds/x  ny: bounds/y
		if any [nx <= 1 ny <= 0] [exit]					;-- nothing to fit - single column or no rows

		margin:    grid/margin
		spacing:   grid/spacing
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
				size: measure-column grid i 1.#inf 1 ny
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
						apply 'search [HE: H- H+ HE2TWE /with on TW2 TW1 /for on TW /error on tolerance /mode on 'binary]
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
			; print ["INVAL" mold cell scope]
			if scope = 'size [
				either cell [
					invalidate-xy grid pick find/same grid/frame/cells cell -1
				][
					quietly grid/size: none
				]
			]
		]
		clear grid/frame/invalid
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
	
	format: function [grid [object!]] [
		if grid/infinite? [return copy {}]
		bounds: grid/cells/size
		rows: map-each/only irow bounds/y [
			cells: map-each/only icol bounds/x [		;-- /only so even empty cells are separated by tabs
				cell: grid/cells/pick icol by irow
				when all [cell in cell 'format] (cell/format)
			]
			delimit cells "^-"
		]
		to {} delimit rows "^/"
	]
	
	;@@ move grid internal funcs here!
	kit: make-kit 'grid [
		format: does [~/format space]
	]
	
	;@@ add simple proportional algorithm?
	fit-types: [width-total width-difference area-total area-difference]	;-- for type checking
	
	;@@ base it on container?
	declare-template 'grid/space [
		kit:  ~/kit
		;; grid's /size can be 'none' if it was invalidated and needs a calc-size() call
		;@@ need a better solution than this
		size: none	#type [point2D! none!]
		
		margin:  5
		spacing: 5
		origin:  (0,0)			;-- scrolls unpinned cells (should be <= (0,0)), mirror of grid-view/window/origin ;@@ make it read-only
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
		pinned:  0x0						;-- how many rows & columns should stay pinned (as headers), no effect if origin = (0,0)
			#type =? :invalidates-look [pair!] (0x0 +<= pinned)
		bounds:  [x: auto y: auto]								;-- max number of rows & cols
			#type :invalidates [block! function! pair!]
			;@@ none should be forbidden in favor of infinity
			(all [										;-- 'auto=bound /cells, integer=fixed, none=infinite (only within a window!)
				bounds: bounds							;-- call it if it's a function
				any [none =? bounds/x  'auto = bounds/x  all [linear? bounds/x  bounds/x >= 0]]
				any [none =? bounds/y  'auto = bounds/y  all [linear? bounds/y  bounds/y >= 0]]
			])
			
		;; data about the last rendered frame, may be used by /draw to avoid extra recalculations
		frame: context [								;@@ hide it maybe from mold? unify with /last-frame ?
			;@@ maybe cache size too here? just to avoid setting grid/size to none in case it's relied upon by some reactors
			;@@ maybe cache drawn and map and only remake the changed parts? is it worth it?
			;@@ maybe width not canvas?
			canvas:  none								;-- encoded canvas of last draw 
			;@@ support more than one canvas? canvas/x affects heights, limits if autofit is on
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
		
		;@@ perhaps 'self' argument should be implicit in on-invalidate?
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
		
		into: func [xy [planar!] /force child [object! none!]] [~/into self xy child]
		
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
			xy [planar!]
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

		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!] /window xy1 [none! point2D!] xy2 [none! point2D!]] [
			~/draw self canvas fill-x fill-y xy1 xy2
		]
	]
]


grid-view-ctx: context [
	~: self
	
	;; gets called before grid/draw by window/draw to estimate the max window size and thus config scrollbars accordingly
	available?: function [
		grid      [object!]
		axis      [word!]
		dir       [integer!]
		from      [linear!] (from >= 0)
		requested [linear!] (requested >= 0)
	][	
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
	
	on-source-change: function [gview [object!] word [word!] value [any-type!]] [
		if object? :gview/grid [invalidate gview/grid]
	]

	declare-template 'grid-view/inf-scrollable [
		;@@ TODO: slide-length should ensure window size is bigger than viewport size + slide
		;@@ situation when jump clears a part of a viewport should never happen at runtime
		;@@ TODO: maybe a % of viewport instead of fixed jump size?
		size: (0,0)		#type = #on-change [space word value] [quietly space/slide-length: min value/x value/y]
		
		;; reminder: window/slide may change this (together with window/origin) when sliding
		;; grid/origin mirrors grid-view/origin: former is used to relocate pinned cells, latter is normal part of scrollable
		origin: (0,0)	#type = #on-change [space word value] [space/grid/origin: value]	;-- grid triggers invalidation
		
		content-flow: 'planar
		source: make map! [size: (0,0)]	#on-change :on-source-change	;-- map is more suitable for spreadsheets than block of blocks
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
			
			available?: function [axis [word!] dir [integer!] from [linear!] requested [linear!]] [	
				~/available? self axis dir from requested
			]
			
			;; currently the only way to make grid forget its rendered content, since we can't "watch" /data
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

	;; main point of this being separate from button is to keep it not focusable (and so without a focus frame)
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
		; edge:     on	#type =? [logic!]				;-- enables border decor ;@@ more edge styles?
	]
]


;@@ this should not be generally available, as it's for the tests only - remove it!
declare-template 'rotor/space [
	content: none	#type =? :invalidates [object! none!]
	angle:   0		#type =  :invalidates-look [linear!]

	ring: make-space 'space [type: 'ring size: (360,10)]
	tight?: no
	;@@ TODO: zoom for round spaces like spiral

	map: reduce [							;-- unused, required only to tell space iterators there's inner faces
		ring [offset (0,0) size (1e3,1e3)]				;-- 1st = placeholder for `content` (see `draw`)
	]
	cache: [size map]
	
	into: function [xy [planar!] /force child [object! none!]] [
		unless spc: content [return none]
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
		r2: r1 + 10
		c: cosine angle  s: negate sine angle
		p0: p: xy - (size / 2)							;-- p0 is the center
		p: as-point2D  p/x * c - (p/y * s)  p/x * s + (p/y * c)	;-- rotate the coordinates
		xy: p + (size / 2)
		xy1: size - spc/size / 2
		if any [child =? content  r1 > distance? 0x0 p] [
			return reduce [content xy - xy1]
		]
		r: p/x ** 2 + (p/y ** 2) ** 0.5
		a: (arctangent2 0 - p0/y p0/x) // 360					;-- ring itself does not rotate
		if any [child =? ring  all [r1 <= r r <= r2]] [
			return reduce [ring  as-point2D a r2 - r]
		]
		none
	]

	draw: function [] [
		render ring						;-- connect it to the tree
		unless content [return []]
		map/1: spc: content				;-- expose actual name of inner face to iterators
		drawn: render content			;-- render before reading the size
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
		self/size: r1 + 10 * (2,2)
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


;@@ TODO: can I make `frame` some kind of embedded space into where applicable? or a container? so I can change frames globally in one go (margin can also become a kind of frame)
;@@ if embedded, map composition should be a reverse of hittest: if something is drawn first then it's at the bottom of z-order
field-ctx: context [
	~: self
	
	;; caret is separate space so it can be styled, but no `field-caret` template is needed, so it's just a class
	caret-template: declare-class 'field-caret/caret [
		type: 'caret
		look-around: 10		#type = [linear!] (look-around >= 0)	;-- how close caret is allowed to come to field borders
	]
	
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
	
	playback: function [field [object!] offset [integer!] selected [pair! none!] text [any-string!]] [
		#assert [not same? text field/text]
		change/part field/text text tail field/text
		#assert [all [0 <= offset offset <= length? text]]
		field/caret/offset: offset
		field/selected: selected
	]
	
	push-to-timeline: function [
		field [object!]
		left  [block!] (parse left  [integer! [pair! | none!] any-string!])
		right [block!] (parse right [integer! [pair! | none!] any-string!])
	][
		left:  reduce ['playback field left/1  left/2  left/3]
		right: reduce ['playback field right/1 right/2 right/3]
		set [space': left': right':] field/timeline/last-event
		if group?: all [
			field =? space'
			elapsed: field/timeline/elapsed?
			elapsed < 0:0:1
		][
			left: left'
			field/timeline/unwind
		]
		unless empty-change?: left/5 == right/5 [		;-- happens when grouping with reverse event
			field/timeline/put field left right
		]
	]
		
	kit: make-kit 'field [
		length: function ["Get text length"] [
			length? space/text
		]
		
		everything: function ["Get full range of text"] [
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [
			all [sel: space/selected  sel/1 <> sel/2  sel]
		]
		
		here: function ["Get current caret offset"] [
			space/caret/offset
		]
		
		frame: object [
			point->caret: function [
				"Get caret location [0..length] closest to given offset on last frame"
				xy [planar! linear!] "If integer, Y=0"
			][
				if number? xy [xy: xy . 0]
				-1 + offset-to-caret
					space/spaces/text/layout
					xy - space/margin - (space/origin . 0)
			]
			
			adjust-origin: function [
				"Adjust field origin so that caret is visible"
			][
				quietly space/origin: ~/adjust-origin space
			]
		]
		
		select-range: function ["Replace selection" range [pair! none!]] [
			space/selected: if range [clip range 0 length]
		]
		
		record: function [code [block!]] [
			set [space': left': right':] space/timeline/last-event 
			left:  reduce [here selected copy space/text]
			do code
			right: reduce [here selected copy space/text]
			~/push-to-timeline space left right
		]
	
		undo: does [space/timeline/undo]
		redo: does [space/timeline/redo]
	
		;@@ move these into text template?
		locate: function [
			"Get offset of a named location"
			name [word!]
		][
			switch/default name [
				head far-head [0]
				tail far-tail [length]
				prev-word [~/find-prev-word space space/caret/offset]
				next-word [~/find-next-word space space/caret/offset]
			] [space/caret/offset]						;-- don't move on unsupported anchors
		]
	
		move-caret: function [
			"Displace the caret"
			pos [word! (not by) integer!]
			/by "Move by a relative integer number of chars"
		][
			if word? pos [pos: locate pos]
			if by        [pos: space/caret/offset + pos]
			space/caret/offset: clip 0 length pos
		]
	
		select-range: function [
			"Redefine selection or extend up to a given limit"
			limit [word! pair! none! (not by) integer!]
			/by "Move selection edge by an integer number of chars"
		][
			set [ofs: sel:] ~/compute-selection space limit by space/caret/offset length selected
			space/caret/offset: ofs
			space/selected: sel
		]
	
		copy-range: function [
			"Copy and return specified range of text"
			range: 0x0 [pair! none!]
			/clip "Write it into clipboard"
		][
			slice: copy/part space/text range + 1
			if clip [clipboard/write slice]
			slice
		]
			
		remove-range: function [
			"Remove range from caret up to a given limit"
			limit [word! pair! (not by) integer! none!]
			/by "Relative integer number of char"
			/clip "Write it into clipboard"
		][
			case/all [
				not limit      [exit]					;-- for `remove selected` transparency
				word? limit    [limit: locate limit]
				by             [limit: space/caret/offset + limit]
				integer? limit [limit: as-pair space/caret/offset limit]
				pair? limit [
					limit: system/words/clip 0 length order-pair limit 
					if clip [clipboard/write copy/part space/text limit + 1]
					if limit/1 <> limit/2 [
						record [ 
							remove/part  skip space/text limit/1  n: span? limit
							adjust-offsets space limit/1 negate n
						]
					]
				]
			]
		]
	
		insert-items: function [
			"Insert text at given offset"
			offset [word! integer!]
			text   [any-string!]
		][
			unless empty? text [
				if word? offset [offset: locate offset]
				offset: clip offset 0 length
				record [
					insert (skip space/text offset) text
					adjust-offsets space offset length? text
				]
			]
		]
	
		paste: function [
			"Paste text from clipboard at given offset"
			offset [integer!]
		][
			if str: clipboard/read/text [insert-items offset str] 
		]
	
	]
	
	adjust-offsets: function [field [object!] offset [integer!] shift [integer!]] [
		foreach path [field/selected/1 field/selected/2 field/caret/offset] [
			if attempt [offset <= value: get path] [
				set path max offset value + shift
			]
		]
	]
	
	;; selection anchor to pair converter shared by field and document
	compute-selection: function [
		space     [object!]
		limit     [pair! word! integer! none!]
		relative? [logic!]
		offset    [integer!]
		length    [integer!]
		selected  [pair! none!]
	][
		; ?? [limit relative? offset length selected]
		case [
			not limit      [return reduce [offset none]]
			relative?      [ofs: offset + limit]
			integer? limit [ofs: limit]
			pair?    limit [sel: limit]
			'else [
				switch/default limit [
					none #[none] [sel: none]
					all [sel: 0 thru length]
				][
					ofs: batch space [locate limit]		;-- document's locate can return a block
					if block? ofs [ofs: ofs/offset]		;-- ignores returned side
				]
			]
		]
		either ofs [									;-- selection extension/contraction
			ofs: clip ofs 0 length
			sel: any [selected  1x1 * offset]
			other: case [
				sel/1 = offset [sel/2]
				sel/2 = offset [sel/1]
				'else [offset]							;-- if caret is not at selection's edge, ignore previous selection
			]
			sel: other thru ofs
		][												;-- selection override
			if sel [sel: clip sel 0 length]
			ofs: either sel [sel/2][offset]				;-- 'select none' doesn't move the caret
		]
		reduce [ofs  if sel [order-pair sel]]
	]
	
	adjust-origin: function [
		"Return field/origin adjusted so that caret is visible"
		field [object!]
	][
		cmargin: field/caret/look-around
		;; layout may be invalidated by a series of keys, second key will call `adjust` with no layout
		;; also changes to text in the event handler effectively make current layout obsolete for caret-to-offset estimation
		;; field can just rebuild it since canvas is always known (infinite)
		layout: paragraph-ctx/lay-out field/spaces/text infxinf no no
		#assert [object? layout]
		view-width: field/size/x - first (2 * field/margin)
		text-width: layout/extra/x
		cw: field/caret/width
		if view-width - cmargin - cw >= text-width [return 0]	;-- fully fits, no origin offset required
		co: field/caret/offset + 1
		cx: first caret-to-offset layout co
		min-org: min 0 cmargin - cx
		max-org: clip min-org 0 view-width - cx - cw - cmargin
		clip field/origin min-org max-org
	]
			
	draw: function [field [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		ctext: field/spaces/text						;-- text content
		invalidate/only ctext							;-- ensure text is rendered too ;@@ TODO: maybe I can avoid this?
		drawn: render/on ctext infxinf no no			;-- this sets the size
		; #assert [field/size/x = canvas/x]				;-- below algo may need review if this doesn't hold true
		cmargin: field/caret/look-around
		;; fill the provided canvas, but clip if text is larger (adds cmargin to optimal size so it doesn't jump):
		width: first either fill-x [canvas][min ctext/size + cmargin canvas]	
		field/size: constrain width . ctext/size/y field/limits
		mrg: field/margin
		;; draw does not adjust the origin, only event handlers do (this ensures it's only adjusted on a final canvas)
		#assert [ctext/layout]							;-- should be set after draw, others may rely
		ofs: field/origin . 0
		quietly field/map: compose/deep [
			(ctext) [offset: (ofs) size: (ctext/size)]
		]
		compose/deep/only [
			clip (mrg) (field/size - mrg) [
				translate (ofs) (drawn)
			]
		]
	]
		
	on-change: function [field [object!] word [word!] value [any-type!]] [
		if find [spacing margin] word [set in field word value: value * 1x1]	;-- normalize to pair
		set/any 'field/spaces/text/:word :value			;-- sync these to text space; invalidated by text
		if word = 'text [								;-- count it in the history
			field/caret/offset: length? value			;-- auto position at the tail
			set [_: _: right':] field/timeline/last-event/for field
			left:  either right' [right' << 3][reduce [0 none {}]]
			right: reduce [field/caret/offset field/selected copy field/text]
			push-to-timeline field left right
		]
	]
	
	;@@ field will need on-change handler support for better user friendliness!
	declare-template 'field/space [
		kit:      ~/kit
		;; own facets:
		weight:   1		#type = :invalidates [number!] (weight >= 0)
		origin:   0		#type = :invalidates-look [linear!] (origin <= 0)	;-- offset(px) of text within the field
		timeline: make timeline! [limit: 50]	 #type [object!]	;-- saved states
		map:      []
		cache:    [size map]

		spaces: object [
			text:       make-space 'text      [color: none]		;-- by exposing it, I simplify styling of field
		] #type [object!]
		
		caret: make-space 'caret caret-template					;-- shared between text and field
			#type (space? caret) #push spaces/text/caret		;-- exposed here but belongs to (drawn by) the text space
		
		;; these mirror spaces/text facets:
		selected: none				#type =? :on-change [pair! none!]	;-- none or pair (offsets of selection start & end)
		margin:   0					#type =  :on-change	;-- default = no margin
		flags:    []				#type    :on-change	;-- [bold italic underline strike] supported ;@@ TODO: check for absence of `wrap`
		text:     spaces/text/text	#type    :on-change
		font:     spaces/text/font	#type =? :on-change
		color:    none				#type =? :on-change	;-- placeholder for user to control
				
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
	
]


declare-template 'fps-meter/text [
	; cache:     off
	rate:      100
	text:      "FPS: 100.0"		#on-change :invalidates	;-- longest text used for initial sizing of it's host
	init-time: now/precise/utc	#type [date!]
	frames:    make [] 400		#type [block!]
	aggregate: 0:0:3			#type [time!]
]

export exports
