Red [
	title:    "Geometry-related helper funcs for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.geometry
	depends:  [global clip overload advanced-function map-each]
]


INFxINF: (1.#inf, 1.#inf)								;-- used too often to always type it numerically
;@@ consider: OxINF Ox-INF INFxO -INFxO (so far they don't seem useful)

global by: thru: make op! :as-pair
global .:        make op! :as-point2D					;@@ comma is not for the taking, and adding 3D support will slow it down :(

global abs:  :absolute
global half: func [x] [x / 2]							;-- the appeal of 'half' is in e.g. `half length? pair-list`
round-down:  func [x] [round/to/floor   x 1]
round-up:    func [x] [round/to/ceiling x 1]

global planar!: make typeset! [pair! point2D!]
global linear!: make typeset! [integer! float!]			;@@ or real! ? real is more like single datatype, while linear is a typeset
global planar?: func [value [any-type!]] [find planar! type? :value]
global linear?: func [value [any-type!]] [find linear! type? :value]


;; Ranges are used by /config/limits facet, until such datatype is introduced on the language level.
;; object = 468 B, block = 92 B, map = 272 B; map is smaller than the object and I don't need to bind to ranges
;; Removed 'none' support, as we have infinite and half-infinite point2D! now, and 'none' only adds unnecessary checks.
;; For compatibility (and so, performance) with pair/point ranges, the components were renamed to /1 and /2.
;; 1D and 2D quantities should not be mixed in a single range, to help reasoning and keep things simpler.
;; Ranges are directional (start and end are not equivalents).
global range!: make map! [1 0 2 0]
global range?: func [x [any-type!]] [all [map? :x  [1 2] = keys-of x]]
global ..: make op! make-range: function [				;-- name `to` cannot be used as it's a native
	"Make a range from START to END"
	start [scalar!]
	end   [scalar!]
][
	#assert [(planar? start) = (planar? end)  "Range limits are of different dimensionality!"]
	also range: copy range! (							;-- 30% faster than make map! compose [..], and less allocations
		range/1: start
		range/2: end
	)
]

;; note: this by design may create values not present in the range, e.g. 1x2..3x1 -> 1x1..3x2
global ordered: function [								;-- 'order' implies modification, while 'ordered' hints the value is copied
	"Turn the RANGE into an ordered region"
	range   [planar! map!]
	return: [planar! map!]
][
	result: make range range							;-- 'make' avoids the type-switch to copy the map
	result/1: min range/1 range/2
	result/2: max range/1 range/2
	result
]

#assert [
	1x3        = ordered 3x1
	(1,3)      = ordered (3,1)
	1 .. 3     = ordered 3 .. 1
	1x6 .. 3x9 = ordered 3x6 .. 1x9
]

global span?: function [
	"Get size of the RANGE encoded as a planar! or range! value"
	range [planar! map!]
][
	abs range/2 - range/1
]

#assert [
	2     = span? 3x1
	2     = span? 1 .. 3
	(3,2) = span? (1,5) .. (4,3)
	nan?    span? (1.#inf, 1.#inf)
]

global area?: function [
	"Get area of a box (0,0)..(X,Y)"
	xy [planar!]
][
	either nan? area: xy/x * 1.0 * xy/y [0.0][abs area]	;-- 1.0 to support infxinf here (overflows otherwise)
]

#assert [
	zero? area? (0,0)
	zero? area? (0,1.#inf)								;-- for the purposes of having a tangible area to draw on, INFx0 is empty
	1.#inf = area? (1.#inf,1.#inf)
	1 = area? (-1,1)
]

;; `length?` is taken; `radius?` or `length-of` possible, but not clearer; it's only used in this file anyway
vec-length?: function [v [planar!]] [					;-- this is still 2x faster than compiled `distance? 0x0 v`
	v/x ** 2 + (v/y ** 2) ** 0.5
]

global list: function [									;-- precursor of `list a..b` REP #168, directionality used by list-view selection
	"List all items in the RANGE"
	range   [planar! map!] "Must be finite"
	return: [block!]       "Never empty"
][
	span:   (e: range/2) - (s: range/1)
	step:   pick [1 -1] s <= e							;-- unlike 'sign?', won't return zero 
	result: make [] 1 + abs span
	while pick [[s <= e] [s >= e]] s <= e [				;@@ use map-each
		append result s
		s: s + step
	]
	result
]

#assert [
	[2 3 4]				== list 2x4
	[4 3 2]				== list 4x2
	[4]					== list 4x4
	[0]					== list 0x0
	[-1.0 -2.0 -3.0]	== list (-1, -3)
	[ 1.0  0.0]			== list ( 1, -0.5)
	[-1.0]				== list (-1, -1.5)
	[-1.0]				== list (-1, -0.5)
	[-1.0]				== list (-1, -1)
	[2 3 4]				== list 2 .. 4
	error? try [list (0, 1.#inf)]						;-- error because infinite
	error? try [list 2x3 .. 4x5]						;-- error because no sign is defined
]

~=: make op! function [
	"Fuzzy number comparison"
	a [number!] b [number!]
][
	and~ a - 1e-6 <= b b - 1e-6 <= a					;-- this mainly is used for point2D compares, so precision has to match rounding errors
]

#assert [
	0          ~= 0
	0          ~= 1e-8
	not 0      ~= 1e-4
	1e6        ~= 1.000000000001e6
	1.#INF     ~= 1.#INF
	not 1.#NAN ~= 1.#NAN
]

;; chainable pair comparison - instead of `within?` monstrosity, see also REP #148
;; very hard to find a sigil for these ops
;; + resembles intersecting coordinate axes, so can be read as "2D comparison"
global +<=: make op! func [
	"Chainable 2D comparison (non-strict)"
	a [planar! none!] b [planar!]
][
	all [a a == min a b  b]								;-- strict equality, otherwise 0 <= -1e30 will pass
]
global +<:  make op! func [
	"Chainable 2D comparison (strict)"    
	a [planar! none!] b [planar!]
][
	all [a a/x < b/x a/y < b/y  b]
]

#assert [
	1x1 +<= 1x1
	1x1 +<= (1, 1)
	(1, 1) +<= (1, 1)
	(1, 1) +<= 1x1
	1x1 +< (1.1, 1.1)
	not 1x1 +< 1x1
	not 1x1 +< (1, 1)
	not 1x1 +< (1, 1.1)
	not 1x1 +< (1.1, 1)
	1x1 +< (2, 2) +< 3x3
]

inside?: make op! function [
	"Test if POINT is inside the SPACE"
	point [planar!] space [object!]
][
	within? point 0x0 space/size
]

along: make op! function [
	"Pick PAIR's dimension along AXIS (integer is treated as a square)"
	pair [planar! linear!]
	axis [word!] (find [x y] axis)
][
	pick pair * 1x1 axis
]

ortho: func [
	"Get axis orthogonal to a given one"
	xy [word! pair!] "One of [x y 0x1 1x0]"
][
	switch xy [x ['y] y ['x] 0x1 [1x0] 1x0 [0x1]]				;-- switch here is ~20% faster than select/skip
]

set-pair: function [
	"Set words to components of a pair value"
	words [block!]
	pair  [planar! block!] "Can be a block (works same as set native then)"
][
	set words/1 pair/1
	set words/2 pair/2
]
#hide [#assert [
	a: b: 0
	set-pair [a b] 2x3
	a = 2
	b = 3
	set-pair [a b] [4 5]
	a = 4
	b = 5
]]

