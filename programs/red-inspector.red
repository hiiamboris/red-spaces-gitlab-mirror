Red [
	title:   "Red Inspector"
	purpose: "Inspect program state at runtime"
	author:  @hiiamboris
	license: BSD-3
	needs:   View
	notes:   {
		TIP: #include it after an error has happened to browse state
	}
]

#include %../../cli/cli.red
#include %../../common/setters.red
#include %../../common/forparse.red
; #do [disable-space-cache?: yes]
#include %../everything.red

import/only spaces/ctx [top]
append spaces/keyboard/focusable 'tube

context [

	code-font: make font! [name: system/view/fonts/fixed]
	
	;@@ workaround for #4854 crashes:
	copy-func: func [f [function!]] [func spec-of :f copy/deep body-of :f]
	
	define-styles [
		cell/ellipsized-text: cell/text: grid/cell/text: grid/cell/paragraph: [
			maybe flags: either attempt [spaces/ctx/grid-ctx/pinned?]
				[union   flags [bold]]
				[exclude flags [bold]]
			maybe/same font: code-font
			below: [(when color: select self 'color (compose [pen (color)]))]
		]
	]
	
	;; override defaults, though can be set in style too
	spaces/templates/grid: make-template 'grid [
		margin:  2x2
		spacing: 1x1
		heights: copy #(min 10 default auto)
		widths:  copy #(default 80)
	]
	
	
	;; limits the displayed size of big blocks/objects
	MAX_VALUES: 100
	
	;; advanced data representation with grid for composite values
	;; overrides the simple default
	spaces/ctx/VID/wrap-value: function [
		"Create a space to represent given VALUE; return it's name"
		value [any-type!]
		wrap? [logic!] "How to lay text out: as a line (false) or paragraph (true)"
	][
		; prof/manual/start 'wrap-value
		switch/default type?/word :value [
			string! [name: make-space/name pick [paragraph text] wrap? [text:  value]]
			logic!  [name: make-space/name 'logic [state: value]]
			url!    [name: make-space/name 'link  [data:  value]]
			tuple!  [
				either find [3 4] length? value [			;-- possibly a color
					s: form to binary! value
					name: make-space/name 'cell [
						align: -1x0
						color: value
						content: make-space/name 'text [
							color: contrast-with value
							text: rejoin [value " #" copy/part skip s 2 back tail s]
						]
					]
				][
					name: make-space/name 'text [text: mold :value]
				]
			]
			image!  [
				space: get name: make-space/name 'grid-view [
					type: 'image
					grid/widths/1: 50
					grid/pinned:  1x0
					; pages: 2
					; limits: 30x30 .. 200x200
					old-wrap-data: :wrap-data
					wrap-data: func [xy data] [
						either all [word? :data space? get/any data] [
							;@@ maybe grid should wrap the word as space too?
							make-space/name 'cell [align: -1x0 content: data]
						][
							old-wrap-data xy :data
						]
					]
				]
				extend space/source reduce [
					'size 2x2
					1x1 "Size" 2x1 form value/size
					1x2 "Look" 2x2 make-space/name 'image [
						limits: 20x20 .. none
						data: value
					] 
				]
			]
			event! [
				map: make map! map-each/eval name system/catalog/accessors/event! [
					[name value/:name]
				]
			]
			function! [
				source: compose/deep [
					["Word" "Type" "Value"]
					[<spec> "block!" (mold/only spec-of :value)]
					[<body> "block!" (mold/only body-of :value)]
					(map-each/eval/only/drop [key [word! lit-word! get-word! refinement!]] spec-of :value [
						;; words might not be accessible:
						val: <unavailable> type: {}
						attempt [type: type? set/any 'val get/any bind to word! key :value]
						[form to word! key  type  :val]
					])
				] 
			]
			block! hash! paren!
			path! get-path! lit-path! set-path! [
				map: make map! reduce [<length> length? value]
				repeat i min MAX_VALUES length? value [map/:i: :value/:i]
			]
			object! map! [map: value]
			word! get-word! lit-word! set-word! refinement! issue! [
				map: make map! reduce [
					<spelling> mold value
					<value>    <unavailable>
				]
				if any-word? value [						;-- no context for refinement & issue
					extend map reduce [<context> context? value]
				]
				attempt [put map <value> get/any value]		;-- might not be available
			]
		][
			name: make-space/name 'text [text: mold :value]
		]
		
		unless name [
			if map [
				source: copy [["Key" "Type" "Value"]] 
				keys: keys-of map
				clear skip keys MAX_VALUES					;-- limit the number of words that can be inspected
				append source map-each/eval/only key keys [
					set/any 'val select/case map key
					[form key  type? :val  :val]
				]
			]
			space: get name: make-space/name 'grid-view [
				type: 'data
				pages: 5
				grid/pinned: 0x1
				extend grid/widths [1 80 2 80]
				limits: 30x30 .. none
			]
			space/source: source
		]
		; prof/manual/end 'wrap-value
		name
	]
	
	
	;; style for ellipsizing text in the cell
	;@@ should be generally available, but need to think in what form
	;@@ and in that case it might need optimization, maybe newtonian search
	elli-text-ctx: context [
		~: self
		
		split-text: function [rich-text [object!] limit [integer!] /chars /non-empty] [
			; prof/manual/start 'split-text
			olde-size: rich-text/size
			olde-text: rich-text/text
			quietly rich-text/size: infxinf
			quietly rich-text/text: text: clear {}
			delim: pick [[skip] #" "] chars 
			forparse [end: [delim | end]] bgn: olde-text [	;-- text should not contain any other whitespace than space!
				append/part text bgn end 
				size: size-text rich-text
				if size/x > limit [break]
				bgn: end
			]
			r: offset? olde-text bgn
			if all [non-empty r = 0] [
				bgn: olde-text
				clear text
				repeat r length? bgn [
					append text bgn/:r
					size: size-text rich-text
					if size/x > limit [r: max 1 r - 1 break]
				]
			]
			quietly rich-text/size: olde-size
			quietly rich-text/text: olde-text
			; prof/manual/end 'split-text
			r
		]
		
		ellipsis: make-space 'text [text: "..." font: code-font]
		render 'ellipsis
		
		spaces/templates/ellipsized-text: make-template 'text [
			text-draw: :draw
			draw: function [/on canvas [pair! none!]] [
				if layout [quietly layout/text: text]
				drawn: text-draw/on canvas
				set [canvas: fill:] spaces/ctx/decode-canvas canvas
				if size/x > canvas/x [
					len: split-text/chars layout canvas/x - ellipsis/size/x
					append clear skip layout/text len "..." 
				]
				drawn
			]
		]
	]
	
	;; advanced data view style with depth control
	cell-data-view-ctx: context [
		~: self
	
		;; to avoid infinite draw blocks during render of cyclic data:
		limit: 2
		depth: 0
		
		deep-types: make typeset! [object! map! function! all-word! any-block!]	;@@ what else? should it even be here??
		
		too-deep: function [space [object!] canvas [none! pair!]] [
			default canvas: 0x0
			make-space/name 'ellipsized-text [text: mold/flat/part :space/data 1000]
		]
		
		draw: function [space [object!] canvas [none! pair!] /extern depth] [
			depth: depth + 1
			if all [
				limit < depth
				find deep-types type? :space/data
			][
				saved: space/content
				set-quiet in space 'content too-deep space canvas
			]
			trap/catch [drawn: space/old-draw/on canvas] [error: thrown]
			depth: depth - 1
			if saved [set-quiet in space 'content saved]
			either error [do error][drawn]
		]
	
		spaces/templates/data-view: make-template 'data-view [
			wrap?: on
			old-draw: :draw
			draw: function [/on canvas [pair! none!]] [~/draw self canvas]
		]
		
		set-style 'image [
			limits/max: if depth > 1 [10x1 * shift-right 400 depth - 1]
		]
		set-style 'grid-view function [gview /on canvas] [
			default canvas: 0x0
			widths: gview/grid/widths
			image?: gview/type = 'image
			set [canvas: fill:] spaces/ctx/decode-canvas canvas
			if all [
				canvas/x < infxinf/x
				canvas/x <> attempt [gview/size/x]
			][
				ncol: either image? [2][3]
				new-width: max 50 canvas/x - widths/1 - (any [widths/2 0]) - (gview/grid/margin/x * 2) - (gview/grid/spacing/x * ncol) - gview/vscroll/size/x
				if widths/default <> new-width [
					widths/default: new-width
					clear gview/grid/hcache
				]
			]
			length? gview/grid/content
			if depth > 1 [
				either image? [
					canvas/y: 9999
				][
					if canvas/y >= infxinf/y [canvas/y: shift-right 400 depth - 1]
				]
			]
			drawn: gview/draw/on spaces/ctx/encode-canvas canvas fill
			if depth > 1 [
				vsc: gview/vscroll/size
				hsc: gview/hscroll/size
				scrollers: (vsc/x * sign? vsc/y) by (hsc/y * sign? hsc/x)
				maybe gview/size: min gview/size gview/window/size + scrollers
			]
			drawn
		]
	]
	
	set 'inspect function ['target [path! word! unset!] /local value] [
		if unset? :target [target: 'system]
		history: reduce [to path! target]
		
		history-move: function [step] [
			new-idx: step + index? history
			if all [1 <= new-idx  new-idx <= length? head history] [
				set 'history skip history step
				reload
			]
		]
		history-back:    does [history-move -1]
		history-forward: does [history-move  1]
		navigate: function [where [word! path!]] [
			append/only set 'history clear next history to path! where
			reload
		]
		get-path: function [path] [
			trap/catch [get/any path] [
				;; there's a function in the path, so path access can't work
				set/any 'value get/any path/1
				foreach name next path [
					set/any 'value case [
						function? :value [get/any bind name :value]
						word? :value [
							switch name [
								<value> [get/any value]
								<context> [context? value]
							]
						]
						'else [:value/:name]
					]
				]
				:value
			]
		]
		a-an: func [str [string!]] [either find "aeiou" str/1 ["an"] ["a"]]
		set-details: function [] [
			type: mold type? get-path history/1
			details/text: form reduce [mold history/1 "is" a-an type type "value"]
		]
		reload: does [
			set/any 'browser/data get-path history/1
			set-details
			;; partial invalidations don't get rid of the now invalid spaces, which burden the cache and make it slow
			;@@ why hash! becomes so slow?? need a way to reproduce it
			; invalidate browser
			; invalidate details
			invalidate <everything>
		]
		jump: function [] [
			attempt [path: transcode/one entry/text]
			if any [path? path word? path] [navigate to path! path]
		]
	
		register-finalizer [key] global-keys: function [space path event] [
			if stop? [exit]
			; dump-event event
			case [
				event/key = #"^L" [
					;@@ TODO: more straightforward focusing function
					focus-space compose [
						(copy/part spaces/keyboard/focus 3)			;-- screen/window/base
						(first spaces/ctx/paths-from-space entry)	;-- part after base
					]
					update
				]
				any [
					event/key = #"^H"					;-- backspace
					all [event/key = 'left  find event/flags 'alt]
				] [history-back update]
				all [event/key = 'right find event/flags 'alt] [history-forward update]
			]
		]
	
		view/flags/options [
			title "Red Inspector"
			host: host rate 33 800x450 [						;-- lower rate to save resources
				column tight [
					;@@ TODO: disabled/enabled state for interactive spaces?
					row align= -1x0 [
						label "Jump to:" 
						entry: field focus weight= 1 on-key [
							if event/key = #"^M" [jump stop update]
						] hint= "Enter a valid path and click 'Go'"
						button "Go" [jump] hint= "Browse into entered path"
					] 
					row 200 .. none [
						box [
							details: paragraph bold on-key-down [
								event/key = #"^-" [pass update]
							]
						]
						button "<<" [history-back]    hint= "Go back in history"
						button ">>" [history-forward] hint= "Go forward in history"
					]
					do [set-details]
					;@@ 9999 is a hack that needs a better solution
					;@@ currently scrollable doesn't know how to render itself on inf canvas, becomes zero and complains
					browser: data-view 100x100 .. 9999x9999 data=(get/any target) on-dbl-click [
						if all [ 
							pos: find path 'grid
							grid: get pos/1
						][
							set [cell: offset:] grid/locate-point pos/2
							contspace: get grid/content/(3 by cell/y)
							namespace: get grid/content/(1 by cell/y)
							if all [0 <= offset/y  offset/y < contspace/size/y  string? namespace/data] [
								new-path: append copy history/1 transcode/one namespace/data
								if all [
									set/any 'value attempt [get-path new-path]
									not scalar? :value
								][
									navigate new-path
									update
								]
							]
						]
					]
				]
			]
			; on-over [status/text: form hittest face/space event/offset]
			; return status: text 800x40
			; do [debug-draw]
		] 'resize [
			actors: object [
				on-resize: on-resizing: function [window event] [
					new-size: window/size - 20x20
					host/size: new-size
					host/dirty?: yes
				]
			]
		]
		
		delist-finalizer :global-keys
	]
]

system/script/header: object [	 						;@@ workaround for #4992
	title:   "Red Data Inspector"
	author:  @hiiamboris
	license: 'BSD-3
]

red-inspector: function [
	"Use `inspect` function in your scripts"
	script [file! block!]
][
	if empty? script [
		inspect system
		quit/return 0
	]
	do script/1
]
; img: make image! 1000x7000
; inspect system/words/img
; inspect system/view
; prof/show
; debug-draw
cli/process-into red-inspector
quit/return 0
