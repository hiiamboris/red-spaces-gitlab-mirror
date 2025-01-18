Red [
	title:    "Auxiliary helper funcs for Draw-based widgets"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.auxi
	depends:  [with once global reshape advanced-function xyloop in-out-func]
]


global skip?: function [
	"Get current offset of SERIES from its head"
	series [series!]
][
	-1 + index? series
]

global top: function [
	"Return SERIES at it's position before the last item"
	series [series!]
][
	back tail series
]


;@@ copy/deep does not copy inner maps (#2167), clone tries to encode system/words, so this kludge is still a must have
copy-deep-map: function [m [map!]] [
	m: make map! copy/deep to [] m
	foreach [k v] m [if map? :v [m/:k: copy-deep-map v]]
	m
]

;@@ this has a drawback of being error-happy, when some system/words reference/binding crawls in - REP #155
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


;; kludges for very limited bitset functionality, used by grid
;@@ move it into grid, or there are other places that may benefit?
; bit-range: func [range [pair!]] [
	; range: ordered range
	; charset reduce [range/1 '- range/2]
; ]

; nonzero-byte: charset [1 - 255]
; lowest-bit: function [bs [bitset!]] [
	; if bs/0 [return 0]									;-- negated bitset?
	; bin: to #{} bs
	; unless p: find bin nonzero-byte [return none]
	; base: 8 * skip? p
	; repeat i 8 [if find bs bit: base + i - 1 [break]]
	; bit
; ]

; highest-bit: function [bs [bitset!]] [
	; if bs/2'147'483'647 [return none]					;-- negated bitset
	; bin: to #{} bs
	; unless p: find/last bin nonzero-byte [return none]
	; base: 8 * skip? p
	; repeat i 8 [if find bs bit: base + 8 - i [break]]
	; bit
; ]

; #assert [
	; none? lowest-bit  charset []
	; none? highest-bit charset []
	; none? highest-bit make bitset! 100
	; 0  = lowest-bit  charset [0  - 20]
	; 3  = lowest-bit  charset [3  - 20]
	; 18 = lowest-bit  charset [18 - 20]
	; 20 = highest-bit charset [0  - 20]
	; 17 = highest-bit charset [3  - 17]
	; 4  = highest-bit charset [3  - 4]
; ]

; unroll-bitset: function [bs [bitset!]] [
	; result: clear []
	; if lo: lowest-bit bs [
		; hi: highest-bit bs
		; for i: lo hi [if bs/:i [append result i]]		;@@ this is really dumb
	; ]
	; copy result
; ]


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

;@@ replace with kit/translate/from
; host-box-of: function [									;@@ temporary until REP #144
	; "Get host coordinates of a space (kludge! not scaling aware!)"
	; space [object!] (space? space)
; ][
	; box: reduce [(0,0) space/size]	
	; while [parent: space/parent] [
		; if host? parent [return box]
		; #assert [select parent 'map]
		; geom: select/same parent/map space
		; #assert [geom]
		; forall box [box/1: box/1 + geom/offset]
		; space: parent
	; ]
	; none
; ]


;@@ can't be named 'bubble' because it would clash with events/bubble
; bubble: function [
	; "Move a value to the end of the list (append if doesn't exist)"
	; list  [block! hash!]
	; value [default!]
; ][
	; remove find/only list :value
	; append/only list :value
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


for: in-out-func [										;@@ temporary kludge until REP #168
	'word [word! set-word!]
	i1    [integer! pair!]
	i2    [integer! pair!] (same? type? i1 type? i2)
	code  [block!]
][
	either integer? i1 [
		if i2 < i1 [exit]								;@@ return none or unset? `while` return value is buggy anyway
		word: i1 - 1
		while [i2 >= word: 1 + word] code
	][
		span: i2 - i1 + 1
		unless 1x1 +<= span [exit]						;-- empty range
		xyloop i: span [
			word: i - 1 + i1							;@@ does not allow index changes within the code, but allows in integer part above
			do code
		]
	]
]


as-object: function [
	"Create an object with given WORDS and assign values from these words"
	words [block!] (parse words [some set-word!])		;@@ I'd prefer words, but this is currently a performance matter
][
	also obj: construct words
	foreach w words [quietly obj/:w: get w]
]

as-map: function [
	"Create a map with given WORDS and assign values from these words"
	words [block!] (parse words [some [set-word! | word!]])
][
	also map: make map! length? words
	foreach w words [map/:w: get w]
]
	
trigger: function [
	"Trigger on-change reaction on the TARGET"
	target [word! path!]
][
	set/any target get/any target
]

copy&clear: function [
	"Grab a copy of SERIES, clearing the original"
	series [series! map! bitset!]
][
	also copy series clear series
]

explode: function [										;@@ use map-each when fast; split produces strings not chars :(
	"Split STRING into a block of characters"			;@@ name by @gltewalt :) but what name would be better?
	string [string!]
	/into buffer: (make [] length? string) [any-list!]
][
	parse string [collect after buffer keep pick to end]
	buffer
]


before: in-out-func [									;-- this seems only used in other helper funcs around here
	"Set PATH to VALUE, but return the previous value of PATH"
	'path [any-path! any-word!] value
][
	also path path: :value 
]


once native-swap: :system/words/swap
swap: function [										;-- replaces native 'swap', because it can't be harmlessly overloaded
	"Swap pointed-to scalar values"
	a [word! path!]
	b [word! path!]
][
	set a before (b) get a
]

#hide [#assert [
	xy: 2x3
	3x2 = (swap 'xy/1 'xy/2  xy)
]]

