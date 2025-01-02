Red [
	title:    "MOLD replacement for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.mold
	depends:  [once with overload reshape map-each advanced-function]
	notes: {
		User friendly molding rules memo:
		- `mold` (and `probe`/`??`/`?`/`help`) should be replaced globally so it works in the console
		- `save` should not be replaced, or it breaks a lot of code; where needed, `write mold/all` can be used instead
		- `form` can't be replaced as it's too ubiquitous - implicitly in series operations everywhere
		- I've never had a need to replace `source` 
		- there's an expanded (depth=0) and compact (depth>0) molded forms for some datatypes
		  this allows to expand the contents of complex values but not to get lost in their inner values
		- compact form should have no newlines in it, so /flat refinement may turn in on
		- `??` with a list of values is single-line by design, so uses only compact forms, and places limit on each
		- excess of /part limit should be ellipsized
		- for block: group values of the same type when block is multiline or doesn't fit into a single line
		- for object/map: align single-line values in a column, but not multiline values
		- blocks are different: there are data blocks, function spec blocks, parse, draw dialect blocks, etc.
		  same rules cannot apply to each, and if it can't be guessed, it's better left expanded
		- /all should produce %red-common/load-anything.red comptabile construction syntax, so the output can be loaded
		- /all should not limit the output and should not group it, or it loses its point
		- limit and output should be shared to avoid modifying and copying on all nesting levels repeatedly
		  i.e. inner mold call should modify global length once, rather than modifying its own and letting outer call do the same
		  while for output the main goal is to avoid excessive (and blind) allocation
	}
]


;; keep the originals as they are still useful sometimes, especially `mold`, e.g. when I need really fast and huge dump
;; and let these funcs always be available in Spaces context
;; in case one wants to disable them globally, they will still work for Spaces
once system/words/mold*:  :system/words/mold
once system/words/probe*: :system/words/probe
once system/words/??*:    :system/words/??
once system/words/?*:     :system/words/?
once system/words/help*:  :system/words/help
mold*: :system/words/mold*										;-- native mold is still used in Spaces when performance is critical
#assert [action? :mold*]

;; temporary definition for assertions to run; replaced later by a real one
once is-space?: func [x][no]

;; replaced so it uses the new mold, and also to add an /all refinement
global probe: function [
	"Returns a value after printing its molded form"
	value [any-type!]
	/all "Print in serialized format"
][
	print mold/:all :value
	:value
]
	
;; replaced to use the new mold, and also to support multiple words/paths list
; global ??: function [
	; "Prints a word and the value it refers to (molded)"
	; 'value [any-type!] "Word, path, multiple words/paths in a block, or any value"
; ] reshape [
	; switch/default type?/word :value [
		; @(to [] any-word!) @(to [] any-path!) [
			; prin `"(value): "`
			; print mold get/any value
			; get/any value										;-- pass the value so `??` can be used in expressions
		; ]
		; block! [												;-- multiple named values on a single line
			; string: clear {}
			; foreach word value [								;@@ use map-each
				; append string `"(word): (mold/flat/part get/any word 20)  "`
			; ]
			; print trim/tail string
		; ]
	; ][
		; print mold :value
		; :value
	; ]
; ]

global ??: function [
	"Prints a word and the value it refers to (molded)"
	'value [any-type!] "Word, path, multiple words/paths in a block, or any value"
][
	print mold :value
	:value
]

overload :?? ['value [any-word! any-path!]] [
	prin `"(mold* value): "`
	print mold get/any value
	get/any value												;-- pass the value so `??` can be used in expressions
]

overload :?? ['value [block!]] [								;-- multiple named values on a single line
	string: clear {}
	foreach word value [										;@@ use map-each
		append string `"(word): (mold/flat/part get/any word 20)  "`
	]
	print trim/tail string
]

ellipsize: function [
	string [string!] "(modified)"
	limit  [integer!]
	/force
][
	if any [force (length? string) > limit] [
		dots: min 3 limit
		append/part clear skip string limit - dots "..." dots
	]
	string
]

#assert [
	""     = ellipsize "abcd" 0
	"."    = ellipsize "abcd" 1
	".."   = ellipsize "abcd" 2
	"..."  = ellipsize "abcd" 3
	"a..." = ellipsize "abcde" 4
	"abcd" = ellipsize "abcd" 4
]

