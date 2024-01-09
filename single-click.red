Red [
	title:   "Click event simulation for Draw-based widgets (because Base does not support it)"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Whatever the reason, on-click event fires after on-up, while on-dbl-click - after on-down
		and it seems to be cross platform so I'm just following along.
		Guess: this makes double-click then drag possible.
		
		Also, on-click fires even if pointer was dragged, but stayed within the same widget.
		So the only conditions are both on-down and on-up within the widget.
		It turns out that accidental movement during click happens quite often,
		which explains this design choice - don't wanna miss these clicks.
		
		Whether or not to limit pointer travel that allows for a click event, undecided yet.
		Or whether on-up in another space should produce click event in it.
	}
]

;-- requires events.red

context [
	start-offset: none						;-- separate from `start-drag`, which is userspace thing, and this one is hidden

	;-- for `down` it doesn't matter if we use previewer or finalizer
	register-finalizer [down] func [space [object!] path [block!] event [map!]] [
		start-offset: event/offset
	]

	;@@ is it ok that click event will follow up event for normal handlers? but some finalizers will have it unordered
	;@@ or maybe we should schedule some code to be run after the finalizers have finished?
	register-finalizer [up] function [space [object! none!] path [block!] event [map!]] [
		if all [
			event/face							;@@ partial workaround for #5124 - but can do nothing with View internal bugs
			20 >= distance? start-offset event/offset	;-- it's a click, not a drag
			not stop?									;-- up event was not eaten
			head? path									;-- original event, not replicated for children
			;; note: can't leverage children replication here, since `stop` flag has to be shared by the whole stack
		][
			event/type: 'click							;-- Red allows overriding it
			events/with-stop [events/process-event path event [] no]
			event/type: 'up								;-- restore it for the other finalizers
		]
		;@@ TODO: maybe a drag-finished event?
		;@@ but need to decide how to do it properly, e.g. maybe provide a path or axis
		;@@ and if such event is even useful, considering we have on-up and will probably have on-drag
	]

]
