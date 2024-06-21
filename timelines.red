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
		if timeline/limit * period < length? timeline/events [	;-- trim the head
			n: round/to timeline/limit * 5% 1
			remove/part timeline/events n * period
		]
	]
	
	elapsed?: function [timeline [object!]] [
		if last-time: pick timeline/events negate period [
			difference now/utc/precise last-time
		]
	]
	
	unwind: function [timeline [object!]] [				;-- unlike undo, does not evaluate anything
		also timeline/last-event
		timeline/events: skip timeline/events negate period
	]
	
	last-event: function [timeline [object!] filter [object! none!]] [
		p: timeline/events
		until [
			if head? p [return none]
			p: skip p negate period
			any [not filter  filter =? p/1] 
		]  
		copy/part next p period - 1
	]
		
	;@@ add docstrings? (increases timeline size - critical in fields)
	set 'timeline! make classy-object! declare-class 'timeline [
		events:     []
		limit:      1000	#type [integer!] (limit >= 20)		;-- max number of events to keep
		elapsed?:   does [~/elapsed? self]						;-- can return none if timeline is empty
		last-event: func [/for obj [object!]] [~/last-event self obj]	;-- only returns arguments to 'put', not the time
		undo:       does [~/undo self]
		redo:       does [~/redo self]
		mark:       does [events]								;-- gets current location in the timeline to save
		unwind:     does [~/unwind self]						;-- like 'undo' but does not execute 'left' events
		put: func [space [object!] left [block!] right [block!] /last] [
			~/put self space left right last
		]
	]
]
