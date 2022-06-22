Red [
	title:   "Simple debug helpers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export, prettify

exports: [dump-tree expand-space-path fix-paths dorc probe~ ??~ debug-draw]


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
				
;; helper to work with words as objects in paths
;@@ can there be a -> operator for select+get+maplookup?
expand-space-path: function [path [any-word! any-path!] /local coll] [
	if word? path [path: to path! path]
	set/any 'coll get/any path/1
	out: head clear next copy path 
	for-each [pos: item] as [] next path [				;@@ as [] = workaround for #4421
		if any-function? :coll [append out pos  break]
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
			unless any [series? :coll  any-object? :coll  map? :coll] [
				#print "Error getting path (path) after (out) which is (type?/word :coll)"
			]
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

mold~stack: make hash! 100								;-- used to avoid cycles
mold~: function [value [any-type!] /indent indent-size [integer! none!]] [
	default indent-size: 4
	decor: select [
		block!  ["[" "]"]
		hash!   ["make hash! [" "]"] 
		map!    ["#(" ")"] 
		object! ["make object! [" "]"] 
	] type?/word :value
	if decor [
		if find/same/only mold~stack :value [return "..."]
		append/only mold~stack value
	]
	result: switch/default type?/word :value [
		map! object! [
			block: to [] value
			longest: any [last sort map-each [k v] block [length? form k]  0]
			strings: copy []
			foreach [k v] block [
				if find [on-change* on-deep-change*] k [continue]	;-- skip hidden fields
				v: case [
					object? :v ["object [...]^/"]
					image?  :v ["make image! [...]^/"]
					'else [append mold~/indent :v indent-size #"^/"]
				]
				k: rejoin [k ": "]
				if tail? find/tail v #"^/" [k: pad k longest + 2]
				append strings rejoin [k v]
			]
			inside: add-indent rejoin ["" strings] indent-size
			rejoin [decor/1 #"^/" inside decor/2]
		]
		block! hash! image! [
			strings: copy []
			p: value
			forall p [
				x: case [
					object? :p/1 [copy "object [...]"]
					image?  :p/1 [copy "make image! [...]"]
					'else [mold~/indent :p/1 indent-size]
				]
				if new-line? p [insert x #"^/"]
				append strings x
			]
			inside: rejoin ["" strings]
			if new-line? value [append add-indent inside indent-size "^/"]
			rejoin [decor/1 inside decor/2]
		]
		image!
	][
		mold :value
	]
	if decor [remove top mold~stack]
	result
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

find-deep: none
context [
	path: make path! 10
	
	find-deep*: function [list [any-block!] value [any-type!]] [
		;; find should be faster on hashes than parse
		either pos: find/only/same list :value [
			throw copy append path index? pos
		][
			append path 1
			forall list [								;@@ for-each can't be used with throw yet!
				inner: list/1
				;@@ [hash! block!] value filter seems buggy in for-each! can't locate the bug!
				unless any [hash? inner block? inner] [continue]	
				change top path index? list
				find-deep* inner :value
			]
			remove top path
		]
		none
	]
	
	set 'find-deep function [list [any-block!] value [any-type!]] [
		clear path
		catch [find-deep* list :value]
	]
]
	
dump-parents-list: function [list [hash! block!] cache [hash! block!]] [			;-- used for cache debugging only
	#print "parents-list: (\size = ((length? list) / 2)) ["
	foreach [space parents] list [
		prin ["   " mold/part/flat space 40 "(" pad find-deep cache space 12 ")" "-> "]
		foreach [node parent] parents [
			prin [find-deep cache node find-deep cache parent "| "]
		]
		print ""
	]
	print "]"
]

;@@ TODO: at least 3 canvases: none (and maybe 0x0), half-infinite, and finite; configurable size
debug-draw: function ["Show GUI to inspect spaces Draw block"] [
	context [
		list: code: free: sized: drawn: path: obj: none
		rea: reactor [canvas?: no]
		fixed: make font! [name: system/view/fonts/fixed]
		update: does [
			list/data: collect [
				foreach-*ace path: anonymize 'screen system/view/screens/1 [
					keep reduce [form path path]
				]
			]
		]
		view/no-wait/options [
			below list: text-list focus 400x400 on-created [update]
			panel 2 [
				origin 0x0 space 10x-5
				text 195 "w/o canvas" text "with canvas"
				free:  box 195x170 on-up [rea/canvas?: no] 
					react [face/color: do pick [white silver] not rea/canvas?]
				sized: box 195x170 on-up [rea/canvas?: yes]
					react [face/color: do pick [white silver] rea/canvas?]
			] return
			code: area 400x600 font fixed react [
				face/text: either any [
					not list/selected
					not path: pick list/data list/selected * 2
				][
					"Select a space in the list"
				][
					either is-face? obj: get last path [
						sized/draw: none
						either free/draw: drawn: obj/draw [
							mold~/indent prettify/draw drawn 3
						][
							"Face has no Draw block!"
						]
					][
						drawn: reduce [
							free/draw:  render    last path
							sized/draw: render/on last path sized/size
						]
						mold~/indent prettify/draw pick drawn not rea/canvas? 3
					]
				] 
			]
			at 350x10 button "Update" [update]
		][
			actors: object [
				on-created: func [face] [
					face/offset: face/parent/size - face/size * 1x0
					foreach other face/parent/pane [
						unless other =? face [
							other/offset/x: face/offset/x - other/size/x - 5
							break
						]
					]
				]
			]
		]
	]
]

export exports