;; replaced mainly to remove the annoying trailing line-feed
help: ?: if function? :help-string [							;-- help-string is undefined if no console is present
	global help: global ?: function [
		"Displays information about functions, values, objects, and datatypes"
		'word [any-type!]
	][
		msg: trim/tail help-string :word
		print ellipsize msg 10000								;@@ unfortunately, help-string is happy to dump full images: #4464
	]
]
	
global mold: context [
	;; format: datatype! [start delimiter end]
	;; (space delimiter turns into a newline when lf marker is found)
	markers: [[
		block!    ["["  " "  "]"]
		paren!    ["("  " "  ")"]
		path!     [""   "/"   ""]
		lit-path! ["'"  "/"   ""]
		get-path! [":"  "/"   ""]
		set-path! [""   "/"  ":"]
		hash!     ["##[make hash! ["      " "  "]]"] 
		vector!   ["##[make vector! ["    ""   "]]"] 
		image!    ["##[make image! ["     ""   "]]"] 
		map!      ["##[make map! ["       " "  "]]"] 
		event!    ["##[make event! ["     " "  "]]"] 
		object!   ["##[construct/only ["  " "  "]]"]
		function! ["##[func "             ""    "]"] 
		action!   ["##[make action! "     ""    "]"]		;-- can't use native mold since it will use it's own indentation 
		native!   ["##[make native! "     ""    "]"] 
		op!       ["##[make op! "         ""    "]"] 
		routine!  ["##[routine "          ""    "]"] 
	][
		block!    ["["  " "  "]"]
		paren!    ["("  " "  ")"]
		path!     [""   "/"   ""]
		lit-path! ["'"  "/"   ""]
		get-path! [":"  "/"   ""]
		set-path! [""   "/"  ":"]
		hash!     ["hash ["    " "  "]"] 
		vector!   ["vector ["  " "  "]"] 
		image!    ["image ["   ""   "]"] 
		map!      ["#["        " "  "]"] 
		event!    ["event ["   " "  "]"] 
		object!   ["object ["  " "  "]"] 
		function! ["func "     ""    ""] 
		action!   ["action "   ""    ""] 
		native!   ["native "   ""    ""] 
		op!       ["op "       ""    ""] 
		routine!  ["routine "  ""    ""] 
	]]
	
	abs: :absolute
	
	;; for brevity, known natives will be shown as their names
	natives: make hash!
		map-each/drop/eval [key value [native! action! op!]] to block! system/words [
			unless integer? body-of :value [continue]
			[:value key]
		] 
	
	add-indent: function [
		text   [string!] "(modified)"
		indent [integer!]
	][
		if indent > 0 [
			indent: append/dup clear {} #" " indent
			parse text [any [thru "^/" insert (indent)]]
		]
		text
	]
	
	#assert ["a^/    b^/    c" = add-indent copy "a^/b^/c" 4]
	
	compact-spec: function [
		fun    [any-function!]
		buffer [block!]
	][
		parse spec-of :fun [collect after buffer any [
			keep [word! | lit-word! | get-word! | refinement!]
		|	/local break
		|	skip
		]]
		buffer
	]
						
	terminal-width: does [any [attempt [system/console/size/x] 80]]
						
	min-group: 20												;-- min. number of items to group
	max-group: 1'000'000'000
	
	compress-list: function [
		list [any-list!]
		/local x y z
	][
		alt: clear []
		; print ["ANALYZING" mold* list]
		if (length? list) < min-group [return none]
		
		;; periodic patterns of 1-3 period...
		=x-template=: [end | quote (:x) | (=x=: [xtype]) =x=]	;-- rule relaxes itself on the go, to avoid backtracking
		=y-template=: [end | quote (:y) | (=y=: [ytype]) =y=]
		=z-template=: [end | quote (:z) | (=z=: [ztype]) =z=]
		=set-x=: [set x skip (xtype: type? :x  =x=: =x-template=  =x=/4: :x)]
		=set-y=: [set y skip (ytype: type? :y  =y=: =y-template=  =y=/4: :y)]
		=set-z=: [set z skip (ztype: type? :z  =z=: =z-template=  =z=/4: :z)]
		=keep-x=: [keep (either single? =x= [xtype][:x])]
		=keep-y=: [keep (either single? =y= [ytype][:y])]
		=keep-z=: [keep (either single? =z= [ztype][:z])]
			
		if parse list [
			collect after alt [									;-- type xN patterns in the list
				s: =set-x= min-group max-group =x= e: end
				=keep-x= keep (to word! `"*(offset? s e)"`)
			]
		|	(clear alt) collect after alt [						;-- (typeX typeY) xN patterns
				s: =set-x= =set-y= min-group max-group [=x= =y=] e: end 
				=keep-x= =keep-y= keep (to word! `"*((offset? s e) / 2)"`)
			]
		|	(clear alt) collect after alt [
				s: =set-x= =set-y= =set-z=						;-- (typeX typeY typeZ) xN patterns
				min-group max-group [=x= =y= =z=] e: end
				=keep-x= =keep-y= =keep-z= keep (to word! `"*((offset? s e) / 3)"`)
			]
		] [return copy alt]
		
	]
	
	mold: function [
		[no-trace]
		{Returns a source format string representation of a value}
		value [any-type!]
		/only "Exclude outer brackets if value is a block" 
		/all  "Return value deeply expanded and in loadable format" 
		/flat "Exclude all indentation and produce compact output (unless /all is given)"
		/part "Limit the length of the result" 
			limit: (pick [100'000'000  10'000] all) [integer!] (limit >= 0)
	][
		line: output: tail first buffer: [{}]					;-- shared buffer to avoid allocations during nested calls
		full?: no												;-- flag to detect the need for ellipsis
		; limit': limit											;-- remember the initial limit before it changes
		indent: either flat [-2'000'000'000][0]					;-- negative indent replaces the 'flat' flag
		stack:  make hash! 4
		; if 'full = catch [mold-internal :value indent stack only all] [full?: yes]
		catch [mold-internal :value indent stack only all]
		output: either (length? output) > 262'144 [				;-- buffer became too long to keep it
			buffer/1: make string! 32
			output
		][
			; copy&clear output
			also copy output clear output
		]
		;@@ close the stack
		; if full? [
			; dots: min 3 length? output
			; append/part clear skip tail output negate dots "..." dots
		; ]
		; ellipsize output limit'
		; output
	]
	
	with-limit: function [size [integer! none!] code [block!] /extern limit full?] with :mold [
		either size [
			limit: allowed: min size saved-limit: limit
			if 'full = catch [do code] [full?: yes]
			limit: saved-limit - used: allowed - limit
			if full? [
				clear skip tail output negate dots: min 3 allowed
				append/part output "..." dots					;-- ensure dots themselves don't exceed the limit
				full?: no
			]
		] code
	]
	
	mold-internal: function [
		[no-trace] "(Internal)"
		data   [any-type!] "Value to mold"
		indent [integer!]  "Current indentation level (may not align with depth)"
		stack  [hash!]     "Nested visited structures (to avoid deadlocks and track depth)"
		only*  [logic!]
		all*   [logic!]
		/local vtype
	] reshape [
		type:        type?/word :data
		depth:       length? stack
		if compact?: all [not all*  depth > 0] [indent: -2'000'000'000]	;-- flatten in compact mode
		markers:     select (pick self/markers all*) type
		set [start: sep: end:] markers
		if all [only*  type = 'block!] [start: end: none]
		lf-enabled?: all [indent >= 0  sep = " "]
		
		; ??* stack
		if found: find/only/same stack :data [					;-- prevent cycles, indicate the nesting depth
			emit [start ".."]
			loop length? next found [emit "/.."]
			emit end
			exit
		]
		
		switch/default type [
			map! @(to block! any-object!) event! [				;-- dictionary types
				append/only stack data
				
				if type = 'event! [
					data: make map! 10
					foreach word system/catalog/accessors/event! [	;@@ use map-each
						map/:word: :data/:word
					]
					data: map
				]
				
				case [
					all [compact?  is-space? data] [			;-- shorten spaces to just type:size
						size: attempt [to pair! data/frames/last/size] 
						emit `"(select data 'type):(size)"`
					]
					all [compact?  face? data] [
						either :data/type = 'rich-text [		;-- shorten rich-text object to just text
							mold-native :data/text
						][
							size: attempt [to pair! data/size]	;-- convert point to pair
							emit `"(select data 'type):(size)"`
						]
					]
					all [compact?  type = 'object!  (class-of font!) = class-of data] [
						mold-native :data/name					;-- only show the font name
					]
					'else [
						emit start
						; body: to block! data					;@@ can't work on the body because of #5140
						keys: keys-of data
						
						if all [
							type = 'object!
							not all*
						] [keys: exclude keys [on-change* on-deep-change*]]
						
						forall keys [							;@@ use map-each
							if word? :keys/1 [keys/1: to set-word! keys/1]
						]
						
						align: 0
						unless any [indent < 0  500 <= length? keys] [	;-- don't try aligning system/words or in flat mode
							foreach key keys [					;@@ use maximum-of map-each
								align: max align length? mold* key
							]    
							align: min align 32
						]
						
						unless tail? keys [
							with-limit if compact? [available-width - align - 1] [
								indent: indent + 4
								emit "^/"
								emit [pad mold* :keys/1 align  " "]
								mold-value select/case data :keys/1	;-- use 'select' as maps are case sensitive, paths aren't
								pair-sep: either lf-enabled? ["^/"][" "]
								foreach key next keys [
									emit pair-sep
									emit [pad mold* :key align  " "]
									mold-value select/case data :key
								]
								indent: indent - 4				;-- unindent before(!) the possible line feed
								emit "^/"
							]
						]
						emit end
					]
				]
				
				take/last stack
			]
			
			@(to block! any-block!) [
				append/only stack head data

				skip-close: emit-skip?							;-- dump the full series in /all mode
				emit start
				
				if all [compact? any-list? data] [
					data: any [compress-list data  data]		;-- try reducing the output
				]
				
				unless tail? data [								;-- empty lists have no newline markers either in them
					edge-sep: all [any-list? data  new-line? data  "^/"]	;-- no new-line for paths
					if edge-sep [indent: indent + 4  emit edge-sep]
					mold-value :data/1
					data: next data
					forall data [								;@@ use map-each
						lf?: all [lf-enabled?  new-line? data]
						emit either lf? ["^/"][sep]
						mold-value :data/1
					]
					if edge-sep [indent: indent - 4  emit edge-sep]
				]
				
				emit [end skip-close]
				take/last stack
			]
			
			@(to block! any-string!) [
				skip-close: emit-skip?							;-- dump the full series in /all mode
				with-limit if compact? [available-width] [mold-native data]
				emit skip-close
			]
			
			vector! image! [
				skip-close: emit-skip?							;-- dump the full series in /all mode
				with-limit if compact? [available-width] [
					either image? data [
						either compact? [
							emit [start mold* data/size " ..." end]
						][
							emit [
								start mold* data/size " "
								mold-native data/rgb " "
								mold-native data/alpha end
							]
						]
					][
						string: apply 'mold* [data /flat indent < 0]
						parse string [
							"make vector! [" opt [copy vtype to "[" skip]
							values: to "]" remove to end
						]
						either compact? [
							length: mold* length? data
							emit [start vtype length end]
						][
							emit either vtype
								[[start vtype "[" values "]" end]]
								[[start values end]]
						]
					]
				]
				emit skip-close
			] 
			
			point2D! point3D! [									;-- boost readability of points
				unless all* [
					prec: to get type 0.01
					dim:  pick [2 3] type = 'point2D!
					repeat i dim [if (abs data/:i) > 1 [prec/:i: 0.1]]
					data: round/to data prec
				]
				mold-native data
			]
			
			unset! [emit either all* ["#(unset)"]["unset"]]		;@@ fix for #5559
			
			@(to block! any-function!) [
				append/only stack :data
				case [
					name: select/same/skip natives :data 2 [
						name: mold* to get-word! name			;@@ add system/words/ prefix?
						emit either all* [["##[" name "]"]][name] 
					]
					compact? [
						emit start
						mold-value compact-spec :data clear []
						emit either integer? body-of :data ["[...]"][mold*/flat/part body-of :data 40]
						emit end
					]
					all* [
						emit start
						mold-value spec-of :data
						either integer? body-of :data [emit "[...]"][mold-value body-of :data]
						emit end
					]
					'else [mold-native :data]					;@@ replace native with my own?
				]
				take/last stack
			]
			
			handle! [											;-- make handles loadable by converting to integers
				data: second transcode/one next mold*/all data	;-- extract the integer
				emit `"(to-hex value)h"`						;-- convert to hex
			]
		][
			;; simple values - dispatch into the native mold
			mold-native :data
		]
	]
	
	;; shortcuts that pass all the refinements
	mold-native: function [data [any-type!]] with [:mold :mold-internal] [
		string: add-indent apply 'mold* [:data /all all* /flat indent < 0 /part on limit + 1] indent
		emit ellipsize string limit								;@@ ellipsization of molded output is a tradeoff - may not be desired
	]
	mold-value: function [data [any-type!]] with :mold-internal [
		mold-internal :data indent stack false all*				;-- /only should never reapply to deeper levels
	]
	
	available-width: does with [:mold :mold-internal] [
		max 0 terminal-width - (length? line) - length? any [skip-close {}]
	]
	
	emit-skip?: function [/extern data] with :mold-internal reshape [
		if all [all* not head? data] [							;-- dump the full series in /all mode
			emit switch/default type [
				paren! @(any-path!) ["##[skip quote "]			;-- active values have to be quoted :(
			] ["##[skip "]
			return also `" (-1 + index? data)]"` data: head data
		]
	]
	
	;; to keep all to string conversions explicit
	;; in a block all expressions should evaluate to strings
	;; (except integer which is used as indentation)
	; emit: function [
		; "(internal emitter for 'mold-internal')"
		; string [block! string! integer! none!] /extern limit line full?
	; ] with [:mold :mold-internal] [
		; switch type?/word string [
			; block!  [
				; while [not tail? string] [
					; emit do/next string 'string
				; ]
			; ]
			; string! [
				; either string = "^/" [
					; if indent >= 0 [							;-- ignore it in flat mode
						; emit-append/part string limit 
						; line: tail output
						; emit-append/dup #" " min limit': limit indent	;-- auto-indent after line feed
						; if limit' < indent [throw 'full] 
					; ]
				; ][
					; emit-append/part string limit': limit
					; if limit' < length? string [throw 'full]	;-- deep early exit when out of limit
				; ]
			; ]
			; integer! [
				; if string <= 0 [exit]
				; emit-append/dup #" " min limit': limit string
				; if limit' < string [throw 'full]
			; ]
			; none! []											;-- does nothing by design
		; ]
	; ]
	emit: function [
		"(internal emitter for 'mold-internal')"
		string [block! string! integer! none!]
	] []														;-- 'none' does nothing by design
	overload :emit [string [block!]] with [:mold :mold-internal] [
		while [not tail? string] [
			emit do/next string 'string
		]
	]
	overload :emit [string [string!] /extern line] with [:mold :mold-internal] [
		either string = "^/" [
			if indent >= 0 [									;-- ignore it in flat mode
				emit-append/part string limit 
				line: tail output
				emit-append/dup #" " min limit': limit indent	;-- auto-indent after line feed
				if limit' < indent [throw 'full] 
			]
		][
			emit-append/part string limit': limit
			if limit' < length? string [throw 'full]			;-- deep early exit when out of limit
		]
	]
	overload :emit [string [integer!]] with [:mold :mold-internal] [
		if string <= 0 [exit]
		emit-append/dup #" " min limit': limit string
		if limit' < string [throw 'full]
	]
	
	emit-append: function [
		"(internal append wrapper for 'emit')"
		value /part part' /dup dup' /extern limit
	] with [:mold :mold-internal] [
		append/:part/:dup output :value part' dup'
		limit: max 0 limit - any [dup' length? :value]
	]
	
	return :mold
]


