Red [
	title:   "Document template for Spaces"
	author:  @hiiamboris
	license: BSD-3
]

; #include %everything.red
; #include %watch.red

do/expand with spaces/ctx [

;@@ get rid of this font here!
code-font: make font! with system/view [name: fonts/fixed size: fonts/size]

;; used for numbering paragraph lists
declare-template 'bullet/text [
	text:   "^(2981)"
	format: does [rejoin [text " "]]
	limits: 15 .. none
]

doc-ctx: context [
	~: self
	
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
			;@@ should info be updated after every function call instead? in case they are chained (if ever)
			plan: with self plan
			while [not tail? plan] [					;-- info is updated after every call
				length: doc/measure [length]
				offset: doc/caret/offset
				set [para: pofs: plen:] caret->paragraph doc offset
				do/next plan 'plan
			]
		]
		undo: redo: at: select: move: remove: copy: paste: insert: paint: break: auto-bullet: none
	]
	
	actions/undo: function [] with :actions/edit [doc/timeline/undo]
	actions/redo: function [] with :actions/edit [doc/timeline/redo]
	
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
	
	;; this func simplifies undo/redo code a bit
	make-actions: function [doc [object!] rem [block!] ins [block!] eval [block!]] [
		edit: reduce [doc/selected doc/caret/offset rem]
		do eval
		repend edit [ins doc/caret/offset doc/selected]
		compose/only/deep [
			[document/atomic-edit (doc) (edit) (false)]
			[document/atomic-edit (doc) (edit) (true)]	;-- edit block is shared, so only has to be grouped once when grouping
		]
	]
		
	;; action format: [selection offset [removed] [inserted] offset selection]
	;; so it combines removal with insertion, and is reversible, and contains offset & selection at both ends
	;; can be (easily) grouped if:
	;; - both actions have only [insert] and end-offset2 = start-offset1
	;; - both actions have only [remove] and end-offset2 = start-offset1
	group-actions: function [action1 [block!] "modified" action2 [block!] /local obj obj2 data1 data2 fwd] [
		if all [
			parse action1 ['document/atomic-edit set obj  object! set data1 block! set fwd logic!]
			parse action2 ['document/atomic-edit set obj2 object! set data2 block! fwd]		;-- tests if direction matches
			obj =? obj2									;-- cannot test sameness within parse
			set [sel1-: ofs1-: rem1: ins1: ofs1+: sel1+:] data1
			set [sel2-: ofs2-: rem2: ins2: ofs2+: sel2+:] data2
			ofs2- = ofs1+
			i: case [									;-- index of ins/rem block to modify
				all [empty? rem1 empty? rem2] [4]		;@@ TODO: more grouping cases possible with more complex logic
				all [empty? ins1 empty? ins2] [3]
			]
		][
			#assert [not empty? data2/:i]
			either empty? data1/:i [
				append data1/:i data2/:i
			][
				pos: either ofs2+ >= ofs2- [infxinf/x][0]
				rich/decoded/insert! data1/:i pos data2/:i
			]
			data1/5: data2/5							;-- copy selection & offset over
			data1/6: data2/6
			action1
		]												;-- none if can't group - didn't modify
	]
	
	record-in-timeline: function [doc [object!] rem [block!] ins [block!] eval [block!]] [
		set [left: right:] make-actions doc rem ins eval
		either all [
			doc/timeline/fresh?
			set [doc': left': right':] doc/timeline/last-event
			group-actions right' right					;-- since edit is shared, only one side needs to be modified
		][
			doc/timeline/put/last doc left' right'
		][
			doc/timeline/put doc left right
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
			limit [
				slice: document/copy doc limit
				#assert [any [limit/1 = offset limit/2 = offset]]	;-- otherwise need to update caret/offset
				record-in-timeline doc slice [] [
					document/remove doc limit
				]
			]
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
		unless empty? data [
			if string? data [
				len: length? data
				attrs: rich/attributes/extend doc/paint len
				data: reduce [explode data attrs]
			]
			range: 0 by (length? data/1) + offset
			#assert [doc/caret/offset = offset]			;-- otherwise need to update caret/offset
			record-in-timeline doc [] data [
				document/insert doc offset data			;-- caret gets moved via adjust-offsets
				if doc/paint [document/paint doc offset + 0x1 doc/paint]
			]
		]
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
		actions/insert "^/"
	]
	
	actions/auto-bullet: function [
		"Automatically assign a bullet to current paragraph if previous one has it"
	] with :actions/edit [
		document/auto-bullet doc doc/caret/offset
	]
	
	;@@ rename this to edit, bind `doc` argument
	;@@ 'length' should be under 'measure' context
	document: context [length: atomic-edit: copy: remove: insert: break: mark: paint: get-attr: get-attrs: align: linkify: codify: bulletify: enumerate: auto-bullet: indent: none]
	
	document/length: function [doc [object!]] [
		doc/measure [length]
	]
	
	document/atomic-edit: function [doc [object!] edit [block!] forward? [logic!]] [	;-- used by undo/redo
		unless forward? [edit: reverse copy edit]
		set [sel-: ofs-: rem: ins: ofs+: sel+:] edit
		ofs: min ofs- ofs+								;-- if offset reduces during action, this is where it starts
		if len: length? rem/1 [document/remove doc 0 by len + ofs]
		if len: length? ins/1 [document/insert doc ofs ins]
		doc/selected:     sel+
		doc/caret/offset: ofs+							;@@ should I restore the side too?
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
	
	;@@ some of these funcs are rather non-essential, maybe I should move them somewhere else
	;@@ this in particular also depends on custom templates
	document/codify: function [doc [object!] range [pair!]] [
		range: order-pair clip range 0 doc/measure [length]
		if range/1 = range/2 [exit]
		mapped: map-range doc range
		either 2 = length? mapped [						;-- single line code span
			set [para: prange:] mapped
			text: para/edit [copy/text prange]
			code: make-space 'code compose [text: (text)]
			para/edit [
				remove! prange
				insert! prange/1 code
			]
		][												;-- code block
			#assert [2 < length? mapped]
			;; remove empty paragraphs from the range
			set [para1: prange1:] mapped
			set [paraN: prangeN:] mapped << 2
			if zero? span? prange1 [range/1: range/1 + 1]
			if zero? span? prangeN [range/2: max range/1 range/2 - 1]
			;; remap to full paragraphs and replace
			mapped: map-range/extend doc range
			range: prange1/1 by second last mapped		;-- include full paragraphs into range (for adjust-offsets)
			lines: map-each [para prange] mapped [para/format]	;-- ignores range
			text: to string! delimit lines "^/"
			code: make-space 'pre compose [text: (text)]
			remove/part find/same/tail doc/content para1 -1 + half length? mapped
			para1/edit [
				remove! prange1
				insert! 0 code
			]
		]
		adjust-offsets doc range/1 negate span? range
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
		data   [block!] (parse data [block! map!])
		/local _
	][
		set [items: attrs:] data
		if empty? items [exit]
		set [para1: pofs1:] caret->paragraph doc offset
		pcar1: offset - pofs1
		rows: parse items [collect [any [keep copy _ to #"^/" skip] keep copy _ to end]]	;@@ split doesn't work on blocks yet
		slice: rich/decoded/copy data 0 by len: length? rows/1
		either single? rows [
			para1/edit [insert! pcar1 slice]
		][
			;; edit first paragraph, but remember the after-insertion part
			para1/edit [								;@@ make another action in edit for this?
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
		adjust-offsets doc offset length? items
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
			slice: rich/attributes/extend attrs span: span? prange
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
	
	document/indent: function [doc [object!] range [pair!] offset [integer!]] [
		if offset = 0 [exit]
		foreach [para: prange:] map-range doc range [
			first: max 0 offset + any [if para/indent [para/indent/first] 0]
			rest:  max 0 offset + any [if para/indent [para/indent/rest]  0]
			para/indent: compose [first: (first) rest: (rest)]
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
	;; so paragraphs have their own (styled, rendered) caret space, moved from paragraph to paragraph
	;; while document has a fake caret (not rendered), that is only used for invalidation
	;; document invalidation -> document/draw -> updates paragraph/caret -> paragraph/draw
	caret-template: declare-class 'document-caret/caret [
		type:  'caret
		holder: none									;-- child that last owned the generated caret space
	]
	
	declare-template 'document/list [
		axis:   'y		#type (axis = 'y)				;-- protected
		spacing: 5
		
		caret:    make-space 'caret caret-template #type [object!] :invalidates
		selected: none	#type [pair! none!] :on-selected-change
		timeline: copy timeline!
		paint:    make map! []	#type [map!]			;-- current set of attributes (for newly inserted chars)
		
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


;@@ can I make code templates generic enough to separate them?
declare-template 'code/text []
declare-template 'pre/paragraph []

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
			box 0x0 (size) (rounding)
		]
	]
]

define-styles [
	;@@ leave only document style here!
	code: using [pen] [
		font: code-font
		margin: 4x0
		pen: when color (compose [pen (color)])
		below: [(underbox size 1 3) (pen)]
	]
	;@@ how to name it better? code-paragraph?
	pre: [
		margin: 10
		font: code-font
		below: [(underbox size 2 5)]
	]
	document: [
		below: [push [pen off fill-pen green box 0x0 (size)]]
	]
]


]
