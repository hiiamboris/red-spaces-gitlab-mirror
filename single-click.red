Red [
	title:   "Click event simulation for Draw-based widgets (because Base does not support it)"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires events.red

;-- whatever the reason, on-click event fires after on-up, while on-dbl-click - after on-down
;-- and it seems to be cross platform so let's just follow along
;-- version: this makes double-click then drag possible

register-finalizer [up] function [space [object!] path [block!] event [event!]] [
	event/type: 'click									;-- Red allows overriding it
	;-- either this, but it may call `update` twice, after on-up and after on-click (may not be a bad thing)
	events/dispatch event/face event
	;-- or this, but we'll need to carry the `update?` flag over
	; events/with-commands [
	; 	events/process-event path event no
	; ]
	event/type: 'up										;-- restore it for the other finalizers
]