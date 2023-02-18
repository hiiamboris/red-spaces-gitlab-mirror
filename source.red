Red [
	title:   "Rich-content editor basis and source format codec"
	author:  @hiiamboris
	license: BSD-3
	description: {
		This provides an internal format for holding rich-content /data:
		- [items block] which contains char! values and space! objects
		- #(attrs map) which contains string! masks that map attributes (bold, italic, etc) to each item
		All rich-content edits work with this /data.
		
		For convenience there's also a high-level 'source' format, which is used by VID/S to populate /data.
		Export from /data into source format is also available (as rich/source/serialize).
		
		Source format design principles:
		- Markdown & co are very complex formats for humans, that a machine can understand but with a lot of work.
		- GML and it's successors (HTML, XML) are source formats for machines that 
		  neither a human cannot read anymore, nor machine parse efficiently.
		- Source format used here is a Red block-level data representation for machines,
		  that should be simple enough for a human to read.
		  
		Source syntax summary:
		- `name` word opens an attribute with a `true` value
		- `name: value` opens an attribute with a given value (sameness is not guaranteed to persist!)
		  if it's already open, just attribute value is replaced
		  value cannot be false or none
		- `/name` closes a previously opened attribute
		- `"string"` represents text fragment to be assigned a currently opened attribute set
		- `object!` represents a space! object, but attributes for it have no effect for now (could be extended later)
		
		Supported attributes are:
		- [bold italic underline strike] as flag attributes
		- [color backdrop size font] as value-bearing attributes:
		  color & backdrop accept tuples
		  size (font size) accepts integer
		  font (font face) accepts string
	}
	notes: {
		Not sure whether to use /same or /case comparison for attributes.
		- /same good for blocks like code
		- /case good for strings
		Since I'm using copy/deep sometimes, and decided against /command attribute, /case makes most sense.
	}
]

;@@ should there be a single items/attributes array for the whole document composed from many paragraphs sources?

