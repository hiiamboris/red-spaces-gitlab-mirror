Red [
	title:   "Web test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
cd %..
do %everything.red


define-handlers [
	web: extends 'inf-scrollable [
		; on-time [space path event] [space/roll update]
	]
]
append keyboard/focusable 'web

view/no-wait/options [
	below
	b: host [
		web with [size: 900x600]
		; web with [size: 300x200]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	; rate 3 on-time [b/draw: render b]
	status: text 300x40
] [offset: 10x10]
; foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [halt][do-events]

