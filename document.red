Red [
	title:   "Document template for Spaces"
	author:  @hiiamboris
	license: BSD-3
]

#include %everything.red
#include %widgets/color-picker.red
#include %watch.red



do/expand with spaces/ctx [

;; helper function to draw some icons for alignment & list toggling
bands: none
context [
	tiny-font: make font! [size: 6 style: 'bold name: system/view/fonts/sans-serif]
	set 'bands function [size [pair!] widths [block!] /named texts [block! string!]] [
		thickness: 4
		n:         half length? widths
		step:      size/y - thickness / (n - 1)
		if string? texts [
			markers: map-each [/i t] texts [
				compose [text (0 by (i - 1 * step - 6)) (form t)]
			]
		]
		if block? texts [
			markers: map-each i n [
				compose/deep/only [push [translate (0 by (i - 1 * step)) (texts)]]
			]
		]
		lines: map-each [/i x1 x2] widths [
			compose [
				move (size/x * x1 by (i - 1 * step))
				'hline (to float! x2 - x1 * size/x)
			]
		]
		compose/deep [
			push [
				line-width (thickness)
				font (tiny-font)
				translate (0 by (thickness / 2))
				(only markers)
				shape (wrap lines)
			]
		]
	]
]

code-font: make font! [name: system/view/fonts/fixed]
doc-ctx: context [
	~: self
	
	;@@ need UNDO/REDO! but how?
	
	;@@ scalability problem: convenience of integer caret/selection offsets leads to linear increase of caret-to-offset calculation
	;@@ don't wanna optimize this prematurely but for big texts a b-tree index should be implemented
	
	foreach-paragraph: function [spec [block!] "[paragraph offset length]" doc [object!] code [block!]] [
		if empty? doc/content [return none]				;-- case for loop never entered
		offset: 0
		foreach para doc/content [
			plen: para/measure [length]
			set spec reduce/into [para offset plen] clear []
			offset: offset + plen + 1					;-- +1 for empty 'new-line' space between paragraphs
			do code										;-- result of last `do` is returned
		]
	]
	
	;; needs no /side in the model where paragraphs are separated by empty (newline) caret slot
	;; cases to consider:
	;; - no paragraphs                     => none (normally document has at least one paragraph which may be empty)
	;; - offset < 0 or offset > doc/length => none
	;; - offset = 0                        => 0 of first paragraph
	;; - offset = doc/length               => tail of last paragraph
	caret-to-paragraph: function [doc [object!] offset [integer!]] [
		if offset >= 0 [
			foreach-paragraph [para: pofs: plen:] doc [
				if pofs + plen >= offset [return reduce [para offset - pofs]]
			]
		]												;-- none if out of range or content is empty
	]
	
	get-paragraph-offset: function [doc [object!] paragraph [object!]] [
		foreach-paragraph [para: pofs:] doc [
			if para =? paragraph [return pofs]
		]
	]
		
	;; maps doc/selected into /selected facets of individual paragraphs
	map-selection: function [doc [object!] range [pair!]] [
		foreach-paragraph [para: pofs: plen:] doc [
			prange: clip range - pofs 0 plen
			para/selected: if prange/2 > prange/1 [prange]
		]
	]
	
	;; maps range into a [paragraph paragraph-range] list 
	map-range: function [doc [object!] range [pair!]] [
		mapped: clear []
		foreach-paragraph [para: pofs: plen:] doc [
			case [
				pofs + plen <= range/1 [continue]
				pofs        >= range/2 [break]
				'else [
					prange: clip range - pofs 0 plen
					repend mapped [para prange]			;-- empty paragraphs are not skipped by design
				]
			]
		]
		copy mapped										;-- may be empty
	]

	;@@ rename this to edit, bind `doc` argument
	;@@ 'length' should be under 'measure' context
	document: context [length: copy: remove: insert: mark: get-attr: get-attrs: align: linkify: bulletify: none]
	
	document/length: function [doc] [
		unless para: last doc/content [return 0]
		add get-paragraph-offset doc para
			para/measure [length]
	]
	
	document/copy: function [doc [object!] range [pair!]] [
		map-each [para prange] map-range doc range [
			also para: para/clone
			para/edit [clip! prange]
		]
	]
		
	;@@ do auto-linkification on space after url!
	document/linkify: function [doc [object!] range [pair!] command [block!]] [
		;; each paragraph becomes a separate link as this is simplest to do
		map-each [para prange] map-range doc range [
			if zero? span? prange [continue]
			clone: para/clone
			clone/edit [
				mark! prange 'color hex-to-rgb #35F		;@@ shouldn't hardcode the color
				mark! prange 'underline on
				clip! prange
			]
			link: make-space 'clickable compose/only [
				content: (clone)
				command: (command)
			]
			para/edit [
				remove! prange
				insert! prange/1 link
			]
		]
		; print mold/deep items
	]
	
	document/remove: function [doc [object!] range [pair!]] [
		n: half length? mapped: map-range doc range
		set [para1: range1:] mapped
		set [paraN: rangeN:] skip tail mapped -2 
		if n >= 1 [para1/edit [remove! range1]]
		if n >= 2 [										;-- requires removal of whole paragraphs
			paraN/edit [remove! rangeN]
			para1/edit [insert! range1/1 values-of paraN]
			s: find/same/tail space/content para1
			e: find/same/tail s paraN
			remove/part s e
		]
	]
	
	document/insert: function [
		doc    [object!]
		offset [integer!]
		data   [block! (parse data [any object!]) string!]
	][
		if empty? data [exit]
		set [para1: pofs:] caret-to-paragraph doc offset
		case [
			string? data [para1/edit [insert! pofs data]]
			single? data [para1/edit [insert! pofs values-of data/1/data]]
			'multiple [
				;; edit first paragraph, but remember the after-insertion part
				para1/edit [							;@@ make another action in edit for this?
					stashed: copy range: pofs by infxinf/x
					remove! range
					insert! pofs values-of data/1/data
				]
				;; append stashed part to the last inserted paragraph
				paraN: last data
				paraN/edit [insert! infxinf/x stashed]
				;; insert all other paragraphs (doc/content can be edited directly)
				insert (find/same/tail doc/content para1) next data
			]
		]
	]
	
	document/mark: function [doc [object!] range [pair!] attr [word!] value] [
		foreach [para: prange:] map-range doc range [
			para/edit [mark! attr :value]
		]
	]
	
	document/get-attr: function [space [object!] index [integer!] attr [word!]] [
		if set [para: offset:] caret-to-paragraph space index - 1 [
			rich/attributes/pick para/data/attrs attr offset + 1	;-- may be none esp. on 'new-line' paragraph delimiters
		]
	]
	
	;@@ need to keep some attr 'state' that can be modified by buttons and applied to new chars
	document/get-attrs: function [space [object!] index [integer!] attr [word!]] [
		if set [para: offset:] caret-to-paragraph space index - 1 [
			if offset = para/measure [length] [offset: max 0 offset - 1]	;-- no attribute at the 'new-line' delimiter
			rich/attributes/copy para/data/attrs 0x1 + offset	;@@ still may be empty - is it ok?
		]
	]
	
	document/align: function [
		doc   [object!]
		range [pair!]
		align [word!] (find [left right center fill scale upscale] align)
	][
		foreach [para: _:] map-range doc range [para/align: align]
	]
	
	;; used to correct caret and selection offsets after an edit
	adjust-offsets: function [doc [object!] offset [integer!] shift [integer!]] [
		sel: doc/selected								;-- can't set components of doc/selected (due to reordering)
		car: doc/caret
		foreach path [sel/1 sel/2 car/offset] [
			if attempt [offset <= value: get path] [	;@@ REP #113
				set path max offset value + shift
			]
		]
		doc/caret:    car								;-- trigger updates
		doc/selected: sel
	]
	
	;@@ maybe more generalized get-marker smth?
	bulleted-paragraph?: function [para [object!]] [
		to logic! all [
			space? item1: para/data/items/1
			'bullet = class? item1
		]
	]
	
	document/bulletify: function [doc [object!] range [pair!]] [
		if empty? mapped: map-range doc range [exit]
		already-bulleted?: bulleted-paragraph? mapped/1	;-- already has a bullet? for toggling
		foreach [para: prange:] mapped [
			items: para/data/items
			pofs:  range/1 - prange/1
			if bulleted-paragraph? para [				;-- get rid of numbers and old bullets
				para/edit [remove! 0x1]
				adjust-offsets doc pofs + 1 -1
			]
			unless already-bulleted? [
				para/edit [insert! 0 make-space 'bullet []]
				adjust-offsets doc pofs 1
			]
		]
	]
	
	; override: ...
	
	on-selected-change: function [space [object!] word [word!] value: -1x-1 [pair! none!]] [	;-- -1x-1 acts as deselect-everything
		;; NxN selection while technically empty, is not forbidden or converted to `none`, to avoid surprises in code
		if value/1 > value/2 [
			quietly space/selected: value: reverse value		;-- keep it ordered for simplicity
		]
		map-selection space value
	]
	
	point-to-caret: function [doc [object!] point [pair!]] [	;@@ accept path maybe too?
		path: hittest doc point
		set [para: xy:] skip path 2
		either para [
			#assert [in para 'measure]							;@@ measure is too general name for strictly caret related api?
			;; lands directly into text or rich-content
			caret: para/measure [point-to-caret xy]
			base: get-paragraph-offset doc para
			caret/offset: caret/offset + base
			caret
		][	;; lands outside - need to find nearest
			;@@ add space box computation to foreach-space ? and ability to skip branches based on that?
			none
		]
	]
	
	draw: function [doc [object!] canvas: infxinf [pair! none!]] [
		;; trick for caret changes to invalidate the document: need to render it once (though it's never displayed)
		unless doc/caret/parent [render doc/caret]
		
		;; para/caret is a space that is moved from paragraph to paragraph, where it gets rendered
		;; not to be confused with doc/caret that is not rendered and only holds the absolute offset
		set [para: offset:] caret-to-paragraph doc doc/caret/offset
		if para [
			unless para =? old-holder: doc/caret/holder [
				either old-holder [
					para/caret: old-holder/caret
					para/caret/parent: none
					old-holder/caret:  none
				][
					para/caret: make-space 'caret []
				]
				doc/caret/holder: para
			]
			para/caret/side:   doc/caret/side
			para/caret/offset: offset
		]
		
		drawn: doc/list-draw/on canvas
	]
	
	declare-template 'document/list [
		axis:   'y		#type (axis = 'y)				;-- protected
		spacing: 5
		
		caret:   make-space 'caret [
			offset: 0
			side:   'right
			holder: none								;-- child that last owned the generated caret space
		] #type [object!] :invalidates
		
		selected: none	#type [pair! none!] :on-selected-change
		
		list-draw: :draw
		draw: func [/on canvas [pair!]] [~/draw self canvas]
	]
]