#hide [#assert [
	;; simple values
	"0"						= mold 0
	"none"					= mold none
	"false"					= mold no
	"unset"					= mold ()
	; "fal"					= mold/part no 3
	"..."					= mold/part no 3
	".."					= mold/part no 2
	""						= mold/part no 0
	"#(false)"				= mold/all no
	"#(none)"				= mold/all none
	"#(unset)"				= mold/all ()
	"(1.2, 6.8)"			= mold     (1.2345, 6.789)
	"(1.2345, 6.789)"		= mold/all (1.2345, 6.789)
	"(1.2, 6.8, 0.12)"		= mold     (1.2345, 6.789, 0.1234)
	
	;; strings
	{"abc"}					= mold "abc"
	{ab@c}					= mold ab@c
	{%"a b"}				= mold %"a b"
	{"^^/{abc}^^/"}			= mold {^/{abc}^/}
	{##[skip "abc" 1]}		= mold/all next "abc"
	{##[skip quote (a b c) 1]}	= mold/all next quote (a b c)
	
	;; lists
	"[1 + 2]"				= mold [1 + 2]
	"1 + 2"					= mold/only [1 + 2]
	"[^/    1^/    +^/    2^/]" = mold new-line/all [1 + 2] on
	"[a/b/c: :d/e/f]"		= mold [a/b/c: :d/e/f]
	
	;-- lists compacted at depth > 0
	(b: append/dup copy [] 1 100)
	"[[1 *100]]"			= mold reduce [b]
	
	(b: copy []  repeat i 100 [append b i])
	"[[integer! *100]]"		= mold reduce [b]
	
	(b: copy []  repeat i 50 [repend b [i 'x]])
	"[[integer! x *50]]" = mold reduce [b]
	
	(b: copy []  repeat i 50 [repend b [i random/only [x y z]]])
	"[hash [integer! word! *50]]" = mold reduce [to hash! b]
	
	(b: copy []  repeat i 30 [repend b [10 i random/only [x y z]]])
	"[hash [10 integer! word! *30]]" = mold reduce [to hash! b]
	
	"[:to]"												= mold reduce [:to]
	"[##[:to]]"											= mold/all reduce [:to]
	"[##[:*]]"											= mold/all reduce [:*]
	
	"[func [s][pick s 1]]"								= mold reduce [:first]
	{[^/    ##[func [^/        "Return but don't evaluate the next value"^/        :value [any-type!]^/    ][^/        :value^/    ]]^/]}
														= mold/all new-line/all reduce [:quote] on
														
	"vector [1 2 3]"									= mold make vector! [1 2 3]
	"vector [1.2 3.4]"									= mold make vector! [1.2 3.4]
	"vector [float! 32 [1.2 3.4]]"						= mold make vector! [float! 32 [1.2 3.4]]
	"[image [10x10 ...]]"								= mold reduce [make image! 10x10]
	find/match mold/flat make image! 10x10 "image [10x10 #{FF"

	;; dictionaries
	{#[^/    xxx: 1^/    2    3^/]}						= mold #[xxx 1 2 3]
	{object [^/    xxx: 1^/    y:   2^/]}				= mold object [xxx: 1 y: 2]
	{[object [x: 1] object [y: 2]]}						= mold reduce [object [x: 1] object [y: 2]]	;-- flattened in the block
	{[#[x: 1] #[2 3]]}									= mold reduce [#[x 1] #[2 3]]				;-- flattened in the block
	{[##[make map! [^/    x: 1^/]] ##[make map! [^/    2 3^/]]]} = mold/all reduce [#[x 1] #[2 3]]
	{["Verdana"]}										= mold reduce [make font! [name: "Verdana"]]
	{["Rich Text"]}										= mold reduce [make face! [type: 'rich-text text: "Rich Text"]]
	{[base:10x10]}										= mold reduce [make face! [type: 'base size: (10,10)]]
	
	;; parent references
	"[[..]]"											= mold append/only b: copy [] b
	"[[..] 1]"											= mold append append/only b: copy [] b 1
	"[[1 [../..] 2]]"									= mold append/only b: copy [] reduce [1 b 2]
	"object [o: object [..]]"							= mold/flat object [o: self]
	"object [o: object [..] p: object [q: object [../..]]]" = mold/flat object [o: self p: object [q: o]]
	{object [^/    o: object [..]^/]}					= mold object [o: self]
	{object [^/    o: object [..]^/    p: object [q: object [../..]]^/]}		;-- 'p' is flattened
														= mold object [o: self p: object [q: o]]
	;; not valid but idk what's a better option:
	{##[construct/only [^/    o: ##[construct/only [..]]^/    p: ##[construct/only [^/        q: ##[construct/only [../..]]^/    ]]^/]]}
														= mold/all object [o: self p: object [q: o]]
]]

; print mold system quit
