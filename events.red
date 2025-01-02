Red [
	title:    "Event processing for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.events
	depends:  [spaces.auxi spaces.macros  global with error map-each reshape advanced-function]
]


events: context [
	;; original (but split) event sheets tree, used for inheritance:
	;; each sheet is a map with fields:
	;;   scope    = path of original definition (block of set-words and refinements only)
	;;   ancestor = from where to inherit events (template name as word/path, or none)
	;;   order    = [below | above] (word, or none)
	;;   source   = original of event handlers (only) sheet (block)
	;;   handlers = compiled event handlers matrix (map of id -> func)
	sheets:     make map! 50
	
	;; compiled event handlers matrix tree, optimized for lookup speed (uses reversed paths):
	;; each matrix item resolves to a #value -> block! [path! path! ...] = a list of sheet paths
	;; each included sheet path resolves to a /handlers compiled event matrix (map of id -> func)
	;; paths are resolved in left to right order when sinking, right to left when bubbling
	handlers:   make map! 50
	
	;; reference data and support functions
	support:    none
	
	;; stuff related to event encoding
	encoding:   none
	
	;; stuff related to the define-handlers dialect
	dialect:    none
	
	;; stuff related to sheet and matrix storage and lookups
	storage:    none
	
	;; the very core of event processing
	processing: none
	
	;; "commands" available to each event handler function
	commands:   none

	;; the highest level event definition function
	global define-handlers: function [
		"Define event handlers using Event DSL"
		sheet [block!]
	][
		paths: storage/load-sheet sheet
		;; separate load phase allows to be independent of definition order:
		foreach path paths [storage/load-handlers/deep path]
	]
]


;; reference data and support functions
events/support: context [
	event-types: make hash! [
		time
		over wheel up mid-up alt-up aux-up
		down mid-down alt-down aux-down click dbl-click
		key key-down key-up enter
		focus unfocus
	]
	pointer-event-types: make hash! [
		over wheel up mid-up alt-up aux-up
		down mid-down alt-down aux-down click dbl-click
	]
	event-flags: make hash! [
		control alt shift
		down alt-down mid-down aux-down
	]
	
	is-pointer-event?: function [type [word!]] [
		to logic! find pointer-event-types type
	]
	is-valid-event?: function [type [word!]] [
		to logic! find event-types type
	]
	is-valid-flag?: function [type [word!]] [
		to logic! find event-flags type
	]
]

	
;; functions for event data encoding
events/encoding: context with events [
	encode-type: function [
		"Get a numeric code for given event TYPE"
		type    [word!]    "E.g. 'over"
		return: [integer!] "In range [1..255]"
	][
		index? any [
			find support/event-types type
			ERROR "Unsupported event type '(type)' encountered"
		]
	]									

	encode-flag: function [
		"Get a bitmask for given event FLAG"
		flag    [word!]    "E.g. 'shift"
		return: [integer!] ">= 256"
	][
		256 << skip? any [
			find support/event-flags flag
			ERROR "Unsupported event flag '(flag)' encountered"
		]
	]									

	encode-flags: function [
		"Get a bitmask for a set of event FLAGS"
		flags   [block!]
		return: [integer!]
	][
		mask: 0
		foreach flag flags [mask: mask or encode-flag flag]		;@@ use 'accumulate'?
		mask
	]									

	encode-event: function [									;-- has to be fast, for constant runtime use
		"Obtain unique id of the event for event sheet mapping"
		type    [word!]
		flags   [block!]
		return: [integer!]
	][
		(encode-type type) or (encode-flags flags)
	]

	#assert [
		1		= encode-event 'time []
		3074	= encode-event 'over [shift down]
		error? try [encode-event 'over [garbage]]
	]
	
	list-ids: function [
		"List all permitted event ids with given TYPE and required FLAGS"
		type    [word! none!] "Use 'none' to list all possible types"
		flags   [block!]
		return: [block!]
	][
		result: clear []
		req-mask: encode-flags flags
		types: either type
			[reduce [encode-type type]] 
			[list 1 thru ntypes: length? support/event-types]
		repeat i 1 << nflags: length? support/event-flags [
			mask: i - 1 << 8
			if mask or req-mask = mask [
				foreach type types [append result id: type or mask]
			]
		]
		copy result
	]
	
	#assert [
		[3330 3842 7426 7938 11522 12034 15618 16130 19714 20226 23810 24322 27906 28418 32002 32514]
			= list-ids 'over [shift control down]
		2000 < length? list-ids none []
	]
]
	