clipboard: context [
	data: []											;-- last copied data
	text: ""											;-- text version of the last copied data
	
	data-to-text: function [data [block!]] [
		list: map-each [item [object!]] data [
			when in item 'format (item/format)
		]
		to {} delimit list "^/" 
	]
	
	;; spaces are cloned so they become "data", not active objects that can change inside clipboard
	clone-data: function [data [block! string!]] [
		either string? data [
			copy data
		][
			map-each item data [
				only all [
					space? :item
					function? select item 'clone
					item/clone
				]
			]
		]
	]
	
	read: function [] [
		read: read-clipboard
		unless read == text [self/data: self/text: read]		;-- last copy comes from outside the running script
		clone-data data
	]
	
	write: function [content [block! (parse content [any object!]) string!]] [
		content: either string? content [
			copy content
		][
			clone-data content
		]
		append clear data content
		write-clipboard self/text: data-to-text data
	]
]

; declare-template 'item/list [axis: 'y weight: 1]
; set-style 'item [
	; margin: 10x1
	; below: [push [line-width 1 fill-pen off pen red box 0x0 (size)]]
; ]

declare-template 'bullet/text [
	text:   "^(2981)"
	format: does [rejoin [text " "]]
	limits: 15 .. none
]

;; this should automatically invalidate the parent, since child facet change will lead to it
#macro [#mirror-into [path! | into [some path!]]] func [[manual] s e /local paths target] [
	either path? target: e/-1 [
		paths: reduce [to set-path! compose [space (to block! target)]]
	][
		paths: target
		forall paths [paths/1: to set-path! compose [space (to block! paths/1)]]
	]
	remove/part s e
	insert s compose/deep [#on-change [space word value] [(paths) :value]]
	s
]

