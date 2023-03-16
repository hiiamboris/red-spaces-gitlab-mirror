Red [
	title:   "Focus model for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;; provides focusing by clicking
;; requires: export and window-of

exports: [focused? focus-space]

;@@ `focus` itself should be somewhere else, as it is used by dispatch and who knows what
focus: make classy-object! declare-class 'focus-context [
	;; template names that can receive focus (affects tabbing & clicking)
	;; class should not matter, name should - then we'll be able to override/extend classes
	;@@ TODO: should paths be allowed here? e.g. if some spaces are only focusable in some bigger context?
	focusable: make hash! [scrollable button field area list-view grid-view]	#type [hash!]
	
	;; each window has own focus history, format: [window [space ...] ...]
	histories: make hash! 8			#type [hash!]
	window:    none					#type [none! object!]		;-- set by on-focus global hook

	;; currently focused space in currently focused window!
	current: does [last history]	#type [function!]	;-- returns space, host face, or none
	history: has [w h] [								;-- previously focused spaces, including current one
		any [
			select/same histories window
			last repend
				self/histories: sift histories [w h .. w/state]		;-- forget closed windows
				[window make [] 11]
		]
	] #type [function!]
	;@@ DOC: history is used when focused face is no longer there

	;; path is valid if it's visible still
	;; for faces this means 'state' is not none and 'visible?' is true
	;; spaces validity is checked by get-full-path itself
	last-valid-focus: function [] [
		for-each/reverse space history [
			all [
				path: get-full-path space
				host: first path
				host/state
				host/visible?
				result: path
				break
			]
		]
		result
	]
	
	;@@ TODO: do not enter hidden tab panel's pane (or any other hidden item?)
	find-next-focal-space: function [dir "forth or back"] [
		focused: any [last-valid-focus reduce [system/view/screens/1]]
		#debug focus [#print "last valid focus: (mold as path! focused)"]
		loop: pick [									;@@ use apply
			foreach-*ace/next
			foreach-*ace/next/reverse
		] dir = 'forth 
		do compose/only [
			(loop) path found: focused [				;-- default to already focused item (e.g. it's the only focusable)
				#debug focus [
					space: last path 
					text: mold any [select space 'text  select space 'data] 
					#print "find-next-focal-space @(mold path), text=(text)"
				]
				if find focus/focusable select last path 'type [found: path break]
			]
		]
		last found
	]

]


;; for use within styles
focused?: function [
	"Check if current style is the one in focus"
	/above n "Rather check if space N levels above is the one in focus"
	/parent  "Shortcut for /above 1"
][
	n: 1 + any [n if parent [1] 0]
	to logic! all [
		space1: focus/current
		space2: pick tail current-path negate n
		space1 =? space2
	]
]


;; since I can't create events, but still gotta tell previewers/finalizers what kind of event it is, have to work around
focus-event!:   object [type: 'focus   face: none]
unfocus-event!: object [type: 'unfocus face: none]

;@@ should this refocus windows?
focus-space: function [
	"Focus given space object in it's window (does not refocus windows)"
	space [object!] (space? space)
] with events [
	if any [
		space =? old: focus/current						;-- no refocusing into the same target
		not find focus/focusable space/type				;-- this space cannot be focused
	] [return no]
	#debug focus [#print "Moving focus from (mold/only reduce [old]) to (mold/only reduce [space])"]
	
	if all [
		old
		old-path: get-full-path old
		old-face: old-path/1
		old-face/state
	][
		invalidate old									;-- let space remove it's focus decoration
		with-stop [										;-- init a separate stop flag for a separate event
			unfocus-event!/face: old-face 
			process-event as [] old-path unfocus-event! [] yes
		]
	]	
	
	if all [
		path: get-full-path space
		face: path/1
		face/state
	][
		set-focus face
		unless system/view/auto-sync? [show window-of face]		;-- otherwise keys won't be detected
	]
		
	append hist: focus/history space
	remove/part hist skip tail hist -10					;-- limit history length
	invalidate space									;-- let space paint it's focus decoration

	if face [											;-- event needs path, which is unavailable if space is orphaned or not drawn yet
		with-stop [										;-- init a separate stop flag for a separate event
			focus-event!/face: face
			process-event as [] path focus-event! [] yes
		]
	]
	yes
]

;@@ set-focus inside the same window won't affect focus/current
;@@ I could track host switch here too, but what space to focus in this case?
insert-event-func function [face event] [
	if event/type == 'focus [focus/window: event/window]
	none
]

register-previewer
	[down mid-down alt-down aux-down dbl-click]			;-- button clicks may change focus
	function [space [object!] path [block!] event [event! object!]] [
		#debug focus [#print "Attempting to focus (mold as path! keep-type head path object!)"]
		focus-space space
	]


export exports
