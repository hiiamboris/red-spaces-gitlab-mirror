Red [
	title:       "On-hover highlight support for Spaces"
	description: "Provides extra OVER events when pointer leaves the space or it is moved on the frame without actual pointer movement"
	author:      @hiiamboris
	license:     BSD-3
]

;-- no load requirements

;@@ for this design to work, all /into funcs must accept (return none) spaces that are no longer their children!

context [
	over-face: none										;@@ suffers from REP #129
	last-path: none
	
	scheduler/event-filters/away-generator: function [face event [map!] "assumes healed event"] [
		switch event/type [
			over [										;-- pointer may have left a space it was in
				if select over-face 'space [
					detect-away over-face event
				]
				unless over-face =? face [				;-- hovering over a new host - full reset
					self/last-path: none
					self/over-face: if face/space [face]
				]
			]
			time [										;-- space may have been moved on the last frame
				if all [over-face =? face  face/space] [
					detect-away face event
				]
			]
			down [self/last-path: none]					;-- dragging initializes a new path (probably shorter than a normal one)
		]
		none											;-- let other event funcs process it
	]
	
	;; logic here is to repeat hittest and see if any space in the new path differs from the last path
	;; last path should be updated by every host's 'over' and 'time' event
	detect-away: function [host [object!] event [map!]] [
		case [
			all [
				drag?: events/dragging?					;-- during dragging away condition is registered routinely
				event/type <> 'time						;-- but it still may have moved on the frame
			] [exit]
			not last-path [								;-- first over for this host?
				self/last-path: make [] 20
				exit
			]
		]
		
		if event/type = 'time [							;-- need to synthesize the 'over event?
			event: copy event
			event/type: 'over
			#assert [event/offset]						;-- must be filled by heal-event
			#assert [event/face =? host]
		]
				
		#debug profile [prof/manual/start 'hovering]
		template: either drag? [last-path][host/space]
		hittest/into template event/offset clear new-path: []
		
		if moved?: not same-paths? last-path new-path [
			;; while 'over' now lands into another space, we need to send the event into the old one, as 'away notice'
			hittest/into last-path event/offset clear path: []	;-- update coordinates along the last-path
			events/with-stop [events/process-event path event [] no]
			append clear last-path new-path						;-- stash the modified path
		]
		#debug profile [prof/manual/end 'hovering]
	]
]
