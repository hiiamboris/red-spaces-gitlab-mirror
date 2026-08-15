Red [
	title:   "Image Browser"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red
#include %../../common/match.red
#include %../../common/glob.red

masks: ["*.jpg" "*.jpeg" "*.png" "*.gif"]						;-- what Red supports so far
thumb-size: 200x100

define-handlers [
	tube: [box: [
		on-click [space path event] [
			if images/selected [images/selected/color: glass]
			images/selected: space
			space/color: opaque 'text 20%
		]
		on-dbl-click [space path event] [browse space/file]
	]]
]

load-dir: function [path [string!]] expand-directives [
	unless exists? path: attempt [dirize to-red-file path] [exit]
	files: glob/from/only/files/limit path masks 1
	clear images/content recycle
	for-each [/i file] files [
		unless image: attempt [load head file] [continue]
		status/text: `"(i)/(length? files) images loaded"`
		recycle
		do-queued-events										;-- prevent event queue buildup
		scale: image/size / thumb-size
		size:  to pair! image/size / max scale/x scale/y
		image: draw size compose [image (image) 0x0 (size)]		;-- resize thumbnail to save RAM
		append images/content lay-out-vids reshape [			;-- emit VID/S icon
			box glass with [file: @[head file]] [
				icon image= @[image] text= @[form second split-path file] with [
					spaces/text/flags:  [ellipsize]
					spaces/text/limits: 0 .. @[size/x by 20]
				]
			]
		]
		trigger 'images/content
	]
]

view/flags reshape [
	title "Spaces Image Browser"
	host 600x400 react [face/size: face/parent/size - 20] [		;-- autoresize host
		column tight [
			row middle [
				text "Path:"
				path: field @[to-local-file what-dir] focus
				button 30 "..." [attempt [path/text: to-local-file request-dir/keep]]
			]
			scrollable vertical [images: row [] selected= none]
			status: text ""
			react [load-dir path/text]
		]
	]
] 'resize