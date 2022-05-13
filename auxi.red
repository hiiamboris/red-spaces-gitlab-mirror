Red [
	title:   "Auxiliary helper funcs for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

; #include %../common/assert.red
;@@ not sure if infxinf should be exported, but it's used by custom styles, e.g. spiral
exports: [by abs range! range? .. when only mix clip ortho dump-event boxes-overlap? infxinf]

;@@ unfortunately macros are not imported yet due to custom `include` :(
;@@ need a special macros file
; ;; readability helper instead of reduce/into [] clear [] ugliness
; #macro [#static-reduce block!] func [[manual] s e] [
	; change/only s 'reduce/into
	; insert/only insert e 'clear copy []
	; s
; ]

; ;@@ watch out for #5009 for a better way to specify refinements
; #macro [#static-compose any refinement! block!] func [[manual] s e /local path] [
	; path: copy 'compose/into
	; e: next s
	; while [refinement? :e/1] [append path to word! take e]
	; change/only s path
	; insert/only insert e 'clear copy []
	; s
; ]

by: make op! :as-pair
abs: :absolute

;; ranges support needed by layout, until such datatype is introduced, have to do with this
;; since it's for layout usage only, I don't care about a few allocated objects, no need to optimize it
;; ranges are used by spaces to constrain their size, but those are read-only
;; object = 468 B, block = 92 B, map = 272 B (cannot be reacted to)
;; space with draw=[] = 512 B, rectangle = 1196 B, timer does not need this at all
range!: object [min: max: none]
range?: func [x [any-type!]] [all [object? :x (class-of x) = class-of range!]]
..: make op! function [a [scalar! none!] b [scalar! none!]] [	;-- name `to` cannot be used as it's a native
	make range! [min: a max: b]
]


;; need this to be able to call event functions recursively with minimum allocations
;; can't use a static block but can use one block per recursion level
;; also used in the layout functions (which can be recursive easily)
obtain: stash: none
context [
	;; for faster lookup of specific sizes, a ladder of discrete sizes (factor^n) is used
	factor: 1.4											;-- https://stackoverflow.com/q/1100311
	log-factor: log-e factor
	free-list: #()
	
	;; `make` alternative that uses a free list of series when possible - to reduce GC load
	set 'obtain function [
		"Get a series of type TYPE with a buffer of at least SIZE length"
		type [datatype!] "Any series type"
		size [integer!]  "Minimal length before reallocation, >= 1"
	][
		#assert [
			find series! type
			size >= 1
		]
		name:   to word! type							;-- datatype is not supported by maps
		ladder: any [free-list/:name  free-list/:name: make hash! 256]
		step:   round/ceiling/to (log-e size) / log-factor 1
		either pos: any [
			find ladder step
			find ladder step + 1						;-- try little bigger sizes as well
			find ladder step + 2						;@@ how many to try optimally?
		][
			also pos/2  fast-remove pos 2
		][
			make type round/ceiling/to factor ** step 1
		]
	]
	
	set 'stash function [
		"Put SERIES back into the free list for futher OBTAIN calls"
		series [series!]
	][
		type:   type?/word series
		ladder: any [free-list/:type  free-list/:type: make hash! 256]
		step:   round/floor/to (log-e length? series) / log-factor 1
		repend ladder [step clear series]
	]
]