set-axis: function [
	"Change VALUE of a given AXIS of an anonymous POINT"
	point [planar!]
	axis  [word!] (find [x y] axis)
	value [linear!]
][
	point/:axis: value
	point
]

#assert [2x3 = set-axis set-axis 0x0 'y 3 'x 2]

global polar->cartesian: function [
	"Transform a 2D polar point (angle, radius) into a cartesian point (x, y)"
	point   [point2D!] "Angle is in degrees"
	return: [point2D!]
][
	as-point2D (point/2 * cosine point/1) (point/2 * sine point/1)
]

global cartesian->polar: function [
	"Transform a 2D cartesian point (x, y) into a polar point (angle, radius)"
	point   [point2D!]
	return: [point2D!] "Angle is in degrees (-180,180]"
][
	as-point2D (arctangent2 point/y point/x) (vec-length? point)
]

global cylindrical->cartesian: function [
	"Transform a 3D cylindrical point (angle, radius, z) into a cartesian point (x, y, z)"
	point   [point3D!] "Angle is in degrees"
	return: [point3D!]
][
	as-point3D (point/2 * cosine point/1) (point/2 * sine point/1) point/3
]

global cartesian->cylindrical: function [
	"Transform a 3D cartesian point (x, y, z) into a cylindrical point (angle, radius, z)"
	point   [point3D!]
	return: [point3D!] "Angle is in degrees (-180,180]"
][
	as-point3D (arctangent2 point/y point/x) (vec-length? point/x . point/y) point/z
]

