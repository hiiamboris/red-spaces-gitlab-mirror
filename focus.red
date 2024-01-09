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
	;@@ rework this for compatibility with latest View tabbing model
	focusable: make hash! [scrollable button field area list-view grid-view slider]	#type [hash!]
	focusable-faces: make hash! [field area button toggle check radio slider text-list drop-list drop-down calendar tab-panel]
	
	;; each window has own focus history, format: [window [space ...] ...]
	histories: make hash! 8			#type    [hash!]
	window:    none					#type =? [none! object!]	;-- set by first history access and by global event hook

	;; currently focused space in currently focused window!
	;@@ it's currently not possible to tell what is focused becase Red doesn't tell us which window is active - #3808
	;@@ so this is not very reliable right now and requires a lot of kludges...
	;@@ TODO: /current should be able to return window object (after unfocus - to avoid duplicate unfocus), while /history should not contain it
	current: does [last history]	#type    [function!]		;-- returns space, face, or none
	
	;; the point of /history is to recover focus when last focused space gets hidden/removed from frame/whole window disappears, and Tab is hit
	;@@ TODO: to support per-tab, per-page focus history they may have their own histories, or maybe /focus should handle scope too?
	history: has [w h hist] [									;-- previously focused spaces, including current one
		unless window [self/window: last head system/view/screens/1/pane]
		unless hist: select/same histories window [
			unless window [ERROR "focus/window must be set before using focus/history"]
			#debug focus [#print "current window detected as: (select window 'type):(select window 'size) (mold select window 'text)"]
			self/histories: sift histories [w h .. w/state]		;-- forget closed windows
			repend histories [window hist: make [] 11]
		]
		hist
	] #type [function!]
	;@@ DOC: history is used when focused face is no longer there
	
	add-to-history: function [space [object!]] [
		#debug focus [#print "adding (space/type):(space/size) to focus history"]
		face: either is-face? space [space][host-of space]
		#assert [face  "attempt to focus an out-of-tree (not yet drawn?) space"]	;@@ maybe call VID/update-focus in this case?
		; unless face [?? histories ?? window ?? space ?? space/content/1 ?? space/content/1/content/1 probe host-of space]		
		self/window: window-of face
		append hist: history space
		remove/part hist hist << 10						;-- limit history length
	]
	
	restore: function [] [
		if path: last-valid-focus [set-focus last path] 
	]
	
	deep-check: function [path [block! path!] facets [block!]] [
		foreach face path [
			unless is-face? face [break]
			unless all with face facets [return no]
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
				deep-check path [state enabled? visible?]
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
			deep-check path [state]						;-- without /state event is pointless; no visible/enabled in case they get set later
		][
			invalidate space							;-- let space remove its focus decoration
			events/with-stop [							;-- init a separate stop flag for a separate event
				event: copy events/event-prototype
				event/face: path/1
				event/type: 'unfocus
				events/process-event as [] path event [] yes
			]
		]
	]	
	
	send-focus: function ["Put focus on the space" space [object!] (space? space)] [
		if all [
			path: get-host-path space
			deep-check path [visible? enabled?]			;-- tests reachability, /state may be none if window is not yet shown
		][
			#assert [is-face? path/1]					;-- or set-focus will deadlock by calling this again
			#debug focus [#print "sending generated 'focus' event to (path/1/type):(path/1/size) on (mold select window-of path/1 'text)"]
			invalidate space							;-- let space paint its focus decoration
			native-set-focus host: path/1
			events/with-stop [							;-- init a separate stop flag for a separate event
				event: copy events/event-prototype
				event/face: host
				event/type: 'focus
				events/process-event as [] path event [] yes
			]
			unless system/view/auto-sync? [show window-of host]	;-- otherwise keys won't be detected
		]
	]
	
	*ace-enabled?:   function [face [object!]] [		;-- spaces has no support for disabling yet
		tabbing/enabled? either is-face? face [face][host-of face]
	]
	*ace-focusable?: function [face [object!]] [
		either is-face? face
			[tabbing/focusable? face]
			[find focus/focusable face/type]
	]
	*ace-visitor: function [parent [object! none!] child [object!]] [
		if all [*ace-focusable? child *ace-enabled? child] [break/return child]
	]
	find-next-focal-*ace: function [dir "forth or back"] [
		if focused: any [current window] [
			tabbing/window-walker/forward?: dir = 'forth
			foreach-node focused tabbing/window-walker :*ace-visitor
		]
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


;@@ should this refocus windows?
focus-space: function [
	"Focus given space object in it's window (does not refocus windows)"
	space [object!] (space? space)
][
	unless find focus/focusable space/type [return no]	;-- this space cannot be focused
	;; note: same space may appear on multiple hosts and windows (e.g. when put on a new popup all the time)
	if space =? old: focus/current [					;-- no refocusing into the same target, but need to ensure host is focused
		host: host-of space
		;@@ may error out without /parent check - e.g. if click on host hides it, then click continue on focusable child
		;@@ may also error out without host check - e.g. in non-compliant trees like grid-test5-7
		all [host host/parent native-set-focus host]
		return no
	]
	#debug focus [#print "moving focus from (mold/only reduce [old]) to (mold/only reduce [space])"]
	
	;@@ bring focused item into scrollable's view - maybe via on-focus handler?
	focus/send-unfocus old
	focus/send-focus space
	focus/add-to-history space
	#assert [space =? focus/current]
	yes
]

;; overrides (extends) the native function
native-set-focus: :system/words/set-focus
set-focus: function ["Focus face or space object" face [object!]] reshape [
	#debug focus [#print "set-focus call on (face/type):(face/size)"]
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
	
	focus-checker: function [face event] [
		; #print "checking focus for (face/type):(face/size)"
		;; focus host on clicks before all other events
		new-focal-face: either host? face
			[event/window/selected: face]
			[event/window/selected]
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
			focus/window: event/window
		]
	]
	
	insert-event-func 'spaces-focus-tracker filtered-event-func [face event] [
		[down alt-down mid-down aux-down dbl-click focus unfocus]
		focus-checker face event
		none
	]
	
	;@@ this fixes the situation when a host in a new window has got focus but `focus-checker` didn't receive 'focus' event
	register-previewer [key-down] function [space [object!] path [block!] event [map!]] [
		focus-checker event/face event
	]
]


register-previewer/priority
	[down mid-down alt-down aux-down dbl-click]			;-- button clicks on host may change focus
	function [space [object!] path [block!] event [map!]] [
		;@@ should it avoid focusing if stop flag is set?
		#debug focus [#print "attempting to focus (space-id space)"]
		path: get-host-path space
		#assert [path "detected click on an out-of-tree widget"]
		all [
			path										;-- can be none in non-compliant trees, like in grid-test5-7
			focus/deep-check path [state enabled?]		;-- don't focus on a just-destroyed host (popup)
			focus-space space
		]
	]


export exports
