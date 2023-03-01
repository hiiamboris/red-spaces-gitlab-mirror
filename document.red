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
	caret->paragraph: function [doc [object!] offset [integer!]] [
		if offset >= 0 [
			foreach-paragraph [para: pofs: plen:] doc [
				if pofs + plen >= offset [return reduce [para pofs plen]]
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
		range: order-pair range
		foreach-paragraph [para: pofs: plen:] doc [
			prange: clip range - pofs 0 plen
			para/selected: if prange/2 > prange/1 [prange]
		]
	]
	
	;; maps range into a [paragraph paragraph-range] list 
	map-range: function [doc [object!] range [pair!] /extend "Extend range to full paragraphs"] [
		range: order-pair range
		mapped: clear []
		foreach-paragraph [para: pofs: plen:] doc [
			case [
				pofs + plen < range/1 [continue]		;-- empty parts (tail/head) of the paragraph are counted (for remove to work)
				pofs        > range/2 [break]
				'else [
					prange: either extend
						[0 by plen + pofs]
						[clip range - pofs 0 plen]
					repend mapped [para prange]			;-- empty paragraphs are not skipped by design
				]
			]
		]
		copy mapped										;-- may be empty
	]

	;; words are split by word separator chars (space, tab) and paragraph delimiter
	word-sep:     [#" " | #"^-"]
	non-word-sep: [not word-sep skip]
		
	metrics: context [
		measure: function [doc [object!] plan [block!]] [
			do with self plan
		]
		
		length: function ["Get length of the document"] with :measure [	;@@ need to cache it (and maybe put into /length facet?)
			unless para: last doc/content [return 0]
			add get-paragraph-offset doc para
				para/measure [length]
		]
		
		find-prev-word: function ["Get offset of the previous word's start"] with :measure [
			set [para: pofs: plen:] caret->paragraph doc offset: doc/caret/offset
			while [offset <= pofs] [					;-- switch to previous paragraph (maybe multiple times)
				if offset <= 0 [return 0]				;-- no more going left
				set [para: pofs: plen:] caret->paragraph doc offset: offset - 1
			]
			#assert [pofs < offset]						;-- limited by paragraph's head
			e: skip s: para/data/items offset - pofs
			before: reverse append/part clear [] s e
			parse before [any word-sep any non-word-sep before:]
			offset - skip? before
		]
		find-next-word: function ["Get offset of the next word's end"] with :measure [
			set [para: pofs: plen:] caret->paragraph doc offset: doc/caret/offset
			length: doc/measure [length]
			while [offset >= (pofs + plen)] [			;-- switch to next paragraph (maybe multiple times)
				if offset >= length [return length]		;-- no more going right
				set [para: pofs: plen:] caret->paragraph doc offset: offset + 1
			]
			#assert [pofs + plen > offset]				;-- limited by paragraph's tail
			after: skip para/data/items offset - pofs
			parse pos: after [any word-sep any non-word-sep pos:]
			offset + offset? after pos
		]
		
		find-line-above: function ["Get caret (offset, side) one line above"] with :measure [
			caret-row-shift doc doc/caret/offset doc/caret/side 'up 0
		]
		find-line-below: function ["Get caret (offset, side) one line below"] with :measure [
			caret-row-shift doc doc/caret/offset doc/caret/side 'down 0
		]
		
		; find-page-above: function ["Get caret (offset, side) one page above"] with :measure [
			; caret-page-shift doc doc/caret/offset doc/caret/side 'up
		; ]
		; find-page-below: function ["Get caret (offset, side) one page below"] with :measure [
			; caret-page-shift doc doc/caret/offset doc/caret/side 'down
		; ]
	]
	
	actions: context [
		edit: function [doc [object!] plan [block!]] [
			length: doc/measure [length]
			offset: doc/caret/offset
			set [para: pofs: plen:] caret->paragraph doc offset
			do with self plan
		]
		at: select: move: remove: copy: paste: insert: paint: break: auto-bullet: none
	]
	
	;@@ undo
	;@@ redo
	
	actions/at: function ["Get offset of a named location" name [word!]] with :actions/edit [
		switch/default name [
			far-head  [0]
			far-tail  [length]
			head      [pofs]							;-- paragraph's head/tail ;@@ or use row's head/tail? exclude indentation or not?
			tail      [pofs + plen]
			prev-word [doc/measure [find-prev-word]]
			next-word [doc/measure [find-next-word]]
			line-up   [doc/measure [find-line-above]]
			line-down [doc/measure [find-line-below]]
			; page-up   [doc/measure [find-page-above]]			;@@ these need to know page size
			; page-down [doc/measure [find-page-below]]
		] [offset]										;-- on unknown anchors assume current offset
	]
		
	actions/select: function [
		"Extend or redefine selection"
		limit [pair! word! (not by) integer!]
		/by "Move selection edge by an integer number of caret slots"
	] with :actions/edit [
		set [ofs: sel:] field-ctx/compute-selection limit by actions offset length doc/selected
		doc/caret/offset: ofs
		doc/selected: sel
	]
	
	actions/move: function [
		"Displace the caret"
		pos [word! (not by) integer!]
		/by "Move by a relative integer number of slots"
	] with :actions/edit [
		set [para: pofs: plen:] caret->paragraph doc offset
		either by [pos: pos + offset][if word? pos [pos: actions/at pos]]
		if block? pos [									;-- block may be returned by find-line-below/above
			doc/caret/side:   pos/side
			doc/caret/offset: clip 0 length pos/offset
		]
		if integer? pos [								;-- unknown words are silently ignored
			if pos <> offset [doc/caret/side: pick [left right] pos > offset]	;-- only change side if moved
			doc/caret/offset: clip 0 length pos
		]
	]
	
	actions/remove: function [
		"Remove range or from caret up to a given limit"
		limit [word! pair! (not by) integer!]
		/by "Relative integer number of slots from the caret"
	] with :actions/edit [
		;@@ mark history state
		case/all [
			limit = 'selected [limit: doc/selected]
			word?    limit    [limit: actions/at limit]
			block?   limit    [limit: limit/offset]		;-- ignores returned side
			by                [limit: offset + limit]
			integer? limit    [limit: order-pair as-pair limit offset]
			limit             [document/remove doc limit]
		]
	]
	
	actions/copy: function [
		"Copy specified range into clipboard"
		range [word! (find [all selected] range) pair!] "Offset range or any of: [selected all]"
	] with :actions/edit [
		switch range [
			selected [range: doc/selected]
			all      [range: 0 by length]
		]
		slice: when pair? range (document/copy doc range)	;-- silently ignores unsupported range words
		clipboard/write slice
		slice
	]
	
	actions/paste: function [
		"Paste text from clipboard into current caret offset"
	] with :actions/edit [
		if data: clipboard/read [actions/insert data]
	]
	
	actions/insert: function [
		"Insert given data into current caret offset"
		data [block! string!]
	] with :actions/edit [
		;@@ mark history state
		unless empty? data [document/insert doc offset data]	;-- caret gets moved via adjust-offsets
	]
	
	actions/paint: function [
		"Paint given range with an attribute set (only first item's attribute is used)"
		range [pair!] attrs [map!]
	] with :actions/edit [
		document/paint doc range attrs
	]
	
	actions/break: function [
		"Break paragraph at current caret offset"
	] with :actions/edit [
		document/break doc doc/caret/offset
	]
	
	actions/auto-bullet: function [
		"Automatically assign a bullet to current paragraph if previous one has it"
	] with :actions/edit [
		document/auto-bullet doc doc/caret/offset
	]
	
	;@@ rename this to edit, bind `doc` argument
	;@@ 'length' should be under 'measure' context
	document: context [length: copy: remove: insert: break: mark: paint: get-attr: get-attrs: align: linkify: bulletify: enumerate: auto-bullet: none]
	
	document/length: function [doc] [
		doc/measure [length]
	]
	
	document/copy: function [doc [object!] range [pair!]] [
		rowbreak: [[#"^/"] #()]
		result:   reduce [make [] span? range  make map! 4]	;@@ cannot use copy/deep since it won't copy literal map
		ofs:      0
		for-each [p: para prange] map-range doc range [
			data: para/edit [copy prange]
			len: length? para/data/items
			rich/decoded/insert! result ofs data
			if 2 < length? p [rich/decoded/insert! result ofs + len rowbreak]
			ofs: ofs + len + 1
		]
		probe result
	]
		
	;@@ do auto-linkification on space after url!
	document/linkify: function [doc [object!] range [pair!] command [block!]] [
		;; each paragraph becomes a separate link as this is simplest to do
		range: order-pair clip range 0 doc/measure [length]
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
		adjust-offsets doc range/1 1 - span? range
		; print mold/deep items
	]
	
	document/remove: function [doc [object!] range [pair!]] [
		range: order-pair clip range 0 doc/measure [length]
		n: half length? mapped: map-range doc range
		set [para1: range1:] mapped
		set [paraN: rangeN:] skip tail mapped -2 
		if n >= 1 [para1/edit [remove! range1]]
		if n >= 2 [										;-- requires removal of whole paragraphs
			paraN/edit [remove! rangeN]
			para1/edit [insert! range1/1 values-of paraN/data]
			s: find/same/tail doc/content para1
			e: find/same/tail s paraN
			remove/part s e
			doc/content: doc/content
		]
		adjust-offsets doc range/1 negate span? range
		if all [doc/selected  0 = span? doc/selected] [doc/selected: none]	;-- normalize emptied selection
	]
	
	document/insert: function [
		doc    [object!]
		offset [integer!]
		data   [block! (parse data [block! map!]) string!]
		/local _
	][
		either block? data [set [items: attrs:] data][items: data]
		if empty? items [exit]
		set [para1: pofs1:] caret->paragraph doc offset
		pcar1: offset - pofs1
		either string? data [
			para1/edit [insert! pcar1 data]
		][
			rows: parse items [collect [any [keep copy _ to #"^/" skip] keep copy _ to end]]	;@@ split doesn't work on blocks yet
			slice: rich/decoded/copy data 0 by len: length? rows/1
			either single? rows [
				para1/edit [insert! pcar1 slice]
			][
				;; edit first paragraph, but remember the after-insertion part
				para1/edit [							;@@ make another action in edit for this?
					stashed: copy range: pcar1 by infxinf/x
					remove! range
					insert! pcar1 slice 
				]
				;; convert other rows into paragraphs and insert them into doc/content
				ofs: len + 1
				rest: map-each row next rows [
					#assert [items/:ofs = #"^/"]
					len: length? row
					slice: rich/decoded/copy data 0 by len + ofs
					ofs: ofs + len + 1
					make-space 'rich-content [data: slice]
				]
				insert (find/same/tail doc/content para1) rest
				;; append stashed part to the last inserted paragraph
				paraN: last rest
				paraN/edit [insert! infxinf/x stashed]
			]
		]
		adjust-offsets doc offset length? items
	]
	
	document/break: function [
		doc    [object!]
		offset [integer!]
	][
		set [para1: pofs1:] caret->paragraph doc offset
		pcar1: offset - pofs1
		para2: para1/clone
		para1/edit [remove! pcar1 by infxinf/x]
		para2/edit [remove! 0 by pcar1]
		insert (find/same/tail doc/content para1) para2
		adjust-offsets doc offset 1
	]
	
	document/mark: function [doc [object!] range [pair!] attr [word!] value] [
		foreach [para: prange:] map-range doc range [
			para/edit [mark! prange attr :value]
		]
	]
	
	;; replaces all attributes in the range with first attribute in attrs
	document/paint: function [doc [object!] range [pair!] attrs [map!]] [
		if any [empty? attrs  zero? span? range] [exit]
		foreach [para: prange:] map-range doc range [	;@@ need edit func for this?
			length: para/measure [length]
			slice: rich/attributes/extend attrs span: span? range
			rich/attributes/remove! para/data/attrs prange
			rich/attributes/insert! para/data/attrs length prange/1 slice span
			para/data: para/data
		]
	]
	
	document/get-attr: function [space [object!] index [integer!] attr [word!]] [
		if set [para: pofs:] caret->paragraph space offset: index - 1 [
			rich/attributes/pick para/data/attrs attr offset - pofs + 1	;-- may be none esp. on 'new-line' paragraph delimiters
		]
	]
	
	document/get-attrs: function [space [object!] index [integer!]] [
		if set [para: pofs: plen:] caret->paragraph space offset: index - 1 [
			while [all [offset > 0  pofs + plen = offset]] [	;-- no attribute at the 'new-line' delimiter, try above paragraph
				set [para: pofs: plen:] caret->paragraph space offset: offset - 1
			]
			offset: clip 0 (max 0 plen - 1) offset - pofs
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
	
	get-bullet-text: function [para [object!]] [
		all [
			space? bullet: para/data/items/1
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
	
	;@@ maybe this should be less smart and not remove bullets? only add them?
	document/bulletify: function [doc [object!] range [pair!]] [
		if empty? mapped: map-range/extend doc range [exit]
		bulletifying?: any [
			not bulleted-paragraph? mapped/1			;-- already has a bullet? for toggling
			numbered-paragraph? mapped/1
		]
		fix: 0
		foreach [para: prange:] mapped [
			prange: prange + fix						;-- each edit changes next prange
			if bulleted-paragraph? para [				;-- get rid of numbers and old bullets
				para/edit [remove! 0x1]
				adjust-offsets doc prange/1 -1
				fix: fix - 1
			]
			if bulletifying? [
				para/edit [insert! 0 make-space 'bullet []]
				adjust-offsets doc prange/1 1
				fix: fix + 1
			]
		]
	]
	
	;@@ maybe this should be less smart and not remove bullets? only add them?
	document/enumerate: function [doc [object!] range [pair!]] [
		if empty? mapped: map-range/extend doc range [exit]
		set [para: prange:] mapped
		if numbering?: not get-bullet-number para [
			prev-number: all [							;-- fetch number of the previous paragraph
				last-para: pick find/same doc/content para -1
				get-bullet-number last-para
			]
			number: either prev-number [prev-number][0]
		]
		fix: 0
		foreach [para: prange:] mapped [
			prange: prange + fix						;-- each edit changes next prange
			if bulleted-paragraph? para [				;-- remove old bullets/numbers
				para/edit [remove! 0x1]
				adjust-offsets doc prange/1 -1
				fix: fix - 1
			]
			if numbering? [								;-- enumerate
				bullet: make-space 'bullet []
				bullet/text: rejoin [number: number + 1 "."]
				para/edit [insert! 0 bullet]
				adjust-offsets doc prange/1 1
				fix: fix + 1
			]
		]
	]
	
	;@@ maybe functions above should be based on this?
	;@@ maybe they should also inherit font/size/flags from the first char of the first paragraph?
	;@@ also ideally on break/remove/cut/paste paragraph numbers should auto-update, but I'm too lazy
	;; replaces paragraph's bullet following that of the previous paragraph
	document/auto-bullet: function [doc [object!] offset [integer!]] [
		set [para: pofs: plen:] caret->paragraph doc offset
		if prev: pick find/same doc/content para -1 [
			text: either num: get-bullet-number prev
				[rejoin [num + 1 "."]]
				[get-bullet-text prev]
			if text [
				bullet: make-space 'bullet []
				bullet/text: text
			]
		]
		if bulleted-paragraph? para [
			para/edit [remove! 0x1]
			adjust-offsets doc pofs -1
		]
		if bullet [
			para/edit [insert! 0 bullet]
			adjust-offsets doc pofs 1
		]
	]
	
	on-selected-change: function [space [object!] word [word!] value: -1x-1 [pair! none!]] [	;-- -1x-1 acts as deselect-everything
		;; NxN selection while technically empty, is not forbidden or converted to `none`, to avoid surprises in code
		if value/1 > value/2 [
			quietly space/selected: value: reverse value	;-- keep it ordered for simplicity (not for -1x-1 case)
		]
		map-selection space value
	]
	
	point->caret: function [doc [object!] point [pair!]] [		;@@ accept path maybe too?
		path: hittest doc point
		set [para: xy:] skip path 2
		either para [
			#assert [in para 'measure]							;@@ measure is too general name for strictly caret related api?
			;; lands directly into text or rich-content
			caret: para/measure [point->caret xy]
			base: get-paragraph-offset doc para
			caret/offset: caret/offset + base
			caret
		][	;; lands outside - need to find nearest
			;@@ add space box computation to foreach-space ? and ability to skip branches based on that?
			none
		]
	]
	
	;@@ what about no rows case? I need to ensure always at least one row, even empty
	;; if zero-height rows exist, this func will just skip them
	caret-row-shift: function [
		doc   [object!]
		caret [integer!]
		side  [word!]
		dir   [word!] (find [up down] dir)
		shift [integer!] (shift >= 0) "0 for one line, else number of extra pixels (for paging)"
	][
		set [para: pofs: plen:] caret->paragraph doc caret
		pcar: caret - pofs
		pgeom: select/same doc/map para
		pxy: pgeom/offset
		para/measure [
			set [pxy1: pxy2:] caret->box pcar side
			prow: caret->row pcar side
		]
		nrows: para/frame/nrows
		edge-row?: any [
			all [dir = 'up   prow = 1]					;-- first row in the paragraph
			all [dir = 'down prow = nrows]				;-- last row in the paragraph
		]
		shift: 0 by (shift + 1 + either edge-row? [doc/spacing][para/frame/spacing])
		xy: pxy + either dir = 'down [pxy2 + shift][pxy1 - shift]
		caret': point->caret doc xy
		if caret' [										;-- may be none if outside the document
			limits: either dir = 'down					;-- ensure a minimum shift of 1 caret slot (for items spanning multiple rows)
				[caret + 1 by document/length doc]
				[0 by (caret - 1)]
			caret'/offset: clip limits/1 limits/2 caret'/offset
		]
		caret'
	]
		
	draw: function [doc [object!] canvas: infxinf [pair! none!]] [
		;; trick for caret changes to invalidate the document: need to render it once (though it's never displayed)
		unless doc/caret/parent [render doc/caret]
		
		;; para/caret is a space that is moved from paragraph to paragraph, where it gets rendered
		;; not to be confused with doc/caret that is not rendered and only holds the absolute offset
		set [para: pofs:] caret->paragraph doc offset: doc/caret/offset
		old-holder: doc/caret/holder
		new-holder: doc/caret/holder: if focused? [para]		;-- don't draw caret when not in focus
		shared-caret: if old-holder [old-holder/caret]
		unless old-holder =? new-holder [				;-- move caret from one paragraph to another
			if shared-caret [shared-caret/parent: none]
			if old-holder [old-holder/caret: none]
			if new-holder [
				new-holder/caret: any [shared-caret make-space 'caret []]
			]
		]
		if new-holder [									;-- update offsets
			new-holder/caret/side:   doc/caret/side
			new-holder/caret/offset: offset - pofs
		]
		
		drawn: doc/list-draw/on canvas
	]
	
	;; document/caret cannot be assigned to it's paragraphs, because it holds absolute offset
	;; so paragraphs have their own (styled, renderde) caret space, moved from paragraph to paragraph
	;; while document has a fake caret (not rendered), that is only used for invalidation
	;; document invalidation -> document/draw -> updates paragraph/caret -> paragraph/draw
	caret-template: declare-class 'document-caret/caret [
		type:  'caret
		holder: none									;-- child that last owned the generated caret space
	]
	
	declare-template 'document/list [
		axis:   'y		#type (axis = 'y)				;-- protected
		spacing: 5
		
		caret:   make-space 'caret caret-template #type [object!] :invalidates
		
		selected: none	#type [pair! none!] :on-selected-change
		
		measure: func [plan [block!]] [~/metrics/measure self plan]	;@@ needs docstring
		edit: func [
			"Apply a sequence of edits to the text"
			plan [block!]
		][
			~/actions/edit self plan
		] #type [function!]
		
		list-draw: :draw
		draw: func [/on canvas [pair!]] [~/draw self canvas]
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
	either all [range: doc/selected  0 < span? range] [
		old: doc-ctx/document/get-attr doc 1 + range/1 name
		?? [old range] 
		doc-ctx/document/mark doc range name not old
	][
		old: rich/attributes/pick paint name 1
		rich/attributes/mark! paint 1 0x1 name not old
	]
	probe not old
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
enumerate: function [] [
	range: any [
		doc/selected
		1x1 * doc/caret/offset
	]
	doc-ctx/document/enumerate doc range
]
;; current attributes (for inserted chars)
paint: #()
pick-paint: function [/from index: (doc/caret/offset + 1) [integer!]] [	;-- use attrs under the caret by default
	set 'paint doc-ctx/document/get-attrs doc index
	; ?? paint
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
						old: rich/attributes/pick paint 1 'color
						color: request-color/from old
						rich/attributes/mark paint 1 0x1 'color color
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
				icon [image 24x20 data= icons/aligns/fill]    on-click [realign 'fill]
				icon [image 24x20 data= icons/aligns/left]    on-click [realign 'left] 
				icon [image 24x20 data= icons/aligns/center]  on-click [realign 'center]
				icon [image 24x20 data= icons/aligns/right]   on-click [realign 'right]
				icon [image 30x20 data= icons/lists/numbered] on-click [enumerate]
				icon [image 30x20 data= icons/lists/bullet]   on-click [bulletify]
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
					if caret: doc-ctx/point->caret space path/2 [
						set with space/caret [offset side] reduce [caret/offset caret/side]
						start-drag/with path copy caret
						pick-paint
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
							pick-paint
						]
					]
				] on-key [
					if is-key-printable? event [
						space/edit key->plan event space/selected
						if paint [space/edit compose [paint -1x0 + space/caret/offset (paint)]]
					]
				] on-key-down [
					unless is-key-printable? event [
						switch/default event/key [
							#"^M" #"^/" [doc/edit [select 'none  break  auto-bullet]]
						][
							space/edit key->plan event space/selected
							pick-paint
						]
					]
				]
				on-focus [invalidate space] on-unfocus [invalidate space]	;-- shows/hides caret
			]
		]
	] ;with [watch in parent 'offset]
]
prof/show

]