;@@ consider this for global availability
interpolate: function [									;@@ any better name since it can also be used for extra-polation? estimate?
	"Interpolate a value between V1 and V2"
	v1 [number! planar! point3D! tuple!]				;@@ issue here is not all type combinations will make sense, esp. for /reverse
	v2 [number! planar! point3D! tuple!]
	t  [number!] "[0..1] corresponds to [V1..V2]"
	/clip        "Force T within [0..1], making outside regions constant"
	/reverse     "Treat T as a point on [V1..V2], return a point on [0..1]"
][
	case/all [
		reverse     [t: t - v1 / (v2 - v1)]
		clip        [t: max 0.0 min 1.0 t]
		not reverse [t: v1 * (1.0 - t) + (v2 * t)]
	]
	t
]

#assert [
	50%      = interpolate -100% 200% 0.5
	120.0.60 = interpolate 100.0.0 180.0.240 25%
]


axis->pair: func [xy [word!]] [
	switch xy [x [1x0] y [0x1]]
]

anchor->axis: func [nesw [word!]] [
	switch nesw [n s ↑ ↓ ['y] w e → ← ['x]]				;-- arrows are way more readable, if harder to type (ascii 24-27)
]

; anchor->pair: func [nesw [word!]] [
	; switch nesw [e → [1x0] s ↓ [0x1] n ↑ [0x-1] w ← [-1x0]]
; ]

