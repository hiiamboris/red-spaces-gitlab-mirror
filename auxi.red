Red [
	title:   "Auxiliary helper funcs for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

; #include %../common/assert.red
;@@ not sure if infxinf should be exported, but it's used by custom styles, e.g. spiral
exports: [by abs range! range? .. using when only mix clip ortho dump-event boxes-overlap? infxinf opaque]

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

by:   make op! :as-pair
abs: :absolute
svf:  system/view/fonts
svm:  system/view/metrics
svmc: system/view/metrics/colors

along: make op! function [
	"Pick PAIR's dimension along AXIS (integer is treated as a square)"
	pair [pair! (0x0 +<= pair) integer! (0 <= pair)]
	axis [word!] (find [x y] axis)
][
	pick 1x1 * pair axis
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

without-GC: func [
	"Evaluate CODE with GC temporarily turned off"
	code [block!]
][
	sort/compare [1 1] func [a b] code
]

;; ranges support needed by layout, until such datatype is introduced, have to do with this
;; since it's for layout usage only, I don't care about a few allocated objects, no need to optimize it
;; ranges are used by spaces to constrain their size, but those are read-only
;; object = 468 B, block = 92 B, map = 272 B (cannot be reacted to)
;; space with draw=[] = 512 B, rectangle = 1196 B, timer does not need this at all
range!: object [min: max: none]
range?: func [x [any-type!]] [all [object? :x (class-of x) = class-of range!]]
..: make op! function [									;-- name `to` cannot be used as it's a native
	"Make a range from A to B"
	a [scalar! none!]
	b [scalar! none!]
][
	make range! [min: a max: b]
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
	0x0 +< ((min A2 B2) - max A1 B1)					;-- 0x0 +< intersection size
]

vec-length?: function [v [pair!]] [						;-- this is still 2x faster than compiled `distance? 0x0 v`
	v/x ** 2 + (v/y ** 2) ** 0.5
]

closest-box-point?: function [
	"Get coordinates of the point on box B1-B2 closest to ORIGIN"
	B1 [pair!] "inclusive" B2 [pair!] "inclusive"
	/to origin: 0x0 [pair!] "defaults to 0x0"
][
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

; zip: function [
	; "Interleave a list of series of equal length"
	; list [block!]
; ][
	; case [
		; tail?   list [copy []]
		; single? list [copy :list/1]
		; 'else [
			; r: make :list/1 (w: length? list) * h: length? :list/1
			; repeat y h [repeat x w [append/only r :list/:y/:x]]
		; ]
	; ]
; ]


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
		type [datatype!] "Any series type" (any [map! = type find series! type])
		size [integer!]  "Minimal length before reallocation, >= 1"
	][
		size:   max 1 size								;-- else log will be infinite
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
		series [series! map!]
	][
		type:   type?/word series
		ladder: any [free-list/:type  free-list/:type: make hash! 256]
		step:   round/floor/to (log-e length? series) / log-factor 1
		repend ladder [step clear series]
	]
]

;; main problem of this faster design: doesn't care about length, may result in lots of reallocations
make-free-list: function [
	"Create a free list of things with GET and PUT methods defined"
	type [datatype!] "Type of thing"
	init [block!]    "Code to create a new thing"
][
	object compose/deep [
		stack: []
		get: function [] [
			either tail? stack [(init)][p: tail stack also :p/-1 clear back p]	;@@ workaround for #5066
		]
		put: func [x [(type)]] [
			append/only stack (either find series! type [ [clear head x] ][ [:x] ])
		]
	]
]

clone: function [
	"Make TARGET series a (shallow) clone of SOURCE series"
	source [series!] target [series!]
][
	at append clear head target head source index? source
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
	unless find series :flag [append series :flag]
	series
]

exclude-from: function [
	"Exclude flag into series if it's there"
	series [series!] flag [any-type!]
][
	remove find series :flag
	series
]

set-flag: function [
	"Include or exclude flag from series depending on present? value"
	series [series!] flag [any-type!] present? [logic!]
][
	either present? [include-into series :flag][exclude-from series :flag]
]


flush: function [
	"Grab a copy of SERIES, clearing the original"
	series [series!]
][
	also copy series clear series
]

set-after: function [
	"Set PATH to VALUE and return the previous value of PATH"
	path [path! word!]
	value [any-type!]
][
	also get/any path set/any path :value 
]

