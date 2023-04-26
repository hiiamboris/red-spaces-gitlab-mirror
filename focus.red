Red [
	title:   "Focus model for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;; provides focusing by clicking
;; requires: export and window-of, tabbing context from common
#assert [object? tabbing]

exports: [focused? focus-space set-focus]

;@@ `focus` itself should be somewhere else, as it is used by dispatch and who knows what
focus: make classy-object! declare-class 'focus-context [
	;; template names that can receive focus (affects tabbing & clicking)
	;; class should not matter, name should - then we'll be able to override/extend classes
	;@@ TODO: should paths be allowed here? e.g. if some spaces are only focusable in some bigger context?
	focusable: make hash! [scrollable button field area list-view grid-view]	#type [hash!]
	focusable-faces: tabbing/focusables
	
	;; each window has own focus history, format: [window [space ...] ...]
	histories: make hash! 8			#type [hash!]
	window:    none					#type [none! object!]		;-- set by first history access and by global event hook

	;; currently focused space in currently focused window!
	;@@ this should be even more sophisticated to support per-tab, per-page focus
	current: does [last history]	#type [function!]	;-- returns space, face, or none
	history: has [w h hist] [							;-- previously focused spaces, including current one
		unless window [self/window: last head system/view/screens/1/pane]
		unless hist: select/same histories window [
			unless window [ERROR "focus/window must be set before using focus/history"]
			#debug focus [#print "current window detected as: (mold/flat window)"]
			self/histories: sift histories [w h .. w/state]		;-- forget closed windows
			repend histories [window hist: make [] 11]
		]
		hist
	] #type [function!]
	;@@ DOC: history is used when focused face is no longer there
	
	add-to-history: function [space [object!]] [
		#debug focus [#print "adding (space/type):(space/size) to focus history"]
		default self/window: window-of space
		append hist: history space
		remove/part hist hist << 10						;-- limit history length
	]
	
	deeply-visible?: function [path [block! path!]] [	;@@ where's the right place for this func?
		foreach face path [
			unless is-face? face [break]
			unless all [face/state face/visible?] [return no]
		]
		yes
	]

	;; path is valid if it's visible still
	;; for faces this means 'state' is not none and 'visible?' is true
	;; spaces validity is checked by get-screen-path itself
	last-valid-focus: function [] [
		for-each/reverse space history [
			all [
				path: get-screen-path space
				deeply-visible? path 
				result: path
				break
			]
		]
		result
	]
		
	send-unfocus: function ["Remove focus from the space" space [object! (any [space? space  is-face? space]) none!]] [
		#debug focus [#print "unfocusing (if space [space/type]):(if space [space/size])"]
		unless space? space [exit]						;-- for faces or none - no action needed
		if all [
			path: get-host-path space
			deeply-visible? path
		][
			invalidate space							;-- let space remove its focus decoration
			events/with-stop [							;-- init a separate stop flag for a separate event
				unfocus-event!/face: path/1
				events/process-event as [] path unfocus-event! [] yes
			]
		]
	]	
	
	send-focus: function ["Put focus on the space" space [object!] (space? space)] [
		if all [
			path: get-host-path space
			deeply-visible? path
		][
			#assert [is-face? path/1]					;-- or set-focus will deadlock by calling this again
			invalidate space							;-- let space paint its focus decoration
			native-set-focus face: path/1
			events/with-stop [							;-- init a separate stop flag for a separate event
				focus-event!/face: face
				events/process-event as [] path focus-event! [] yes
			]
			unless system/view/auto-sync? [show window-of face]	;-- otherwise keys won't be detected
		]
	]
	
	;@@ TODO: do not enter hidden tab panel's pane (or any other hidden item?)
	find-next-focal-*ace: function [dir "forth or back"] [
		focused: any [last-valid-focus compose [(system/view/screens/1) (only window)]]		;-- screen-relative path
		#debug focus [#print "last valid focus path: (mold as path! focused)"]
		loop: pick [									;@@ use apply
			foreach-*ace/next
			foreach-*ace/next/reverse
		] dir = 'forth 
		do compose/only [
			(loop) path found: focused [				;-- default to already focused item (e.g. it's the only focusable)
				#debug focus [
					space: last path 
					text: mold/flat/part any [select space 'text  select space 'data] 40 
					#print "find-next-focal-*ace @(mold path), text=(text)"
				]
				accepted: either space? obj: last path [focusable][focusable-faces]
				all [
					find accepted obj/type
					deeply-visible? path
					found: path
					break
				]
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
][
	unless find focus/focusable space/type [return no]	;-- this space cannot be focused
	if space =? old: focus/current [					;-- no refocusing into the same target, but need to ensure host is focused
		native-set-focus first get-host-path space
		return no
	]
	#debug focus [#print "moving focus from (mold/only reduce [old]) to (mold/only reduce [space])"]
	
	focus/send-unfocus old
	focus/send-focus space
	focus/add-to-history space
	#assert [space =? focus/current]
	yes
]

;; overrides (extends) the native function
native-set-focus: :system/words/set-focus
set-focus: function ["Focus face or space object" face [object!]] reshape [
	either space? face [
		focus-space face
	][
		focus/send-unfocus focus/current
		unless find [screen window] face/type [			;-- native set-focus errors out on these
			focus/add-to-history face
			@(body-of :native-set-focus)
		]
	]
]

context [
	;@@ due to #3728 focus/unfocus is unreliable as most faces do not report these events on clicks
	;@@ so a partial workaround is to manually test window/selected every time focus may have changed
	;@@ but it's not working when controls are in a panel - see #3808
	;@@ native buttons also silently steal focus on clicks, without affecting window/selected, so they break this
	
	make-event-filter: function [events [block!]] [
		excluded: exclude extract to [] system/view/evt-names 2 events
		make map! map-each/eval type excluded [[type [return none]]]
	]
	
	filter: make-event-filter [down alt-down mid-down aux-down dbl-click focus unfocus]
	
	insert-event-func focus-checker: function [face event] [
		do filter/(event/type)
		new-focal-face: event/window/selected
		old-focal-face: all [
			focus/current
			path: get-screen-path focus/current
			path: locate/back path [obj .. is-face? obj]
			first path
		]
		unless new-focal-face =? old-focal-face [
			focus/send-unfocus focus/current
			if all [object? new-focal-face  not host? new-focal-face] [
				focus/add-to-history new-focal-face
			]
		]
		none
	]
	;@@ this filtered structure of event funcs should be used for all other cases, to reduce event system load
]

register-previewer
	[down mid-down alt-down aux-down dbl-click]			;-- button clicks on host may change focus
	function [space [object!] path [block!] event [event! object!]] [
		;@@ perhaps buttons should not accept focus when clicked? only when tabbed?
		#debug focus [#print "attempting to focus (space-id space)"]
		focus-space space
	]


export exports
