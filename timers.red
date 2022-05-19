Red [
	title:   "Timers support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires events.red (extends them on load), uses traversal.red & rendering.red (paths-from-space)


context [
	;; to lighten the timer-inflicted CPU load (from 100% really), a registry of /rate-enabled spaces has to be kept
	;; it is achieved by injecting /rate-tracking code into space/on-change
	rated-spaces: make hash! 32
	
	#assert [object? :space-object!]
	#assert [empty? body-of :space-object!/on-change*]		;-- must be safe to override
	rate-types!: make typeset! [integer! float! time!]
	on-rate-change: function [space [object!] word [any-word!] old [any-type!] new [any-type!]][
		if 'rate = word [
			pos: find/same rated-spaces space
			either all [
				find rate-types! type? :new
				positive? rate: new
			][											;-- enable timers
				if number? rate [rate: 0:0:1 / rate]	;-- normalize rate in advance
				unless pos [repend rated-spaces [space rate]]
			][											;-- disable timers
				if pos [fast-remove pos 2]
			]
			rated-spaces
		]
	]
	
	space-object!/on-change*: function [word [any-word!] old [any-type!] new [any-type!]] with space-object! [
		on-rate-change self word :old :new
	]
	

	;-- static map of previous call times of each timer, but `map!` cannot hold objects as keys so using hash!
	marks: make hash! []
	timer-resolution: 0:0								;-- measured automatically
	timer-host: none									;-- a single host face that is used for resolution estimation

	events/on-time: function [face [object!] event [event!]] [
		#debug profile [prof/manual/start 'timers]
		either face =? timer-host [update-resolution][update-timer-host face]
		process-timers face event
		#debug profile [prof/manual/end 'timers]
	]

	update-timer-host: function [face [object!]] [		;-- automatically choose the host with maximum rate
		#assert [not face =? timer-host]
		#assert [face/rate]
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
		;-- timer has no target (as is the case with focused space or pointed at)
		;-- so we'll have to scan the whole tree for `rate` facets; all the time
		;-- so this code has to be blazing fast
		handlers: events/handlers
		hpath: as path! []
		foreach [space rate] rated-spaces [
			paths: paths-from-space space face			;-- static, not copied, but it's ok since timer is not reentrant
			foreach path paths [
				pos: find/same/tail marks space
				set [prev: bias:] any [pos [0:0 0:0]]
				delay: either pos [difference time prev + rate][0:0]		;-- estimate elapsed delay for this timer
				if delay < negate timer-resolution / 2 + bias [continue]	;-- too early to call it?
				
				args: reduce/into [to 1% delay / rate] clear []
				path: new-line/all as [] path no
				;; even if no time handler, actors or previewers/finalizers may be defined
				events/do-previewers top path event args
				forall path [
					compose/into [handlers (path) on-time] clear hpath		;-- not allocated
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

]