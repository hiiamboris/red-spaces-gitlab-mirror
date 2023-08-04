Red [
	title:   "Document and basic editor template for Spaces"
	author:  @hiiamboris
	license: BSD-3
]


do/expand with spaces/ctx [

doc-ctx: context [
	~: self
	
	append focus/focusable 'document

	;@@ scalability problem: convenience of integer caret/selection offsets leads to linear increase of caret-to-offset calculation
	;@@ don't wanna optimize this prematurely but for big texts a b-tree index should be implemented
	;@@ another unoptimized area is paragraph to caret offset calculation
	;@@ one more consideration: since document can be in every cell of a grid, it should be kept lightweight, optimized for 1-3 paragraphs
	
	foreach-paragraph: function [spec [block!] "[paragraph offset length]" doc [object!] code [block!]] [
		if empty? doc/content [return none]				;-- case for loop never entered
		offset: 0
		foreach para doc/content [
			plen: batch para [length]
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
					prange: either extend [0 thru plen][clip prange 0 plen]
					unless relative [prange: prange + pofs]
					repend mapped [para prange]			;-- empty paragraphs are not skipped by design
				]
			]
		]
		copy mapped										;-- may be empty
	]

	;; extraction has to copy paragraphs to carry alignment and indentation attributes
	extract: function [doc [object!] range [pair!] /block "Always extract as paragraph list"] [
		mapped: batch doc [map-range/relative range]
		either any [block  2 < length? mapped] [		;-- extract paragraphs
			block: map-each [para prange] mapped [
				also para: batch para [clone]
				batch para [clip-range prange]
			]
			make rich-text-block! [data: block]
		][												;-- extract text span
			set [para: prange:] mapped
			span: batch para [copy-range prange]
			make rich-text-span! [data: span]
		]
	]

	;; basis for all timeline actions - the rest is built on top of it
	playback: function [doc [object!] plan [block!] /local par val rng] [
		parse plan [any [
			'move   set val integer! (doc/caret/offset: val)
		|	'side   set val word! (doc/caret/side: val)
		|	'select set val [none! | pair!] (doc/selected: val)
		|	'indent set par integer! set val [none! | block!] (doc/content/:par/indent: val)
		|	'align  set par integer! set val word! (doc/content/:par/align: val)
		|	'insert set rng pair! set val object! (
				#assert [val/length = span? rng]
				insert-data doc rng/1 val
			)
		|	'remove set rng pair! (remove-range doc rng)
		|	end | p: (ERROR "Invalid plan action at (mold/flat/part p 100)")
		]]
	]
	
	robot-time: 0:0:0.02								;-- human can't do things faster than every 20ms, so these are always grouped
	human-time: 0:0:1									;-- when human pauses for this period, group is guaranteed to close
		
	;; returns modifying action (word) if it's not mixed with other modifying actions
	primary-action?: function [edit [block!]] [
		any-action: ['indent | 'align | 'insert | 'remove]
		parse edit [
			to any-action set action skip (action: to lit-word! action)		;@@ extra headache - see REP 142
			any [action | not any-action skip]
			end (return action)
		]
		none
	]
	#assert [
		none?     primary-action? [remove 0x1 insert 0x1 [#"a" 0]]
		'remove = primary-action? [remove 0x1 remove 0x1]
		'insert = primary-action? [insert 0x1 [#"b" 0] insert 0x1 [#"a" 0]]
	]
		
	;; used to check grouping possibility before doing any destructive changes
	groupable?: function [edit1 [block!] edit2 [block!] elapsed [time!]] [
		case [
			elapsed <= robot-time [yes]
			elapsed >= human-time [no]
			;; to avoid having "do-nothing" undo blocks I have to forbid grouping insert & remove into single action
			;; indents & aligns are also never grouped out of UX considerations, so that leaves equality of actions
			'else [
				all [
					action1: primary-action? edit1
					action1 = action2: primary-action? edit2
				]
			] 
		]
	]
		
	group-edits: function [edit1 [block!] edit2 [block!] elapsed [time!] /local word par rng2 data2] [
		#assert [groupable? edit1 edit2 elapsed]
		;; there can be dumb grouping (append/insert) or more sophisticated - modification of insert/remove data
		;; latter is used solely to make undo data smaller in the face of lots of single character insertions/removals
		;; smart grouping rules are:
		;;   move/select/side: latter overrides the former
		;;   insert: same data format + latter inserts starts where former ends
		;;   remove: latter removal either ends or starts where the former starts
		; #print "grouping (mold edit1) + (mold edit2)"
		parse edit2 [any [s:
			set word ['move | 'select | 'side] skip e: (
				mapparse compose [quote (word) skip] edit1 [[]]	;-- removes all previous actions of the same kind
				append/part edit1 s e
			)
		|	set word ['align | 'indent] 2 skip e: (		;-- no reason for smart grouping
				append/part edit1 s e
			)
		|	set word 'insert set rng2 pair! set data2 object! e: (
				either all [
					set [_: rng1: data1:] p: find/last edit1 'insert
					rng1/2 = rng2/1
					'rich-text-span = data1/name
					'rich-text-span = data2/name
				][
					p/2: rng1/1 thru rng2/2
					append data1/data data2/data
				][
					append/part edit1 s e
				]
			)
		|	set word 'remove set rng2 pair! e: (
				either all [
					set [_: rng1:] p: find/last edit1 'remove
					any [rng1/1 = rng2/1  rng1/1 = rng2/2]
				][
					p/2: (min rng1/1 rng2/1) + (0 thru add span? rng1 span? rng2)
				][
					append/part edit1 s e
				]
			)
		|	end | p: (ERROR "Invalid plan action at (mold/flat/part p 100)")
		]]
		; #print "=> (mold edit1)"
		edit1											;-- when succeeds, edit1 is modified in place
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
			elapsed: doc/timeline/elapsed?				;-- returns none if timeline is empty
			set [doc': left': right':] doc/timeline/last-event
			doc' =? doc									;-- last event must come from the same document in a shared timeline
			parse left'  ['playback object! block!]
			parse right' ['playback object! block!]
			groupable? right'/3 right/3 elapsed			;-- check groupability before modifying in place
			groupable? left/3   left'/3 elapsed
		][
			group-edits right'/3 right/3 elapsed
			group-edits left/3   left'/3 elapsed		;-- left edit is grouped in reverse order
			doc/timeline/put/last doc left right'		;-- refreshes the event timer, even though actions are modifed in place
		][
			doc/timeline/put doc left right
		]
	]
	
	;; words are split by word separator chars (space, tab) and paragraph delimiter
	word-sep:     [#" " | #"^-"]
	non-word-sep: [not word-sep skip]
		
	get-length: function ["Get length of the document" doc [object!]] [	;@@ need to cache it (and maybe put into /length facet?)
		unless para: last doc/content [return 0]
		add get-paragraph-offset doc para
			batch para [length]
	]
		
	kit: make-kit 'document [
		length: function ["Get document length in items"] [
			space/length
		]
		
		everything: function ["Get full range of text"] [		;-- used by macro language, e.g. `select-range everything`
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [	;-- used by macro language, e.g. `remove-range selected`
			all [sel: space/selected  sel/1 <> sel/2  order-pair sel]
		]
		
		here: function ["Get current caret offset"] [
			space/caret/offset
		]
		
		caret->paragraph: function [
			"Get paragraph and its range at given offset"
			offset [integer!]
		][
			if set [para: pofs: plen:] ~/caret->paragraph space offset [
				reduce [para 0 thru plen + pofs]				;@@ use range for the other func too?
			]
		]
		
		paragraph-range: function [
			"Get offset range of paragraph containing given offset"
			para [integer! object!] "Paragraph number or its space object"
		][
			either integer? para [
				second caret->paragraph para
			][
				plen: batch para [length]
				0 thru plen + get-paragraph-offset space para
			]
		]
		
		paragraph-head: function [
			"Get offset of the start of paragraph containing given offset"
			offset [integer! object!] "Paragraph number or its space object"
		][
			first paragraph-range offset
		]
		
		paragraph-tail: function [
			"Get offset of the end of paragraph containing given offset"
			offset [integer! object!] "Paragraph number or its space object"
		][
			second paragraph-range offset
		]
		
		word-before: function [
			"Get offset of the word's start before given offset"
			offset [integer!]
		][
			set [para: prange:] caret->paragraph offset
			while [offset <= prange/1] [				;-- switch to previous paragraph (maybe multiple times)
				if offset <= 0 [return 0]				;-- no more going left
				set [para: prange:] caret->paragraph offset: offset - 1
			]
			#assert [prange/1 < offset]					;-- limited by paragraph's head
			e: skip s: para/data offset - prange/1 * 2
			before: reverse system/words/extract (copy/part s e) 2
			parse before [any word-sep any non-word-sep before:]
			offset - skip? before
		]
		
		word-after: function [
			"Get offset of the word's end after given offset"
			offset [integer!]
		][
			set [para: prange:] caret->paragraph offset
			while [offset >= prange/2] [				;-- switch to next paragraph (maybe multiple times)
				if offset >= length [return length]		;-- no more going right
				set [para: prange:] caret->paragraph offset: offset + 1
			]
			#assert [prange/2 > offset]					;-- limited by paragraph's tail
			after: skip para/data offset - prange/1 * 2
			parse pos: after [any [word-sep skip] any [non-word-sep skip] pos:]
			offset + half offset? after pos
		]
		
		pick-attrs: function [
			"Get attributes code for the item at given index"
			index [integer!]
		][
			~/pick-attrs space index
		]
		
		pick-attr: function [
			"Get chosen attribute's value for the item at given index"
			index [integer!] attr [word!]
		][
			~/pick-attr space index attr
		]
		
		frame: object [
			point->caret: function [
				"Get caret offset and side near the point XY on last frame"
				point [planar!]
			][
				~/point->caret space point
			]
		
			caret-box: function [
				"Get box [xy1 xy2] of the caret at given offset and side on last frame"
				offset [integer!] side [word!]
			][
				all [
					set [para: prange:] caret->paragraph offset
					geom: select/same space/map para
					box: batch para [frame/caret-box offset - prange/1 side]
					; ?? [para prange geom box]
					map-each xy box [geom/offset + xy]
				]
			]
			
			line-above: function [
				"Get caret (offset, side) one line above"
				offset [integer!] side [word!]
			][
				caret-row-shift space offset side 'up 0
			]
			line-below: function [
				"Get caret (offset, side) one line below"
				offset [integer!] side [word!]
			][
				caret-row-shift space offset side 'down 0
			]
			
			page-above: function [
				"Get caret (offset, side) one page above"
				offset [integer!] side [word!]
			][
				caret-row-shift space offset side 'up space/page-size
			]
			page-below: function [
				"Get caret (offset, side) one page below"
				offset [integer!] side [word!]
			][
				caret-row-shift space offset side 'down space/page-size
			]
		]
		
		map-range: function [
			"Get a list of [paragraph range] intersecting the given document range"
			range [pair!]
			/extend   "Extend range to full paragraphs"
			/no-empty "Exclude empty intersections (may return empty list)"
			/relative "Return ranges relative to paragraphs themselves"
		][
			~/map-range space range extend no-empty relative
		]
		
		extract: function [
			"Extract paragraphs intersecting the document range"
			range [pair!]
			 /block "Always extract as paragraph list"
		][
			~/extract/:block space range
		]
		
		record: function [
			"Record an undo/redo action pair in timeline. Input is composed"
			undo-action [block!]
			redo-action [block!]
		][
			init:  reduce [space/selected here]			;-- remember them before the edit
			left:  compose/deep/only undo-action 
			right: compose/deep/only redo-action
			; ?? left ?? right
			playback space right 
			push-to-timeline space left right init
			space/modified?: yes						;-- will adjust origin on next render!
		]

		undo: does [space/timeline/undo]
		redo: does [space/timeline/redo]
	
		locate: function [								;@@ maybe always return side too?
			"Get offset (and in some cases side) of a named location"
			name [word!]
		][
			switch/default name [
				far-head  [0]
				far-tail  [length]
				head      [paragraph-head here]			;@@ or use row's head/tail? exclude indentation or not?
				tail      [paragraph-tail here]
				prev-word [word-before    here]
				next-word [word-after     here]
				line-up   [frame/line-above here space/caret/side]
				line-down [frame/line-below here space/caret/side]
				page-up   [frame/page-above here space/caret/side]	;-- these need to know /page-size
				page-down [frame/page-below here space/caret/side]
			] [here]									;-- on unknown anchors assume current offset
		]
		
		select-range: function [
			"Redefine selection or extend up to a given limit"
			limit [word! pair! none! (not by) integer!]
			/by "Move selection edge by an integer number of items"
		][
			set [ofs: sel:] field-ctx/compute-selection space limit thru here length selected
			record
				[move (here) select (selected)]
				[move (ofs)  select (sel)]
		]
	
		move-caret: function [
			"Displace the caret"
			pos [word! (not by) integer!]
			/by "Move by a relative integer number of items"
			/side cside [word!] "Specify caret side" (find [left right] cside)
		][
			case/all [
				by [pos: pos + here]
				word? pos [
					pos: locate pos
					if block? pos [						;-- block may be returned by line-below/above
						default cside: pos/side
						pos: clip 0 length pos/offset
					]
				]
				integer? pos [							;-- unknown words are silently ignored
					default cside: case [pos > here ['left] pos < here ['right]]	;-- only change side if moved
					pos: clip 0 length pos
					record [move (here)] [move (pos)]
					if cside [record [side (space/caret/side)] [side (cside)]]
				]
			]
		]
	
		remove-range: function [
			"Remove range or from caret up to a given limit"
			limit [word! pair! none! (not by) integer!]
			/by "Relative integer number of items from the caret"
			/clip "Write it into clipboard"
		][
			unless limit [exit]
			case/all [
				by             [limit: here + limit]
				word?    limit [limit: locate limit]
				block?   limit [limit: limit/offset]			;-- block may be returned by `locate`, ignores side
				integer? limit [limit: as-pair limit here]
				limit [
					limit: order-pair system/words/clip limit 0 length
					unless limit/1 = limit/2 [
						slice: extract limit
						if clip [clipboard/write slice]
						record [insert (limit) (slice)] [remove (limit)]
					]
				]
			]
		]
	
		copy-range: function [
			"Copy and return specified range of items"
			range [pair!]
			/text  "Return it as plain text"
			/block "Always return paragraph list"
			/clip  "Write it into clipboard"
		][
			slice: extract/:block range
			if clip [clipboard/write slice]
			if text [slice: slice/format]
			slice
		]
	
		paste: function [
			"Paste text from clipboard at given offset"
			offset [integer!]
		][
			if data: clipboard/read [insert-items offset data]
		]
	
		insert-items: function [
			"Insert given data at given offset"
			offset [integer!]
			data [object! (any [space? data  'clipboard-format = class? data]) string!]
		][
			case [
				string? data [data: paint-string space data]
				space?  data [data: make rich-text-span! compose/deep [data: [(data) 0]]]
				not find [rich-text-span rich-text-block] data/name [	;-- unsupported clipboard format (incl. text) inserted as text
					data: paint-string space data/format
				]
			]
			if 0 <> data/length [
				range: 0 thru data/length + offset
				record [remove (range)] [insert (range) (data)]
			]
		]
	
		change-range: function [
			"Remove range or from caret up to a given limit, and insert items there"
			limit [word! pair!]
			data [object! (any [space? data  'clipboard-format = class? data]) string!]
		][
			if word?    limit [limit: locate limit]
			if integer? limit [limit: order-pair limit thru here]
			remove-range limit
			insert-items limit/1 data
		]
		
		mark-range: function [
			"Change attribute value over given range"
			range [pair! none!]
			attr  [word!]
			value [none! logic! scalar! any-string!]	;@@ what other types to allow? words?
				"When falsey, attribute is cleared"
		][
			unless zero? span? range: clip order-pair range 0 length [
				;; for undoability this has to remove then insert whole paragraphs
				slice:  extract range
				marked: extract range
				either marked/name = 'rich-text-block [
					foreach para marked/data [batch para [mark-range everything attr :value]]
				][
					rich/attributes/mark marked/data 'all attr :value
				]
				sel: space/selected						;-- remember selection to restore it afterwards
				record
					[remove (range) insert (range) (slice)  select (sel)]
					[remove (range) insert (range) (marked) select (sel)]
			]
		]
	
		align-range: function [
			"Realign paragraph(s) spanned by given range"
			range: here [pair! integer! none!] "Range or offset, or none for caret location"
			align [word!]
		][
			if integer? range [range: range * 1x1]
			mapped: map-range range
			base:   skip? find/same space/content mapped/1
			for-each [/i para prange] mapped [
				 record
				 	[align (base + i) (para/align)]
				 	[align (base + i) (align)]
			]
		]
	
		indent-range: function [
			"Reindent paragraph(s) spanned by given range"
			range: here [pair! integer! none!] "Range or offset, or none for caret location"
			indent [block! (parse indent [2 [set-word! integer!]]) integer!]
				"Relative integer offset or absolute [first: int! rest: integer!] block"
		][
			if integer? range [range: range * 1x1]
			mapped: map-range range
			base:   skip? find/same space/content mapped/1
			for-each [/i para prange] mapped [
				unless block? new-indent: indent [
					first: max 0 indent + any [get-safe 'para/indent/first 0]
					rest:  max 0 indent + any [get-safe 'para/indent/rest  0]
					new-indent: compose [first: (first) rest: (rest)]
				]
				record
					[indent (base + i) (para/indent)]
					[indent (base + i) (new-indent)]
			]
		]
	];kit: make-kit 'document [
	
	;; these are low level functions bypassing undo mechanism
	remove-range: function [doc [object!] range [pair!]] [
		range: order-pair clip range 0 doc/length
		n: half length? mapped: batch doc [map-range/relative range]
		set [para1: range1:] mapped
		set [paraN: rangeN:] skip tail mapped -2 
		if n >= 1 [batch para1 [remove-range range1]]
		if n >= 2 [										;-- requires removal of whole paragraphs
			batch paraN [remove-range rangeN]
			batch para1 [insert-items range1/1 paraN/data]
			remove/part
				s: find/same/tail doc/content para1		;@@ make content a hash or how to faster find it all?
				find/same/tail s paraN
		]
		adjust-offsets doc range/1 negate span? range
		if all [doc/selected  0 = span? doc/selected] [doc/selected: none]	;-- normalize emptied selection
	]
	
	insert-data: function [
		doc    [object!]
		offset [integer!]
		data   [object!] (find [rich-text-span rich-text-block] select data 'name)
	][
		if empty? data/data [exit]
		list: select (data: data/copy) 'data			;-- will modify paragraphs data in place!
		set [dst-para: dst-ofs:] caret->paragraph doc offset
		dst-loc: offset - dst-ofs
		len: data/length
		case [
			data/name = 'rich-text-span [
				#assert [not find list #"^/"]
				batch dst-para [insert-items dst-loc list]
			]
			single? data/data [
				batch dst-para [insert-items dst-loc list/1/data]
			]
			'multiline [
				;; edit first paragraph, but remember the after-insertion part
				batch dst-para [
					stashed: copy-range range: dst-loc thru 2e9
					change-range range list/1/data 
				]
				;; insert other paragraphs into doc/content
				insert (find/same/tail doc/content dst-para) next list
				;; append stashed part to the last inserted paragraph
				paraN: last list
				batch paraN [insert-items infxinf/x stashed]
			]
		]
		adjust-offsets doc offset len
	]
		
	pick-attr: function [doc [object!] index [integer!] attr [word!]] [
		if set [para: pofs:] caret->paragraph doc offset: index - 1 [
			batch para [pick-attr offset - pofs + 1 attr]
		]												;-- none on 'new-line' delimiters, or if attr is not set
	]
	
	pick-attrs: function [doc [object!] index [integer!]] [
		offset: clip index - 1 0 doc/length
		if set [para: pofs: plen:] caret->paragraph doc offset [
			;; no attribute at the 'new-line' delimiter, so it tries to get them from:
			;; - last char of this paragraph (if not empty)
			;; - last char of some non-empty above paragraph
			;@@ maybe unify all paragraph/data into single document/data so newlines will have attrs?
			;@@ but this data won't contain paragraph alignment/indentation
			while [all [offset > 0  pofs + plen = offset]] [	
				set [para: pofs: plen:] caret->paragraph doc offset: offset - 1
			]
			batch para [pick-attrs offset - pofs + 1]
		]												;-- may return none if can't find any attrs
	]
	
	;; used to correct caret and selection offsets after an edit
	adjust-offsets: function [doc [object!] offset [integer!] shift [integer!]] [
		foreach path [doc/selected/1 doc/selected/2 doc/length doc/caret/offset] [
			if attempt [offset <= value: get path] [
				set path max offset value + shift
			]
		]
	]
	
	on-selected-change: function [space [object!] word [word!] value: -1x-1 [pair! none!]] [	;-- -1x-1 acts as deselect-everything
		;; NxN selection while technically empty, is not forbidden or converted to `none`, to avoid surprises in code
		map-selection space value
	]
	
	point->caret: function [doc [object!] point [planar!]] [	;@@ accept path maybe too?
		path: hittest doc point
		set [para: xy:] skip path 2
		if all [not para  not empty? doc/map] [					;-- doesn't land on a paragraph - need to find nearest
			points: map-each/eval [para geom] doc/map [
				closest: closest-box-point?/to 0x0 geom/size ppoint: point - geom/offset
				dist: distance? closest ppoint 
				[dist closest para]
			]
			set [_: xy: para:] sort/skip points 3
		]
		if para [
			caret: batch para [frame/point->caret xy]
			base: get-paragraph-offset doc para
			caret/offset: caret/offset + base
			caret
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
		pgeom: select/same doc/map para					;@@ how to look up paragraphs fast?
		pxy: pgeom/offset
		batch para [
			set [pxy1: pxy2:] frame/caret-box pcar side
			prow: frame/caret->row pcar side
			set [rxy1: rxy2:] frame/row-box prow
			nrows: frame/line-count
		]
		pxy1/y: rxy1/y									;-- extend caret box to the full row
		pxy2/y: rxy2/y
		edge-row?: any [
			all [dir = 'up   prow = 1]					;-- first row in the paragraph
			all [dir = 'down prow = nrows]				;-- last row in the paragraph
		]
		shift: as-point2D 0 (shift + 1 + either edge-row? [doc/spacing][para/frame/spacing])
		xy: pxy + either dir = 'down [pxy2 + shift][pxy1 - shift]
		xy: clip xy 0x0 doc/size - 0x1
		caret': point->caret doc xy
		if caret' [										;-- may be none if outside the document
			limits: either dir = 'down					;-- ensure a minimum shift of 1 caret slot (for items spanning multiple rows)
				[caret + 1 thru doc/length]
				[0 thru (caret - 1)]
			caret'/offset: clip limits/1 limits/2 caret'/offset
		]
		caret'
	]
		
	;; automatically fills string with attributes and converts to supported clipboard format
	paint-string: function [doc [object!] string [string!]] [
		lines: split string #"^/"
		code:  rich/store-attrs doc/paint
		either single? lines [
			result: remake rich-text-span! [data: (zip explode lines/1 code)]
		][
			result: make rich-text-block! []
			result/data: map-each line lines [
				obj: remake-space 'rich-content [data: (zip explode line code)]
			]
		]
		result
	]
			
	pick-paint: function [doc [object!] /from offset: doc/caret/offset [integer!]] [	;-- use attrs near the caret by default
		doc/paint: any [
			;; question is, should it pick the attribute from before the caret or after?
			;; before probably makes more sense for appending, then if that fails it also tries after
			pick-attrs doc offset
			pick-attrs doc offset + 1
			clear doc/paint								;-- no attributes if can't pick up
		]
	]

	;; this should not replace the document, only content! e.g. if 'focus' comes before block in VID, it should stay focused
	lay-out-editor: function [spec [block!] /styles sheet [map! none!]] [	;-- only used to pass styles down to content/document
		content: lay-out-vids/styles spec sheet
		if empty? content [content: lay-out-vids [rich-content]]	;-- don't let document be empty
		compose/only [content/content: (content)]
	]
	extend VID/styles [
		editor [
			template: editor
			layout: lay-out-editor
			facets: [focus [VID/update-focus content]]
		]
	]

	draw: function [doc [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
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
			new-holder/caret/side:     doc/caret/side
			new-holder/caret/offset:   offset - pofs
			new-holder/caret/width:    doc/caret/width
			new-holder/caret/visible?: doc/caret/visible?
		]
		
		drawn: doc/list-draw/on canvas fill-x fill-y
	]
	
	on-content-change: function [doc [object!] word [word!] content [block!]] [
		if unset? :doc/modified? [exit]					;-- wait for init
		doc/length: get-length doc
		invalidate doc
	]
	
	on-caret-move: function [caret [object!] word [word!] offset [integer!]] [
		if caret/parent [pick-paint caret/parent]
		invalidate/info caret none 'look
	]
	
	;; document/caret cannot be assigned to it's paragraphs, because it holds absolute offset
	;; so paragraphs have their own (styled, rendered) caret space, moved from paragraph to paragraph
	;; while document has a fake caret (not rendered), that is only used for invalidation
	;; document invalidation -> document/draw -> updates paragraph/caret -> paragraph/draw
	caret-template: declare-class 'document-caret/caret [
		type:  'caret
		holder: none									;-- child that last owned the generated caret space
		offset: 0		#on-change :on-caret-move		;-- on top of invalidation, also updates the paint
	]
	
	;@@ should it support /items override? what will be the use case? spoilers? (for now length accounts for every paragraph)
	declare-template 'document/list [
		kit:       ~/kit
		content:   []		#type :on-content-change
		axis:      'y		#type (axis = 'y)			;-- protected
		spacing:   5		#type [integer!] :invalidates	;-- interval between paragraphs
		margin:    1x0									;-- don't let caret become fully invisible at the end of the longest line
		page-size: function [] [						;-- needs access to the parent viewport for paging
			vp: any [get-safe 'parent/viewport 0x0]
			max 0 (pick vp 'y) * 90%
		] #type [linear! function!] (page-size >= 0)
		
		length:   0					#type [integer!]	;-- read-only, auto-updated on edits
		caret:    make-space 'caret caret-template #type [object!] :invalidates-look
		selected: none				#type [pair! none!] :on-selected-change
		timeline: copy timeline!	#type [object!]
		paint:    []				#type [block!]		;-- current set of attributes (for newly inserted chars), updated on caret movement
		modified?: no									;-- set by edit as a flag to adjust origin on next render
		
		list-draw: :draw			#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
	
	editor-kit: make-kit 'editor [
		frame: object [
			adjust-origin: function ["Adjust document origin so that caret is visible"] [
				#assert [0x0 +< space/viewport]
				doc:  space/content
				cbox: batch doc [frame/caret-box here doc/caret/side]
				if cbox [
					height: cbox/2/y - cbox/1/y
					space/move-to/margin (cbox/1 + cbox/2 / 2) (0 . height) / 2 + 30	;@@ expose this hardcoded lookaround value?
				]
			]
		]
	]
	
	declare-template 'editor/scrollable [
		kit: ~/editor-kit
		content: make-space 'document [
			content: reduce [make-space 'rich-content []]		;-- ensure editor is not empty, or it can't be clicked on
		]
		content-flow: 'vertical
		
		scrollable-draw: :draw
		draw: function [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			if all [
				content/modified?
				0x0 +< canvas							;-- don't adjust until size is final
				fill-x									;@@ need a more reliable test than this!
			][
				scrollable-draw/on canvas fill-x fill-y
				batch self [frame/adjust-origin]
				content/modified?: no
			]
			scrollable-draw/on canvas fill-x fill-y
		]
	]
]


;; data format that holds whole paragraphs, together with their facets (alignment, indentation)
rich-text-block!: make rich-text-span! [
	name:   'rich-text-block
	data:   []
	length: does [max 0 (length? data) - 1 + sum map-each item data [batch item [length]]]
	format: function [] [to format: {} map-each/eval item data [[batch item [format] #"^/"]]]
	copy:   function [] [
		;; tricky! need to clone paragraphs but not their inner spaces! (see notes)
		data: system/words/copy self/data
		data: map-each para data [
			also para': batch para [clone]
			para'/data: system/words/copy para/data
		]
		remake rich-text-block! [data: (data)]
	]
	clone:  function [] [
		data: map-each item self/data [batch item [clone]]
		remake rich-text-block! [data: (data)]
	]
]


;; basic editing functions mandatory for every editor widget
define-handlers [
	editor: extends 'scrollable [
		document: [
			;@@ need dragging when click is on selected area
			;@@ need selection to work on any document, not just in the editor (or pan it instead?)
			;@@ maybe some modularity is required to select what feature does what, e.g. /config or /options facet
			on-down [doc path event] [
				batch doc [
					select-range none
					caret: frame/point->caret path/2
					if caret [move-caret/side caret/offset caret/side]
				]
				start-drag/with path copy caret
			]
			on-up [doc path event] [stop-drag]
			;@@ need double-click selection mode (whole words)
			on-over [doc path event] [
				if dragging?/from doc [
					start: drag-parameter
					batch doc [
						caret: frame/point->caret path/2
						if caret [
							select-range start/offset thru caret/offset
							move-caret/side caret/offset caret/side
						]
					]
				]
			]
			on-key [doc path event] [
				case [
					is-key-printable? event [
						batch doc key->plan event doc/selected
					]
					event/key = #"^-" [					;-- on tab - don't lose focus, insert tab char or reindent
						batch doc [
							either selected [
								indent-range selected 20 * pick [-1 1] event/shift?
							][
								;@@ tabs support is "accidental" for now - only correct within a single text span
								;@@ if something splits the text, it's incorrect
								;@@ need special case for it in paragraph layout, for which section size=0 is reserved
								insert-items here "^-"
							]
						]
					]
					event/key = #"^M" [					;-- enter is not handled by key->plan
						unless event/ctrl? [			;-- ctrl+enter is probably some special key
							batch doc [select-range none  insert-items here "^/"]
						]
					]
				]
			]
			on-key-down [doc path event] [
				if is-key-printable? event [exit]
				batch doc key->plan event doc/selected
			]
			;; these show/hide the caret - /draw will check if document is focused or not
			on-focus   [doc path event] [doc/caret/visible?: yes]
			on-unfocus [doc path event] [doc/caret/visible?: no]
		]; document: [
	]; editor: extends 'scrollable [
]; doc-ctx: context [
]; do/expand with spaces/ctx [
