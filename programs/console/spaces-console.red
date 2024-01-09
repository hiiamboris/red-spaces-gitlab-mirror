Red [
	needs:       view
]
system/script/header: [											;@@ workaround for #4992
	title:       "Spaces Console"
	description: "Advanced REPL for Red built on top of Spaces"
	author:      @hiiamboris
	license:     {Distributed under the 3-clause BSD license}
]

;@@ `ask` and `input` aren't supported - how to implement them in this layout? extend log-entry?
;@@ console shortcuts - ls, pwd, etc - aren't implemented - need a plugin with them?

{	;@@ TODOs:
	save also size/offset ahead of crash
	session manager plugin to save/load logs
	faster printing
	scroller and list-view bugs need design fixes
	paragraph reordering
	undo/redo entries removal?
	
	;@@ somewhere on the horizon:
	paragraph grouping/structuring... -> step tracing
	Red inspector instead of mold output limiting
	live editing:
		As with libraries and modules, we should be able to work at low levels, then step up a layer and make sub-assemblies, design interfaces to those, test them, include them in a project, along with custom data interface needs and viewers; organize those elements for high level understanding and business use cases, allowing each person or team to work with their own custom environment but also see how people are using them. So it's not just a pre-config'd cloud IDE container with your dependencies, but a stack of views you can navigate, collaborating with people above and below the technical level you focus on.	 
}


#include %../../everything.red
; #do [disable-space-cache?: on]

;; stash native print before console-on-demand overrides it
spaces-console: context [
	native-prin:  :system/words/prin
	native-print: :system/words/print
	#assert [native? :native-print]
]

#include %../../../cli/console-on-demand.red
#process off

