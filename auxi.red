Red [
	title:   "Auxiliary helper funcs for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

#include %../common/assert.red

by: make op! :as-pair

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
	range: reduce range
	#assert [any [not number? range/1  range/1 <= range/2]]
	min range/2 max range/1 value
]


for: func ['word [word! set-word!] i1 [integer! pair!] i2 [integer! pair!] code [block!]] [
	either all [integer? i1 integer? i2] [
		if i2 < i1 [exit]			;@@ return none or unset? `while` return value is buggy anyway
		set word i1 - 1
		while [i2 >= set word 1 + get word] code
	][
		#assert [all [pair? i1 pair? i2]]
		range: i2 - i1 + 1
		if 1x1 <> min 1x1 range [exit]
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

#assert [3 = closest-number 3 [1 2 3]]
#assert [3 = closest-number 3 [3 4 5]]
#assert [3 = closest-number 1 [3 4 5]]
#assert [3 = closest-number 3 [1 4 5 3 2]]
#assert [4 = closest-number 3 [1 4 5 0]]

;-- debug func
dump-event: function [event] [
	event: object map-each/eval w system/catalog/accessors/event! [
		[to set-word! w 'quote event/:w]
	]
	help event
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

;@@ need good names to use these 'shortcuts' :(
; down-right-from?: make op! func [b [pair!] a [pair!]] [1x1 = min 1x1 b - a]
; down-right-inclusive-from?: 

;-- if one of the boxes is 0x0 in size, result is false: 1x1 (one pixel) is considered minimum overlap
;@@ to be rewritten once we have floating point pairs
bbox-overlap?: function [
	"True if bounding boxes A1-A2 and B1-B2 intersect"
	A1 [pair!] A2 [pair!] B1 [pair!] B2 [pair!]
][
	i: (min A2 B2) - max A1 B1							;-- intersection size
	1x1 == min 1x1 i									;-- optimized `all [i/x > 0 i/y > 0]`
]

vec-length?: function [v [pair!]] [
	v/x ** 2 + (v/y ** 2) ** 0.5
]

;-- faster than for-each/reverse, but only correct if series length is multiple of skip
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

#assert [a: object [] b: object [] same-paths? 'a/b [a b]]
#assert [2 = index? r: find-same-path [a/c a/b] 'a/b  'r]
#assert [2 = index? r: find-same-path reduce [as path! bind [a b] construct [a: b:] 'a/b] 'a/b  'r]