; normalize-alignment: function [
	; "Turn block alignment into a -1x-1 to 1x1 pair along provided Ox and Oy axes"
	; align [block! pair!] "Pair is just passed through"
	; ox [pair!] oy [pair!]
; ][
	; either pair? align [
		; align
	; ][
		; ;; center/middle are the default and do not need to be specified, but double arrows are still supported ;@@ should be?
		; dict: [n ↑ [0x-1] s ↓ [0x1] e → [1x0] w ← [-1x0] #(none) ↔ ↕ [0x0]]
		; align: ox + oy * add switch align/1 dict switch align/2 dict
		; either ox/x =? 0 [reverse align][align]
	; ]
; ]

normalize-alignment: function [
	"Turn block alignment into a -1x-1 to 1x1 pair along provided Ox and Oy axes"
	align [block! pair!] "Pair is just passed through"
	ox [pair!] oy [pair!]
][
	;; center/middle are the default and do not need to be specified, but double arrows are still supported ;@@ should be?
	dict: [n ↑ [0x-1] s ↓ [0x1] e → [1x0] w ← [-1x0] #(none) ↔ ↕ [0x0]]
	align: ox + oy * add switch align/1 dict switch align/2 dict
	either ox/x =? 0 [reverse align][align]
]
overload :normalize-alignment [align [pair!]] [align]

#assert [
	-1x-1 = normalize-alignment -1x-1  0x1   1x0
	 1x1  = normalize-alignment  1x1   0x1   1x0
	 0x0  = normalize-alignment  0x0   0x1   1x0
	 1x1  = normalize-alignment  1x1   1x0   0x1
	 1x1  = normalize-alignment [n w] -1x0   0x-1
	 1x1  = normalize-alignment [w n] -1x0   0x-1		;-- unordered
	-1x-1 = normalize-alignment [n w]  0x1   1x0
	 1x-1 = normalize-alignment [n w]  0x-1  1x0		;-- swapped vertical X => change in /1
	 1x1  = normalize-alignment [n w]  0x-1 -1x0		;-- swapped horizontal Y => change in /2
	-1x1  = normalize-alignment [n w]  0x1  -1x0
	-1x-1 = normalize-alignment [n e]  0x1  -1x0
	-1x-1 = normalize-alignment [↑ →]  0x1  -1x0		;-- arrows support
	 0x-1 = normalize-alignment  [e]   0x1  -1x0		;-- no vertical alignment => no vertical X => no /1
	 1x0  = normalize-alignment  [s]   0x1  -1x0		;-- no horizontal alignment => no horizontal Y => no /2
	 0x0  = normalize-alignment  []    0x1  -1x0		;-- no alignment => no axes => no /1 or /2
]


segments-overlap?: function [
	"Get nonzero intersection size of segments A1-A2 and B1-B2, or none if they don't intersect"
	A1 [linear!] A2 [linear!]
	B1 [linear!] B2 [linear!]
][
	sec: (min A2 B2) - max A1 B1
	all [sec > 0 sec]									;-- 0 < intersection size
]

boxes-overlap?: function [
	"Get nonzero intersection size of boxes A1-A2 and B1-B2, or none if they don't intersect"
	A1 [planar!] A2 [planar!]
	B1 [planar!] B2 [planar!]
][
	(0,0) +< ((min A2 B2) - max A1 B1)					;-- 0x0 +< intersection size
]

#assert [
	not   boxes-overlap? -2x-2 -1x-1 1x1 2x2
	not   boxes-overlap? -2x1 -1x2 1x-2 2x-1
	not   boxes-overlap? -2x-2 0x0 0x0 2x2
	2x2 = boxes-overlap? -2x-2 1x1 -1x-1 2x2
	2x2 = boxes-overlap? -2x-1 1x2 -1x-2 2x1
]

closest-box-point?: function [
	"Get coordinates of the point on box B1-B2 closest to ORIGIN"
	B1 [planar!] "inclusive" B2 [planar!] "inclusive"
	/to origin: (0,0) [planar!] "defaults to 0x0"
][
	clip origin B1 B2
]

box-distance?: function [
	"Get distance between closest points of box A1-A2 and box B1-B2 (negative if overlap)"
	A1 [planar!] "inclusive" A2 [planar!] "non-inclusive"
	B1 [planar!] "inclusive" B2 [planar!] "non-inclusive"
][
	either isec: boxes-overlap? A1 A2 B1 B2 [			;-- case needed by box arrangement algo
		negate min isec/x isec/y
	][
		AC: A1 + A2 / 2
		BC: B1 + B2 / 2
		AP: closest-box-point?/to A1 A2 BC
		BP: closest-box-point?/to B1 B2 AP
		vec-length? BP - AP
	]
]
; test for it:
; view [a: base 100x20 loose b: base 20x100 loose return t: text 100 react [t/text: form box-distance? a/offset a/offset + a/size b/offset b/offset + b/size]]


