Red [
	title:   "Highlighting plugin for Spaces Console"
	purpose: "Ease visual scanning of input Red code"
	author:  @hiiamboris
	license: BSD-3
]

system/console/plugins/highlighting: context with spaces/ctx [
	~: self
	;@@ add GUI to edit rules and default background, color, font
	
	;; store rules in the state so user can rewrite them
	;; rules must be a map of: datatype! -> block! [attr value ...]
	default spaces-console/state/highlight-rules:				;@@ rules should be GUI-configured 
	default-rules: make map! [
		set-word! [color @(blend 'panel 'text  150%)  bold #[true]]
		set-path! [color @(blend 'panel 'text  150%)  bold #[true]]
		string!   [color @(blend 'text  magenta 50%)]
		binary!   [color @(blend 'text  magenta 50%)]
		integer!  [color @(blend 'text  cyan    50%)]
		float!    [color @(blend 'text  cyan    50%)]
		percent!  [color @(blend 'text  cyan    50%)]
		pair!     [color @(blend 'text  cyan    50%)]
		point2D!  [color @(blend 'text  cyan    50%)]
		point3D!  [color @(blend 'text  cyan    50%)]
		paren!    [color @(blend 'text  blue    50%)  bold #[true]]
		block!    [color @(blend 'text  black   50%)  bold #[true]]
		url!      [color @(blend 'text  sky     50%)  underline #[true]]
		native!   [color @(blend 'text  green   50%)]
		action!   [color @(blend 'text  green   50%)]
		op!       [color @(blend 'text  green   50%)]
		function! [color @(blend 'text  green   50%)]
		unset!    [color @(blend 'text  red     50%)  bold #[true]]
	]
	
	;; resulting colors need not appear in the state, only used locally
	colors: to #() reshape to [] spaces-console/state/highlight-rules

	foreach-token: function [
		"Evaluate code for each loaded datatype in the text"
		spec [block!] "[type range]" (parse spec [2 [word! | set-word!]])
		text [string!]
		code [block!]
	][
		opens: make [] 16
		in-paths: 0
		transcode/trace text :lexical-tracer
	]
	
	lexical-tracer: function [
		event [word!]
		input [string!]
		type  [word! datatype!]
		line  [integer!]
		token
		/extern in-paths
	] with :foreach-token [
		[scan load open close error]
		; [scan open close error]
		path?: find [path! lit-path! get-path! set-path!] to word! type		;-- any-path! will error on word type
		switch event [
			scan  [report?: not any [path? in-paths > 0]]		;-- ignore tokens in paths, but not in lists
			open  [
				either path?
					[in-paths: in-paths + 1]
					[report?: token: token + 0x1]
			]
			close [
				report?: either path?
					[in-paths: in-paths - 1]
					[token: token/2 + 0x1]
			]
			error [
				input: next input								;-- protect from deadlock
				return no
			]
		]
		if report? [
			set spec/1 to word! type
			set spec/2 token
			do code
		]
		type <> word!											;-- don't bloat bloats system/words with partial words
	]
	
	word-exists?: function [									;@@ maybe check for not unset too?
		"Check if word exists in global context without loading it"
		word [string!]
	][
		formed: #()
		foreach w words-of system/words [
			f: any [formed/:w formed/:w: form w]
			if word = f [return yes]
		]
		no
	]
	
	highlight: function [
		"Colorize text in the document"
		doc   [object!] ('document = class? doc)
		sheet [map!] "Map of: datatype! -> block! [attr value]"
	][
		foreach para doc/content [
			append data: clear [] para/data 
			rich/attributes/clear data 'all
			text: rich/source/format data
			tokens: clear []
			foreach-token [type range] text [
				; #print "(type)	(range)	(mold copy/part text range)"
				if find [path! get-path! word! get-word!] type [
					slice: copy/part text range
					if any [
						find [path! get-path!] type
						word-exists? slice						;-- do not bloat system/words with partial words
					][
						try [type: type?/word get/any transcode/one slice]
					]
				]
				if attrs: :sheet/:type [
					foreach [attr value] attrs [
						rich/attributes/mark data range - 1 attr value
					]
				]
			]
			if data <> para/data [								;-- apply changes without allocation
				change para/data data
				trigger 'para/data
			]
		]
	]
	
	declare-template 'log-editor/log-editor [					;-- modify editor template to turn on highlighting
		draw: function [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] compose [
			highlight content ~/colors
			(body-of :draw)
		]
	]
]