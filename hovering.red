Red [
	title:   "Hovering support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires events.red & focus.red


;-- provides early detection of the moment pointer leaves the space it last hovered above
register-previewer [
	time over											;@@ assumes only timer renders the host
														;@@ although previewer gets called on next frame only (may be a good thing)
] function [space [object!] path [block!] event [event!]] [
	last-path:  []
	last-wpath: []
	extract/into path 2 wpath: clear []
	unless same-paths? wpath last-wpath [
		unless empty? last-wpath [
			hittest/as/into
				event/face/space
				event/offset
				last-path
				away-path: clear []
			#assert [not empty? away-path]
			event/away?: yes
			events/process-event away-path event no
			event/away?: no
		]
		append clear last-wpath wpath
		append clear last-path path
	]
]