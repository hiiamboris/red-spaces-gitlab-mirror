Red [
	title:       "On-hover highlight support for Spaces"
	description: "Provides extra OVER events when pointer leaves the space or it is moved on the frame without actual pointer movement"
	author:      @hiiamboris
	license:     BSD-3
]

;-- no load requirements


context [
	last-offsets: make hash! 2							;@@ suffers from REP #129
	insert-event-func function [face event] [
		if host? face [
			switch event/type [
				over [									;-- pointer may have left a space it was in
					pos: any [find/same last-offsets face  tail last-offsets]
					change change pos face event/offset
					detect-away face event event/offset
				]
				time [									;-- space may have been moved on the last frame
					if offset: select/same last-offsets face [
						detect-away face event offset
					]
				]
			]
		]
		none											;-- let other event funcs process it
	]
	
	;; virtual forged 'over' event template
	false-event: construct map-each word system/catalog/accessors/event! [to set-word! word]
	
	;; logic here is to repeat hittest and see if any space in the new path differs from the last path
	;; last path should be updated by every host's 'over' and 'time' event
	last-paths: make hash! 2							;@@ suffers from REP #129
	detect-away: function [
		host [object!]
		event [event!]
		host-offset [pair!]
	][
		case [
			not host/space   [exit]						;-- not initialized - no hittesting
			all [
				events/dragging?						;-- during dragging away condition is registered routinely
				event/type <> 'time						;-- but it still may have moved on the frame
			] [exit]
			not pos: find/same last-paths host [		;-- first over for this host?
				repend last-paths [host make [] 20]
				exit
			]
		]
		
		old-path: pos/2
		hittest/into host/space host-offset clear new-path: []
		foreach [space offset] new-path [
			unless space =? old-path/1 [
				if event/type = 'time [					;@@ can't write event/offset, have to provide virtual event
					foreach word [type face window] [false-event/:word: event/:word]
					event: false-event
					event/offset: host-offset
				]
				events/with-stop [events/process-event new-path event [] no]
				break
			]
			old-path: skip old-path 2
		]
		append clear head old-path new-path				;-- stash the new path
	]
]
