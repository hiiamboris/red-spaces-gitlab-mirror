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
	;; prototype for custom clipboard formats
	text!: make classy-object! format!: declare-class 'clipboard-format [
		name:   'text				#type [word!]
		data:   {}
		length: does [length? data]	#type [function!]
		clone:  does [copy self]	#type [function!]
		format: does [copy data]	#type [function!]
	]
	
	;; text is used to detect if some other program wrote to clipboard
	;; if read text = last written text, we can use `data`
	;; otherwise data is invalid and clipboard is read as plain text string
	
	data: copy text!									;-- last copied data
	
	read: function [
		"Get clipboard contents"
		/text "Return text even if data is non-textual"
	][
		read: read-clipboard
		unless read == as-text: data/format [			;-- last copy comes from outside the running script
			self/data: make text! [data: read]
			if text [as-text: data/format]
		]
		either text [as-text][data/clone]
	]
	
	write: function [
		"Write data to clipboard"
		content [object! ('clipboard-format = class? content) string!]
	][
		write-clipboard either string? content [
			self/data: make text! [data: copy content]
		][
			self/data: content/clone
			data/format
		]
	]
]