declare-template 'color-wheel/space [
	color: white
]

;@@ how to organize it?
;@@ popup UI needs improvements: touch-sized buttons, scrollbars and wheel scrolling, automatic limitation of scrollable size
;@@ also on-change event
declare-template 'drop-button/list [
	axis: 'x
	spaces: object [
		box:    make-space 'data-clickable [type: 'face]		;@@ how to name the type for styling consistency?
		button: make-space 'data-clickable [type: 'side-button data: "⏷"]	;-- don't want 'button' style to apply to it
	]
	content: reduce [spaces/box spaces/button]
	command: []		#mirror-into spaces/box/command
	data:    none	#mirror-into spaces/box/data
	font:    none	#mirror-into [spaces/box/font spaces/button/font]
]

icons: object [
	lists: object [
		numbered: bands/named 30x20 [25% 1  25% 1  25% 1] "123"
		bullet:   bands/named 30x20 [25% 1  25% 1  25% 1] [line-width 1 circle 2x0 1.5]
	]
	aligns: object [
		left:   bands 24x20 [0   80%  0 1  0   70%]
		right:  bands 24x20 [20% 1    0 1  30% 1  ]
		center: bands 24x20 [10% 90%  0 1  15% 85%]
		fill:   bands 24x20 [0   1    0 1  0   1  ]
	]
]

