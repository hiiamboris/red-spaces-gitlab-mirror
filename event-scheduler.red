Red [
	title:   "Custom event scheduler for Spaces"
	purpose: "Provide platform-independent and optimal event processing"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Scheduler is an attempt to work around https://github.com/red/red/issues/4881
		which freezes some tests (grid-test4-7) and slows down others on GTK.
		
		This implementation is currently replacing do-events, because it needs to
		gather all pending events and then start processing right away.
		There's no other way I know of of triggering any code "right away" after the last event.
		
		However due to weird behavior of Windows backend, single do-events/no-wait may lock the evaluation.
		Happens on menu activation and on resizing. And all events just keep getting queued.
		
		I have yet found no easy workaround for this problem, because
		the only code that runs in this situation is event functions and actors.
		And they have no knowledge of pending events, nor any way to know if lockup happened.
		So I can imagine no logic (other than relying on delay anomalies) that would let me to
		temporarily switch events processing from do-events into the event function.
		
		On design...
		
		Generally there are 3 groups of events:
		- priority events - keys, clicks, change, focus and more
		  these cannot be skipped and usually require fast UI response
		- groupable events - over, wheel, moving, resizing, drawing
		  these can be skipped if there's another similar event pending but no other events inbetween except 'time
		  because the order of input is of importance and we can't mix it
		  wheel is a bit different: as it reports relative change, this change must be summed when grouping
		  these require less fast UI response
		- time event - unordered with the other events, so can always be skipped if another time event is pending
		  since in Spaces it's the heaviest event that renders everything, it can also be most delayed
		
		In Spaces some of these e.g. moving, resizing, change are unused (not applicable to base face).
		'drawing is also not reported to the base at the moment, but even if it was, Spaces do not handle it.
		The remaining events - input and time - are prioritized using "delay norms" that are big for 'time and small for input.
		An event is only skipped (grouped) in two cases:
		- no other events inbetween 
		- the event inbetween (of different type) has lesser delay to norm value
		Since effectively we have only 'time and 'input groups, it's always just a choice whether to delay the timer or fire it.
		Delay is measured since time last event of the same type finished processing,
		so the bigger the delay gets the more likely this event will be scheduled again,
		and on the other hand, if similar event just finished it is likely to get skipped.
		So it leads to a fair distribution of events across timeline, removing deadlocks.
	}
]

;; requires do-queued-events.red
;; uses events/dispatch and events/copy-event


scheduler: context [
	event-types: extract system/view/evt-names 2

	accepted-events: make hash! [						;-- real (not generated) View events that need processing
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		; focus unfocus 	-- internally generated ;@@ but maybe these will be required too
		time
		#[true]											;-- used to be able to use path notation (faster)
	]
	
	delay-norms: #(										;-- delay norm per event type, used for prioritization
		time     500
		; drawing  300									;-- not reported to the event function
		; moving   200									;-- only concerns windows not hosts
		; move     200									;-- same
		; resizing 200									;-- same
		; resize   200									;-- same
		over     100
		drag     100
		wheel    100
	)
	default-delay: 50
	for-each type event-types [default delay-norms/:type: default-delay]
	
	groupable: make hash! append keys-of delay-norms true		;-- 'true' allows to use path notation which is faster than find

	;; event groups determine which events can or cannot be grouped with each other
	groups: #(
		time     time
		drawing  drawing
	)
	for-each type exclude event-types [time drawing] [groups/:type: 'normal]

	finish-times: #()									;-- timestamp of last event of each type processing finish(!)
	for-each type event-types [finish-times/:type: now/utc/precise]
	
	shared-queue: make [] 200							;-- for dispatching events by host

	insert-event: group-next-event: take-next-event: process-next-event: process-any-event: none
	context [
		igroup: 1 ievent: 2 period: 2
		limit: 50										;-- search distance limit
		
		set 'insert-event function [host [object!] event [map!]] [
			#assert [host =? event/face]
			insert next shared-queue host
			insert skip host/queue period reduce [		;-- inserted after the current event
				groups/(event/type) event
			] 
		] 
		
		set 'remove-next-event function [host [object!]] [
			quietly host/queue: skip host/queue period
			if 100 < index? host/queue [
				; remove/part host/queue quietly host/queue: head host/queue
				remove/part head host/queue host/queue
				quietly host/queue: head host/queue
			]
		]
	
		set 'process-next-event function [host [object!]] [
			unless group-next-event host [
				events/dispatch host host/queue/:ievent
				finish-times/(host/queue/:ievent/type): now/utc/precise	;-- mark the end of processing of this event type
				remove-next-event host
			]
		]
		
		set 'process-any-event function [/extern shared-queue] [	;-- must return true if processes
			unless host: shared-queue/1 [return no]
			#assert [
				not empty? host/queue		"shared and host queues are out of sync"
				1000 > length? host/queue	"event queue buildup detected"
			]
			process-next-event host
			shared-queue: next shared-queue
			if 100 < index? shared-queue [
				; remove/part shared-queue shared-queue: head shared-queue
				remove/part head shared-queue shared-queue
				shared-queue: head shared-queue
			]
			true
		]

		set 'group-next-event function [host [object!]] [
			unless attempt [window-of host] [					;-- ignore out-of-tree events (host or window has been destroyed?)
				remove-next-event host
				return true
			]
			;; find grouping candidate
			rest: skip this: host/queue period
			type: this/:ievent/type
			unless all [
				groupable/:type											;-- this event type cannot be grouped
				ahead: find/skip/part rest this/:igroup period limit	;-- no similar event ahead
				type = ahead/:ievent/type								;-- similar event of different type blocks grouping
			] [return none]
			
			;; check if grouping would lead us to a more delayed event, otherwise abort
			if period <> offset? this rest [					;-- only if skipping another event
				this-delay: difference t-now: now/utc/precise finish-times/:type
				this-norm:  delay-norms/:type
				next-type:  rest/:ievent/type
				next-delay: difference t-now finish-times/:next-type
				next-norm:  delay-norms/:next-type
				if greater? this-delay / this-norm next-delay / next-norm [return none]	;-- abort if this event is more delayed
			]
			
			;; perform grouping
			if type = 'wheel [									;-- the only event that requires summation
				ahead/:ievent/picked: ahead/:ievent/picked + this/:ievent/picked
			]
			remove-next-event host
			true												;-- report success
		]
	
	]

	;; sometimes this gets window as 'host', likely when no face is in focus
	insert-event-func func [host event] [
		all [
			host? host									;@@ maybe /content field not /space?
			host/space									;-- /space is assigned?
			accepted-events/(event/type)
			append shared-queue host
			append append host/queue
				groups/(event/type)
				events/copy-event event
			none										;-- the event can be processed by other handlers
		]
	]

	#assert [1291100108 = checksum mold body-of :do-events 'crc32  "Warning: do-events was likely modified"]
	
	set 'do-events func spec-of native-do-events: :do-events [
		either no-wait [
			native-do-events/no-wait
		][
			forever [
				switch native-do-events/no-wait [		;-- fetch all pending events ;@@ may deadlock?
					#[true]  [continue]
					#[false] []
					#[none]  [break]
				]
				unless process-any-event [wait 1e-3]	;-- wait is also tainted by single do-events/no-wait
			]
		]
	]
	
	set 'view func spec-of :view body-of :view			;-- uses compiled `do-events` so need to recreate it
]
