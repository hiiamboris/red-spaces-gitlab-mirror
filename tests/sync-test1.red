Red []

#include %../everything.red

box: make-space 'box [
	margin: 25
	color: yello
	draw: function [/on canvas fill-x fill-y] [
		render/on content (50,50) yes yes
		render/on content (50,25) yes yes
		print "--->"
		r: render/on content (50,50) yes yes
		print "<---"
		self/map: compose/deep [(content) [offset: (margin * (1,1)) size: (content/size)]]
		self/size: canvas
		probe compose/only [pen off fill-pen (color) box (0,0) (self/size) translate (margin * (1,1)) (r)]
	]
	content: make-space 'box [
		margin: 10
		color: orange
		content: make-space 'box [
			margin: 10
			color: red
		]
	]
]

view/no-wait [
	txt: text wrap 300x50
	host: host 100x100 with [space: box]
	on-over [txt/text: mold hittest host/space event/offset]
]
; render host  invalidate host/space
; ?? box/cached
; probe (head box/content/cached)
; probe (head box/content/content/cached)
do-events
