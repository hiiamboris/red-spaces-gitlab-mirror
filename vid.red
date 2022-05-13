Red [
	title:   "VID layout support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ TODO: a separate host-based style for each high level space
;@@ also, templates e.g. `vlist` should appear as `list` in the tree but have an `axis: 'y` as default
;@@ also combine them faces and spaces in one object! or not? `draw` will prove difficult, but we can rename it to render


vid-styles: make map! 10
vid-styles/hlist:     [template: list      spec: [margin: spacing: 10x10 axis: 'x]]
vid-styles/vlist:     [template: list      spec: [margin: spacing: 10x10 axis: 'y]]
vid-styles/row:       [template: tube      spec: [margin: spacing: 10x10 axes: [e s]]]
vid-styles/column:    [template: tube      spec: [margin: spacing: 10x10 axes: [s e]]]
vid-styles/list-view: [template: list-view spec: [margin: spacing: 10x10 axis: 'y]]	;@@ is there ever a need for horizontal list-view?
vid-styles/label: [
	template: label
	spec: [limits: 100 .. none]
	facets: #(
		image! image
		char! image
		string! text
	)
]
vid-styles/text: [
	template: text
	facets: #(
		string! text
	)
]
vid-styles/url: [
	template: url
	spec: []
	facets: #(
		url! text
	)
]
vid-styles/button: [
	template: button
	spec: []
	facets: #(
		string! data
		block! command
	)
]
;; grid
;; grid-view
;; timer
;; stretch
;; box
;@@ should it also accept raw template names? I think it should, but VID/S styles override templates


;-- basic event dispatching face
;@@ DOC it: user can use any face as long as 'space' is defined (serves as a marker for the host-event-func)
system/view/VID/styles/host: [
	default-actor: worst-actor-ever						;-- worry not! this is useful
	template: [
		type:   'base
		size:   0x0										;-- no size by default - used by vid.red (layout resets none to 0x0)
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

;@@ I'm not sure about adding containers to native VID!
;@@ because it won't support spaces syntax and this will cause confusion!
;@@ but without any facets set it kind of works and eliminates the need for `host` with only a single child
;; create VID styles for basic containers
; #localize [
	; foreach name [hlist vlist row column] [
		; system/view/VID/styles/:name: spec: copy/deep system/view/VID/styles/host
		; spec/template/space: to lit-word! name
	; ]
; ]


;@@ make it internal? no! rather there must be an exported `layout-spaces` or smth
init-spaces-tree: function [face [object!]] [
	unless spec: select face/actors 'worst-actor-ever [exit]
	face/actors/worst-actor-ever: none
	#assert [function? :spec]
	spec: body-of :spec
	if empty? spec [exit]
	
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
	rendered: render face
	#assert [face/size]						;-- should be set by `render-face`, `size: none` blows up `layout`
	#debug draw [prin "host/draw: " probe~ rendered] 
	
	face/draw: rendered
]


wrap-value: function [
	"Create a space to represent given VALUE; return it's name"
	value [any-type!]
][ 
	switch/default type?/word :value [
		string! [make-space/name 'text  [text:  value]]	;@@ text or paragraph??
		logic!  [make-space/name 'logic [state: value]]
		image!  [make-space/name 'image [data:  value]]
		url!    [make-space/name 'url   [data:  value]]
		;@@ also object & map as grid? and use lay-out-data for block?
	] [make-space/name 'text [text: mold :value]]
]

lay-out-data: function [
	"Create a space layout out of DATA block"
	data [block!] "image, logic, url get special treatment"
	/only "Return only the spaces list, do not create a layout"
][
	result: map-each value data [wrap-value :value]
	either only [
		result
	][
		make-space 'tube [
			margin:    0x0								;-- outer space most likely has it's own margin
			spacing:   10x10
			item-list: result
		]
	]
]


lay-out-vids: function [
	"Turn VID/S specification block into a forest of spaces"
	spec [block!]	;@@ document DSL, leave a link here
	/local w b x lo hi
][
	pane: make block! 8
	def: construct [								;-- accumulated single style definition
		template: 										;-- should not end in `=` (but not checked)
		spec:											;-- used to build space, before all other modifiers applied
		link: 											;-- will be set to the instantiated space object
		style: 											;-- style spec fetched from vid-styles
		reactions:										;-- bound to space
		actors:											;-- unlike event handlers, affects individual space only
		facets:											;-- facets collected by manual and auto-facet
		pane:											;-- unless snatched by auto-facet, assigns /content
		tight?:											;-- sets margin/spacing to zero
	]
	
	commit-style: [
		#assert [def/template]
		#assert [def/style/template "template name must be defined in style specification"]
		
		;; may assign non-existing facets like hint= or menu=
		facets: map-each/eval [facet value] def/facets [
			[to set-word! facet 'quote :value]
		]
		;; tight overrides template but not custom margin= spacing= facets, so comes before
		if def/tight? [insert facets [margin: spacing: 0x0]]
		space: make-space def/style/template compose [
			(any [def/style/spec []])
			(def/spec)
			(facets)
		]
		?? def/template
		??~ space
		if def/link [set def/link space]
		; foreach reaction def/reactions [react bind copy/deep reaction space]
		; def/actors					;@@ TODO: actors
		if def/pane [	;@@ remove item-list
			content: lay-out-vids def/pane
			; either block? 
			case [
				in space 'content [
					if 1 < n: length? content [
						ERROR "Style (def/template) can only contain a single space, given (n)"
					]
					if n = 1 [space/content: content/1]
				]
				in space 'item-list [append space/item-list content]
				'else [ERROR "Style (def/template) cannot contain other spaces"]
			]
		]
		;; check if tight was applicable - not possible in this pipeline, will always succeed
		; all [
			; def/tight? 
			; not in space 'margin
			; not in space 'spacing
			; ERROR "Style (def/template) does not have any margins or spacing to adjust"
		; ]
		append pane anonymize def/style/template space
	]
	
	reset: [
		set def none
		def/actors:    make map!   4
		def/facets:    make block! 8
		def/reactions: make block! 2
		def/spec:      make block! 8
	]
	=vids=:              [any [(do reset) =style-definition= | =style-declaration=]]
	=style-definition=:  [ahead word! 'style =new-name= =style-declaration=]
	=new-name=:          [set-word! (ERROR "Not implemented")]		;@@ implement custom styles
	=style-declaration=: [not end opt =space-name= =style-name= any =modifier= (do commit-style)]
	=space-name=:        [set w set-word! (def/link: w)]
	=style-name=:        [
		set w #expect word! (
			def/template: w
			case [
				x: vid-styles/:w [def/style: x]
				templates/:w [def/style: reduce ['template w]]
				'else [ERROR "Unsupported VID/S style: (w)"]
			]
		)
	]
	
	=modifier=:   [=spec= | =reaction= | =action= | =tight= | =facet= | =auto-facet= | =pane= | =size=]
	
	=spec=:       [ahead word! 'with  set b #expect block! (append def/spec b)]	;-- collects multiple `with` blocks
	
	=reaction=:   [ahead word! 'react set b #expect block! (	;@@ TODO: react/later
		ERROR "Space objects won't be reactive until PR #4529 is merged"
		append/only def/reactions b
	)]
	
	=action=:     [=actor-name= =actor-body=]
	=actor-name=: [set w word! if (find/match form w "on-")]
	=actor-body=: [
		set x [block! | get-word! | get-path! | block!] (def/actors/:w: x)
	|	ahead word! 'function p: #expect [2 block!] (def/actors/:w: function p/1 p/2)
	|	#expect "actor body"
	]
	
	=tight=:      [ahead word! 'tight (def/tight?: yes)]
	
	=facet=:      [=facet-name= =facet-expr=]
	=facet-name=: [
		set w word! if (#"=" = last s: form w) (
			take/last s  append def/facets to word! s
		)
	]
	=facet-expr=: [s: e: (append/only def/facets do/next s 'e) :e]
	
	=auto-facet=: [
		ahead set x any-type!
		if (attempt [facet: select def/style/facets type?/word :x])	;@@ REP #113
		(repend def/facets [facet :x])
		skip
	]
	
	;@@ rename item-list to content to generalize it
	=pane=:       [set b block! (def/pane: b)]
	
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
			not vid-styles/:x							;-- protect from bugs if style name is set globally to a number
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

