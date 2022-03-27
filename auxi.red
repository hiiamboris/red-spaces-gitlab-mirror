Red [
	title:   "Auxiliary helper funcs for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

; #include %../common/assert.red

exports: [by abs range! range? .. when clip ortho dump-event boxes-overlap?]

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


;-- we need this to be able to call event functions recursively with minimum allocations
;-- we can't use a static block but we can use one block per recursion level
block-stack: object [
	stack: []
	get: does [any [take/last stack  make [] 100]]
	put: func [b [block!]] [append/only stack clear head b]
	hold: func [b [block!]] [at  append get head b  index? b]
]


;-- `compose` readability helper variant 2
when: func [test value] [either :test [do :value][[]]]


range: func [a [integer!] b [integer!]] [
	collect [while [a <= b] [keep a  a: a + 1]]
]

;-- `clip [a b] v` is far easier to understand than `max a min b v`
clip: func [range [block!] value [scalar!]] [
	range: reduce/into range clear []
	#assert [any [not number? range/1  range/1 <= range/2]]
	min range/2 max range/1 value
]

constrain: function [
	"Sets TARGET to SIZE clipped within LIMITS"
	'target [set-word! set-path!]
	size    [pair!]
	limits  [none! word! object!]
	; /force "Set it even if it's equal, to trigger reactions"
][
	case [
		limits = 'fixed [size: get target]				;-- cannot be changed ;@@ need to think more about this
		range? limits  [
			case [
				none = min: limits/min [min: 0x0]
				number? min [min: min by 0]				;@@ should numbers only apply to X, or to main axis (harder)? 
			]
			case [
				none = max: limits/max [max: max by 2e9]
				number? max [max: max by 2e9]
			]
			size: clip [min max] size
		]
		;-- rest is treated as `none`
	]
	set target size
	; if any [force  not size == get target] [set target size]
	; size
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
; native-swap: :swap
; swap: func [a [word! series!] b [word! series!]] [
	; either series? a [
		; native-swap a b
	; ][
		; set a also get b set b get a
	; ]
; ]


ortho: func [
	"Get axis orthogonal to a given one"
	xy [word! pair!] "One of [x y 0x1 1x0]"
][
	select/skip [x y y x 0x1 1x0 1x0 0x1] xy 2
]

axis2pair: func [xy [word!]] [
	switch xy [x [1x0] y [0x1]]
]

anchor2axis: func [nesw [word!]] [
	switch nesw [n s ['y] w e ['x]]
]

anchor2pair: func [nesw [word!]] [
	switch nesw [n [0x-1] s [0x1] w [-1x0] e [1x0]]
]


;-- debug func
dump-event: function [event] [
	event: object map-each/eval w system/catalog/accessors/event! [
		[to set-word! w 'quote event/:w]
	]
	help event
]


top: func [series [series!]] [back tail series]

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

;-- faster than for-each/reverse, but only correct if series length is a multiple of skip
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
