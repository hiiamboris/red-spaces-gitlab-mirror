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
	either all [range: doc/selected  0 < span? range] [
		old: doc-ctx/pick-attr doc 1 + range/1 name
		doc/edit [mark range name not old]
	][
		old: rich/attributes/pick doc/paint name
		rich/attributes/change doc/paint name not old
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
		grid: remake-space 'grid [bounds: (size)]
		grid/heights/min: 20
		for-each xy size [
			grid/content/:xy: first lay-out-vids [document [rich-content ["123"]]]
		]
		data: reduce [reduce [grid] #()]
		doc/edit [insert data]
	] 
] 

tools: context [
	selected-range: function [doc [object!]] [
		any [doc/selected  doc/caret/offset * 1x1]
	]
	
	extend-range: function [							;@@ put this into document itself?
		"Extend given range to cover instersected paragraphs fully"
		doc [object!] range [pair!]
	][
		mapped: doc/map-range/extend/no-empty range
		range1: mapped/2
		range2: last mapped
		range1/1 by range2/2
	]
	
	range->paragraphs: function [
		"Return a list of paragraphs intersecting the given range"
		doc [object!] range [pair!]
	][
		extract doc/map-range range 2
	]
	
	linkify-data: function [data [block!]] [
		rich/attributes/mark data 'all 'color hex-to-rgb #35F	;@@ I shouldn't hardcode the color like this 
		rich/attributes/mark data 'all 'underline on 
	]
	;@@ do auto-linkification on space after url?! good for high-level editors but not the base one, so maybe in actor?
	linkify: function [doc [object!] range [pair!] command [block!]] [
		if range/1 = range/2 [exit]
		;; each paragraph becomes a separate link as this is simplest to do
		slice: doc/edit [slice range]
		either slice/name = 'rich-text-span [
			linkify-data slice/data
			link: first lay-out-vids [clickable [rich-content data= slice] command= command]
			slice/data: reduce [link 0]
		][
			foreach para slice/data [
				linkify-data para/data
				link: first lay-out-vids [clickable [rich-content data= para/data] command= command]
				para/data: reduce [link 0]
			]
		]
		doc/edit [
			remove range
			insert/at slice range/1
			select 'none
		]
	]
	
	codify: function [doc [object!] range [pair!]] [
		if range/1 = range/2 [exit]
		slice: doc/edit [slice range]
		either slice/name = 'rich-text-span [
			code: remake-space 'code [text: (slice/format)]
		][
			slice: doc/edit [slice range: extend-range doc range]
			code: remake-space 'pre [text: (slice/format) sections: (none)]	;-- prevent block from being dissected
		]
		doc/edit [
			remove range
			insert/at code range/1
		]
	]
	
	get-bullet-text: function [para [object!]] [
		all [
			space? bullet: para/data/1
			'bullet = class? bullet
			bullet/text
		]
	]
	get-bullet-number: function [para [object!]] [
		all [
			text: get-bullet-text para
			parse text [copy num some digit! "."]
			transcode/one num
		]
	]
	bulleted-paragraph?: function [para [object!]] [
		to logic! get-bullet-text para
	]
	numbered-paragraph?: function [para [object!]] [
		to logic! get-bullet-number para
	]
	
	;@@ maybe bullets should also inherit font/size/flags from the first char of the first paragraph?
	;@@ also ideally on break/remove/cut/paste paragraph numbers should auto-update, but I'm too lazy
	
	;; replaces paragraph's bullet following that of the previous paragraph
	auto-bullet: function [doc [object!] para [object!]] [
		pindex: index? find/same doc/content para
		if prev: pick doc/content pindex - 1 [
			text: either num: get-bullet-number prev
				[rejoin [num + 1 "."]]
				[get-bullet-text prev]
			if text [new-bullet: remake-space 'bullet [text: (text)]]
		]
		old-bullet: bulleted-paragraph? para
		offset: doc-ctx/get-paragraph-offset doc para	;@@ need to put it into measure
		base-indent: any [if para/indent [para/indent/first] 0]	;@@ REP 113
		doc/edit [
			if old-bullet [remove 0x1 + offset]
			if new-bullet [
				move offset insert new-bullet
				indent compose [first: (base-indent) rest: (base-indent + 15)]
			]
		]
	]
	
	auto-bullet-caret: function [doc [object!]] [
		para: first doc/measure [caret->paragraph doc/caret/offset]
		auto-bullet doc para
	]
	
	debulletify: function [doc [object!] para [object!]] [
		if bulleted-paragraph? para [
			offset: doc-ctx/get-paragraph-offset doc para
			new-indent: if para/indent [compose [first: (i: para/indent/first) rest: (i)]]
			doc/edit [
				remove 0x1 + offset
				if new-indent [indent new-indent]
			]
		]
	]
	
	bulletify: function [doc [object!] para [object!] /as number [integer!]] [
		offset: doc-ctx/get-paragraph-offset doc para
		bullet: make-space 'bullet []
		if number [bullet/text: rejoin [number "."]]
		if bulleted-paragraph? para [doc/edit [remove 0x1 + offset]]
		base-indent: any [if para/indent [para/indent/first] 0]	;@@ REP 113
		doc/edit [
			move offset insert bullet
			indent compose [first: (base-indent) rest: (base-indent + 15)]
		]
	]
	
	bulletify-selected: function [doc [object!]] [
		list: range->paragraphs doc selected-range doc
		action: either bulleted-paragraph? list/1 [:debulletify][:bulletify]
		foreach para list [action doc para]
	]
	
	enumerate-selected: function [doc [object!]] [
		list: range->paragraphs doc selected-range doc
		either num: get-bullet-number list/1 [debulletify doc list/1][bulletify/as doc list/1 1]
		foreach para next list [auto-bullet doc para]
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
							doc/edit [
								mark range 'font font/name
								mark range 'size font/size
								foreach style compose [(only font/style)] [
									doc/mark range style on
								]
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
						old: doc-ctx/pick-attr doc 1 + range/1 'color
						if color: request-color/from old [
							color: if old <> color [color]		;-- resets color if the same one applied
							doc/edit [mark range 'color color]
						]
					][
						old: rich/attributes/pick doc/paint 1 'color
						color: request-color/from old
						rich/attributes/mark doc/paint 1 0x1 'color color
					]
					focus-space doc						;-- focus was destroyed by request-color
				]
				attr "🔗" on-click [
					if all [
						range: doc/selected
						range/1 <> range/2
						not empty? url: request-url
					][
						unless any [
							find/match url https://
							find/match url http://
						] [insert url https://]
						tools/linkify doc range compose [browse (as url! url)]
					]
					focus-space doc						;-- focus was destroyed by request-url
				] 
				attr "[c]" font= make code-font [size: 20] on-click [codify]
				; attr content= probe first lay-out-vids [image 30x20 data= icons/aligns/left] 
				attr "⤆" on-click [indent -20]
				attr "⤇" on-click [indent  20]
				icon [image 24x20 data= icons/aligns/fill   ] on-click [realign 'fill]
				icon [image 24x20 data= icons/aligns/left   ] on-click [realign 'left] 
				icon [image 24x20 data= icons/aligns/center ] on-click [realign 'center]
				icon [image 24x20 data= icons/aligns/right  ] on-click [realign 'right]
				icon [image 30x20 data= icons/lists/numbered] on-click [tools/enumerate-selected doc]
				icon [image 30x20 data= icons/lists/bullet  ] on-click [tools/bulletify-selected doc]
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
							#"^M" #"^/" [doc/edit [select 'none  insert "^/"] tools/auto-bullet-caret doc]
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