;@@ make a REP with this? (need use cases)
;@@ this is no good, because it treats paths as series
native-swap: :system/words/swap
swap: func [a [word! series!] b [word! series!]] [
	either series? a [
		native-swap a b
	][
		set a set-after b get a
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

area?: func [xy [pair!]] [xy/x * xy/y]					;-- maybe support infxinf? or partialy infinity?

skip?: func [series [series!]] [-1 + index? series]

;-- `clip [a b] v` is far easier to understand than `max a min b v`
;@@ although block-form [a b] requires extra reduction; maybe use just `clip a b v`?
;@@ v is at the end because it's usually a big expression, OTOH order is not so relevant here:
;@@ (clip [1 2] 3) = (clip [1 3] 2) = (clip [2 3] 1) - segment bounds just have to be sorted (not clip [3 1] 2)
;@@ this means there really is no need to remember the argument order!
clip: func [
	"Get VALUE or margin closest to it if it's outside of [range/1 range/2] segment"
	range [block!]  "Reduced"
	value [scalar!]
][
	range: reduce/into range clear []
	#assert [any [not number? range/1  range/1 <= range/2]]
	min range/2 max range/1 value
]

;@@ this should be just `clip` but min/max have no vector support
clip-vector: function [v1 [vector!] v2 [vector!] v3 [vector!]] [
	repeat i length? r: copy v1 [r/:i: clip [v2/:i v3/:i] v1/:i]
	r
]

resolve-color: function [color [tuple! word! issue!]] [
	case [
		word?  color [svmc/:color]
		issue? color [hex-to-rgb color]
		'else [color]
	]
]

mix: function [
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
	bgnd  [tuple! word!]
	color [tuple! word!]
	amnt  [number!] "Should be over 100%" (amnt >= 100%)
][
	bg-hsl: RGB2HSL resolve-color bgnd
	fg-hsl: RGB2HSL resolve-color color
	sign: pick [1 -1] fg-hsl/3 >= bg-hsl/3
	fg-hsl/3: clip [0% 100%] fg-hsl/3 + (amnt - 1 / 2 * sign)
	HSL2RGB fg-hsl
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


range: func [a [integer!] b [integer!]] [
	collect [while [a <= b] [keep a  a: a + 1]]
]

min-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b min a b] a b]
]

max-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b max a b] a b]
]

half: func [x] [x / 2]

quantize: function [
	"Quantize a float sequence into integers, minimizing the overall bias"
	vector [vector! block!]
][
	r: make vector! n: length? vector
	error: 0											;-- accumulated rounding error is added to next value
	repeat i n [
		r/:i: hit: round/to aim: vector/:i + error 1
		error: aim - hit
	]
	r
]

context [
	set 'binary-search function [
		"Look for optimum F(x)=Fopt on a segment [X1..X2] using binary search, return [X1 F1 X2 F2]"
		'word [word! set-word!] "Argument name for the loop"
		X1    [number!]
		X2    [number!]
		Fopt  [number!] "Optimum to find"
		error [number!] "Minimum acceptable error to stop search (along X or F)"
		F     [block!]  "Function F(x)"
		/with "Provide F(X1) and F(X2) if they are known"
			F1: (call-f X1) [number!] 
			F2: (call-f X2) [number!] 
	][
		#assert [fopt = clip [min f1 f2 max f1 f2] fopt  "Optimum value should be within [F1,F2]"]	;@@ rephrase when clip updates
		sign: sign? (f2 - f1) * (x2 - x1)				;-- + if ascending
		repeat n 1e3 [
			df: abs f2 - f1
			dx: abs x2 - x1
			if error >= max abs f2 - f1 abs x2 - x1 [break]		;-- found it already; segment is too narrow
			y: call-f x: x1 + x2 / 2
			;; in / case: y < fopt < y2 means x is new x1; in \ case: x is new x2
			either positive? fopt - y * sign [x1: x f1: y][x2: x f2: y]		;-- use new low or high boundary
		]
		; print `"Spent (n - 1) iterations in search"`
		if n = 1e3 [ERROR "Binary search deadlocked"]	;-- too much precision will slow it down, better to error out
		reduce [x1 f1 x2 f2]
	]
	
	call-f: func [x] with :binary-search [set word x do f]
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
	size    [none! pair!]   "none if unlimited (same as infxinf)"
	limits  [object! (range? limits) none!] "none if no limits"
][
	unless limits [return size]							;-- most common case optimization
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
	size
]

#assert [infxinf = constrain infxinf none]

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

set-pair: function [
	"Set words to components of a pair value"
	words [block!]
	pair  [pair!]
][
	set words/1 pair/x
	set words/2 pair/y
]

