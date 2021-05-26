Red [
	title:   "Simple debug helpers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export

exports: [dump-tree get-space ?s ??s sdo]

dump-tree: function [] [
	foreach-*ace path: anonymize 'screen system/view/screens/1 [
		spc: get last path
		print [pad spc/size 10 path]
	]
	()
]

get-space: function ['path [word! path!]] [
	if word? path [path: to path! path]
	o: get path/1
	foreach x next path [
		o: either any [
			all [word? x  object? :o  in o 'map  p: find o/map x]
			all [word? x  block?  :o             p: find o     x]
		] [get p/1] [:o/:x]
		if word? :o [o: get o]
	]
	:o
]

;-- debug helper
?s: function ['path [word! path!]] [
	val: get-space (path)
	print replace help-string val "VAL" uppercase mold path
]

??s: function ['path [word! path!]] [
	probe get-space (path)
	()
]

sdo: function [code [block!]] [
	map-each/self/only [p [path!]] code [get-space (p)]
	do code
]


;-- experimental probe with depth control
context [
	containers: make typeset! [block! object! map! hash! paren! function!]
	openings: reduce [block! "[" object! "object [" map! "#(" hash! "make hash! [" paren! "(" function! "function"]
	closings: reduce [block! "]" object! "]"        map! ")"  hash! "]"            paren! ")" function! ""]

	indent-text: function [text [string!] isize [integer!] /after] [
		if isize <= 0 [return text]
		text: copy text
		indent: append/dup clear "" #" " isize
		append append clear line: "" "^/" indent
		unless after [insert text indent]
		replace/all text #"^/" line
	]

	set '?p function [depth [integer!] value [any-type!] /indent isize [integer!]] [
		isize: any [isize 0]
		either find containers type: type? :value [
			either depth = 0 [
				prin mold/flat/part :value 40
			][
				either any [object? :value map? :value function? :value] [
					either function? :value [
						prin [select openings type  mold/flat spec-of :value  ""]
						?p/indent depth - 1 body-of :value isize
					][
						print indent-text select openings type isize
						foreach [k v] to [] :value [
							prin [indent-text pad mold k 10 isize + 4 ""]
							?p/indent depth - 1 :v isize + 4
							print ""
						]
						print indent-text select closings type isize
					]
				][
					prin select openings type
					if nl?: new-line? value [prin ["^/" indent-text "" isize + 4]]
					repeat i length? value [
						?p/indent depth - 1 :value/:i isize + 4
						unless i = length? value [prin " "]
						if new-line? skip value i [prin ["^/" indent-text "" isize + 4]]
					]
					if nl? [prin ["^/" indent-text "" isize]]
					prin select closings type
				]
			]
		][
			prin indent-text/after mold/part :value 40 isize
		]
	]
]

export exports