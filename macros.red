Red [
	title:    "Macros used by Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.macros
]


;; MEMO: requires `function` scope or `~~p` will leak out
#macro [#expect skip] func [[manual] bgn end /local quote? rule error] [
	remove bgn
	unless quote?: :bgn/1 = 'quote [end: back end]
	rule:  copy/part bgn end
	error: compose [expected ~~p quote (last rule)]				;-- ignore 'quote' in the error message, but quote to avoid double evaluation
	change/only bgn compose [(rule) | ~~p: (to paren! error)]
	bgn															;-- reprocess as rule could be a block 
]

#macro [#tip string!] func [[manual] bgn end /local msg] [
	msg: take remove bgn
	insert bgn reduce [to issue! 'debug 'tips reduce [to issue! 'print rejoin ["*** Tip: " msg]]]
	bgn
]