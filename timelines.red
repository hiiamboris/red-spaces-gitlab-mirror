Red [
	title:   "Timelines for Spaces"
	purpose: "Provide generalized history with undo/redo capabilities"
	author:  @hiiamboris
	license: BSD-3
]	


timeline!: none

context [
	~: self
	
	;; timeline format: [date space left-action right-action ...]
	period: 4
	
	undo: function [timeline [object!]] [
		if head? timeline/events [exit]
		set [date: space: left: right:] timeline/events: skip timeline/events negate period
		do left
		focus-space space
	]
	
	redo: function [timeline [object!]] [
		if tail? timeline/events [exit]
		set [date: space: left: right:] timeline/events
		timeline/events: skip timeline/events period
		do right
		focus-space space
	]
	
	put: function [timeline [object!] space [object!] left [block!] right [block!] replace? [logic!]] [
		if replace? [timeline/events: skip timeline/events negate period]
		timeline/events: clear rechange timeline/events [
			now/utc/precise
			space
			with space left
			with space right
		]
	]
	
	fresh?: function [timeline [object!]] [
		to logic! all [
			last-time: pick timeline/events negate period
			elapsed: difference now/utc/precise last-time
			elapsed < timeline/interval
		]
	]
		
	set 'timeline! make classy-object! declare-class 'timeline [
		events:     []
		interval:   0:0:1								;-- time needs to elapse before event group is finished
		fresh?:     does [~/fresh? self]
		last-event: does [copy/part events -3]			;-- only returns arguments to 'put', not the time
		undo:       does [~/undo self]
		redo:       does [~/redo self]
		put: func [space [object!] left [block!] right [block!] /last] [
			~/put self space left right last
		]
	]
]
