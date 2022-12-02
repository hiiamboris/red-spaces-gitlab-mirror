Red [
	title:   "Rich-content test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

;; let capital initial be an image
svf: system/view/fonts
r: rtd-layout compose/deep [font [50 (svf/serif)] "L" /font]
fgcolor: any [system/view/metrics/colors/text]
bgcolor: any [system/view/metrics/colors/panel]
bgnd: make image! compose [(16x4 + size-text r) (bgcolor)]
capital: draw bgnd compose [
	pen (fgcolor) text 8x2 (r)
	line-width 4 pen (bgcolor) line 10x0 50x100 line 50x20 0x70
	line-width 1 pen (fgcolor) fill-pen off box 1x1 (bgnd/size - 1) 10
]; ? capital

source: does [compose [
	(make-space 'image [data: capital])
	font: (svf/serif) size: 20 {o} size: 17 {r} size: 15 {e} size: 14 {m} size: 11
	{ ipsum dolor sit amet, consectetur adipiscing elit, }
	italic {sed do eiusmod tempor incididunt ut labore et dolore magna } underline {aliqua.} /underline
	{ Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.}
	{ Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.}
	{ Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
]]

view/no-wait/options/flags [
	below
	b: host 500x500 [
		style rich-content2: rich-content source= source
		row tight [
			column tight weight= 1 [
				cell left   [rich-content2 align= 'left]
				cell center [rich-content2 align= 'center]
			]
			column tight weight= 1 [
				cell left   [rich-content2 align= 'fill]
				cell right  [rich-content2 align= 'right]
			]
		]
	] react [
		face/size: face/parent/size - 100x100
		status/offset/y: face/parent/size/y - 50
		status/size/x: face/parent/size/x - 20
	]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 400x60
] [offset: 10x10] 'resize

either system/build/config/gui-console? [halt][do-events]
