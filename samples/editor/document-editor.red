Red [
	title:   "Document editor demo"
	author:  @hiiamboris
	license: BSD-3
]

#include %../../everything.red
#include %../../widgets/color-picker.red
#include %../../document.red
#include %editor-toolbar.red

;; this block is used as VID/S layout for initial fill of editor's document
;; it's not super readable because there's no special design for it, since I think it's uncommon to pre-load editor with text
;; it can ONLY contain spaces of RICH-CONTENT type! (every other space must be wrapped into rich-content) 
;; format of rich-content block is described in the header of %../../source.red and it cannot include newline chars!
initial-text: [
	style p: rich-content indent= [first: 20 rest: 0]	;-- html-like rename for brevity
	style li: p indent= [first: 15 rest: 30]			;-- bulleted list item
	style break: p []
	p [bold italic size: 20 "Welcome to Document Editor!"] align= 'center
	break break
	p ["It implements all features needed to build your own " bold "word processor" /bold
	   ", but can also be handy in many other " bold "applications:" /bold]
	li [!(bullet) "as a Draw-based " !(code "area") " widget (main goal of the implementation)"]
	li [!(bullet) "to type rich text in " italic "chat clients"]
	li [!(bullet) "to compose " italic "emails and forum messages"]
	li [!(bullet) "for " italic "note-taking apps"]
	li [!(bullet) "to edit " italic "wiki pages or math sheets"]
	li [!(bullet) "to write " italic "documentation" /italic " for your own program"]
	break
	p ["Structurally, " !(link "editor" %reference.md#editor) " is a scrollable wrapper around " !(link "document" %reference.md#document)
	   " which itself is a vertical list of " !(link "rich-content" %reference.md#rich-content) " spaces that each represent a paragraph."]
	p ["A paragraph can " italic "include any other space" /italic ", though only those spaces that define the /clone facet can be copied and pasted (a very limited set currently)."]
	p ["Paragraph supports all basic text formatting attributes, colors, font face and font size, alignment, indentation, but its "
	   italic "real magic" /italic " lies in the " italic "ability to wrap" /italic " any included space that defines the /sections facet. " !(code "For example, this long span of code is a single space that gets properly wrapped despite having an outline and having no clue about paragraph's existence.") " Moreso, as you may notice this paragraph has " italic "fill" /italic " alignment and code span gets properly spaced without interrupting its outline."] align= 'fill
	p ["Document provides some basic automation, like handling of keys and attribute inherence for new chars. Yet the trickiest feature of it is undo/redo history that gracefully handles rich text with spaces! Even trickier: if you use the button above to insert a table, each table cell contains a separate document, and history is shared between them. Thus pressing Ctrl+Z in a cell may undo an edit in the main document and vice versa."]
	break
	p [size: 10 "Now go on and try to edit this text yourself!"]
]

do/expand with spaces/ctx [

;@@ pageup/down keys events

;; used for numbering paragraph lists
declare-template 'bullet/text [
	text:   "^(2981)"
	format: does [rejoin [text " "]]
	limits: 15 .. none
]

;@@ can I make code templates generic enough to separate them?
declare-template 'code-span/text []
declare-template 'code-block/paragraph []

underbox: function [
	"Draw a box to highlight code parts"
	size       [pair!]
	line-width [integer!]
	rounding   [integer!]
][
	compose/deep [
		push [										;-- solid box under code areas
			line-width (line-width)
			pen (opaque 'text 10%)
			fill-pen (opaque 'text 5%)
			box 0x0 (size - 0x1) (rounding)
		]
	]
]

code-font: make font! with system/view [name: fonts/fixed size: fonts/size]

define-styles [
	code-span: using [pen] [
		font: code-font
		margin: 4x0
		pen: when color (compose [pen (color)])
		below: [(underbox size 1 3) (pen)]
	]
	code-block: [
		margin: 10
		font: code-font
		below: [(underbox size 2 5)]
	]
	
	;; makes grid cells outline visible
	grid: [
		spacing: margin: 1x1
		below: [
			push [
				pen off
				fill-pen (opaque 'text 50%)
				box 0x0 (size)
			]
		]
	]
]


;@@ auto determine URLs during edit, after a space
;@@ need to build a generic requester instead of adhoc ones
request-url: function [
	"Show a dialog to request URL input"
	/from url [url!] "Initial (default) result"
][
	focus: spaces/ctx/focus/current						;-- remember focus (changed by new window)
	view/flags [
		title "Enter an URL"
		host [
			vlist [
				row [
					text "URL:" entry: field 300 focus on-key [
						if event/key = #"^M" [unview set 'url as url! entry/text]
					]
				]
				row [
					button 80 "OK"     [unview set 'url as url! entry/text]
					<->
					button 80 "Cancel" [unview]
				]
			]
		]
	] 'modal
	focus-space focus									;@@ TODO: need separate focus per window!
	url
]

request-grid-size: function [] [
	focus: spaces/ctx/focus/current						;-- remember focus (changed by new window)
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
	focus-space focus									;@@ TODO: need separate focus per window!
	result
]

				
lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
editor-tools: context [
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
	
	toggle-flag: function [
		"Toggle the state of one of logic text attributes"
		doc [object!] name [word!] (find [bold italic underline strike] name)
	][
		either zero? span? range: selected-range doc [
			old: rich/attributes/pick doc/paint name
			rich/attributes/change doc/paint name not old
		][
			old: doc-ctx/pick-attr doc 1 + range/1 name
			doc/edit [mark range name not old]
		]
	]

	linkify-data: function [data [block!] command [block!]] [
		rich/attributes/mark data 'all 'color hex-to-rgb #35F	;@@ I shouldn't hardcode the color like this 
		rich/attributes/mark data 'all 'underline on 
		link: first lay-out-vids [clickable [rich-content data= data] command= command]
		reduce [link 0]
	]
	
	;@@ do auto-linkification on space after url?! good for high-level editors but not the base one, so maybe in actor?
	linkify: function [doc [object!] range [pair!] command [block!]] [
		if range/1 = range/2 [exit]
		;; each paragraph becomes a separate link as this is simplest to do
		data: doc/edit [slice range]
		either data/name = 'rich-text-span [
			data/data: linkify-data data/data command
		][
			foreach para data/data [
				para/data: linkify-data para/data command
			]
		]
		doc/edit [
			remove range
			insert/at data range/1
			select 'none
		]
	]
	
	linkify-selected: function [doc [object!] command [word! (command = 'pick) block!]] [
		if zero? span? range: selected-range doc [exit]
		if command = 'pick [
			if empty? url: request-url [exit]
			unless any [
				find/match url https://
				find/match url http://
			] [insert url https://]
			command: compose [browse (url)]
		]
		linkify doc range command
	]
					
	codify: function [doc [object!] range [pair!]] [
		if range/1 = range/2 [exit]
		slice: doc/edit [slice range]
		either slice/name = 'rich-text-span [
			code: remake-space 'code-span [text: (slice/format)]
		][
			slice: doc/edit [slice range: extend-range doc range]
			trim/tail text: slice/format
			code: remake-space 'code-block [text: (text) sections: (none)]	;-- prevent block from being dissected
		]
		doc/edit [
			remove range
			insert/at code range/1
		]
	]
	
	codify-selected: function [doc [object!]] [
		unless zero? span? range: selected-range doc [
			codify doc range
			doc/selected: none
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
	
	insert-grid: function [doc [object!] size [word! (size = 'pick) pair!]] [
		if size = 'pick [size: request-grid-size]
		unless size [exit]
		col-width: to integer! (max 100 doc/parent/size/x - 100) / size/x
		grid: remake-space 'grid [bounds: (size) widths/default: (col-width)]
		for-each xy size [
			grid/content/:xy: cell: first lay-out-vids [editor]
			cell/content/timeline: doc/timeline			;-- share undo/redo timeline
		]
		doc/edit [insert grid]
	]
	
	change-selected-font: function [doc [object!] font [word! (font = 'pick) none! object!]] [ 
		if font = 'pick [font: request-font]
		default font: [name: #[none] size: #[none]]
		either zero? span? range: selected-range doc [
			rich/attributes/mark paint 1 0x1 'font font/name
			rich/attributes/mark paint 1 0x1 'size font/size
		][
			doc/edit [
				mark range 'font font/name
				mark range 'size font/size
				foreach style compose [(only font/style)] [
					doc/mark range style on
				]
			]
		]
	]
	
	change-selected-color: function [doc [object!] color [word! (color = 'pick) none! tuple!]] [ 
		selected?: zero? span? range: selected-range doc
		if color = 'pick [
			old: either selected?
				[doc-ctx/pick-attr doc 1 + range/1 'color]
				[rich/attributes/pick doc/paint 'color]
			color: request-color/from old
		]
		either selected?
			[doc/edit [mark range 'color color]]
			[rich/attributes/mark doc/paint 1 0x1 'color color]
		focus-space doc									;-- focus was destroyed by request-color ;@@ FIX it
	]
	
];editor-tools: context [

define-handlers [
	editor: extends 'editor [
		document: extends 'editor/document [
			on-key [doc path event] [
				if find [#"^/" #"^M"] event/key [
					editor-tools/auto-bullet-caret doc
				]
			]
		]
	]
]

;; helpful layout funcs
bullet: does [make-space 'bullet []]
home: https://codeberg.org/hiiamboris/red-spaces/src/branch/master/
link: func [text path] [
	remake-space 'link [
		text: (text)
		command: [browse (either url? path [path][home/:path])]
	]
]
code: func [text] [remake-space 'code-span [text: (text)]]
pre:  func [text] [remake-space 'code-block [text: (text)]]

view reshape [
	title "Spaces Document Editor"
	host 640x400 [
		vlist [
			editor-toolbar
			editor: editor 50x50 .. 620x300 focus !(reshape initial-text)
		]
	] ;with [watch in parent 'offset]
]

; prof/show

]; do/expand with spaces/ctx [