;; older (but faster) design - for blocks only - not sure if worth keeping
;; main problem of it: doesn't care about length, may result in lots of reallocations
block-stack: object [
	stack: []
	get:  does [any [take/last stack  make [] 100]]
	put:  func [b [block!]] [append/only stack clear head b]
	hold: func [b [block!]] [at  append get head b  index? b]
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


flush: function [
	"Grab a copy of SERIES, clearing the original"
	series [series!]
][
	also copy series clear series
]

only: function [
	"Turn falsy values into unset, eliminating from compose expressions"
	value [any-type!] "Any truthy value is passed through"
][
	any [:value ()]
]

;-- `clip [a b] v` is far easier to understand than `max a min b v`
clip: func [range [block!] value [scalar!]] [
	range: reduce/into range clear []
	#assert [any [not number? range/1  range/1 <= range/2]]
	min range/2 max range/1 value
]

mix: function [
	"Impose COLOR onto BGND and return the resulting color"
	bgnd  [tuple!] "Alpha channel ignored"
	color [tuple!] "Alpha channel determines blending amount"
][
	c3: c4: color + 0.0.0.0
	c3/4: none
	bg-amnt: c4/4 / 255
	bgnd * bg-amnt + (1 - bg-amnt * c3)
]

#assert [
	0.0.0   = mix 0.0.0     0.0.0
	0.0.0   = mix 100.50.10 0.0.0
	50.25.5 = mix 100.50.10 0.0.0.128
]

;; https://www.rapidtables.com/convert/color/rgb-to-hsl.html
;@@ actually these formulas are simplistic and not statisticaly neutral, need improvement
;@@ when improved, consider inclusion into /common
RGB2HSL: function [rgb [tuple!]] [
	R: rgb/1  G: rgb/2  B: rgb/3
	C+: max max R G B
	C-: min min R G B
	D: C+ - C-
	L: C+ + C- / 510
	S: either D = 0 [0][D / 255 / (1 - abs L * 2 - 1)]
	H: 60 * case [
		D  = 0 [0]
		C+ = R [G - B / D // 6]
		C+ = G [B - R / D + 2]
		"C+=B" [R - G / D + 4]
	]
	reduce [H 100% * S 100% * L]
]

;; https://www.rapidtables.com/convert/color/hsl-to-rgb.html
HSL2RGB: function [hsl [block!]] [
	set [H: S: L:] hsl
	C: (1 - abs L * 2 - 1) * S * 255
	X: (1 - abs H / 60 // 2 - 1) * C
	m: 255 * L - (C / 2)
	n: to integer! H / 60
	triple: pick [[C X 0] [X C 0] [0 C X] [0 X C] [X 0 C] [C 0 X] [C X 0]] n + 1
	rgb: 0.0.0
	repeat i 3 [rgb/:i: clip [0 255] to integer! m + do triple/:i]
	rgb
]

;; these mostly fail due to rounding
; #assert [
  	; [  0   0%   0%] = RGB2HSL 0.0.0
  	; [  0   0% 100%] = RGB2HSL 255.255.255
  	; [  0 100%  50%] = RGB2HSL 255.0.0
  	; [120 100%  50%] = RGB2HSL 0.255.0
  	; [240 100%  50%] = RGB2HSL 0.0.255
  	; [ 60 100%  50%] = RGB2HSL 255.255.0
  	; [180 100%  50%] = RGB2HSL 0.255.255
  	; [300 100%  50%] = RGB2HSL 255.0.255
  	; [  0   0%  75%] = RGB2HSL 191.191.191
  	; [  0   0%  50%] = RGB2HSL 128.128.128
  	; [  0 100%  25%] = RGB2HSL 128.0.0
  	; [ 60 100%  25%] = RGB2HSL 128.128.0
  	; [120 100%  25%] = RGB2HSL 0.128.0
  	; [300 100%  25%] = RGB2HSL 128.0.128
  	; [180 100%  25%] = RGB2HSL 0.128.128
  	; [240 100%  25%] = RGB2HSL 0.0.128
; ]
; #assert [
  	; (HSL2RGB [  0   0%   0%]) = 0.0.0
  	; (HSL2RGB [  0   0% 100%]) = 255.255.255
  	; (HSL2RGB [  0 100%  50%]) = 255.0.0
  	; (HSL2RGB [120 100%  50%]) = 0.255.0
  	; (HSL2RGB [240 100%  50%]) = 0.0.255
  	; (HSL2RGB [ 60 100%  50%]) = 255.255.0
  	; (HSL2RGB [180 100%  50%]) = 0.255.255
  	; (HSL2RGB [300 100%  50%]) = 255.0.255
  	; (HSL2RGB [  0   0%  75%]) = 191.191.191
  	; (HSL2RGB [  0   0%  50%]) = 128.128.128
  	; (HSL2RGB [  0 100%  25%]) = 128.0.0
  	; (HSL2RGB [ 60 100%  25%]) = 128.128.0
  	; (HSL2RGB [120 100%  25%]) = 0.128.0
  	; (HSL2RGB [300 100%  25%]) = 128.0.128
  	; (HSL2RGB [180 100%  25%]) = 0.128.128
  	; (HSL2RGB [240 100%  25%]) = 0.0.128
; ]
#assert [
  	(HSL2RGB RGB2HSL 0.0.0      ) = 0.0.0      
  	(HSL2RGB RGB2HSL 255.255.255) = 255.255.255
  	(HSL2RGB RGB2HSL 255.0.0    ) = 255.0.0    
  	(HSL2RGB RGB2HSL 0.255.0    ) = 0.255.0    
  	(HSL2RGB RGB2HSL 0.0.255    ) = 0.0.255    
  	(HSL2RGB RGB2HSL 255.255.0  ) = 255.255.0  
  	(HSL2RGB RGB2HSL 0.255.255  ) = 0.255.255  
  	(HSL2RGB RGB2HSL 255.0.255  ) = 255.0.255  
  	(HSL2RGB RGB2HSL 191.191.191) = 191.191.191
  	(HSL2RGB RGB2HSL 128.128.128) = 128.128.128
  	(HSL2RGB RGB2HSL 128.0.0    ) = 128.0.0    
  	(HSL2RGB RGB2HSL 128.128.0  ) = 128.128.0  
  	(HSL2RGB RGB2HSL 0.128.0    ) = 0.128.0    
  	(HSL2RGB RGB2HSL 128.0.128  ) = 128.0.128  
  	(HSL2RGB RGB2HSL 0.128.128  ) = 0.128.128  
  	(HSL2RGB RGB2HSL 0.0.128    ) = 0.0.128    
]

