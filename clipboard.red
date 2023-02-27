Red [
	title:   "Extended clipboard for Spaces"
	purpose: "Allow copy/paste of rich content within document"
	author:  @hiiamboris
	license: BSD-3
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
			map-each item data [
				only all [
					space? :item
					function? select item 'clone
					item/clone
				]
			]
		]
	]
	
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
		content [block! (parse content [any object!]) string!]
	][
		content: either string? content [
			copy content
		][
			clone-data content
		]
		append clear data content
		write-clipboard self/text: data-to-text data
	]
]

