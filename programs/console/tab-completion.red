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
		suffix: any [find/last/tail path #"/"  path]
		prefix: copy/part path back suffix
		either path/1 = #"%" [
			if empty? prefix [prefix: "%." suffix: next suffix]
			try [list: read dirize transcode/one prefix]
		][
			if empty? prefix [prefix: "system/words"]
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
		text: any [find/last text word-break!  text]
		set [suffix: list:] list-alternatives/limit text 50
		switch/default length? list [
			0 [exit]
			1 [
				text-range: 0 thru (length? suffix) + skip? suffix
				batch doc [change-range text-range form list/1]
			]
		][
			entry/rows/output/set-text mold/only/part list 500
		]
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