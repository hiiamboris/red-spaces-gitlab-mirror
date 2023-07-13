Red [
	title:   "Layout functions for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export, typecheck

exports: [layouts make-layout]

;@@ can this be layouts/make ?
make-layout: function [
	"Create a layout (arrangement of spaces on a plane)"
	type     [word!]            "Layout name (list, tube, ring)"
	spaces   [block! function!] "List of space names or a picker function"
	settings [block!]           "Block of words referring to setting values"
	; return: [block!] "[size [pair!] map [block!]]
][
	layouts/:type/create :spaces settings
]

layouts: make map! to block! context [					;-- map can be extended at runtime
	import-settings: function [settings [block!] ctx [word!]] [
		bound:  bind append clear [] settings ctx
		values: head reduce/into settings clear []
		set bound values
	]

	list: context [
		;; shared by list/create and list-view/draw
		get-item-canvas: function [list-canvas [pair!] limits [object! none!] axis [word!] margin [pair!]] [
			extend-canvas (subtract-canvas (constrain list-canvas limits) margin * 2) axis	;-- list is infinite along its axis
		]
		
		;; used to preallocate map buffer when count is unknown/infinite, but length (in px) is provided
		item-size-estimate: 100x20
		
		;; settings for list layout:
		;;   axis             [word!]      x or y
		;;   margin           [pair!]      >= 0x0, always added around edge items, even if 'range' limits displayed items
		;;   spacing      [pair! integer!] >= 0x0 (integer used by the document!)
		;;   canvas        [pair! none!]   >= 0x0
		;;   fill-x fill-y [logic! none!]  fill along canvas axes flags: flag along 'axis' is ignored completely,
		;;      while the opposite flag controls whether whole list width extends to canvas or not (but items always fill the width)
		;;   limits        [object! none!]
		;;   origin         [pair! none!]  unrestricted, offsets whole map, default=0x0
		;;   anchor       [integer! none!] index of the item at axis=margin (used by list-view), default=1
		;;   length       [integer! none!] in pixels, when to stop adding items (used by list-view), default=unlimited
		;;                                 does not include anchor size and both margins
		;;   reverse?       [logic! none!] true if items should be counted back from the anchor (used by list-view), default=false
		;;   do-not-extend? [logic! none!] true if sticking out items cannot extend list's width (used by list-view); default=false
		;;                                 (list-view has to maintain fixed width across slides and scrolls)
		;; result of all layouts is a frame object with size, map and possibly more; map geometries contain `drawn` block so it's not lost!
		;; settings are passed as a list of bound words, not as context
		;; this is done to make the list explicit, to avoid unexpected settings being read from the space object
		;; some of the words are also calculated directly in `draw`, so object is a bad fit to pass these
		create: function [
			"Build a list layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [axis margin spacing canvas fill-x fill-y limits origin anchor length reverse? do-not-extend?]"
			;; settings - imported locally to speed up and simplify access to them:
			/local axis margin spacing canvas fill-x fill-y limits origin anchor length reverse? do-not-extend?
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			#assert [any [count length]]				;-- this layout only supports finite number of items or limited length
			default count: infxinf/x
			if count <= 0 [return reduce [margin * 2 copy []]]	;-- empty list optimization
			#debug [typecheck [
				axis     [word! (find [x y] axis)]
				margin   [pair! (0x0 +<= margin)]
				spacing  [pair! (0x0 +<= spacing) integer! (0 <= spacing)]
				canvas   [pair! (0x0 +<= canvas) none!]
				fill-x   [logic! none!]
				fill-y   [logic! none!]
				limits   [object! (range? limits) none!]
				origin   [pair! none!]
				anchor   [integer! (anchor > 0) none!]
				length   [integer! (length >= 0) none!]
				reverse? [logic! none!]
				do-not-extend? [logic! none!]
			]]
			default origin:   0x0
			default canvas:   infxinf
			default fill-x:   no
			default fill-y:   no
			default anchor:   1
			default length:   infxinf/x
			default reverse?: no
			spacing: spacing * 1x1						;-- pair normalization needed by document
			direction: either reverse? [-1][1]
			default do-not-extend?: no
			x: ortho y: axis
			guide: axis2pair y
			item-canvas: get-item-canvas canvas limits axis margin
			;@@ this should be documented in the sizing/canvas docs (to be written)
			;; NOTE: fill/:x does not affect whether items fill the final width or not
			;;   they always do (and fill/:x cannot be true for inf width anyway)
			;;   fill/:x affects whether list extends its width to finite canvas width if former is smaller, or not
			;;   otherwise I will have to enable fill flag for the infinite canvas to make items fill the final width
			;; list can be rendered in two modes:
			;; - on infinitely wide canvas: first render each item on unlimited, then on final (finite) list width
			;;   final width is set to that of the widest visible item (it may change upon scrolling e.g. list-view)
			;;   since width is infinite, scrolling won't affect items height, only resulting list width
			;; - on finitely wide canvas: then fill/:x=true may be done in a single render (unless some item sticks out)
			;;   - if list length is finite:
			;;     wide sticking out items extend the final width, but not beyond limits/max/:x
			;;     (esp. useful when zero canvas is given, e.g. in tube)
			;;     if width has been extended or fill/:x=false (width determined by 1st render),
			;;     then 2nd render fills items along the final width
			;;   - if list has infinite number of items, no width extension is possible,
			;;     because such extension will affect items heights, and items will become denser
			;;     (that would break window-filling logic of list-view)
			;;     if fill/:x=false (for list), 2nd render fills items along width of the widest visible item (changes while scrolling)
			;;     however this layout doesn't know about infinite item count, so forbid-widening? flag is used instead
			;;   so if fill/:x is set, final width cannot be thinner than finite canvas, otherwise it can be
			;; constraining: limits/:x is applied to canvas before rendering items
			;;   then limits/:x is checked when extending or contracting the list width
			;;   along main axis items canvas is always infinite
			;;   but final list length is clipped/extended by limits/:y (hiding items or adding empty space)
			
			loop 2 [									;-- two render cycles
				size: 0x0
				map:  fill abs length direction			;@@ avg+2dev, estimator/corrector
				
				;; total width (size/:x) is used for new canvas when:
				;; - fill/:x = off and total width < canvas width
				;; - 1st render was on infinite width (included into previous case since fill/:x is off for infinity)
				;; - total width > canvas width and count is finite
				if switch sign? size/:x - item-canvas/:x [
					-1 [not either x = 'x [fill-x][fill-y]]
					 1 [not do-not-extend?]
				][
					new-canvas: get-item-canvas size + (margin * 2) limits axis margin	;-- only size/:x is accounted for
					#debug sizing [#print "list c1=(item-canvas) c2=(new-canvas)"]
					if new-canvas <> item-canvas [
						item-canvas: new-canvas
						continue
					]
				]
				break									;-- no second render cycle if canvas is the same
			]
			if direction < 0 [reverse/skip map 2]		;-- order items top-down
			geom1:    map/2
			geom2:    last map
			size/:y:  geom2/offset/:y + geom2/size/:y - geom1/offset/:y
			item-len: max 1 size/:y + spacing/:y / n: half length? map	;-- don't let it become zero, or will overflow
			update-ema/batch 'item-size-estimate/:y item-len 1000 n 
			size:     size + (2 * margin)
			if direction < 0 [							;-- make all offsets positive
				shift: size
				shift/:x: 0
				foreach [_ geom] map [geom/offset: geom/offset + shift]
			]
			range:    order-pair range 
			filled:   size/:y - margin/:y				;-- filled length is not constrained and only has 1 margin (used by 'available?')
			size:     constrain size limits				;-- do not let size exceed the limits (this clips the drawn layout)
			#assert [0x0 +<= size +< (1e7 by 1e7)]
			;@@ omit some of these?
			frame: compose/only [
				size:         (size)
				map:          (map)
				axis:         (axis)
				margin:       (margin)
				spacing:      (spacing)
				origin:       (origin)
				anchor:       (anchor)
				range:        (range)
				length:       (length)					;-- requested length to fill
				reverse?:     (reverse?)
				filled:       (filled)					;-- actually filled length (may be both bigger and smaller)
				canvas:       (canvas)
				fill-x:       (fill-x)
				fill-y:       (fill-y)
				item-canvas:  (item-canvas)
				limits:       (if limits [copy limits])
			]
		]
		
		;; fills at least given amount of pixels with items in given direction (but may stop when runs out of items)
		;; increases size, returns map
		;; consideration: even if whole edge item is hidden (together with spacing), it still should be in the map
		;; because when tabbing around list-view, we need to have this item to switch to it and then pan the view
		;; for the same reason it should draw at least one item even if length=0 or less than margin
		fill: function [
			length [integer!] (length >= 0) sign [integer!] (1 = abs sign)
			/extern y spaces count func? origin margin spacing anchor range item-canvas size
		] with :create [
			ith-item: pick [[spaces/pick i][spaces/:i]] func?
			;; requested length does not include margin, otherwise if margin is big it may happen that window intersects the margin
			; length:   max 0 length - (margin/:y * 2)	;-- w/o margin = length of items themselves (and their spacing)
			count~:   either length < 1e9 [length / item-size-estimate/:y][count]
			map':     make [] count~ * 110% + 5			;-- add extra space to lower the need for reallocations
			i:        anchor
			range:    anchor * 1x1
			pos:      origin + (1 by sign * margin)
			add-item: [
				; ?? [i pos item/size] 
				compose/only/deep/into [
					(item) [offset (pos) size (item/size) drawn (drawn)]
				] tail map'
			]
			draw-next: [
				unless item: do ith-item [break]				;-- stop if no more items
				drawn: render/on item item-canvas yes yes		;-- items always fill the width (render disables fill for infinity)
				#assert [item/size +< (1e7 by 1e7)]				;-- sanity check that items are finite
				size:  max size item/size						;-- accumulate width
				i:     sign + range/2: i						;-- `range/2: i` relies on guaranteed add-item after draw-next
			]
			do draw-next
			length: length + item/size/:y				;-- don't count anchor in the length (required by list-view)
			limit:  pos/:y + (sign * length) 
			forever pick [
				[										;-- going down
					do add-item
					pos/:y: pos/:y + item/size/:y
					if pos/:y > limit [break]					;-- stop if pos > length (last item box intersects bottom margin)
					pos/:y: pos/:y + spacing/:y
					do draw-next
				][										;-- going up
					pos/:y: pos/:y - item/size/:y
					do add-item
					if pos/:y < limit [break]					;-- stop if pos < length (last item box intersects top margin)
					pos/:y: pos/:y - spacing/:y
					do draw-next
				]
			] sign > 0
			map'
		]
	]
	
	tube: context [
		;; settings for tube layout:
		;;   axes          [block! none!]   2 words, any of [n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s] (also supports arrows)
		;;                                  in essence, any of n/e/s/w but both should be orthogonal, total 4x2
		;;                                  default = [e s] - left-to-right items, top-down rows
		;;   align       [block! pair! none!]   pair of -1x-1 to 1x1: x = list within row, y = item within list
		;;                                      default = -1x-1 - both x/y stick to the negative size of axes
		;;   margin            [pair!]      >= 0x0
		;;   spacing           [pair!]      >= 0x0
		;;   canvas         [none! pair!]   >= 0x0; if none=inf, width determined by widest item
		;;   fill-x fill-y [logic! none!]    fill along canvas axes flags
		;;   limits        [none! object!]
		create: function [
			"Build a tube layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [axes align margin spacing canvas fill-x fill-y limits]"
			;; settings - imported locally to speed up and simplify access to them:
			/local axes align margin spacing canvas fill-x fill-y limits
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			if count <= 0 [return copy/deep [0x0 []]]
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			#debug [typecheck [
				axes     [
					block! (
						find/only [
							[n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s]
							[→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←]
						] axes
					)
					none!
				]
				align    [
					pair! (-1x-1 +<= align +<= 1x1)
					block! [(
						all [
							2 >= length? align
							find [#[none] n s e w ↑ ↓ → ← ↔ ↕] align/1
							find [#[none] n s e w ↑ ↓ → ← ↔ ↕] align/2
						]
					)]
					none!
				]
				margin   [pair!] (0x0 +<= margin)
				spacing  [pair!] (0x0 +<= spacing)
				canvas   [pair! (0x0 +<= canvas) none!]
				fill-x   [none! logic!]
				fill-y   [none! logic!]
				limits   [object! (range? limits) none!]
			]]
			default axes:   [e s]
			default align:  -1x-1
			default canvas: infxinf						;-- none to pair normalization
			default fill-x: no
			default fill-y: no
			y: ortho x: anchor2axis axes/1				;-- X/Y align with default representation (row)
			ox: anchor2pair axes/1
			oy: anchor2pair axes/2
			align: normalize-alignment align ox oy
			reverse?: either x = 'x [:do][:reverse]
			
			;; to support automatic sizing, each item's constraints (`limits`) has to be analyzed
			;; obviously there can be two strategies:
			;;  1. fill everything with max size, then shrink, and rearrange as possible
			;;  2. fill everything with min size, then expand within a single row
			;;  2nd option seems more predictable and easier to implement
			;; constraint presence does not mean that space can reach that size as content affects it too,
			;; so it should only be used as hint (canvas size passed to render) to obtain real min size
			;; then, every item has to be rendered 2-3 times:
			;;  1. to get it's narrowest appearance
			;;  2. to expand it horizontally (changes row height) - only for items with nonzero weight
			;;  3. to fully fill row height
			;; quite a rendering torture, but there's no way around it
			
			;; constraints question is also a tricky one
			;; I decided to estimate min. size of each space by using 0x2e9 and 2e9x0 canvases (best fit for text/tube)
			;; (or 0xN / Nx0 when canvas is of fixed width)
			;; then each space will report the "narrowest" possible form of it, suiting tube needs
			;; when limits/min is set, it overrides the half-unlimited canvas
			;; when only limits/max is set, it's "height" overrides the infinite 2e9, "width" stays zero
			
			;; obtain constraints info
			;; `info` can't be static since render may call another layout/create; same for other arrays here
			;; info format: [space-object draw-block available-extension weight]
			info: make [] count * 4
			
			;; clipped canvas - used for allowed width / height fitting
			min-size: max 0x0 (constrain 0x0 limits) - (2 * margin)
			stripe: ccanvas: subtract-canvas constrain canvas limits 2 * margin
			;; along X finite canvas becomes 0 (to compress items initially), infinite stays as is
			;; along Y canvas becomes of canvas size
			stripe/:x: pick ccanvas / infxinf * infxinf x
			; stripe/:y: 0
			#debug sizing [#print "tube canvas=(canvas) ccanvas=(ccanvas) stripe=(stripe)"]
			
			repeat i count [
				space: either func? [spaces/pick i][spaces/:i]
				#assert [space? :space]
				;; 1st render needed to obtain min *real* space/size, which may be > limits/max
				drawn: render/crude/on space stripe no no	;-- fill is not used for 1st render
				weight: any [select space 'weight 0]
				#assert [number? weight]
				available: 1.0 * case [					;-- max possible width extension length, normalized to weight
					weight <= 0 [0]						;-- fixed size
					not max-size: all [space/limits space/limits/max] [infxinf/x]	;-- unlimited extension possible ;@@ REP #113
					pair? max-size [max-size/:x - space/size/:x / weight]
					number? max-size [
						either x = 'x [				 	;-- numeric max-size only used on vertical tubes
							max-size - space/size/:x / weight
						][								;-- vertical is considered unbound
							infxinf/x
						]
					]
				]
				;; if width is infinite, this 1st `drawn` block and `space/size` will be used as there's no meaningful width to fill
				;; otherwise they're just drafts and will be replaced by proper size & block
				repend info [space drawn available weight]
			]
			
			;; split info into rows according to found min widths
			;; rows coordinate system is always [x=e y=s] for simplicity; results are later normalized
			rows: make [] 30
			row:  make [] count * 4
			row-size: -1x0 * spacing					;-- works because no row is empty, so spacing will be added (count=0 handled above)
			allowed-row-width: ccanvas/:x				;-- how wide rows to allow (splitting margin)
			peak-row-width: 0							;-- used to determine full layout size when some row is bigger than the canvas
			total-length:   0							;-- used to extend row heights to fill finite canvas
			row-weight:     0							;-- later used to expand rows with >0 peak weight
			foreach [space drawn available weight] info [
				new-row-size: as-pair					;-- add item-size and check if it hangs over
					row-size/x + space/size/:x + spacing/:x
					max row-size/y space/size/:y		;-- height will only be needed in infinite width case (no 2nd render)
				either any [							;-- row either fits allowed-row-width, or has no items yet?
					new-row-size/x <= allowed-row-width
					tail? row
				][										;-- accept new width
					row-size:   new-row-size
					row-weight: max row-weight weight
				][										;-- else move this item to next row
					append (new-row: make [] length? row) row
					repend rows [row-size row-weight new-row]
					total-length: total-length + row-size/y		;-- add before resetting row-size
					clear row
					row-size: reverse? space/size
					row-weight: weight
				]
				peak-row-width: max peak-row-width row-size/x
				repend row [space drawn available weight]
			]
			repend rows [row-size row-weight row]
			total-length: total-length + row-size/y

			;; expand row items - facilitates a second render cycle of the row
			;; this collects row heights (canvas/:y is still infinite)
			if allowed-row-width < infxinf/x [			;-- only if width is constrained
				allowed-row-width: max allowed-row-width peak-row-width		;-- expand canvas to the biggest row
				peak-row-width: 0						;-- will have to recalculate it during expansion
				total-length:   0
				forall rows [							;@@ use for-each
					set [row-size: row-weight: row:] rows
					free: allowed-row-width - row-size/x
					if all [row-weight > 0 free > 0] [	;-- any space left to distribute?
						;; free space distribution mechanism relies on continuous resizing!
						;; render itself doesn't have to occupy max-size or the size we allocate to it
						;; and since we don't know what render is up to,
						;; we can only "fix" it by re-rendering until we fill whole row space
						;; but this will be highly inefficient, and not even guaranteed to ever finish
						;; so a proper solution in this case should be to use a custom layout or resize hook
						;@@ this needs to be documented, and maybe another sizing type should be possible: a list of valid sizes
						weights: clear []				;-- can be static, not used after distribute
						extras:  clear []
						foreach [_ _ available weight] row [	;@@ use 2 map-eachs
							append weights weight
							append extras  available
						]
						extensions: distribute free weights extras
						; ?? [free extensions weights extras]
						
						row-size: -1x0 * spacing
						repeat i length? extensions [	;@@ use for-each
							set [space:] item: skip row i - 1 * 4
							if extensions/:i > 0 [		;-- only re-render items that are being extended
								desired-size: reverse? space/size/:x + extensions/:i by ccanvas/:y
								;; fill is enabled for width only! otherwise it will affect row/y and later stage of row extension!
								; ?? [desired-size space/content/size]
								item/2: render/crude/on space desired-size x = 'x x = 'y
							]
							row-size: as-pair			;-- update row size with the new render results
								row-size/x + space/size/:x + spacing/:x
								max row-size/y space/size/:y
						]
						rows/1: row-size
					]
					peak-row-width: max peak-row-width row-size/x
					total-length: total-length + row-size/y
					rows: skip rows 2
				]
			]
			
			;; add spacing to total-length (previously not accounted for)
			nrows: (length? rows) / 3
			total-length: total-length + (nrows - 1 * spacing/:y)
			
			;; extend row heights evenly before filling rows in the following cases:
			;; - when canvas has height bigger than all rows height and filling is requested along height 
			;;   this makes it possible to align tube with the canvas without resorting to manual geometry management
			;; - when min height limit is bigger than all rows height (regardless of the fill flag) 
			fill-length: all [ccanvas/:y < infxinf/y  either x = 'x [fill-y][fill-x]]	;-- only fill if finite and requested to fill
			min-length: max-safe min-size/:y if fill-length [ccanvas/:y]				;-- but also if cannot be smaller
			free: min-length - total-length
			if 0 < free: min-length - total-length [
				weights: extract/into next rows 3 clear []	;@@ use map-each
				extras:  append/dup clear [] free nrows
				shares:  distribute free weights extras
				repeat i nrows [						;@@ use for-each
					i3: i - 1 * 3 + 1
					rows/:i3/y: rows/:i3/y + shares/:i
				]
				total-length: min-length
			]
			
			;; third render cycle fills full row height if possible; doesn't affect peak-row-width or row-sizes
			;; it must always be performed for other cycles to be used as /crude
			;@@ maybe it should affect (contract) row widths?
			foreach [row-size row-weight row] rows [
				repeat i (length? row) / 4 [			;@@ use for-each
					set [space:] item: skip row i - 1 * 4
					;; always re-renders items, because they were painted on an infinite canvas
					;; finite canvas will most likely bring about different outcome
					desired-size: reverse? space/size/:x by row-size/y
					item/2: render/on space desired-size yes yes
				]
			]
			
			;; build the map & measure the final layout size using results of 1st or 2nd render
			map:   clear []
			row-y: margin/:y
			shift: min 0x0 oxy: ox + oy					;-- offset correction for negative axes
			row-shift:    align/1 + 1 / 2
			in-row-shift: align/2 + 1 / 2
			total-width:  max-safe peak-row-width if allowed-row-width < infxinf/x [allowed-row-width] 
			foreach [row-size _ row] rows [
				ofs: reverse? margin/:x + (total-width - row-size/x * row-shift) by row-y
				foreach [space drawn _ _] row [
					ofs/:y: to integer! row-size/y - space/size/:y * in-row-shift + row-y
					geom: reduce ['offset ofs * oxy + (space/size * shift) 'size space/size 'drawn drawn]
					repend map [space geom]
					ofs/:x: ofs/:x + spacing/:x + space/size/:x
				]
				row-y: row-y + spacing/:y + row-size/y
			]
			;; fill the desired canvas width if canvas is given:
			size: 2 * margin + reverse? total-width by total-length
			if shift <> 0x0 [							;-- have to add total size to all offsets to make them positive
				shift: size * abs shift
				foreach [_ geom] map [geom/offset: geom/offset + shift]
			]
			#debug sizing [#print "tube c=(canvas) cc=(ccanvas) stripe=(stripe) >> size=(size)"]
			#assert [size +< infxinf]
			frame: compose/only [
				size: (size)
				map:  (copy map)
			]
		]
	]
	
	;; unlike tube this allows the single space to span multiple lines, wrapping it accordingly
	;; wrapping occurs between spaces and between sections (if supported by each item)
	;; it is able to wrap any space without that space knowing about it, letting it keep simple box-like rendering logic
	;; has no support for axes or weight
	;@@ maybe remove limits and apply them to canvas in advance?
	paragraph: context [
		;; paragraph has 3 coordinate spaces (CS):
		;; - 1D CS ("original") - all spaces form a single tight row, vertically aligned along the baseline
		;;   this is the CS /map is expressed in
		;; - 1D' CS (aka "unrolled 2D") - Y is the same as in 1D CS, X usually bigger, sometimes smaller
		;;   it may have words scaled, padded with spaces, etc.
		;;   it consists of whole rows of fixed width, so row number = x / total-width
		;;   this CS is used by mapping function from 1D CS (since mapping has to be monotonic)
		;; - 2D CS ("rolled 2D") - 1D' CS split into chunks, so x here = 1D'x % total-width
		;;   Y depends on each rows height
		;;   this is what user actually sees, where clicks land, etc
		;; coordinates usually include the CS name to avoid confusion
		
		;; builds a tight (no spacing/margin) map in 1D space, vertically aligned
		;@@ must be rebuilt on spacing or baseline change (or content or any item's size change)
		;@@ it shares a lot with list layout (1st phase) - can I unify them?
	    build-map: function [spaces [block! function!] baseline [float! percent!]] [
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
	    	map:   make [] count * 2
	    	if count <= 0 [return reduce [map 0x0]]
	    	
	    	offset: total: 0x0							;-- margin is not accounted for in the map, so it's easier to change
	    	ith-item: either func? [[spaces/pick i]][[spaces/:i]]
			repeat i count [
				space: do ith-item
				#assert [space? :space]
				drawn: render space						;-- for subparagraphs and lists canvas is infinite
				compose/deep/only/into [
					(space) [offset: (offset) size: (space/size) drawn: (drawn)]
				] tail map
				offset/x: offset/x + space/size/x
				total: max total space/size				;-- need row height for aligning items
			]
			total/x: offset/x
			
			foreach [space geom] map [					;-- align vertically along a common baseline
				geom/offset/y: round/to total/y - space/size/y * baseline 1	
			]
	    	reduce [map total]
	    ]

		;; builds a mapping 1Dx -> offset-in-map, to locate relevant spaces quickly
		index-map: function [map [block!]] [
			points: clear []
			repend points [x: 0 o: 0]					;@@ need 1-based offsets, more convenient to use with pick
			foreach [space geom] map [					;@@ use map-each
				repend points [x: x + geom/size/x  o: o + 1]
			]
			#assert [x < infxinf/x]
			if points = [0 0 0 1] [points/3: 1]			;-- hack to make it all work with a zero-wide map
			build-index copy points n: x >> 5 + 1		;-- 1 point per 32 px
		]
		
		;; lists all sections of all child spaces in 1D space! - so not the same as space/sections
		list-sections: function [map [block!] total [integer!]] [
	    	generate-sections map total sections: clear []
	    	;@@ make leading spaces significant?
	    	if empty? sections [append sections 1]
	    	copy sections
		]
	    
		words-period: 4								;-- helpful constant
			
	    ;; groups sections by their sign into 'words', and returns them in this format:
	    ;; [word-x1-1D by word-x2-1D   word-width(int)   white?(logic)   sections-slice(pair)]
	    list-words: function [sections [block!]] [
	    	words: clear []
	    	unless empty? sections [
		    	offset: width: sec-end: sec-bgn: 0
				white?: sections/1 < 0
		    	foreach w sections [					;@@ use for-each
		    		#assert [w <> 0]					;-- zero reserved for tabs
		    		sec-end: sec-end + 1
		    		next-white?: if next-sec: sections/(sec-end + 1) [next-sec < 0]
					width: width + abs w
		    		if white? <> next-white? [
			    		repend words [
			    			0 by width + offset			;-- word's x1..x2 in 1D
			    			width						;-- word's 1D' width (= 1D width now, may be scaled later)
			    			white?						;-- whether word's empty or not
			    			sec-bgn by sec-end			;-- sections slice used by the word
			    		]
			    		white?: next-white?
			    		sec-bgn: sec-end
			    		offset: offset + width
			    		width: 0
		    		]
		    	]
	    	]
	    	copy words
	    ]
	    #assert [
	    	[] = list-words []
	    	; [0x1 1 #[true]  0x0] = list-words []
	    	[0x6 6 #[false] 0x3] = list-words [1 2 3]
	    	[0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[true] 5x6] = list-words [-1 -2 1 2 3 -4]
	    ]
	    
	    ;@@ ensure this is not called with /force-wrap 
	    ;; estimates minimum total width of the paragraph (without margin) given indents and words
	    get-min-total-width-2D: function [words [block!] indent1 [integer!] indent2 [integer!]] [
			;; tricky algorithm to account for the case where indent1 < indent2:
			;; indent1-> w1 w2 long-word
			;; indent2          -> long-word
			;; i.e. it's more optimal to keep long-word in the 1st row than the 2nd
			;; after a few iterations only indent2+width matters then
	    	total: indent1
	    	first?: yes
	    	foreach [wordx width white? _] words [		;@@ use accumulate
	    		unless white? [
	    			either first? [						;-- first non-white word is always on the first row 
			    		total: max total (indent1 + wordx/2)
			    		first?: no
		    		][
			    		total: max total min (indent1 + wordx/2) (indent2 + wordx/2 - wordx/1)
		    		]
	    		]
	    	]
	    	total
	    ]
	    #assert [
	    	10 = get-min-total-width-2D [] 10 20
	    	36 = get-min-total-width-2D [0x6 6 #[false] 0x3] 30 0
	    	36 = get-min-total-width-2D [0x6 6 #[false] 0x3] 30 35
	    	23 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[false] 5x6] 10 30
	    	19 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[true] 5x6] 10 30
	    	19 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[false] 5x6] 10 12
	    	19 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[true] 5x6] 10 12
	    	19 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[false] 5x6] 10 2
	    ]
	    
		;; copy words into buffer, until it fits row-width (or until scaling factor worsens in 'scale mode)
		fill-row: function [buffer [block!] words [block!] sections [block!] row-avail-width [integer!] align [word!] wrap? [logic!]] [
			accept-word?: pick [
				[new-used-width <= row-avail-width]
				[										;-- 'scale mode may exceed row-avail-width
					new-scale: new-used-width / row-avail-width
					old-scale: row-used-width / row-avail-width
					;; plot of best scale func: https://i.gyazo.com/87bf83b060f2a6c6a12a12cbb4e29164.png
					(max new-scale 1.0 / new-scale) < (max old-scale 1.0 / old-scale)	;-- may succeed once when crosses row-avail-width
				]
			] align <> 'scale 
			
			set [word-x-1D: word-width: white?: word-sections:] words-end: words	;-- always add at least one word
			row-used-width: either white? [0][word-width]
			while [not tail? words-end: skip words-end words-period] [
				if white?: words-end/3 [continue]				;-- add as many empty words as possible
				new-used-width: words-end/1/2 - word-x-1D/1
				unless do accept-word? [break]
				row-used-width: new-used-width
			]
			
			append/part row-words: tail buffer words words-end
			if all [									;-- split the word itself if it's bigger than the canvas
				align <> 'scale
				row-used-width > row-avail-width
			][
				; #assert [words-period = offset? words words-end]	;-- single word in the row -- doesn't check for white words before!
				#assert [wrap?]							;-- no-wrap mode must have adjusted the row-avail-width
				#assert [0 < span? word-sections]
				#assert [not white?]					;-- whitespace does not increase used width
				
				;; try adding part of the word section by section
				unless block? sec-slice: word-sections [		;-- it's only block after a word gets split
					sec-slice: copy/part sections 1 + word-sections
				]
				sec-width: 0
				sec-added: 0
				foreach w sec-slice [					;@@ use for-each
					sec-width: sec-width + abs w
					if new-used-width > row-avail-width [break]
					sec-width: new-used-width
					sec-added: sec-added + 1
				]
				either sec-added = 0 [					;-- add only a part of the section
					#assert [new-used-width > row-avail-width]
					sec-width: row-avail-width
					;; modify the sections themselves for next iteration to work
					sec-slice/1: (abs w) - sec-width * (sign? w)
					word-sections: sec-slice
				][
					word-sections: sec-added by 0 + word-sections
				]
				word1: 0 by sec-width + word-x-1D/1		;-- commit only part the the word
				word2: sec-width by 0 + word-x-1D
				rechange row-words [word1 sec-width white? none]	;-- sections are unused in row-words (can be none)
				rechange words [									;-- subtract the committed part from the next word
					word2 (word-width - sec-width) white? word-sections
				]
				row-used-width: sec-width
				words-end: words						;-- no word was added
			]
			
			reduce [row-used-width words-end]
		]
		
		float-vector: make vector! [float! 64 10]
		;; evenly distributes remaining whitespace in fill mode
		distribute-whitespace: function [words [block!] size [integer!]] [
			;; last (trailing) whitespace should not be changed, so need to get rid of it first
			whites: clear {}
			foreach [_ _ white? _] words [append whites pick " +" white?]	;@@ use map-each or sift
			trim/tail whites							;@@ due to #5119 find/last/skip cannot be used
			trim/with whites #"+"
			n-white: length? whites
			if n-white = 0 [exit]						;-- no empty words in the row, have to leave it left-aligned
			
			append/dup clear float-vector 1.0 * size / n-white n-white
			white: quantize float-vector
			while [not tail? words] [					;-- skip 1st word ;@@ use for-each
				if white?: words/3 [
					words/2: words/2 + white/1			;-- modifies word-width-1D
					if tail? white: next white [break]
				]
				words: skip words words-period
			]
		]
		
		;; unifies all words except trailing whitespace into one (for faster drawing)
		;, also groups trailing whitespace
		group-words: function [words [block!]] [
			-skip: negate words-period
			group-end: tail words
			while [group-end/-2 = yes] [				;@@ due to #5119 find/last/skip cannot be used 
				group-end: skip group-end -skip
			]
			; if words-period < length? group-end [  		;-- group whitespace
				; words-end: tail group-end
				; range-1D: group-end/1/1 by words-end/-4/2 
				; clear rechange group-end [range-1D span? range-1D yes none]
			; ]
			if words-period < offset? words group-end [	;-- group words
				range-1D: words/1/1 by group-end/-4/2 
				remove/part
					rechange words [range-1D span? range-1D no none]
					group-end
			]
		]
		
		;; measures y1 (upper) and y2 (lower) of spaces spanned by the row
		get-row-y1y2: function [
			map [block!]
			map-offset1 [integer!] (map-offset1 >= 0)
			map-offset2 [integer!] (map-offset2 >= map-offset1)
		][
			y1: 2e9  y2: 0
			for i: map-offset1 + 1 map-offset2 + 1 [
				geom: pick map i * 2
				y1: min y1 geom/offset/y
				y2: max y2 geom/offset/y + geom/size/y
			]
			reduce [y1 y2]
		]
				
		;; return format skeleton for paragraph layout
		frame!: object [
			size-1D:     0x0
			size-1D':    0x0
			size-2D:     0x0
			margin:      0x0
			spacing:     0
			map:         []
			sections:    []
			drawn:       []
			nrows:       0
			y-levels:    []
			x1D->x1D':   none
			x1D->map:    none
			y2D->row:    none
			caret-boxes: none							;-- not filled by layout/create - only on demand
		]
		
		empty-mapping: build-index [0 0 0 0] 1			;-- cached for faster 0x0 layout
				
		;; settings for paragraph layout:
		;;   align          [none! word!]     one of: [left center right fill scale upscale], default: left
		;;   baseline         [number!]       0=top to 1=bottom(default) normally, otherwise sticks out - vertical alignment in a row
		;;   margin            [pair!]   >= 0x0
		;;   spacing         [integer!]       >= 0 - vertical distance between rows
		;;   canvas         [none! pair!]     >= 0; if infinite, produces a single row
		;;   fill-x fill-y [logic! none!]     fill along canvas axes flags
		;;   limits        [none! object!]
		;;   indent        [none! block!]     [first: integer! rest: integer!], first and rest are independent of each other
		;;   force-wrap?      [logic!]        prioritize canvas width and allow splitting words at *any pixel, even inside a character*
		;@@ ensure spacing is used for vertical distancing (may forget it :)
		;@@ move canvas constraining into render, remove limits?
		create: function [
			"Build a paragraph layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [align baseline margin spacing canvas fill-x fill-y limits indent force-wrap?]"
			;; settings - imported locally to speed up and simplify access to them:
			/local align baseline margin spacing canvas fill-x fill-y limits indent force-wrap?
		][
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			#debug [typecheck [
				align    [word! (find [left center right fill scale upscale] align) none!]
				baseline [number!]
				margin   [pair! (0x0 +<= margin)]
				spacing  [integer! (0 <= spacing)]		;-- vertical only!
				canvas   [pair! (0x0 +<= canvas) none!]
				fill-x   [none! logic!]
				fill-y   [none! logic!]
				limits   [object! (range? limits) none!]
				indent   [block! (parse indent [2 [integer! | none!]]) none!]
			]]
			default canvas: infxinf
			default fill-x: no
			default fill-y: no
			set [map: total-1D:] build-map :spaces 1.0 * baseline
			if empty? map [								;@@ return value needs optimization
				return make frame! compose/only [
					margin:    (margin)
					spacing:   (spacing)
					map:       (map)
					sections:  (reduce [margin/x margin/x])
					x1D->x1D':
					x1D->map:
					y2D->row:  (copy/deep empty-mapping)	;-- single shared mapping is OK since they're read only
				]
			]
			default align:  'left
			default canvas: infxinf						;-- none to pair normalization
			default indent: []
			indent1: any [indent/first 0]
			indent2: any [indent/rest  0]
			
			;; clipped canvas - used to find desired paragraph width
			ccanvas: subtract-canvas constrain canvas limits 2 * margin
			#debug sizing [#print "paragraph canvas=(canvas) ccanvas=(ccanvas)"]
			
			x-1D-to-map-offset: index-map map
			sections: list-sections map total-1D/x
			#assert [not empty? sections]				;-- too hard to adapt the algorithm for that case
			total-1D/x: max 1 total-1D/x				;-- ditto
			words: list-words sections
			total-2D: 1x0 * ccanvas						;-- without margins
			if any [
				ccanvas/x >= infxinf/x					;-- convert infinite canvas into single-row canvas
				not fill-x								;-- contract width if not asked to fill it
			][
				total-2D/x: min total-2D/x total-1D/x
			]
			unless force-wrap? [						;-- extend width to the longest predicted row
				total-2D/x: max total-2D/x get-min-total-width-2D words indent1 indent2
			]
			#assert [total-2D/x < infxinf/x]
			
			;; lay out rows...
			
			indent:            indent1
			nrows:             0
			row-y1-2D:         0
			x-1D-1D'-points:   clear []
			y-irow-points:     clear []
			y-levels:          clear []
			layout-drawn:      clear []
			get-in-row-indent: switch/default align [
				right [[row-left-width]]
				center [[round/ceiling/to half row-left-width 1]]
			] [0]
			while [not tail? words] [
				;; consume some words (or part of a single word)
				row-words: clear []
				row-avail-width: max 1 total-2D/x - indent		;-- disallow rows of 0 pixels ;@@ 1px may still be rather slow!
				set [row-used-width: words:] fill-row row-words words sections row-avail-width align force-wrap?
				#assert [not empty? row-words]
				last-word:  skip tail row-words -4
				row-left-width: max 0 row-avail-width - row-used-width
				
				row-x1-1D:  row-words/1/1
				row-x2-1D:  last-word/1/2				;-- row x1-x2 includes the trailing whitespace, unlike used-width
				row-x1-1D': nrows     * total-2D/x
				row-x2-1D': nrows + 1 * total-2D/x
				#assert [any [row-x2-1D > row-x1-1D empty? sections]]	;-- empty row only allowed for empty input
				
				;; unify, pad, scale words
				#assert [not empty? row-words]
				if 1 < length? row-words [
					either align <> 'fill [
						group-words row-words			;-- leaves row-words/2 unset (zero)
					][
						if all [
							row-left-width > 0
							not tail? words				;-- don't fill the last row
						][
							distribute-whitespace row-words row-left-width
						]
					]
				]
				if align <> 'fill [
					row-words/2: either find [scale upscale] align
						[row-avail-width][row-used-width]
				]
			
				;; collect x mapping points
				in-row-indent: do get-in-row-indent
				words-offset-1D': row-x1-1D' + indent + in-row-indent
				repend x-1D-1D'-points [
					row-x1-1D row-x1-1D'				;-- left visible row margin (before indenting)
					row-x1-1D words-offset-1D'			;-- indent's end = word's start
				]
				offset-1D': words-offset-1D'
				foreach [word-x-1D word-width-1D' white? _] row-words [		;-- add all words' end
					offset-1D': min row-x2-1D' offset-1D' + word-width-1D'	;-- clip x at row's end
					repend x-1D-1D'-points [word-x-1D/2 offset-1D']
				]
				
				;; measure the row vertically
				set [map-ofs1: map-ofs2:] reproject-range/truncate x-1D-to-map-offset row-x1-1D max row-x1-1D row-x2-1D - 1
				set [row-y1-1D: row-y2-1D:] get-row-y1y2 map map-ofs1 map-ofs2
				row-y2-2D:  row-y1-2D + (row-y2-1D - row-y1-1D)
				row-y0-2D:  row-y2-2D - row-y2-1D
				row-height: row-y2-1D - row-y1-1D
				repend y-levels [row-y0-2D row-y1-2D row-y2-2D]
				repend y-irow-points [row-y1-2D nrows row-y2-2D nrows]	;-- zero-based row number
				; ?? [row-y1-1D row-y2-1D row-y0-2D row-y1-2D row-y2-2D]
				
				;; draw the row
				row-drawn: clear []
				word-offset: 0
				foreach [word-x-1D word-width-1D' white? _] row-words [
					#assert [0 < span? word-x-1D]
					word-scale: word-width-1D' / span? word-x-1D
					set [map-ofs1: map-ofs2:] reproject-range/truncate x-1D-to-map-offset word-x-1D/1 word-x-1D/2 - 1
					#assert [map-ofs2 >= map-ofs1]
					
					geom1: pick map map-ofs1 + 1 * 2
					row-origin-1D: geom1/offset * 1x0
					spaces-drawn: clear []
					for i: map-ofs1 + 1 map-ofs2 + 1 [
						geom: pick map i * 2 
						compose/only/into [
							translate (geom/offset - row-origin-1D) (geom/drawn)
						] tail spaces-drawn
					]
					
					offset1: geom1/offset/x - word-x-1D/1		;-- negative x offset of 1st space within the word
					#assert [offset1 <= 0]
					word-span: span? word-x-1D
					word-drawn: compose/deep/only [
				  		translate (word-offset by 0)			;-- move to the 2D point
						#debug paragraph [push [
							translate (0 by row-y1-1D)
							fill-pen off pen magenta line-width 1
							box 0x0 (word-width-1D' by row-height)
						]]
				  		scale (word-scale) 1.0
				  		clip 0x0 (word-span by total-1D/y)
				  		translate (offset1 by 0)				;-- account for word's offset within geom/size/x
				  		(copy spaces-drawn)
					]
					repend row-drawn ['push word-drawn]
					word-offset: word-offset + word-width-1D'
				]
				word-x1-2D: indent + in-row-indent
				compose/only/into [
					translate (indent + in-row-indent by row-y0-2D)
					(copy row-drawn)
				] tail layout-drawn
			
				indent: indent2
				row-y1-2D: row-y2-2D + spacing
				nrows: nrows + 1
			]
			total-2D/y: row-y2-2D
			drawn: compose/only [translate (margin) (copy layout-drawn)]
			total-1D': (last x-1D-1D'-points) by total-1D/y
			
			frame: make frame! compose/only [
				size-1D:   (total-1D)
				size-1D':  (total-1D')
				size-2D:   (total-2D)					;-- size without margins
				margin:    (margin)
				spacing:   (spacing)
				map:       (map)
				sections:  (sections)
				drawn:     (drawn)
				nrows:     (nrows)
				y-levels:  (copy y-levels)
				x1D->x1D': (build-index copy x-1D-1D'-points total-1D/x >> 5 + 1)
				x1D->map:  (x-1D-to-map-offset)
				y2D->row:  (build-index copy y-irow-points   total-2D/y >> 2 + 1)
			]
			
			frame
		]
	]		
	
	ring: context [
		;; settings for ring layout:
		;;   angle    [integer! float! none!]   unrestricted, defaults to 0
		;;     in degrees - clockwise direction to the 1st item (0 = right, aligns with math convention on XY space)
		;;   radius      [integer! float!]   >= 0
		;;     minimum distance (pixels) from the center to the nearest point of arranged items
		;;   round?      [logic!]   default: false
		;;     whether items should be considered round, not rectangular
		create: function [
			"Build a ring layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [angle radius round?]"
			/local angle radius round?
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			if count <= 0 [return copy/deep [0x0 []]]	;-- empty layout optimization
			foreach word settings [						;-- free settings block so it can be reused by the caller
				#assert [:self/create =? context? bind word 'local]
				set bind word 'local get word
			]
			#debug [typecheck [
				angle  [integer! float! none!]
				radius [integer! float!] (0 <= radius)
				round? [logic! none!]
			]]
			default angle: 0
			default round?: no
			
			map: make [] 2 * count
			origin: 0x0
			total:  0x0
			step:   360 / count
			
			either round? [
				;; round items are also considered almost equal in size, so it's easy math
				repeat i count [
					space:  either func? [spaces/pick i][spaces/:i]
					#assert [space? :space]
					drawn:  render space
					center: space/size / 2
					rad:    radius + max center/x center/y
					point:  (polar2cartesian rad angle) - center
					compose/only/deep/into [
						(space) [offset (pos) size (space/size) drawn (drawn)]
					] tail map
					origin: min origin pos				;-- find leftmost topmost point
					total:  max total pos + space/size	;-- find total dimensions
					angle:  angle + step
				]
			][
				;; measures real distance from the box to 0x0 and pushes `rad` closer to `radius`
				;; input: [size rad angle radius] output: [rad pos r-move]
				adjust-radius: [
					pos:    (polar2cartesian rad angle) - (size / 2)
					r-move: radius - vec-length? closest-box-point? pos pos + size
					rad:    rad + r-move
					pos:    (polar2cartesian rad angle) - (size / 2)
				]
						
				;; initially arrange box centers uniformly around the 0x0 point
				items: make [] count * period: 7
				
				repeat i count [
					space: either func? [spaces/pick i][spaces/:i]
					#assert [space? :space]
					drawn: render space
					size:  space/size
					rad:   radius
					do adjust-radius
					repend items [i space angle rad pos space/size drawn]
					angle: angle + step
				]
				
				;; now repeatedly move boxes around (tangentially) until they look equidistant
				limit: 2								;-- optimization criterion: 2px of irregularity allowed
				loop 10 [								;-- cap at 10 iterations in case of a bug
					max-move: 0
					repeat i count [					;@@ should be for-each but it binds `rad` which adjust-radius modifies
						item-1: skip items i - 2 // count * period
						item:   skip items i - 1          * period
						item+1: skip items i     // count * period
						set [_: _: angle: rad: pos: size:] item
						dist-1: box-distance? pos pos + size o: item-1/5 o + item-1/6
						dist+1: box-distance? pos pos + size o: item+1/5 o + item+1/6
						a-move: dist+1 - dist-1 / 2 / rad * #do keep [180 / pi]
						angle:  angle + a-move
						do adjust-radius
						change change change at item 3 angle rad pos
						max-move: max max max-move abs a-move abs r-move	;@@ should be done with HOFs
					]
					if max-move <= limit [break]		;-- stop optimization attempts
				]
				
				;; lay out boxes into a map and estimate boundaries
				foreach [_ space _ _ pos size drawn] items [
					compose/only/deep/into [
						(space) [offset (pos) size (size) drawn (drawn)]
					] tail map
					origin: min origin pos				;-- find leftmost topmost point
					total:  max total pos + size		;-- find total dimensions
				]
			]
			
			frame: compose/only [
				size:   (total - origin)
				map:    (map)
				origin: (origin)						;-- container will auto translate contents if origin is returned
			]
		]
	]
]

export exports