enhance: function [
	"Push COLOR further from BGND (alpha channels ignored)"
	bgnd  [tuple!]
	color [tuple!]
	amnt  [number!] "Should be over 100%"
][
	bg-hsl: RGB2HSL bgnd
	fg-hsl: RGB2HSL color
	sign: pick [1 -1] fg-hsl/3 >= bg-hsl/3
	fg-hsl/3: clip [0% 100%] fg-hsl/3 + (amnt - 1 / 2 * sign)
	HSL2RGB fg-hsl
]



;-- `compose` readability helper variant 2
when: func [test value] [only if :test [do :value]]

range: func [a [integer!] b [integer!]] [
	collect [while [a <= b] [keep a  a: a + 1]]
]

;; constraining is used by `render` to impose soft limits on space sizes
;; constraining logic:
;; no canvas (unlimited) and no limits (unlimited) => return `none` (also unlimited)
;; no canvas (unlimited) and has upper limit => return upper limit
;; pair canvas and no limits => pass canvas thru
;; pair canvas and any of limits defined => clip canvas by limits
;; this includes 0x0 and 0x2e9 canvases which aim for min (0) on one axis and max (2e9) on another
;; numeric canvas defines only X coordinate, while Y remains unconstrained (min=0, max=2e9)
;; 2e9 pair coordinate is treated exactly as `none` (unlimited)
;; 2e9x2e9 result is normalized to `none`
infxinf: 2000000000x2000000000							;-- used too often to always type it numerically
constrain: function [
	"Clip SIZE within LIMITS (allows none for both)"
	size    [none! pair!]   "none if unlimited"
	limits  [none! object!] "none if no limits"
][
	unless limits [return size]							;-- most common case optimization
	#assert [range? limits]
	either size [										;-- pair size
		case [
			none =? min: limits/min [min: 0x0]
			number? min [min: min by 0]					;-- numeric limits only affect X
		]
		case [
			none =? max: limits/max [max: infxinf]
			number? max [max: max by infxinf/y]
		]
		size: clip [min max] size
		;; rest is treated as `none`, not affecting size
	][													;-- `none` size
		case [
			pair? max: limits/max [size: max]
			number? max [size: max by infxinf/y]
			;; no /max leaves unlimited size as `none`
		]
	]
	unless size =? infxinf [size]						;-- normalization
]

