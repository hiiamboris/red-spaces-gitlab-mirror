Red [
	title:    "VID layout support for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.vid
	depends:  [
		spaces.macros spaces.auxi spaces.templates spaces.rendering
		global with error reshape bind-only advanced-function classy-object
	]
]


;@@ use tag for hint? (makes sense if hint is widely used)

VID: classy-object [
	"VID/S dialect"
	
	common: none
	styles: #[]				#type [map!] "Known VID/S styles collection"
	
	init-spaces-tree: none
	lay-out-vids:     none
	
	;; these are helpers for VID/S and new styles to do common things:
	add-flag:         none
	add-actor:        none
	set-facet:        none
	set-color:        none
	set-limits:       none
	
	dialect:          none
	
	focus: classy-object [
		"(internal focus tracking facilities)"
		track: update: none
	]
]	

VID/common: classy-object [
	"Templating shortcuts to avoid repetition"
	
	;; for inclusion into style /spec:
	spec: #[
		spacious [margin: spacing: 10x10]
	]
	
	;; for inclusion into style /facets:
	facets: #[
		tight    [tight [margin: spacing: 0x0]]
		align [											;-- used by box and tube
			left   [align/x: -1]
			right  [align/x:  1]
			center [align/x:  0]
			top    [align/y: -1]
			bottom [align/y:  1]
			middle [align/y:  0]
		]
		text-align [									;-- used by rich-paragraph and co
			left   [align: 'left]
			center [align: 'center]
			right  [align: 'right]
			fill   [align: 'fill]
		]
		font-styles [
			bold      [add-flag self 'bold]
			italic    [add-flag self 'italic]
			underline [add-flag self 'underline]
			strike    [add-flag self 'strike]
			;; no 'ellipsize' flag as it's not a font flag, but a text-specific addition
			;; no 'wrap' flag as it is now controlled by the canvas
		]
	]
]
		
;; used internally in host's `init` only
VID/init-spaces-tree: function [
	"Construct VID/S layout from the host's default actor"
	host [object!] (host? host)
	/local focused
][
	swap 'spec 'host/actors/worst-actor-ever
	#assert [function? :spec]
	if empty? spec: body-of :spec [spec: [space]]				;-- default host to an empty space, so /space is always assigned
	focused: VID/focus/track [pane: lay-out-vids spec]
	if 1 < n: length? pane [ERROR "Host face can only contain a single space, given (n)"]
	host/space: pane/1
	canvas: make rendering/canvas! compose [size: (host/size) x: fill y: fill]
	drawn:  rendering/render-host host canvas					;-- render-host auto-assigns host/draw & host/size
	#debug draw [#print ["host (host/size) /draw: (mold drawn)"]] 
	if focused [set-focus focused]
]
	
;; focus is tricky! lay-out-vids should never change focus, because its result may never be part of the tree
;; but it has to return the pane, so focused space becomes its extra return
;; also REP 172 is tightly involved, requiring focus target to be connected to the screen at the time of focusing
VID/focus/track: function [
	"Wrapper for layout functions that returns the last space with focus marker (or none)"
	code [block!] "Evaluated"
	/local focused
][
	do code
	:focused
]

VID/focus/update: func [
	"Update focus target within the VID/S subtree"
	space [object!]
] with :VID/focus/track [
	try [focused: space]										;-- may fail when called outside of focus/track scope
]

VID/add-flag: function [
	"Add a FLAG to SPACE's /config, copying it in the process"	;-- copying is required to avoid modifying the shared config
	space [object!]
	flag  [word!]
][
	space/config: copy/deep space/config						;@@ fix /owners
	append space/config/flags flag
]
	
VID/add-actor: function [
	"Add an ACTOR to SPACE's /config, copying it in the process"	;-- copying is required to avoid modifying the shared config
	space   [object!]
	on-type [word!]   (find/match form on-type "on-")
	code    [block! function!]
][
	space/config: either select space/config 'actors
		[copy/deep space/config]								;@@ fix /owners
		[make copy/deep space/config [actors: copy #[]]]
	if block? :code [code: function [event [map!]] code]
	space/config/actors/:on-type :code
]
	
VID/set-facet: function [
	"Set FACET in the SPACE to VALUE"
	space [object!]
	facet [word! path!] "All containers in the path are copied"	;-- copying is required to avoid modifying the shared container
	value [default!]
][
	if path? facet [
		foreach item topless facet [							;@@ use for-each [item | facet]
			#assert [container? space/:item  "facet path elements must be containers"]
			space: space/:item: copy space/:item
		]
		facet: last facet
	]
	space/:facet: :value
]
	
VID/set-color: function [
	"Set COLOR in SPACE's /config, copying it in the process"
	space [object!]
	color [tuple!]
][
	#assert [in space/config 'color  "color is not supported by the selected template"]	;@@ or force-add it?
	VID/set-facet 'config/color color
]
	
VID/set-limits: function [
	"Set LIMITS in SPACE's /config, copying it in the process"
	space  [object!]
	limits [map!] "A range! value"
][
	;@@ maybe limits should always be in config?
	space/config: remake copy/deep space/config [limits: (limits)]	;@@ fix /owners
]
	
	
	; wrap-value: function [
		; "Create a space to represent given VALUE; return it's name"
		; value [any-type!]
		; wrap  [logic!] "How to lay text out: as a line (false) or paragraph (true)"
	; ][ 
		; either space? :value [							;-- pass spaces as is - common case for list-view/grid-view
			; :value
		; ][
			; make-space 'text [text: mold :value]
		; ]
	; ]
	; overload :wrap-value [value [string!]] [make-space pick [paragraph text] wrap [text: value]]
	; overload :wrap-value [value [logic!]]  [make-space 'logic [state: value]]
	; overload :wrap-value [value [image!]]  [make-space 'image [data:  value]]
	; overload :wrap-value [value [url!]]    [make-space 'link  [text:  value]]
	; overload :wrap-value [value [block!]]  [lay-out-data/:wrap value]
	
	
	; lay-out-data: function [
		; "Create a space layout out of DATA block"
		; data [block!] "image, logic, url get special treatment"
		; /only "Return only the spaces list, do not create a layout"
		; /wrap "How to lay text out: as a line (false) or paragraph (true)"
	; ][
		; result: map-each value data [wrap-value :value wrap]
		; unless only [
			; result: make-space 'tube [
				; margin:  0x0							;-- outer space most likely has it's own margin
				; spacing: 10x10
				; content: result
			; ]
		; ]
		; result
	; ]
	
	
	; lay-out-grid: function [
		; "Turn Grid specification block into a code block"
		; spec [block!] "Same as VID/S, with `as pair!` / `as range!` support"
		; /styles sheet [map! none!] "Add custom stylesheet to the global one"
		; /local x
	; ][
		; code: make block! 20
		; xy:   1x1
		; step: 1x0
		
		; =at-expr=: [s: e: (set/any 'x do/next s 'e) :e]
		; =at=: [
			; ahead word! 'at =at-expr=
			; (case [
				; pair? :x [xy: x]
				; all [range? :x  pair? x/min  pair? x/max] [
					; repend code ['set-span  xy: x/min  x/max + 1 - xy]
				; ]
				; 'else [ERROR "Expected pair or range of pairs after 'at' keyword, got (type? :x) at (mold/part s 100)"]
			; ])
		; ]
		; =batch=: [
			; opt =at=
			; s: to [ahead word! ['at | 'return | 'across | 'below] | end] e: (	;-- lay out part between keywords
				; spaces: lay-out-vids/styles copy/part s e sheet
				; foreach space spaces [
					; repend code ['put 'content xy space]
					; xy: xy + step
				; ]
			; )
		; ]
		; =return=: [ahead word! 'return (xy: 1 + multiply xy reverse step)]
		; =across=: [ahead word! 'across (step: 1x0)]
		; =below=:  [ahead word! 'below  (step: 0x1)]
		; parse spec [any [=return= | =across= | =below= | =batch=]]
		; code
	; ]
	

global VID/lay-out-vids: function [
	"Turn VID/S specification block into a forest of spaces"
	spec    [block!] "See VID/S manual on syntax" 
	/styles sheet: (copy #[]) [map!] "Add custom stylesheet to the global one"
	return: [block!] "One or more top-level spaces"
][
	sheet: extend copy/deep VID/styles sheet
	VID/dialect/build-pane VID/dialect/parse-pane spec sheet
]

VID/dialect: classy-object [
	"(internal VID/S parsing support facilities)"
	
	datatype-names: to hash! any-type!							;-- used to screen datatypes from flags
	actor-names:    to hash! extract next system/view/evt-names 2
	active!:        make typeset! [any-word! any-path! paren! any-function!]	;-- what values to quote in /init
	
	;; note: both parse-style and parse-pane are indirectly tied to lay-out-vids, because rules are using the stylesheet
	;; this function is separated to have stack-like context for 'p', 'x', data
	parse-entry: function [
		"Read a VID/S style definition from POS, setting POS' to the tail of it"
		original [block!]  "Original rule at its head"
		pos      [block!]  "Expanded rule at current position"
		pos'     [word!]   "Word to set to the next position in the expanded rule"
		return:  [object!] "A newly built tree of spaces"
		/local p x												;-- used by the rules
	][
		data: copy/deep #[										;-- data collected from VID/S block in a single entry
			label:	#(none)										;-- set-word to assign to a space or style
			name:	#(none)										;-- word referring to the template or style name
			style:	#(none)										;-- style going by that name or auto-generated from template
			pane:	#(none)										;-- children spaces
			init:	[]											;-- code for make-space, initialized from style
		]
		parse pos with rules [
			p: [style-declaration (data: []) | style-instantiation]
			pos: (set pos' pos)
		]
		data
	]
	
	parse-pane: function [
		"Turn all VID/S style definitions in the PANE into space objects"
		pane    [block!]      "A VID/S block"
		sheet   [map! block!] "Style sheet to look up styles in"
		return: [block!]      "A forest of spaces"
		/local p'												;-- used by the rules
	][
		parse pos: copy pane rules/expand-links					;-- expansion modifies the copied pane
		if block? sheet [sheet: make map! sheet]
		collect [while [not tail? pos] [keep parse-entry pane pos 'pos]]
	]
	
	store-style: function [
		"Store a new style in the SHEET"
		sheet [map!]
		data  [map!] "Collected style data" (word? data/label)
	][
		;; style block is freeform, so we don't know if it has /init or /pane, and don't want to add any,
		;; both to keep sheet human-readable and to avoid confusing e.g. pane=[] with pane=none
		if            data/pane [data/style/pane: compose [(only data/style/pane) (data/pane)]]
		unless empty? data/init [data/style/init: compose [(only data/style/init) (data/init)]]
		sheet/(data/label): data/style
	]
	
	build-style: function [
		"Turn collected style DATA into a space object"
		data    [map!]
		return: [object!]
	][
		#assert [word? :data/style/template]
		space: make-space data/style/template compose [(only data/style/init) (data/init)]
		if data/label [set data/label space]
		if data/pane [
			pane: parse-pane data/pane
			switch/default type?/word :space/content [
				block! [space/content: parse-pane data/pane]
				none!  [
					pane: parse-pane data/pane
					if (length? pane) > 1 [ERROR "Style (data/name) can only have a single child"]
					space/content: pane/1						;-- pane/1 may still be none
				]
			] [ERROR "Style (data/name) cannot have children"]
		]
		data/space: space
	]
	
	build-pane: function [
		"Turn parsed VID/S style data into space objects"
		pane    [block!] (parse pane [any map!])
		return: [block!]
	][
		collect [foreach data pane [keep build-style data]]		;@@ use map-each
	]
	
	get-style: function [
		"Get a style from the style SHEET by its NAME, otherwise create a minimal style"
		sheet   [map!]
		name    [word!]
		return: [map!]
	][
		any [
			if :sheet/:name [
				#assert [any [map? :sheet/:name block? :sheet/:name]]
				style: make map! copy/deep sheet/:name			;-- composing maps is tricky so styles are allowed to be just blocks
				if block? style/facets [style/facets: make map! style/facets]
				style
			]
			if templates/:name [make map! compose [template: (name)]]
			ERROR "Unknown VID/S style (name)"
		]
	]
	
	;@@ this code is a good showcase on how awkward Parse is when you need to extract values from the data - make a REP?
	rules: [
		"Rules for style parsing"
		
		~~p: none												;-- used by #expect
		p:   none												;-- used by rules
		<<:  make op! :compose-after
		
		expected: function [
			"(internal) wrapper for 'expected' that forwards errors to the original series"
			where [block!]
			token [default!]
		] bind-only [
			spaces/ctx/expected at original index? where :token
		] bind 'original :parse-entry
		
		known-style?: function [
			"(internal) look up style name in style sheet then templates list"
			name [word!]
		][
			any [sheet/:name templates/:name]
		]
	
		quote?: function [
			"(internal) return 'quote if value doesn't evaluate to itself"
			value [any-type!]
		][
			when find active! type? :value 'quote
		]
	
		set-auto-facet: function [
			"(internal) automatically assign style's facet value from given block position"
			pos     [word!]  "Advanced to point after the consumed values"
			return: [logic!] "True if a matching facet found"
		][
			unless facets: data/style/facets [return false]
			fail: [ERROR "Facet '(facet)' in style '(data/name)' must be a word or function, not (type)"]
			value: first source: get pos
			result: case [
				all [											;-- word -> code block or function
					target: :facets/:value
					word? :value								;-- tip: datatype word is handled before auto-facet, so only other words are here
				][
					switch/default type: type?/word :target [
						block!    [append data/init copy/deep target]
						function! [
							arity:  preprocessor/func-arity? spec-of :target
							call:   copy/part source 1 + arity
							call/1: 'target
							code:   do interleave/between call 'quote
							#assert [block? :code  "facet function must return a block"]
							append data/init code
							source: skip source arity
						]
					] fail
				]
				target: select facets facet: type?/word :value [	;-- any-type -> word or unary function
					switch/default type: type?/word :target [
						function! [append data/init (target :value)]
						word!     [append data/init compose [(to set-word! target) (quote? :value) (:value)]]
					] fail
				]
				'else [return false]
			]
			set pos next source 
			true
		]
		
		is-manual-facet: function [
			"(internal) test if word or path is a manual facet assignment"
			facet   [word! path!]
			return: [none! word! path!] "Facet without the trailing `=` or none"
		][
			switch type?/word facet [
				word! [
					if #"=" = take/last word: form facet [
						to word! word
					]
				]
				path! [
					if #"=" = take/last word: form last facet [
						as path! compose [(as block! topless facet) (to word! word)]
					]
				]
			]
		]
		
		set-manual-facet: function [
			"(internal) assign to space's FACET a given VALUE"
			facet [word! path!]
			value [default!]
		][
			;; by design, word= adds a new facet to space, while some/path= doesn't add it
			append data/init compose switch type?/word facet [
				word! [[ (to set-word! facet) (quote? :value) (:value) ]]
				path! [[ VID/set-facet self (as lit-path! facet) (quote? :value) (:value) ]]
			]
		]
		
		;; performs global preprocessing of the VID/S block to support fetching values by their reference/code
		expand-links: [ahead any [p':
			change only [get-word! | get-path!] (get p'/1)
		|	change only paren! (do p'/1)
		|	change only url! (load p'/1)
		|	skip
		]]
		
		;; collects into the 'data' map: spec block, init block, label word/path, name word, pane block
		; style-entry:         [p: any style-declaration style-instantiation]
		style-declaration:   [ahead word! 'style #expect label-word style-description (store-style sheet data)]
		style-instantiation: [opt [label-word | label-path] style-description]
		style-description:   [#expect style-name any [tail | style-modifier]]
		style-name:          [p: word! if (known-style? p/1) (data/style: get-style sheet data/name: p/1)]
		label-word:          [p: set-word! (data/label: to word! p/1)]
		label-path:          [p: set-path! (data/label: to path! p/1)]
		style-modifier: [
			;; keywords take priority:
			p: ahead word! [
				with-block
			|	react-block
			|	actor-block
			|	focus-flag
			]
			;; then decorated words:
		|	facet-manual
			;; 'reserved' helps avoid consuming e.g. 'style' or 'text' when a color or size is assigned to that word:
			;; (affects exactly: facet-auto, word-color, word-size)
		|	not reserved [
				;; then specific flags and datatypes:
				facet-auto
				;; then generic handling of datatypes:
			|	subtree
			|	size
			|	color
			]
		]
		
		; keyword:      [ahead word! ['style | 'focus | 'with | 'react | actor-name | template-name]]
		reserved:     [word! if (any [p/1 = 'style known-style? p/1])]
		
		with-block:   ['with #expect block! (append data/init p/2)]
		
		react-block:  ['react #expect block! (append/part data/init p 2)]
		
		actor-block:  [actor-name #expect actor-body (data/init << [VID/add-actor self (to lit-word! p/1) quote (:x)])]
		actor-name:   [word! if (find actor-names p/1)]
		actor-body:   [set x [block! | function!] | ahead word! 'function 2 block! [x: function p/3 p/4]]
		
		focus-flag:   ['focus (data/init << [VID/focus/update self])]
		
		facet-manual: [[word! | path!] if (x: is-manual-facet p/1) #expect facet-value (set-manual-facet x :p/2)]
		facet-value:  [skip]									;-- named for the sake of error reporting only
		
		facet-auto:   [skip if (set-auto-facet 'p) :p]
		
		subtree:      [block! if (not data/pane) (data/pane: copy p/1)]	;-- don't accept 2 or more subtrees; stored unprocessed!
		
		size:         [p: [fixed-size | range-size | word-size] (data/init << [VID/set-limits self (x)])]	;@@ what if space has a VID: facet?
		fixed-size:   [planar! (x: p/1 .. p/1)]
		range-size:   [map! if (range? x: p/1)]
		word-size:    [word! if (case [range? x: get-safe p/1 [x] planar? :x [x .. x]])]
		
		color:        [p: [tuple-color | hex-color | word-color] (data/init << [VID/set-color self (x)])]
		tuple-color:  [tuple! (x: p/1)]
		hex-color:    [issue! (x: hex-to-rgb p/1)]
		word-color:   [word! if (tuple? x: get-safe p/1)]
	]
	
	;; rules have access to 'sheet' and 'data', and minute variables ~~p, p, x
	;; `~~p` can safely be shared, `x` can be currently but not future-proof to share
	;; and `p` must be made local to the style as facet-auto may evaluate arbitrary code and reenter the parser
	rules: classy-object bind-only rules compose [
		(bind [sheet p'] :parse-pane)							;-- sheet is collected within a pane, copied in a subpane
		(bind [data p x] :parse-entry)							;-- data is local to a single style entry
	]
]

#hide [#assert [
	parse-pane: :VID/dialect/parse-pane
	[] = parse-pane [] #[]
	(parse-pane [space] #[]) = [#[label: #(none) name: space style: #[template: space] pane: #(none) init: []]]
	
	extra: make map! reshape [
		test: [
			template: space
			init:     [num-facet: 0]
			facets:   [
				flag     [flag-facet: on]
				string!  text-facet
				integer! @(func [i][compose [num-facet: (i)]])
				param    @(func [x][compose [any-facet: (x)]])
			]
		]
	]
	pane: parse-pane [test] extra
	single? pane
	pane/1/label = none
	pane/1/pane  = none
	pane/1/init  = []											;-- style/init isn't inserted here
	pane/1/style/init = [num-facet: 0]
	
	2 = length? pane: parse-pane [test test] extra
	pane/1 = pane/2
	
	pane: parse-pane [test test= ('test) deep/facet= :pi] extra
	single? pane
	pane/1/init = reshape [
		test: quote test
		VID/set-facet self 'deep/facet @[pi]
	]
	
	pane: parse-pane [test test= style] extra					;-- shouldn't take style for a keyword
	single? pane
	pane/1/init = [test: quote style]
	
	pane: parse-pane [test "abc" ('flag) with [a: 'b] (1 + 2) param 1.23] extra
	single? pane
	pane/1/init = [												;-- facets should be ordered
		text-facet: "abc"
		flag-facet: on
		a: 'b
		num-facet: 3
		any-facet: 1.23
    ]
	
	pane: parse-pane [style test1: test 5 test1] extra
	single? pane
	pane/1/label = none											;-- style label shouldn't be carried over to the space
	pane/1/name  = 'test1
	pane/1/init  = []											;-- style init shouldn't contaminate space/init
	
	pane: parse-pane [
		style test: test 4
		style test: test 5										;-- self-references shouldn't deadlock it
		test: test [test] "10"									;-- last test is an instantiation
	] extra
	single? pane
	pane/1/label = 'test
	pane/1/name  = 'test
	pane/1/pane  = [test]
	pane/1/init  = [text-facet: "10"]
	pane/1/style/init = [
		num-facet: 0
		num-facet: 4
		num-facet: 5
	]
	
	test: style: 'hacked
	pane: parse-pane [style test: test test] extra				;-- external words shouldn't affect VID/S behavior
	single? pane
	
	error? try [parse-pane [nonexistent-word] extra]
	error? try [parse-pane [test nonexistent-word] extra]
]]
	