;; define-handlers dialect support
events/dialect: context with events [ 
;@@ ^ temporary(?) 'with' kludge
; events/dialect: context [ 

	;; rules for strict syntax checking and error reporting
	grammars: object [
		~~p: none												;-- ~~p used by #expect :(
		handlers: object [
			w: none
			=type=:     [set w word! if (support/is-valid-event? w)]
			=flag=:     [set w word! '+ if (support/is-valid-flag? w)]
			=mask=:     [some [opt '* any =flag= =type= opt paren!] | '*]	;-- single '*' can only be a standalone mask, and has no args
			=handler=:  [=mask= #expect block!]
		]
		groups: object [
			=names=:    [some [set-word! | refinement!]]
			=ancestor=: [ahead word! ['above | 'below] #expect [lit-word! | lit-path!]]
			=group=:    [=names= opt =ancestor= #expect block!]
		]
		sheet: with handlers with groups [any [end | #expect [=group= | =handler=]]]
		scope: groups/=names=
	]
	
	decode-mask: function [
		"Decode a Handlers DSL event MASK into a map"
		mask    [block!] "E.g. [* shift + key]"
		return: [map!]   "#[type [word! none!] flags [block!] args [block!] fuzzy? [logic!]]"
		/local flags args code ids
	][
		=type=:  [set type [not '* word!]]
		=flag=:  [ahead [not '* word! '+] keep word! '+]
		=flags=: [collect set flags any =flag=]
		=args=:  [set args opt paren! (args: to [] only args)]
		=code=:  [set code #expect block!]
		=mask=:  [
			'* =flags= =type=   (fuzzy?: yes)
		|	'* (flags: copy []) (fuzzy?: yes)
		|	   =flags= =type=   (fuzzy?: no)
		]
		parse mask [#expect =mask= =args= #expect [end | block!]]	;-- block is left for in-line decoding of the dialect
		as-map [type: flags: args: fuzzy?:]
	]
	
	#assert [
		#[
			type:	#(none)
			flags:	[]
			args:	[]
			fuzzy?:	#(true)
		] = decode-mask [*]
		#[
			type:	down
			flags:	[]
			args:	[]
			fuzzy?:	#(false)
		] = decode-mask [down]
		#[
			type:	over
			flags:	[shift]
			args:	[arg]
			fuzzy?:	#(false)
		] = decode-mask [shift + over (arg)]
		error? try [decode-mask []]
		error? try [decode-mask [* shift +]]
		error? try [decode-mask [* + over]]
		error? try [decode-mask [* * over]]
	]
	
	split-sheet: function [
		"Split Event DSL sheet into two parts: children and event handlers"
		sheet   [block!]
		return: [block!] "[children handlers]"
	][
		;; since it is the only func with access to the original block, it also has to report syntax errors:
		parse sheet grammars/sheet
		
		;; then after the check, parse rules can be relaxed:
		children:   clear []
		handlers:   clear []
		=nested=:   [collect after children keep pick [[set-word! | refinement!] thru block!]]
		=handler=:  [collect after handlers keep pick [word! thru block!]]
		parse sheet [any [=handler= | =nested=]]
		reduce [copy children copy handlers]
	]
	
	#assert [
		[[a: b: [1] c: [3]] [* [2]]] = split-sheet [a: b: [1] * [2] c: [3]]
	]
	
	; parse-children: function [
		; "Parse a children sheet and return them as a map: name -> sheet"
		; children [block!]
		; return:  [map!] "Keys are words and refinements"
	; ][
		; groups: object [
			; =names=:    [some [set-word! | refinement!]]
			; =ancestor=: [ahead word! ['above | 'below] #expect lit-word!]
			; =group=:    [=names= opt =ancestor= #expect block!]
		; ]
		; sheet: with handlers with groups [any [end | #expect [=group= | =handler=]]]
	; ]

	compile-handler: function [
		"Make an event handler function out of a [type args body] BLOCK in given tree PATH"
		scope [block!] (parse scope grammars/scope)
		type  [word!] "Only needed to decide if path argument contains coordinates"
		args  [block!]
		body  [block!]
		/local w
	][
		offsets?: support/is-pointer-event? type
		
		;; offset is negative for nested handlers
		offset: 1 - length? scope
		
		;; innermost set-word determines the kit to use - may differ between scopes
		target: find/last scope set-word!
		
		;; names add support for using template names in the handlers
		names: parse scope [collect some [set w skip keep (to set-word! w)]]	;@@ use map-each
		
		args:  parse args  [collect any  [set w skip keep (to set-word! w)]]	;@@ use map-each
		
		bind body commands
		; spec: compose [event (args)]
		body: reshape [
			processing/fill-args event path @[args]	/if not empty? args	;@@ or pass args after the event?
			set @[names] skip path @[offset]		/if offset <> 0
			@[names/1] path/1						/if offset = 0
			using @[to word! target/1] @[body]		/if target		;-- expose body to the kit
			@(body)									/if not target	;-- only refinements in the scope? no kit then
		]
		function [event path] new-line body on
	]
	
	;; max mask size atm is ~115kB (5000 k/v pairs)
	compile-sheet: function [
		"Create an event matrix out of Handlers DSL sheet"
		scope   [block!] "Scope for the handler functions" (parse scope grammars/scope)
		sheet   [block!] "Handlers only: [event masks (extra arguments) [code] ...]"
		return: [map!]   "A map! of: event id -> function"
		/local _ masks code
	][
		matrix:  clear #[]										;-- static matrix to lessen RAM load
		=mask=:  [opt '* not '* word! any ['+ word!] opt paren! | '*]
		=masks=: [collect set masks some [ahead word! keep copy _ =mask=]]
		=code=:  [set code block!]
		process: [
			foreach mask masks [
				map: decode-mask mask
				ids: either map/fuzzy?
					[encoding/list-ids map/type map/flags]
					[reduce [encoding/encode-event map/type map/flags]]
				fun: compile-handler scope map/type map/args code
				foreach id ids [matrix/:id: any [:matrix/:id :fun]]	;-- late definitions do not override the previous ones
			]
		]
		parse sheet [any [end | #expect =masks= #expect =code= (do process)]]
		copy&clear matrix										;-- always clear static sheet to free references to code
	]
	
	; extend-matrix: function [
		; "Extend an exisitng event MATRIX with a new SHEET"
		; matrix [map!]   "Map of id -> function"
		; sheet  [block!] "[event mask [code] ...]"
	; ][
		; extend compile-event-sheet spec sheet
	; ]
	
]
	

;; events/handlers matrix: storage and lookups
events/storage: context with events [

	fetch-handlers: function [
		"Retrieve a LIST of event handler matrix paths for the given tree PATH in events/handlers"
		path    [path! block! word!]
		return: [block! none!]
	][
		attempt [fetch-path-value/reverse events/handlers path]
	]
	
	store-handlers: function [
		"Store a LIST of event handler matrix paths for the given tree PATH in events/handlers"
		path [path! block! word!]
		list [block!] (parse list [any path!])				;-- each item: events/sheets/.../#value -> sheet (map!)
	][
		trees/store-path-value/reverse events/handlers path list
	]
	
	find-handlers: function [
		"Find the most specialized event handlers sequence for the given tree PATH in events/handlers"
		path    [block! path! word!]    "Reversed before lookup"
		/part n [integer! block! path!] "Match only a part of the path"
		return: [block! none!]
	][
		trees/match-path/:part events/handlers path n
	]
	
	;; events/sheets tree storage
	
	store-sheet: function [
		"Store a parsed event handlers SHEET for the given tree PATH in events/sheets"
		path  [path! block! word!]
		sheet [map!]
	][
		trees/store-path-value events/sheets path sheet
	]
	
	fetch-sheet: function [
		"Retrieve the event sheet for a given tree PATH in events/sheets"
		path    [path! block! word!] "Should exist in events/sheets map"
		return: [map!]
	][
		get trees/make-access-path 'events/sheets path
	]
	
	;@@ this has a lot of /dialect-related code, but idk how to extract it
	load-sheet: function [
		"Parse an event sheet, compile it and store it in the events/sheets tree"
		sheet [block!] "May contain event handlers as well as child sheets"
		;; refinements are needed for recursion mainly:
		/in scope: (make [] 4) [block!] (parse scope dialect/grammars/scope)
		/from
			order    [word!] (find [below above] order)
			ancestor [path! (parse ancestor [some word!]) word!]
		/into paths: (make [] 4) [block!] "Where to put a list of modified tree paths" 
		return: [block!] "Paths list is returned, including children"
		/local w name
	][
		set [children: source:] dialect/split-sheet sheet
		if all [empty? scope not empty? source] [ERROR "No handlers allowed at the root level"]
		
		;; create and store the sheet as a tree leaf
		unless empty? source [
			scope:    new-line/all copy scope no			;-- store the original set-word/refinement scope
			handlers: dialect/compile-sheet scope source
			store-sheet
				path: mapparse [set w skip] to path! scope [to word! w]	;@@ use map-each when fast
				map:  as-map [scope: order: ancestor: source: handlers:]
			append/only paths path
		]
		
		unless empty? children [
			=fetch=:    [ahead [some =name= opt [=order= =ancestor=] set sheet block!]]
			=process=:  [some [set name =name= (do dive)] opt [=order= =ancestor=] block!]
			=name=:     [set-word! | refinement!]
			=order=:    [set order ['above | 'below]]
			=ancestor=: [set ancestor [lit-word! | lit-path!]]
			=group=:    [(do reset) =fetch= =process=]
			reset:      [order: ancestor: none]
			dive:       [
				append scope name
				apply 'load-sheet [sheet /in on scope /from order order do ancestor /into on paths]
				take/last scope
			]
			parse children [any [end | #expect =group=]]
		]
		unique paths										;-- for load-handlers use; unique to avoid reloading of the same subtrees
	]
	
	load-handlers: function [
		"Export an event sheet from given PATH in events/sheets into events/handlers"
		path [path! block! (parse path [some word!]) word!]
		/deep "Also load handlers of all children"
	][
		if deep [
			path:  to [] path								;-- copy it, will be modified
			scope: get trees/make-access-path/scope 'sheets path
			foreach [key value] scope [						;-- use for-each [key [word!] value] for filtering
				if key = #value [continue]
				append path key
				load-handlers/deep path
				take/last path
			]
		]
		
		sheet: get full-path: trees/make-access-path 'sheets path
		append full-path 'handlers
		list: reduce [full-path]
		while [sheet/order] [
			#assert [find [below above] sheet/order]
			#assert [find [word! path!] type?/word sheet/ancestor]
			commit: switch sheet/order [above [:append] below [:insert]]
			sheet:  get full-path: trees/make-access-path 'sheets sheet/ancestor
			commit/only list (append full-path 'handlers)
		]
		store-handlers path list
		list
	]
]
		

;; the very core of event processing
events/processing: context with events [

	;; chain of event processors, each is a func [event [map!]]
	pipeline:   make [] 16
	
	;; each map is: event-type -> list of funcs
	;; each previewer/finalizer should also be a func [event [map!]]
	previewers: make #[] map-each/eval type support/event-types [[type copy []]]
	finalizers: make #[] map-each/eval type support/event-types [[type copy []]]
	
	
	;; main entry point from the scheduler into event processing
	dispatch: function [
		"Dispatch host event along the events pipeline"
		event [map!]
	][
		prepare-event event
		foreach proc pipeline [proc event]
	]
	
	prepare-event: function [
		"Fill in additional fields of the event (when applicable)"
		event [map!] "(modified)"
	][
		event/id: encoding/encode-event event/type event/flags	;-- used for fast lookups in event matrices
		event/done?: no											;-- only a marker for some event processors
		event/direction: 'down									;-- used to avoid duplicate 'sink' calls
		switch/default event/type [
			@(to [] support/pointer-event-types) [
				event/hittest: hittest event/face event/offset
				event/path:    keep-type event/hittest object!
			]
			key key-down key-up focus unfocus [
				event/path: get-host-path keyboard/focus
			]
			; time []
		][
			event/path: reduce [event/face]
		]
		event/lookup: lookup: copy event/path					;-- path of words (types) used for handler lookups
		forall lookup [lookup/1: lookup/1/type]					;@@ use map-each when fast ;@@ any better name than /lookup?
	]
	
	;@@ it's possible to split this func into multiple per-event-type - worth it?
	fill-args: function [										;-- called from inside event handlers 
		"Fill given words with arguments specific to given EVENT type"
		event [map!]
		path  [block!]
		args  [block!]
	][
		switch event/type [
			time [
				timer: path/1/timer
				dt: difference timers/time timer/planned
				set args 100% * (dt / timer/period)
			]
			@(to [] support/pointer-event-types) [
				xy: pick event/hittest 2 * index? path
				; dxy: ???
				set args xy
			]
			key key-down key-up [
				set args event/key
			]
			; focus unfocus [
			; ]
		]
	]
	
	;; the point of this func is to form a basis for the equivalence
	;; of parent/child and ancestor/descendant relationships
	;; so that 'sink'&'bubble' work similarly in both scenarios
	;; it doesn't test against event/id, because it's convenient for timers this way
	list-handlers: function [
		"List all now existing handlers for given event parameters"
		path   [block!] (not empty? path)
		lookup [block!] (equal? length? path length? lookup)
		/target "Omit all parents, list only for the innermost child"
		return: [block!] "[handler-path event-path ...] list"
	][
		if target [path: top path]
		handlers: clear []
		forall path [
			if sequence: storage/find-handlers/part lookup index? lookup [
				foreach handler-path sequence [
					append/only append/only handlers handler-path path
				]
			]
		]
		copy handlers			
	]
	
	sink-event: function [	
		"Evaluate next handler for the EVENT and 'stop' unless 'bubble' is called"
		event    [map!]
		handlers [block!] "[handler-path event-path ...] remaining"
	][
		catch/name [
			foreach [handler-path event-path] handlers [
				if handler: select (get handler-path) event/id [
					do-handler :handler event event-path
					commands/stop								;-- both error and success of a handler = automatic full stop
				]
			]													;-- no handler found for given id = same as 'bubble'
		] 'bubble												;-- 'bubble' may resume the upper 'sink' call
	]

	do-handler: function [
		"Evaluate an event handler with its errors trapped safely and reported"
		handler [function!] "func [event [map!] path [block!]]"
		event   [map!]      "Event to pass to the handler"
		path    [block!]    "Path to pass to the handler"
		/type type': "handler" [string!] "Specify handler type (for error reports only)"
	][
		trap/keep/catch [handler event path] [
			lookup: map-each obj path [obj/type]				;-- infer lookup path used
			#print "*** Error in '(event/type)' (type') for (lookup)^/(thrown)"
			?? handler
			;@@ should erroneous handlers be disabled after 1-2-3 errors?
		]														;-- errors are contained inside each individual handler
	]
	
	do-handlers: function [
		"Evaluate a predefined list of event handlers"
		event    [map!]
		handlers [block!] "[handler-path event-path ...] pairs"
	][
		catch/name [sink-event event handlers] 'stop			;-- unknown throws pass through (e.g. halt)
	]
	
	do-sink+bubble: function [
		"Common event processing: sink an event then bubble it up"
		event [map!]
	][
		if event/type = 'time [exit]							;-- timers are not sunk/bubbled
		do-handlers event list-handlers event/path event/lookup
	]
	
	do-global: function [
		"Internal wrapper for previewers and finalizers evaluation"
		array [map!]
		event [map!]
	][
		type: pick ["previewer" "finalizer"] array =? previewers
		foreach handler array/(event/type) [
			catch/name [
				do-handler/type :handler event event/path type
			] 'stop												;-- 'stop' may stop sinking but never other previewers/finalizers 
		]
	]
	
	do-previewers: function [
		"Carry event through the previewers list"
		event [map!]
	][
		do-global previewers event
	]
	
	do-finalizers: function [
		"Carry event through the finalizers list"
		event [map!]
	][
		do-global finalizers event
	]
	
	do-render: function [
		"Do host rendering: for timers only"
		event [map!]
	][
		unless event/type = 'time [exit]						;-- rendering is only done on time event
		canvas: copy #[size: (0,0) axis: xy mode: fill]
		canvas/size: event/face/size
		rendering/render-host event/face canvas					;-- render assigns host/draw on its own
	]
	
	;@@ move this into scheduler instead? and remove host/on-time?
	do-timers: function [
		"Singular event processing: for timers only"
		event [map!]
	][
		if event/type = 'time [timers/fire]						;-- this only handles timers
	]
	
	arm-timer: function [
		"Arm the SPACE's TIMER and set its code to call the relevant on-time handler"
		space [object!]
		timer [map!]
		/now "Make it fire ASAP (if inactive only)"
	][
		lookup: append clear [] path: get-host-path space		;-- prefetch tree path to save time on timer evaluation
		forall lookup [lookup/1: lookup/1/type]					;@@ use map-each
		handlers: list-handlers/target path lookup				;-- list handlers at arm time, not at timer fire time (optimization)
		timer/code: compose/only [do-handlers (bind 'event :do-timers) (handlers)]
		timers/arm/:now timer
	]
	
	disarm-timer: function [
		"Disarm the SPACE's TIMER"
		space [object!] "(unused for now)"
		timer [map!]
	][
		timers/disarm timer
	]
		

	;; here it makes sense to place 'do-render' after 'do-timers' (both are on the 'time' event)
	;; so that timers may make changes to the layout and it may be updated immediately
	;; other events will have to wait for the next 'time' event for changes to have effect
	repend clear pipeline [:do-previewers :do-sink+bubble :do-timers :do-finalizers :do-render]

	register-as: function [
		"Internal wrapper for previewers and finalizers registering"
		array   [map!]
		mask    [block!]    "List of event types"
		handler [function!] "func [event [map!]]"
		/priority "Put before other previewers"
	][
		action: either priority [:insert][:append]
		foreach type mask [
			#assert [find support/event-types type]
			bind body-of :handler commands
			action array/:type :handler
		]
	]
	
	global register-previewer: function [
		"Add HANDLER into the event previewers sequence"
		mask    [block!] "List of event types"
		handler [function!] "func [event [map!]]"
		/priority "Put before other previewers"
	][
		register-as/:priority previewers mask :handler
	]
	
	global register-finalizer: function [
		"Add HANDLER into the event finalizers sequence"
		mask    [block!] "List of event types"
		handler [function!] "func [event [map!]]"
		/priority "Put before other finalizers"
	][
		register-as/:priority finalizers mask :handler
	]
]


;; hints on commands design and operation:
;; 'sink' evaluates and returns so the parent handler can resume itself
;;   just a recursively called function, initiated by 'do-sink+bubble'
;;   throws a 'stop' exception if next handler fails (errors out) or returns/exits
;;   but automatically exits (bubbles up) if event/done? is set
;; 'bubble' has to throw to get out of the possible inner function calls, but stop at handler level
;;   caught by 'sink-event', so it can then resume the upper handler
;; 'stop' has to throw to get out of the possible inner function and all handler calls
;;   caught by 'do-handlers' and its wrappers ('do-sink-bubble', 'do-previewers/finalizers')
events/commands: context with events/processing [
	sink:   does with :sink-event [
		unless event/done? [sink-event event next next handlers]	;@@ or throw an error on double sink attempt?
	]
	bubble: does with :sink-event [
		throw/name event 'bubble								;@@ maybe use fcatch? but throw/name is faster
	]
	stop:   does with :sink-event [
		event/done?: yes
		throw/name event 'stop
	]
]
			

#hide [#assert [												;-- this test requires 'commands' defined
	[1288 14088 4872 5896 6920 7944 13064 15112 16136 21256 22280 23304 24328 29448 30472 31496 32520]
	= keys-of sheet: events/dialect/compile-sheet [abc: /def] [
		shift + control + down [1]
		mid-down + alt-down + alt + shift + control + down [2]
		* alt + control + alt-down + down [3]
	]
	code1: events/encoding/encode-event 'down [shift control]
	code2: events/encoding/encode-event 'down [mid-down alt-down alt shift control]
	code3: events/encoding/encode-event 'down [aux-down alt-down alt control]
	find/only body-of select sheet code1 [1]
	find/only body-of select sheet code2 [2]
	find/only body-of select sheet code3 [3]
]]

