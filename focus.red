Red [
	title:   "Focus model for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- provides focusing by clicking
;-- requires: is-face?

;@@ rename this!? e.g. focus/current instead of keyboard/focus?
;@@ `focus` itself should be somewhere else, as it is used by dispatch and who knows what
keyboard: object [
	;-- which spaces should receive focus? affects tabbing & clicking
	;-- class should not matter, name should - then we'll be able to override/extend classes
	;@@ TODO: should paths be allowed here? e.g. if some spaces are only focusable in some bigger context?
	focusable: make hash! [scrollable button field table list-view]

	focus: []	;-- a path (descending list of spaces)
	;@@ DOC: focus is a path because we want to be able to go up the tree when tabbing

	history: []	;-- previous focus paths, including current
	;@@ DOC: history is used when focused face is no longer there

	;-- path is valid if it's visible still
	;-- for faces this means 'state' is not none and 'visible?' is true
	;-- spaces can be created in a vacuum, but their map should contain rendered only items
	;@@ TODO: externalize this, as it is general enough ?
	valid-path?: function [path [path! block!]] [
		foreach name path [
			obj: get name
			either is-face? obj [
				unless all [obj/state obj/visible?] [return no]
			][
				if all [map  not find map name] [return no]
				map: select obj 'map
			]
		]
		yes
	]

	last-valid-focus: function [] [
		foreach path history [if valid-path? path [return path]]
		none
	]

	;-- automatic focus history collection
	on-change*: func [word old [any-type!] new [any-type!]] [
		if any [word <> 'focus  same-paths? old new][exit]
		insert/only history copy new
		clear skip history 10							;@@ 10 spaces should be enough?
	]
]



;@@ TODO: do not enter hidden tab panel's pane (or any other hidden item?)
find-next-focal-space: function [dir "forth or back"] [
	focus: keyboard/last-valid-focus
	#debug focus [#print "last valid focus: (as path! focus)"]
	foreach: pick [										;@@ use apply
		foreach-*ace/next
		foreach-*ace/next/reverse
	] dir = 'forth 
	do compose/only [
		(foreach) path next: focus [			;-- default to already focused item (e.g. it's the only focusable)
			#debug focus [#print "find-next-focal-space @(path)"]
			if find keyboard/focusable last path [next: path break]
		]
	]
	path: copy as focus next					;-- preserve the original type
	new-line/all path no
]


focus-space: function [
	"Focus space with a given PATH"
	path [block!] "May include faces"
	; return: [logic!] "True if focus changed"
][
	path: append clear [] path							;-- make a copy so we can modify it
	while [name: take/last path] [						;-- reverse order to focus the innermost space possible
		unless find keyboard/focusable name [continue]
		append path new-name: name
		if same-paths? path keyboard/focus [break]		;-- no refocusing into the same target
		#debug [print ["Moving focus to" as path! path]]

		unless empty? old-path: keyboard/focus [
			events/do-previewers old-path none 'on-unfocus		;-- pass none as 'event' since we don't have any
			events/do-handlers   old-path none 'on-unfocus no
			events/do-finalizers old-path none 'on-focus
		]

		foreach name path [								;-- if faces are provided, find the innermost one
			either is-face? f: get name [face: f][break]
		]
		if face [set-focus face]						;-- ..and focus it
		keyboard/focus: copy path						;-- copy since the path is static

		events/do-previewers path none 'on-focus				;-- pass none as 'event' since we don't have any
		events/do-handlers   path none 'on-focus no
		events/do-finalizers path none 'on-focus

		return yes
	]
	no
]

register-previewer
	[down mid-down alt-down aux-down dbl-click]			;-- button clicks may change focus
	function [space [object!] path [block!] event [event!]] [
		path: keep-type path word!						;-- for focus path we want style names only

		f: event/face									;-- list also all face parents in the path
		until [
			insert path anonymize f/type f
			none? f: f/parent
		]

		#debug focus [#print "Attempting to focus (as path! path)"]
		if focus-space path [update]
	]
