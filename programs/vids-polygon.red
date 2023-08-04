Red [
	title:   "VID/S experimentation polygon"
	author:  @hiiamboris
	license: 'BSD-3
]

; #do [disable-space-cache?: yes]
#include %../everything.red
#include %../../common/load-anything.red

config: object [offset: size: text: none]
attempt [set config construct expand-directives load %vids-polygon.cfg]
default config/size: 400x300
default config/text: "cell [text {some stuff} green]"
; debug-draw
; view/no-wait/flags/options compose [
view/flags/options reshape [
	title "VID/S experimentation polygon"
	text "VID/S code:" space: area 400x80 focus !(config/text) return
	host: host !(config/size) white react [
		try [
			face/space:    first lay-out-vids load/all space/text
			config/text:   space/text
			config/offset: host/parent/offset
			config/size:   host/size
			write %vids-polygon.cfg mold/all/only config
		]
	] on-over [status/text: mold hittest face/space event/offset]
	return status: text 400x40
] 'resize [
	offset: config/offset
	actors: object [
		on-resize: on-resizing: function [window event] [
			status/size: window/size/x - 20 . 40 
			status/offset/y: window/size/y - 50
			host/size: window/size - 20x155
			if host/space [invalidate host/space]
		]
	]
]
