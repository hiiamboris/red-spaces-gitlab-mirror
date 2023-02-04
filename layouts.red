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
		foreach word settings [
			#assert [(context? ctx) =? context? bind word ctx]
			set bind word ctx get word
		]
	]

	list: context [
		;; settings for list layout:
		;;   axis             [word!]   x or y
		;;   margin       [integer! pair!]   >= 0x0
		;;   spacing      [integer! pair!]   >= 0x0
		;;   canvas        [pair! none!]
		;;   limits        [none! object!]
		;;   origin           [pair!]   unrestricted
		;; result of all layouts is a block: [size [pair!] map [block!]], but map geometries contain `drawn` block so it's not lost!
		;; settings are passed as a list of bound words, not as context
		;; this is done to make the list explicit, to avoid unexpected settings being read from the space object
		;; some of the words are also calculated directly in `draw`, so object is a bad fit to pass these
		create: function [
			"Build a list layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [axis margin spacing canvas limits origin]"
			;; settings - imported locally to speed up and simplify access to them:
			/local axis margin spacing canvas limits origin
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			if count <= 0 [return reduce [margin * 2x2 copy []]]	;-- empty list optimization
			#debug [typecheck [
				axis     [word! (find [x y] axis)]
				margin   [integer! (0 <= margin)  pair! (0x0 +<= margin)]
				spacing  [integer! (0 <= spacing) pair! (0x0 +<= spacing)]
				canvas   [none! pair!]
				limits   [object! (range? limits) none!]
				origin   [none! pair!]
			]]
			default origin: 0x0
			default canvas: infxinf
			canvas: extend-canvas canvas axis			;-- list is infinite along it's axis
			set [canvas: fill:] decode-canvas canvas
			margin: margin * 1x1						;-- integer to pair normalization
			; canvas: constrain canvas limits
			x: ortho y: axis
			fill/:x: 1									;-- always fills along it's secondary axis
			guide: axis2pair y
			pos: pos': origin + margin
			;; list can be rendered in two modes:
			;; - on unlimited canvas: first render each item on unlimited canvas, then on final list size
			;; - on fixed canvas: then only single render is required, unless some item sticks out
			canvas1: canvas2: subtract-canvas canvas 2 * margin
			canvas1: encode-canvas canvas1 fill
			
			map: make [] 2 * count
			size: 0x0
			repeat i count [							;-- first render cycle
				space: either func? [spaces/pick i][spaces/:i]
				#assert [space? :space]
				drawn: render/on space canvas1
				#assert [space/size +< (1e7 by 1e7)]
				compose/only/deep/into [(space) [offset (pos) size (space/size) drawn (drawn)]] tail map
				pos:   pos + (space/size + spacing * guide)
				size:  max size space/size
			]
			;; only extend the canvas to max item's size, but not contract if it's finite
			;; do contract if X is infinite
			canvas2/:x: max-safe size/:x if canvas2/:x < infxinf/x [canvas2/:x]		;-- `size` already has margin subtracted
			;; apply limits to canvas2/:x to obtain proper list width
			; size: constrain size limits
			canvas2: constrain canvas2 limits
			canvas2: encode-canvas canvas2 fill
			#debug sizing [#print "list c1=(canvas1) c2=(canvas2)"]
			if canvas2 <> canvas1 [	;-- second render cycle - only if canvas changed
				pos: pos'  size: 0x0
				repeat i count [
					space: either func? [spaces/pick i][spaces/:i]
					drawn: render/on space canvas2
					#assert [space/size +< (1e7 by 1e7)]
					geom:  pick map 2 * i
					compose/only/into [offset (pos) size (space/size) drawn (drawn)] clear geom
					pos:   pos + (space/size + spacing * guide)
					size:  max size space/size
				]
			]
			size: pos - (spacing * guide)				;-- cut trailing space
				- origin + margin						;-- 2 margins + size along axis
				+ (size * reverse guide)				;-- size normal to axis
			#assert [size +< (1e7 by 1e7)]
			reduce [size map]
		]
	]
	
	tube: context [
		;; settings for tube layout:
		;;   axes          [block! none!]   2 words, any of [n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s] (also supports arrows)
		;;                                  in essence, any of n/e/s/w but both should be orthogonal, total 4x2
		;;                                  default = [e s] - left-to-right items, top-down rows
		;;   align       [block! pair! none!]   pair of -1x-1 to 1x1: x = list within row, y = item within list
		;;                                      default = -1x-1 - both x/y stick to the negative size of axes
		;;   margin        [integer! pair!]   >= 0x0
		;;   spacing       [integer! pair!]   >= 0x0
		;;   canvas         [none! pair!]   if none=inf, width determined by widest item
		;;   limits        [none! object!]
		create: function [
			"Build a tube layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [axes align margin spacing canvas limits]"
			;; settings - imported locally to speed up and simplify access to them:
			/local axes align margin spacing canvas limits
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
				margin   [integer! (0 <= margin)  pair! (0x0 +<= margin)]
				spacing  [integer! (0 <= spacing) pair! (0x0 +<= spacing)]
				canvas   [none! pair!]
				limits   [object! (range? limits) none!]
			]]
			default axes:   [e s]
			default align:  -1x-1
			default canvas: infxinf						;-- none to pair normalization
			set [canvas: fill:] decode-canvas canvas
			margin:  margin  * 1x1						;-- integer to pair normalization
			spacing: spacing * 1x1
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
			ccanvas: subtract-canvas constrain canvas limits 2 * margin
			; stripe: (subtract-canvas canvas 2 * margin) * oy
			;; along X finite canvas becomes 0 (to compress items initially), infinite stays as is
			;; along Y canvas becomes infinite, later expanded to fill the row
			;@@ should it always be 0xinf maybe?
			; stripe: round/to subtract-canvas canvas 2 * margin infxinf * ox		;@@ #5151
			; stripe: reverse? encode-canvas  0 by ccanvas/:y  0x-1	;-- fill is not used for 1st render
			stripe: encode-canvas ccanvas reverse? 0x-1	;-- fill is not used for 1st render
			; stripe: reverse? encode-canvas  infxinf/x by ccanvas/:y  0x-1	;-- fill is not used for 1st render
			; stripe: subtract-canvas canvas 2 * margin
			; stripe/:x: round/to stripe/:x infxinf/x
			; stripe/:y: infxinf/x
			#debug sizing [#print "tube canvas=(canvas) ccanvas=(ccanvas) stripe=(stripe)"]
			
			repeat i count [
				space: either func? [spaces/pick i][spaces/:i]
				#assert [space? :space]
				;; 1st render needed to obtain min *real* space/size, which may be > limits/max
				drawn: render/on space stripe
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
						
						row-size: -1x0 * spacing
						repeat i length? extensions [	;@@ use for-each
							set [space:] item: skip row i - 1 * 4
							if extensions/:i > 0 [		;-- only re-render items that are being extended
								desired-size: reverse? space/size/:x + extensions/:i by ccanvas/:y
								;; fill is enabled for width only! otherwise it will affect row/y and later stage of row extension!
								item/2: render/on space encode-canvas desired-size reverse? 1x-1
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
			
			;; when canvas has height bigger than all rows height - extend row heights evenly before filling rows
			;; this makes it possible to align tube with the canvas without resorting to manual geometry management
			if fill/:y = 1 [
				free: ccanvas/:y - total-length
				if all [0 < free  ccanvas/:y < infxinf/y][	;-- canvas/y has to be finite and bigger than length
					weights: extract/into next rows 3 clear []	;@@ use map-each
					extras:  append/dup clear [] free nrows
					shares:  distribute free weights extras
					repeat i nrows [					;@@ use for-each
						i3: i - 1 * 3 + 1
						rows/:i3/y: rows/:i3/y + shares/:i
					]
					total-length: ccanvas/:y
				]
			]
			
			;; third render cycle fills full row height if possible; doesn't affect peak-row-width or row-sizes
			;@@ maybe it should affect (contract) row widths?
			foreach [row-size row-weight row] rows [
				repeat i (length? row) / 4 [			;@@ use for-each
					set [space:] item: skip row i - 1 * 4
					;; always re-renders items, because they were painted on an infinite canvas
					;; finite canvas will most likely bring about different outcome
					desired-size: reverse? space/size/:x by row-size/y
					item/2: render/on space encode-canvas desired-size 1x1
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
			reduce [size copy map]
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
			repeat i count [
				space: either func? [spaces/pick i][spaces/:i]
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
			build-index copy points n: x >> 5 + 1		;-- 1 point per 32 px
		]
		
		;; lists all sections of all child spaces in 1D space! - so not the same as space/sections
		list-sections: function [map [block!] total [integer!]] [
	    	generate-sections map total sections: clear []
	    	;@@ make leading spaces significant?
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
	    	foreach [wordx width white? _] words [		;@@ use accumulate
	    		unless white? [
		    		total: max total min (indent1 + wordx/2) (indent2 + wordx/2 - wordx/1)
	    		]
	    	]
	    	total
	    ]
	    #assert [
	    	10 = get-min-total-width-2D [] 10 20
	    	30 = get-min-total-width-2D [0x6 6 #[false] 0x3] 30 0
	    	36 = get-min-total-width-2D [0x6 6 #[false] 0x3] 30 35
	    	23 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[false] 5x6] 10 30
	    	19 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[true] 5x6] 10 30
	    	18 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[false] 5x6] 10 12
	    	18 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[true] 5x6] 10 12
	    	10 = get-min-total-width-2D [0x3 3 #[true] 0x2  3x9 6 #[false] 2x5  9x13 4 #[false] 5x6] 10 2
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
			row-used-width: either white? [word-width][0]
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
				#assert [words-period = offset? words words-end]	;-- single word in the row
				#assert [force-wrap?]					;-- no-wrap mode must have adjusted the row-avail-width
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
					if new-width > row-avail-width [break]
					sec-width: new-width
					sec-added: sec-added + 1
				]
				either sec-added = 0 [					;-- add only a part of the section
					#assert [new-width > row-avail-width]
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
			n-white: 0
			foreach [_ _ white? _] words [if white? [n-white: n-white + 1]]
			if n-white = 0 [exit]						;-- no empty words in the row, have to leave it left-aligned
			append/dup clear float-vector 1.0 * size / n-white n-white
			white: quantize float-vector
			while [not tail? words] [					;-- skip 1st word ;@@ use for-each
				if words/3 [
					words/2: words/2 + white/1			;-- modifies word-width-1D
					white: next white
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
				
		;; settings for paragraph layout:
		;;   align          [none! word!]     one of: [left center right fill scale upscale], default: left
		;;   baseline         [number!]       0=top to 1=bottom(default) normally, otherwise sticks out - vertical alignment in a row
		;;   margin        [integer! pair!]   >= 0x0
		;;   spacing         [integer!]       >= 0 - vertical distance between rows
		;;   canvas            [pair!]        if infinite, produces a single row
		;;   limits        [none! object!]
		;;   indent        [none! block!]     [first: integer! rest: integer!], first and rest are independent of each other
		;;   force-wrap?      [logic!]        prioritize canvas width and allow splitting words at *any pixel, even inside a character*
		;@@ ensure spacing is used for vertical distancing (may forget it :)
		;@@ move canvas constraining into render, remove limits?
		create: function [
			"Build a paragraph layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [align baseline margin spacing canvas limits indent force-wrap?]"
			;; settings - imported locally to speed up and simplify access to them:
			/local align baseline margin spacing canvas limits indent force-wrap?
		][
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			#debug [typecheck [
				align    [word! (find [left center right fill scale upscale] align) none!]
				baseline [number!]
				margin   [integer! (0 <= margin)  pair! (0x0 +<= margin)]
				spacing  [integer! (0 <= spacing)]		;-- vertical only!
				canvas   [pair!]
				limits   [object! (range? limits) none!]
				indent   [block! (valid-indent? indent) none!]
			]]
			set [map: total-1D:] build-map :spaces 1.0 * baseline
			if empty? map [								;@@ return value needs optimization
				return frame: construct compose/only [
					size-1D:     0x0
					size-2D:     (margin * 2x2)
					map:         (map)
					drawn:       (copy [])
					y-levels:    (copy [])
					x1D-to-x1D': (build-index copy [0 0 0 0] 1)
					y1D-to-row:  (build-index copy [0 0 0 0] 1)
				]
			]
			
			default align:  'left
			default canvas: infxinf						;-- none to pair normalization
			set [|canvas|: fill:] decode-canvas canvas
			default indent: []
			indent1: any [indent/first 0]
			indent2: any [indent/rest  0]
			margin:  margin * 1x1						;-- integer to pair normalization
			
			;; clipped canvas - used to find desired paragraph width
			ccanvas: subtract-canvas constrain |canvas| limits 2 * margin
			#debug sizing [#print "paragraph canvas=(canvas) ccanvas=(ccanvas)"]
			
			x-1D-to-map-offset: index-map map
			sections: list-sections map total-1D/x
			words: list-words sections
			total-2D: 1x0 * ccanvas						;-- without margins
			unless force-wrap? [						;-- extend width to the longest predicted row
				total-2D/x: max total-2D/x get-min-total-width-2D words indent1 indent2
			]
			
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
				#assert [row-x2-1D > row-x1-1D]
				
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
				set [map-ofs1: map-ofs2:] reproject-range/truncate x-1D-to-map-offset row-x1-1D row-x2-1D - 1
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
			drawn: compose/only [translate (margin * 2) (copy layout-drawn)]
			total-1D': (last x-1D-1D'-points) by total-1D/y
			
			frame: construct compose/only [
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
				x1D->x1D': (build-index copy x-1D-1D'-points total-1D/x >> 5)
				x1D->map:  (x-1D-to-map-offset)
				y2D->row:  (build-index copy y-irow-points   total-2D/y >> 2)
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
			
			total: total - origin
			;; container will auto translate contents if origin is returned
			reduce [total map origin]
		]
	]
]

export exports
