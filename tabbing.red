Red [
	title:   "Tabbing support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires events.red & focus.red


;-- has to be `key` event (if it's key-down, the following `key` event after refocus goes into the wrong space)
register-finalizer [key] function [space [object!] path [block!] event [event! object!]] [
	if all [
		event/key = #"^-"								;-- tab key
		not stop?										;-- was not eaten by any control
	][
		new-focus: find-next-focal-space (pick [back forth] event/shift?)
		focus-space new-focus
	]
]