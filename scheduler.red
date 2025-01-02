Red [
	title:    "Custom event scheduler for Spaces"
	purpose:  "Provide platform-independent and optimal event processing"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.scheduler
	depends:  [default map-each]
	notes: {
		Scheduler is an attempt to work around https://github.com/red/red/issues/4881
		which freezes some tests (grid-test4-7) and slows down others on GTK.
		
		Another use of it is REP #161 which is used for 'over' events generation on moving spaces (see %hovering.red).
		
		On design...
		
		A more general writeup, including addressed pitfalls, can be found in REP #157.
		
		Generally there are 3 groups of events:
		- priority events - keys, clicks, change, focus and more
		  these cannot be skipped and usually require fast UI response
		- groupable events - over, wheel, moving, resizing, zoom, pan, rotate, drawing
		  these can be skipped if there's another similar event pending but no other events inbetween except 'time
		  because the order of input is of importance and we can't mix it
		  wheel is a bit different: as it reports relative change, this change must be summed when grouping
		  (possibly also touch gestures - not sure as they aren't implemented in View)
		  these require less fast UI response
		- time event - unordered with the other events, so can always be skipped if another time event is pending
		  since in Spaces it's the heaviest event that renders everything, it can also be delayed the most
		
		In Spaces some of these e.g. moving, resizing, change are unused (not applicable to base face).
		'drawing is also not reported to the base at the moment, but even if it was, Spaces do not handle it.
		The remaining events - input and time - are prioritized using "delay norms" that are big for 'time and small for input.
		An event is only skipped (grouped) in two cases:
		- no other events inbetween 
		- the event inbetween (of different type) has lesser delay to norm value
		Since effectively we have only 'time and 'input groups,
		it's always just a choice whether to delay the timer or input event or fire it now.
		Delay is measured since time last event of the same type finished processing,
		so the bigger the delay gets the more likely this event will be scheduled again,
		and on the other hand, if similar event just finished it is likely to get skipped.
		So it leads to a fair distribution of events across timeline, removing deadlocks.
		
		Since the OS loves to reorder events not in our favor (hence this scheduler is made),
		we have to fetch native events as early as possible and put them into the queue,
		but not process immediately, as otherwise no queue will ever be filled.
		Since there's no other "wake up" call for our program than events though,
		the only place where processing can happen is in the same place the event is fetched.
		Then the only way to build a queue is to (slightly) delay the processing,
		and process events more aggressively the more this delay grows.
		 
		This is complicated somewhat on Windows by the way it processes events:
		- when window is resized, `do-events/no-wait` will not return,
		  but the following events will still be processed: time, resize, resizing, drawing
		- when system menu is open, only time event will be processed
		So to avoid UI freezes on Windows I need to do internal event processing from inside the 'time' handler.
		
		Using only 'time' for internal event processing may be easy, but may introduce a delay that's unnecessary.
		Hence the best course of action is to have entry points from 'time' and all other events, 
		but decide based on accumulated delay how much to process right away.
	}
]


scheduler: context [

	;; --------------------------------
	;; --- getting events from View ---
	;; --------------------------------
	
	;; types not listed here are ignored by the scheduler and are not used in Spaces
	;; this only applies to real (not synthesized) event types; synthesized events aren't filtered
	accepted-events: make hash! [
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		; focus unfocus 	-- internally generated ;@@ but maybe these will be required too
		time
		#(true)													;-- 'true' to be able to use path notation (faster)
	]
	
	;; optimization note: common use case is having one host face so most of the events will go into it
	;; it makes sense then to first filter out by the type, then check for the host
	;@@ sometimes this gets window as 'host', likely when no face is in focus
	insert-event-func 'spaces-scheduler function [face event] [
		all [
			accepted-events/(event/type)
			host? face
			filter-event event: internalize-event event			;-- filters may return 'none' to drop the event
			queue-event event									;-- add event to the queue 
			switch event/type [time [maybe-process-events]]		;-- process first available event if delay is enough
			none
		]
	]
	
	internalize-event: function [
		"Convert a native OS event into one used by Spaces"
		event   [event!]
		return: [map!]
	][
		map: make map! 22										;-- 15 from event! + id done? direction lookup path hittest recorded
		foreach word event-words [map/:word: event/:word]
		map/recorded: now/utc/precise							;-- remember the time event was discovered, for queue management
		map
	]


	;; -------------------------
	;; --- events processing ---
	;; -------------------------
	
	;; minimum event processing delay (helps build the queue)
	min-delay: 0:0:0.001 * 5
	
	maybe-process-events: function ["Process up to a few queued events"] [
		unless all [
			next-event: event-queue/2
			min-delay <= delay: difference time: now/utc/precise next-event/recorded
		] [exit]
		
		quota: min
			1 + to integer! log-2 delay / min-delay				;-- slowly increase processing quota as delay accumulates
			half length? event-queue
		loop quota [any [
			group-next-event
			process-next-event
		]]
	]
	
	event-types: extract system/view/evt-names 2
	event-words: system/catalog/accessors/event!
	event-proto: to map! map-each/eval w event-words [[w none]]	;-- used in event synthesis

	process-next-event: function ["Remove and dispatch next event in the queue"] [
		event: take-next-event
		#assert [event]
		self/queue-point: event-queue							;-- put synthesized events after the currently processed one
		events/processing/dispatch event						;-- this can be reentrant, though I'm trying to keep it from being so
		finish-times/(event/type): now/utc/precise
	]
	
	synthesize-event: function [
		"Synthesize a new event from the provided SPEC"
		spec [block!] "Used to initialize the event (composed)"
	][
		queue-event/next extend extend copy event-proto tracked-state compose/only spec
	]
	
	
	;; -------------------------------
	;; --- events queue management ---
	;; -------------------------------
	
	queue-point: event-queue: make hash! 1024
	
	;; queueing fills up a group right next to the currently processed event
	;; so that queued events are processed in FIFO order, but also follow the current event immediately
	queue-event: function [
		"Add an event to the end of processing queue"
		event [map!]
		/next "Add it right next to the current event (for synthesized events)"
		/extern queue-point
	][
		id: make-grouping-id event
		either next
			[queue-point: insert queue-point reduce [id event]]
			[append append event-queue id event]
	]
	
	take-next-event: function [
		"Remove next event from the queue and return it"
		/extern event-queue queue-point
	][
		also event: event-queue/2
		if 1024 < index? event-queue: skip event-queue 2 [
			queue-point: skip queue-point -1024
			event-queue: skip event-queue -1024
			remove/part event-queue 1024
		]
	]
	
	
	;; -----------------------
	;; --- events grouping ---
	;; -----------------------
	
	groupable: make hash! [time over drag wheel #(true)]		;-- 'true' allows to use path notation which is faster than find
	delay-norms: #[												;-- delay norm per event type, used for prioritization
		time     500
		over     100
		drag     100
		wheel    100
	]
	for-each type event-types [default delay-norms/:type: 50]
	
	finish-times: #[]											;-- timestamp of last event of each type processing finish(!)
	for-each type event-types [finish-times/:type: now/utc/precise]
	
	;; event groups determine which events can or cannot be grouped with each other
	;; currently there are only two groups: time events and input events
	;; since host id is an integer, and I need to unify it with the group, it's convenient to make the group id a fraction
	groups: make map! map-each/eval type event-types [[type 0.0]]
	groups/time: 0.1

	make-grouping-id: function [
		"Make a grouping id out of event group and host"
		event [map!]
	][
		event/face/id + groups/(event/type)
	]
	
	grouping-limit: 100											;-- slots (double the events count) to look ahead for possible grouping
	
	group-next-event: function [
		"Group and skip next event in the queue if possible"
		return: [map! none!] "Taken event if grouping succeeded; none otherwise"
	][
		this: event-queue/2
		#assert [this]
		unless all [
			groupable/(this/type)								;-- a groupable event
			other: select/part next event-queue event-queue/1 grouping-limit	;-- have one of the same group ahead
			this/type  = other/type								;-- type and away flag are the same
			this/away? = other/away?
		] [return none]
		
		;; check if grouping would lead to a more delayed event, otherwise abort
		unless other =? event-queue/4 [							;-- only a concern if skipping another event
			norm1:  delay-norms/(this/type)
			norm2:  delay-norms/(other/type)
			t-now:  now/utc/precise								;@@ consider reading time only once
			delay1: difference t-now finish-times/(this/type)
			delay2: difference t-now finish-times/(other/type)
			if (delay1 / norm1) > (delay2 / norm2) [return none]
		]		
		
		;; perform grouping for the only event that requires summation; others are just skipped
		if this/type = 'wheel [other/picked: other/picked + this/picked]
		
		take-next-event
	]
	

	;; ------------------------
	;; --- events filtering ---
	;; ------------------------
	
	;; similar to system/view/handlers but only for host events
	;; goal is to have predictable event order (e.g. hovering may call new 'over event immediately before 'time)
	;; if function throws a 'drop word, event is skipped, otherwise it may modify the event in place
	;; format is like a map: [name func] but with explicit order
	event-filters: make hash! 20

	filter-event: function [
		"Drag EVENT through the chain of filters"
		event   [map!]
		return: [map! none!] "Event (may be modified) or none to cancel processing"
	][
		catch [													;@@ should be fcatch, but it would be slower :/
			foreach [name filter] event-filters [filter event]
			return event
		]
		none													;-- event should be dropped
	]


	;; ----------------------------------------
	;; --- events info tracking and healing ---
	;; ----------------------------------------
	
	;; most of this below is a workaround for issue #5520 & REP #161
	;; but another use is to fill info into synthesized events

	;; pointer & key events correctly carry all the flags, so they can be used as source of info
	tracked-events: make hash! [
		over wheel down up click dbl-click 
		alt-down alt-up mid-down mid-up aux-down aux-up
		key-down key key-up
		#(true)
	]

	;; Optimization note: I can either 'extend' native events into 'tracked-state'
	;;  and then copy a set of fields one by one into the healed 'time' event
	;;  or copy from native events one by one, then 'extend' into the 'time' event
	;; At the moment, among source events, only 'over' is populous sometimes
	;;  so it makes more sense to optimize the 'time' event instead, which is constantly running
	tracked-state: #[											;@@ remove this if REP #161 gets implemented
		flags:     []
		offset:    (0,0)										;-- screen offset!
		ctrl?:     #(false)
		shift?:    #(false)
		down?:     #(false)
		mid-down?: #(false)
		alt-down?: #(false)
	]
	tracked-keys: exclude keys-of tracked-state [offset]
	
	track-event: function [
		"Used to keep track of keyboard flags and pointer offset"
		event [map!]
	][
		if tracked-events/(event/type) [
			#assert [event/offset]
			foreach key tracked-keys [tracked-state/:key: event/:key]
			tracked-state/offset: face-to-screen event/offset event/face
		]
	]
	
	heal-event: function [										;@@ need to gather extensive data on which events needs healing
		"Used to propagate keyboard flags and pointer offset into the time event"
		event [map!]
	][
		switch event/type [
			time [
				extend event tracked-state						;-- timer carries no own state
				event/offset: screen-to-face event/offset event/face
			]
		]
	]
	
	;; order is important here:
	;@@ I could also have made tracker a global handler, but I see no practical significance in that atm
	put event-filters 'flags-tracker :track-event
	put event-filters 'event-healer  :heal-event
]