define-styles [
	drop-button: [
		below: when select self 'color [push [pen off fill-pen (color) box 0x0 (size)]]
	]
]
define-handlers [
	drop-button: [
		face: [
		]
		side-button: [
			on-down [space path event] [
				offset: -1x-1 + face-to-window event/offset event/face
				menu: lay-out-menu items: [
					"1" (print "1")
					"2" (print "2")
					"3" (print "3")
					"Font" (print "hehe found it")
					"hello" (print "HELL")
				]
				drop-button: space/parent
				picked: 1 + half any [skip? find items drop-button/data  0]
				face: make-popup event/window 1
				face/rate:  10										;-- reduced timer pressure
				face/space: menu
				face/size:  none									;-- to make render set face/size
				face/draw:  render face
				?? menu/content
				picked-geom: pick menu/content/map picked * 2
				offset: offset - picked-geom/offset - (picked-geom/size / 2)
				show-popup event/window 1 offset face
			]
		]
	]
]

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

font-20: make font! [size: 20]
				
lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
append keyboard/focusable 'document
toggle-attr: function [name] [
	; doc-ctx/document/toggle-attribute range
	unless zero? span? range: doc/selected [
		old: doc-ctx/document/get-attr doc 1 + range/1 name
		doc-ctx/document/mark doc range name not old
	]
]
realign: function [name] [
	range: any [
		doc/selected
		1x1 * doc/caret/offset
	]
	doc-ctx/document/align doc range name
]
bulletify: function [] [
	range: any [
		doc/selected
		1x1 * doc/caret/offset
	]
	doc-ctx/document/bulletify doc range
]
view reshape [
	host 500x400 [
		vlist [
			formatting: row tight weight= 0 [
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
					if all [
						range: doc/selected
						font: request-font
					][
						doc-ctx/document/mark doc range 'font font/name
						doc-ctx/document/mark doc range 'size font/size
						foreach style compose [(only font/style)] [
							doc-ctx/document/mark doc range style on
						]
					]
				]
				; attr "code"							;@@ need inline code and code span (maybe smart) formatter, similar to linkify
				attr "🎨⏷" on-click [
					if all [
						range: doc/selected
						range/1 <> range/2
						color: request-color/from old: doc-ctx/document/get-attr doc 1 + range/1 'color
					][
						doc-ctx/document/mark doc range 'color if old <> color [color]	;-- resets color if the same applied
					]
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
						doc-ctx/document/linkify doc range compose [browse (as url! url)]
					]
				] 
				; attr content= probe first lay-out-vids [image 30x20 data= icons/aligns/left] 
				icon [image 24x20 data= icons/aligns/fill]   on-click [realign 'fill]
				icon [image 24x20 data= icons/aligns/left]   on-click [realign 'left] 
				icon [image 24x20 data= icons/aligns/center] on-click [realign 'center]
				icon [image 24x20 data= icons/aligns/right]  on-click [realign 'right]
				icon [image 30x20 data= icons/lists/numbered];  on-click [realign 'right]
				icon [image 30x20 data= icons/lists/bullet]  on-click [bulletify]
			]
			scrollable [
				style code: rich-content ;font= code-font
				doc: document focus [
					; #code ["block [^/    of code^/]"]
					; #paragraph [command: [] size: 20 "prefix^/" /command /size !(copy/part lorem 200)]
					; code source= ["12" underline bold "34" /bold /underline "56"]
					; rich-content source= [!(make-space 'bullet [text: "○"]) !(copy skip lorem 200)] indent= [rest: 15] ;align= 'fill
					
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
					] indent= [rest: 15]
					rich-content [
						!(make-space 'bullet [])
						!(copy skip lorem 220)
					] indent= [rest: 15]
				] ;with [watch 'size] 
				on-down [
					space/selected: none
					if caret: doc-ctx/point-to-caret space path/2 [
						set with space/caret [offset side] reduce [caret/offset caret/side]
						start-drag/with path copy caret
					]
				] on-up [
					stop-drag
				] on-over [
					;@@ need switchable behavior - drag content or select it, /editable flag may control it
					if dragging?/from space [
						if caret: doc-ctx/point-to-caret space path/2 [
							start: drag-parameter
							space/selected: start/offset by caret/offset
							set with space/caret [offset side] reduce [caret/offset caret/side]
						]
					]
				] on-key [
					if switch event/key [
						left  [set [side: shift:] [right -1]]
						right [set [side: shift:] [left   1]]
					][
						total: doc-ctx/document/length space	;@@ need to cache it
						new: clip 0 total space/caret/offset + shift
						set with space/caret [offset side] reduce [new side]
					]
					switch probe event/key [
						#"^C" [
							if space/selected [
								clipboard/write doc-ctx/document/copy space space/selected
							]
						]
						#"^V" [
							unless empty? data: clipboard/read [
								doc-ctx/document/insert space space/caret/offset data
							]
						]
						#"^X" [
							if range: space/selected [
								clipboard/write doc-ctx/document/copy space range
								doc-ctx/document/remove space range
								space/selected: none
							]
						]
					]
				]
			]
		]
	] ;with [watch in parent 'offset]
]
prof/show

]