order: function [										;@@ should this receive a block of any number of paths?
	"Swap pointed-to scalar values if A > B"
	a [word! path!]
	b [word! path!]
][
	if greater? get a get b [swap a b]
]


;; MEMO: since it does not copy (for performance), only use it for temporary values, never for returns
only: function [
	"Turn falsy values into empty block (useful for composing Draw code)"
	value [any-type!] "Any truthy value is passed through"
][
	any [:value []]										;-- block is better than unset here because can be used in assignments
]

;; `compose` readability helper variant 4; simplified after all
;; to evaluate the result use `only if ... [expr]` instead
when: function [
	"If TEST is truthy, return VALUE, otherwise an empty block (static!)"
	test  [any-type!]
	value [any-type!]
][
	only if :test [:value]
]

;; simple shortcut for `compose` to produce blocks only where needed
;; as turns out only was used once in compose; and in other places reduce is not worse
; wrap: func [
	; "Put VALUE into a block"
	; value [any-type!]
; ][
	; reduce [:value]
; ]


;; the benefit of this over 'make' is that evaluated expressions are not bound to object's words
remake: function [
	"Construct an object from PROTOTYPE with composed SPEC"
	prototype [object!]
	spec      [block!] "Unlike `make`, isn't bound to the object"
][
	construct/only/with compose/only spec prototype
]


;@@ this should be just `clip` but min/max have no vector support
;@@ only used in grid/autofit - move there?
; clip-vector: function [v1 [vector!] v2 [vector!] v3 [vector!]] [
	; repeat i length? r: copy v1 [r/:i: clip v1/:i v2/:i v3/:i]
	; r
; ]

get-safe: function [path [path! word!]] [						;@@ REP 113; this in case of error is 10x slower than 'get'
	try [return x: get path] none								;@@ workaround for #5300 here
]

min-safe: function [a [scalar! none!] b [scalar! none!]] [		;@@ make a REP if it's proven useful
	any [all [a b min a b] a b]
]

