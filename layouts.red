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
			if count <= 0 [return copy/deep [0x0 []]]	;-- empty list optimization
			foreach word settings [						;-- free settings block so it can be reused by the caller
				set bind word 'local get word			;@@ check that only allowed words are overwritten, not e.g. `count` or global smth
			]
			#debug [typecheck [
				axis     [word! (find [x y] axis)]
				margin   [integer! (0 <= margin)  pair! (0x0 +<= margin)]
				spacing  [integer! (0 <= spacing) pair! (0x0 +<= spacing)]
				canvas   [none! pair!]
				limits   [object! (all [in limits 'min in limits 'max]) none!]
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
			#debug sizing [print ["list c1=" canvas1 "c2=" canvas2]]
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
		;;   align         [block! none!]   pair of -1x-1 to 1x1: x = list within row, y = item within list
		;;                                  default = -1x-1 - both x/y stick to the negative size of axes
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
			foreach word settings [						;-- free settings block so it can be reused by the caller
				set bind word 'local get word			;@@ check that only allowed words are overwritten, not e.g. `count`
			]
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
				limits   [object! (all [in limits 'min in limits 'max]) none!]
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
			;; `info` can't be static since render may call another build-map; same for other arrays here
			;; info format: [space-name space-object draw-block available-extension weight]
			info: obtain block! count * 4
			#leaving [stash info]
			
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
			#debug sizing [print ["tube canvas=" canvas "ccanvas=" ccanvas "stripe=" stripe]]
			
			repeat i count [
				space: either func? [spaces/pick i][spaces/:i]
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
			rows: obtain block! 30
			row:  obtain block! count * 4
			row-size: -1x0 * spacing					;-- works because no row is empty, so spacing will be added (count=0 handled above)
			allowed-row-width: ccanvas/:x				;-- how wide rows to allow (splitting margin)
			peak-row-width: 0							;-- used to determine full layout size when canvas is not limited
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
					append (new-row: obtain block! length? row) row
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
			#leaving [foreach [_ _ row] rows [stash row]  stash rows]

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
			#debug sizing [print ["tube c=" canvas "cc=" ccanvas "stripe=" stripe ">> size=" size]]
			#assert [size +< infxinf]
			reduce [size copy map]
		]
	]
	
	ring: context [
		;; settings for ring layout:
		;;   angle       [integer! float!]   unrestricted, defaults to 0
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
				set bind word 'local get word			;@@ check that only allowed words are overwritten
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
				items: obtain block! count * period: 7
				#leaving [stash items]
				
				repeat i count [
					space: either func? [spaces/pick i][spaces/:i]
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
