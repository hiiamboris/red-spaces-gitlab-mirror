Red [
	title:   "Rich-content source format codec and editor"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Markdown & co which are source formats for humans, that a machine can understand but with a lot of work.
		GML and it's successors are source formats for machines that neither a human cannot read anymore, nor machine parse efficiently.
		My format here is a Red block-level data representation for machines, that should be simple enough for a human to read.
		
		TODO: design principles and gotchas, and make a design card for it
	}
]

;@@ should there be a single items/attributes array for the whole document composed from many paragraphs sources?

rich: context [	;@@ how to name it?
	~: self												;-- allows to combine 'ranges' context with 'ranges' word
	
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
		
		
	;; externalization avoids name collision for common names like insert, copy, etc
	masks: context [
		from-range:
		to-ranges:
		normalize:
		pick:
		shift:
		clip:
		include:
		exclude:
		remove:
			none
		empty: #{}
	]
	
	masks/from-range: function [range [pair!]] [
		if range/2 < range/1 [range: reverse range]
		range: max 0 range
		#assert [range/2 < infxinf/x]
		either positive? range/2 [
			to #{} charset when range/2 <> range/1 (
				reduce [range/1 '- range/2 - 1]
			)
		][
			copy #{}
		]
	]
	#assert [
		#{}       = masks/from-range -50x-100
		#{}       = masks/from-range 0x0
		#{FFFF}   = masks/from-range 0x16
		#{7FFFC0} = masks/from-range 1x18
		#{0FFC}   = masks/from-range 4x14
	]
	
	zero!:          charset [0]
	; nonzero!:       complement zero!
	; nonzero-digit!: complement charset "0"
	
	masks/to-ranges: function [mask [binary!]] [
		parse mask [any zero! mask:]					;-- optimization: skip leading zeroes
		ranges: clear []
		unless empty? mask [
			base: 8 * skip? mask
			mask: enbase/base mask 2
			parse mask [any [
				any #"0" opt [s: some #"1" e: (
					append ranges base + as-pair skip? s skip? e
				)]
			]]
		]
		copy ranges
	]
	#assert [
		[0x16]     = masks/to-ranges #{FFFF}
		[1x18]     = masks/to-ranges #{7FFFC0}
		[1x8 9x18] = masks/to-ranges #{7F7FC0}
	]
	
	masks/normalize: function [mask [binary!]] [
		trim/tail mask									;@@ workaround for bitset weirdness - auto trim the tail
	]
	#assert [#{FF80} = masks/normalize #{FF800000}]
	
	masks/pick: function [mask [binary!] index [integer!]] [
		pick to bitset! mask index - 1
	]
	
	masks/shift: function [mask [binary!] offset [integer!]] [
		if zero? offset [return copy mask]
		mask: enbase/base mask 2
		either offset < 0 [
			remove/part mask negate offset
		][
			insert/dup mask #"0" offset
		]
		append/dup mask #"0" (negate length? mask) and 7	;@@ stupid debase only accepts length divisible by 8
		masks/normalize debase/base mask 2
	]
	#assert [
		#{7FFF80} = masks/shift #{FFFF}    1
		#{FFFF}   = masks/shift #{7FFF80} -1
	]
	
	masks/clip: function [mask [binary!] range [pair!]] [
		masks/normalize mask and masks/from-range min range 8 * length? mask
	]
	#assert [
		#{0FFC}   = masks/clip #{FFFFF0} 4x14
		#{0FFFF0} = masks/clip #{FFFFF0} 4 by infxinf/x
	]
	
	masks/include: function [mask [binary!] other [pair! binary!]] [
		if pair? other [other: masks/from-range other]
		mask or other									;-- both are expected to be normalized already
	]
	masks/exclude: function [mask [binary!] other [pair! binary!]] [
		if pair? other [other: masks/from-range min other 8 * length? mask]
		append/dup other #{00} (length? mask) - length? other
		masks/normalize mask and complement copy other
	]
	#assert [
		#{0FFC}      = masks/include #{}       4x14
		#{FFFFF0}    = masks/include #{F003F0} 4x14
		#{FFFFF0}    = masks/include #{F00FF0} #{0FF0}
		#{FFFFFF}    = masks/include #{F0}     #{0FFFFF}
		
		#{F003F0}    = masks/exclude #{FFFFF0} 4x14
		#{FFF0}      = masks/exclude #{FFFFF0} 12 by infxinf/x
		#{F00FF0}    = masks/exclude #{FFFFF0} #{0FF0}
		#{F0}        = masks/exclude #{FFFFF0} #{0FFFFF}
		2#{10101000} = masks/exclude 2#{11111100} 2#{01010100}
	]
	
	masks/remove: function [mask [binary!] range [pair!]] [
		if zero? span? range [return copy mask]
		mask: enbase/base mask 2
		remove/part skip mask range/1 range/2 - range/1 
		append/dup mask #"0" (negate length? mask) and 7	;@@ stupid debase only accepts length divisible by 8
		masks/normalize debase/base mask 2
	]
	#assert [#{FFC0} = masks/remove #{FFFFF0} 4x14]
	
	
	
	values: context [
		normalize:
		map-each:
		copy:
		remove:
		exclude:
		clip:
		shift:
		union:
		insert:
			none
	]
	
	values/normalize: function [
		"Returns a copy of values list without intersections and empty ranges"
		vlist [block!] "Latter values take priority"
	][
		vlist: skip tail copy vlist -2
		coverage: copy vlist/2							;-- maintaining coverage allows it to be O(number of values)
		while [not head? vlist] [						;@@ use for-each/reverse
			vlist: skip vlist -2
			vlist/2: masks/exclude vlist/2 coverage
			unless head? vlist [coverage: coverage or vlist/2]
			if empty? vlist/2 [remove/part vlist 2]		;-- empty? works because masks/exclude trims it
		]
		vlist
	]
	#assert [
		[1 2#{10101000} 2 2#{01010100}]                = values/normalize [1 2#{11111100} 2 2#{01010100}]
		[1 2#{11000000} 2 2#{00011000} 3 2#{00000011}] = values/normalize [1 2#{11000000} 2 2#{00011000} 3 2#{00000011}]
	]
	
	values/map-each: function [							;@@ use normal map-each when it's native
		"Map value list into another one, transforming masks"
		spec [block!] "[value mask]" vlist [block!] code [block!] "Should return a new mask"
	][
		result: clear copy vlist
		foreach (spec) vlist [repend result [get/any spec/1 do code]]
		result 
	]
	
	values/copy: function [vlist [block!] /local value mask] [	;-- copy/deep would break sameness whereas this won't
		values/map-each [value mask] vlist [copy mask]
	]
	
	values/remove: function [vlist [block!] range [pair!] /local value mask] [
		values/normalize values/map-each [value mask] vlist [masks/remove mask range]
	]
	
	values/exclude: function [vlist [block!] range [pair!] /local value mask] [
		values/normalize values/map-each [value mask] vlist [masks/exclude mask range]
	]
	
	values/clip: function [vlist [block!] range [pair!] /local value mask] [
		values/normalize values/map-each [value mask] vlist [masks/clip mask range] 
	]
	
	values/shift: function [vlist [block!] offset [integer!] /local value mask] [
		values/map-each [value mask] vlist [masks/shift mask offset]
	]
	
	values/union: function [vlist1 [block!] vlist2 [block!]] [
		vlist1: copy vlist1
		foreach [value mask2] vlist2 [
			either pos: find/only/same/skip vlist1 :value 2 [
				pos/2: pos/2 or mask2
			][
				repend vlist1 [:value copy mask2]
			]
		]
		values/normalize vlist1
	]
	
	;; without 'range' (pair) length of 'other' is unknown
	values/insert: function [vlist [block!] range [pair!] other [block!]] [
		part1: values/clip vlist 0 by range/1
		part2: values/shift
			values/clip vlist range/1 by infxinf/x
			range/2 - range/1
		other: values/shift other range/1
		vlist: values/union part1 part2
		either empty? other [vlist][values/union vlist other]
	]
	#assert [[1 #{A00B}] = values/insert [1 #{AB}] 4x12 []]
	
	{
		attrs format: #(
			name [
				value1 [range range ...]				;-- ranges sorted (by start then end)
				value2 [range range ...]				;-- value is 'true' for words, anything else for set-words
				...
			]
			...
		)
	}
	attributes: context [
		to-rtd-flag:
		make-rtd-flags:
		mark:		;@@ or 'set'?
		clear:
		pick:
		map-each:
		clip:
		copy:
		remove:
		shift:
		union:
		insert:
			none
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
		attrs [map!] limits [pair!]
	][
		length: limits/2 - limits/1
		flags: clear []
		foreach [attr values] attrs [
			unless find rtd-attrs attr [continue]
			foreach [value mask] values [
				foreach range masks/to-ranges mask [	;@@ use map-each
					range: clip 0 length range - limits/1
					if zero? span? range [continue]
					pair: ranges/to-rtd-pair range
					flag: attributes/to-rtd-flag to word! attr value
					append append flags pair flag
				]
			]
		]
		copy flags
	]
	#assert [
		[1x8  bold] = attributes/make-rtd-flags #(bold [#[true] #{0FFFF0}]) 4x12
		[5x8  bold] = attributes/make-rtd-flags #(bold [#[true] #{0FFFF0}]) 0x12
		[5x16 bold] = attributes/make-rtd-flags #(bold [#[true] #{0FFFF0}]) 0x20
	]
	
	;@@ modify or not? currently it's a mess
	
	;@@ maybe move range before attr in the spec?
	attributes/mark: function ["modifies" attrs [map!] attr [word!] value range [pair!] state [logic!]] [
		values: any [attrs/:attr  attrs/:attr: make [] 2]
		unless pos: find/same/only/skip values :value 2 [
			repend pos: tail values [:value copy masks/empty]
		]
		pos/2: either state [masks/include pos/2 range][masks/exclude pos/2 range]
		attrs/:attr: ~/values/normalize values
		attrs
	]
	#assert [
		#(bold [#[true] #{0FF0}]) = attributes/mark #(bold [#[true] #{}])     'bold on 4x12 on
		#(bold [#[true] #{0FF0}]) = attributes/mark #(bold [#[true] #{0000}]) 'bold on 4x12 on
		#(bold [#[true] #{F00F}]) = attributes/mark #(bold [#[true] #{FFFF}]) 'bold on 4x12 off
		#(x [1 2#{01100110} 2 2#{00011000}]) = attributes/mark #(x [1 2#{01111110}]) 'x 2 3x5 on
		#(x [1 2#{01100000} 2 2#{00001100} 3 2#{00000001}]) = attributes/mark #(x [1 2#{01100000} 2 2#{00001100}]) 'x 3 7x8 on
	]
	
	;; unlike /mark, clears all values in the range
	attributes/clear: function ["modifies" attrs [map!] attr [word!] range [pair!]] [
		if values: attrs/:attr [
			values: ~/values/exclude values range
			either empty? values [remove/key attrs attr][attrs/:attr: values]
		]
		attrs
	]
	#assert [#(bold [#[true] #{F001}]) = attributes/clear #(bold [#[true] #{FFF1}]) 'bold 4x12]
	
	;; problem with this one is not having a way to determine if attr is `none` or absent
	;; but I haven't designed attributes to carry 'none' value anyway
	attributes/pick: function [attrs [map!] attr [word!] index [integer!]] [
		if values: attrs/:attr [
			foreach [value mask] values [
				if masks/pick mask index [return :value]
			]
		]
		none
	]
	#assert [
		on =  attributes/pick #(bold [#[true] #{F001}]) 'bold 1
		on =  attributes/pick #(bold [#[true] #{F001}]) 'bold 4
		on =  attributes/pick #(bold [#[true] #{F001}]) 'bold 16
		none? attributes/pick #(bold [#[true] #{F001}]) 'bold 0
		none? attributes/pick #(bold [#[true] #{F001}]) 'bold 5
	]
	
	attributes/map-each: function [spec [block!] "[attr values]" attrs [map!] code [block!]] [
		make map! map-each/eval (spec) attrs compose/only [		;-- have to compose for code to be bound to the spec
			when not empty? values: do (code) (spec)
		]
	]
	
	; attributes/normalize: function [attrs [map!]] [
		; attributes/map-each [attr values] attrs [~/values/normalize values]
	; ]
	attributes/clip: function [attrs [map!] range [pair!]] [
		attributes/map-each [attr values] attrs [~/values/clip values range]
	]
	#assert [#(bold [#[true] #{0F}]) = attributes/clip #(bold [#[true] #{0FF0}]) 4x8]
	
	attributes/copy: function [attrs [map!] range [pair!]] [
		attributes/shift attributes/clip attrs range negate range/1
	]
	
	attributes/remove: function [attrs [map!] range [pair!]] [
		attributes/map-each [attr values] attrs [~/values/remove values range]
	]
	#assert [#(bold [#[true] #{0FF0}]) = attributes/remove #(bold [#[true] #{0FFF}]) 4x8]
	
	attributes/shift: function [attrs [map!] offset [integer!]] [
		attributes/map-each [attr values] attrs [~/values/shift values offset]
	]
	#assert [
		#(bold [#[true] #{000FF0}]) = attributes/shift #(bold [#[true] #{0FF0}])  8
		#(bold [#[true] #{F0}    ]) = attributes/shift #(bold [#[true] #{0FF0}]) -8
	]

	attributes/union: function [attrs [map!] other [map!]] [
		names: union keys-of attrs keys-of other
		result: make map! length? names
		foreach name names [
			result/:name: case [
				not attrs/:name [values/copy other/:name]
				not other/:name [values/copy attrs/:name]
				'both-have-it [values/union attrs/:name other/:name]
			]
		]
		result
	]
	#assert [#(bold [#[true] #{F00F}]) = attributes/union #(bold [#[true] #{000F}]) #(bold [#[true] #{F0}])]

	;; without 'range' (pair) length of 'other' is unknown
	attributes/insert: function [attrs [map!] range [pair!] other [map!]] [
		attrs: attributes/map-each [attr values] attrs [
			~/values/insert values range []
		]
		other: attributes/clip attributes/shift other range/1 range
		attributes/union attrs other
	]
	#assert [#(bold [#[true] #{CABF}]) = attributes/insert #(bold [#[true] #{CF}]) 4x12 #(bold [#[true] #{ABD0}])]

	source: context [
		;@@ need to make modularity somehow, later
		; datatypes: make map! reduce [
			; string! object [
				
			; ]
		; ]
		
		deserialize: function [
			"Split source into [items attributes]"
			source [block!]
			/local attr value item
		][
			items:   clear copy source					;@@ should items be just chars and objects? other types support, e.g. image?
			attrs:   make #() 10
			pending: make #() 10
			offset:  0
			parse source [any [
				set attr [
					word! (value: on)
				|	set-word! p: (value: do/next p 'p) :p	;-- reduce words (color names) to their values
				] (
					attr:  to word! attr
					stack: any [pending/:attr  pending/:attr: make [] 4]
					repend stack [offset :value]
				)
			|	set attr refinement! (							;-- attributes work stack-like and do not close automatically
					attr:  to word! attr
					unless empty? stack: pending/:attr [		;-- extra closings are silently ignored
						value: take/last stack
						start: take/last stack
						attributes/mark attrs attr :value start by offset on
					]
				)
			|	set item string! (								;@@ make it a module
					parse item [collect after items keep pick to end]	;-- explodes the string
					offset: offset + length? item
				)
			|	set item skip (
					append/only items item
					offset: offset + 1
				)
			]]
			foreach [attr stack] pending [						;-- auto-close unclosed ranges
				foreach [start value] stack [
					attributes/mark attrs to word! attr :value start by offset on
				]
			]
			; attrs: attributes/normalize attrs
			reduce [items attrs]
		]
		
		serialize: function [
			"Create a source block out of items and attributes"
			items [block!] attrs [map!]
			/local part
		][
			queue: clear []
			foreach [attr values] attrs [
				values: ~/values/normalize values
				foreach [value mask] values [
					opening: either true = :value [to word! attr][reduce [to set-word! attr :value]]
					closing: to refinement! attr
					foreach range masks/to-ranges mask [
						;; order is important: close then open, that's why I add 0.1
						;; e.g. to avoid output like `color: 1 "x" color: 2 /color "x" /color`
						;; when it should have been  `color: 1 "x" /color color: 2 "x" /color`
						repend queue [range/1 + 0.1 opening range/2 closing]
					]
				]
			]
			sort/stable/skip queue 2
			result: clear []
			foreach [offset marker] queue [
				append/part result items items: skip head items to integer! offset
				append result marker
			]
			append result items
			parse result [any [							;-- unify chars into strings
				change copy part some char! (to string! part)
			|	skip
			]]
			copy result
		]
		
		#assert [
			["x"] = serialize [#"x"] #()
			["12" bold "3456" /bold "7"] == serialize [#"1" #"2" #"3" #"4" #"5" #"6" #"7"] #(bold [#[true] #{3C}])
			["12" bold underline "3" /bold /underline] = serialize [#"1" #"2" #"3"] #(bold [#[true] #{20}] underline [#[true] #{20}])
			["1" x: 1 "2" /x x: 2 "3" /x "4"] = serialize [#"1" #"2" #"3" #"4"] #(x [1 #{40} 2 #{20}])
		]
		
		;@@ leverage prototypes for this
		to-spaces: function [
			"Transform decoded source into a list of spaces, return [content ranges]"
			items [block!] attrs [map!]
		][
			;@@ should I clip attrs to items/length?
			;; collect all /command change offsets
			commands: clear []
			;@@ how can I possibly generalize this all? perhaps all attributes except text ones should become spans?
			offset: 0
			if attrs/command [
				foreach [value mask] attrs/command [
					ranges: masks/to-ranges mask
					foreach range ranges [repend commands [range :value]]
				]
				filled: sort/skip commands 2
				commands: clear []
				foreach [range value] filled [
					repend commands [
						offset by range/1 none
						range :value
					]
					offset: range/2
				]
			]
			repend commands [offset by length? items none]
			
			;; split items into spans at /command change offsets - to generate clickables
			spans: clear []
			foreach [range value] commands [
				list: copy/part items range + 1
				repend spans ['command :value range/1 list]
			]
			
			;@@ maybe do this within the upper loop? to avoid sublist allocations
			content: clear []
			ranges:  clear []							;-- range spans of items that caret can dive into
			foreach [attr value offset items] spans [
				spaces: clear []
				parse items [any [
					s: some [not #"^/" char!] e: (
						append spaces obj: make-space 'text []
						append/part obj/text s e
						limits: offset + as-pair skip? s skip? e
						obj/flags: attributes/make-rtd-flags attrs limits
						repend ranges [obj limits]
					)
				|	[
						#"^/" (obj: make-space 'break [])		;-- equivalent: lf <-> break (single item)
					|	set obj object!
					] (
						append spaces obj 
						repend ranges [obj  offset + 0x1 + skip? s]
					)
				|	end
				|	(ERROR "Unsupported data in the source: (mold/part s 40)")
				]]
				either :value [
					append content obj: make-space 'clickable [
						content: make-space 'list [
							quietly axis:   'x
							quietly margin: 0x0
						]
					]
					; quietly obj/content/spacing: space/spacing	@@ need rich-content for this, or spacing info
					quietly obj/content/content: copy spaces
					quietly obj/command: value
					limits: offset by length? items
					repend ranges [
						obj limits
						obj/content limits
					]
				][
					append content spaces
				]
			]
			reduce [copy content make hash! ranges]
		]
	]
]
