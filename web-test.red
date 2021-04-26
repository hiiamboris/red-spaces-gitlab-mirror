Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

recycle/off
#include %everything.red


define-handlers [
	web: extends 'scrollable [
		on-time [space path event] [space/roll update]
	]
]

view/no-wait/options [
	below
	b: host [
		web with [size: 300x200 rate: 4]
	] with [color: system/view/metrics/colors/panel]
	on-over [
		status/text: form hittest face/space event/offset
	]
	rate 3 on-time [
		b/draw: render/as b/space 'root
	]
	status: text 300x40
] [offset: 10x10]
foreach-*ace/next path system/view/screens/1 [probe path]
either system/build/config/gui-console? [halt][do-events]

