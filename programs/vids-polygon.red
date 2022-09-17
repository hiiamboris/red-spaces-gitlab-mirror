Red [
	title:   "VID/S experimentation polygon"
	author:  @hiiamboris
	license: 'BSD-3
]

; #do [disable-space-cache?: yes]
#include %../everything.red

text: any [
	attempt [read %vids-polygon.cfg]
	"cell [text {some stuff} green]"
]
; debug-draw
; view/no-wait/flags/options compose [
view/flags/options compose [
	title "VID/S experimentation polygon"
	text "VID/S code:" space: area 400x80 focus (text) return
	host: host 400x300 white react [
		try [
			invalidate <everything>						;-- ensure clearing of unused spaces & their timers
			data: load/all space/text
			face/space: first lay-out-vids data
			face/dirty?: yes
			write %vids-polygon.cfg space/text
		]
	] on-over [status/text: form hittest face/space event/offset]
	return status: text 400x40
] 'resize [
	actors: object [
		on-resize: on-resizing: function [window event] [
			status/size: window/size/x - 20 by 40 
			status/offset/y: window/size/y - 50
			host/size: window/size - 20x155
			host/dirty?: yes
		]
	]
]
