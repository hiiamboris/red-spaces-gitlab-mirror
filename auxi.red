Red [
	title:   "Auxiliary helper funcs for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- we need this to be able to call event functions recursively with minimum allocations
;-- we can't use a static block but we can use one block per recursion level
block-stack: object [
	stack: []
	get: does [any [take/last stack  make [] 100]]
	put: func [b [block!]] [append/only stack clear head b]
	hold: func [b [block!]] [at  append get head b  index? b]
]


range: func [a [integer!] b [integer!]] [
	collect [while [a <= b] [keep a  a: a + 1]]
]


for: func ['word [word! set-word!] i1 [integer!] i2 [integer!] code [block!]] [
	if i2 < i1 [exit]			;@@ return none or unset? `while` return value is buggy anyway
	set word i1 - 1
	while [i2 >= set word 1 + get word] code
]

;-- debug func
dump-event: function [event] [
	foreach w system/catalog/accessors/event! [
		print [w mold/flat/part event/:w 60]
	]
]

