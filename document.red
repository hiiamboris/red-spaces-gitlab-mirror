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
	
	;@@ simplify this, should not use recursion
	get-length: function [space [object!]] [			;-- measures length of the document or any of it's children
		case [
			select space 'measure [space/measure [length]]
			select space 'content [
				len: 0
				foreach child space/content [			;@@ use accumulate
					len: len + get-length child			;@@ need cycle protection?
				]
				len
			]
			'empty [0]									;-- scaffolding has no length, should be skipped
		]
	]
	
	caret-to-child: function [space [object!] offset [integer!] side [word!]] [
		foreach child space/content [
			child-len: get-length child
			if child-len = 0 [continue]					;-- ignore scaffolding
			
			;; remember best candidate in case caret prefers a non-empty child to the right of it, but none exists:
			match: child 
			
			if any [									;-- prefer to skip this child if:
				offset > child-len							;-- caret does not fit it
				all [offset = child-len  side = 'right]		;-- right side prefers next child
			][
				offset: offset - child-len
				continue
			]
			
			break										;-- good match found, no need to continue
		]
		
		if match [										;-- not none if at least one non-empty child exists
			#assert [select match 'measure]
			reduce [match offset]
		]
	]
		
	;@@ problem here - need to set /selected facet of children as they are being drawn
	;@@ another problem - whole tree traversal, while in most cases it's not needed
	map-selection: function [space [object!] range [pair!]] [
		foreach child space/content [
			child-len: get-length child
			#assert [select child 'measure]
			clipped: clip range 0 child-len
			child/selected: if clipped/2 > clipped/1 [clipped]
			range: range - child-len
		]
	]

	document: context [clip: remove: insert: mark: get-attr: align: linkify: linkify-item: none]
	document/clip: function [space [object!] range [object!] (all [in range 'start in range 'end])] [
		if range/start/offset > range/end/offset [
			swap in range 'start in range 'end
		]
		set [item1: offset1:] caret-to-child space range/start/offset range/start/side
		set [item2: offset2:] caret-to-child space range/end/offset   range/end/side
		#assert [item1]
		#assert [item2]
		items: copy/part
			find/same      space/content item1
			find/same/tail space/content item2
		items: map-each item items [item/clone]
		pair:  range/start/offset by range/end/offset
		either item1 =? item2 [							;-- within the same paragraph
			item: items/1
			pair: pair - (pair/1 - offset1)
			item/edit [copy/keep pair]
		][
			item1: items/1
			item2: last items
			pair1: pair - (pair/1 - offset1)
			pair2: pair - (pair/2 - offset2)
			item1/edit [copy/keep pair1]
			item2/edit [copy/keep pair2]
		]
		; print mold/deep items
		#print "Copied: (mold map-each item items [to string! item/decoded/items])"
		items
	]
	
	document/linkify-item: function [text [object!] range [pair!] command [block!]] [
		set [items: attrs:] text/edit [copy range]
		link: make-space 'clickable [
			content: make-space 'rich-content []
		]
		range1: 0 by length? items
		attrs: rich/attributes/mark attrs 'color hex-to-rgb #35F range1 on	;@@ shouldn't hardcode the color
		attrs: rich/attributes/mark attrs 'underline on range1 on
		link/content/source: rich/source/serialize items attrs
		link/command: command
		text/edit [
			remove range
			insert range/1 reduce [link]
		]
	]
	
	document/linkify: function [space [object!] range [pair!] command [block!]] [
		#assert [range/1 < range/2]
		set [item1: offset1:] caret-to-child space range/1 'right
		set [item2: offset2:] caret-to-child space range/2 'left
		#assert [item1]
		#assert [item2]
		either item1 =? item2 [							;-- within the same paragraph
			range: range - (range/1 - offset1)
			document/linkify-item item1 range command
		][
			items: copy/part
				find/same      space/content item1
				find/same/tail space/content item2
			item1: items/1
			item2: last items
			range1: range - (range/1 - offset1)
			range2: range - (range/2 - offset2)
			document/linkify-item item1 range1 command
			document/linkify-item item2 range2 command
			items: next items
			repeat i (length? items) - 1 [
				document/linkify-item items/:i 0 by infxinf/x command
			]
		]
		; print mold/deep items
	]
	
	document/remove: function [space [object!] range [object!] (all [in range 'start in range 'end])] [
		if range/start/offset > range/end/offset [
			swap in range 'start in range 'end
		]
		set [item1: offset1:] caret-to-child space range/start/offset range/start/side
		set [item2: offset2:] caret-to-child space range/end/offset   range/end/side
		#assert [item1]
		#assert [item2]
		pair:  range/start/offset by range/end/offset
		either item1 =? item2 [							;-- within the same paragraph
			pair: pair - (pair/1 - offset1)
			item1/edit [remove pair]
		][
			pair1: pair - (pair/1 - offset1)
			pair2: pair - (pair/2 - offset2)
			item2/edit [remove pair2]
			item1/edit [
				remove pair1
				insert infxinf/x item2
			]
			remove/part
				find/same/tail space/content item1
				find/same      space/content item2
		]
	]
	
	document/insert: function [space [object!] offset [integer!] side [word!] data [block! string!]] [
		set [target: offset:] caret-to-child space offset side
		either block? data [
			#assert ['rich-content = class? data/1]
			either single? data [
				target/edit [insert offset data/1]
			][
				target/edit [
					set [items2: attrs2:] copy range: offset by infxinf/x
					remove range
					insert offset data/1
				]
				; #print "target after insertion (mold target/decoded/items)"
				;; insert all other paragraphs
				pos: find/same/tail space/content target
				; insert/part pos next data top data
				insert pos next data
				target: last data
				; #print "last batch item (mold target/decoded/items)"
				;; append stashed part to the last inserted
				target/edit [insert/with infxinf/x items2 attrs2]
				; #print "last batch item after insertion (mold target/decoded/items)"
			]
		][
			target/edit [insert offset data]
		]
	]
	
	document/mark: function [space [object!] range [pair!] attr [word!] value] [
		if range/1 > range/2 [range: reverse range]
		set [item1: offset1:] caret-to-child space range/1 'right
		set [item2: offset2:] caret-to-child space range/2 'left
		#assert [item1]
		#assert [item2]
		items: copy/part
			find/same      space/content item1
			find/same/tail space/content item2
		either item1 =? item2 [							;-- within the same paragraph
			item: items/1
			range: range - (range/1 - offset1)
			item/edit [mark range attr :value]
		][
			item1: items/1
			item2: last items
			range1: clip range - (range/1 - offset1) 0 item1/measure [length]
			range2: clip range - (range/2 - offset2) 0 item2/measure [length]
			item1/edit [mark range1 attr :value]
			item2/edit [mark range2 attr :value]
			for-each [item | _] next items [
				range: 0 by item/measure [length]
				item/edit [mark range attr :value]
			]
		]
	]
	
	; document/get-attrs: function [space [object!] index [integer!] attr [word!]] [
	document/get-attr: function [space [object!] index [integer!] attr [word!]] [
		set [item: offset:] caret-to-child space index - 1 'right
		#assert [item]
		rich/attributes/pick item/decoded/attrs attr offset + 1
	]
	
	document/align: function [
		doc [object!]
		range [object!] (all [in range 'start in range 'end])	;-- sides are useful for absent selection (align by caret)
		align [word!] (find [left right center fill] align)
	][
		#assert [
			range/start/offset <= range/end/offset
			0 <= range/start/offset
			range/end/offset <= get-length doc
		]
		; range: clip range 0 doc/measure [length]
		set [item1: _:] caret-to-child doc range/start/offset range/start/side
		set [item2: _:] caret-to-child doc range/end/offset   range/end/side
		; ?? item1
		; ?? item2
		items: copy/part
			find/same      doc/content item1
			find/same/tail doc/content item2
		foreach item items [
			item/align: align
			; #print "Set (index? find/same doc/content item) to (align)"
		]
	]
	
	; override: ...
	
	on-selected-change: function [space [object!] word [word!] value [object! none!]] [
		either value [ 
			pair: value/range
			#assert [pair/1 <= pair/2]
		][
			pair: -1x-1
		] 
		map-selection space pair
	]
	
	caret-base: function [space [object!] item [object!]] [
		if item =? space [return 0]
		base: 0
		foreach child item/parent/content [				;@@ use accumulate, or caching
			if child =? item [break]
			base: base + get-length child
		]
		base
	]
	
	point-to-caret: function [space [object!] point [pair!]] [	;@@ accept path maybe too?
		path: hittest space point
		either path/3 [
			#assert [in path/3 'measure]					;@@ measure is too general name for strictly caret related api?
			;; lands directly into text or rich-content
			set [item: xy:] skip path 2
			caret: item/measure [point-to-caret xy]
			base: caret-base space item
			caret/offset: caret/offset + base
			caret
		][	;; lands outside - need to find nearest
			;@@ add space box computation to foreach-space ? and ability to skip branches based on that?
			none
		]
	]
	
	draw: function [space [object!] canvas: infxinf [pair! none!]] [
		;; trick for caret changes to invalidate the document: need to render it once
		unless space/caret/parent [render space/caret]
		
		;; child/caret is a space that is moved from child to child, where it gets rendered
		;; not to be confused with space/caret that is not rendered and only holds the absolute offset
		set  [child: offset:] caret-to-child space space/caret/offset space/caret/side
		if child [
			unless child =? old-holder: space/caret/holder [
				either old-holder [
					child/caret: old-holder/caret
					child/caret/parent: none
					old-holder/caret:   none
				][
					child/caret: make-space 'caret []
				]
				space/caret/holder: child
			]
			child/caret/side:   space/caret/side
			child/caret/offset: offset
		]
		
		drawn: space/list-draw/on canvas
	]
	
	declare-template 'document/list [
		axis:   'y		#type (axis = 'y)				;-- protected
		spacing: 5
		
		caret:   make-space 'caret [
			offset: 0
			side:   'right
			holder: none								;-- child that last owned the generated caret space
		] #type [object!] :invalidates
		
		selected: none	#type [object! none!] :on-selected-change
		
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
		probe to {} delimit list "^/" 
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
	if doc/selected [
		range: doc/selected/range
		if range/1 <> range/2 [
			old: doc-ctx/document/get-attr doc 1 + range/1 name
			doc-ctx/document/mark doc range name not old
		]
	]
]
realign: function [name] [
	range: any [
		if doc/selected [doc/selected]
		object [
			start: end: compose [offset: (o: doc/caret/offset) side: (doc/caret/side)]
			range: o * 1x1
		]
	]
	doc-ctx/document/align doc range name
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
						doc/selected
						font: request-font
					][
						range: doc/selected/range
						doc-ctx/document/mark doc range 'font font/name
						doc-ctx/document/mark doc range 'size font/size
						foreach style compose [(font/style)] [
							doc-ctx/document/mark doc range style on
						]
					]
				]
				attr "🎨⏷" on-click [
					if all [
						doc/selected
						range: doc/selected/range
						range/1 <> range/2
						color: request-color/from old: doc-ctx/document/get-attr doc 1 + range/1 'color
					][
						doc-ctx/document/mark doc range 'color if old <> color [color]	;-- resets color if the same applied
					]
				]
				attr "🔗" on-click [
					if all [
						doc/selected
						range: doc/selected/range
						range/1 <> range/2
						not empty? url: request-url
					][
						doc-ctx/document/linkify doc range compose [browse (as url! url)]
						doc/selected/end/offset: doc/selected/range/2: range/1 + 1
						; ?? doc/selected
						if doc/caret/offset >= range/1 [
							doc/caret/offset: max range/1 doc/caret/offset - (range/2 - range/1) + 1
						] 
						doc/selected: none
						invalidate doc
					]
				] 
				; attr content= probe first lay-out-vids [image 30x20 data= icons/aligns/left] 
				icon [image 24x20 data= icons/aligns/fill]   on-click [realign 'fill]
				icon [image 24x20 data= icons/aligns/left]   on-click [realign 'left] 
				icon [image 24x20 data= icons/aligns/center] on-click [realign 'center]
				icon [image 24x20 data= icons/aligns/right]  on-click [realign 'right]
				icon [image 30x20 data= icons/lists/numbered];  on-click [realign 'right]
				icon [image 30x20 data= icons/lists/bullet];  on-click [realign 'right]
			]
			scrollable [
				style code: rich-content font= code-font
				doc: document focus [
					; #code ["block [^/    of code^/]"]
					; #paragraph [command: [] size: 20 "prefix^/" /command /size !(copy/part lorem 200)]
					; code source= ["12" underline bold "34" /bold /underline "56"]
					; rich-content source= [!(make-space 'bullet [text: "○"]) !(copy skip lorem 200)] indent= [rest: 15] ;align= 'fill
					
					code source= ["block ["]
					code source= ["    of wrapped long long long code"]
					code source= ["]"]
					code source= compose ["12" (lay-out-vids [clickable margin= 0x2 command= [print 34] [rich-content [underline bold "34" /bold /underline]]]) "56"]
					rich-content source= [!(make-space 'bullet [text: "○"]) 
					@(
						lay-out-vids [rich-content source= [!(copy skip lorem 200)]]
					)] indent= [rest: 15]
					rich-content source= [!(make-space 'bullet [text: ">"]) !(copy skip lorem 220)] indent= [rest: 15]
				] with [watch 'size] 
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
							range: start/offset by caret/offset
							if range/1 > range/2 [range: reverse range]
							;@@ need to design selection API - is it going to use on-change or laziness or what, or just a block?
							space/selected: construct compose/only [
								start: (start) end: (caret) range: (range)
							]
							set with space/caret [offset side] reduce [caret/offset caret/side]
						]
					]
				] on-key [
					if switch event/key [
						left  [set [side: shift:] [right -1]]
						right [set [side: shift:] [left   1]]
					][
						total: doc-ctx/get-length space			;@@ need to cache it
						new: clip 0 total space/caret/offset + shift
						set with space/caret [offset side] reduce [new side]
					]
					switch probe event/key [
						#"^C" [
							if space/selected [
								clipboard/write doc-ctx/document/clip space space/selected
							]
						]
						#"^V" [
							unless empty? data: clipboard/read [
								doc-ctx/document/insert space space/caret/offset space/caret/side data
							]
						]
						#"^X" [
							if space/selected [
								clipboard/write doc-ctx/document/clip space space/selected
								doc-ctx/document/remove space space/selected
								caret: copy do with space/selected [
									either start/offset <= end/offset [start][end]
								]
								space/selected:     none
								space/caret/offset: caret/offset
								space/caret/side:   caret/side
							]
						]
					]
				]
			]
		]
	] with [watch in parent 'offset]
]
prof/show

]
