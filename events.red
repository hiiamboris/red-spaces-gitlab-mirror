Red [
	title:   "Event processing pipeline for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires auxi.red (make-free-list), styles (to fix svmc/), error-macro.red, vid.red


;-- event function that pushes events over to each space
context [
	;@@ TODO: scan previewers/finalizers against this list
	supported-events: make hash! [
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		; focus unfocus 	-- internally generated ;@@ but maybe these will be required too
		time
	]
	;; sometimes this gets window as 'host', likely when no face is in focus
	host-event-func: function [host event] [
		all [
			word? w: select host 'space					;-- a host face? ;@@ use classes to detect this, and maybe /content field?
			space? get w
			find supported-events event/type
			events/dispatch host event
			none										;-- the event can be processed by other handlers
		]
	]
	unless find/same system/view/handlers :host-event-func [	;@@ check shouldn't be needed anymore
		insert-event-func :host-event-func
	]
]


events: context [
	cache: make-free-list block! [make [] 100]

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
					word! opt [quote [object!] | quote [object! none!] | quote [none! object!]]
					word! opt quote [block!]
					word! opt [quote [event!] | quote [event! object!] | quote [object! event!]]
					opt [word! opt [quote [percent!] | quote [percent! none!] | quote [none! percent!]]]
					opt [/local to end]
				]
				(source handler  none)
			] "invalid handler spec"
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
		handler [function!] "func [space path event]"
	][
		register-as previewers types :handler
	]

	register-finalizer: func [
		"Register a finalizer in the event chain; remove previous instances"
		types [block!] "List of event/type words that this HANDLER supports"
		handler [function!] "func [space path event]"
	][
		register-as finalizers types :handler
	]

	delist-previewer: func [
		"Unregister a previewer from the event chain"
		handler [function!] "Previously registered"
	][
		delist-from previewers :handler
	]

	delist-finalizer: func [
		"Unregister a previewer from the event chain"
		handler [function!] "Previously registered"
	][
		delist-from finalizers :handler
	]

	export [register-previewer register-finalizer delist-previewer delist-finalizer]


	do-previewers: func [path [block!] event [event! object!] args [block!]] [
		do-global previewers path event args
	]

	do-finalizers: func [path [block!] event [event! object!] args [block!]] [
		do-global finalizers path event args
	]

	do-global: function [map [map!] path [block!] event [event! object!] args [block!]] [
		unless list: map/(event/type) [exit]
		space: all [path/1 get path/1]					;-- space can be none if event falls into space-less area of the host ;@@ REP #113
		;@@ none isn't super elegant here, for 4-arg handlers when delay is unavailable
		code: compose/into [handler space pcopy event (args) none] clear []
		foreach handler list [
			pcopy: clone path cache/get					;-- copy in case user modifies/reduces it, preserve index
			trap/all/catch code [
				msg: form/part thrown 1000				;@@ should be formed immediately - see #4538
				kind: either map =? previewers ["previewer"]["finalizer"]
				#print "*** Failed to evaluate event (kind) (mold/part/flat :handler 100)!^/(msg)"
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
	define-handlers: function [
		"Define event handlers for any number of spaces"
		def [block!] "[name: [on-event [space path event] [...]] ...]"
	] reshape [
		prefix: copy [handlers]

		=style-def=: [
			set name set-word! (name: to word! name)
			['extends
				;@@ TODO: allow paths here too
				set base #expect [lit-word! | word!] (base: to word! base)
			|	(base: none)
			]
			set body #expect block!
			(add-style/from name body base)
		]
		add-style: function [name body /from base] [
			append prefix name
			#debug events [print ["Defining" mold as path! prefix when base ("from") when base (base)]]
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
				ahead #expect [word! | set-word!]
				=style-def= | =hndlr-def=
			]
		]

		=hndlr-def=: [
			set name word!
			set spec [ahead #expect block! into =spec-def=]
			set body #expect block!
			(add-handler name spec body)
		]
		add-handler: function [name spec body] [
			#debug events [print ["-" name]]
			path: as path! compose [(prefix) (name)]
			list: any [get path  set path copy []]
			append list function spec bind body commands
		]

		=spec-def=: [								;-- just validation, to protect from errors
			#expect word! opt [ahead block! #expect quote [object!]]	;-- space [object!]
			#expect word! opt [ahead block! #expect quote [block!]]	;-- path [block!]
			#expect word! opt [
				quote [event! object!]
			|	quote [object! event!]
			|	ahead block! #expect quote [event!]
			]
			opt [if (name = 'on-time) not [refinement! | end]
				#expect word! opt [ahead block! #expect quote [percent!]]
			]
			opt [not end #expect /local to end]
		]

		ok?: parse def [any [not end ahead #expect set-word! =style-def=]]	;-- no handlers in the topmost block allowed
		#assert [ok?]
	]

	export [define-handlers]
	; export [copy-handlers define-handlers extend-handlers]



	;; stack-like wrappers for `commands` usage
	;; have to be separate because `stop?` is valid until all finalizers are done (e.g. in simulated events)
	with-stop: function [code [block!]] [
		stop?: no										;-- force logic type
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
	dispatch: function [face [object!] event [event!] /local result /extern resolution last-on-time] [
		focused?: no
		with-stop [
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
						make block! 12
				]
				key key-down key-up enter [
					focused?: yes								;-- event should not be detected by parent spaces
					if empty? f: keyboard/focus [				;-- when focused by `set-focus`, keyboard/focus is not set, also see #3808 numerous bugs
						keyboard/focus: f: as f path-from-face face
					]
					f
				]
				; focus unfocus ;-- generated internally by focus.red
				time [
					on-time face event							;-- handled by timers.red
					#assert [face/space]
					cspace: get face/space
					if dirty?: cspace/cache <> 'valid [			;-- only timer updates the view because of #4881
						#debug profile [prof/manual/start 'drawing]
						face/draw: render face					;@@ #5130 is the killer of animations
						unless system/view/auto-sync? [show face]	;@@ or let the user do this manually?
						#debug profile [prof/manual/end   'drawing]
					]
					exit										;-- timer does not need further processing
				]
				;@@ TODO: simulated hover-in and hover-out events to highlight items when hovering
				;@@ TODO: `enter` should be simulated because base face does not support it
				;@@ menu -- make context menus??
				;@@ select change  -- make these?
				; drag-start drag drop move moving resize resizing close  -- no need
				; zoom pan rotate two-tap press-tap   -- android-only?
				; create created  -- simulate these? (they're still undocumented mostly in View)
			] [exit]											;-- ignore unsupported events
			#debug events [print ["dispatch path:" path]]
			if path [
				#assert [block? path]							;-- for event handler's convenience, e.g. `set [..] path`
				;-- empty when hovering out of the host or over empty area of it
				;-- actually also empty when clicking outside of other spaces, so disabled
				; #assert [any [not empty? path  event/type = 'over]]
				process-event path event [] focused?
			]
		]
	]

	;-- used for better stack trace, so we know error happens not in dispatch but in one of the event funcs
	do-handler: function [spc-name [path!] handler [function!] path [block!] event [event! object!] args [block!]] [
		space: get first path: clone path cache/get			;-- copy in case user modifies/reduces it, preserve index
		code: compose/into [handler space path event (args) none] clear []
		trap/all/catch code [
			msg: form/part thrown 400					;@@ should be formed immediately - see #4538
			#print "*** Failed to evaluate (spc-name)!^/(msg)"
		]
		cache/put path
	]

	do-handlers: function [
		"Evaluate normal event handlers applicable to PATH"
		path [block!] event [event! object!] args [block!] focused? [logic!]
	][
		if commands/stop? [exit]
		hnd-name: to word! head clear change skip "on-" 3 event/type	;-- don't allocate
		wpath: path  unit: 1										;-- word-only path
		if pair? second path [
			hodl: obtain block! (length? path) / unit: 2			;-- need reentrancy because some events generate others
			wpath: extract/into path unit hodl						;-- remove pairs ;@@ should be `map` - extract is slow
		]
		#leaving [if hodl [stash hodl]]
		#assert [not find wpath pair!]
		len: length? wpath
		i2: either focused? [len][1]								;-- keyboard events should only go into the focused space
		;; this also needs reentrancy or e.g. up event closes the menu face, over event slips in and changes template
		template: change obtain path! 8 'handlers 
		#leaving [stash template] 
		;@@ TODO: this is O(len^2) and should be optimized...
		while [i2 <= len] [											;-- walk from the outermost spaces to the innermost
			;; last space is usually the one handler is intereted in, not `screen`
			;; (but can be empty e.g. on over/away? event, then space = none as it hovers outside the host)
			target: skip head path i2 - 1 * unit					;-- position path at the space that receives event
			do-previewers target event args
			
			unless commands/stop? [
				repeat i1 i2 [										;-- walk from the longest path to the shortest
					hpath:											;-- construct full path to the handler
						append append/part
						clear template 
						at wpath i1  skip wpath i2					;-- add slice [i1,i2] of path
						hnd-name
					unless block? try [list: get hpath] [continue]	;@@ REP #113
					commands/stop									;-- stop after current stack unless `pass` gets called
					foreach handler list [							;-- whole list is called regardless of stop flag change
						#assert [function? :handler]
						do-handler template :handler target event args	;@@ should handler index in the list be reported on error?
					]
				]
			]
			
			do-finalizers target event args
			i2: i2 + 1
		]
	]

	process-event: function [
		"Process the EVENT calling all respective event handlers"
		path  [block!] "Path on the space tree to lookup handlers in"
		event [event! object!] "View event or simulated"
		args  [block!] "Extra arguments to the event handler"
		focused? [logic!] "Skip parents and go right into the innermost space"
	][
		#debug profile [prof/manual/start 'process-event]
		unless commands/stop? [do-handlers path event args focused?]
		#debug profile [prof/manual/end 'process-event]
	]


	;-- pointer can only be captured by single space at a time, so this info is shared:
	drag-in: object [
		head: path: []									;-- `head` alias is needed to avoid a LOT of `head path` calls
		payload: none
	]
	

	dragging?: function [
		"True if in dragging mode"
		/from space [object!] "Only if SPACE started it"
	][
		case [
			empty? drag-in/head [no]
			not from [yes]
			name: drag-in/path/1 [space =? get name]
		]
	]
	
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
		#assert [
			spc =? spc'									;-- only makes sense to track it within the same space
			word? spc
			pair? ofs
			pair? ofs'
		]
		ofs - ofs'
	]

	;@@ export dragging functions or not? (they're available to event handlers anyway)

]

;-- toolkit available to every event handler/previewer/finalizer
;-- designed following REP#80 - commands, not return values
events/commands: context with events [
	;-- flag is local to each handler's call, so we have to use a hack here
	;@@ question here is what is the default behavior: pass the event further or not?
	;@@ let's try with 'stop' by default
	stop:    does [set bind 'stop?   :with-stop yes]	;-- used by previewers/finalizers
	stop?:   does [get bind 'stop?   :with-stop]
	pass:    does [set bind 'stop?   :with-stop no]		;-- stop is ignored for timer events ;@@ DOC it

	;-- the rest does not require a stack but should be available too
	dragging?:      :events/dragging?
	stop-drag:      :events/stop-drag
	start-drag:     :events/start-drag
	drag-path:      :events/drag-path
	drag-parameter: :events/drag-parameter
	drag-offset:    :events/drag-offset
]