for: func ['word [word! set-word!] i1 [integer! pair!] i2 [integer! pair!] code [block!]] [
	either all [integer? i1 integer? i2] [
		if i2 < i1 [exit]			;@@ return none or unset? `while` return value is buggy anyway
		set word i1 - 1
		while [i2 >= set word 1 + get word] code
	][
		#assert [all [pair? i1 pair? i2]]
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

;@@ make a REP with this? (need use cases)
native-swap: :system/words/swap
swap: func [a [word! series!] b [word! series!]] [
	either series? a [
		native-swap a b
	][
		set a also get b set b get a
	]
]


polar2cartesian: func [radius [float! integer!] angle [float! integer!]] [
	(radius * cosine angle) by (radius * sine angle)
]

ortho: func [
	"Get axis orthogonal to a given one"
	xy [word! pair!] "One of [x y 0x1 1x0]"
][
	;; switch here is ~20% faster than select/skip
	; select/skip [x y y x 0x1 1x0 1x0 0x1] xy 2
	switch xy [x ['y] y ['x] 0x1 [1x0] 1x0 [0x1]]
]

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
		dict: [n ↑ [0x-1] s ↓ [0x1] e → [1x0] w ← [-1x0] #[none] ↔ ↕ [0x0]]
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


extend-canvas: function [canvas [pair! none!] axis [word!]] [
	if canvas [
		canvas/:axis: infxinf/x
		all [canvas <> infxinf canvas]					;-- normalize infxinf to `none`
	]
]

;; useful to subtract margins, but only from finite dimensions
subtract-canvas: function [canvas [pair! none!] pair [pair!]] [
	if canvas [
		mask: 1x1 - (canvas / infxinf)					;-- 0x0 (infinite) to 1x1 (finite)
		max 0x0 canvas - (pair * mask)
	]
]

#assert [(60 by infxinf/y) = subtract-canvas 100 by infxinf/y 40x30]


;-- debug func
dump-event: function [event] [
	event: object map-each/eval w system/catalog/accessors/event! [
		[to set-word! w 'quote event/:w]
	]
	help event
]


top: func [series [series!]] [back tail series]

quietly: function ['path [set-path!] value [any-type!]] [
	obj: get append/part as path! clear [] path top path
	set-quiet in obj last path :value
	:value
]

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

{
	useful pair invariants to test in which quadrant a point is located
	points: a, b
	a = min a b <=> 0x0 = min 0x0 b - a <=> B is in Q1 to A, axis-inclusive <=> A is in Q3 to B, axis-inclusive
	a = max a b <=> 0x0 = max 0x0 b - a <=> B is in Q3 to A, axis-inclusive <=> A is in Q1 to B, axis-inclusive
	                1x1 = min 1x1 b - a <=> B is in Q1 to A, axis-exclusive <=> A is in Q3 to B, axis-exclusive
	            -1x-1 = max -1x-1 b - a <=> B is in Q3 to A, axis-exclusive <=> A is in Q1 to B, axis-exclusive
	a = min a b <=> b = max a b   
}

;-- chainable pair comparison - instead of `within?` monstrosity
; >> 1x1 +< 2x2 +<= 3x3 +< 4x4
; == 4x4

;; very hard to find a sigil for these ops
;; + resembles intersecting coordinate axes, so can be read as "2D comparison"
+<=: make op! func [
	"Chainable pair comparison (non-strict)"
	a [pair! none!] b [pair! none!]
][
	all [a b a = min a b  b]
]
+<:  make op! func [
	"Chainable pair comparison (strict)"    
	a [pair! none!] b [pair! none!]
][
	all [a b a = min a b - 1  b]
]
;+>:  make op! func [a b] [a = max a b + 1]
;+>=: make op! func [a b] [a = max a b]

;-- if one of the boxes is 0x0 in size, result is false: 1x1 (one pixel) is considered minimum overlap
;@@ to be rewritten once we have floating point pairs
boxes-overlap?: function [
	"Get intersection size of boxes A1-A2 and B1-B2, or none if they do not intersect"
	A1 [pair!] "inclusive" A2 [pair!] "non-inclusive"
	B1 [pair!] "inclusive" B2 [pair!] "non-inclusive"
][
	0x0 +< ((min A2 B2) - max A1 B1)							;-- 0x0 +< intersection size
]

vec-length?: function [v [pair!]] [
	v/x ** 2 + (v/y ** 2) ** 0.5
]

closest-box-point?: function [
	"Get coordinates of the point on box B1-B2 closest to ORIGIN"
	B1 [pair!] "inclusive" B2 [pair!] "inclusive"
	/to origin [pair!] "defaults to 0x0"
][
	default origin: 0x0
	as-pair
		case [origin/x < B1/x [B1/x] B2/x < origin/x [B2/x] 'else [origin/x]]
		case [origin/y < B1/y [B1/y] B2/y < origin/y [B2/y] 'else [origin/y]]
]

box-distance?: function [
	"Get distance between closest points of box A1-A2 and box B1-B2 (negative if overlap)"
	A1 [pair!] "inclusive" A2 [pair!] "non-inclusive"
	B1 [pair!] "inclusive" B2 [pair!] "non-inclusive"
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

fast-remove: function [block [any-block!] length [integer!]] [
	any [
		block =? other: skip tail block negate length
		change block other
	]
	clear other
]

;; extend & expand are taken already
enlarge: function [
	"Ensure certain SIZE of the BLOCK, fill empty space with VALUE"
	block [any-block!] size [integer!] value [any-type!]
][
	insert/dup skip block size :value size - length? block
	;; returns after size
]

;-- see REP #104, but this is still different: we don't care what context word belongs to, only it's spelling and value
same-paths?: function [p1 [block! path!] p2 [block! path!]] [
	to logic! all [
		p1 == as p1 p2									;-- spelling & length match
		; (length? p1) = length? p2						;-- doesn't seem to be faster this way
		find/match/same									;-- values match
			reduce/into as [] p1 clear []
			reduce/into as [] p2 clear []
	]
]

find-same-path: function [b [block!] p [path!]] [
	forall b [
		all [
			path? :b/1
			same-paths? :b/1 p
			return b
		]
	]
	none
]

#assert [
	(a: object [] b: object [])
	same-paths? 'a/b [a b]
	2 = index? r: find-same-path [a/c a/b] 'a/b
	2 = index? r: find-same-path reduce [as path! bind [a b] construct [a: b:] 'a/b] 'a/b
]


;; this function is used by tube layout to expand items in a row (which should be blazingly fast)
;; it is quite tricky, because limits (constraints) of each item affect all others in a row
;; goal here is to make Red level code linear of complexity, while R/S part can be quadratic
;; implementation sorts items by the available extension size normalized to weight
;; then it eliminates slices from the shortest to the longest,
;; subtracting each item's extension size multiplied by number of items left
;@@ maybe extract this into /common? maybe with /limits being an optional refinement?
distribute: function [
	"Distribute a numeric AMOUNT across items with given WEIGHTS"
	amount  [number!] "Any nonnegative number"
	weights [block!] "Zero for items that do not receive any part of AMOUNT"
	limits  [block!] "Maximum part of AMOUNT each item is able to receive; NONE if unlimited"
][
	#assert [amount > 0]
	#assert [(length? limits) > 0]
	#assert [(length? limits) = length? weights]
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
	
	result: append/dup make block! count amount * 0 count	;@@ use obtain?
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
	[ 33  33  34] == distribute 100 [1  1   1] [#[none] #[none] #[none]]
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


export exports
