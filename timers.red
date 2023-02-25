Red [
	title:   "Timers support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;; requires events.red (extends them on load), uses traversal.red & rendering.red (get-full-path)


timers: context [
	;; to lighten the timer-inflicted CPU load (from 100% really), a registry of /rate-enabled spaces has to be kept
	;; it is achieved by injecting /rate-tracking code into space/on-change
	rated-spaces: make hash! 32

	prime: function [space [object!]] [
		unless find/same rated-spaces space [
			append rated-spaces space
			#debug timer [
				code: mold/part body-of :space/actors/on-time 60
				#print "primed timer for (space/type):(space/size) code: (code), total active (length? rated-spaces)"
			]
		]
	]
	
	;@@ find a way someday to make timers an optional module
	; modify-class 'space-object! [
		; #type =? [none! integer! float! time!] :on-rate-change
		; (any [none? rate zero? rate positive? rate])
		; rate: none
	; ]	
	
	;-- static map of previous call times of each timer, but `map!` cannot hold objects as keys so using hash!
	marks: make hash! []
	timer-resolution: 0:0								;-- measured automatically
	timer-host: none									;-- a single host face that is used for resolution estimation

	events/on-time: function [face [object!] event [event!]] [	;-- events reserve this slot
		#debug profile [prof/manual/start 'timers]
		either face =? timer-host [update-resolution][update-timer-host face]
		process-timers face event
		#debug profile [prof/manual/end 'timers]
	]

	;; automatically chooses the host with maximum rate
	update-timer-host: function [face [object!] (all [face/rate  not face =? timer-host])] [
		unless number? rate: face/rate [rate: 0:0:1 / rate]
		if all [
			timer-host
			timer-host/state
			rate-old: timer-host/rate
		][
			unless number? rate-old [rate-old: 0:0:1 / rate-old]
			if rate <= rate-old [exit]
		]
		#debug [print ["switching timer host to" mold/flat/part face 100]]
		set 'timer-host face
		update-resolution
	]

	;-- resolution estimation with period = O(100) timer events
	last-mark: 1900/1/1
	update-resolution: function [/extern timer-resolution last-mark time] [
		if 0:0:1 > elapsed: difference time: now/utc/precise last-mark [	;-- discard glitches like PC went to sleep etc.
			timer-resolution: timer-resolution * 0.999 + (0.001 * elapsed)
		]
		last-mark: time
	]
	
	time: none											;-- cached to all `now` less often

	process-timers: function [face [object!] event [event!] /extern time] [
		;; timer has no target (as is the case with focused space or pointed at)
		;; and scanning of the whole tree for `rate` facets, all the time, is out of question - or this code will take 99% CPU time
		;; to win performance I maintain a list of all 'armed' timers at the cost of having to explicitly render each timer
		handlers: events/handlers
		hpath: as path! []
		foreach space rated-spaces [
			unless all [
				rate: select space 'rate				;-- previously enabled timer has been disabled? don't react on it again
				path: get-full-path space				;-- space is orphaned (no longer connected to the tree)? remove it so GC can take it
			][
				#debug timer [#print "disabling timer for (mold space)"]
				fast-remove find/same rated-spaces space 1		;-- won't be active until it gets rendered again
				continue
			]
			#debug timer [#print "timer rate (rate) has path (mold path)"]
			if number? rate [rate: 0:0:1 / rate]
			pos: find/same/tail marks space
			set [prev: bias:] any [pos [0:0 0:0]]
			delay: either pos [difference time prev + rate][0:0]		;-- estimate elapsed delay for this timer
			if delay < negate timer-resolution / 2 + bias [continue]	;-- too early to call it?
			
			args: reduce/into [to 1% delay / rate] clear []
			wpath: copy path: new-line/all as [] path no				;@@ need new-line here?
			forall wpath [wpath/1: wpath/1/type]						;@@ use map-each
			;; even if no time handler, actors or previewers/finalizers may be defined
			events/do-previewers top path event args
			forall wpath [
				compose/into [handlers (wpath) on-time] clear hpath		;-- not allocated
				unless block? try [list: get hpath] [continue]			;-- no time handler ;@@ REP #113
				foreach handler list [									;-- call the on-time stack
					#assert [function? :handler]
					events/do-handler next hpath :handler top path event args 
				]
			]
			events/do-finalizers top path event args
			
			unless pos [pos: tail append marks space]
			delay: min delay rate * 5					;-- avoid frame spikes after a lag or sleep
			change change pos time bias + delay			;-- mark last timer call time for this space
			;@@ TODO: cap bias at some maximum, for 50+ fps cases, so it won't run away
			
			time: now/utc/precise						;-- update time after handlers evaluation
		]
	]

]
