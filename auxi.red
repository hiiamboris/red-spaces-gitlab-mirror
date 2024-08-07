Red [
	title:   "Auxiliary helper funcs for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

; #include %../common/assert.red
;@@ not sure if infxinf should be exported, but it's used by custom styles, e.g. spiral
exports: [by thru . abs half skip? linear! linear? planar! planar? range! range? make-range .. using when only trigger impose clip ortho boxes-overlap? infxinf opaque blend batch]

; ;; readability helper instead of reduce/into [] clear [] ugliness
; #macro [#reduce-in-place block!] func [[manual] s e] [
	; change/only s 'reduce/into
	; insert/only insert e 'clear copy []
	; s
; ]

; ;@@ watch out for #5009 for a better way to specify refinements
; #macro [#compose-in-place any refinement! block!] func [[manual] s e /local path] [
	; path: copy 'compose/into
	; e: next s
	; while [refinement? :e/1] [append path to word! take e]
	; change/only s path
	; insert/only insert e 'clear copy []
	; s
; ]

by: thru: make op! :as-pair
.:        make op! :as-point2D							;@@ unfortunately, comma is not for the taking :(
abs: :absolute
svf:  system/view/fonts
svm:  system/view/metrics
svmc: system/view/metrics/colors

digit!: charset [#"0" - #"9"]							;@@ add typical charsets to /common repo

INFxINF: (1.#inf, 1.#inf)								;-- used too often to always type it numerically
;@@ consider: OxINF Ox-INF INFxO -INFxO (so far they don't seem useful)

skip?: func [series [series!]] [-1 + index? series]

half: func [x] [x / 2]
round-down: func [x] [round/to/floor   x 1]
round-up:   func [x] [round/to/ceiling x 1]

planar!: make typeset! [pair! point2D!]
linear!: make typeset! [integer! float!]				;@@ or real! ? real is more like single datatype, while linear is a typeset
planar?: func [value [any-type!]] [find planar! type? :value]
linear?: func [value [any-type!]] [find linear! type? :value]

along: make op! function [
	"Pick PAIR's dimension along AXIS (integer is treated as a square)"
	pair [planar! linear!]
	axis [word!] (find [x y] axis)
][
	pick pair * 1x1 axis
]

block-of?: make op! func [
	"Test if all of BLOCK's values are of type TYPE"
	block [block!] type [datatype!]
][
	parse block [any type]
]

using: function [
	"Return CODE bound to a context with WORDS local to it"
	words [block!] "List of words" (words block-of? word!)
	code  [block!]
][
	words: construct map-each w words [to set-word! w]
	with words code
]

get-safe: function [path [path! word!]] [				;@@ REP 113; this in case of error is 10x slower than 'get'
	try [return x: get path] none						;@@ workaround for #5300 here
]

; set-many: function [
	; "Set each target to a result of the corresponding expression evaluation"
	; targets [block!] exprs [block!]
; ][
	; forall targets [set :targets/1 do/next exprs 'exprs]
	; exprs
; ]


;@@ copy/deep does not copy inner maps (#2167), clone tries to encode system/words, so this kludge is still must have
copy-deep-map: function [m [map!]] [
	m: make map! copy/deep to [] m						;@@ workaround for copy/deep #(map) not copying nested strings/blocks
	foreach [k v] m [if map? :v [m/:k: copy-deep-map v]]
	m
]

clone: function [										;@@ should space cloning be based on this?
	"Obtain a complete deep copy of the data"
	data [any-object! map! series!]
	/flat "Make a shallow copy (unlike native copy, keeps items before head)"
] with system/codecs/redbin reshape [
	either flat [
		switch type?/word :data [
			@(to [] series!) [
				at	append (clear copy head data) head data
					index? data
			]
			map! @(to [] any-object!) [copy data] 
		]
	][
		decode encode data none
	]
]

;; ranges support needed by layout, until such datatype is introduced, have to do with this
;; since it's for layout usage only, I don't care about a few allocated objects, no need to optimize it
;; ranges are used by spaces to constrain their size, but those are read-only
;; object = 468 B, block = 92 B, map = 272 B (cannot be reacted to)
;; space with draw=[] = 512 B, rectangle = 1196 B, timer does not need this at all
range!: object [min: max: none]
range?: func [x [any-type!]] [all [object? :x (class-of x) = class-of range!]]
..: make op! make-range: function [						;-- name `to` cannot be used as it's a native
	"Make a range from A to B"
	a [scalar! none!]
	b [scalar! none!]
][
	#assert [any [not a  not b  b >= a]  "Reversed limits detected!"]
	make range! [min: a max: b]
]


;; kludges for very limited bitset functionality
nonzero-byte: charset [1 - 255]
lowest-bit: function [bs [bitset!]] [
	if bs/0 [return 0]									;-- negated bitset?
	bin: to #{} bs
	unless p: find bin nonzero-byte [return none]
	base: 8 * skip? p
	repeat i 8 [if find bs bit: base + i - 1 [break]]
	bit
]

highest-bit: function [bs [bitset!]] [
	if bs/2'147'483'647 [return none]					;-- negated bitset
	bin: to #{} bs
	unless p: find/last bin nonzero-byte [return none]
	base: 8 * skip? p
	repeat i 8 [if find bs bit: base + 8 - i [break]]
	bit
]

#assert [
	none? lowest-bit  charset []
	none? highest-bit charset []
	none? highest-bit make bitset! 100
	0  = lowest-bit  charset [0  - 20]
	3  = lowest-bit  charset [3  - 20]
	18 = lowest-bit  charset [18 - 20]
	20 = highest-bit charset [0  - 20]
	17 = highest-bit charset [3  - 17]
	4  = highest-bit charset [3  - 4]
]

unroll-bitset: function [bs [bitset!]] [
	result: clear []
	if lo: lowest-bit bs [
		hi: highest-bit bs
		for i: lo hi [if bs/:i [append result i]]		;@@ this is really dumb
	]
	copy result
]


{
	useful pair invariants to test in which quadrant a point is located
	points: a, b
	a = min a b <=> 0x0 = min 0x0 b - a <=> B is in Q1 to A, axis-inclusive <=> A is in Q3 to B, axis-inclusive
	a = max a b <=> 0x0 = max 0x0 b - a <=> B is in Q3 to A, axis-inclusive <=> A is in Q1 to B, axis-inclusive
	                1x1 = min 1x1 b - a <=> B is in Q1 to A, axis-exclusive <=> A is in Q3 to B, axis-exclusive
	            -1x-1 = max -1x-1 b - a <=> B is in Q3 to A, axis-exclusive <=> A is in Q1 to B, axis-exclusive
	a = min a b <=> b = max a b   
}

;; chainable pair comparison - instead of `within?` monstrosity
; >> 1x1 +< 2x2 +<= 3x3 +< 4x4
; == 4x4

;; very hard to find a sigil for these ops
;; + resembles intersecting coordinate axes, so can be read as "2D comparison"
+<=: make op! func [
	"Chainable pair comparison (non-strict)"
	a [planar! none!] b [planar!]
][
	all [a a == min a b  b]								;-- strict equality, otherwise 0 <= -1e30 will pass
	; all [a a/x <= b/x a/y <= b/y  b]
]
+<:  make op! func [
	"Chainable pair comparison (strict)"    
	a [planar! none!] b [planar!]
][
	all [a a/x < b/x a/y < b/y  b]
]
;+>:  make op! func [a b] [a = max a b + 1]
;+>=: make op! func [a b] [a = max a b]

inside?: make op! function [
	"Test if POINT is inside the SPACE"
	point [planar!] space [object!]
][
	within? point 0x0 space/size
]

above: function [										;-- a replacement for space/parent/parent/parent/parent shit
	"Get parent space of specific type (or none)"
	child [object!]
	type  [word!]
][
	while [space? child: child/parent] [if child/type = type [return child]]	;@@ use locate + tree iterator
	child
]

host-of: function [space [object!]] [
	all [path: get-host-path space  path/1]
]

host-box-of: function [									;@@ temporary until REP #144
	"Get host coordinates of a space (kludge! not scaling aware!)"
	space [object!] (space? space)
][
	box: reduce [(0,0) space/size]	
	while [parent: space/parent] [
		if host? parent [return box]
		#assert [select parent 'map]
		geom: select/same parent/map space
		#assert [geom]
		forall box [box/1: box/1 + geom/offset]
		space: parent
	]
	none
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

segments-overlap?: function [
	"Get nonzero intersection size of segments A1-A2 and B1-B2, or none if they don't intersect"
	A1 [linear!] A2 [linear!]
	B1 [linear!] B2 [linear!]
][
	sec: (min A2 B2) - max A1 B1
	all [sec > 0 sec]									;-- 0 < intersection size
]

vec-length?: function [v [planar!]] [					;-- this is still 2x faster than compiled `distance? 0x0 v`
	v/x ** 2 + (v/y ** 2) ** 0.5
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

~=: make op! function [a [number!] b [number!]] [
	to logic! any [
		a = b
		(abs a - b) < 1e-6
	]
]

; slope?: function [
	; "Get the slope of the line (X1,Y1)-(X2,Y2)"
	; x1 [float!] y1 [float!]
	; x2 [float!] y2 [float!]
; ][
	; (y2 - y1) / (x2 - x1)
; ]


;@@ move into common?
make-stack: function [
	"Create a stack of given row size"
	size [pair!] (size/1 > 0) "row size X row count"
][
	context [
		data:  make [] size/1 * size/2
		push:  func [values [block!]] [data: tail reduce/into values data]
		pop:   does compose [clear data: skip data (negate size/1)]
		top:   does compose [skip data (negate size/1)]
		empty: does [data: clear head data]
	]
]


; block-buffers: make hash! 100
; buffer-for: function [block [block!]] [
	; any [
		; clear buf: select/only/same/skip buffers block 2	;@@ unfortunately #4466 - search is linear
		; repend buffers [buf: copy []]
	; ]
	; buf
; ]
; cached-reduce: function [block [block!]] [
	; reduce/into block buffer-for block
; ]
; cached-compose: function [block [block!]] [
	; compose/into block buffer-for block
; ]


;; MEMO: requires `function` scope or `~~p` will leak out
#macro [#expect skip] func [[manual] bgn end /local quote? rule error name] [
	quote?: all [word? bgn/2  bgn/2 = 'quote  remove next bgn]
	rule: reduce [bgn/2]
	if quote? [insert rule 'quote]						;-- sometimes need to match block literally
	name: either string? bgn/2 [bgn/2][mold/flat bgn/2]
	error: compose/deep [
		do make error! rejoin [
			(rejoin ["Expected "name" at: "]) mold/part ~~p 100
		]
	]
	change/only remove bgn compose [(rule) | ~~p: (to paren! error)]
	bgn 
]


;@@ move this into /common once debugged
in-out-func: function [spec [block!] body [block!]] [
	lit-words: keep-type spec lit-word!
	block-rule: [any [
		ahead set w get-word! if (find lit-words w)
		change only skip (as paren! reduce ['get/any to word! w])
	|	ahead set w word!     if (find lit-words w)
		change only skip (as paren! reduce ['get to word! w])
	|	ahead set w set-word! if (find lit-words w)
		insert ('set) change skip (to word! w)
	|	ahead any-list! into block-rule
	|	ahead any-path! into path-rule
	|	ahead word! 'quote skip
	|	skip
	]]
	path-rule: [any [
		ahead set w get-word! if (find lit-words w) change only skip (as paren! reduce ['get/any to word! w])
	|	ahead any-list! into block-rule
	|	skip
	]]
	parse body: copy/deep body block-rule
	function spec body
]


include-into: function [
	"Include flag into series if it's not there"
	series [series!] flag [any-type!]
][
	unless find/only series :flag [append/only series :flag]
	series
]

exclude-from: function [
	"Exclude flag into series if it's there"
	series [series!] flag [any-type!]
][
	remove find/only series :flag
	series
]

set-flag: function [
	"Include or exclude flag from series depending on present? value"
	series [series!] flag [any-type!] present? [logic! none!]
][
	either present? [include-into series :flag][exclude-from series :flag]
]

has-flag?: function [									;-- used in popups
	"Test if FLAGS is a block and contains FLAG"
	flags [any-type!]
	flag  [word!]
][
	none <> all [block? :flags  find flags flag]
]

toggle: function [
	"Flip the value of a boolean flag"
	flag [path!]
][
	set flag not get flag
]

trigger: function [
	"Trigger on-change reaction on the target"
	target [word! path!]
][
	set/any target get/any target
]


flush: function [
	"Grab a copy of SERIES, clearing the original"
	series [series!]
][
	also copy series clear series
]

before: function [
	"Set PATH to VALUE, but return the previous value of PATH"
	'path [any-path! any-word!] value
][
	also get path set path :value 
]

explode: function [										;@@ use map-each when fast; split produces strings not chars :(
	"Split string into a block of characters"
	string [string!]
	/into buffer [any-list!]
][
	unless buffer [buffer: make [] length? string]
	parse string [collect after buffer keep pick to end]
	buffer
]

zip: function [
	"Interleave a list with another list or scalar"
	list1 [series!]
	list2 [any-type!]
	/into result: (make list1 2 * length? list1) [series!]
][
	#assert [any [not series? :list2  equal? length? list1 length? list2]]
	repeat i length? list1 pick [
		[append/only append/only result :list1/:i :list2/:i]
		[append/only append/only result :list1/:i :list2]
	] series? :list2
	result
]
#assert [
	""              = zip "" []
	[]              = zip [] []
	[1 2 3 4]       = zip [1 3] [2 4]
	[1 #"2" 3 #"4"] = zip [1 3] "24"
	"1234"          = zip "13" [2 4]
	"1-3-"          = zip "13" #"-"
]

;@@ make a REP with this? (need use cases)
;@@ this is no good, because it treats paths as series
native-swap: :system/words/swap
swap: function [a [word! series!] b [word! series!]] [
	either series? a [
		native-swap a b
	][
		set a before (b) get a
	]
]

only: function [
	"Turn falsy values into empty block (useful for composing Draw code)"
	value [any-type!] "Any truthy value is passed through"
][
	any [:value []]		;-- block is better than unset here because can be used in set-word assignments
]

;-- `compose` readability helper variant 2
; when: func [test value] [only if :test [do :value]]

;-- `compose` readability helper variant 3
;-- by the way, works in rejoin/composite as empty block results in empty string!!!
when: func [
	"If TEST is truthy, return VALUE, otherwise an empty block"
	test   [any-type!]
	:value [any-type!] "Paren is evaluated, block or other value is returned as is"
][
	only if :test [either paren? :value [do value][:value]]
]

;-- simple shortcut for `compose` to produce blocks only where needed
wrap: func [
	"Put VALUE into a block"
	value [any-type!]
][
	reduce [:value]
]

remake: function [proto [object! datatype!] spec [block!]] [
	construct/only/with compose/only spec proto
]

area?: function [xy [planar!]] [
	either nan? area: xy/x * 1.0 * xy/y [0.0][area]		;-- 1.0 to support infxinf here (overflows otherwise)
]
#assert [
	zero? area? (0,0)
	zero? area? (0,1.#inf)								;-- for the purposes of having a tangible area to draw on, INFx0 is empty
	1.#inf = area? (1.#inf,1.#inf)
]
span?: func [xy [planar!]] [abs xy/y - xy/x]			;@@ or range? but range? tests for range! class
order-pair: function [xy [planar!]] [either xy/1 <= xy/2 [xy][reverse xy]]
order: function [a [word! path!] b [word! path!]] [		;@@ should this receive a block of any number of paths?
	if greater? get a get b [set a before (b) get a]
]

bit-range: func [range [pair!]] [
	range: order-pair range
	charset reduce [range/1 '- range/2]
]


;@@ this should be just `clip` but min/max have no vector support
clip-vector: function [v1 [vector!] v2 [vector!] v3 [vector!]] [
	repeat i length? r: copy v1 [r/:i: clip v1/:i v2/:i v3/:i]
	r
]

resolve-color: function [color [tuple! word! issue!]] [
	case [
		word?  color [svmc/:color]
		issue? color [hex-to-rgb color]
		'else [color]
	]
]

impose: function [
	"Impose COLOR onto BGND and return the resulting color"
	bgnd  [tuple! word!] "Alpha channel ignored"
	color [tuple! word!] "Alpha channel determines blending amount"
][
	c3: c4: (resolve-color color) + 0.0.0.0
	c3/4: none
	bg-amnt: c4/4 / 255
	(resolve-color bgnd) * bg-amnt + (1 - bg-amnt * c3)
]

#assert [
	0.0.0   = impose 0.0.0     0.0.0
	0.0.0   = impose 100.50.10 0.0.0
	50.25.5 = impose 100.50.10 0.0.0.128
]


HSL2XYZ: function [
	"Transform HSL cylindrical coordinate into cartesian XYZ"
	HSL [point3D!]
][
	as-point3D
		HSL/2 * cosine HSL/1
		HSL/2 * sine   HSL/1
		HSL/3
]

XYZ2HSL: function [
	"Transform cartesian XYZ coordinate into HSL cylindrical"
	XYZ [point3D!]
][
	as-point3D
		(arctangent2 XYZ/2 XYZ/1) + 360 % 360			;-- map [-180,180] into [0,360)
		vec-length? XYZ/1 . XYZ/2						;-- this doesn't check if it's >1, assumes correct
		XYZ/3
]

blend: function [
	"Get new color from a projection of BGND->COLOR vector scaled by AMNT (alpha channels ignored)"
	bgnd  [tuple! word!]
	color [tuple! word!]
	amnt  [number!] "< 100% to pull color closer to bgnd, > 100% to push further"
][
	;; in XYZ space it's possible to e.g. push red->green towards cyan
	bg-xyz: HSL2XYZ RGB2HSL resolve-color bgnd
	fg-xyz: HSL2XYZ RGB2HSL resolve-color color
	hsl: XYZ2HSL fg-xyz - bg-xyz * (clip -1e10 1e10 amnt) + bg-xyz	;-- avoid 1.#inf - leads to unwanted NaNs
	HSL2RGB/tuple clip (0,0,0) (360,1,1) hsl
]

#assert [
	255.0.0    = blend red green  0
	0.255.0    = blend red green  1
	191.191.63 = blend red green  0.5
	255.0.81   = blend red green -1
	0.255.81   = blend red green  2
	255.0.127  = blend red green -1.#inf
	0.255.127  = blend red green  1.#inf
]

enhance: function [
	"Push COLOR further from BGND (alpha channels ignored)"
	bgnd  [tuple! word!]
	color [tuple! word!]
	amnt  [number!] "Should be over 100%" (amnt >= 100%)
][
	bg-hsl: RGB2HSL resolve-color bgnd
	fg-hsl: RGB2HSL resolve-color color
	sign: pick [1 -1] fg-hsl/3 >= bg-hsl/3
	fg-hsl/3: clip 0 1 fg-hsl/3 + (amnt - 1 / 2 * sign)
	HSL2RGB/tuple fg-hsl
]

;@@ any better name?
opaque: function [
	"Add alpha channel to the COLOR"
	color [tuple! word! issue!] "If a word, looked up in system/view/metrics/colors"
	alpha [percent! float!] (all [0 <= alpha alpha <= 1])
][
	color: 0.0.0.0 + resolve-color color
	color/4: to integer! 255 - (255 - color/4 * alpha)
	color
]


list-range: function [a [integer!] b [integer!]] [		;-- directional by design (used by list-view selection)
	step:   sign? range: b - a
	result: make [] 1 + abs range
	append result a
	while [a <> b] [append result a: a + step]			;@@ use map-each
	result
]

min-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b min a b] a b]
]

max-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b max a b] a b]
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
		add (get estimate) * weight measurement * (1 - weight)
]

interpolate: function [
	"Interpolate a value between V1 and V2"
	v1 [number!]
	v2 [number!]
	t  [number!] "[0..1] corresponds to [V1..V2]"
	/clip        "Force T within [0..1], making outside regions constant"
	/reverse     "Treat T as a point on [V1..V2], return a point on [0..1]"
][
	case/all [
		reverse     [t: t - v1 / (v2 - v1)]
		clip        [t: max 0.0 min 1.0 t]
		not reverse [t: add  v1 * (1.0 - t)  v2 * t]
	]
	t
]

#assert [
	50% = interpolate -100% 200% 0.5
]

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

;; constraining is used by `render` to impose soft limits on space sizes
constrain: function [
	"Clip SIZE within LIMITS"
	size    [planar!] "use infxinf for unlimited; negative size will become zero"
	limits  [object! (range? limits) none!] "none if no limits"
][
	unless limits [return size]							;-- most common case optimization
	;@@ NOTE: always use type?/word, not type? here, otherwise construction syntax is lost during 'inline' call
	;@@ see #5387
	min: switch/default type?/word limits/min [
		pair! point2D!  [limits/min]
		integer! float! [limits/min . 0]				;-- numeric limits only affect /x
	] [0x0]												;-- none and invalid treated as 0x0
	max: switch/default type?/word limits/max [
		pair! point2D!  [limits/max]
		integer! float! [limits/max . 1.#inf]			;-- numeric limits only affect /x
	] [infxinf]											;-- none and invalid treated as infinity
	clip size min max
]

#assert [
	infxinf = constrain infxinf none
	(20,16) = constrain 8x16 20 .. none
]

;@@ rewrite this using inoutfunc?
for: function ['word [word! set-word!] i1 [integer! pair!] i2 [integer! pair!] (same? type? i1 type? i2) code [block!]] [
	either integer? i1 [
		if i2 < i1 [exit]			;@@ return none or unset? `while` return value is buggy anyway
		set word i1 - 1
		while [i2 >= set word 1 + get word] code
	][
		range: i2 - i1 + 1
		unless 1x1 +<= range [exit]	;-- empty range
		xyloop i: range [
			set word i - 1 + i1		;@@ does not allow index changes within the code, but allows in integer part above
			do code
		]
	]
]

closest-number: function [n [number!] list [block!]] [
	p: remove find/case (sort append list n) n
	case [
		head? p [p/1]
		tail? p [p/-1]
		(n - p/-1) < (p/1 - n) [p/-1]
		'else   [p/1]
	]
]

#assert [
	3 = closest-number 3 [1 2 3]
	3 = closest-number 3 [3 4 5]
	3 = closest-number 1 [3 4 5]
	3 = closest-number 3 [1 4 5 3 2]
	4 = closest-number 3 [1 4 5 0]
]


polar2cartesian: func [radius [linear!] angle [linear!]] [
	as-point2D (radius * cosine angle) (radius * sine angle)
]

ortho: func [
	"Get axis orthogonal to a given one"
	xy [word! pair!] "One of [x y 0x1 1x0]"
][
	;; switch here is ~20% faster than select/skip
	; select/skip [x y y x 0x1 1x0 1x0 0x1] xy 2
	switch xy [x ['y] y ['x] 0x1 [1x0] 1x0 [0x1]]
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

axis2pair: func [xy [word!]] [
	switch xy [x [1x0] y [0x1]]
]

anchor2axis: func [nesw [word!]] [
	; switch nesw [n s ['y] w e ['x]];
	switch nesw [n s ↑ ↓ ['y] w e → ← ['x]]				;-- arrows are way more readable, if harder to type (ascii 24-27)
]

anchor2pair: func [nesw [word!]] [
	; switch nesw [n [0x-1] s [0x1] w [-1x0] e [1x0]]
	switch nesw [e → [1x0] s ↓ [0x1] n ↑ [0x-1] w ← [-1x0]]
]

normalize-alignment: function [
	"Turn block alignment into a -1x-1 to 1x1 pair along provided Ox and Oy axes"
	align [block! pair!] "Pair is just passed through"
	ox [pair!] oy [pair!]
][
	either pair? align [
		align
	][
		;; center/middle are the default and do not need to be specified, but double arrows are still supported ;@@ should be?
		dict: [n ↑ [0x-1] s ↓ [0x1] e → [1x0] w ← [-1x0] #(none) ↔ ↕ [0x0]]
		align: ox + oy * add switch align/1 dict switch align/2 dict
		either ox/x =? 0 [reverse align][align]
	]
]

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


decode-canvas: function [
	"Turn pair canvas into positive value and fill flags"
	canvas [point2D!] "can be positive or infinite (no fill), negative (fill)"
][
	reduce/into [
		abs canvas
		canvas/x < 0									;-- only true if strictly negative, not zero
		canvas/y < 0
	] clear []
]

#assert [
	(reduce [infxinf   no  no]) = decode-canvas infxinf
	(reduce [(10, 20)  no  no]) = decode-canvas ( 10,  20)
	(reduce [(10, 20) yes yes]) = decode-canvas (-10, -20)
	(reduce [(10,  0)  no  no]) = decode-canvas ( 10,   0)	;-- zero is fill=false
]

encode-canvas: function [
	|canvas| [point2D!] (0x0 +<= |canvas|)
	fill-x   [logic!]
	fill-y   [logic!]
][
	x-sign: any [all [fill-x |canvas|/x < 1.#inf -1] 1]	;-- finite part may flip sign
	y-sign: any [all [fill-y |canvas|/y < 1.#inf -1] 1]	;-- infinite part stays positive
	x-sign . y-sign * |canvas|
]

#hide [#assert [
	reencode: func [b] [encode-canvas b/1 b/2 b/3]
	infxinf   = reencode decode-canvas  infxinf
	( 10, 20) = reencode decode-canvas ( 10, 20)
	(-10,-20) = reencode decode-canvas (-10,-20)
	( 10,  0) = reencode decode-canvas ( 10,  0)
	infxinf   = encode-canvas infxinf yes yes			;-- must not become negative infinity
	infxinf   = encode-canvas infxinf yes no
]]


finite-canvas: function [
	"Turn infinite dimensions of CANVAS into zero"
	canvas [point2D!] (0x0 +<= canvas)
][
	case/all [
		canvas/x = 1.#inf [canvas/x: 0]
		canvas/y = 1.#inf [canvas/y: 0]
	]
	canvas
]

#assert [(0,20) = finite-canvas infxinf/x . 20]

extend-canvas: function [
	"Make one of CANVAS dimensions infinite"
	canvas [point2D!]
	axis   [word!] "X or Y" (find [x y] axis)
][
	canvas/:axis: infxinf/x
	canvas
]

;; useful to subtract margins, but only from finite dimensions
subtract-canvas: function [
	"Subtract PAIR from CANVAS if it's finite, rounding negative results to 0x0"
	canvas [point2D!]
	pair   [planar!]
][
	max canvas - pair 0x0
]

#assert [( 60, 1.#inf) = subtract-canvas (100, 1.#inf) 40x30]
#assert [(  0, 1.#inf) = subtract-canvas ( 20, 1.#inf) 40x30]

fill-canvas: function [
	"Set unfilled and infinite canvas dimensions to zero"
	canvas [point2D!] fill-x [logic!] fill-y [logic!]
][
	as-point2D
		either all [fill-x canvas/x < 1.#inf] [canvas/x][0] 
		either all [fill-y canvas/y < 1.#inf] [canvas/y][0] 
]

top: func [
	"Return SERIES at it's position before the last item"
	series [series!]
][
	back tail series
]

rechange: function [
	"Sequence multiple changes into SERIES"
	series [series!]
	values [block!] "Reduced"
][
	change series reduce values
]

#hide [#assert [
	s: [a b c]
	e: rechange next s [1 + 1 2 * 3 3 + 4]
	s == [a 2 6 7]
	e =? tail s
]]

compose-after: function [target [any-list!] template [block!]] [
	compose/only/deep/into template tail target
]

;; main problem with these is they can't be used in performance critical areas, which is quite often the case
>>: make op! function [
    "Return series at an offset from head or shift bits to the right"
    data   [series! integer!]
    offset [integer!]
][
    if integer? data [return shift-right data offset]
    skip head data offset
]

<<: make op! function [
    "Return series at an offset from tail or shift bits to the left"
    data   [series! integer!]
    offset [integer!]
][
    if integer? data [return shift-left data offset]
    skip tail data negate offset
]

; abs-pick: func [series [series!] index [integer!]] [	;@@ what's a better name?
	; pick either index < 0 [tail series] [series] index
; ]

filtered-event-func: function [
	"Make a filtered global View event function"
	spec [block!] "Function spec"
	body [block!] "Function body, should start with a list of supported event types" (block? :body/1)
	/local event-name
][
	parse spec [thru word! to word! set event-name skip]
	function spec compose/deep [
		switch (as path! reduce [event-name 'type]) [
			(body/1) [(next body)]
		]
	]
]
	
;-- faster than for-each/reverse, but only correct if series length is a multiple of skip
;@@ use for-each when becomes available
foreach-reverse: function [spec [word! block!] series [series!] code [block!]] [
	if empty? series [exit]
	step: 0 - length? spec: compose [(spec)]
	series: tail series
	until [										;-- clear the map of invisible spaces ;@@ should be for-each/reverse
		set spec series: skip series step
		do code
		head? series
	]
]

;; O(1) remove that doesn't preserve the order (useful for hashes)
fast-remove: function [block [any-block!] length [integer!]] [
	last-entry: skip tail block negate length
	unless block =? last-entry [change block last-entry]
	clear last-entry
]

;@@ extend & expand are taken already, maybe prolong?
;; it's similar to pad/with but supports blocks, returns insert position, and should be faster
enlarge: function [
	"Ensure certain SIZE of the BLOCK, fill empty space with VALUE"
	block [any-block! any-string!] size [integer!] value [any-type!]
][
	#assert [any [any-block? block  char? :value]]
	insert/only/dup skip block size :value size - length? block
	;; returns after size
]

;-- see REP #104, but this is still different: we don't care what context word belongs to, only it's spelling and value
same-paths?: function [p1 [block! path!] p2 [block! path!]] [
	to logic! all [
		find/match/same as [] p1 as [] p2
		(length? p1) = length? p2
	]
]

find-same-path: function [block [block!] path [path!]] [
	forall block [
		all [
			path? :block/1
			same-paths? block/1 path
			return block
		]
	]
	none
]

#hide [#assert [
	(a: object [] b: object [])
	same-paths? as path! reduce [a b] reduce [a b]
	2 = index? r: find-same-path reduce [
		as path! reduce [copy a b]
		as path! reduce [a b]
	] as path! reduce [a b]
]]


kit-catalog: make map! 40

;@@ add on-change to kit to lock it from modification
make-kit: function [name [path! (parse name [2 word!]) word!] spec [block!]] [
	unless word? name [
		base: kit-catalog/(name/2)
		spec: append copy/deep base spec
		name: name/1
	]
	kit-catalog/:name: copy/deep spec
	kit: object append keep-type spec set-word! [do-batch: none]	;-- must not be named 'batch' since global batch is used by kits
	kit/do-batch: function
		["(Generated) Evaluate plan for given space" space [object!] plan [block!]]
		with kit compose [do bind/copy plan self]				;-- must copy or may get context not available errors on repeated batch
	do with [:kit :kit/do-batch] spec
	kit
]

batch: function ["Evaluate plan within space's kit" space [object!] plan [block!]] [
	either kit: select space 'kit [kit/do-batch space plan][do plan]	;@@ or error if no kit?
]

;; this function assumes no scaling or anything fishy, plain map
;; uses geom/size/x, not space/size/x because parent's map may have been fetched from the cache,
;; while children sizes may not have been updated
;; it's not totally error-proof but I haven't come up with a better plan
generate-sections: function [
	"Generate sections block out of list of spaces; returns none if nothing to dissect"
	map     [block!]  "A list in map format: [space [size: ...] ...]" (parse map [end | object! block! to end])
	width   [linear!] "Total width (may be affected by limits/min)" (width >= 0)
	buffer  [block!]
][
	case [
		not tail? buffer [return buffer]				;-- already computed
		tail? map [										;-- optimization
			if width > 0.02 [append buffer width]		;-- treat margins as significant
			return buffer
		]
	]
	offset: 0
	frame: []											;-- when no sections in space, uses local value
	foreach [space geom] map [
		if (skipped: offset - geom/offset/x) < -0.02 [	;-- avoid adding too tiny (rounding error) values
			append buffer skipped
		]
		case [
			sec: batch space [
				sec: select frame 'sections
				sec										;-- calls if a function, may return none
			][
				append buffer sec
			]
			geom/size/x > 0 [append buffer geom/size/x]			;-- don't add empty (0) spaces
		]
		offset: offset - skipped + geom/size/x
	]
	if all [buffer/1 buffer/1 < 0] [buffer/1: abs buffer/1]		;-- treat margins as significant
	if width - offset > 0.02 [append buffer width - offset]
	#assert [not find/same buffer 0]
	buffer
]
#assert [[10] = generate-sections [] 10 copy []]
	
	
;; this function is used by tube layout to expand items in a row (which should be blazingly fast)
;; it is quite tricky, because limits (constraints) of each item affect all others in a row
;; goal here is to make Red level code linear of complexity, while R/S part can be quadratic or nlogn
;; implementation sorts items by the available extension size normalized to weight
;; then it eliminates slices from the shortest to the longest,
;; subtracting each item's extension size multiplied by number of items left
;@@ maybe extract this into /common? maybe with /limits being an optional refinement?
distribute: function [
	"Distribute a numeric AMOUNT across items with given WEIGHTS"
	amount  [number!] "Any nonnegative number" (amount >= 0)
	weights [block!] "Zero for items that do not receive any part of AMOUNT" ((length? limits) = length? weights)
	limits  [block!] "Maximum part of AMOUNT each item is able to receive; NONE if unlimited" (0 < length? limits)
][
	data: clear []
	sum-weights: 0.0
	repeat i count: length? weights [
		weight: 1.0 * any [weights/:i 0]
		either weight <= 0 [
			repend data [i 0.0 0.0]
		][
			limit: 1.0 * max 0 any [limits/:i 1.#inf]
			sum-weights: sum-weights + weight
			repend data [i weight limit / weight]
		]
	]
	
	result: append/dup make block! count amount * 0 count
	if sum-weights <= 0 [return result]
	sort/skip/compare data 3 3
	
	left: 1.0 * amount
	foreach [i weight slice] data [
		if left <= 0 [break]
		part: min slice left / sum-weights
		left: left - used: to amount part * weight
		sum-weights: sum-weights - weight
		result/:i: used
	]
	result
]


#assert [
	[100]         == distribute 100 [1]        [2e9]
	[ 99]         == distribute 100 [1]        [ 99]
	[ 99]         == distribute 100 [2]        [ 99]
	[  0]         == distribute 100 [1]        [  0]
	[  0]         == distribute 100 [0]        [2e9]
	[ 50  50]     == distribute 100 [1  1]     [2e9 2e9]
	[ 25  50  25] == distribute 100 [1  2   1] [2e9 2e9 2e9]
	[ 33  33  34] == distribute 100 [1  1   1] [2e9 2e9 2e9]
	[ 33  33  34] == distribute 100 [1  1   1] [#(none) #(none) #(none)]
	[  0 100   0] == distribute 100 [0  1   0] [2e9 2e9 2e9]
	[ 33  34  33] == distribute 100 [1  1   1] [2e9 2e9  33]
	[  1   2   3] == distribute 100 [1  1   1] [  1   2   3]
	[ 33  33  33] == distribute 100 [1 10 100] [ 33  33  33]
	[  0   0   0] == distribute 100 [1 10 100] [  0   0   0]
	[  0   0   0] == distribute 100 [0  0   0] [  0   0   0]
	[  0   0   0] == distribute 100 [0  0   0] [  3   2   1]
	[  0   0   0] == distribute 100 [1  2   3] [ -1  -1  -1]
	[  0   0   0] == distribute 100 [0 -1  -1] [  3   2   1]
	[14 29 42 15] == distribute 100 [1 2 3 1] [2e9 2e9 2e9 2e9]
	[25 50  0 25] == distribute 100 [1 2 0 1] [2e9 2e9 2e9 2e9]
	[27 53  0 20] == distribute 100 [1 2 0 1] [2e9 2e9 2e9  20]
	[28 52  0 20] == distribute 100 [1 2 0 1] [2e9  52 2e9  20]
	[28 52  0 20] == distribute 100 [1 2 1 1] [2e9  52   0  20]
	[34 66  0  0] == distribute 100 [1 2 0 0] [2e9 2e9 2e9 2e9]
	[66  0  0 34] == distribute 100 [2 0 0 1] [2e9 2e9 2e9 2e9]
	[50.0 25.0 0.0 25.0] == distribute 100.0 [2 1 0 1] [2e9 2e9 2e9 2e9]
	[50%  25%  0%  25% ] == distribute 100%  [2 1 0 1] [2e9 2e9 2e9 2e9]
]

new-rich-text: none
context [
	;; rtd-layout is slow! about 200 times slower than object creation (it also invokes VID omg)
	;; just make face! is 120 times slower too, because of on-change handlers
	;; rich text does not require any of that however, so I mimick it using a non-reactive object
	;; achieved construction time is 16us vs 200us
	light-face!: construct map-each w exclude words-of :face! [on-change* on-deep-change*] [to set-word! w]
	light-face!/para: make para! [wrap?: on]
	; rtd-template: make face! compose [
	rtd-template: compose [
		on-change*: does []								;-- for whatever reason, crashes without this
		on-deep-change*: does []
		(system/view/VID/styles/rich-text/template)
	]
	set 'new-rich-text does [make light-face! rtd-template]
]


export exports
