Red [
	title:   "TAB completion plugin for Spaces Console"
	purpose: "Complete input on TAB key"
	author:  @hiiamboris
	license: BSD-3
]

system/console/plugins/tab-completion: context with spaces/ctx [
	~: self
	
	;@@ need support for files in quotes and files with spaces (quoted) - boring for now
	list-alternatives: function [
		"List all possible names that finish the given path"
		path [string!]
		/limit max [integer!]
	][
		either suffix: find/last/tail path #"/"
			[prefix: copy/part path suffix]
			[prefix: copy {} suffix: path]
		either path/1 = #"%" [
			if empty? prefix [prefix: "%./" suffix: next suffix]
			try [list: read transcode/one prefix]
		][
			either empty? prefix [prefix: "system/words"][take/last prefix]
			try [list: words-of get transcode/one prefix]
		]
		either list [
			unless empty? suffix [								;-- /match doesn't work with {}
				formed: #[]
				remove-each w list [
					f: any [formed/:w formed/:w: form w]
					not find/match f suffix
				]
			]
			if max [clear skip list max]
		][
			list: copy []
		]
		reduce [suffix list]
	]
	
	word-break!: charset " ^-^/^M[]()"
	tab-complete: function [
		"Try to complete path in given entry at current caret offset"
		entry [object!] ('log-entry = class? entry)
	][
		text: batch doc: entry/rows/input/document [copy-range/text 0 thru here]
		text: any [find/last/tail text word-break!  text]
		set [suffix: list:] list-alternatives/limit text 50
		either single? list [
			text-range: 0 thru (length? suffix) + skip? suffix
			batch doc [change-range text-range form list/1]
			options: copy {}									;-- clear the options after completion
		][	;; this branch includes empty list
			options: mold/only/part list 500
		]
		entry/rows/output/set-text options
		invalidate entry										;-- may not be auto-detected because of not all rows present in /content
		;@@ ideally it should not touch the output, use some 'hint' entry, or show a popup
	]
	
	on-tab-key: function [space path event] with events/commands [
		if all [
			event/key = #"^-"
			empty? event/flags
		][
			tab-complete above space 'log-entry
			stop/now
		]
	]
	append spaces-console/hooks/on-editor-key 'on-tab-key 
]