;; this context proceeds from lowest level (ranges) to highest level (source) below
rich: context [											;@@ what would be a better name?
	
	ranges: context [
		to-rtd-pair: function [
			"Convert source range into RTD range"
			range [pair!]
		][
			range/1 + 1 by (range/2 - range/1)
		]
	
		from-rtd-pair: function [
			"Convert RTD range into source range"
			range [pair!]
		][
			range/1 - 1 by (range/2 + range/1 - 1)
		]
		
		#assert [2x5 = to-rtd-pair   1x6]
		#assert [1x6 = from-rtd-pair 2x5]
	]
		
	zero!:    charset "^@"								;-- charset is about 10x faster than using a char
	nonzero!: complement zero!
	
	mask-to-ranges: function [values [block!] mask [string!] /local c] [
		ranges: clear []
		parse mask [
			any [
				any zero! s: set c nonzero! any c e: (
					value: pick values to integer! c
					append append ranges :value as-pair skip? s skip? e
				)
			]
		]
		copy ranges
	]
	
	{
		MEMO: mask length should always equal items length! otherwise would need to pass length separately anyway
		attrs format: #(
			name [										;-- attribute name
				values: [value1 value2 ...]				;-- block of allowed values
				mask:   "mask"							;-- string mapping items to values (zero char = no value)
			]
			...
		)

		I do not add #length into attrs as that would complicate foreach [attr data] loop
		unfortunate result is that length has to be passed as argument together with attributes
		;@@ for-each loop could help this by filtering #length out
	}
	
	;; external context allows me to use /copy word without shadowing the global one
	attributes: context [
		to-rtd-flag: make-rtd-flags: mark!: pick: copy: remove!: insert!: none
	]
	
	attributes/to-rtd-flag: function [attr [word!] value [tuple! logic! string! integer!]] [
		switch attr [
			bold italic underline strike [attr]
			color size font [value]
			backdrop [compose [backdrop (value)]]
		]
	]
	#assert [[backdrop 10.20.30] = attributes/to-rtd-flag 'backdrop 10.20.30]
		
	rtd-attrs: make hash! [bold italic underline strike color backdrop size font]
	attributes/make-rtd-flags: function [
		"Make an RTD flags block out of given attributes"
		attrs [map!] limits [pair!] "segment to extract"
	][
		flags:  clear []
		length: span? limits
		foreach [attr data] attrs [
			unless find rtd-attrs attr [continue]		;-- attribute not supported by RTD
			set [_: values: _: mask:] data
			foreach [value range] mask-to-ranges values mask [	;@@ use map-each
				range: clip 0 length range - limits/1
				if zero? span? range [continue]
				pair: ranges/to-rtd-pair range
				flag: attributes/to-rtd-flag to word! attr value
				append append flags pair flag
			]
		]
		copy flags
	]
	#assert [
		[1x8  bold] = attributes/make-rtd-flags #(bold [values: [#[true]] mask: "^@^@^@^@^A^A^A^A^A^A^A^A^A^A^A^A^A^A^A^A^@^@^@^@"]) 4x12
		[5x8  bold] = attributes/make-rtd-flags #(bold [values: [#[true]] mask: "^@^@^@^@^A^A^A^A^A^A^A^A^A^A^A^A^A^A^A^A^@^@^@^@"]) 0x12
		[5x16 bold] = attributes/make-rtd-flags #(bold [values: [#[true]] mask: "^@^@^@^@^A^A^A^A^A^A^A^A^A^A^A^A^A^A^A^A^@^@^@^@"]) 0x20
	]
	
	attributes/mark!: function [						;@@ maybe rename to set! ?
		attrs  [map!]
		length [integer!] (length >= 0) "target items size"		;-- required to insert missing attributes
		range  [pair!]
		attr   [word!]
		value
	][
		if zero? span: span? range [return attrs]
		either not empty? data: attrs/:attr [			;-- existing attr
			#assert [parse data [any-word! block! any-word! string!]]
			set [_: values: _: mask:] data
			#assert [length = length? mask]
			char: #"^@"
			if :value [
				unless pos: find/only/case values :value [
					append/only pos: tail values :value
				]
				char: to char! index? pos
			]
			change/dup (skip mask range/1) char span
		][												;-- new attr
			if :value [									;-- not added if value is falsey
				values: reduce [:value]
				enlarge (mask: make {} length) length #"^@"
				change/dup (skip mask range/1) #"^A" span
				attrs/:attr: compose/only [values: (values) mask: (mask)]
			]
		]
		attrs
	]
	#assert [
		#(x [values: [1] mask: "^@^@^@^@^A^A^A^A^A^A^A^A"  ]) = attributes/mark! #() 12 4x12 'x 1
		#(x [values: [1] mask: "^@^@^@^@^A^A^A^A^A^A^A^A^@"]) = attributes/mark! #() 13 4x12 'x 1
		#(x [values: [1] mask: "^@^@^A^A^A^A^@^@"          ]) = attributes/mark! #(x [values: [1] mask: "^@^@^@^@^@^@^@^@"]) 8 2x6 'x 1
		#(x [values: [1] mask: "^A^A^@^@^@^@^A^A"          ]) = attributes/mark! #(x [values: [1] mask: "^A^A^A^A^A^A^A^A"]) 8 2x6 'x none
	]
	
	; ;; unlike /mark, clears all attributes in the range
	; attributes/clear!: function ["modifies" attrs [map!] range [pair!]] [
		; foreach [name data] attrs [
			; masks/mark! data/mask range #"^@"
		; ]
		; attrs
	; ]
	
	attributes/pick: function [attrs [map!] attr [word!] index [integer!]] [
		all [
			set [_: values: _: mask:] attrs/:attr
			i: mask/:index
			pick values to integer! i
		]
	]
	#assert [
		on =  attributes/pick #(bold [values: [#[true]] mask: {^A^A^@^@^A}]) 'bold 1
		on =  attributes/pick #(bold [values: [#[true]] mask: {^A^A^@^@^A}]) 'bold 2
		on =  attributes/pick #(bold [values: [#[true]] mask: {^A^A^@^@^A}]) 'bold 5
		none? attributes/pick #(bold [values: [#[true]] mask: {^A^A^@^@^A}]) 'bold 0
		none? attributes/pick #(bold [values: [#[true]] mask: {^A^A^@^@^A}]) 'bold 3
	]
	
	attributes/copy: function [attrs [map!] range [pair!] (range/2 >= range/1)] [
		slice: copy/deep attrs							;-- this doesn't copy the strings but they will be replaced anyway
		foreach [attr data] slice [
			data/mask: copy/part data/mask range + 1
		]
		;@@ should this clean up unused attribute values? probably not worth it
		slice
	]
	
	attributes/remove!: function [attrs [map!] range [pair!] (range/2 >= range/1)] [
		if 0 <> span: span? range [
			foreach [attr data] attrs [
				remove/part skip data/mask range/1 span
			]
		]
		;@@ should this clean up unused attribute values? probably not worth it
		attrs
	]
	
	attributes/insert!: function [
		attrs   [map!]
		length  [integer!] (length >= 0) "target items size"	;-- required to insert missing attributes
		offset  [integer!]
		other   [map!]
		length2 [integer!] (length2 >= 0) "inserted items size"	;-- required in case `other` is empty :/
	][
		offset: clip offset 0 length
		;; insert empty regions into `attrs` - needed for attributes that aren't in `other`
		foreach [attr data1] attrs [
			insert/dup skip data1/mask offset #"^@" length2
		]
		;; merge `other` into `attrs`
		foreach [attr data2] other [
			;; if attr is absent from the target, may just copy it over
			unless data1: attrs/:attr [
				attrs/:attr: data1: copy/deep data2
				insert/dup data1/mask #"^@" offset
				enlarge data1/mask (length + length2) #"^@"
				continue
			]
			;; otherwise, have to join values and remap the old mask
			values1: make hash! data1/values
			values2: append clear [] data2/values
			forall values2 [							;@@ use map-each
				values2/1: to char! index? any [
					find/only/case        values1 :values2/1
					back insert/only tail values1 :values2/1
				]
			]
			insert values2 #"^@"						;-- null always maps to itself
			mask2: data2/mask
			forall mask2 [								;@@ use map-each
				mask2/1: pick values2 1 + to integer! mask2/1
			]
			data1/values: to [] values1
			change (skip data1/mask offset) mask2		;-- mask2 now has values1-compatible indices
		]
		attrs
	]
	#assert [
		#(x [values: [1]   mask: {^@^A^@^@^A^@}]) =       attributes/insert! #(x [values: [1] mask: {^@^A^A^@}]) 4 2 #() 2
		#(x [values: [1 2] mask: {^@^A^@^A^B^A^@^A^@}]) = attributes/insert! #(x [values: [1] mask: {^@^A^A^@}]) 4 2 #(x [values: [2 1] mask: {^@^B^A^B^@}]) 5
	]
	
	;@@ need to make modularity somehow, later
	; datatypes: make map! reduce [
		; string! object [
		; ]
	; ]
	
	decoded: context [copy: remove!: insert!: normalize!: format: to-spaces: none]
	
	decoded/copy: function [
		"Copy a slice of decoded source"
		source [block!] "[items attrs] block to copy from" (parse source [block! map!])
		range  [pair!]  "head x tail"
	][
		range: clip range 0 length? source/1			;@@ workaround for #5263 here as well
		if range/1 > range/2 [range: reverse range]
		reduce [
			copy/part source/1 range + 1
			attributes/copy source/2 range
		]
	]
	
	decoded/remove!: function [
		"Remove a range from the decoded source"
		source [block!] "[items attrs] block" (parse source [block! map!])
		range  [pair!]  "head x tail"
	][
		range: clip range 0 length? source/1
		if range/1 > range/2 [range: reverse range]
		remove/part skip source/1 range/1 span? range
		attributes/remove! source/2 range
		source
	]
	
	decoded/insert!: function [
		"Insert a slice into the decoded source"
		source [block!] "[items attrs] block" (parse source [block! map!])
		offset [integer!]
		slice  [block!] "[items attrs] block" (parse slice [block! map!])
	][
		insert skip source/1 offset slice/1
		attributes/insert! source/2 (length? source/1) offset slice/2 (length? slice/1)
		source
	]
	
	decoded/normalize!: function [
		"Clean up empty attributes from decoded data"
		source [block!] "[items attrs] block" (parse source [block! map!])
	][
		len: length? source/1
		foreach [attr data] source/2 [
			#assert [len = length? data/mask]
			unless find/case data/mask nonzero! [
				remove/key source/2 attr
			]
		]
		source
	]

	decoded/format: function [
		"Convert decoded source into plain text"
		source [block!] "[items attrs] block" (parse source [block! map!])
	][
		result: make {} length? items: source/1
		foreach item items [							;@@ use map-each
			case [
				char?  :item [append result item]
				space? :item [if in item 'format [append result item/format]]
			]
		]
		result
	]
	
	;@@ leverage prototypes for this
	decoded/to-spaces: function [
		"Transform decoded source into a list of spaces (for use in rich-content), return [content ranges]"
		source [block!] "[items attrs] block" (parse source [block! map!])
	][
		;@@ should I clip attrs to items/length?
		content: clear []
		ranges:  clear []								;-- range spans of items that caret can dive into
		set [items: attrs:] source
		;@@ or trim linefeed? or silently split into multiple paragraphs (hard)?
		#assert [not find items #"^/"  "line breaks are not allowed inside paragraph text"]
		parse items [any [
			[	s: some char! e: (
					append content obj: make-space 'text []
					append/part obj/text s e
					range: as-pair skip? s skip? e
					obj/flags: attributes/make-rtd-flags attrs range
				)
			|	set obj object! (
					append content obj
					range: 0x1 + skip? s
				)
			] (repend ranges [obj range])
		|	end
		|	(ERROR "Unsupported data in the source: (mold/part s 40)")
		]]
		reduce [copy content  make hash! ranges]
	]
		
	source: context [deserialize: serialize: none]
	
	source/deserialize: function [
		"Split source into [items attributes]"
		source [block!]
		/local attr value item
	][
		items:   clear []							;@@ should items be just chars and objects? other types support, e.g. image?
		attrs:   clear #()
		queue:   clear []
		pending: clear #()
		;; first need to build items list: each attr mask will have to have the same length
		parse source [any [
			set attr [
				word! (value: on)
			|	set-word! p: (value: do/next p 'p) :p	;-- reduce words (color names) to their values
			] (
				attr:  to word! attr
				stack: any [pending/:attr  pending/:attr: make [] 4]
				repend stack [length? items :value]
			)
		|	set attr refinement! (						;-- attributes work stack-like and do not close automatically
				attr:  to word! attr
				unless empty? stack: pending/:attr [	;-- extra closings are silently ignored
					value: take/last stack
					start: take/last stack
					repend queue [attr (start by length? items) :value]
				]
			)
		|	set item string! (explode/into item items)	;@@ make it a module
		|	set item skip    (append/only items item)
		]]
		length: length? items							;-- length is fixed now
		;; auto-close unclosed ranges
		foreach [attr stack] pending [
			foreach [start value] stack [
				repend queue [to word! attr (start by length? items) :value]
			]
		]
		;; mark attribute ranges
		foreach [attr range value] queue [
			attributes/mark! attrs length range attr :value
		]
		reduce [copy items copy attrs]
	]
	
	source/serialize: function [
		"Create a source block out of items and attributes"
		items [block!] attrs [map!]
		/local part
	][
		queue: clear []
		foreach [attr data] attrs [
			set [_: values: _: mask:] data
			closing: to refinement! attr
			foreach [value range] mask-to-ranges values mask [
				opening: either true = :value [to word! attr][reduce [to set-word! attr :value]]
				;; order is important: close then open, that's why I add 0.1
				;; e.g. to avoid output like `color: 1 "x" color: 2 /color "x" /color`
				;; when it should have been  `color: 1 "x" /color color: 2 "x" /color`
				repend queue [range/1 + 0.1 opening range/2 closing]
			]
		]
		sort/stable/skip queue 2
		
		result: clear []								;-- flush the queue
		foreach [offset marker] queue [
			append/part result items items: skip head items to integer! offset
			append result marker
		]
		append result items
		
		parse result [any [								;-- unify chars into strings
			change copy part some char! (to string! part)
		|	skip
		]]
		copy result
	]
	
	#assert [
		["x"] = source/serialize [#"x"] #()
		["12" bold "3456" /bold "7"] = source/serialize [#"1" #"2" #"3" #"4" #"5" #"6" #"7"] #(bold [values: [#[true]] mask: "^@^@^A^A^A^A"])
		["12" bold underline "3" /bold /underline] = source/serialize [#"1" #"2" #"3"] #(bold [values: [#[true]] mask: "^@^@^A^@"] underline [values: [#[true]] mask: "^@^@^A^A"])
		["1" x: 1 "2" /x x: 2 "3" /x "4"] = source/serialize [#"1" #"2" #"3" #"4"] #(x [values: [1 2] mask: "^@^A^B"])
	]
]
