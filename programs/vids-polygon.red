Red [
	title:   "VID/S experimentation polygon"
	author:  @hiiamboris
	license: 'BSD-3
]

; #do [disable-space-cache?: yes]
#include %../everything.red
#include %../../common/load-anything.red
#include %../../common/data-store.red

config: data-store/load-config/name/defaults %vids-polygon.cfg #(
	size: 400x300
	text: "cell [text {some stuff} green]"
)
; debug-draw
; view/no-wait/flags/options compose [
view/flags/options reshape [
	title "VID/S experimentation polygon"
	text "VID/S code:" code: area 400x80 focus @[config/text] return
	host: host @[config/size] white on-over [status/text: mold hittest face/space event/offset]
	return status: text 400x40 rate 0:0:3 on-time [
		data-store/save-config/name config %vids-polygon.cfg
	]
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
	react/later [
		try [
			host/space:    first lay-out-vids load/all code/text
			config/text:   code/text
			config/offset: host/parent/offset
			config/size:   host/size
		]
	]
]
