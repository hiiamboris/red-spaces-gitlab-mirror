Red [
	title:   "Focus tracking for Spaces"
	author:  @hiiamboris
	license: BSD-3
	depends: [spaces.focus spaces.auxi  maybe advanced-function]
	notes:   {Most of this is a set of kludges to work around serious issues with Red/View focus}
]

once set-focus*: :set-focus

focus/tracking: classy-object [
	"Kludges that help Spaces track what the currently focused face is"
	
	insert-event-func 'spaces-focus-tracker						;@@ this only works for window/field/area - #3728
		focus-tracker: filtered-event-func [focus unfocus]		;@@ it is also the only way to know about window activation/deactivation
		function [event [event!]] [
			target: event/face
			either event/type = 'focus [
				if target/type = 'window [
					target: any [target/selected target]		;-- window activation puts focus back into the selected widget
				]
				focus-on-face target
			][
				if any [										;@@ unfocus becomes harmful outside these two allowed cases
					same? target focus/current
					target/type = 'window
				][
					maybe focus/current: none
					#debug focus [print "lost focus"]
				]
			]
		] #type "(internal) Kludge for window/field/area"

	insert-event-func 'spaces-focus-down-tracker				;@@ covers clicks on buttons and other focusables - #3728
		focus-down-tracker: filtered-event-func [down]
		function [event [event!]] [
			if any [
				'focusable = flags: event/face/flags			;@@ this has false positives - #5574
				if block? flags [find flags 'focusable]
			][
				focus-on-face event/face
			]
		] #type "(internal) Kludge for buttons and other focusables"
		
	
	global set-focus: function [ 
		"Sets the keyboard focus on a face or space object"
		*ace [object!] (any [space? *ace face? *ace])
	][
		;; it is imperative here that focus detection follows the actual set-focus* native call
		;; otherwise e.g. when tabbing from field into a button it'll be a [field -> button -> none] chain
		;; instead of proper [field -> none -> button]
		;@@ but this order assumption is still going to be broken in non-auto-sync mode
		either face? *ace [
			set-focus* *ace
			focus-on-face *ace									;@@ covers programmatic set-focus into faces (e.g. tabbing)
		][
			focus/focus-space *ace
		]
		*ace
	]

	focus-on-face: function [
		"(internal) Invoked when focus is detected on the FACE"
		face [object!]
	][
		#debug focus [unless same? face focus/current [print ["focused" face/type ":" face/text]]]
		maybe/same focus/current: face
	]
	
	;@@ other methods to consider:
	;@@ 1. hijacking window/init and adding reaction to /selected - currently covered by set-focus override
	;@@ 2. key-down events hook - who receives the key is in focus - currently seems to be unnecessary
	;@@ 3. hijacking stop-reactor and adding focus/restore - not sure it's needed, as another window should be focused at that time
]

;; testing/tuning code
; w: view/no-wait [
	; b1: button "1" [print 1] b2: base "2" b3: button "3" [print 3] f4: field "4" a5: area "5" return 
	; panel [b6: button "6" f7: field "7" b8: base "8" with [flags: 'focusable]]
; ]
; ;react [print ["override:" if w/selected [w/selected/type] ":" if w/selected [w/selected/text]]]	;@@ #5575
; halt
