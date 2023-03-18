Red [
	title:   "Requester widgets for Spaces"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Requester guidelines.
		
		I care for human friendliness more than for OS standards.
		
		Requesters should not become a "Guess what button to click" game,
		which is the case if they have a long message and answers like "Yes"/"No"
		that require careful reading of the context before the decision can be made.
		
		Requesters should:
		- be immediately obvious (think milliseconds) without reading
		- help avoid accidental damage (e.g. a stuck Enter key pressing the "Erase" button)
		
		A dialog to ask whether to save the work should never appear in the first place.
		Work should be saved in background and have multiple backups in multiple places, and restored automatically.
		
		But in case a possibly destructive action is being considered,
		the dialog may as well draw big red button with the HDD broken into pieces or smth,
		near another focused green button with the happy picture. And it would work.
		
		I understand the laziness though, and words for buttons are often fine.
		But words should never be "Yes" and "No". Words should be "Save" and "ERASE"!
		This way they don't need context, and case acts as a warning on possible destruction.
		Preferably also with color, but this is subject to application style.
		
		Window closure without button click should be considered a Cancel (abort, do nothing) action when possible.
		When impossible, next least destructive action.
		
		Requesters to consider:
		- file/directory/font - better to use native; for font there can be better UI than a requester
		- color - better to use native, but since that is not implemented, temporarily available
		- confirmation (e.g. on quit, or recovery from a sudden error) - valid need
		- alert (informational or with choice) - valid need, but should flash it (not yet possible in Red)
		- splash screen - bad practice, in worst cases stays on top and blocks the PC, avoid it 
		- blocking timers (e.g. while connecting to smth) - bad UI practice 
		- simple data input (text/URL, count/size, option to pick) - must be better UI for this
		  but requester can be used as a temporary kludge until that UI is finished
		- date/time - same
		
		On portability.
		Dialogs are mostly a PC thing. Implies touch screen and touchpad friendliness.
		Modern UIs tendency is to avoid dialogs and adopt a browser-like paging behavior.
		A dialog can be replaced with a new page with choices to proceed, or Back button to cancel the action.
		If portability with handheld devices is desired, paging UI is a better option.
		If not, dialogs are an OK choice, less visually intrusive, keeps the context (main window) visible.
	}
]

; #include %../everything.red

#include %color-picker.red

request: function [
	"Display a requester dialog of provided configuration"
	title   [string!]
	layout  [block!] "VID/S code for dialog body"
	buttons [block!] {List of buttons, e.g. ["OK" [action] @"Cancel" [action]] - use @ for default button}
	/local focus text action result default
][
	buttons: mapparse [set default opt @ set text string! set action opt block!] copy buttons [
		action: compose/only [set/any 'result do (only action) unview]	;-- action can use `exit` to prevent unview
		compose/deep [(when default [default-button:]) button 60 .. none (text) [(action)]]
	]
	view/flags compose/deep/only [
		title (title)
		host focus [
			column align= 0x0 [box 200 .. none (layout) row (buttons) align= 0x0]
		] on-key-up [									;-- 'key-up' so Enter first goes into buttons, then here
			switch event/key [
				#"^[" [unview]							;@@ suffers from #5124 unfortunately
				#"^M" [if default-button [do default-button/command]]
			]
		]
	] [modal no-min no-max]
	if unset? :result [result: none]					;-- avoid unset results from empty button commands
	:result												;-- returns none if closed without a button
]

request-color: function [
	"Show a dialog to request color input"
	/from color: gray [tuple! none!] "Initial (default) result"
][
	request "Pick a color" [
		vlist [
			cp: color-picker 200x200 color= color
			box 200x20 white react [color: cp/color]
		]
	] [@"OK" [cp/color] "Cancel"]
]

; probe request-color/from blue
; probe request-grid-size
; probe request-url
; request "request title" [text 0 .. 400 "some message text"] [@"OK" [print "OK"] "Cancel" [print "Ca"]]
; quit