;; constraining is used by `render` to impose soft limits on space sizes
global constrain: function [
	"Clip SIZE within LIMITS"
	size    [planar!] "Use INFxINF for unlimited"
	limits  [map! (range? limits) none!] "none if no limits"
][
	unless limits [return size]							;-- most common case optimization
	min: switch/default type?/word limits/1 [			;@@ /word was for #5387, remove it later
		pair! point2D!  [limits/1]
		integer! float! [limits/1 . 0]					;-- numeric limits only affect /x
	] [0x0]												;-- invalid treated as 0x0 .. INFxINF
	max: switch/default type?/word limits/2 [
		pair! point2D!  [limits/2]
		integer! float! [limits/2 . 1.#inf]				;-- numeric limits only affect /x
	] [INFxINF]											;-- invalid treated as 0x0 .. INFxINF
	clip size min max									;-- this could be optimized, but since /limits are mostly 'none' I see no point
]

#assert [
	INFxINF = constrain INFxINF none
	(20,16) = constrain 8x16 20 .. 1.#inf
	(20,50) = constrain 8x50 20x50 .. INFxINF
]


update-EMA: function [
	"Update exponential moving average with new parameter measurements"
	estimate    [word! path!] "Current EMA"
	measurement [number!]     "New measurement result"
	period      [integer!]    "Averaging period"
	/batch num: 1 [integer!]  "Apply a whole batch of identical measurements"
][
	weight: 1 - (1 / period) ** num
	set estimate
		to type? get estimate							;-- required when modifying component of a pair
		interpolate measurement (get estimate) weight
]


