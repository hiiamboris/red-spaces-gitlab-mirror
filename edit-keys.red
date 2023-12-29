Red [
	title:   "Keys to edit commands mapping for editable Spaces"
	author:  @hiiamboris
	license: BSD-3
]	

key->plan: none
context [
	near-moves: #(
		left       [by -1]
		right      [by  1]
		backspace  [by -1]
		delete     [by  1]
		home       'head 
		end        'tail
		up         'line-up
		down       'line-down
		page-up    'page-up
		page-down  'page-down
	)
	far-moves:  extend copy near-moves #(
		left      'prev-word
		right     'next-word
		backspace 'prev-word
		delete    'next-word
		home      'far-head
		end       'far-tail
	)

	set 'key->plan function [
		"Turn keyboard event into an edit plan"
		event    [event! map! object!]
		selected [pair! none!] "Current selection state"
	][
		key: event/key
		either printable?: all [
			char? key
			key >= #" "
			not event/ctrl?
		][
			compose [
				remove-range selected
				insert-items here (form key)
			]
		][
			if key = #"^H" [key: 'backspace]
			if all [selected  0 = span? selected] [selected: none]	;-- ignore empty selection
			removal?: find [delete backspace] key
			distance: select either event/ctrl? [far-moves][near-moves] key
			action:   case [removal? ['remove-range] event/shift? ['select-range] 'else ['move-caret]]
			if all [removal?  selected] [distance: 'selected]
			if block? distance [						;-- [move-caret [by 1]] -> [move-caret/by 1]
				distance: distance/2
				action: as path! reduce [action 'by]
			]
			switch/default key [
				left right home end up down page-up page-down [
					deselect?: when all [selected not event/shift?] [select-range none]
					compose [(deselect?) (action) (distance)]
				] 
				delete backspace [compose [(action) (distance)]]
				insert [
					case [
						event/ctrl?  [[copy-range/clip selected]]
						event/shift? [[remove-range selected  paste here]]
						'else        [[]]
					]
				]
				#"A" [[select-range everything]]
				#"C" [[copy-range/clip selected]]
				#"X" [[remove-range/clip selected]]
				#"V" [[remove-range selected  paste here]]
				#"Z" [pick [[redo] [undo]] event/shift?]
			] [[]]										;-- not supported yet key
		]
	]
]
