Red [
	title:   "Extended clipboard for Spaces"
	purpose: "Allow copy/paste of rich content within document"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Data is cloned twice, when:
		- it's put into clipboard - so any change in the source does not affect clipped contents
		- it's fetched from clipboard - so any change in the pasted data does not affect clipped contents
		  and also so spaces can be pasted multiple times without any effort on the pasting code's side
	}
]	

clipboard: context [
	;; text is used to detect if some other program wrote to clipboard
	;; if read text = last written text, we can use `data`
	;; otherwise data is invalid and clipboard is read as plain text string
	
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
			#assert [parse data [block! map!]]
			items: map-each [obj [object!]] data/1 [
				either function? select obj 'clone [obj/clone][#" "]	;-- fill unsupported items with space, to preserve attr mapping
			]
			reduce [
				items
				make map! copy/deep to [] data/2		;@@ cannot use copy/deep on maps
			]
		]
	]
	
	;@@ TODO: /as refinement with 'text and 'rich-text formats for more abstraction?
	read: function [
		"Get clipboard contents"
		/text "Return text even if data is non-textual"
	][
		read: read-clipboard
		unless read == self/text [self/data: self/text: read]	;-- last copy comes from outside the running script
		clone-data either text [self/text][data]
	]
	
	write: function [
		"Write data to clipboard"
		content [block! (parse content [block! map!]) string!]
	][
		content: either string? content
			[copy content]
			[clone-data content]
		append clear data content
		write-clipboard self/text: data-to-text data
	]
]

