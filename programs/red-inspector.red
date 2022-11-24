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

; recycle/off
#include %../../cli/cli.red
; #include %../../common/assert.red
;@@ stupid include bugs turn off assertions in some crooked way, can't use them to debug inspector
#include %../../common/setters.red
#include %../../common/forparse.red
; #do [disable-space-cache?: yes]
#include %../everything.red

#process off											;@@ hack to avoid #include bugs
; do/expand [#include %../stylesheets/glossy.red]
#process on

import/only spaces/ctx [top]
append spaces/keyboard/focusable 'tube

context [

	code-font: make font! [name: system/view/fonts/fixed]
	
	;@@ workaround for #4854 crashes:
	copy-func: func [f [function!]] [func spec-of :f copy/deep body-of :f]
	
	define-styles [
		cell/text: grid/cell/text: grid/cell/paragraph: [
			spaces/ctx/set-flag flags 'bold if parent [parent/pinned?]
			; default font: code-font
			font: code-font
			below: when color: select self 'color [pen (color)]
		]
	]
	
	;; override defaults, though can be set in style too
	declare-template 'grid/grid [
		margin:  2x2
		spacing: 1x1
		autofit: none
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
			string! [space: make-space pick [paragraph text] wrap? [text:  value]]
			logic!  [space: make-space 'logic [state: value]]
			url!    [space: make-space 'link  [data:  value]]
			tuple!  [
				space: either find [3 4] length? value [		;-- possibly a color
					s: form to binary! value
					make-space 'cell [
						align: -1x0
						color: value
						content: make-space 'text [
							color: contrast-with value
							text: rejoin [value " #" copy/part skip s 2 back tail s]
						]
						pinned?: does [spaces/ctx/grid-ctx/pinned? self]
					]
				][
					make-space 'text [text: mold :value]
				]
			]
			image!  [
				space: make-space 'grid-view [
					kind: 'image
					grid/widths/1: 50
					grid/pinned:  1x0
					; pages: 2
					limits: 30x50 .. none
					old-wrap-data: :wrap-data
					wrap-data: func [data] [
						either space? :data [
							;@@ maybe grid should wrap the space as cell too?
							make-space 'cell [
								align: -1x0
								content: data
								pinned?: does [spaces/ctx/grid-ctx/pinned? self]
							]
						][
							old-wrap-data :data
						]
					]
				]
				extend space/source reduce [
					'size 2x2
					1x1 "Size" 2x1 form value/size
					1x2 "Look" 2x2 make-space 'image [
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
			space: make-space 'text [text: mold :value]
		]
		
		unless space [
			if map [
				source: copy [["Key" "Type" "Value"]] 
				keys: keys-of map
				clear skip keys MAX_VALUES					;-- limit the number of words that can be inspected
				append source map-each/eval/only key keys [
					set/any 'val select/case map key
					[form key  type? :val  :val]
				]
			]
			space: make-space 'grid-view [
				kind: 'data
				pages: 5
				grid/pinned: 0x1
				extend grid/widths [1 80 2 80]
				limits: 30x100 .. none
			]
			space/source: source
		]
		; prof/manual/end 'wrap-value
		space
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
			make-space 'text [
				quietly text: mold/flat/part :space/data 1000
				quietly flags: [ellipsize]
			]
		]
		
		draw: function [space [object!] canvas [none! pair!] /extern depth] [
			depth: depth + 1
			if all [
				limit < depth
				find deep-types type? :space/data
			][
				saved: space/content
				quietly space/content: too-deep space canvas
			]
			trap/catch [drawn: space/old-draw/on canvas] [error: thrown]
			depth: depth - 1
			if saved [quietly space/content: saved]
			either error [do error][drawn]
		]
	
		declare-template 'data-view/data-view [
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
			image?: gview/kind = 'image
			set [canvas: fill:] spaces/ctx/decode-canvas canvas
			if all [
				canvas/x < infxinf/x
				canvas/x <> attempt [gview/size/x]
			][
				ncol: either image? [2][3]
				new-width: max 50 canvas/x - widths/1 - (any [widths/2 0])
					- (gview/grid/margin/x * 2) - (gview/grid/spacing/x * ncol) - gview/vscroll/size/x
				if widths/default <> new-width [
					widths/default: new-width
					invalidate gview/grid
					; gview/grid/do-invalidate
					; clear gview/grid/frame/heights
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
				gview/size: min gview/size gview/window/size + scrollers
			]
			drawn
		]
	]
	
	set 'inspect function [
		"Open Red Inspector window on the TARGET"
		'target [path! word! unset!] "Path or word to inspect"
		/local value
	][
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
			; invalidate browser
			invalidate-tree host
			; invalidate details
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
				]
				any [
					event/key = #"^H"					;-- backspace
					all [event/key = 'left  find event/flags 'alt]
				] [history-back]
				all [event/key = 'right find event/flags 'alt] [history-forward]
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
							if event/key = #"^M" [jump stop]
						] hint= "Enter a valid path and click 'Go'"
						button "Go" [jump] hint= "Browse into entered path"
					] 
					row 200 .. none [
						box [
							details: paragraph bold on-key-down [
								event/key = #"^-" [pass]
							]
						]
						button "<<" [history-back]    hint= "Go back in history"
						button ">>" [history-forward] hint= "Go forward in history"
					]
					do [set-details]
					;@@ 9999 is a hack that needs a better solution
					;@@ currently scrollable doesn't know how to render itself on inf canvas, becomes zero and complains
					browser: data-view data=(get/any target) on-dbl-click [
						if all [ 
							pos: locate path [obj .. /type = 'grid]
							grid: pos/1
						][
							set [cell: offset:] grid/locate-point pos/2
							contspace: grid/content/(3 by cell/y)
							namespace: grid/content/(1 by cell/y)
							if all [0 <= offset/y  offset/y < contspace/size/y  string? namespace/data] [
								new-path: append copy history/1 transcode/one namespace/data
								if all [
									set/any 'value attempt [get-path new-path]
									not scalar? :value
								][
									navigate new-path
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
					if host/space [invalidate-tree host]
					; if host/space [invalidate host/space]
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
	either empty? script [
		inspect system
	][
		; debug-draw
		do script/1
	]
	prof/show
]
; img: make image! 1000x7000
; inspect system/words/img
; inspect system/view
; prof/show
; debug-draw
cli/process-into red-inspector
quit/return 0