max-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b max a b] a b]
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
;@@ remove number support? but this may break others' code that is bound to spaces/ctx
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
	mask    [block!]    "List of event types"
	handler [function!] "func [event [event!]]"
][
	function [face event] compose/deep [
		switch event/type [(mask) [(:handler) event]]
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

;@@ extend & expand are taken already, maybe prolong?
;; it's similar to pad/with but supports blocks, returns insert position, and should be faster
; enlarge: function [
	; "Ensure certain SIZE of the BLOCK, fill empty space with VALUE"
	; block [any-block! any-string!] size [integer!] value [any-type!]
; ][
	; #assert [any [any-block? block  char? :value]]
	; insert/only/dup skip block size :value size - length? block
	; ;; returns after size
; ]


;; see REP #104, but this is still different: we don't care what context word belongs to, only it's spelling and value
; same-paths?: function [p1 [block! path!] p2 [block! path!]] [
	; to logic! all [
		; find/match/same as [] p1 as [] p2
		; (length? p1) = length? p2
	; ]
; ]

; find-same-path: function [block [block!] path [path!]] [
	; forall block [
		; all [
			; path? :block/1
			; same-paths? block/1 path
			; return block
		; ]
	; ]
	; none
; ]

; #hide [#assert [
	; (a: object [] b: object [])
	; same-paths? as path! reduce [a b] reduce [a b]
	; 2 = index? r: find-same-path reduce [
		; as path! reduce [copy a b]
		; as path! reduce [a b]
	; ] as path! reduce [a b]
; ]]


;@@ move this to events context? where is it used anyway?
; is-printable?: function [
	; "True if it's a printable character input event"
	; event [map!]
; ][
	; to logic! all [
		; char? char: event/key
		; find charsets/printable char
		; empty? intersect event/flags [control alt]
	; ]
; ]

with-space: function [
	"Evaluate CODE providing SPACE word to it"
	space [object!] (space? space)
	_code [block!]  "Should be already bound to this function"	;-- underscore to avoid conflicts with the 'code' word ;@@ need bind/only
][
	do _code
]

;; fun facts:
;; - find/same call on a block of 10 items is as fast as on hash
;; - listing even 10 items into a hash adds much more overhead than calling find on a block
;; - it gets worse: at 50 items hash listing adds 7us to 20us, while find of last item adds less than 1us
;; - hash copy is much slower than to-block conversion - #5576
;; however, to support cyclic trees I must either use hash or just cap the depth
;; the logic I've chosen is to list parents quickly and carelessly, then look back and see what's wrong
list-parents: context [
	max-depth: 100												;-- auto-increased when tree is too deep
	warned?:   no
	
	return function [
		"Get a list of all parents of the SPACE"
		space   [object!] (space? space)
		/host "Exclude parents of SPACE's host"
		return: [block!]
		/extern max-depth warned?
	][
		list: clear []
		loop max-depth [
			append list any [
				space: space/parent
				(
					if host [
						while [face? last list] [taken: take/last list]
						if taken [								;-- can be 'none' if no faces were added
							#assert [host? taken]
							append list taken
						]
					]
					return copy list							;-- expected (fast) return point
				)
			]
		]
		;; if reached here, tree is either cyclic or too deep
		cyclic?: not tail? find/same/tail list last list
		either cyclic? [
			#debug [
				#assert [warned?  "Tree is cyclic"]
				warned?: yes									;-- issue only one warning
			]
			copy list											;-- for cyclic there's no meaningful path, but it must be finite
		][
			max-depth: max-depth * 2
			list-parents space									;-- for deep trees retry with a higher depth limit
		]
	]
]