make-pair: function [
	"Construct a pair out of default value and possible axis replacements"
	spec [block!] "Reduced, /x /y and /1 are used"
][
	reduce/into spec spec: clear []
	as-pair any [spec/x spec/1/1] any [spec/y spec/1/2]
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


decode-canvas: function [
	"Turn pair canvas into positive value and fill flags"
	canvas [none! pair!] "can be none, negative or infinite (no fill), positive (fill)"
][
	reduce/into [
		|canvas|: either canvas [abs canvas][canvas: infxinf]
		fill: negate canvas / max 1x1 |canvas|			;-- 1 if fill=true, -1 if false, can be 0 (also false, but doesn't matter)
	] clear []
]

#assert [
	(reduce [infxinf -1x-1]) = decode-canvas none
	[10x20 -1x-1] = decode-canvas  10x20
	[10x20  1x1]  = decode-canvas -10x-20
	[10x0  -1x0]  = decode-canvas  10x0
]

encode-canvas: function [
	|canvas| [pair!] "Absolute canvas size"
	fill     [pair!] "Fill mask (1 = true, 0 and -1 = false)"
][
	;; must ensure infinity always stays +infinity:
	add |canvas| / infxinf * infxinf					;-- part for infinite coordinates
		|canvas| % infxinf * negate fill				;-- part for finite coordinates
]

#localize [#assert [
	reencode: func [b] [encode-canvas b/1 b/2]
	infxinf = reencode decode-canvas  none
	 10x20  = reencode decode-canvas  10x20
	-10x-20 = reencode decode-canvas -10x-20
	 10x0   = reencode decode-canvas  10x0
	infxinf = encode-canvas infxinf 1x1					;-- must not become negative infinity
	infxinf = encode-canvas infxinf 1x0					;-- must not become zero
]]


finite-canvas: function [
	"Turn infinite dimensions of CANVAS into zero"
	canvas [pair! none!]
][
	remainder any [canvas 0x0] infxinf
]

#assert [0x20 = finite-canvas infxinf/x by 20]

extend-canvas: function [
	"Make one of CANVAS dimensions infinite"
	canvas [pair!]
	axis   [word!] "X or Y" (find [x y] axis)
][
	canvas/:axis: infxinf/x
	canvas
]

;; useful to subtract margins, but only from finite dimensions
subtract-canvas: function [
	"Subtract PAIR from CANVAS if it's finite, rounding negative results to 0x0"
	canvas [pair!] (0x0 +<= canvas)
	pair   [pair!]
][
	mask: 1x1 - (canvas / infxinf)						;-- 0x0 (infinite) to 1x1 (finite)
	max 0x0 canvas - (pair * mask)
]

#assert [( 60 by infxinf/y) = subtract-canvas  100 by infxinf/y 40x30]
#assert [( 0  by infxinf/y) = subtract-canvas   20 by infxinf/y 40x30]


top: func [
	"Return SERIES at it's position before the last item"
	series [series!]
][
	back tail series
]

;; good addition to do-atomic which holds reactivity
do-async: function [									;@@ used solely to work around #5132
	"Evaluate CODE with view/auto-sync off"
	code [block!]
][
	sync: 'system/view/auto-sync?
	old: get sync
	set sync off
	do code
	set sync old
]

rechange: function [
	"Sequence multiple changes into SERIES"
	series [series!]
	values [block!] "Reduced"
][
	change series reduce values
]

#localize [#assert [
	s: [a b c]
	e: rechange next s [1 + 1 2 * 3 3 + 4]
	s == [a 2 6 7]
	e =? tail s
]]

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

#assert [
	(a: object [] b: object [])
	same-paths? as path! reduce [a b] reduce [a b]
	2 = index? r: find-same-path reduce [
		as path! reduce [copy a b]
		as path! reduce [a b]
	] as path! reduce [a b]
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
	
;@@ workaround for #5165! - remove me once it's fixed
#if linux? [
	native-caret-to-offset: :caret-to-offset
	set 'caret-to-offset function [
	    {Given a text position, returns the corresponding coordinate relative to the top-left of the layout box} 
	    face [object!] 
	    pos [integer!] 
	    /lower "lower end offset of the caret" 
	][
		either lower [
			;@@ this also suffers from #3812: /with is ignored by size-text, have to work around!
			rt: new-rich-text
			quietly rt/text: copy/part face/text 0x1 + pos
			add native-caret-to-offset face pos
				size-text rt
		][
			native-caret-to-offset face pos
		]
	]
]


export exports
