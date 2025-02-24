Red [
	title:    "Keyboard focus implementation for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.focus
	depends:  [classy-object advanced-function for-each]
]


focus: classy-object [
	"Keyboard focus management"
	
	set 'focus self												;-- required for the forward reference to 'move-focus'
	
	move-focus: function [
		"(internal) Called when the keyboard focus moves"
		old [object! none! unset!]
		new [object! none!]
	][
		if is-space? :old [
			scheduler/synthesize-event [
				type:   unfocus
				face:   (host: host-of old)
				window: (window-of host)
			] 
		]	
		if new [
			remove find/same history new						;-- no need in duplication of spaces in the history
			append history new
			if (length? history) >= 1024 [						;-- keep the length sane, but wide enough
				remove/part history 128
			]
			if is-space? new [
				scheduler/synthesize-event [					;@@ maybe synthesize should obtain the window and host?
					type:   focus
					face:   (host: host-of new)
					window: (window-of host)
				]
			]
		]
	]
	
	;; single per-interpreter focused face or space object, or `none` when nothing is focused
	current:  none
		#type [object! none!] "Current keyboard focus target (face or space object)"
		#on-change [obj word new old [any-type!]] [focus/move-focus :old new]
		
	;; history of focus changes used for focus restoration
	;; useful e.g. if a popup was shown, a lot of refocus (tab?) events happened, then popup got closed
	history:  make [] 32	#type [block!] "Values previously assigned to /current (used for focus restoration)"
	
	;; context for %focus-tracking.red
	tracking: none
	
	focus-space: function [
		"Put keyboard focus on a SPACE"
		space [object!] (space? space)
	][
		#debug focus [#print "focusing (space-id space)"]
		#assert [select space 'focusable?  "Attempt to focus an unfocusable space"]
		host: host-of space
		#assert [host  "Attempt to focus a detached space"]		;@@ an unfortunate limitation of Red focus model - see REP #172
		set-focus* host
		maybe/same focus/current: space
	]
	
	global focused?: function [
		"Test if SPACE has keyboard focus"
		space [object!]
		/child "Test if one of the children has focus instead"
	][
		either child
			[to logic! if current [find/same (list-parents current) space]]
			[same? space current]
	]

	restore: function ["Put keyboard focus to the last target that is still live"] [
		at-live: locate/back history [x .. space? x live? x  target: x]
		clear either at-live [next at-live][history]
		maybe/same focus/current: target						;-- sets to 'none' when no live target found
	]
]