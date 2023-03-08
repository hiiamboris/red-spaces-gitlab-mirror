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
	
	;; maps range into a [paragraph paragraph-range] list, where range is document-relative
	map-range: function [
		doc      [object!]
		range    [pair!]
		extend   [logic!]
		no-empty [logic!]
		relative [logic!]
	][
		range:  order-pair range
		mapped: clear []
		less:   either no-empty [:<=][:<]				;-- by default empty parts (tail/head) of the paragraph are counted (for remove to work)
		foreach-paragraph [para: pofs: plen:] doc [
			prange: range - pofs
			case [
				plen less prange/1 [continue]			;-- not reached the first intersecting paragraph
				prange/2 less 0    [break]				;-- won't be no intersections anymore
				'else [
					prange: either extend [0 by plen][clip prange 0 plen]
					unless relative [prange: prange + pofs]
					repend mapped [para prange]			;-- empty paragraphs are not skipped by design
				]
			]
		]
		copy mapped										;-- may be empty
	]

	extract: function [doc [object!] range [pair!]] [
		map-each [para prange] doc/map-range/relative range [
			also para: para/clone
			para/edit [clip! prange]
		]
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
			while [offset >= (pofs + plen)] [			;-- switch to next paragraph (maybe multiple times)
				if offset >= doc/length [return doc/length]		;-- no more going right
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
	
	
	;; basis for all timeline actions - the rest is built on top of it
	playback: function [doc [object!] plan [block!] /local par val rng] [
		parse plan [any [
			'move   set val integer! (doc/caret/offset: val)
		|	'side   set val word! (doc/caret/side: val)
		|	'select set val [none! | pair!] (doc/selected: val)
		|	'indent set par integer! set val [none! | block!] (doc/content/:par/indent: val)
		|	'align  set par integer! set val word! (doc/content/:par/align: val)
		|	'insert set rng pair! set val block! (document/insert doc rng/1 val)
		|	'remove set rng pair! (document/remove doc rng)
		|	end | p: (ERROR "Invalid plan action at (mold/flat/part p 100)")
		]]
	]
	
	group-edits: function [edit1 [block!] edit2 [block!] /local word par rng2 data2] [
		;; to avoid having "do-nothing" undo blocks it forbids grouping insert & remove into single action
		;; indents & aligns are never grouped out of UX considerations
		if any [
			find edit1 'indent
			find edit2 'indent
			find edit1 'align
			find edit2 'align
			all [find edit1 'insert  find edit2 'remove]
			all [find edit1 'remove  find edit2 'insert]
		] [return no]
		
		#print "grouping (mold edit1) + (mold edit2)"
		parse edit2 [any [s:
			set word ['move | 'select | 'side] skip e: (
				mapparse compose [quote (word) skip] edit1 [[]]
				append/part edit1 s e
			)
		|	set word 'insert set rng2 pair! set data2 block! e: (
				either all [
					set [_: rng1: data1:] p: find/last edit1 'insert
					rng1/2 = rng2/1
				][
					p/2: rng1/1 by rng2/2
					rich/decoded/insert! data1 infxinf/x data2
				][
					append/part edit1 s e
				]
			)
		|	set word 'remove set rng2 pair! e: (
				either all [
					set [_: rng1:] p: find/last edit1 'remove
					any [rng1/1 = rng2/1  rng1/1 = rng2/2]
				][
					p/2: (min rng1/1 rng2/1) + (0 by add span? rng1 span? rng2)
				][
					append/part edit1 s e
				]
			)
		|	end | p: (ERROR "Invalid plan action at (mold/flat/part p 100)")
		]]
		#print "=> (mold edit1)"
		edit1
	];group-edits: function [edit1 [block!] edit2 [block!] /local word par rng2 data2] [
	
	undo-worthy?: function [edit [block!]] [
		not parse edit [any [['move | 'select | 'side] skip]]
	]
	
	push-to-timeline: function [doc [object!] left [block!] right [block!] init [block!]] [
		unless any [undo-worthy? left  undo-worthy? right] [exit]
		left:  reduce ['playback doc left]
		right: reduce ['playback doc right]
		set [sel': car':] init
		if car' <> car: doc/caret/offset [				;@@ remember side or not worth it?
			repend left/3  ['move car']
			repend right/3 ['move car]
		]
		if sel' <> sel: doc/selected [
			repend left/3  ['select sel']
			repend right/3 ['select sel]
		]
		; ?? left ?? right
		either all [
			doc/timeline/fresh?
			set [doc': left': right':] doc/timeline/last-event
			doc' =? doc									;-- last event must come from the same document in a shared timeline
			parse left'  ['playback object! block!]
			parse right' ['playback object! block!]
			group-edits right'/3 right/3
			group-edits left/3   left'/3				;-- left edit is grouped in reverse order
		][
			doc/timeline/put/last doc left right'		;-- refreshes the event timer, even though actions are modifed in place
		][
			doc/timeline/put doc left right
		]
	]
	
	;@@ add ! to destructive actions for consistency with rich-content?
	actions: context [
		edit: function [doc [object!] plan [block!] /local result] [
			init:  reduce [doc/selected doc/caret/offset]	;-- remember them before the edit
			left:  make [] 10							;-- history for undo/redo
			right: make [] 10
			;@@ unfortunately I have to manually call this 'update' in every action - how to automate?
			update: [
				offset: doc/caret/offset
				set [para: pofs: plen:] caret->paragraph doc offset
			]
			set/any 'result do with self plan
			; ?? left ?? right
			push-to-timeline doc left right init
			:result
		]
		record: undo: redo: at: select: move: remove: slice: copy: paste: insert: align: indent: auto-bullet: none
	]
	
	actions/record: function [
		"Record an undo/redo action pair in timeline. Input is composed"
		undo-action [block!]
		redo-action [block!]
	] with :actions/edit [
		insert left  compose/deep/only undo-action 
		append right todo: compose/deep/only redo-action
		playback doc todo 
	]

	actions/undo: function [] with :actions/edit [doc/timeline/undo]
	actions/redo: function [] with :actions/edit [doc/timeline/redo]
	
	actions/at: function ["Get offset of a named location" name [word!]] with :actions/edit [
		do update
		switch/default name [
			far-head  [0]
			far-tail  [doc/length]
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
		do update
		set [ofs: sel:] field-ctx/compute-selection limit by actions offset doc/length doc/selected
		actions/record
			[move (offset) select (doc/selected)]
			[move (ofs) select (sel)]
	]
	
	actions/move: function [
		"Displace the caret"
		pos [word! (not by) integer!]
		/by "Move by a relative integer number of slots"
	] with :actions/edit [
		do update
		case/all [
			by [pos: pos + offset]
			word? pos [
				pos: actions/at pos
				if block? pos [							;-- block may be returned by find-line-below/above
					side: pos/side
					pos:  clip 0 doc/length pos/offset
				]
			]
			integer? pos [								;-- unknown words are silently ignored
				default side: case [pos > offset ['left] pos < offset ['right]]	;-- only change side if moved
				pos: clip 0 doc/length pos
				actions/record [move (offset)] [move (pos)]
				if side [actions/record [side (doc/caret/side)] [side (side)]]
			]
		]
	]
	
	actions/remove: function [
		"Remove range or from caret up to a given limit"
		limit [word! pair! (not by) integer!]
		/by "Relative integer number of slots from the caret"
	] with :actions/edit [
		do update
		case/all [
			limit = 'selected [limit: doc/selected]
			word?    limit    [limit: actions/at limit]
			block?   limit    [limit: limit/offset]		;-- block may be returned by `at`, ignores side
			by                [limit: offset + limit]
			integer? limit    [limit: order-pair as-pair limit offset]
			limit [
				slice: copy-range doc limit no
				actions/record [insert (limit) (slice)] [remove (limit)]
			]
		]
	]
	
	actions/slice: function [
		"Extract specified range"
		range [word! (find [all selected] range) pair!] "Offset range or any of: [selected all]"
		/text "Return it as plain text"
	] with :actions/edit [
		do update
		switch range [
			selected [range: doc/selected]
			all      [range: 0 by doc/length]
		]
		unless pair? range [return copy pick ["" []] text]		;-- silently ignores unsupported range words
		copy-range doc range text
	]
	
	actions/copy: function [
		"Copy specified range into clipboard"
		range [word! (find [all selected] range) pair!] "Offset range or any of: [selected all]"
	] with :actions/edit [
		if slice: actions/slice range [clipboard/write slice]
		slice
	]
	
	actions/paste: function [
		"Paste text from clipboard into current caret offset"
	] with :actions/edit [
		if data: clipboard/read [actions/insert data]
	]
	
	actions/insert: function [
		"Insert given data into current caret offset"
		data [block! (parse data [block! map!]) object! (space? data) string!]
		/at pos [integer!] 
	] with :actions/edit [
		do update
		case [
			object? data [data: reduce [reduce [data] copy #()]]
			empty?  data [exit]
			string? data [data: paint-string doc data]
		]
		range: 0 by (length? data/1) + any [pos offset]
		actions/record [remove (range)] [insert (range) (data)]
	]
	
	actions/align: function [
		"Realign selected paragraph(s)"
		align [word!]
	] with :actions/edit [
		do update
		range:  any [doc/selected  offset * 1x1]
		mapped: doc/map-range range
		base:   skip? find/same doc/content mapped/1
		for-each [/i para prange] mapped [
			 actions/record
			 	[align (base + i) (para/align)]
			 	[align (base + i) (align)]
		]
	]
	
	actions/indent: function [
		"Reindent selected paragraph(s)"
		indent [block! (parse indent [2 [set-word! integer!]]) integer!]
			"Relative integer offset or absolute [first: int! rest: integer!] block"
	] with :actions/edit [
		do update
		range:  any [doc/selected  offset * 1x1]
		mapped: doc/map-range range
		base:   skip? find/same doc/content mapped/1
		for-each [/i para prange] mapped [
			unless block? pindent: indent [
				first: max 0 indent + any [if para/indent [para/indent/first] 0]
				rest:  max 0 indent + any [if para/indent [para/indent/rest]  0]
				pindent: compose [first: (first) rest: (rest)]
			]
			actions/record
				[indent (base + i) (para/indent)]
				[indent (base + i) (pindent)]
		]
	]
	
	actions/auto-bullet: function [
		"Automatically assign a bullet to current paragraph if previous one has it"
	] with :actions/edit [
		auto-bullet doc doc/caret/offset
	]
	
	document: context [remove: insert: break: mark: paint: get-attr: get-attrs: bulletify: enumerate: none]
	
	copy-range: function [doc [object!] range [pair!] plain-text? [logic!]] [
		mapped: doc/map-range/relative range
		either plain-text? [
			lines: map-each para extract doc range [para/format]
			to string! delimit lines "^/"
		][
			rowbreak: [[#"^/"] #()]
			result:   reduce [make [] span? range  make map! 4]	;@@ cannot use copy/deep since it won't copy literal map
			ofs:      0
			for-each [p: para prange] mapped [
				data: para/edit [copy prange]
				len: length? para/data/items
				rich/decoded/insert! result ofs data
				if 2 < length? p [rich/decoded/insert! result ofs + len rowbreak]
				ofs: ofs + len + 1
			]
			result
		]
	]
		
	document/remove: function [doc [object!] range [pair!]] [
		range: order-pair clip range 0 doc/length
		n: half length? mapped: doc/map-range/relative range
		set [para1: range1:] mapped
		set [paraN: rangeN:] skip tail mapped -2 
		if n >= 1 [para1/edit [remove! range1]]
		if n >= 2 [										;-- requires removal of whole paragraphs
			paraN/edit [remove! rangeN]
			para1/edit [insert! range1/1 values-of paraN/data]
			s: find/same/tail doc/content para1
			e: find/same/tail s paraN
			remove/part s e
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
		foreach [para: prange:] doc/map-range/relative range [
			para/edit [mark! prange attr :value]
		]
	]
	
	;; replaces all attributes in the range with first attribute in attrs
	document/paint: function [doc [object!] range [pair!] attrs [map!]] [
		if any [empty? attrs  zero? span? range] [exit]
		foreach [para: prange:] doc/map-range/relative range [	;@@ need edit func for this?
			length: para/measure [length]
			slice: rich/attributes/extend attrs span: span? prange
			rich/attributes/remove! para/data/attrs prange
			rich/attributes/insert! para/data/attrs length prange/1 slice span
			para/data: para/data
		]
	]
	
	document/get-attr: function [doc [object!] index [integer!] attr [word!]] [
		if set [para: pofs:] caret->paragraph doc offset: index - 1 [
			rich/attributes/pick para/data/attrs attr offset - pofs + 1	;-- may be none esp. on 'new-line' paragraph delimiters
		]
	]
	
	document/get-attrs: function [doc [object!] index [integer!]] [
		offset: clip index - 1 0 doc/length
		if set [para: pofs: plen:] caret->paragraph doc offset [
			;; no attribute at the 'new-line' delimiter, so it tries to get them from:
			;; - last char of this paragraph (if not empty)
			;; - last char of some non-empty above paragraph
			;@@ maybe unify all paragraph/data into single document/data so newlines will have attrs?
			while [all [offset > 0  pofs + plen = offset]] [	
				set [para: pofs: plen:] caret->paragraph doc offset: offset - 1
			]
			if pofs + plen > offset [
				rich/attributes/copy para/data/attrs 0x1 + offset - pofs
			]											;-- none if cannot pick the attribute
		]
	]
	
	;; used to correct caret and selection offsets after an edit
	adjust-offsets: function [doc [object!] offset [integer!] shift [integer!]] [
		sel: doc/selected								;-- can't set components of doc/selected (due to reordering)
		foreach path [sel/1 sel/2 doc/length doc/caret/offset] [
			if attempt [offset <= value: get path] [	;@@ REP #113
				set path max offset value + shift
			]
		]
		doc/selected: sel								;-- trigger update of /selected
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
		if empty? mapped: doc/map-range/extend/no-empty range [exit]
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
		if empty? mapped: doc/map-range/extend/no-empty range [exit]
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
	auto-bullet: function [doc [object!] offset [integer!]] [
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
			quietly space/selected: value: reverse value		;-- keep it ordered for simplicity (not for -1x-1 case)
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
			set [rxy1: rxy2:] row->box prow
		]
		pxy1/y: rxy1/y									;-- extend caret box to the full row
		pxy2/y: rxy2/y
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
				[caret + 1 by doc/length]
				[0 by (caret - 1)]
			caret'/offset: clip limits/1 limits/2 caret'/offset
		]
		caret'
	]
		
	paint-string: function [doc [object!] string [string!]] [	;-- automatically fills string with attributes
		attrs: rich/attributes/extend doc/paint length? string
		items: explode string
		reduce [items attrs]
	]
			
	pick-paint: function [doc [object!] /from offset: doc/caret/offset [integer!]] [	;-- use attrs near the caret by default
		doc/paint: any [
			;; question is, should it pick the attribute from before the caret or after?
			;; before probably makes more sense for appending, then if that fails it also tries after
			document/get-attrs doc offset
			document/get-attrs doc offset + 1
			clear doc/paint								;-- no attributes if can't pick up
		]
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
	
	on-content-change: function [doc [object!] word [word!] content [block!]] [
		if unset? :doc/measure [exit]					;-- wait for init
		doc/length: doc/measure [length]
		invalidate doc
	]
	
	on-caret-move: function [caret [object!] word [word!] offset [integer!]] [
		if caret/parent [pick-paint caret/parent]
		invalidate caret
	]
	
	;; document/caret cannot be assigned to it's paragraphs, because it holds absolute offset
	;; so paragraphs have their own (styled, rendered) caret space, moved from paragraph to paragraph
	;; while document has a fake caret (not rendered), that is only used for invalidation
	;; document invalidation -> document/draw -> updates paragraph/caret -> paragraph/draw
	caret-template: declare-class 'document-caret/caret [
		type:  'caret
		holder: none									;-- child that last owned the generated caret space
		offset: 0	#on-change :on-caret-move			;-- on top of invalidation, also updates the paint
	]
	
	;@@ should it support /items override? what will be the use case? spoilers? (for now length accounts for every paragraph)
	declare-template 'document/list [
		content: []		#type :on-content-change
		axis:   'y		#type (axis = 'y)				;-- protected
		spacing: 5
		
		length:   0		#type [integer!]				;-- read-only, auto-updated on edits
		caret:    make-space 'caret caret-template #type [object!] :invalidates
		selected: none				#type [pair! none!] :on-selected-change
		timeline: copy timeline!	#type [object!]
		paint:    make map! []		#type [map!]			;-- current set of attributes (for newly inserted chars), updated on caret movement
		
		;; high-level functions
		measure: func [plan [block!]] [~/metrics/measure self plan]	;@@ needs docstring
		edit: func [
			"Apply a sequence of edits to the text and store it on the timeline"
			plan [block!]
		][
			~/actions/edit self plan
		] #type [function!]
		
		;; lower-level functions
		map-range: function [
			"Get a list of [paragraph range] intersecting the given document range"
			range [pair!]
			/extend   "Extend range to full paragraphs"
			/no-empty "Exclude empty intersections"
			/relative "Return ranges relative to paragraphs themselves"
		][
			~/map-range self range extend no-empty relative
		] #type [function!]
		
		extract: function [
			"Extract paragraphs intersecting the document range"
			range [pair!]
		][
			~/extract self range
		] #type [function!]
		
		list-draw: :draw
		draw: func [/on canvas [pair!]] [~/draw self canvas]
	]
]

context [
	;@@ pageup/down keys events
	declare-template 'editor/scrollable [
		content: make-space 'document []
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
	code: using [pen] [	;@@ code-span?
		font: code-font
		margin: 4x0
		pen: when color (compose [pen (color)])
		below: [(underbox size 1 3) (pen)]
	]
	;@@ how to name it better? code-paragraph? code-block?
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
