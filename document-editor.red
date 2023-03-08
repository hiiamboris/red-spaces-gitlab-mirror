Red [
	title:   "Document editor demo"
	author:  @hiiamboris
	license: BSD-3
]

#include %everything.red
#include %widgets/color-picker.red
#include %document.red
#include %document-toolbar.red

do/expand with spaces/ctx [

;@@ auto determine URLs during edit, after a space
request-url: function [
	"Show a dialog to request URL input"
	/from url "Initial (default) result"
][
	view/flags [
		title "Enter an URL"
		host [
			vlist [
				row [
					text "URL:" entry: field 300 focus on-key [
						if event/key = #"^M" [unview set 'url entry/text]
					]
				]
				row [
					button 80 "OK"     [unview set 'url entry/text]
					<->
					button 80 "Cancel" [unview]
				]
			]
		]
	] 'modal
	url
]

request-grid-size: function [] [
	accept: [if pair? attempt [loaded: load entry/text] [unview result: loaded]]
	view/flags [
		title "Enter desired grid size"
		host [
			vlist [
				row [
					text "Size:" entry: field 300 text= "2x2" focus on-key [
						if event/key = #"^M" accept
					]
				]
				row [
					button 80 "OK"     [do accept]
					<->
					button 80 "Cancel" [unview]
				]
			]
		]
	] 'modal
	result
]

font-20: make font! [size: 20]
				
define-styles [
	grid: [
		below: [
			push [
				pen off
				fill-pen (opaque 'text 50%)
				box 0x0 (size)
			]
		]
	]
]

lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
append keyboard/focusable 'document
toggle-attr: function [name] [
	; doc-ctx/document/toggle-attribute range
	either all [range: doc/selected  0 < span? range] [
		old: doc-ctx/document/get-attr doc 1 + range/1 name
		?? [old range] 
		doc-ctx/document/mark doc range name not old
	][
		old: rich/attributes/pick doc/paint name 1
		rich/attributes/mark! doc/paint 1 0x1 name not old
	]
	not old
]
realign: function [name] [
	doc/edit [align name]
]
bulletify: function [] [
	range: any [
		doc/selected
		1x1 * doc/caret/offset
	]
	doc-ctx/document/bulletify doc range
]
enumerate: function [] [
	range: any [
		doc/selected
		1x1 * doc/caret/offset
	]
	doc-ctx/document/enumerate doc range
]
indent: function [offset [integer!]] [
	doc/edit [indent offset]
]
codify: function [] [
	if all [
		range: doc/selected
		range/1 <> range/2
	][
		tools/codify doc range
		doc/selected: none
	]
]
insert-grid: function [] [
	if size: request-grid-size [
		grid: make-space 'grid []
		grid/bounds: size
		grid/heights/min: 20
		for-each xy size [
			grid/content/:xy: first lay-out-vids [document [rich-content ["123"]]]
		]
		data: reduce [reduce [grid] #()]
		doc/edit [insert data]
	] 
] 

tools: context [
	extend-range: function [							;@@ put this into document itself?
		"Extend given range to cover instersected paragraphs fully"
		range [pair!]
	][
		mapped: doc/map-range/extend/no-empty range
		range1: mapped/2
		range2: last mapped
		range1/1 by range2/2
	]
	
	;@@ do auto-linkification on space after url?! good for high-level editors but not the base one, so maybe in actor?
	linkify: function [doc [object!] range [pair!] command [block!]] [
		if range/1 = range/2 [exit]
		;; each paragraph becomes a separate link as this is simplest to do
		take/last items: map-each para doc/extract range [
			len: length? para/data/items
			link: when len > 0 (
				rich/attributes/mark! para/data/attrs len 0 by len 'color hex-to-rgb #35F	;@@ I shouldn't hardcode the color like this
				rich/attributes/mark! para/data/attrs len 0 by len 'underline on
				para/data: para/data
				first lay-out-vids [clickable content= para command= command]
			)
			compose [(link) #"^/"]
		]
		data: reduce [items copy #()]
		doc/edit [
			remove range
			insert/at data range/1
			select 'none
		]
	]
	
	codify: function [doc [object!] range [pair!]] [
		if range/1 = range/2 [exit]
		set [items: attrs:] slice: doc/edit [slice range]
		either find items #"^/" [						;-- multiline code block
			slice: doc/edit [slice range: extend-range range]
			lines: map-each para doc/extract range [para/format]
			text: to string! delimit lines "^/"
			code: make-space 'pre compose [text: (text) sections: none]		;-- prevent block from being dissected
		][
			text: doc/edit [slice/text range]
			code: make-space 'code compose [text: (text)]
		]
		doc/edit [
			remove range
			insert/at code range/1
		]
	]
	
]
	
view reshape [
	host 500x400 [
		vlist [
			row tight weight= 0 [
				; drop-button data= "Font" font= font-20 color= none
					; on-over [space/color: if path/2 inside? space [opaque 'text 20%]]
				style attr: data-clickable 0 .. none weight= 0 margin= 4x2 font= font-20 color= none
					on-over [space/color: if path/2 inside? space [opaque 'text 20%]]
				style icon: clickable 0 .. none weight= 0 margin= 5x10 font= font-20 color= none
					on-over [space/color: if path/2 inside? space [opaque 'text 20%]]
				attr "B" bold on-click [toggle-attr 'bold]
				attr "U" underline [toggle-attr 'underline]
				attr "i" italic [toggle-attr 'italic]
				attr "S" strike [toggle-attr 'strike]
				attr "𝓕⏷" flags= [1x1 bold] on-click [
					if font: request-font [
						either all [
							range: doc/selected
							range/1 <> range/2
						][
							doc-ctx/document/mark doc range 'font font/name
							doc-ctx/document/mark doc range 'size font/size
							foreach style compose [(only font/style)] [
								doc-ctx/document/mark doc range style on
							]
						][
							rich/attributes/mark paint 1 0x1 'font font/name
							rich/attributes/mark paint 1 0x1 'size font/size
						]
					]
				]
				; attr "code"							;@@ need inline code and code span (maybe smart) formatter, similar to linkify
				attr "🎨⏷" on-click [
					either all [
						range: doc/selected
						range/1 <> range/2
					][
						old: doc-ctx/document/get-attr doc 1 + range/1 'color
						if color: request-color/from old [
							doc-ctx/document/mark doc range 'color if old <> color [color]	;-- resets color if the same applied
						]
					][
						focus-space doc					;-- focus was destroyed by request-color
						old: rich/attributes/pick doc/paint 1 'color
						color: request-color/from old
						rich/attributes/mark doc/paint 1 0x1 'color color
					]
				]
				attr "🔗" on-click [
					if all [
						range: doc/selected
						range/1 <> range/2
						not empty? url: request-url
					][
						focus-space doc					;-- focus was destroyed by request-url
						unless any [
							find/match url https://
							find/match url http://
						] [insert url https://]
						tools/linkify doc range compose [browse (as url! url)]
					]
				] 
				attr "[c]" font= make code-font [size: 20] on-click [codify]
				; attr content= probe first lay-out-vids [image 30x20 data= icons/aligns/left] 
				attr "⤆" on-click [indent -20]
				attr "⤇" on-click [indent  20]
				icon [image 24x20 data= icons/aligns/fill   ] on-click [realign 'fill]
				icon [image 24x20 data= icons/aligns/left   ] on-click [realign 'left] 
				icon [image 24x20 data= icons/aligns/center ] on-click [realign 'center]
				icon [image 24x20 data= icons/aligns/right  ] on-click [realign 'right]
				icon [image 30x20 data= icons/lists/numbered] on-click [enumerate]
				icon [image 30x20 data= icons/lists/bullet  ] on-click [bulletify]
				attr "▦" on-click [insert-grid]
			]
			scrollable [
				style code: rich-content ;font= code-font
				doc: document focus [
					code [bold font: "Consolas" "block ["]
					code [bold font: "Consolas" "    of wrapped long long long code"]
					code [bold font: "Consolas" "]"]
					code [
						"12"
						@(lay-out-vids [
							clickable command= [print 34] [
								rich-content [underline bold "34" /bold /underline]
							]
						])
						"56"
					]
					rich-content [
						!(make-space 'bullet [])		;@@ need control over bullet font/size 
						@(lay-out-vids [
							rich-content [!(copy skip lorem 200)]
						])
					] indent= [first: 0 rest: 15]
					rich-content [
						!(make-space 'bullet [])
						!(copy skip lorem 220)
					] indent= [first: 0 rest: 15]
				] ;with [watch 'size] 
				on-down [
					space/selected: none
					if caret: doc-ctx/point->caret space path/2 [
						set with space/caret [offset side] reduce [caret/offset caret/side]
						start-drag/with path copy caret
					]
				] on-up [
					stop-drag
				] on-over [
					;@@ need switchable behavior - drag content or select it, /editable flag may control it
					if dragging?/from space [
						if caret: doc-ctx/point->caret space path/2 [
							start: drag-parameter
							space/selected: start/offset by caret/offset
							set with space/caret [offset side] reduce [caret/offset caret/side]
						]
					]
				] on-key [
					case [
						is-key-printable? event [
							space/edit key->plan event space/selected
						]
						event/key = #"^-" [
							either all [doc/selected 0 < span? doc/selected] [
								indent 20 * pick [-1 1] event/shift?
							][
								;@@ tabs support is "accidental" for now - only correct within a single text span
								;@@ if something splits the text, it's incorrect - need special case for it in paragraph layout
								space/edit [insert "^-"]
							]
							stop
						]
					]
				] on-key-down [
					unless is-key-printable? event [
						switch/default event/key [
							#"^M" #"^/" [doc/edit [select 'none  insert "^/"  auto-bullet]]
						][
							space/edit key->plan event space/selected
						]
					]
				]
				on-focus [invalidate space] on-unfocus [invalidate space]	;-- shows/hides caret
			]
		]
	] ;with [watch in parent 'offset]
]

; prof/show

]; do/expand with spaces/ctx [
