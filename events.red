Red [
	title:   "Event processing pipeline for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires auxi.red (block-stack), error-macro.red



;-- basic event dispatching face
;@@ DOC it: user can use any face as long as 'space' is defined (serves as a marker for the host-event-func)
;@@ TODO: get this out somewhere else
system/view/VID/styles/host: [
	default-actor: worst-actor-ever					;-- worry not! this is useful
													;@@ TODO: lay it out
	template: [
		type: 'base
		size: 100x100
		space: none
		flags: 'all-over							;-- else 'over' events won't make sense over spaces
		rate: 100									;-- for space timers to work
	]
	init: [init-spaces-tree face]
]


;@@ make it internal?
init-spaces-tree: function [face [object!]] [
	unless spec: select face/actors 'worst-actor-ever [exit]
	face/actors/worst-actor-ever: none
	#assert [function? :spec]
	spec: body-of :spec
	if empty? spec [exit]
	tree-from: function [spec [block!]] [
		r: copy []
		while [not empty? spec] [
			name: spec/1  spec: next spec
			#assert [word? name]		;@@ TODO: normal error handling here
			#assert [spaces/:name  'name]
			name: make-space/name name []
			append r name
			space: get name
			if spec/1 = 'with [		;-- reserved keyword
				blk: spec/2
				#assert [block? blk]
				spec: skip spec 2
				do bind blk space
			]
			if block? blk: spec/1 [		;@@ TODO: sizes data and whatever else to make this on par with `layout`
				spec: next spec
				inner: tree-from blk
				unless empty? inner [
					case [		;@@ this is all awkward adhoc crap - need to generalize it!
						t: in space 'content [space/content: inner/1]
						t: in space 'items   [append space/items inner]
						'else [ERROR "do not know how to add spaces to (name)"]
					]
				]
			]
		]
		r
	]
	tree: tree-from spec
	#assert [any [1 >= length? tree]]
	face/space: tree/1
	render face/space			;@@ required to populate `map`s & get the size
	face/size: select get face/space 'size
]


;@@ TODO: a separate host-based style for each high level space
;@@ also combine them faces and spaces in one object! or not? `draw` will prove difficult, but we can rename it to render


;-- event function that pushes events over to each space
context [
	;@@ TODO: scan previewers/finalizers against this list
	supported-events: make hash! [
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		focus unfocus
		time
	]
	host-event-func: function [host event] [
		all [
			word? w: select host 'space					;-- a host face?
			space? get w
			find supported-events event/type
			events/dispatch host event
			none										;-- the event can be processed by other handlers
		]
	]
	unless find/same system/view/handlers :host-event-func [
		insert-event-func :host-event-func
	]
]


