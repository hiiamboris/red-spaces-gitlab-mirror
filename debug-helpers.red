Red [
	title:   "Simple debug helpers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export, prettify

exports: [dump-event dump-tree expand-space-path fix-paths dorc mold probe save ?? ? help debug-draw]


;-- debug func
dump-event: function [event] [
	event: object map-each/eval w system/catalog/accessors/event! [
		[to set-word! w 'quote event/:w]
	]
	help event
]

dump-tree: function [
	"List hierarchical tree of currently rendered spaces"
	/from host [object!] "Root face to list from (by default - the screen)" (host? host)
][
	foreach-*ace path: any [host system/view/screens/1] [
		spc: last path
		probe path
	]
	()
]

dorc: does [do read-clipboard]

color-names: make map! map-each/eval [name value [tuple!]] to [] system/words [[value to word! name]]
color-name: function [color [tuple! none!]] [			;-- used for debug output to easier identify spaces
	any [
		select color-names color 
		color
		'colorless
	]
]

space-id: function [space [object!]] [					;-- used to identify spaces in debug sessions
	#composite "(color-name select space 'color) (space/type):(space/size)"	
]


add-indent: function [text [string!] size [integer!]] [
	indent: append/dup clear "" #" " size
	parse text [any [#"^/" not end insert indent (lf?: yes) | skip]]
	if lf? [insert text indent]
	text
]

mold: :system/words/mold								;-- let it always be available in Spaces context
if action? :mold [
	native-mold: :mold
	
	;; this monstrosity is adjusted to make more user-friendly output
	;; without /all it will not expand inner objects/maps, and will output spaces in compact form type:size
	;; and generally will be closer to `help` output
	;; mold/all will output loadable info in format acceptable by %load-anything.red
	context [
		; system/words/native-mold: :mold
		decor*: [[
			block!    ["[" "]"]
			paren!    ["(" ")"]
			path!     ["" ""]
			lit-path! ["'" ""]
			get-path! [":" ""]
			set-path! ["" ":"]
			hash!     ["##[make hash! [" "]]"] 
			map!      ["##[make map! [" "]]"] 
			event!    ["##[make event! [" "]]"] 
			object!   ["##[construct/only [" "]]"]
			function! ["##[func" "]"] 
			action!   ["##[make action!" "]"]			;-- can't use native mold since it will use it's own indentation 
			native!   ["##[make native!" "]"] 
			routine!  ["##[routine" "]"] 
			image!    ["##[make image! [" "]]"] 
		][
			block!    ["[" "]"]
			paren!    ["(" ")"]
			path!     ["" ""]
			lit-path! ["'" ""]
			get-path! [":" ""]
			set-path! ["" ":"]
			hash!     ["hash [" "]"] 
			map!      ["#(" ")"] 
			event!    ["event [" "]"] 
			object!   ["object [" "]"] 
			function! ["func" ""] 
			action!   ["action" ""] 
			native!   ["native" ""] 
			routine!  ["routine" ""] 
			image!    ["image [" "]"] 
		]]
		
		set 'mold function [
			{Returns a source format string representation of a value}
			value [any-type!]
			/only "Exclude outer brackets if value is a block" 
			/all  "Return value in loadable format" 
			/flat "Exclude all indentation"
			/deep "Expand nested structures on all levels" 
			/part "Limit the length of the result" 
				limit: (pick [100'000'000  10'000] all) [integer!] (limit >= 0)
		][
			indent: make string! 32
			depth:  0
			mold* :value limit
		]
		
		~: system/words
			
		mold-stack: make hash! 100						;-- used to avoid cycles
		mold*: function [value [any-type!] limit /extern deep flat] with :mold [
			; print native-mold reduce [only all :value]
			sp: " "
			output: make string! 16
			decor: select pick decor* all type: type?/word :value
			if ~/all [decor only depth = 0] [decor: ["" ""] noindent?: yes]
			~/all [decor  find/same/only mold-stack :value  return emit ["..."]]
			unless deep [
				if 0 < depth [
					if 'block! = type [
						try [							;-- fails on system/words
							parse value: copy value [any [	;-- simple grouping ;@@ TODO: also find periodic patterns
								s: ahead [set x skip (xtype: type? :x) 9 xtype] [	;@@ how many items minimum to group?
									skip change [some x e:] (to word! rejoin ['x offset? s e])
								|	change xtype (to word! xtype)
									change [some xtype e:]  (to word! rejoin ['x offset? s e])
								]
							|	skip
							]]
						]
					]
					if 'object! = type [
						string: case [
							face? value [
								either 'rich-text = :value/type [ 
									native-mold value/text
								][
									rejoin [:value/type ":" mold* :value/size limit]
								]
							]
							space? value [
								rejoin [:value/type ":" mold* :value/size limit]
							]
							(class-of value) = class-of font! [native-mold value/name]
							'else [
								size: any [attempt [system/console/size/x] 80]
								rejoin [
									decor/1
									native-mold/only/part words-of value size - length? indent	;@@ ellipsize it
									decor/2
								]
							]
						]
						return emit [string] 
					]
				]
			]
			
			if decor [append/only mold-stack :value]
			switch/default type [
				pair! [
					either all [
						emit [(native-mold value)]
					][
						x: value/x  y: value/y
						if x =  2e9 [x: 'INF]
						if x = -2e9 [x: '-INF]
						if y =  2e9 [y: 'INF]
						if y = -2e9 [y: '-INF]
						emit [(native-mold x) "x" (native-mold y)]
					]
				]
				object! map! hash! block! paren! path! get-path! set-path! lit-path! event! [
					if any-path? value [sp: "/" flat': flat flat: yes]
					step 'depth
					;; output events too ;@@ won't be loadable since can't make events
					if 'event! = type [
						value: construct/only map-each/eval word system/catalog/accessors/event! [
							[to set-word! word  :value/:word]
						]
					]
					;; emit skip for blocks in /all mode
					if ~/all [
						all
						find [block! hash! paren!] type
						skip?: unless head? value [-1 + index? value]
					][
						skip-decor: reduce ["##[skip " rejoin [" " skip? "]"]]
						emit [skip-decor/1]
						value: head value
					]
					pos: block: to block! value
					if find [object! event!] type [				;@@ workaround for #5140 - restore words
						values: values-of value
						repeat i length? values [
							poke block i * 2 :values/:i
						]
					]
					;; emit opening
					unless noindent? [
						if ~/all [not empty? block new-line? block] [	;@@ not empty = workaround for #5235
							append/dup indent #" " 4
						]
					]
					lf: unless flat [rejoin ["^/" indent]]
					emit [decor/1]
					;; emit contents
					if ~/all [							;-- exclude on-change in normal mold
						not deep
						object? value
					][
						remove/part find/skip pos 'on-change* 2 2
						remove/part find/skip pos 'on-deep-change* 2 2
						~/all [
							(length? pos) < 100			;-- exclude system/words and copies, which also return true on space? check
							space? value
							pos': find/skip pos 'cached 2
							block? :value/cache
							block? :value/cached
							change/only next pos' extract pos'/2 (3 + length? value/cache)	;-- minify /cached to only canvas sizes
						]
					]
					if ~/all [not flat  find [object! map!] type] [	;-- find max word length (excluding on-change possibly) 
						align: 1 + any [
							maximum-of map-each [word _] block [length? form word]
							0
						]
					]
					forall pos [						;-- emit items
						if new-line? pos [emit [lf]]
						string: mold* :pos/1 limit
						emit [string]
						unless tail? next pos [
							if align [
								string: append/dup clear "" " " align - length? string
								emit [string]
							]
							emit [sp]
						]
						if limit <= 0 [break]
					]
					if ~/all [not empty? block new-line? block] [	;@@ not empty = workaround for a heisenbug
						unless noindent? [clear skip tail indent -4]
						unless flat [
							lf: rejoin ["^/" indent]
							emit [lf]
						]
					]
					;; emit closing & skip closing
					emit [decor/2]
					if skip-decor [emit [skip-decor/2]]
					step/down 'depth
					if any-path? value [flat: flat']
				]
				image! [
					size:  value/size
					either ~/all [not deep depth >= 1] [
						emit [decor/1 (native-mold size) " ..." decor/2]
					][
						rgb:   value/rgb
						alpha: value/alpha
						emit [decor/1 (native-mold size) sp]	;-- mulitple emits will update limit on the go
						emit [(mold* rgb limit) sp]
						emit [(mold* alpha limit) decor/2]
					]
				]
				function! action! native! routine! [
					spec: spec-of :value
					body: body-of :value
					if ~/all [not deep depth > 1] [
						new-line/all spec: copy spec no
						parse spec [
							any [/local remove to end | not 'return all-word! | remove skip]
						]
						body: [...]
					]
					if find [action! native!] type [body: [...]]	;-- body is unknown to runtime
					deep': deep  deep: yes				;-- don't shorten function bodies
					emit [decor/1 sp (mold* spec limit) sp (mold* body limit) decor/2]
					deep: deep'
				]
				handle! [										;-- make handles loadable by converting to integers
					value: second transcode/one next native-mold/all value	;-- extract the integer
					string: rejoin [form to-hex value "h"]		;-- convert to hex
					emit [string]
				]
			][
				string: native-mold/:all/:flat :value
				emit [string]
			]
			if decor [clear find/same/only mold-stack :value]
			
			output
		]
		
		emit: function [strings [block!] /extern limit] with [:mold :mold*] [
			foreach string reduce strings [
				if paren? string [string: do string]
				unless string [continue]
				append/part output string limit
				limit: max 0 limit - length? string
			]
			output
		]
			
	]
]

probe: function [
	"Returns a value after printing its molded form"
	value [any-type!]
][
	print mold :value
	:value
]

??: function [
	"Prints a word and the value it refers to (molded)"
	'value [any-type!] "Word, path, multiple words/paths in a block, or any value"
][
	case [
		any [any-word? :value any-path? :value] [
			prin value prin ": "
			print mold get/any value
		]
		block? :value [									;-- multiple named values on a single line
			print form map-each word value [
				`"(word): (mold/part/flat get/any word 20) "`
			]
		]
		'else [print mold :value]
	]
]

help: ?: none
if function? :system/words/help [						;-- if console present, remove the annoying trailing new-line
	set 'help set '? function [
		{Displays information about functions, values, objects, and datatypes}
		'word [any-type!]
	][
		if #"^/" = last msg: help-string :word [take/last msg]	;@@ unfortunately, help-string is happy to dump full images: #4464
		print msg
	]
]

save: none
context [												;-- replace compiled mold with interpreted mold, and add /deep
	body: body-of :system/words/save
	parse body rule: [any [
		ahead any-list! into rule
	|	ahead any-path! into [thru 'mold insert ('deep) to end]
	|	change only 'mold ('mold/deep)
	|	skip
	]]
	set 'save func spec-of :system/words/save body
]


; form: :system/words/form								;-- let it always be available in Spaces context
; if action? :form [
	; native-form: :form
	
	; set 'form function [
		; "Returns a user-friendly string representation of a value"
		; value [any-type!] 
		; /part "Limit the length of the result" 
			; limit [integer!] 		
	; ][
		; switch/default type?/word :value [
			; object! [mold value]
			; block! hash! paren! path! get-path! set-path! lit-path! [
				; sp: either any-path? value ["/"][" "]
				; left: limit
				; r: rejoin next map-each/eval x value [
					; either part [
						; s: form/part :x limit
						; left: left - 1 - length? s
					; ][
						; s: form :x
					; ]
					; [sp s]
				; ]
				; if part [clear skip r limit]
				; r
			; ]
		; ][
			; either part
				; [native-form/part :value limit]
				; [native-form      :value]
		; ]
	; ]
; ]



;@@ TODO: at least 3 canvases: none (and maybe 0x0), half-infinite, and finite; configurable size
debug-draw: function ["Show GUI to inspect spaces Draw block"] [
	context [
		list: code: free: sized: drawn: path: obj: none
		rea: reactor [canvas?: no]
		fixed: make font! [name: system/view/fonts/fixed]
		;; can't put paths into list-view/data because of face's aggressive ownership system
		paths: []
		update: has [i] [
			clear paths
			list/data: collect [
				i: 0
				foreach-*ace path: system/view/screens/1 [
					append/only paths path
					keep reduce [mold path i: i + 1]
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
					not path: pick paths list/selected
				][
					"Select a space in the list"
				][
					either is-face? obj: last path [
						sized/draw: none
						either free/draw: drawn: obj/draw [
							mold prettify/draw drawn
						][
							"Face has no Draw block!"
						]
					][
						drawn: reduce [
							free/draw:  render    last path
							sized/draw: render/on last path sized/size
						]
						mold prettify/draw pick drawn not rea/canvas?
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
