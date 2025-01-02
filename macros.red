Red [
	title:    "Macros used by Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.macros
]


;; MEMO: requires `function` scope or `~~p` will leak out
#macro [#expect skip] func [[manual] bgn end /local quote? rule error name] [
	quote?: all [word? bgn/2  bgn/2 = 'quote  remove next bgn]
	rule: reduce [bgn/2]
	if quote? [insert rule 'quote]								;-- sometimes need to match block literally
	name: either string? bgn/2 [bgn/2][mold/flat bgn/2]
	error: compose/deep [
		do make error! rejoin [
			(rejoin ["Expected "name" at: "]) mold/part ~~p 100
		]
	]
	change/only remove bgn compose [(rule) | ~~p: (to paren! error)]
	bgn 
]

#macro [#tip string!] func [[manual] bgn end /local msg] [
	msg: take remove bgn
	insert bgn reduce [to issue! 'debug 'tips reduce [to issue! 'print rejoin ["*** Tip: " msg]]]
	bgn
]