do/expand [
	#include %../../../cli/cli.red
	#include %../../widgets/document.red
	#include %../../../common/everything.red					;-- data-store is required, rest is there to make console more powerful
	#include %../../../red-src/red/environment/console/help.red	;-- for compiled access to help
]
system/console: spaces-console: make spaces-console with spaces/ctx expand-directives [
	~: self
	
	size: 80x1000												;-- terminal size in chars; only /x is normally used (set by row-draw)
	
	plugins: #()												;-- where plugins may put their contexts if they wish to
	
	state: #(
		size:    600x400										;-- last window size
		offset:  #[none]										;-- last window offset
		plugins: []												;-- plugins to auto load from data store
	)
	
	
	;; *************************************************
	;; **        P L U G I N S   S U P P O R T        **
	;; *************************************************
	
	;; hooks for plugins to extend: plugin itself is initialized before window is shown
	hooks: #(
		on-show:			[]									;-- nullary; after window is shown
		on-exit:			[]									;-- nullary; after window is closed
		on-editor-key:		[]									;-- [space path event]; in on-key event of the editor
		on-editor-key-down:	[]									;-- [space path event]; in on-key-down event of the editor
		on-log-key:			[]									;-- [space path event]; in on-key event of the log (list-view)
		on-log-key-down:	[]									;-- [space path event]; in on-key-down event of the log (list-view)
		;@@ more to come
	)
	do-hooks: function [
		"Evaluate a group of console hooks"
		group [word!]
		/with args [block!] "Provide a block of values for arguments"
	][
		call: compose [hook (only args)]
		for-each [name [word!]] hooks/:group [
			trap/all/keep/catch [hook: get name do call] [
				#print "on-show hook '(name)' failed:"
				print thrown
			]
		]
	]
	terminate: function [
		"Gracefully terminate the console"
		code [integer!] "Exit code"
	][
		do-hooks 'on-exit
		preserve-log
		data-store/save-state state
		quit-return code
	]

	;; where to look for plugins if not cloned locally (e.g. using binary release)
	plugin-repo: https://codeberg.org/hiiamboris/red-spaces/raw/branch/master/programs/console
	
	install-plugin: function [
		"Install or update a plugin from the file source (takes effect after console restart)"
		file [file!]
	][
		target: second split-path to-red-file file
		unless exists? file [									;-- try to fetch from web
			#print "Not found (file), trying to fetch from (plugin-repo/:target)..."
			file: plugin-repo/:target
		]
		text: read file
		unless parse text ["Red" to "[" to end] [
			ERROR "(target) is not a Red script!"				;-- mainly for typos and "Not found" page
		]
		data-store/write-file 'data target text
		include-into state/plugins target						;-- may already be there if updating
		data-store/save-state state
	]
	
	remove-plugin: function [
		"Remove plugin installed as file (takes effect after console restart)"
		file [file!]
	][
		target: second split-path to-red-file file
		exclude-from state/plugins target
		data-store/save-state state
	]
	
	load-plugin: function [
		"Load a plugin from local data store"
		file [file!]
	][
		loaded: data-store/load-file 'data file
		trap/catch loaded [#print "Failed to load '(file)' plugin:^/(thrown)"]
	]
	load-plugins: function ["Load all plugins from local data store"] [
		for-each [file [file!]] state/plugins [load-plugin file]
	] 
	
	
	;; *************************************************
	;; **       P R I N T I N G   S U P P O R T       **
	;; *************************************************
	
	;; need to capture print output into the log
	capture-output: function [
		"Evaluate code while appending all printed output to given target log entry"
		target [object!] ('log-entry = class? target) code [block!]
	][
		target/rows/output/set-text {}
		clear target/rows/output/extra-text
		do code
	]
	feed-output: function [
		"Append value to captured output"
		value [any-type!]
	] with :capture-output [
		row: target/rows/output
		text: append append row/get-text row/extra-text :value
		row/extra-text: either #"^/" = last text [form take/last text][{}]	;-- keep the last newline but never show it
		row/set-text text										;@@ need a lower level faster (without undo) setter
	]
	
	print: function [
		"Outputs a value followed by a newline"
		value [any-type!]
	][
		prin :value prin #"^/"
	]
	prin: function [
		"Outputs a value"
		value [any-type!]
	][
		if attempt [get bind 'target :capture-output] [			;-- check if wrapped by capture-output
			unless terminal/state [show-terminal]				;-- show on first print
			if any-list? :value [
				if block? :value [value: reduce value]
				value: form value
			]
			feed-output :value
		]
		native-prin :value
	]
	
	;; this should only be called after console-on-demand's own overrides are no longer needed (print, quit)
	fix-environment: function ["Adapt global natives and functions for console compatibility"] [
		system/words/print: :print
		system/words/prin:  :prin
		
		;; compatibility layer for compiled print-using code:
		;; (probe ? and ?? automatically work because they're redefined in Spaces)
		reload-func: function [path [any-word! any-path!]] [
			set path func spec-of get path body-of get path 
		]
		reload-func 'system/reactivity/eval
		reload-func 'system/words/clock
		reload-func 'system/words/dump-reactions
		reload-func 'system/lexer/tracer
		reload-func 'system/words/profile
		system/tools/tracers/emit: :print
		reload-func last body-of :system/words/parse-trace 

		;; state autosave
		system/words/q: system/words/quit: func spec-of :quit [
			terminate any [status 0]
		]
	]
	
	
	;; *************************************************
	;; **                     U I                     **
	;; *************************************************
	
	monofont: make font! [name: system/view/fonts/fixed]
	monofont-cell: (0.01, 1) * size-text						;-- used in console width estimation
		make rtd-layout reduce [append/dup {} "x" 100] [
			font: monofont
			size: none
		]
		
	declare-template 'log-editor/editor []						;-- replace generic template with a named one, for extensibility
	declare-template 'log-viewer/scrollable []
	; declare-template 'log-text/document []
	
	append focus/focusable 'log-viewer
	append focus/focusable 'log
	
	row-draw: function [row [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		drawn: row/tube-draw/on canvas fill-x fill-y			;-- have to draw a frame to estimate length
		either any [row/kind = 'input  row/document/length > 0] [
			if row/kind = 'input [
				;@@ for some reason width is bigger until first output is shown :/
				width: row/document/size/x - row/viewer/vscroll/size/x
				maybe ~/size/x: to integer! width / monofont-cell/x
			]
			drawn
		][
			set-empty-size row canvas fill-x fill-y
			return quietly row/map: copy []
		]
	]		
	
	row-kit: make-kit 'log-row/tube [
		tube-format: :format
		format: function [] [
			either space/document/length = 0 [
				copy {}
			][
				join container-ctx/format-items space " "
			]
		]
	]
	
	;; single log row - input, output or result
	declare-template 'log-row/tube [
		kit:		~/row-kit
		axes:		[→ ↓]
		align:		0x0
		spacing:	5
		
		;; inlined sub-spaces right here, for easier path access
		editor:      make-space 'log-editor [limits: none .. (1.#inf, 200)]
		viewer:      make-space 'log-viewer [content: editor/content  content-flow: 'vertical  limits: none .. (1.#inf, 200)]
		document:    editor/content
		prefix:      make-space 'text []
		suffix:      make-space 'text []
		left-field:  make-space 'box [limits: 20 .. 20 align: 0x-1 content: prefix]
		right-field: make-space 'box [limits: 20 .. 20 align: 0x-1 content: suffix]
		
		kind: 'input	#type [word!] (find [input output result] kind)
			#on-change [space word value] [
				center: switch value [input ['editor] output result ['viewer]]
				center: space/:center
				center/limits/max/y: select #(input 1.#inf output 400 result 120) value
				space/prefix/text: select #(input ">>" output "" result "==") value
				space/content: reduce with space [left-field center right-field]
			]
			
		extra-text: {}											;-- keeps trailing newline, which is never shown
		get-text: does [batch document [copy-range/text everything]]
		set-text: func [text [string!]] [
			text: trim/all/with copy text #"^M"					;-- fixes ^M char appearing in `help` output
			batch document [change-range everything text]
		]
		
		tube-draw: :draw
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			~/row-draw self canvas fill-x fill-y
		]
	]
	
	;; a group that enforces order - simplifies working with the log
	declare-template 'log-entry/cell [
		rows: context [											;@@ use map-each
			input:  make-space 'log-row [kind: 'input]
			output: make-space 'log-row [kind: 'output]
			result: make-space 'log-row [kind: 'result]
		]
		content: make-space 'list [
			axis:    'y
			spacing: 2
			content: values-of rows
		]
	]
	
	declare-template 'log/list-view [							;-- renamed for custom events
		behavior/draggable: 'scroll
		behavior/follows-cursor?: no							;-- this was meant for non-interactive items
	]
	
	#hide [
		foreach name [											;@@ this is highly inelegant
			log
			log/window/list/selection
			log/window/list/cursor
			log/window/list/item
		][
			new: to path! name
			change old: copy new 'list-view
			set-style new get-style old
		]
	]
	
	define-styles [
		log-entry/list/log-row/box/text:
		log-entry/list/log-row/log-editor/document/rich-content:
		log-entry/list/log-row/log-viewer/document/rich-content: [font: monofont]
		
		log-entry: [below: [push [line-width 0.3 box -2x-2 (size + 2) 3]]]
	]
	
	VID/styles/log: copy/deep VID/styles/list-view
	VID/styles/log/template: 'log
	
	
	;; *************************************************
	;; **             U I    S U P P O R T            **
	;; *************************************************
	
	;; log preservation/restoration
	log-modified?: no											;-- flag helps to avoid disk writes while inactive
	
	preserve-log: function ["Save current commands log"] [		;-- to restore after a crash or quit
		if log-modified? [
			commands: map-each entry log/source [entry/rows/input/get-text]
			data-store/save-file 'state %spaces-console.history commands
			self/log-modified?: no
		]
	]
	
	recover-log: function ["Restore commands log after a crash"] [
		commands: data-store/load-file 'state %spaces-console.history
		if empty? commands [commands: ["help"]]					;-- let help be the default starter's command
		log/source: map-each [/i command] commands [
			also entry: make-space 'log-entry []
			entry/rows/input/set-text command
		]
	]
	
	clear-log: function ["Empty console log"] [
		entry: first log/source
		set-focus entry/rows/input/document						;@@ could've been simpler if I could focus a newly created space
		foreach row values-of entry/rows [row/set-text {}]
		log/anchor/index: 1
		log/anchor/reverse?: no
		clear next log/source
	]
	
	evaluate: function [
		"Evaluate command in given log entry"
		entry [object!] ('log-entry = class? entry)
	][
		; if 0 < entry/rows/input/document/length [
			; entry/rows/input/suffix/text: copy "⏳"
			; do-queued-events									;@@ needs more work! fails when pasting things
			; loop 10 [do-events/no-wait]							;@@ this works better but still unreliable
		; ]
		text: entry/rows/input/get-text
		set/any 'result trap/all/keep/catch [
			capture-output entry [
				fcatch/handler [thrown = 'halt-request] [		;-- fcatch/pcatch do not support /name kludge :(
					do text
				] [print "(halted)"]							;-- unset result
			]
		] [error: thrown]
		; entry/rows/input/suffix/text: copy ""
		;@@ trim newlines in a fast way
		; while [#"^/" = last output] [take/last output]			;@@ trim/tail/with is useless - REP #52 
		; entry/rows/output/set-text output 
		entry/rows/result/set-text case [
			error [form result]
			unset? :result [{}]
			'else [mold :result]
		]
		:result
	]
	
	;@@ maybe chain it? evaluated N - evaluate N + 1?
	evaluate-since: function [
		"Evaluate all commands since given log entry; return last evaluated"
		entry [object!] "(can be a child of log-entry)"
	][
		if 'log-entry <> class? entry [entry: above entry 'log-entry]
		foreach entry find/same log/source entry [evaluate entry]
	]
	
	into-editor: function [
		"Focus the editor of log entry"
		entry [object!] "(can be a child of log-entry)"
	][
		if 'log-entry <> class? entry [entry: above entry 'log-entry]
		set-focus entry/rows/input/document
	]
	
	into-adjacent-entry: function [
		"Focus next entry input in the log (creates one if no next)"
		entry  [object!] "Add after this one (can be a child of log-entry)"
		offset [integer!]
	][
		if 'log-entry <> class? entry [entry: above entry 'log-entry]
		parent: entry/parent
		any [
			all [
				there: apply 'find [log/source entry /same on /tail offset > 0]
				entry: pick there offset
			]
			if offset > 0 [
				append log/source entry: make-space 'log-entry []
				invalidate parent
				render host-of parent							;@@ required by set-focus atm :(
			]
			return none											;-- don't append when going up
		]
		into-editor entry
		batch log [frame/move-to/before length]
		entry
	]
	
	get-last-entry: function ["Return last non-empty logentry (or first empty if they are all empty)"] [
		repeat i n: length? log/source [
			entry: pick log/source n - (i - 1)
			if entry/rows/input/document/length > 0 [break]
		]
		entry
	]
	
	
	;; *************************************************
	;; **              U I    E V E N T S             **
	;; *************************************************
	
	define-handlers [
		;; for console touch-friendly dragging is hardly useful, but multi-item dragging-selection is
		log: extends 'list-view [
			on-key-down [space path event] [
				~/log-modified?: yes							;-- turn on next log save
				case [
					all [event/ctrl? event/key = #"L"] [clear-log]
					all [										;-- for removing selected log rows
						event/key = 'delete
						empty? event/flags
					][
						foreach i sort/reverse copy space/selected [
							unless single? log/source [remove at log/source i]	;-- don't remove the last entry
						]
						trigger 'log/source
					]
				]
				do-hooks/with 'on-log-key-down reduce [space path event]
			]
			on-key [space path event] [
				all [											;-- enter activates the editor at cursor
					event/key = #"^M"
					empty? event/flags
					i: space/cursor
					entry: pick space/source i
					into-editor entry
				]
				do-hooks/with 'on-log-key reduce [space path event]
			]
		]  
		
		log-viewer: extends 'scrollable [
			on-key-down [space path event] [
				if char? event/key [into-editor space]
			]
			document: [											;@@ design problem: this one should not be focusable
				on-key-down [space path event] [
					case [
						any [char? event/key event/key = 'up] [
							into-editor space
						]
						event/key = 'down [into-adjacent-entry space 1]
					]
				]
			]
		]
		
		log-editor: extends 'editor [
			document: extends 'editor/document [
				on-key-down [space path event] [
					~/log-modified?: yes						;-- turn on next log save
					case [
						all [
							event/key = 'up
							caret: batch space [locate 'row-head]	;@@ need higher level tests, e.g. top-row/bottom-row
							caret/offset = 0
						][
							into-adjacent-entry space -1
							stop/now							;-- don't let document get this event
						]
						all [
							event/key = 'down
							caret: batch space [locate 'row-tail]
							caret/offset = batch space [length] 
						][
							into-adjacent-entry space 1
							stop/now
						]
						all [event/ctrl? event/key = #"L"] [
							clear-log
							stop/now
						]
					]
					do-hooks/with 'on-editor-key-down reduce [space path event]
				]
				on-key [space path event] [
					if empty? event/flags [ 
						switch event/key [
							#"^M" [								;-- enter key evaluates
								evaluate-since space
								into-adjacent-entry get-last-entry 1
								stop/now
							]
							#"^[" [set-focus above space 'log]	;-- esc key focuses the log
						]
					]
					do-hooks/with 'on-editor-key reduce [space path event]
				]
			]
		]
	]

	;; I can't leverage reactivity or 'clear-reactions' will break the console, have to rely on events
	on-terminal-resize: function [terminal event] [
		maybe host/size: terminal/size - 4
		state/size:      terminal/size
		state/offset:    terminal/offset						;@@ required - see #5452
	]
	on-terminal-move:   function [terminal event] [
		state/offset:    terminal/offset
	]
	
	
	;; *************************************************
	;; **        I N I T I A L I Z A T I O N          **
	;; *************************************************
	
	log: host: none												;-- keep these in context, not global (assigned in view)

	terminal: none
	
	init-terminal: function ["Createconsole REPL window" /extern host log] [	;-- should be called after plugins are loaded
		~/terminal: layout/flags/options reshape [
			title @(`"Spaces Console 🚀 (#do keep [now/date])"`) 
			on-resize :on-terminal-resize on-resizing :on-terminal-resize
			on-move   :on-terminal-move   on-moving   :on-terminal-move
			origin 2x2
			host: host with [size: ~/state/size - 4 rate: 34] [		;-- decreased rate for less resource usage
				log: log multi-selectable source= lay-out-vids [log-entry] 
				rate= 0:0:3 on-time [preserve-log]
			]
		] 'resize [offset: ~/state/offset]
	]
	
	show-terminal: function ["Display console REPL window"] [
		#assert [terminal]
		view/no-wait terminal
		loop 5000 [do-events/no-wait]							;@@ focus kludge - fixme (otherwise fails in window-of randomly!)
		try [set-focus log/source/1/rows/input/document]		;@@ but just in case: let rather focus fail than startup
		do-hooks 'on-show
	]
	
	startup: function ["CLI entry point"] [
		repl: function [
			"Advanced REPL for Red built on top of Spaces"
			script [file! block!]
			/reset "Run console with no state (use in case it's broken)"
			/catch "If script is given, don't close after it finishes"
		][
			;; load state unless disabled
			either reset [
				file: data-store/make-path 'state rejoin [
					as file! data-store/script-name ".state"
				]
				if exists? file [								;-- make a state backup, as it will be overwritten
					try [write rejoin [file ".bak"] read file]
				]
			][
				~/state: data-store/load-state/defaults state
				;; plugins require context declared, but window shouldn't be shown yet - so they can modify styles etc
				load-plugins
			]
			
			fix-environment
			init-terminal										;-- required to print into
			either script-args [
				system/script/args: form append reduce [system/options/boot] script-args	;@@ unreliable composition
				remove/part system/options/args next script-args 
				capture-output log/source/1 [do script/1]
			][
				recover-log
			]
			if any [											;-- show terminal if:
				catch											;-- explicitly requested
				not script-args									;-- no script given
				terminal/state									;-- script printed anything
			][
				unless terminal/state [show-terminal]			;-- may have been shown by a print call; calls 'on-show' hooks
				do-events
			] 
			terminate 0											;-- calls 'on-exit' hooks
		]
	
		script-args: none
		args: map-each/drop [pos: arg] system/options/args [	;-- extract only arguments for the console itself
			if script-args [break]
			unless find/match arg "-" [script-args: next pos]
			arg
		]
		cli/process-into/args 'repl args
	]
]	

if system/platform <> 'Windows [								;-- needed to disarm kludges included into `quit` function
	set '_save-cfg none
	set '_terminate-console none
]
spaces-console/startup
