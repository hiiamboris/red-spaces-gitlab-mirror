Red [
	title:   "Actors support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
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
		space [object! none!] path [block!] event [event! object!] delay [percent! none!]
	][
		; print [event/type mold path]
		all [
			space
			actors: select space 'actors
			name:   select actor-names event/type
			actor:  select actors name
			actor space path event delay
		]
	]
	
];; actors
