Red [
	title:   "Keys to edit commands mapping for editable Spaces"
	author:  @hiiamboris
	license: BSD-3
]	

key->plan: none
context [
	near-moves: #(
		left      -1
		right      1
		backspace -1
		delete     1
		home       head
		end        tail
		up         up
		down       down
	)
	far-moves:  #(
		left      prev-word
		right     next-word
		backspace prev-word
		delete    next-word
		home      far-head
		end       far-tail
		up        up
		down      down
	)

	set 'key->plan function [
		"Turn keyboard event into an edit plan"
		event    [event! object!]
		selected [pair! none!] "Current selection state"
	][
		key: event/key
		either printable?: all [
			char? key
			key >= #" "
			not event/ctrl?
		][
			compose [
				remove selected
				insert (form key)
			]
		][
			if key = #"^H" [key: 'backspace]
			removal?: find [delete backspace] key
			distance: select either event/ctrl? [far-moves][near-moves] key
			action:   case [removal? ['remove] event/shift? ['select] 'else ['move]]
			if all [removal? selected] [distance: 'selected]
			switch/default key [
				left right home end up down delete backspace [reduce [action distance]]
				#"A" [[select all]]
				#"C" [[copy selected]]
				#"X" [[copy selected  remove selected]]
				#"V" [[remove selected  paste]]
				#"Z" [pick [[redo] [undo]] event/shift?]
			] [[]]										;-- not supported yet key
		]
	]
]
