Red [
	title:       "On-hover highlight support for Spaces"
	description: "Provides extra OVER events when pointer leaves the space or it is moved on the frame without actual pointer movement"
	author:      @hiiamboris
	license:     BSD-3
]

;-- no load requirements

;@@ for this design to work, all /into funcs must accept (return none) spaces that are no longer their children!

context [
	last-path: make [] 20								;@@ suffers from REP #129
	
	scheduler/event-filters/away-generator: function [face event [map!] "assumes healed event"] [
		#debug events [id: #composite "(select face 'type):(select face 'size)"]
		switch event/type [
			over [										;-- pointer may have left a space it was in
				#debug events [#print "got 'over' event for (id) away=(event/away?)"]
				#debug events [#print "checking it for space change..."]
				detect-away face event
				; if event/away? [clear last-path]
			]
			time [										;-- space may have been moved on the last frame
				; if face =? over-face [					;@@ see #5520 why sameness check is needed
					#debug events [#print "got 'time' event while over (id); checking it for space change..."]
					detect-away face event
				; ]
			]
			down [clear last-path]						;-- dragging initializes a new path (probably shorter than a normal one)
		]
		none											;-- let other event funcs process it
	]
	
	;; logic here is to repeat hittest and see if any space in the new path differs from the last path
	;; last path should be updated by every host's 'over' and 'time' event
	detect-away: function [host [object!] event [map!]] [
		if all [
			drag?: events/dragging?						;-- during dragging away condition is registered routinely
			event/type <> 'time							;-- but it still may have moved on the frame
		] [exit]
		
		#debug events [#print "reached still 'over' detection code for (host/type):(host/size) away=(event/away?)"]
		if event/type = 'time [							;-- need to synthesize the 'over event?
			event: copy event
			event/type: 'over
			#assert [event/offset]						;-- must be filled by heal-event
			; #assert [event/face =? host]				;-- doesn't hold when already moved away from the last host
		]
				
		#debug profile [prof/manual/start 'hovering]
		template: either drag? [last-path][host/space]
		hittest/into template event/offset clear new-path: []
		
		if moved?: not same-paths? last-path new-path [
			#debug events [#print "still movement confirmed based on paths (mold last-path)->(mold new-path)"]
			;; while 'over' now lands into another space, we need to send the event into the old one, as 'away notice'
			hittest/into last-path event/offset clear path: []	;-- update coordinates along the last-path
			events/with-stop [events/process-event path event [] no]
			append clear last-path new-path						;-- stash the modified path
		]
		#debug profile [prof/manual/end 'hovering]
	]
]
