Red [
	title:   "Simple debug helpers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export, prettify

exports: [dump-tree expand-space-path fix-paths dorc probe~ ??~]

dump-tree: function [] [
	foreach-*ace path: anonymize 'screen system/view/screens/1 [
		spc: get last path
		print [pad spc/size 10 path]
	]
	()
]

fix-paths: function [
	"Replaces convenient but invalid space-referring paths with valid ones"
	code [block!] "Block where to replace paths"
	/local path
][
	parse r: copy/deep code [any [
		change only set path any-path! (to path expand-space-path path)
	|	skip
	]]
	r
]
				
expand-space-path: function [path [any-word! any-path!] /local coll] [
	if word? path [path: to path! path]
	set/any 'coll get/any path/1
	out: head clear next copy path 
	for-each [pos: item] as [] next path [				;@@ as [] = workaround for #4421
		space: if word? :item [
			;; substitute global word in the path with a word that refers to a space
			any [
				all [object? :coll  in coll 'map  found: find coll/map item  found/1]
				all [object? :coll  is-face? coll  any [item = 'space  item = select coll 'space]  coll/space]
				all [block?  :coll  found: find coll item  found/1]
			]
		]
		set/any 'coll either space [
			append clear out space
			get/any space
		][
			append out :item
			:coll/:item
		]
	]
	if single? out [out: out/1]
	case [
		any [get-word? path get-path? path] [out: either word? out [to get-word! out][as get-path! out]]
		any [set-word? path set-path? path] [out: either word? out [to set-word! out][as set-path! out]]
	]
	out
]

; get-space: function ['path [word! path!]] [
	; get expand-space-path (path)
; ]

; ;-- debug helper
; ?s: function ['path [word! path!]] [
	; val: get-space (path)
	; print replace help-string val "VAL" uppercase mold path
; ]

; ??s: function ['path [word! path!]] [
	; probe get-space (path)
	; ()
; ]

; sdo: function [code [block!]] [
	; map-each/self/only [p [path!]] code [get-space (p)]
	; do code
; ]

dorc: does [do read-clipboard]


add-indent: function [text [string!] size [integer!]] [
	indent: append/dup clear "" #" " size
	parse text [any [#"^/" not end insert indent (lf?: yes) | skip]]
	if lf? [insert text indent]
	text
]

mold~: function [value [any-type!]] [
	decor: select [
		block!  ["[" "]"]
		hash!   ["make hash! [" "]"] 
		map!    ["#(" ")"] 
		object! ["make object! [" "]"] 
	] type?/word :value
	switch/default type?/word :value [
		map! object! [
			block: to [] value
			longest: any [last sort map-each [k v] block [length? form k]  0]
			strings: copy []
			foreach [k v] block [
				v: either object? :v ["object [...]^/"][append mold~ :v #"^/"]
				k: rejoin [k ": "]
				if tail? find/tail v #"^/" [k: pad k longest + 2]
				append strings rejoin [k v]
			]
			inside: add-indent rejoin ["" strings] 4
			rejoin [decor/1 #"^/" inside decor/2]
		]
		block! hash! [
			strings: copy []
			p: value
			forall p [
				x: either object? :p/1 [copy "object [...]"][mold~ :p/1]
				if new-line? p [insert x #"^/"]
				append strings x
			]
			lf?: either new-line? value ["^/"][""]
			inside: add-indent rejoin ["" strings] 4
			rejoin [decor/1 inside lf? decor/2]
		]
	][mold :value]
] 

probe~: function [
	"Returns a value after printing its molded form, excluding inner objects"
	value [any-type!]
][
	print mold~ any [
		attempt [prettify/data :value]
		:value
	]
	:value
]

??~: function ['value [any-type!]] [
	probe~ either any [any-word? :value any-path? :value] [
		prin value prin ": "
		get/any value
	][
		:value
	]
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