events: context [
	cache: copy/deep block-stack

	on-time: none										;-- set by timers.red

	;-- previewers and finalizers are called before/after handlers
	;-- both have the same args format: [space [object!] path [block!] event [event!]]
	;-- stop? command indicates that event was "eaten" and becomes true after:
	;-- any previewer or finalizer calls `stop`
	;-- any normal event handler does not call `pass`
	;-- "eaten" events do not propagate further into normal event handlers, but do into all previewers & finalizers
	;-- map format: event/type [word!] -> list of functions
	previewers: #()
	finalizers: #()

	;-- we want extensibility so this is a map of maps:
	;-- format: space-name [word!] -> on-event-type [word!] -> list of functions [path [block!] event [event! none!] ...]
	;--         space-name [word!] -> sub-space-name [word!] -> ... (reentrant, supports paths)
	handlers: #()


	register-as: function [map [map!] types [block!] handler [function!]] [
		delist-from map :handler						;-- duplicate protection, in case of multiple includes etc.
		#assert [										;-- validate the spec to help detect bugs
			any [
				parse spec-of :handler [
					word! opt quote [object!]
					word! opt quote [block!]
					word! opt [quote [event!] | quote [event! none!] | quote [none! event!]]
					;@@ does not receive delay [percent!] - but should it?
					opt [/local to end]
				]
				(?? handler  none)
			]
			"invalid handler spec"
		]
		foreach type types [
			#assert [word? type]
			list: any [map/:type  map/:type: copy []]
			append list :handler						;@@ append or insert? affects evaluation order
			bind body-of :handler commands
		]
		:handler
	]

	delist-from: function [map [map!] handler [function!]] [
		foreach [_ list] map [
			remove-each fn list [:handler =? :fn]
		]
	]

	register-previewer: func [
		"Register a previewer in the event chain; remove previous instances"
		types [block!] "List of event/type words that this HANDLER supports"
		handler [function!] "func [path event]"
	][
		register-as previewers types :handler
	]

	register-finalizer: func [
		"Register a finalizer in the event chain; remove previous instances"
		types [block!] "List of event/type words that this HANDLER supports"
		handler [function!] "func [path event]"
	][
		register-as finalizers types :handler
	]

	delist-previewer: func [
		"Unregister a previewer from the event chain"
		handler [function!] "Previously registered"
	][
		delist-from 'previewers :handler
	]

	delist-finalizer: func [
		"Unregister a previewer from the event chain"
		handler [function!] "Previously registered"
	][
		delist-from 'finalizers :handler
	]

	export [register-previewer register-finalizer delist-previewer delist-finalizer]


	do-previewers: func [path [block!] event [event! none!] type [word!]] [
		do-global previewers path event type
	]

	do-finalizers: func [path [block!] event [event! none!] type [word!]] [
		do-global finalizers path event type
	]

	;-- `type` is only required for focus/unfocus events, since we can't construct a fake 'event!' type
	do-global: function [map [map!] path [block!] event [event! none!] type [word!]] [
		unless list: map/:type [exit]
		kind: either map =? previewers ["previewer"]["finalizer"]
		foreach fn list [
			pcopy: cache/hold path					;-- copy in case user modifies/reduces it, preserve index
			error: try/all [set/any 'result (fn get path/1 pcopy event)  'ok]
			cache/put pcopy
			unless 'ok == error [
				print #composite "*** Failed to evaluate event (kind) (mold/part/flat :fn 100)!"
				print form/part error 400
			]
		]
	]

	; copy-handlers: function [
	; 	"Make wrappers for event handlers from STYLE"
	; 	style [word! path! block!] "Style name"		;-- requires style name so we can build paths
	; ][
	; 	r: copy #()
	; 	style: to [] style
	; 	spec: get as path! compose [handlers (style)]
	; 	unless spec [return r]
	; 	foreach [hname hfunc] spec [
	; 		either map? m: :hfunc [
	; 			r/:hname: copy-handlers compose [(style) (hname)]
	; 		][
	; 			spec: copy spec-of :hfunc
	; 			clear find spec refinement!
	; 			r/:hname: func spec compose [
	; 				(as path! compose [handlers (style) (to word! hname)]) (spec)
	; 			]
	; 		]
	; 	]
	; 	r
	; ]

	define-handlers: function [
		"Define event handlers"
		spec [block!] "A block of: event-name [spec..] [code..]"
	][
		extend-handlers #() spec
	]

	copy-deep-map: function [m [map!]] [
		m: copy/deep m
		foreach [k v] m [if map? :v [m/:k: copy-deep-map v]]
		m
	]

	extend-handlers: function [
		"Extend event handlers of STYLE"
		style [path! word! map!] "Style name, path or a map of it's event handlers"
		def [block!] "A block of: on-event-name [spec..] [code..]"
	][
		all [
			not map? map: style
			none? map: get as path! compose [handlers (style)]
			map: #()
		]
		#assert [map? map]
		r: copy-deep-map map							;@@ BUG: copy/deep does not copy inner maps unfortunately
		while [not tail? def] [
			either word? :def/1 [						;-- on-event [spec] [body] case
				set [name: spec: body:] def
				def: skip def 3
				list: any [r/:name r/:name: copy []]
				#assert [								;-- validate the spec to help detect bugs
					any [
						parse spec [
							word! opt quote [object!]
							word! opt quote [block!]
							word! opt [quote [event!] | quote [event! none!] | quote [none! event!]]
							opt [if (name = 'on-time) word! opt quote [percent!]]
							opt [/local to end]
						]
						(?? handler  none)				;-- display handler to clarify what error is
					]
					"invalid handler spec"
				]
				append list function spec bind body commands
			][											;-- substyle: [handlers..] case
				#assert [not map? style]				;-- cannot be used without named style
				#assert [set-word? :def/1]
				set [name: spec:] def
				def: skip def 2
				unless r/:name [r/:name: copy #()]
				; name: to word! name
				substyle: as path! compose [(style) (to word! name)]
				r/:name: extend-handlers substyle spec
			]
		]
		r
	]

	export [define-handlers extend-handlers]
	; export [copy-handlers define-handlers extend-handlers]



	;-- stack-like wrapper for `commands` usage
	with-commands: function [code [block!]] [
		update?: stop?: no								;-- force logic type
		do code
	]

	;-- has to be set later so we can refer to 'events' to get the drag functions
	commands: none

	;-- fundamentally there are 3 types of events here:
	;-- - events tied to a coordinate (mouse, touch) - then hittest is used to obtain path
	;-- - events tied to focus (keyboard, focus changes) - these use keyboard/focus path in the tree
	;-- - events without both (timer) - but timer has path too, and also delay
	;-- coordinate events' path includes pairs of coordinates (hittest format)
	;-- other events' path does not (tree node format)
	;-- focus/unfocus events have not 'event' arg!
	;@@ any way to unify these 2 formats?
	dispatch: function [face event /local result /extern resolution last-on-time] [
		focused?: no
		with-commands [
			; #debug [unless event/type = 'time [print ["dispatching" event/type "event from" face/type]]]
			buf: cache/get
			path: switch/default event/type [
				over wheel up mid-up alt-up aux-up
				down mid-down alt-down aux-down click dbl-click [	;-- `click` is simulated by single-click.red
					;@@ should spaces all be `all-over`? or dupe View 'all-over flag into each space?
					hittest/as/into
						face/space
						event/offset
						if dragging? [head drag-path]
						clear []							;-- use a static buffer since `over` events can be populous (process-event ensures copy)
				]
				key key-down key-up enter [
					focused?: yes							;-- event should not be detected by parent spaces
					keyboard/focus
				]
				; focus unfocus ;-- generated internally
				time [
					on-time face event						;-- handled by timers.red
					none
				]
				;@@ TODO: simulated hover-in and hover-out events to highlight items when hovering
				;@@ TODO: `enter` should be simulated because base face does not support it
				;@@ menu -- make context menus??
				;@@ select change  -- make these?
				; drag-start drag drop move moving resize resizing close  -- no need
				; zoom pan rotate two-tap press-tap   -- android-only?
			] [exit]										;-- ignore unsupported events
			; #debug [print ["dispatch path:" path]]
			if path [
				#assert [block? path]						;-- for event handler's convenience, e.g. `set [..] path`
				process-event path event focused?
			]
			if commands/update? [
				face/draw: render/as face/space 'root
				do-events/no-wait				;@@ is it OK to drop it here? or in the handlers? gonna stack overflow?
												;@@ or maybe use reactivity to unroll the recursion?
			]
		]
	]

	;-- used for better stack trace, so we know error happens not in dispatch but in one of the event funcs
	do-handler: function [spc-name [path!] handler [function!] path [block!] args [block!]] [
		path: cache/hold path							;-- copy in case user modifies/reduces it, preserve index
		space: get path/1
		code: compose/into [handler space path (args)] clear []
		error: try/all [set/any 'result do code  'ok]
		cache/put path
		unless 'ok == error [
			msg: form/part error 400					;@@ should be formed immediately - see #4538
			print #composite "*** Failed to evaluate (spc-name)!"
			print msg
		]
	]

	do-handlers: function [
		"Evaluates normal event handlers applicable to PATH"
		path [block!] event [event! none!] type [word!] focused? [logic!]
	][
		if commands/stop? [exit]
		hnd-name: to word! head clear change skip "on-" 3 type		;-- don't allocate
		wpath: path  unit: 1										;-- word-only path
		if pair! = type? second path [
			wpath: extract/into path unit: 2 clear []				;-- remove pairs
		]
		#assert [not find wpath pair!]
		len: length? wpath
		i2: either focused? [len][1]								;-- keyboard events should only go into the focused space
		template: next as path! [handlers]							;-- static, not allocated
		;@@ TODO: this is O(len^2) and should be optimized...
		while [i2 <= len] [											;-- walk from the outermost spaces to the innermost
			repeat i1 i2 [											;-- walk from the longest path to the shortest
				hpath:												;-- construct full path to the handler
					append append/part
					clear template 
					at wpath i1  skip wpath i2						;-- add slice [i1,i2] of path
					hnd-name
				if empty? list: attempt [get hpath] [continue]
				#assert [block? :list]
				commands/stop										;-- stop after current stack unless `pass` gets called
				path: skip head path i2 - 1 * unit					;-- position path at the space that receives event
				foreach handler list [								;-- whole list is called regardless of stop flag change
					#assert [function? :handler]
					do-handler template :handler path [event]		;@@ should handler index in the list be reported on error?
				]
				if commands/stop? [exit]
			]
			i2: i2 + 1
		]
	]

	process-event: function [path [block!] event [event!] focused? [logic!]] [
		do-previewers path event event/type
		unless commands/stop? [do-handlers path event event/type focused?]
		do-finalizers path event event/type
	]


	;-- pointer can only be captured by single space at a time, so this info is shared:
	drag-in: object [
		head: path: []									;-- `head` alias is needed to avoid a LOT of `head path` calls
		payload: none
	]
	

	dragging?: does [not empty? drag-in/head]
	
	stop-drag: function [
		"Stop dragging; return truthy if stopped, none otherwise"
	][
		if dragging? [
			drag-in/payload: none						;-- let GC release it
			clear drag-in/head
		]
	]
	
	start-drag: func [
		"Start dragging marking the initial state by PATH"
		path [path! block!]
		/with param [any-type!] "Attach any data to the dragging state"
	][
		#assert [not dragging?]
		append clear drag-in/head head path				;-- make a copy in place, saving original offsets
		drag-in/path: at drag-in/head index? path		;-- drag-path will return it at the same index
		set/any in drag-in 'payload :param
	]

	drag-path: func ["Return path that started dragging (or none)"] [
		if dragging? [:drag-in/path]					;@@ copy or not?
	]
	
	drag-parameter: func ["Fetch the user data attached to the dragging state"] [
		:drag-in/payload
	]
	
	drag-offset: function [
		"Get current dragging offset (or none if not dragging)"
		path [path! block!] "index of PATH controls the space to which offset will be relative to"
	][
		unless dragging? [return none]
		path': at drag-in/head index? path
		set [spc': ofs':] path'
		set [spc:  ofs: ] path
		#assert [spc = spc']							;-- only makes sense to track it within the same space
		#assert [word? spc]  #assert [pair? ofs]  #assert [pair? ofs']
		ofs - ofs'
	]

]

;-- toolkit available to every event handler/previewer/finalizer
;-- designed following REP#80 - commands, not return values
events/commands: context with events [
	;-- update shouldn't throw immediately but set a flag
	;-- but flag is local to each handler's call, so we have to use a hack here
	update:  does [set bind 'update? :with-commands yes]
	update?: does [get bind 'update? :with-commands]
	;@@ question here is what is the default behavior: pass the event further or not?
	;@@ let's try with 'stop' by default
	stop:    does [set bind 'stop?   :with-commands yes]	;-- used by previewers/finalizers
	stop?:   does [get bind 'stop?   :with-commands]
	pass:    does [set bind 'stop?   :with-commands no]		;-- stop is ignored for timer events ;@@ DOC it

	;-- the rest does not require a stack but should be available too
	dragging?:      :events/dragging?
	stop-drag:      :events/stop-drag
	start-drag:     :events/start-drag
	drag-path:      :events/drag-path
	drag-parameter: :events/drag-parameter
	drag-offset:    :events/drag-offset
]