get-host-path: function [
	"Get a host-relative path of SPACE"
	space   [object!]
	return: [block! none!] "none if not connected to a host"
][
	list: append reverse list-parents/host space space
	if host? list/1 [list]										;-- check for host reachability (doesn't check for liveness)
]

get-screen-path: function [
	"Get a screen-relative path of SPACE"
	space   [object!]
	return: [block! none!] "none if not connected to a screen"
][
	list: append reverse list-parents space space
	all [face? list/1  list/1/type = 'screen  list]				;-- check for screen reachability (doesn't check for liveness)
]

host-of: function [
	"Get host object of SPACE"
	space   [object!] (space? space)
	return: [object! none!] "none if not connected to a host"
][
	last only list-parents/host space
]

reload-function: function [
	"Recreate a compiled function to make it leverage altered runtime features"
	name [word! path!]
][
	set name func spec-of get name copy/deep body-of get name
]

generate-id: function [
	"Generate a new interpreter-unique integer ID"
	return: [integer!]
][
	id: [0]
	id/1: id/1 + 1
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
;@@ otherwise move it into tube template
; distribute: function [
	; "Distribute a numeric AMOUNT across items with given WEIGHTS"
	; amount  [number!] "Any nonnegative number" (amount >= 0)
	; weights [block!] "Zero for items that do not receive any part of AMOUNT" ((length? limits) = length? weights)
	; limits  [block!] "Maximum part of AMOUNT each item is able to receive; NONE if unlimited" (0 < length? limits)
; ][
	; data: clear []
	; sum-weights: 0.0
	; repeat i count: length? weights [
		; weight: 1.0 * any [weights/:i 0]
		; either weight <= 0 [
			; repend data [i 0.0 0.0]
		; ][
			; limit: 1.0 * max 0 any [limits/:i 1.#inf]
			; sum-weights: sum-weights + weight
			; repend data [i weight limit / weight]
		; ]
	; ]
	
	; result: append/dup make block! count amount * 0 count
	; if sum-weights <= 0 [return result]
	; sort/skip/compare data 3 3
	
	; left: 1.0 * amount
	; foreach [i weight slice] data [
		; if left <= 0 [break]
		; part: min slice left / sum-weights
		; left: left - used: to amount part * weight
		; sum-weights: sum-weights - weight
		; result/:i: used
	; ]
	; result
; ]


; #assert [
	; [100]         == distribute 100 [1]        [2e9]
	; [ 99]         == distribute 100 [1]        [ 99]
	; [ 99]         == distribute 100 [2]        [ 99]
	; [  0]         == distribute 100 [1]        [  0]
	; [  0]         == distribute 100 [0]        [2e9]
	; [ 50  50]     == distribute 100 [1  1]     [2e9 2e9]
	; [ 25  50  25] == distribute 100 [1  2   1] [2e9 2e9 2e9]
	; [ 33  33  34] == distribute 100 [1  1   1] [2e9 2e9 2e9]
	; [ 33  33  34] == distribute 100 [1  1   1] [#(none) #(none) #(none)]
	; [  0 100   0] == distribute 100 [0  1   0] [2e9 2e9 2e9]
	; [ 33  34  33] == distribute 100 [1  1   1] [2e9 2e9  33]
	; [  1   2   3] == distribute 100 [1  1   1] [  1   2   3]
	; [ 33  33  33] == distribute 100 [1 10 100] [ 33  33  33]
	; [  0   0   0] == distribute 100 [1 10 100] [  0   0   0]
	; [  0   0   0] == distribute 100 [0  0   0] [  0   0   0]
	; [  0   0   0] == distribute 100 [0  0   0] [  3   2   1]
	; [  0   0   0] == distribute 100 [1  2   3] [ -1  -1  -1]
	; [  0   0   0] == distribute 100 [0 -1  -1] [  3   2   1]
	; [14 29 42 15] == distribute 100 [1 2 3 1] [2e9 2e9 2e9 2e9]
	; [25 50  0 25] == distribute 100 [1 2 0 1] [2e9 2e9 2e9 2e9]
	; [27 53  0 20] == distribute 100 [1 2 0 1] [2e9 2e9 2e9  20]
	; [28 52  0 20] == distribute 100 [1 2 0 1] [2e9  52 2e9  20]
	; [28 52  0 20] == distribute 100 [1 2 1 1] [2e9  52   0  20]
	; [34 66  0  0] == distribute 100 [1 2 0 0] [2e9 2e9 2e9 2e9]
	; [66  0  0 34] == distribute 100 [2 0 0 1] [2e9 2e9 2e9 2e9]
	; [50.0 25.0 0.0 25.0] == distribute 100.0 [2 1 0 1] [2e9 2e9 2e9 2e9]
	; [50%  25%  0%  25% ] == distribute 100%  [2 1 0 1] [2e9 2e9 2e9 2e9]
; ]

;@@ only used in glossy style and text template - move there
; new-rich-text: none
; context [
	; ;; rtd-layout is slow! about 200 times slower than object creation (it also invokes VID omg)
	; ;; just make face! is 120 times slower too, because of on-change handlers
	; ;; rich text does not require any of that however, so I mimick it using a non-reactive object
	; ;; achieved construction time is 16us vs 200us
	; light-face!: construct map-each w exclude words-of :face! [on-change* on-deep-change*] [to set-word! w]
	; light-face!/para: make para! [wrap?: on]
	; rtd-template: make face! compose [
	; rtd-template: compose [
		; on-change*: does []								;-- for whatever reason, crashes without this
		; on-deep-change*: does []
		; (system/view/VID/styles/rich-text/template)
	; ]
	; set 'new-rich-text does [make light-face! rtd-template]
; ]


;@@ this is mostly used for text's /flags facet, but I'm not sure that design is still valuable
;@@ maybe /flags (now /config/flags?) should be a map? would be more convenient?
flags: context [
	include: function [
		"Include FLAG into SET if it's not there"
		set  [series!]
		flag [any-type!]
	][
		unless find/only set :flag [append/only set :flag]
		set
	]

	exclude: function [
		"Exclude FLAG into SET if it's there"
		set  [series!]
		flag [any-type!]
	][
		remove find/only set :flag
		set
	]

	set: function [
		"Include or exclude FLAG from SET"
		set   [series!]
		flag  [any-type!]
		state [logic! none!] "True to include, false/none to exclude"
	][
		either state [include series :flag][exclude series :flag]
	]
	
	set?: function [
		"Test if SET contains FLAG"
		set  [series!]
		flag [any-type!]
	][
		to logic! find/only flags :flag
	]
]


dictionary: context [
	;; extend the default retarded put with any-type key and /same refinement (see #5532)
	;; (does not support maps as they don't support such keys, and would slow down the function)
	put: function [
		"Replace the value following a KEY, and return the new value" 
		dict    [series!] 
		key     [any-type!] 
		value   [any-type!] 
		/case "Perform a case-sensitive search"
		/same "Perform a sameness search"
		return: [series!]
	][
		either pos: find/only/skip/:same/:case dict :key 2 [
			pos/2: :value
		][
			append/only append/only dict :key :value
			:value
		]
	]
		
	remove: function [
		"Remove the KEY and its value from a dictionary"		;-- O(1)
		dict [series!]
		key  [any-type!]
		/case "Perform a case-sensitive search"
		/same "Perform a sameness search"
	][
		if pos: find/only/skip/:same/:case dict :key 2 [
			unless pos =? end: skip tail dict -2 [change pos end] 
			clear end
		]
		dict
	]
]	

		
trees: context [
	store-path-value: function [
		"Store VALUE for the given tree PATH in the given ROOT map"
		root  [map!]
		path  [path! block! (parse path [some word!]) word!]
		value [default!]
		/reverse "Reverse the path"
	][
		case [
			word? path [path: append clear [] path]
			reverse    [path: system/words/reverse append clear [] path]
		]
		foreach item path [
			root: any [
				root/:item
				root/:item: make map! 4
			]
		]
		put root #value :value									;-- final item must not be a word! to avoid conflict with template names
	]
	
	make-access-path: function [
		"Construct a path for fast access to a given tree PATH in ROOT"
		root    [path! block! word!]
		path    [path! block! (parse path [some word!]) word!]
		/reverse "Reverse the path"
		/scope   "Get path of the scope instead of its value (for children access)"
		return: [path!]
	][
		if reverse [path: system/words/reverse append clear [] path]
		result: append to path! root path
		unless scope [append result #value]
		result
	]
		
	fetch-path-value: function [
		"Retrieve VALUE of the given tree PATH in the given ROOT map"
		root    [map!]
		path    [path! block! (parse path [some word!]) word!]
		/reverse "Reverse the path"
		return: [default!]
	][
		get make-access-path/:reverse 'root path
	]
	
	match-path: function [
		"Find the most specialized fit for the given tree PATH in the given ROOT map"
		root    [map!]
		path    [block! path! word!]    "Is reversed before lookup"
		/part n [integer! block! path!] "Match only a part of the path"
	][
		path: reverse append/:part clear [] path n
		;; optimization note: 'path' may be long, 10+ items, loop's early failure is expected very often
		foreach item path [root: any [root/:item break]]		;@@ use for-each/reverse when fast; repeat-based approach is slower here
		select root #value										;@@ #5007 - can't compile 'root/#value'
	]
]

