Red [
	title:   "Timers support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires events.red (extends them on load), uses traversal.red

context [
	;-- static map of previous call times of each timer, but `map!` cannot hold objects as keys so using hash!
	marks: make hash! []
	timer-resolution: 0:0								;-- measured automatically
	timer-host: none									;-- a single host face that is used for resolution estimation

	events/on-time: function [face [object!] event [event!]] [
		#debug profile [prof/manual/start 'timers]
		update-timer-host face
		if face =? timer-host [update-resolution]
		process-timers face event
		#debug profile [prof/manual/end 'timers]
	]

	update-timer-host: function [face [object!]] [		;-- automatically choose the host with maximum rate
		if face =? timer-host [exit]
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
	]

	;-- resolution estimation with period = O(100) timer events
	update-resolution: function [/extern timer-resolution] [
		last-mark: [1900/1/1]
		elapsed: difference t: now/utc/precise last-mark/1		;-- /utc is 2x faster
		last-mark/1: t
		if elapsed < 0:0:1 [							;-- discard glitches like PC went to sleep etc.
			timer-resolution: timer-resolution * 0.99 + (0.01 * elapsed)
		]
	]

	;@@ a bit of an inconsistency: previewers & finalizers are called for all events even in absence of handlers
	;@@ however for timers they are called only when timers are present..
	;@@ but should we call them all every time for every damn space? or forbid them for timer events totally?
	process-timers: function [face [object!] event [event!]] [
		;-- timer has no target (as is the case with focused space or pointed at)
		;-- so we'll have to scan the whole tree for `rate` facets; all the time
		;-- so this code has to be blazing fast
		handlers: events/handlers
		foreach-space [path space] face/space [
			unless rate: select space 'rate [continue]					;-- no rate facet
			if rate <= 0 [continue]										;-- disabled
			path: as [] path
			forall path [
				hpath: as path! compose/into [handlers (path) on-time] clear []	;-- not allocated
				list: any [attempt [get hpath] []]						;@@ REP #113
				;; even if no time handler, actors or previewers/finalizers may be defined, so have to continue
				; if empty? list: attempt [get hpath] [continue]					;-- no time handler
				#assert [
					block? list
					any [time? rate  float? rate  integer? rate]
				]
				if number? rate [rate: 0:0:1 / rate]					;-- turn rate into period
				pos: find/same/tail marks space
				set [prev: bias:] any [pos [0:0 0:0]]
				time: now/utc/precise									;-- /utc is 2x faster
				delay: either pos [difference time prev + rate][0:0]
				if delay < negate timer-resolution / 2 + bias [continue]	;-- too early to call this timer?
				path: back tail new-line/all path no					;-- position it at the target space (for handlers)
				args: reduce/into [to 1% delay / rate] clear []
				events/do-previewers path event args
				foreach handler list [									;-- call the on-time stack
					#assert [function? :handler]
					events/do-handler next hpath :handler path event args 
				]
				events/do-finalizers path event args
				unless pos [pos: insert tail marks space]
				delay: min delay rate * 5								;-- avoid frame spikes after a lag or sleep
				change change pos time bias + delay
				;@@ TODO: cap bias at some maximum, for 50+ fps cases, so it won't run away
			]
		]
	]

]