Red [
	title:   "Rich-content editor basis and source format codec"
	author:  @hiiamboris
	license: BSD-3
	description: {
		This provides an internal efficient format for holding rich-content /data:
			[item1 attr1 item2 attr2 ...]
			itemN can be a char! value or space! object
			attrN is an integer index in global attribute catalog
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
	~: self

	;; catalog holds every attribute combo ever encountered
	;; format: [hash [attr value ...] ...] - hash is used to look up by attribute combo (binary is hashed by hash! type)
	;; but normally attributes are indexed by integer (half offset, zero-based), since it's more readable on mold
	;; attrs are in a block because there usually aren't many anyway, no reason to use a map
	;; attr names must always all be lowercase or hashing would have to be slowed down with auto-lowecasing
	;@@ test lowercase in high-level funcs
	catalog: make hash! 1024
	
	hash-attrs: function [attrs [block!]] [
		attrs: sort/skip append clear [] attrs 2				;-- sort to guarantee uniqueness of the combo
		checksum (native-mold/all/flat/only attrs) 'sha1		;-- native mold is much faster than save into redbin
	]
	
	store-attrs: function [attrs [block!]] [
		#assert [any [empty? attrs  all extract next attrs 2]]		;-- only truthy values are allowed for attrs
		hash: hash-attrs attrs
		unless pos: find catalog hash [
			pos: tail catalog 
			repend catalog [hash copy/deep attrs]
		]
		half skip? pos
	]
	
	index->attrs: function [index [integer!]] [
		copy/deep pick catalog index + 1 * 2			;-- copy ensures attrs are never modified in place
	]
	
	attrs->index: function [attrs [block!]] [
		hash: hash-attrs attrs
		if pos: find catalog hash [half skip? pos]
	]
	
	store-attrs []										;-- empty attribute set is always present and has zero index
	#assert [											;-- other attributes are added for testing purposes
		1 = store-attrs [bold #(true)]
		2 = store-attrs [bold #(true) underline #(true)]
		3 = store-attrs [size 8]
		4 = store-attrs [size 12]
		4 = store-attrs [size 12]
		3 = attrs->index [size 8]
		[bold #(true)] = index->attrs 1
	]
	
	
	ranges: context [
		to-rtd-pair: function [
			"Convert source range into RTD range"
			range [pair!]
		][
			range/1 + 1 thru span? range
		]
	
		from-rtd-pair: function [
			"Convert RTD range into source range"
			range [pair!]
		][
			0 thru range/2 + range/1 - 1
		]
		
		#assert [2x5 = to-rtd-pair   1x6]
		#assert [1x6 = from-rtd-pair 2x5]
	]
		
	extract-ranges: function [data [block!] (even? length? data)] [
		ranges: clear []
		range-code: 0
		offset:     0
		flush: [
			if range-code > 0 [
				range: range-start thru offset
				attrs: index->attrs range-code
				repend ranges [range attrs]
			]
		]
		foreach [item code] data [						;@@ use for-each
			if code <> range-code [
				do flush
				range-start: offset
				range-code:  code
			]
			offset: offset + 1
		]
		do flush
		copy ranges
	]
	
	#assert [ [0x3 [bold #(true)]] = extract-ranges [_ 1 _ 1 _ 1] ]

	;; external context allows me to use /copy word without shadowing the global one
	attributes: context [
		to-rtd-flag: make-rtd-flags: change: mark: clear: pick: exclude: compatible?: none
	]
	
	attributes/to-rtd-flag: function [attr [word!] value [tuple! logic! string! integer!]] [
		switch attr [
			bold italic underline strike [attr]
			color size font [value]
			backdrop [compose [backdrop (value)]]
		]
	]
	#assert [[backdrop 10.20.30] = attributes/to-rtd-flag 'backdrop 10.20.30]
		
	value-types!: make typeset! [tuple! logic! string! integer!]
	rtd-attrs: make hash! [bold italic underline strike color backdrop size font]
	
	attributes/make-rtd-flags: function [
		"Make an RTD flags block out of data attributes"
		data [block!] limits [pair!] "segment to extract"		;-- segment used in to-spaces to create individual paragraphs
	][
		limits: clip limits 0 half length? data
		data:   append/part clear [] (skip data limits/1 * 2) (2 * span? limits)
		result: clear []
		ranges: extract-ranges data
		foreach [range attrs] ranges [ 
			flags: clear []
			pair: ~/ranges/to-rtd-pair range
			foreach [attr value] attrs [						;@@ use map-each
				unless find value-types! type? :value [
					ERROR "rich-content attribute value cannot be (type? :value) = (mold/flat/part :value 60)"
				]
				attr: attributes/to-rtd-flag to word! attr value
				if attr [append append flags pair attr]			;-- only collects attributes supported by RTD
			]
			append result flags
		]
		copy result
	]
	
	#assert [
		[1x3 bold] = attributes/make-rtd-flags [_ 0 _ 0 _ 1 _ 1 _ 1 _ 0 _ 0] 2x5
		[1x1 bold] = attributes/make-rtd-flags [_ 0 _ 0 _ 1 _ 1 _ 1 _ 0 _ 0] 4x5
		[3x3 bold] = attributes/make-rtd-flags [_ 0 _ 0 _ 1 _ 1 _ 1 _ 0 _ 0] 0x5
		[3x3 bold] = attributes/make-rtd-flags [_ 0 _ 0 _ 1 _ 1 _ 1 _ 0 _ 0] 0x10
	]
	
	attributes/change: function [
		attrs [block!] "modified"
		attr  [word!]
		value
	][
		pos: find/skip attrs attr 2
		either :value [
			change/only change any [pos tail attrs] attr :value
		][
			remove/part pos 2
		]
		attrs
	]
	
	attributes/mark: function [							;@@ maybe rename to set! ?
		data  [block!] "modified" (parse data [end | 1 3 [skip integer!] to end])
		range [word! ('all = range) pair!]
		attr  [word!]
		value
	][
		if range = 'all [range: 0 thru 2e9]
		range: clip range 0 half length? data			;-- avoid runaway repeat if range is infinite
		repeat i span? range [							;@@ use for-each!
			code: pick data i2: range/1 + i * 2
			either last-code = code [					;-- streaming optimization
				code: new-code
			][
				attrs: copy index->attrs last-code: code
				attributes/change attrs attr :value
				new-code: code: store-attrs attrs
			]
			data/:i2: code 
		]
		data
	]
	#assert [
		[] = attributes/mark [] 4x12 'x 1
		[_ 0 _ 1 _ 1 _ 1 _ 0] = attributes/mark [_ 0 _ 0 _ 1 _ 0 _ 0] 1x4 'bold on
		[_ 0 _ 0 _ 0 _ 0 _ 0] = attributes/mark [_ 0 _ 1 _ 0 _ 1 _ 0] 1x4 'bold off
		[_ 0 _ 0 _ 0 _ 0 _ 0] = attributes/mark [_ 0 _ 1 _ 1 _ 1 _ 0] 1x4 'bold off
	]
	
	;; unlike /mark, clears all attributes in the range
	attributes/clear: function [
		data  [block!] "modified" (parse data [end | 1 3 [skip integer!] to end])
		range [word! ('all = range) pair!]
	][
		if range = 'all [range: 0 thru 2e9]
		range: clip range 0 half length? data			;-- avoid runaway repeat if range is infinite
		repeat i span? range [poke data (range/1 + i * 2) 0]	;@@ use map-each/self!
		data
	]
	
	attributes/pick: function [attrs [integer! block!] attr [word!]] [
		if integer? attrs [attrs: index->attrs attrs]
		select/skip attrs attr 2 
	]
	#assert [
		on =  attributes/pick 1 'bold
		none? attributes/pick 0 'bold
		none? attributes/pick 3 'bold
		8  =  attributes/pick 3 'size
	]
	
	attributes/exclude: function [set1 [block!] set2 [block!]] [
		result: copy set1
		remove-each [name value] result [
			:value == select/case/skip set2 name 2
		]
		result
	]
	#assert [
		[a 1] = attributes/exclude [a 1 b 2] [b 2]
		[a 1] = attributes/exclude [a 1 b 2] [b 2 a 3]
		[a 3] = attributes/exclude [b 2 a 3] [a 1 b 2]
	]
	
	;; used to split text on font size change, to ease alignment
	attributes/compatible?: function [index1 [integer!] index2 [integer!]] [
		to logic! any [
			index1 =? index2
			all [
				attrs1: index->attrs index1
				attrs2: index->attrs index2
				size1: select/skip attrs1 'size 2 
				size2: select/skip attrs2 'size 2
				size1 =? size2 
				font1: select/skip attrs1 'font 2 
				font2: select/skip attrs2 'font 2 
				font1 = font2
			]
		]
	]
	
	
	source: context [deserialize: serialize: format: to-spaces: none]

	source/format: function [
		"Convert decoded source into plain text"
		data [block!] "[item attr ...] block" (even? length? data)
		/local format: {}								;-- used when item has no /format in the kit
	][
		result: make {} half length? data
		foreach [item attr] data [						;@@ use map-each
			case [
				char?  :item [append result item]
				space? :item [append result batch item [format]]
			]
		]
		#debug clipboard [#print "  rich/source/format: (mold/part result 120)"]
		result
	]
	#assert ["abc" = source/format [#"a" 1 #"b" 0 #"c" 1]]
	
	;@@ leverage prototypes for this
	source/to-spaces: function [
		"Transform decoded source into a list of spaces (for use in rich-content)"
		data [block!] "[item attr ...] block" (even? length? data)
		; return: [block!] "[content ranges]"
		/local char
	][
		content: clear []
		ranges:  clear []								;-- range spans of items that caret can dive into
		;@@ or trim linefeed? or silently split into multiple paragraphs (hard)?
		#assert [not find data #"^/"  "line breaks are not allowed inside paragraph text"]
		buf:     clear {}
		parse data [any [
			[	s: [set char char! set attr1 integer! (append buf char)]
				any [
					set char char! set attr2 integer!
					if (attributes/compatible? attr1 attr2) (append buf char)
				] e: (
					append content obj: make-space 'text []
					append obj/text buf
					clear buf
					range: half as-pair skip? s skip? e
					obj/flags: attributes/make-rtd-flags data range
				)
			|	set obj [object! integer!] (			;@@ apply attribute to the object?
					append content obj
					range: 0x1 + half skip? s
				)
			] (repend ranges [obj range])
		|	end
		|	(ERROR "Unsupported data in the source: (mold/part s 40)")
		]]
		reduce [copy content  make hash! ranges]
	]
		
	source/deserialize: function [
		"Split source into decoded block of [item attr ...]"
		source [block!]
		/local attr value item
	][
		result: clear []								;@@ should items be just chars and objects? other types support, e.g. image?
		attrs:  clear []
		parse source [any [
			set attr [
				word! (value: on)
			|	set-word! p: (value: do/next p 'p) :p	;-- reduce words (color names) to their values
			]
			(attributes/change attrs to word! attr :value)
		|	set attr refinement!						;-- attributes work stack-like and do not close automatically
			(attributes/change attrs to word! attr none)
		|	set item string! (							;@@ make it a module
				code: store-attrs attrs
				zip/into explode item code result
			)
		|	set item skip (
				code: store-attrs attrs
				repend result [item code]
			)
		]]
		copy result
	]
	#assert [
		[#"1" 0 #"2" 0 #"3" 1 #"4" 1 #"5" 1 #"6" 1 #"7" 0] = source/deserialize ["12" bold "3456" /bold "7"]
	]
	
	source/serialize: function [
		"Create a source block out of decoded data"
		data [block!] "[item attr ...] block" (even? length? data)
	][
		result:     clear []
		string:     clear {}
		last-attrs: clear []
		last-code:  0
		flush-string: [
			unless empty? string [
				append result copy string
				clear string
			]
		]
		foreach [item code] data [
			if last-code <> code [
				do flush-string
				attrs: index->attrs last-code: code
				opened: attributes/exclude attrs last-attrs 2	;-- native 'exclude' is useless since it ignores value slot
				closed: attributes/exclude last-attrs attrs 2
				last-attrs: attrs
				foreach [name value] closed [			;@@ use map-each
					append result to refinement! name
				]
				foreach [name value] opened [			;@@ use map-each
					repend result either true = :value [[name]] [[to set-word! name :value]]
				]
			]
			either char? :item [
				append string item
			][
				do flush-string
				append/only result :item
			]
		]
		do flush-string
		;@@ no reason to auto-close opened attributes?
		copy result
	]
	
	#assert [
		["x"] = source/serialize [#"x" 0]
		["12" bold "3456" /bold "7"] = source/serialize [#"1" 0 #"2" 0 #"3" 1 #"4" 1 #"5" 1 #"6" 1 #"7" 0]
		; ["12" bold underline "3" /bold /underline] = source/serialize [#"1" 0 #"2" 0 #"3" 2]
		["12" bold underline "3"] = source/serialize [#"1" 0 #"2" 0 #"3" 2]
		["12" bold underline "3" /bold /underline "4"] = source/serialize [#"1" 0 #"2" 0 #"3" 2 #"4" 0]
		["1" size: 8 "2" /size size: 12 "3" /size "4"] = source/serialize [#"1" 0 #"2" 3 #"3" 4 #"4" 0]
	]
]
