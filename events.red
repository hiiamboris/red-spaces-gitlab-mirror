Red [
	title:   "Event processing pipeline for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires auxi.red (block-stack), error-macro.red, layout.red



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
		dirty?: no
	]
	init: [init-spaces-tree face]
]


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
				(source handler  none)
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
			trap/all/catch [fn get path/1 pcopy event] [
				msg: form/part thrown 400			;@@ should be formed immediately - see #4538
				#print "*** Failed to evaluate event (kind) (mold/part/flat :fn 100)!^/(msg)"
			]
			cache/put pcopy
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

	;@@ copy/deep does not copy inner maps unfortunately, so have to use this
	copy-deep-map: function [m [map!]] [
		m: copy/deep m
		foreach [k v] m [if map? :v [m/:k: copy-deep-map v]]
		m
	]

	;-- it's own DSL:
	;-- new-style: [                              
	;--   OR                                      
	;-- new-style: extends 'other-style [         
	;--     on-down [space path event] [...]      
	;--     on-time [space path event delay] [...]
	;--     inner-style: [                        
	;--         ...                               
	;--     ]                                     
	;-- ]                                         
	;@@ TODO: doc this DSL
	define-handlers: do with [
		expected: function ['rule] [
			reshape [!(rule) | p: (ERROR "Expected (mold quote !(rule)) at: (mold/part p 100)")]
		]
	][
		function [
			"Define event handlers for any number of spaces"
			def [block!] "[name: [on-event [space path event] [...]] ...]"
		] reshape [
			prefix: copy [handlers]

			=style-def=: [
				set name set-word! (name: to word! name)
				['extends
					;@@ TODO: allow paths here too
					set base !(expected [lit-word! | word!]) (base: to word! base)
				|	(base: none)
				]
				set body !(expected block!)
				(add-style/from name body base)
			]
			add-style: function [name body /from base] [
				append prefix name
				#debug events [print ["Defining" mold as path! prefix when base ["from"] when base [base]]]
				path: as path! prefix
				map: either base [
					copy-deep-map get as path! compose [handlers (to [] base)]
				][	copy #()
				]
				set path map
				fill-body body map
				take/last prefix
			]

			fill-body: function [body map] [
				parse body =style-body=
			]
			=style-body=: [
				any [
					not end
					ahead !(expected [word! | set-word!])
					=style-def= | =hndlr-def=
				]
			]

			=hndlr-def=: [
				set name word!
				set spec [ahead !(expected block!) into =spec-def=]
				set body !(expected block!)
				(add-handler name spec body)
			]
			add-handler: function [name spec body] [
				#debug events [print ["-" name]]
				path: as path! compose [(prefix) (name)]
				list: any [get path  set path copy []]
				append list function spec bind body commands
			]

			=spec-def=: [								;-- just validation, to protect from errors
				!(expected word!) opt [ahead block! [quote @(expected [object!])] ]
				!(expected word!) opt [ahead block! [quote @(expected [block!]) ] ]
				!(expected word!) opt [ahead block!
					!(expected [quote [event!] | quote [event! none!] | quote [none! event!]])
				]
				opt [if (name = 'on-time) not [refinement! | end]
					!(expected word!) opt [ahead block! [quote @(expected [percent!])]]
				]
				opt [not end !(expected /local) to end]
			]

			ok?: parse def [any [not end ahead !(expected set-word!) =style-def=]]		;-- no handlers in the topmost block allowed
			#assert [ok?]
		]
	]

	export [define-handlers]
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
			#debug events [unless event/type = 'time [print ["dispatching" event/type "event from" face/type]]]
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
					if empty? f: keyboard/focus [			;-- when focused by `set-focus`, keyboard/focus is not set, also see #3808 numerous bugs
						keyboard/focus: f: as f path-from-face face
					]
					f
				]
				; focus unfocus ;-- generated internally by focus.red
				time [
					on-time face event						;-- handled by timers.red
					if any [commands/update? face/dirty?] [	;-- only timer updates the view because of #4881 ;@@ on Linux this won't work
						face/draw: render face
						face/dirty?: no
						unless system/view/auto-sync? [show face]	;@@ or let the user do this manually?
					]
					; none
					exit									;-- timer does not need further processing
				]
				;@@ TODO: simulated hover-in and hover-out events to highlight items when hovering
				;@@ TODO: `enter` should be simulated because base face does not support it
				;@@ menu -- make context menus??
				;@@ select change  -- make these?
				; drag-start drag drop move moving resize resizing close  -- no need
				; zoom pan rotate two-tap press-tap   -- android-only?
				; create created  -- simulate these? (they're still undocumented mostly in View)
			] [exit]										;-- ignore unsupported events
			#debug events [print ["dispatch path:" path]]
			if path [
				#assert [block? path]						;-- for event handler's convenience, e.g. `set [..] path`
				#assert [any [not empty? path  event/away?]]	;-- empty when hovering out of the host (away = true)
				process-event path event focused?
			]
			if commands/update? [face/dirty?: yes]			;-- mark it for further redraw on timer
		]
	]

	;-- used for better stack trace, so we know error happens not in dispatch but in one of the event funcs
	do-handler: function [spc-name [path!] handler [function!] path [block!] args [block!]] [
		path: cache/hold path							;-- copy in case user modifies/reduces it, preserve index
		space: get path/1
		code: compose/into [handler space path (args)] clear []
		trap/all/catch code [
			msg: form/part thrown 400					;@@ should be formed immediately - see #4538
			#print "*** Failed to evaluate (spc-name)!^/(msg)"
		]
		cache/put path
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
		#debug events [if dragging? [#print "WARNING: Dragging override detected: (drag-path)->(path)"]]
		#debug events [#print "Starting drag on [(copy/part path -99) | (path)] with (:param)"]
		if dragging? [stop-drag]						;@@ not yet sure about this, but otherwise too much complexity
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

