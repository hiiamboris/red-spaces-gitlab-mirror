Red [
	title:   "Timelines for Spaces"
	purpose: "Provide generalized history with undo/redo capabilities"
	author:  @hiiamboris
	license: BSD-3
]	


timeline!: none

context [
	~: self
	
	;; timeline format: [space left-action right-action ...]
	
	undo: function [timeline [object!]] [
		if head? timeline/events [exit]
		set [space: left: right:] timeline/events: skip timeline/events -3
		do left
		focus-space space
	]
	
	redo: function [timeline [object!]] [
		if tail? timeline/events [exit]
		set [space: left: right:] timeline/events
		timeline/events: skip timeline/events 3
		do right
		focus-space space
	]
	
	put: function [timeline [object!] space [object!] left [block!] right [block!]] [
		timeline/events: clear rechange timeline/events [
			space
			with space left
			with space right
		]
	]
		
	set 'timeline! object [
		events: []
		undo: does [~/undo self]
		redo: does [~/redo self]
		put:  func [space [object!] left [block!] right [block!]] [~/put self space left right]
	]
]
