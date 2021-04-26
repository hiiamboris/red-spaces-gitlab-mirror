Red [
	title:   "Tabbing support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires events.red & focus.red


;-- has to be `key` event (if it's key-down, the following `key` event after refocus goes into the wrong space)
register-finalizer [key] function [space [object!] path [block!] event [event!]] [
	if all [
		event/key = #"^-"								;-- tab key
		not stop?										;-- was not eaten by any control
	][
		new-focus: find-next-focal-space (pick [back forth] event/shift?)
		unless same-paths? new-focus keyboard/focus [
			#debug [#print "Moving focus from (as path! keyboard/focus) to (as path! new-focus)"]
			; probe index? find-same-path list-*aces anonymize 'screen system/view/screens/1 as path! new-focus
			keyboard/focus: new-focus
			update
		]
	]
]