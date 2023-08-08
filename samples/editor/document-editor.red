Red [
	title:   "Document editor demo"
	author:  @hiiamboris
	license: BSD-3
]

;; include Spaces core
#include %../../everything.red

#process off
do/expand [												;-- hack to avoid #include bugs!
	;; requester widgets needed by the toolbar
	#include %../../widgets/requesters.red
	
	;; document widget provides the foundation for the editor
	#include %../../widgets/document.red
	
	;; toolbar includes all the buttons and their associated actions
	#include %editor-toolbar.red
]
#process on


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

;; this wrapping is used to ease access to Spaces context
do/expand with spaces/ctx [

;; 'bullet' template used for numbering paragraph lists
declare-template 'bullet/text [
	text:   "^(2981) "									;-- has bullet symbol by default, not number; space is for better look in the clipboard
	format: does [rejoin [text " "]]
	limits: 15 .. none									;-- set min width to align numbers better
]

;; in-line and block code templates
;@@ can I make code templates generic enough to separate them?
declare-template 'code-span/text []
declare-template 'code-block/paragraph [limits: 0 .. 500]	;@@ there must be a better way to wrap it than hard cap on width!

;; fixed-width font for code
code-font: make font! with system/view [name: fonts/fixed size: fonts/size]

;; helper function that draws background in styles
underbox: function [
	"Draw a box to highlight code parts"
	size       [planar!]
	line-width [integer!]
	rounding   [integer!]
][
	compose/deep [
		push [
			line-width (line-width)
			pen (opaque 'text 10%)
			fill-pen (opaque 'text 5%)
			box 0x0 (size - 0x1) (rounding)
		]
	]
]

;; extension of the stylesheet
define-styles [
	;; styles for newly introduced code templates
	code-span: [
		font: code-font
		margin: 4x0
		pen: when color (compose [pen (color)])
		below: reduce [quote (underbox size 1 3) pen]
	]
	code-block: [
		margin: 10
		font: code-font
		below: [(underbox size 2 5)]
	]
	
	;; this just makes grid cells outline visible (by default grid has no background)
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
request-url: function [
	"Show a dialog to request URL input"
	/from url: https:// [url! string! none!] "Initial (default) result"
][
	request "Enter an URL"
		[row middle [text "URL:" entry: field text= url focus 300]]
		[@"OK" [as url! copy entry/text] "Cancel"]
]

;@@ currently there's no UI to resize the grid
request-grid-size: function [] [
	accept: [unless pair? attempt [loaded: load entry/text] [exit] loaded]
	request "Enter desired grid size" [
		row middle [
			text "Size:"
			entry: field 300 focus text= "2x2"
			on-key [if event/key = #"^M" accept]
		]
	] [@"OK" [do accept] "Cancel"]
]

				
;; high level wrappers for basic `document/edit` functions, more suitable for toolbar actions
;@@ these could go into editor/kit eventually
editor-tools: context [
	extend-range: function [							;@@ put this into document itself?
		"Extend given range to cover instersected paragraphs fully"
		doc [object!] range [pair! none!] "If none, current caret offset"
	][
		mapped: batch doc [map-range/extend/no-empty any [range here * 1x1]]
		range1: mapped/2
		range2: last mapped
		range1/1 thru range2/2
	]
	
	range->paragraphs: function [
		"Return a list of paragraphs intersecting the given range"
		doc [object!] range: (1x1 * doc/caret/offset) [pair! none!]
	][
		extract batch doc [map-range range] 2
	]
	
	toggle-flag: function [
		"Toggle the state of one of logic text attributes"
		doc [object!] name [word!] (find [bold italic underline strike] name)
	][
		either range: batch doc [selected] [
			batch doc [
				old: pick-attr 1 + range/1 name
				mark-range range name not old
			]
		][
			old: rich/attributes/pick doc/paint name
			rich/attributes/change doc/paint name not old
		]
	]

	;@@ it will be possible to edit links if I use `link: url!` attribute for them, but it's no pressing matter
	linkify-data: function [
		"Given text slice returns a single link containing it"
		data [block!] command [block!]
	][
		rich/attributes/mark data 'all 'color hex-to-rgb #35F	;@@ I shouldn't hardcode the color like this 
		rich/attributes/mark data 'all 'underline on 
		link: first lay-out-vids [clickable [rich-content data= data] command= command]
		reduce [link 0]
	]
	
	;@@ do auto-linkification on space after url?! good for high-level editors but not the base one, so maybe in actor?
	linkify: function [
		"Convert given range into a link"
		doc [object!] range [pair!] command [block!]
	][
		if range/1 = range/2 [exit]
		;; each paragraph becomes a separate link as this is simplest to do
		data: batch doc [copy-range range]
		either data/name = 'rich-text-span [
			data/data: linkify-data data/data command
		][
			foreach para data/data [
				para/data: linkify-data para/data command
			]
		]
		batch doc [
			change-range range data
			select-range none
		]
	]
	
	linkify-selected: function [
		"Convert selection into a link"
		doc [object!] command [word! (command = 'pick) block!]
	][
		unless range: batch doc [selected] [exit]
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
					
	codify: function [
		"Convert given range into a code span or block"
		doc [object!] range [pair!]
	][
		if range/1 = range/2 [exit]
		slice: batch doc [copy-range range]
		either slice/name = 'rich-text-span [
			code: remake-space 'code-span [text: (slice/format)]
		][
			range: extend-range doc range
			slice: batch doc [copy-range range]
			trim/tail text: slice/format
			code: remake-space 'code-block [text: (text) sections: (none)]	;-- prevent block from being dissected
		]
		batch doc [change-range range code]
	]
	
	codify-selected: function [
		"Convert selection into a code span or block"
		doc [object!]
	][
		if range: batch doc [selected] [
			codify doc range
			doc/selected: none
		]
	]
	
	;; helpers that simplify work with bulleted/numbered paragraphs
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
	
	auto-bullet: function [
		"Replace paragraph's bullet with the one that follows the previous paragraph"
		doc [object!] para [object!]
	][
		pindex: index? find/same doc/content para
		if prev: pick doc/content pindex - 1 [
			text: either num: get-bullet-number prev
				[rejoin [num + 1 "."]]
				[get-bullet-text prev]
			if text [new-bullet: remake-space 'bullet [text: (text)]]
		]
		old-bullet: bulleted-paragraph? para
		base-indent: any [get-safe 'para/indent/first 0]
		batch doc [
			offset: paragraph-head para
			if old-bullet [remove-range 0x1 + offset]
			if new-bullet [
				move-caret offset
				insert-items here new-bullet
				indent-range here compose [first: (base-indent) rest: (base-indent + 15)]
			]
		]
	]
	
	auto-bullet-caret: function [
		"Replace bullet of the current paragraph with the one following the previous paragraph"
		doc [object!]
	][
		para: first batch doc [caret->paragraph here]
		auto-bullet doc para
	]
	
	debulletify: function [
		"Remove bullet or number from the paragraph"
		doc [object!] para [object!]
	][
		if bulleted-paragraph? para [
			batch doc [
				offset: paragraph-head para
				remove-range 0x1 + offset
				new-indent: if para/indent [compose [first: (i: para/indent/first) rest: (i)]]
				if new-indent [indent-range offset new-indent]
			]
		]
	]
	
	bulletify: function [
		"Set bullet for the paragraph"
		doc [object!] para [object!]
		/as number [integer!] "Set a number instead of a bullet"
	][
		bullet: make-space 'bullet []
		if number [bullet/text: rejoin [number "."]]
		base-indent: any [get-safe 'para/indent/first 0]
		batch doc [
			offset: paragraph-head para
			move-caret offset
			if bulleted-paragraph? para [remove-range 0x1 + here]
			insert-items here bullet
			indent-range here compose [first: (base-indent) rest: (base-indent + 15)]
		]
	]
	
	bulletify-selected: function [
		"Set bullets for selected paragraphs"
		doc [object!]
	][
		list: range->paragraphs doc batch doc [selected]
		action: either bulleted-paragraph? list/1 [:debulletify][:bulletify]
		foreach para list [action doc para]
	]
	
	enumerate-selected: function [
		"Enumerate selected paragraphs"
		doc [object!]
	][
		list: range->paragraphs doc batch doc [selected]
		either num: get-bullet-number list/1 [debulletify doc list/1][bulletify/as doc list/1 1]
		foreach para next list [auto-bullet doc para]
	]
	
	insert-grid: function [
		"Insert grid of given size at caret location"
		doc [object!] size [word! (size = 'pick) pair!] "Use 'pick to pop up a requester"
	][
		if size = 'pick [size: request-grid-size]
		unless size [exit]
		col-width: (max 100 doc/parent/size/x - 100) / size/x
		grid: remake-space 'grid [bounds: (size) widths/default: (col-width)]
		for-each xy size [
			grid/content/:xy: cell: first lay-out-vids [editor]
			cell/content/timeline: doc/timeline			;-- share undo/redo timeline
		]
		batch doc [insert-items here grid]
	]
	
	change-selected-font: function [
		"Change font for the selection or for newly input text"
		doc [object!] font [word! (font = 'pick) none! object!] "Use 'pick to pop up a requester"
	][ 
		if font = 'pick [font: request-font]
		default font: [name: #[none] size: #[none]]
		either range: batch doc [selected] [
			batch doc [
				mark-range range 'font font/name
				mark-range range 'size font/size
				foreach style compose [(only font/style)] [
					mark-range range style on
				]
			]
		][
			rich/attributes/change doc/paint 'font font/name
			rich/attributes/change doc/paint 'size font/size
		]
	]
	
	change-selected-color: function [
		"Change color for the selection or for newly input text"
		doc [object!] color [word! (color = 'pick) none! tuple!] "Use 'pick to pop up a requester"
	][ 
		range: batch doc [selected]
		if color = 'pick [
			old: either range
				[batch doc [pick-attr 1 + range/1 'color]]
				[rich/attributes/pick doc/paint 'color]
			color: request-color/from old
		]
		either range
			[batch doc [mark-range range 'color color]]
			[rich/attributes/change doc/paint 'color color]
	]
	
];editor-tools: context [


;; extend Enter key of editor to auto-add bullets to new paragraph
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


;; helpful layout funcs (used in the `initial-text` at the top of this file)
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


;; build main editor window
view reshape [
	title "Spaces Document Editor"
	host 640x400 [
		column [
			editor-toolbar
			editor: editor focus !(reshape initial-text)
		]
	]
]

; prof/show

]; do/expand with spaces/ctx [
