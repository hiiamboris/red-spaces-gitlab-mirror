Red [
	title:    "VID layout support for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.vid
	depends:  [
		spaces.macros spaces.auxi spaces.templates
		global with error quietly map-each advanced-function collect-set-words
	]
]


;@@ use tag for hint? (makes sense if hint is widely used)

VID: classy-object [
	"VID/S dialect"
	
	common: none
	styles: #[]				#type [map!] "Known VID/S styles collection"
	
	init-spaces-tree: none
	lay-out-vids:     none
	
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
			bold      [flags: append flags 'bold]
			italic    [flags: append flags 'italic]
			underline [flags: append flags 'underline]
			strike    [flags: append flags 'strike]
			ellipsize [flags: append flags 'ellipsize]
			; wrap      [flags: append flags 'wrap]		;-- no wrap flag by design, choose text vs paragraph instead 
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
	canvas: make rendering/canvas! compose [size: (host/size) mode: fill axis: xy]
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
	try [focused: space]										;-- may fail when called outside of track-focus scope
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
	
datatype-names: to block! any-type!						;-- used to screen datatypes from flags

;@@ can this func be split apart?
global VID/lay-out-vids: function [
	"Turn VID/S specification block into a forest of spaces"
	spec [block!] "See VID/S manual on syntax" 
	/styles sheet [map! none!] "Add custom stylesheet to the global one"
	/local w b x lo hi late?
	/extern with										;-- gets collected from `def`
] with VID [
	pane: make block! 8
	sheet: any [sheet make map! 4]						;-- new sheet should not persist after leaving lay-out-vids 
	def: construct [									;-- accumulated single style definition
		styling?:												;-- used when defining a new style in VID
		template: 												;-- should not end in `=` (but not checked)
		with:													;-- used to build space, before all other modifiers applied
		link: 													;-- prefix set-word, will be set to the instantiated space object
		style: 													;-- style spec fetched from VID/styles
		reactions:												;-- bound to space
		actors:													;-- unlike event handlers, affects individual space only
		facets:													;-- facets collected by manual and auto-facet
		pane:													;-- unless snatched by auto-facet, assigns /content
		focused?:												;-- to move focus into this space
		children:												;-- collects set-words of a style
	]
	
	commit-style: [
		#assert [def/template]
		#assert [def/style/template "template name must be defined in style specification"]
		
		;; may assign non-existing facets like hint= or menu=
		facets: map-each [facet value] def/facets [
			either facet [ reduce [to set-word! facet 'system/words/quote :value] ][ value ]
		]
		unless empty? def/actors [
			append facets compose/deep/only [
				actors: apply 'construct [
					to [] def/actors
					/with object? :actors :actors				;-- allows block! facet to define an actor too
				]
			]
		]
		either def/styling? [									;-- new style defined, def/style already copied and in the sheet
			unless def/style/payload [append def/style [payload: []]] 
			def/style/payload: copy/deep/part style-bgn style-end
			; #print "saved payload (mold def/style/payload) in (def/link) style based on (def/style/template)"
		][
			space-spec: compose [
				(only def/style/spec)
				(compose when def/children [children: (def/children)])
				(facets)
				(def/with)
			]
		
			space: make-space def/style/template space-spec
			if def/link [set def/link space]					;-- set the word before calling reactions
			
			if def/pane [
				unless in space 'content [
					ERROR "Style (def/template) cannot contain other spaces"
				]
				;; allow usage of custom layout function
				either def/style/layout [
					layout: get def/style/layout
					#assert [function? :layout]
					do with space (layout/styles def/pane copy sheet)	;-- copy sheet so inner styles don't modify parent's
				][
					content: lay-out-vids/styles def/pane copy sheet	;-- copy sheet so inner styles don't modify parent's
					space/content: case [						;-- always trigger on-change just in case
						any-list? :space/content [content]
						immediate? :space/content [
							if 1 < n: length? content [
								ERROR "Style (def/template) can only contain a single space, given (n)"
							]
							content/1							;-- can be none if no items
						]
						'else [									;-- e.g. content is a map in grid
							ERROR "Style (def/template) requires custom content filling function"
						]
					]
				]
			]
			if def/focused? [focus/update space]				;-- does not trigger actors/events (until fully drawn)
			
			if object? actors: select space 'actors [
				foreach actor values-of actors [
					;; bind to space and commands but don't unbind locals:
					with [space events/commands :actor] body-of :actor
				]
			]
			; if actor: :def/actors/on-created [actor space none none]	;@@ need this? or need `on-create`?
			
			;; make reactive all spaces that define reactions or have a name
			;@@ this is a kludge for lacking PR #4529, remove me
			;@@ another option would be to make all VID spaces reactive, but this may be slow in generative layouts
			if any [def/link  not empty? def/reactions] [
				quietly space/on-change*: reload-function in space 'on-change*
				insert body-of :space/on-change*
					with [space :space/on-change*] [			;-- newlines are imporant here for mold readability
						system/reactivity/check/only self word
					]
			]
			foreach [later reaction] def/reactions [
				reaction: bind copy/deep reaction space			;@@ should bind to commands too?
				react/:later reaction
			]
			; #print "finished instantiation of (def/template) -> (space/type):(space/size)"
			
			append pane space
		]
	];; commit-style: []
	
	reset: [
		set def none
		def/actors:    make map!   4
		def/facets:    make block! 8
		def/reactions: make block! 2
		def/with:      make block! 8
	]
	=vids=:              [any [end | (do reset) =do= | =styling= | =instantiating=]]
	=styling=:           [
		ahead word! 'style (def/styling?: yes)
		ahead #expect set-word! =space-name=
		=style-declaration=
	]
	=instantiating=:     [not end opt =space-name= =style-declaration=]
	=style-declaration=: [=style-name= style-bgn: any =modifier= style-end: (do commit-style)]
	=space-name=:        [set w set-word! (def/link: to word! w)]
	=style-name=:        [
		set w #expect word! p: (
			; #print "found style (w)..."
			def/template: w
			def/style: case [
				x: sheet/:w      [x]
				x: VID/styles/:w [x]
				templates/:w     [compose/only [template: (w)]]
				'else            [ERROR "Unsupported VID/S style: (w)"]
			]
			#assert [not empty? def/style]
			if def/styling? [
				put sheet def/link def/style: copy/deep def/style	;-- from now on, linked word ends the definition and instantiates
			]
			if payload: def/style/payload [					;-- style has literal data to insert
				def/children: make [] 4						;-- collect names of the children
				;; literally insert anonymized copy of the payload
				;; to avoid set-words collision when a style with set-words inside is instantiated multiple times:
				def/children: construct collect-set-words payload
				insert p with def/children copy/deep payload
				; #print "inserted payload at: (mold/part p 80)"
			]
		)
	]
	
	=modifier=:   [
		not [
			end
		|	ahead word! 'style						;-- style is a keyword and can't be faceted
		|	set-word!								;-- set-words are reserved for space names
		|	set w word! if (any [sheet/:w VID/styles/:w templates/:w])	;-- style names mark the end of modifiers
		]; p: (#print "modifier at: (mold/part p 80)")
		[=with= | =reaction= | =action= | =facet= | =flag= | =auto-facet= | =focus= | =color= | =pane= | =size=]
		; p: (#print "modifier finished at: (mold/part p 80)")
	]
	
	=with=:       [ahead word! 'with  set b #expect block! (append def/with b)]	;-- collects multiple `with` blocks
	=do=:         [ahead word! 'do    set b #expect block! (do b)]
	
	=reaction=:   [ahead word! 'react set late? opt [ahead word! 'later] set b #expect block! (
		unless def/styling? [						;-- will be created during instantiation
			repend def/reactions [late? b]
		]
	)]
	
	=action=:     [=actor-name= =actor-body=]
	=actor-name=: [
		set w word!
		if (all [find/match x: form w "on-" #"=" <> last x])	;-- don't take facet for actor, e.g. on-move=
		;@@ should look the name up in system/view/evt-names?
	]
	=actor-body=: [
		set b block! (def/actors/:w: function [event path] b)
	|	set x [get-word! | get-path!] (
			unless function? get/any x [
				ERROR "(mold x) should refer to a function, not (type? get/any x)"
			]
			;@@ check arity too? (up to 2 args)
			def/actors/:w: get/any x
		)
	|	ahead word! 'function p: #expect [2 block!] (def/actors/:w: function p/1 p/2)
	|	#expect "actor body"
	]
	
	=focus=:      [ahead word! 'focus (def/focused?: yes)]
	
	=facet=:      [=facet-name= =facet-expr=]
	=facet-name=: [
		set w word! if (#"=" = last s: form w) (
			take/last s  append def/facets to word! s
		)
	]
	=facet-expr=: [s: e: (append/only def/facets do/next s 'e) :e]
	
	=flag=: [
		set w word!
		if (facet: get-safe 'def/style/facets/:w)	;-- flag defined for this style?
		if (not find datatype-names w)				;-- datatype names do not count
		(repend def/facets [none facet])
	]
		
	=auto-facet=: [
		set x any-type!								;-- try to match by value type
		if (facet: get-safe 'def/style/facets/(type?/word :x))
		(repend def/facets pick [[none facet :x] [facet :x]] function? :facet) 
	]
	
	;; I decided to make a special case because color is in principle applicable to all templates
	;; and adding it into every VID/S style would be tedious, plus raw templates won't support it otherwise
	;@@ should there be two colors (fg/bg)? (this may complicate styles a lot)
	=color=:      [
		[	set x tuple!
		|	set w word! if (tuple? x: get-safe w)	;-- safe or may have lost context
		|	set w issue! if (x: hex-to-rgb w)
		]
		(repend def/facets ['color x])
	]
	
	=pane=:       [set b block! (def/pane: b)]		;-- will only be expanded during instantiation
	
	=size=:       [
		[	ahead [skip ahead word! '.. skip]
			=size-component-2= (lo: x) skip =size-component-2= (hi: x)
		|	=size-component-1= (lo: hi: x)
		]
		(repend def/facets ['limits lo .. hi])
	]
	limit!: make typeset! [linear! planar! none!]
	=size-component-1=: [
		set x limit!
	|	set x [word! | get-word!] if (all [
			not VID/styles/:x						;-- protect from bugs if style name is set globally to a number
			not templates/:x
			find limit! type? set/any 'x get-safe x	;-- safe or may have lost context
			none <> :x								;-- ignore single none or unset values!
		])
	]
	=size-component-2=: [
		set x [limit! | word! | get-word! | paren!] (x: do x)
	]
	
	parse copy spec =vids=							;-- copy so styles can insert into it
	pane
];; lay-out-vids: function
	

; #hide [#assert [
	; lay-out-vids [										;-- new style names should be recognized
		; style text1: text 20
		; text1 "text"
	; ]
	
	; lt: lay-out-vids [									;-- ensure it doesn't deadlock
		; style text: text
		; style text: text
		; text
	; ]
	; single? lt											;-- last text should be recognized as instantiation
	
	; ys: []
	; lay-out-vids [
		; style x: box [y: text do [append ys y]]
		; x x												;-- should recognize 'x' here as instantiation (definition ended)
	; ]
	; 2 = length? ys
	; not same? :ys/1 :ys/2								;-- 'y' should stay inside 'x's context, not shared
	
	; button: text: 1
	; lt: lay-out-vids [button "ok" text "text"]
	; 2 = length? lt										;-- style names should not be broken by word values
	; lt/1/type = 'button
	; lt/2/type = 'text
	
	; error? try [lay-out-vids [nonexistent-word]]
	; error? try [lay-out-vids [text nonexistent-word]]
	
	; ;@@ add [text: text text= text] test here
; ]]
