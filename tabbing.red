Red [
	title:   "Tabbing support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
	notes:   {Extends %common/tabbing.red}
]

;-- requires events.red & focus.red, common/tabbing.red
#assert [object? tabbing]
remove-event-func 'tabbing								;-- will be called by the spaces handler

;; handler for faces
insert-event-func 'tabbing spaces-tab-handler: function [face event] [
	all [
		event/key = #"^-"
		face/type <> 'base								;-- handled by the finalizer below
		not event/ctrl?									;-- let area and tab-panel handle ctrl-tab
		result: 'stop
		not host? face									;-- but just in case /avoid-faces is modified and supports general base
		event/type = 'key-down							;-- only react to one event type (should be repeatable - key or key-down)
		set-focus focus/find-next-focal-*ace (pick [back forth] event/shift?)
	]
	result
]

;; handler for spaces
;; has to be `key` event (if it's key-down, the following `key` event after refocus goes into the wrong space)
;@@ consider consuming the next key-up event when refocused
register-finalizer [key] function [space [object!] path [block!] event [event! map! object!]] [
	all [
		event/key = #"^-"
		not stop?										;-- was not eaten by any space
		set-focus focus/find-next-focal-*ace (pick [back forth] event/shift?)
	]
]