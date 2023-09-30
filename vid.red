Red [
	title:   "VID layout support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires export

;@@ use percent for weight globally?? but can be misleading as weights are summed
;@@ another idea: tag for hint (makes sense if hint is widely used)

VID: context [
	; create VID styles for basic containers
	; #localize [
		; foreach name [hlist vlist row column] [
			; system/view/VID/styles/:name: spec: copy/deep system/view/VID/styles/host
			; spec/template/space: to lit-word! name
		; ]
	; ]
	
	;; these help avoid repetition:
	props: #(
		spacious [margin: spacing: 10x10]
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
	)
		
	;; specifications for VID/S styles available in `lay-out-vids`
	styles: make map! reshape [
		scrollable [
			template: scrollable
			facets:   [
				vertical   [content-flow: 'vertical]
				horizontal [content-flow: 'horizontal]
			]
		]
		hlist [
			template: list
			spec:     [@(props/spacious) axis: 'x]
			facets:   [@(props/tight)]					;@@ all these should be maps, but see REP #111
		]
		vlist [
			template: list
			spec:     [@(props/spacious) axis: 'y]
			facets:   [@(props/tight)]
		]
		row [
			template: tube
			spec:     [@(props/spacious) axes: [e s]]
			facets:   [@(props/tight) @(props/align)]
		]
		column [
			template: tube
			spec:     [@(props/spacious) axes: [s e]]
			facets:   [@(props/tight) @(props/align)]
		]
		list-view [										;@@ is there ever a need for horizontal list-view?
			template: list-view
			spec:     [list/spacing: 5x5 list/axis: 'y]
			facets:   [
				tight [list/spacing: 0x0]				;-- different from #tight prop
				selectable       [selectable: 'single]
				multi-selectable [selectable: 'multi]
			]
		]
		label [
			template: label
			spec:     [limits: 80 .. none]
			facets:   [
				image!  image
				char!   image
				string! text
				@(props/font-styles)
			]
		]
		paragraph [template: paragraph facets: [string! text @(props/font-styles)]]
		text   [template: text   facets: [string! text @(props/font-styles)]]
		link   [template: link   facets: [string! text url! text block! command]]
		button [
			template: button
			facets: [string! data image! data block! command @(props/font-styles)]
			spec: [limits: 40 .. none]
		]
		data-clickable [
			template: data-clickable
			facets: [string! data image! data block! command @(props/font-styles)]
		]
		field  [
			template: field
			facets: [string! text @(props/font-styles)]
			;@@ unfortunately without deep reactivity there's no way changes in caret can be recognized in owning field
			;@@ so any reactions placed upon field/caret/stuff will not fire unless I explicitly make caret reactive
			;@@ #4529 could solve this for all spaces
			spec: [
				insert body-of :caret/on-change*
					with [caret :caret/on-change*] [			;-- newlines are imporant here for mold readability
						system/reactivity/check/only self word
					]
			]
		]
		rich-paragraph [
			template: rich-paragraph
			facets:   [percent! baseline @(props/text-align)]
		]
		rich-content [
			template: rich-content
			facets: [
				percent! baseline
				block! !(func [block] [compose/only/deep [kit/do-batch self [deserialize (block)]]])	;-- high level source dialect support for VID
				@(props/text-align)
			]
		]
		
		box   [template: box    facets: [@(props/align)]]
		cell  [template: cell   facets: [@(props/align)]]
		timer [
			template: timer
			facets:   [
				integer! rate
				float!   rate
				time!    rate
				block!   !(func [block] [
					compose/deep/only [
						actors: object [
							on-time: function [space path event delay] (block)
						]
					]
				])
			]
		]
		grid [
			template: grid
			layout:   lay-out-grid						;-- uses custom layout function
			facets:   [pair! bounds @(props/tight)]
		]
		slider [
			template: slider
			facets: [
				percent! offset
				float!   offset
			]
		]
	];; styles
	
	for-each [name spec] styles [spec/facets: make map! spec/facets]	;@@ dumb solution for REP #111
		
	;@@ grid-view
	
	
	host?: func ["Check if OBJ is a HOST face" obj [object!]]['host = class? obj]
	
	host-on-change: function [host word value] [
		;@@ maybe call a tree invalidation instead?
		if space? :host/space [invalidate host/space]
	]
	
	;; basic event dispatching face
	system/view/VID/styles/host: reshape [
		default-actor: worst-actor-ever					;-- worry not! this is useful
		init: [set 'init-window window-of face init-spaces-tree face]
		template: /use (declare-class/manual 'host [
			;; make a chimera of classy-object's and face's on-change so it works as a face and supports class features
			on-change*: function spec-of :classy-object!/on-change*
				with self append copy body-of :classy-object!/on-change* compose/only [
					;; this shields space object from being owned by the host and from cascades of on-deep-change events!
					unless word = 'space (body-of :face!/on-change*)
				]
			classify-object self 'host
			#assert [host? self]
			
			type:       'base					#type =  [word!]	;-- word will be used to lookup styles and event handlers
			;; no size by default - used by init-spaces-tree as a hint to resize the host itself:
			size:       (0,0)					#type =? [planar! none!]  :host-on-change
			;; makes host background opaque otherwise it loses mouse clicks on most of it's part:
			;; (except for some popups that must be almost transparent)
			color:      svmc/panel				#type =  [tuple! none!] :host-on-change
			space:      none					#type =? [object! (space? space) none!] :host-on-change
			flags:      'all-over				#type =  [block! word! none!]		;-- else 'over' events won't make sense over spaces
			rate:       100						#type =  [integer! time! none!]		;-- for space timers to work
			;; render generation number, used to detect live spaces (0 = never rendered):
			generation: 0.0						#type =  [float!]
			queue:      make hash! 200			#type    [hash! block!]	;-- queued events to process
		])
	]
	
	
	;; used internally in host's `init` only
	init-spaces-tree: function [face [object!] /local focused] [
		unless spec: select face/actors 'worst-actor-ever [exit]
		face/actors/worst-actor-ever: none
		#assert [function? :spec]
		spec: body-of :spec
		if empty? spec [exit]
		
		default focus/window: window-of face			;-- init focus
		focused: track-focus [pane: lay-out-vids spec]
		if 1 < n: length? pane [ERROR "Host face can only contain a single space, given (n)"]
		face/space: pane/1
		;; this is rather tricky:
		;;  1. we want `render` to render the content on currently set face/size
		;;  2. yet, in `layout` we set face/size from the rendered content size
		;; so, to avoid double rendering we have to re-apply the host style
		;; this is done inside `render-face` if we set size to none
		;; for this reason, `host` template contains `size: 0x0`
		;; which is used as a hint to estimate size automatically
		;; user can then explicitly set host size to nonzero, in which case it's not changed
		if zero? face/size [face/size: none]
		drawn: render face
		#assert [face/size]								;-- should be set by `render-face`, `size: none` blows up `layout`
		#debug draw [prin "host/draw: " probe drawn] 
		face/draw: drawn
		
		;; also the tree does not exist until drawn, so focus-space will fail (and see notes on track-focus)
		;; so I have to put focus here, and this also tells View to focus the host
		if focused [set-focus focused]
	]
	
	;; focus is tricky! lay-out-vids should never change focus, because its result may never be part of the tree
	;; but it has to return the pane, so focused space becomes its extra return
	;; lack of apply is no fun: instead of passing a refinement across all layout functions, it's much easier to use a wrapper
	track-focus: function [
		"Wrapper for layout functions that returns the last space with focus marker (or none)"
		code [block!] "Evaluated"
		/local focused
	][
		do code
		:focused
	]
	update-focus: func [space [object!]] with :track-focus [
		try [focused: space]							;-- may fail when called outside of track-focus scope
	]
	
	wrap-value: function [
		"Create a space to represent given VALUE; return it's name"
		value [any-type!]
		wrap  [logic!] "How to lay text out: as a line (false) or paragraph (true)"
	][ 
		switch/default type?/word :value [
			string! [make-space pick [paragraph text] wrap [text: value]]
			logic!  [make-space 'logic [state: value]]
			image!  [make-space 'image [data:  value]]
			url!    [make-space 'link  [text:  value]]
			block!  [lay-out-data/:wrap value]
		] [make-space 'text [text: mold :value]]
	]
	
	
	lay-out-data: function [
		"Create a space layout out of DATA block"
		data [block!] "image, logic, url get special treatment"
		/only "Return only the spaces list, do not create a layout"
		/wrap "How to lay text out: as a line (false) or paragraph (true)"
	][
		result: map-each value data [wrap-value :value wrap]
		unless only [
			result: make-space 'tube [
				margin:  0x0							;-- outer space most likely has it's own margin
				spacing: 10x10
				content: result
			]
		]
		result
	]
	
	
	lay-out-grid: function [
		"Turn Grid specification block into a code block"
		spec [block!] "Same as VID/S, with `as pair!` / `as range!` support"
		/styles sheet [map! none!] "Add custom stylesheet to the global one"
		/local x
	][
		code: make block! 20
		xy:   1x1
		step: 1x0
		
		=at-expr=: [s: e: (set/any 'x do/next s 'e) :e]
		=at=: [
			ahead word! 'at =at-expr=
			(case [
				pair? :x [xy: x]
				all [range? :x  pair? x/min  pair? x/max] [
					repend code ['set-span  xy: x/min  x/max + 1 - xy]
				]
				'else [ERROR "Expected pair or range of pairs after 'at' keyword, got (type? :x) at (mold/part s 100)"]
			])
		]
		=batch=: [
			opt =at=
			s: to [ahead word! ['at | 'return | 'across | 'below] | end] e: (	;-- lay out part between keywords
				spaces: lay-out-vids/styles copy/part s e sheet
				foreach space spaces [
					repend code ['put 'content xy space]
					xy: xy + step
				]
			)
		]
		=return=: [ahead word! 'return (xy: 1 + multiply xy reverse step)]
		=across=: [ahead word! 'across (step: 1x0)]
		=below=:  [ahead word! 'below  (step: 0x1)]
		parse spec [any [=return= | =across= | =below= | =batch=]]
		code
	]
	
	datatype-names: to block! any-type!					;-- used to screen datatypes from flags
			
	lay-out-vids: function [
		"Turn VID/S specification block into a forest of spaces"
		spec [block!] "See VID/S manual on syntax" 
		/styles sheet [map! none!] "Add custom stylesheet to the global one"
		/local w b x lo hi late?
		/extern with									;-- gets collected from `def`
	][
		pane: make block! 8
		sheet: any [sheet make map! 4]					;-- new sheet should not persist after leaving lay-out-vids 
		def: construct [								;-- accumulated single style definition
			styling?:										;-- used when defining a new style in VID
			template: 										;-- should not end in `=` (but not checked)
			with:											;-- used to build space, before all other modifiers applied
			link: 											;-- prefix set-word, will be set to the instantiated space object
			style: 											;-- style spec fetched from VID/styles
			reactions:										;-- bound to space
			actors:											;-- unlike event handlers, affects individual space only
			facets:											;-- facets collected by manual and auto-facet
			pane:											;-- unless snatched by auto-facet, assigns /content
			focused?:										;-- to move focus into this space
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
						/with object? :actors :actors	;-- allows block! facet to define an actor too
					]
				]
			]
			space-spec: compose [
				(any [def/style/spec []])
				(facets)
				(def/with)
			]
			
			either def/styling? [						;-- new style defined, def/style already copied and in the sheet
				unless def/style/payload [append def/style [payload: []]] 
				def/style/payload: copy/deep/part style-bgn style-end
				; #print "saved payload (mold def/style/payload) in (def/link) style based on (def/style/template)"
			][
				space: make-space def/style/template space-spec
				if def/link [set def/link space]		;-- set the word before calling reactions
				
				if def/pane [
					unless in space 'content [
						ERROR "Style (def/template) cannot contain other spaces"
					]
					;; allow usage of custom layout function
					either def/style/layout [
						layout: get def/style/layout
						#assert [function? :layout]
						do with space layout/styles  def/pane copy sheet	;-- copy sheet so inner styles don't modify parent's
					][
						content: lay-out-vids/styles def/pane copy sheet	;-- copy sheet so inner styles don't modify parent's
						space/content: case [			;-- always trigger on-change just in case
							any-list? :space/content [content]
							immediate? :space/content [
								if 1 < n: length? content [
									ERROR "Style (def/template) can only contain a single space, given (n)"
								]
								content/1				;-- can be none if no items
							]
							'else [						;-- e.g. content is a map in grid
								ERROR "Style (def/template) requires custom content filling function"
							]
						]
					]
				]
				if def/focused? [update-focus space]	;-- does not trigger actors/events (until fully drawn)
				
				if object? actors: select space 'actors [
					foreach actor values-of actors [
						;; bind to space and commands but don't unbind locals:
						with [space events/commands :actor] body-of :actor
					]
				]
				if actor: :def/actors/on-created [actor space none none]	;@@ need this? or need `on-create`?
				
				;; make reactive all spaces that define reactions or have a name
				;@@ this is a kludge for lacking PR #4529, remove me
				;@@ another option would be to make all VID spaces reactive, but this may be slow in generative layouts
				if any [def/link  not empty? def/reactions] [
					insert body-of :space/on-change*
						with [space :space/on-change*] [		;-- newlines are imporant here for mold readability
							system/reactivity/check/only self word
						]
				]
				foreach [later reaction] def/reactions [
					reaction: bind copy/deep reaction space		;@@ should bind to commands too?
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
					;; literally insert anonymized copy of the payload
					;; to avoid set-words collision when a style with set-words inside is instantiated multiple times:
					ctx: construct collect-set-words payload
					insert p with ctx copy/deep payload
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
		=actor-name=: [set w word! if (find/match form w "on-")]
		=actor-body=: [
			set b block! (def/actors/:w: function [space path event] b)
		|	set x [get-word! | get-path!] (
				unless function? get/any x [
					ERROR "(mold x) should refer to a function, not (type? get/any x)"
				]
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
	
	export [lay-out-vids host?]
]

#localize [#assert [
	lay-out-vids [										;-- new style names should be recognized
		style text1: text 20
		text1 "text"
	]
	
	lt: lay-out-vids [									;-- ensure it doesn't deadlock
		style text: text
		style text: text
		text
	]
	single? lt											;-- last text should be recognized as instantiation
	
	ys: []
	lay-out-vids [
		style x: box [y: text do [append ys y]]
		x x												;-- should recognize 'x' here as instantiation (definition ended)
	]
	2 = length? ys
	not same? :ys/1 :ys/2								;-- 'y' should stay inside 'x's context, not shared
	
	button: text: 1
	lt: lay-out-vids [button "ok" text "text"]
	2 = length? lt										;-- style names should not be broken by word values
	lt/1/type = 'button
	lt/2/type = 'text
	
	error? try [lay-out-vids [nonexistent-word]]
	error? try [lay-out-vids [text nonexistent-word]]
]]
