Red []

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
	text "VID/S code:" space: field 400 focus (text) return
	host: host 400x300 white react [
		try [
			data: load/all space/text
			face/space: first probe lay-out-vids data
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
			host/size: window/size - 20x95
			host/dirty?: yes
		]
	]
]
