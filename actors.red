Red [
	title:   "Actors support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		A defined actor does NOT by default stop the evaluation of standard event handler.
		This is so actors don't accidentally disable any internal functionality.
		When required though, they can use STOP, e.g. for stopping tabbing. 
	}
]


;; requires events


actors: context [

	supported-events: [
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		focus unfocus click							 	;-- internally generated
		time
	]
	
	actor-names: make map! map-each/eval name supported-events [	;-- used to avoid frequent allocations when adding "on-"
		[name to word! rejoin ["on-" name]]
	]

	;; previewer so it takes priority over event handlers and can stop them
	register-previewer supported-events function [
		space [object! none!] path [block!] event [map!] delay [percent! none!]
	][
		all [
			space
			actors: select space 'actors
			name:   select actor-names event/type
			actor:  select actors name
			actor space path event delay
		]
		; if event/type <> 'time [print [event/type mold path] ??~ space]
		; if event/type = 'key [print [event/type mold path] ??~ actors]
	]
	
];; actors
