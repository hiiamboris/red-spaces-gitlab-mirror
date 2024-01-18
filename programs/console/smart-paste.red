Red [
	title:   "Smart clipboard paste plugin for Spaces Console"
	purpose: "Decode outside console output as commands (using >> and == markers)"
	author:  @hiiamboris
	license: BSD-3
]

system/console/plugins/smart-paste: context with spaces/ctx [
	~: self
	
	;; these allow to paste external examples directly into console (except for brackets - idk how to handle them)
	multi-command?: function [
		"Test if data from the clipboard contains multiple commands"
		data [object!]
	][
		to logic! all [
			data/name = 'text
			find/match data/data ">> "
		]
	]
	
	decode-clipboard: function [
		"Convert formatted multi-command clipboard text into a raw command list"
		data [object!]
	][
		if data/name = 'text [
			data: data/clone
			parse data/data [any [
				remove ">> " thru [#"^/" | end]					;-- remove only prefix for commands
			|	remove thru [#"^/" | end]						;-- remove output and result totally
			]]
		]
		data/format
	]
	
	paste-commands: function [
		"Paste clipboard data into the console log, decoding if it's formatted"
		data [object!]
	][
		text: data/format
		cmds: either multi-command? data
			[split decode-clipboard data #"^/"]
			[reduce [data/format]]
		foreach cmd cmds [
			if empty? cmd [continue]
			append spaces-console/log/source entry: make-space 'log-entry []
			batch entry/rows/input/document [insert-items 0 cmd]
			first-entry: any [first-entry entry]
		]
		if first-entry [spaces-console/evaluate-since first-entry]
	]
	
	on-log-paste: function [space path event] with events/commands [
		if all [event/ctrl? event/key = #"V"] [
			if data: clipboard/read [paste-commands data]
		]
	]
	on-editor-paste: function [space path event] with events/commands [
		if all [event/ctrl? event/key = #"V"] [
			stop/now											;-- disable editor's internal paste
			unless data: clipboard/read [exit]
			either multi-command? data [						;-- paste multiple commands as entries
				paste-commands data
			][
				text: data/format								;-- paste single command as text
				#assert [string? text]
				batch space [
					remove-range selected
					insert-items here text
				]
			]
		]
	]
	append spaces-console/hooks/on-log-key-down    'on-log-paste 
	append spaces-console/hooks/on-editor-key-down 'on-editor-paste 
]