;@@ unless this can be generalized, move it into the paragraph template
build-index: reproject: reproject-range: none			;-- don't make these global, keep in spaces/ctx
context [
	;@@ can parts of this context be generalized and put into /common?
	;@@ maybe indexed search can be included into %search.red?
	
	set 'build-index function [
		"Build an index of given length for fast search over points"
		points [block! vector!] (4 <= length? points)
		length [integer!] (length >= 1)
	][
		#assert [all [points/1 = 0 points/2 = 0]]		;@@ I may want to generalize it later, but no need yet
		yindex: copy xindex: make vector! length
		clear xindex  clear yindex
		top:    skip tail points -2
		xrange: max 1e-10 top/1 - points/1				;-- 1e-10 to avoid zero division by step
		yrange: max 1e-10 top/2 - points/2
		dx: xrange * 1.000001 / length					;-- stretch a bit to ensure never picking at the tail
		dy: yrange * 1.000001 / length
		ix: iy: 1
		ipoint: -1  foreach [xi yi] next next points [	;@@ use for-each/reverse?
			ipoint: ipoint + 2
			ix: 1 + to integer! xi / dx
			iy: 1 + to integer! yi / dy
			append/dup xindex ipoint     ix - length? xindex
			append/dup yindex ipoint + 1 iy - length? yindex
		]
		obj: construct [points: xstep: ystep: xindex: yindex:]
		set obj reduce [points  dx     dy     xindex  yindex]
		obj
	]
	#assert [
		[1]     = to [] select build-index [0 0 2 2 6 6 8 8 10 10] 1 'xindex
		[2]     = to [] select build-index [0 0 2 2 6 6 8 8 10 10] 1 'yindex
		[1 3]   = to [] select build-index [0 0 2 2 6 6 8 8 10 10] 2 'xindex
		[2 4]   = to [] select build-index [0 0 2 2 6 6 8 8 10 10] 2 'yindex
		[1 3 5] = to [] select build-index [0 0 2 2 6 6 8 8 10 10] 3 'xindex
		[2 4 6] = to [] select build-index [0 0 2 2 6 6 8 8 10 10] 3 'yindex
		[1 3 5] = to [] select build-index [0 0 2 2 6 6 10 10] 3     'xindex
		[2 4 6] = to [] select build-index [0 0 2 2 6 6 10 10] 3     'yindex
		[1 1 5] = to [] select build-index [0 0 4 4 6 6 10 10] 3     'xindex
		[2 2 6] = to [] select build-index [0 0 4 4 6 6 10 10] 3     'yindex
		[1 1 3] = to [] select build-index [0 0 5 5 10 10] 3         'xindex
		[2 2 4] = to [] select build-index [0 0 5 5 10 10] 3         'yindex
	]
	
	locate: function [
		points [block!]
		index  [vector!]
		step   [number!] (step > 0)
		value  [number!]
	][
		#assert [value / step < length? index  "value out of the function's domain"]
		pos: at points pick index 1 + to integer! value / step
		;; find *first* segment that contains the value
		while [all [pos/5 value > pos/3]] [pos: skip pos 2]		;@@ use general locate when fast
		#assert [all [pos/1 <= value  value <= (pos/3 + 0.1)]]	;-- 0.1 to account for rounding error
		pos
	]
	find-x: function [fun [object!] x [number!]] [
		locate fun/points fun/xindex fun/xstep x
	]
	find-y: function [fun [object!] y [number!]] [
		locate fun/points fun/yindex fun/ystep y
	]
	#hide [#assert [
		f: build-index [0 0 1 2 2 4 2 5 4 8] 3
		[1 1 3 3 7 7 7] = map-each x [0 1 1.1 2 2.1 3.9 4] [index? find-x f x]
		[2 2 4 4 6 8 8] = map-each y [0 2 2.1 4 4.1 5.1 8] [index? find-y f y]
	]]
	
	;; 'reproject' meaning get inverse projection from X to function line and then project into Y
	;@@ maybe there's a better name I don't see yet... X2Y and Y2X func pair?
	set 'reproject function [
		"Find value Y=F(X) given X on a non-decreasing function"
		fun [object!] "Indexed function as a sequence of points [X1 Y1 ... Xn Yn]"
		x   [number!] "X value"
		/up       "If Y is not unique, return highest corresponding value (default: lowest)"
		/inverse  "Given Y find an X"
		/truncate "Convert result to integer"
	][
		xs: either inverse [find-y fun x][find-x fun x]
		;; find *last* segment that contains the value
		if up [while [all [xs/5  xs/3 <= x]] [xs: skip xs 2]]	;@@ use for-each
		ys: either inverse [back xs][next xs]
		t: either xs/1 == xs/3 [						;-- avoid zero-division
			either up [1][0]
		][
 			clip 0 1 x - xs/1 / (xs/3 - xs/1)			;-- clip to work around rounding issues
		]
		y: interpolate ys/1 ys/3 t
		if truncate [y: to integer! y]
		y
	]
	comment [											;-- interactive test
		f: build-index [0 0 1 2 2 4 2 5 4 5 7 8]
		sc: 400 / 8
		view [
			base white 400x400 all-over on-over [try [
				trace: map-each [x y] f/points [as-point2D sc * x sc * y]
				x: event/offset/x / sc
				y: event/offset/y / sc
				y1: sc * reproject    f x
				y2: sc * reproject/up f x
				x1: sc * reproject/inverse    f y
				x2: sc * reproject/inverse/up f y
				face/draw: compose/deep [
					pen magenta line (trace)
					pen cyan
					shape [
						move (event/offset) vline (y1)
						move (event/offset) hline (x1)
						move (0 by y1) 'hline (event/offset/x)
						move (0 by y2) 'hline (event/offset/x)
						move (x1 by 0) 'vline (event/offset/y)
						move (x2 by 0) 'vline (event/offset/y)
					]
				]
			]]
		]
	]
	
	set 'reproject-range function [
		"Return segment [Y1 Y2] projected by function FUN from segment [X1 X2]"
		fun [object!] "Indexed function as a sequence of points [X1 Y1 ... Xn Yn]"
		x1  [number!]
		x2  [number!] (x2 >= x1)
		/inverse  "Given Ys find Xs"
		/truncate "Convert result to integers"
	][
		reduce [
			reproject/:inverse/:truncate    fun x1
			reproject/:inverse/:truncate/up fun x2
		]
	]
]

