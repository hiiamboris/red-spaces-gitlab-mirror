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
			ellipsize [flags: append flags 'ellipsize]
			; wrap      [flags: append flags 'wrap]		;-- no wrap flag by design, choose text vs paragraph instead 
		]]
		
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
			paragraph [template: paragraph facets: [string! text #font-styles]]
			text   [template: text   facets: [string! text #font-styles]]
			link   [template: link   facets: [string! text url! text block! command]]
			button [template: button facets: [string! data image! data block! command] spec: [limits: 40 .. none]]
			field  [
				template: field
				facets: [string! text #font-styles]
				;@@ unfortunately without deep reactivity there's no way changes in caret can be recognized in owning field
				;@@ so any reactions placed upon field/caret/stuff will not fire unless I explicitly make caret reactive
				;@@ #4529 could solve this for all spaces
				spec: [
					insert body-of :caret/on-change*
						with [caret :caret/on-change*] [		;-- newlines are imporant here for mold readability
							system/reactivity/check/only self word
						]
				]
			]
			
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
				layout:   lay-out-grid					;-- uses custom layout function
				facets:   [pair! bounds  #tight]
			]
		];; styles
		
		for-each [name spec] styles [spec/facets: make map! spec/facets]	;@@ dumb solution for REP #111
		
	];; #local
	
	;@@ grid-view
	
	
	host?: func ["Check if OBJ is a HOST face" obj [object!]]['host = class? obj]
	
	host-on-change: function [host word value] [
		if space? :host/space [invalidate host/space]
	]
	
	;; basic event dispatching face
	system/view/VID/styles/host: reshape [
		default-actor: worst-actor-ever					;-- worry not! this is useful
		init: [init-spaces-tree face]
		template: /use (declare-class/manual 'host [
			;; make a chimera of classy-object's and face's on-change so it works as a face and supports class features
			on-change*: function spec-of :classy-object!/on-change*
				with self append copy body-of :classy-object!/on-change* compose/only [
					;; this shields space object from being owned by the host and from cascades of on-deep-change events!
					unless word = 'space (body-of :face!/on-change*)
				]
			classify-object self 'host
			#assert [host? self]
			
			type:       'base					#type =  [word!]
			; style:      anonymize 'host self	#type =  [word!]	;-- word will be used as a reference from paths
			style:      'host					#type =  [word!]	;-- word will be used as a reference from paths
			;; no size by default - used by init-spaces-tree as a hint to resize the host itself:
			size:       0x0						#type =? [pair! none!]  :host-on-change
			;; makes host background opaque otherwise it loses mouse clicks on most of it's part:
			;; (except for some popups that must be almost transparent)
			color:      svmc/panel				#type =  [tuple! none!] :host-on-change
			space:      none					#type =? [object! (space? space) none!] :host-on-change
			flags:      'all-over				#type =  [block! word! none!]		;-- else 'over' events won't make sense over spaces
			rate:       100						#type =  [integer! time! none!]		;-- for space timers to work
			;; render generation number, used to detect live spaces (0 = never rendered):
			generation: 0.0						#type =  [float!]
		])
	]
	
	
	;; used internally in host's `init` only
	init-spaces-tree: function [face [object!]] [
		unless spec: select face/actors 'worst-actor-ever [exit]
		face/actors/worst-actor-ever: none
		#assert [function? :spec]
		spec: body-of :spec
		if empty? spec [exit]
		
		set 'focused none								;-- reset focus flag
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
		
		if object? focused [							;-- has to be focused after render creates the tree
			path: get-full-path focused
			#assert [path]
			focus-space compose [
				(system/view/screens/1)
				(face/parent)							;-- not linked to the screen yet, has no /parent
				(as [] path)
			] 
		]
	]
	
	
	wrap-value: function [
		"Create a space to represent given VALUE; return it's name"
		value [any-type!]
		wrap? [logic!] "How to lay text out: as a line (false) or paragraph (true)"
	][ 
		switch/default type?/word :value [
			string! [make-space pick [paragraph text] wrap? [text: value]]
			logic!  [make-space 'logic [state: value]]
			image!  [make-space 'image [data:  value]]
			url!    [make-space 'link  [data:  value]]
			block!  [either wrap? [lay-out-data/wrap value][lay-out-data value]]	;@@ use apply
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
	focused: none										;-- used to make `focus` flag work
			
	lay-out-vids: function [
		"Turn VID/S specification block into a forest of spaces"
		spec [block!]	;@@ document DSL, leave a link here
		/styles sheet [map! none!] "Add custom stylesheet to the global one"
		/local w b x lo hi late?
		/extern with									;-- gets collected from `def`
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
				append facets compose/deep/only [
					actors: either object? :actors		;-- allows block! facet to define an actor too
						[construct/with (to [] def/actors) actors]
						[construct      (to [] def/actors)]
				]
			]
			space-spec: compose [
				(any [def/style/spec []])
				(facets)
				(def/with)
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
						do with space layout/styles def/pane sheet
					][
						content: lay-out-vids/styles def/pane sheet
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
				if def/focused? [set 'focused space]
				
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
				foreach [late? reaction] def/reactions [
					reaction: bind copy/deep reaction space		;@@ should bind to commands too?
					either late? [react/later reaction][react reaction] 
				]
				
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
		=do=:         [ahead word! 'do    set b #expect block! (do b)]
		
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
			set w word!
			if (attempt [facet: def/style/facets/:w])	;-- flag defined for this style? ;@@ REP #113
			if (not find datatype-names w)				;-- datatype names do not count
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
			[	set x tuple!
			|	set w word! if (tuple? get/any w) (x: get w)
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
	];; lay-out-vids: function
	
	export [lay-out-vids host?]
]

