Red [
	title:   "Focus model for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- provides focusing by clicking
;-- requires: export is-face? and window-of

exports: [focused? focus-space]

;@@ rename this!? e.g. focus/current instead of keyboard/focus?
;@@ `focus` itself should be somewhere else, as it is used by dispatch and who knows what
keyboard: object [
	;-- which spaces should receive focus? affects tabbing & clicking
	;-- class should not matter, name should - then we'll be able to override/extend classes
	;@@ TODO: should paths be allowed here? e.g. if some spaces are only focusable in some bigger context?
	focusable: make hash! [scrollable button field table list-view grid-view]

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

	;@@ TODO: maybe instead of this, scanning should continue from last valid outer space
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


;-- for use within styles
focused?: function [
	"Check if current style is the one in focus"
	/parent "Rather check if parent style is the one in focus"
	;@@ will /parent be enough or need more levels?
][
	all [
		name1: last keyboard/focus						;-- order here: from likely empty..
		name2: either parent [							;-- ..to rarely empty (performance)
			pick tail current-path -2
		][	last current-path
		]
		(get name1) =? get name2
	]													;-- result: true or none
]


;@@ TODO: do not enter hidden tab panel's pane (or any other hidden item?)
find-next-focal-space: function [dir "forth or back"] [
	focus: keyboard/last-valid-focus
	#debug focus [#print "last valid focus: (as path! focus)"]
	; #assert [focus]										;@@ TODO: cover the case when it's none
	foreach: pick [										;@@ use apply
		foreach-*ace/next
		foreach-*ace/next/reverse
	] dir = 'forth 
	do compose/only [
		(foreach) path next: focus [			;-- default to already focused item (e.g. it's the only focusable)
			#debug focus [
				space: get last path 
				text: mold any [select space 'text  select space 'data] 
				#print "find-next-focal-space @(path), text=(text)"
			]
			if find keyboard/focusable last path [next: path break]
		]
	]
	path: copy as focus next					;-- preserve the original type
	new-line/all path no
]

;; since I can't create events, but still gotta tell previewers/finalizers what kind of event it is, have to work around
focus-event!:   object [type: 'focus   face: none]
unfocus-event!: object [type: 'unfocus face: none]

focus-space: function [
	"Focus space with a given PATH"
	path [block!] "May include faces"
	; return: [logic!] "True if focus changed"
] with events [
	path: append clear [] path							;-- make a copy so we can modify it
	while [name: take/last path] [						;-- reverse order to focus the innermost space possible ;@@ #5066
		unless find keyboard/focusable name [continue]
		append path new-name: name
		if same-paths? path keyboard/focus [break]		;-- no refocusing into the same target
		#debug focus [print ["Moving focus from" as path! keyboard/focus "to" as path! path]]

		with-update [									;-- provide context to event handlers
			;@@ with no face in the path, `update?` command is lost!
			foreach name path [							;-- if faces are provided, find the innermost one
				either is-face? f: get name [face: f][break]
			]
			
			unless empty? old-path: keyboard/focus [
				with-stop [								;-- init a separate stop flag for a separate event
					unfocus-event!/face: face
					process-event old-path unfocus-event! [] yes
					unfocus-event!/face: none
				]
			]
	
			if face [									;-- ..and focus it
				unless system/view/auto-sync? [
					show window-of face					;-- otherwise keys won't be detected
				]
			]
			keyboard/focus: copy path					;-- copy since the path is static
	
			with-stop [									;-- init a separate stop flag for a separate event
				focus-event!/face: face
				process-event path focus-event! [] yes
				focus-event!/face: none
			]
			
			all [commands/update? face face/dirty?: yes]
		]
		return yes
	]
	no
]

register-previewer
	[down mid-down alt-down aux-down dbl-click]			;-- button clicks may change focus
	function [space [object!] path [block!] event [event!]] [
		path: keep-type head path word!					;-- for focus path we want style names only

		f: event/face									;-- list also all face parents in the path
		until [
			insert path anonymize f/type f
			none? f: f/parent
		]

		#debug focus [#print "Attempting to focus (as path! path)"]
		if focus-space path [update]
	]


export exports