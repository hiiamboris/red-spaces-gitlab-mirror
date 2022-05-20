Red [
	title:   "VID layout support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires export

;@@ use percent for weight globally?? but can be misleading as weights are summed
;@@ another idea: tag for hint (makes sense if hint is widely used)

VID: context [
	;@@ I'm not sure about adding containers (tubes, lists) to native VID!
	;@@ because it won't support spaces syntax and this will cause a lot of confusion!
	;@@ but without any facets set it kind of works and eliminates the need for `host` with only a single child
	; create VID styles for basic containers
	; #localize [
		; foreach name [hlist vlist row column] [
			; system/view/VID/styles/:name: spec: copy/deep system/view/VID/styles/host
			; spec/template/space: to lit-word! name
		; ]
	; ]
	
	;@@ add grids somehow
	
	#local [
		;; these help avoid repetition:
		#macro [#spacious] func [s e] [[ margin: spacing: 10x10 ]]
		#macro [#tight]    func [s e] [[ tight [margin: spacing: 0x0] ]]
		#macro [#align]    func [s e] [[
			left   [align/x: -1]
			right  [align/x:  1]
			center [align/x:  0]
			top    [align/y: -1]
			bottom [align/y:  1]
			middle [align/y:  0]
		]]
		#macro [#font-styles] func [s e] [[
			bold      [flags: append flags 'bold]
			italic    [flags: append flags 'italic]
			underline [flags: append flags 'underline]
		]]
		
		;; specifications for VID/S styles available in `lay-out-vids`
		styles: make map! reshape [
			hlist [
				template: list
				spec:     [#spacious axis: 'x]
				facets:   [#tight]						;@@ all these should be maps, but see REP #111
			]
			vlist [
				template: list
				spec:     [#spacious axis: 'y]
				facets:   [#tight]
			]
			row [
				template: tube
				spec:     [#spacious axes: [e s]]
				facets:   [#tight #align]
			]
			column [
				template: tube
				spec:     [#spacious axes: [s e]]
				facets:   [#tight #align]
			]
			list-view [									;@@ is there ever a need for horizontal list-view?
				template: list-view
				spec:     [list/spacing: 5x5 list/axis: 'y]
				facets:   [tight [list/margin: list/spacing: 0x0]]	;-- different from #tight macro
			]
			label [
				template: label
				spec:     [limits: 80 .. none]
				facets:   [
					image!  image
					char!   image
					string! text
					#font-styles
				]
			]
			text   [template: text   facets: [string! text #font-styles]]
			field  [template: field  facets: [string! text #font-styles]]
			link   [template: link   facets: [string! text url! text block! command]]
			button [template: button facets: [string! data block! command]]
			
			box    [template: box    facets: [#align]]
			cell   [template: cell   facets: [#align]]
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
				facets:   [
					pair!  bounds
					block! !(func [block] [
						;@@ hacky way to get access to current stylesheet.. any better idea?
						lay-out-grid/styles block get bind 'sheet :lay-out-vids
					]) 
				]
			]
		];; styles
		
		for-each [name spec] styles [spec/facets: make map! spec/facets]	;@@ dumb solution for REP #111
		
	];; #local
	
	;@@ grid
	;@@ grid-view
	
	
	;-- basic event dispatching face
	;@@ DOC it: user can use any face as long as 'space' is defined (serves as a marker for the host-event-func)
	system/view/VID/styles/host: [
		default-actor: worst-actor-ever						;-- worry not! this is useful
		template: [
			type:   'base
			size:   0x0										;-- no size by default - used by init-spaces-tree
			;; makes host background opaque otherwise it loses mouse clicks on most of it's part:
			;; (except for some popups that must be almost transparent)
			color:  system/view/metrics/colors/panel
			space:  none
			flags:  'all-over								;-- else 'over' events won't make sense over spaces
			rate:   100										;-- for space timers to work
			dirty?: no										;-- for events to mark the host for redraw
		]
		init: [init-spaces-tree face]
	]
	
	
	;; used internally in host's `init` only
	init-spaces-tree: function [face [object!]] [
		unless spec: select face/actors 'worst-actor-ever [exit]
		face/actors/worst-actor-ever: none
		#assert [function? :spec]
		spec: body-of :spec
		if empty? spec [exit]
		
		append clear focusing path-from-face face		;-- reset in case it wasn't & collect path prefix of faces
		;@@ this has no screen yet! because window is not shown!
		insert focusing anonymize 'screen system/view/screens/1
		
		pane: lay-out-vids spec
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
		if face/size = 0x0 [face/size: none]
		drawn: render face
		#assert [face/size]								;-- should be set by `render-face`, `size: none` blows up `layout`
		#debug draw [prin "host/draw: " probe~ drawn] 
		
		face/draw: drawn
	]
	
	
	wrap-value: function [
		"Create a space to represent given VALUE; return it's name"
		value [any-type!]
		wrap? [logic!] "How to lay text out: as a line (false) or paragraph (true)"
	][ 
		switch/default type?/word :value [
			string! [make-space/name pick [paragraph text] wrap? [text:  value]]
			logic!  [make-space/name 'logic [state: value]]
			image!  [make-space/name 'image [data:  value]]
			url!    [make-space/name 'link  [data:  value]]
			;@@ also object & map as grid? and use lay-out-data for block?
		] [make-space/name 'text [text: mold :value]]
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
	
	
	;@@ not exactly solid design - rethink this! in case errors happen during VID evaluation it may be corrupted
	focusing: make block! 20							;-- used internally to have a focusable path
	
	lay-out-grid: function [
		"Turn Grid specification block into a facet block"
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
				names: lay-out-vids/styles copy/part s e sheet
				foreach name names [
					repend code ['put 'content xy to lit-word! name]
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
	
	lay-out-vids: function [
		"Turn VID/S specification block into a forest of spaces"
		spec [block!]	;@@ document DSL, leave a link here
		/styles sheet [map! none!] "Add custom stylesheet to the global one"
		/local w b x lo hi late?
	][
		pane: make block! 8
		sheet: any [sheet make map! 4] 
		def: construct [								;-- accumulated single style definition
			styling?:										;-- used when defining a new style in VID
			template: 										;-- should not end in `=` (but not checked)
			with:											;-- used to build space, before all other modifiers applied
			link: 											;-- will be set to the instantiated space object
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
				append facets compose/only [
					actors: either object? :actors		;-- allows block! facet to define an actor too
						[construct/with (to [] def/actors) actors]
						[construct      (to [] def/actors)]
				]
			]
			space-spec: compose [
				(any [def/style/spec []])
				(def/with)
				(facets)
			]
			
			either def/styling? [						;-- new style defined
				new-style: copy/deep def/style
				either new-style/spec [
					new-style/spec: copy/deep space-spec
				][
					compose/only/into [spec: (space-spec)] tail new-style
				]
				put sheet def/link new-style
			][
				space: get name: make-space/name def/style/template space-spec
				if def/link [set def/link space]
				
				append focusing name					;@@ BUG: not cleared on error
				if def/pane [
					unless in space 'content [
						ERROR "Style (def/template) cannot contain other spaces"
					]
					content: lay-out-vids/styles def/pane sheet
					space/content: case [				;-- always trigger on-change just in case
						any-list? :space/content [content]
						immediate? :space/content [
							if 1 < n: length? content [
								ERROR "Style (def/template) can only contain a single space, given (n)"
							]
							content/1					;-- can be none if no items
						]
						'else [							;-- e.g. content is a map in grid
							ERROR "Style (def/template) requires custom content filling function"
						]
					]
				]
				if def/focused? [focus-space focusing]
				remove top focusing
				
				foreach [_ actor] def/actors [
					with [events/commands :actor] body-of :actor	;-- bind to commands but don't unbind locals
				]
				if actor: :def/actors/on-created [actor space none none]	;@@ need this? or need `on-create`?
				
				;; make reactive all spaces that define reactions or have a name
				;@@ this is a kludge for lacking PR #4529, remove me
				;@@ another option would be to make all VID spaces reactive, but this may be slow in generative layouts
				if any [def/link  not empty? def/reactions] [
					insert body-of :space/on-change*
						with [space :space/on-change*] [system/reactivity/check/only self word]
				]
				foreach [late? reaction] def/reactions [
					reaction: bind copy/deep reaction space
					either late? [react/later reaction][react reaction] 
				]
				
				append pane name
			]
		]
		
		reset: [
			set def none
			def/actors:    make map!   4
			def/facets:    make block! 8
			def/reactions: make block! 2
			def/with:      make block! 8
		]
		=vids=:              [any [(do reset) =styling= | =instantiating=]]
		=styling=:           [
			ahead word! 'style (def/styling?: yes)
			ahead #expect set-word! =space-name=
			=style-declaration=
		]
		=instantiating=:     [not end opt =space-name= =style-declaration=]
		=style-declaration=: [=style-name= any =modifier= (do commit-style)]
		=space-name=:        [set w set-word! (def/link: to word! w)]
		=style-name=:        [
			set w #expect word! (
				def/template: w
				case [
					x: sheet/:w [def/style: x]
					x: VID/styles/:w [def/style: x]
					templates/:w [def/style: reduce ['template w]]
					'else [ERROR "Unsupported VID/S style: (w)"]
				]
			)
		]
		
		=modifier=:   [
			not [ahead word! 'style]					;-- style is a keyword and can't be faceted
			[=with= | =reaction= | =action= | =focus= | =facet= | =flag= | =auto-facet= | =color= | =pane= | =size=]
		]
		
		=with=:       [ahead word! 'with  set b #expect block! (append def/with b)]	;-- collects multiple `with` blocks
		
		=reaction=:   [ahead word! 'react set late? opt [ahead word! 'later] set b #expect block! (
			;@@ this would likely require reactions run before pane is created, but needs more data for decision
			if def/styling? [ERROR "Reactions are not supported in style definitions yet"]
			repend def/reactions [late? b]
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
			set w word! if (attempt [facet: def/style/facets/:w])	;-- flag defined for this style? ;@@ REP #113
			(repend def/facets [none facet])
		]
			
		=auto-facet=: [
			set x any-type!											;-- try to match by value type
			if (attempt [facet: select def/style/facets type?/word :x])	;@@ REP #113
			(repend def/facets pick [[none facet :x] [facet :x]] function? :facet) 
		]
		
		;; I decided to make a special case because color is in principle applicable to all templates
		;; and adding it into every VID/S style would be tedious, plus raw templates won't support it otherwise
		;@@ should there be two colors (fg/bg)? (this may complicate styles a lot)
		=color=:      [
			[	set w word! if (tuple? get/any w) (x: get w)
			|	set w issue! if (x: hex-to-rgb w)
			]
			(repend def/facets ['color x])
		]
		
		=pane=:       [set b block! (
			if def/styling? [ERROR "Panes are not supported in style definitions yet"]
			def/pane: b
		)]
		
		=size=:       [
			[	ahead [skip ahead word! '.. skip]
				=size-component-2= (lo: x) skip =size-component-2= (hi: x)
			|	=size-component-1= (lo: hi: x)
			]
			(repend def/facets ['limits lo .. hi])
		]
		limit!: make typeset! [integer! float! pair! none!]
		=size-component-1=: [
			set x limit!
		|	set x [word! | get-word!] if (all [
				not VID/styles/:x						;-- protect from bugs if style name is set globally to a number
				not templates/:x
				find limit! type? set/any 'x get/any x
			])
		]
		=size-component-2=: [
			set x [limit! | word! | get-word! | paren!] (x: do x)
		]
		
		parse spec =vids=
		pane
	]
	
	export [lay-out-vids]
]

