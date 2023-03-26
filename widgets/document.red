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

	;; extraction has to copy paragraphs to carry alignment and indentation attributes
	extract: function [doc [object!] range [pair!] /block "Always extract as paragraph list"] [
		mapped: doc/map-range/relative range
		either any [block  2 < length? mapped] [		;-- extract paragraphs
			block: map-each [para prange] mapped [
				also para: para/clone
				para/edit [clip-range prange]
			]
			make rich-text-block! [data: block]
		][												;-- extract text span
			set [para: prange:] mapped
			span: para/edit [copy-range prange]
			make rich-text-span! [data: span]
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
		
		point->caret: function ["Get info for caret location closest to given point" point [pair!]] with :measure [
			~/point->caret doc point
		]
		
		caret->paragraph: function ["Get paragraph and it's range at given offset" offset [integer!]] with :measure [
			if set [para: pofs: plen:] ~/caret->paragraph doc offset [
				reduce [para 0 by plen + pofs]			;@@ use range for the other func too?
			]
		]
		
		caret->box: function ["Get box [xy1 xy2] of the caret at given offset" offset [integer!] side [word!]] with :measure [
			all [
				set [para: prange:] caret->paragraph offset
				geom: select/same doc/map para
				box: para/measure [caret->box offset - prange/1 side]
				map-each xy box [geom/offset + xy]
			]
		]
		
		find-prev-word: function ["Get offset of the previous word's start"] with :measure [
			set [para: pofs: plen:] ~/caret->paragraph doc offset: doc/caret/offset
			while [offset <= pofs] [					;-- switch to previous paragraph (maybe multiple times)
				if offset <= 0 [return 0]				;-- no more going left
				set [para: pofs: plen:] ~/caret->paragraph doc offset: offset - 1
			]
			#assert [pofs < offset]						;-- limited by paragraph's head
			e: skip s: para/data offset - pofs * 2
			before: reverse system/words/extract (copy/part s e) 2
			parse before [any word-sep any non-word-sep before:]
			offset - skip? before
		]
		find-next-word: function ["Get offset of the next word's end"] with :measure [
			set [para: pofs: plen:] ~/caret->paragraph doc offset: doc/caret/offset
			while [offset >= (pofs + plen)] [			;-- switch to next paragraph (maybe multiple times)
				if offset >= doc/length [return doc/length]		;-- no more going right
				set [para: pofs: plen:] ~/caret->paragraph doc offset: offset + 1
			]
			#assert [pofs + plen > offset]				;-- limited by paragraph's tail
			after: skip para/data offset - pofs * 2
			parse pos: after [any [word-sep skip] any [non-word-sep skip] pos:]
			offset + half offset? after pos
		]
		
		find-line-above: function ["Get caret (offset, side) one line above"] with :measure [
			caret-row-shift doc doc/caret/offset doc/caret/side 'up 0
		]
		find-line-below: function ["Get caret (offset, side) one line below"] with :measure [
			caret-row-shift doc doc/caret/offset doc/caret/side 'down 0
		]
		
		find-page-above: function ["Get caret (offset, side) one page above"] with :measure [
			caret-row-shift doc doc/caret/offset doc/caret/side 'up doc/page-size
		]
		find-page-below: function ["Get caret (offset, side) one page below"] with :measure [
			caret-row-shift doc doc/caret/offset doc/caret/side 'down doc/page-size
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
		|	'insert set rng pair! set val object! (insert-data doc rng/1 val)
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
			(return action)
		]
		none
	]
		
	;; used to check grouping possibility before doing any destructive changes
	groupable?: function [edit1 [block!] edit2 [block!] elapsed [time!]] [
		groupable?: case [
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
					p/2: rng1/1 by rng2/2
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
					p/2: (min rng1/1 rng2/1) + (0 by add span? rng1 span? rng2)
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
	
	;@@ add ! to destructive actions for consistency with rich-content? or remove it instead?
	actions: context [
		edit: function [doc [object!] plan [block!] /local result] [
			init:  reduce [doc/selected doc/caret/offset]	;-- remember them before the edit
			left:  make [] 10							;-- history for undo/redo
			right: make [] 10
			;@@ unfortunately I have to manually call this 'update' in every action - how to automate?
			;@@ or maybe get rid of it? paragraph is rarely used anyway
			update: [
				offset: doc/caret/offset
				set [para: pofs: plen:] caret->paragraph doc offset
			]
			set/any 'result do with self plan
			; ?? left ?? right
			push-to-timeline doc left right init
			; probe head doc/timeline/events
			doc/modified?: yes							;-- will adjust origin on next render!
			:result
		]
		record: undo: redo: at: select: move: remove: slice: copy: paste: insert: mark: align: indent: none
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
			page-up   [doc/measure [find-page-above]]			;@@ these need to know page size
			page-down [doc/measure [find-page-below]]
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
		/side cside [word!] "Specify caret side" (find [left right] cside)
	] with :actions/edit [
		do update
		case/all [
			by [pos: pos + offset]
			word? pos [
				pos: actions/at pos
				if block? pos [							;-- block may be returned by find-line-below/above
					default cside: pos/side
					pos:  clip 0 doc/length pos/offset
				]
			]
			integer? pos [								;-- unknown words are silently ignored
				default cside: case [pos > offset ['left] pos < offset ['right]]	;-- only change side if moved
				pos: clip 0 doc/length pos
				actions/record [move (offset)] [move (pos)]
				if cside [actions/record [side (doc/caret/side)] [side (cside)]]
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
				slice: extract doc limit
				actions/record [insert (limit) (slice)] [remove (limit)]
			]
		]
	]
	
	actions/slice: function [
		"Extract specified range"
		range [word! (find [all selected] range) pair!] "Offset range or any of: [selected all]"
		/text  "Return it as plain text"
		/block "Always return paragraph list"
	] with :actions/edit [
		do update
		switch range [
			selected [range: doc/selected]
			all      [range: 0 by doc/length]
		]
		unless pair? range [range: offset * 1x1]		;-- silently ignores unsupported range words
		either block [extract/block doc range][extract doc range]	;@@ use apply
	]
	
	actions/copy: function [
		"Copy specified range into clipboard"
		range [word! (find [all selected] range) pair!] "Offset range or any of: [selected all]"
	] with :actions/edit [
		slice: actions/slice range
		unless empty? slice/data [clipboard/write slice]
		slice
	]
	
	actions/paste: function [
		"Paste text from clipboard into current caret offset"
	] with :actions/edit [
		if data: clipboard/read [actions/insert data]
	]
	
	actions/insert: function [
		"Insert given data into current caret offset"
		data [object! (any [space? data  'clipboard-format = class? data]) string!]
		/at pos [integer!] 
	] with :actions/edit [
		do update
		case [
			string? data [data: paint-string doc data]
			space?  data [data: make rich-text-span! compose/deep [data: [(data) 0]]]
			not find [rich-text-span rich-text-block] data/name [	;-- unsupported clipboard format (incl. text) inserted as text
				data: paint-string doc data/format
			]
		]
		if 0 = data/length [exit]
		range: 0 by data/length + any [pos offset]
		actions/record [remove (range)] [insert (range) (data)]
	]
	
	actions/mark: function [
		"Mark given range with an attribute and value"
		range [pair!]
		attr  [word!]
		value [none! logic! scalar! any-string!]		;@@ what other types to allow? words?
			"When false or none, attribute is cleared"
	] with :actions/edit [
		do update
		unless zero? span: span? range: clip order-pair range 0 doc/length [
			;; for undoability this has to remove then insert whole paragraphs
			slice:  extract doc range
			marked: extract doc range
			either marked/name = 'rich-text-block [
				foreach para marked/data [para/edit [mark-range everything attr :value]]
			][
				rich/attributes/mark marked/data 'all attr :value
			]
			; ?? slice ?? marked
			sel: doc/selected							;-- remember selection to restore it afterwards
			; ?? slice ?? marked
			actions/record
				[remove (range) insert (range) (slice)  select (sel)]
				[remove (range) insert (range) (marked) select (sel)]
		]
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
	
	;; these are low level functions bypassing undo mechanism
	remove-range: function [doc [object!] range [pair!]] [
		range: order-pair clip range 0 doc/length
		n: half length? mapped: doc/map-range/relative range
		set [para1: range1:] mapped
		set [paraN: rangeN:] skip tail mapped -2 
		if n >= 1 [para1/edit [remove-range range1]]
		if n >= 2 [										;-- requires removal of whole paragraphs
			paraN/edit [remove-range rangeN]
			para1/edit [insert-items range1/1 paraN/data]
			s: find/same/tail doc/content para1
			e: find/same/tail s paraN
			remove/part s e
		]
		adjust-offsets doc range/1 negate span? range
		if all [doc/selected  0 = span? doc/selected] [doc/selected: none]	;-- normalize emptied selection
	]
	
	insert-data: function [
		doc    [object!]
		offset [integer!]
		data   [object!] (find [rich-text-span rich-text-block] select data 'name)
		/local _
	][
		if empty? data/data [exit]
		list: select (data: data/copy) 'data			;-- will modify paragraphs data in place!
		set [dst-para: dst-ofs:] caret->paragraph doc offset
		dst-loc: offset - dst-ofs
		len: data/length
		case [
			data/name = 'rich-text-span [
				#assert [not find list #"^/"]
				dst-para/edit [insert-items dst-loc list]
			]
			single? data/data [
				dst-para/edit [insert-items dst-loc list/1/data]
			]
			'multiline [
				;; edit first paragraph, but remember the after-insertion part
				dst-para/edit [							;@@ make another action in edit for this?
					stashed: copy-range range: dst-loc by infxinf/x
					remove-range range
					insert-items dst-loc list/1/data 
				]
				;; insert other paragraphs into doc/content
				insert (find/same/tail doc/content dst-para) next list
				;; append stashed part to the last inserted paragraph
				paraN: last list
				paraN/edit [insert-items infxinf/x stashed]
			]
		]
		adjust-offsets doc offset len
	]
		
	pick-attr: function [doc [object!] index [integer!] attr [word!]] [
		if set [para: pofs:] caret->paragraph doc offset: index - 1 [
			para/measure [pick-attr offset - pofs + 1 attr]
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
			para/measure [pick-attrs offset - pofs + 1]
		]												;-- may return none if can't find any attrs
	]
	
	;; used to correct caret and selection offsets after an edit
	adjust-offsets: function [doc [object!] offset [integer!] shift [integer!]] [
		sel: doc/selected								;-- can't set components of doc/selected (due to reordering)
		foreach path [sel/1 sel/2 doc/length doc/caret/offset] [
			if attempt [offset <= value: get path] [
				set path max offset value + shift
			]
		]
		doc/selected: sel								;-- trigger update of /selected
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
		if all [not para  not empty? doc/map] [					;-- doesn't land on a paragraph - need to find nearest
			points: map-each/eval [para geom] doc/map [
				closest: closest-box-point?/to 0x0 geom/size ppoint: point - geom/offset
				dist: distance? closest ppoint 
				[dist closest para]
			]
			set [_: xy: para:] sort/skip points 3
		]
		if para [
			#assert [in para 'measure]
			caret: para/measure [point->caret xy]
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
		xy: clip xy 0x0 doc/size - 0x1
		caret': point->caret doc xy
		if caret' [										;-- may be none if outside the document
			limits: either dir = 'down					;-- ensure a minimum shift of 1 caret slot (for items spanning multiple rows)
				[caret + 1 by doc/length]
				[0 by (caret - 1)]
			caret'/offset: clip limits/1 limits/2 caret'/offset
		]
		caret'
	]
		
	;; automatically fills string with attributes and converts to supported clipboard format
	paint-string: function [doc [object!] string [string!]] [
		lines: split string #"^/"
		code:  rich/store-attrs doc/paint
		either single? lines [
			result: make rich-text-span! []
			result/data: zip explode lines/1 code
		][
			result: make rich-text-block! []
			result/data: map-each line lines [
				also obj: make-space 'rich-content []
				obj/data: zip explode line code
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
			facets: [focus [focus-space content]]
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
			new-holder/caret/width:  doc/caret/width
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
		content:   []		#type :on-content-change
		axis:     'y		#type (axis = 'y)			;-- protected
		spacing:   5		#type [integer!]			;-- interval between paragraphs
		margin:    1x0									;-- don't let caret become fully invisible at the end of the longest line
		page-size: function [] [						;-- needs access to the parent viewport for paging
			vp: any [all [parent parent/viewport] 0x0]	;@@ REP 113
			max 0 to integer! vp/y * 90%
		] #type [integer! function!] (page-size >= 0)
		
		length:   0			#type [integer!]			;-- read-only, auto-updated on edits
		caret:    make-space 'caret caret-template #type [object!] :invalidates
		selected: none				#type [pair! none!] :on-selected-change
		timeline: copy timeline!	#type [object!]
		paint:    []				#type [block!]		;-- current set of attributes (for newly inserted chars), updated on caret movement
		modified?: no									;-- set by edit as a flag to adjust origin on next render
		
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
			/no-empty "Exclude empty intersections (may return empty list)"
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
	
	declare-template 'editor/scrollable [
		content: make-space 'document [
			content: reduce [make-space 'rich-content []]		;-- ensure editor is not empty, or it can't be clicked on
		]
		content-flow: 'vertical
		
		adjust-origin: function [] [
			doc:  content
			cbox: doc/measure [caret->box doc/caret/offset doc/caret/side]
			if cbox [
				height: cbox/2/y - cbox/1/y
				move-to/margin (cbox/1 + cbox/2 / 2) 0 by height / 2 + 30	;@@ expose this hardcoded lookaround value?
			]
		]
		
		scrollable-draw: :draw
		draw: function [/on canvas [pair!]] [
			if content/modified? [
				scrollable-draw/on canvas
				adjust-origin
				content/modified?: no
			]
			scrollable-draw/on canvas
		]
	]
]


;; data format that holds whole paragraphs, together with their facets (alignment, indentation)
rich-text-block!: make rich-text-span! [
	name:   'rich-text-block
	data:   []
	length: does [max 0 (length? data) - 1 + sum map-each item data [item/measure [length]]]
	format: does [to {} map-each/eval item data [[when in item 'format (item/format) #"^/"]]]
	copy:   function [] [
		;; tricky! need to clone paragraphs but not their inner spaces! (see notes)
		data: system/words/copy self/data
		data: map-each para data [
			also para': para/clone
			para'/data: system/words/copy para/data
		]
		remake rich-text-block! [data: (data)]
	]
	clone:  function [] [
		data: map-each item self/data [when select item 'clone (item/clone)]
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
				doc/selected: none
				caret: doc/measure [point->caret path/2]
				if caret [
					doc/edit [move-caret/side caret/offset caret/side]
					start-drag/with path copy caret
				]
			]
			on-up [doc path event] [
				stop-drag
			]
			;@@ need double-click selection mode (whole words)
			on-over [doc path event] [
				if dragging?/from doc [
					caret: doc/measure [point->caret path/2]
					if caret [
						start: drag-parameter
						doc/edit [
							select-range start/offset by caret/offset
							move-caret/side caret/offset caret/side
						]
					]
				]
			]
			on-key [doc path event] [
				case [
					is-key-printable? event [
						doc/edit key->plan event doc/selected
					]
					event/key = #"^-" [					;-- on tab - don't lose focus, insert tab char or reindent
						either all [doc/selected 0 < span? doc/selected] [
							indent 20 * pick [-1 1] event/shift?
						][
							;@@ tabs support is "accidental" for now - only correct within a single text span
							;@@ if something splits the text, it's incorrect
							;@@ need special case for it in paragraph layout, for which section size=0 is reserved
							doc/edit [insert-items "^-"]
						]
					]
					find [#"^M" #"^/"] event/key [		;-- enter is not handled by key->plan
						unless event/ctrl? [			;-- ctrl+enter is probably some special key
							doc/edit [select-range none  insert-items "^/"]
						]
					]
				]
			]
			on-key-down [doc path event] [
				if is-key-printable? event [exit]
				doc/edit key->plan event doc/selected
			]
			;; these show/hide the caret - /draw will check if document is focused or not
			on-focus   [doc path event] [invalidate doc]
			on-unfocus [doc path event] [invalidate doc]
		]; document: [
	]; editor: extends 'scrollable [
]; doc-ctx: context [
]; do/expand with spaces/ctx [
