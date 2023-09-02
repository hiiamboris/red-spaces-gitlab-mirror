Red [
	title:   "Rich-content test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red
								
view/no-wait/options/flags [
	below
	b: host 200x500 [
		style rich-paragraph: rich-paragraph [
			text italic "12 " text bold italic "34 "
			text bold italic " ab cde f"  sky
			text bold italic " ab cde f" pink margin= 10x0
			text bold italic " ab cde f"  papaya
			text bold italic white " 56 "
			text "efh" yellow
			text " 78"
		]
		; on-over [
			; caret: spaces/ctx/rich-content-ctx/xy-to-caret space offset: path/2
			; lrow:  spaces/ctx/rich-content-ctx/caret-to-row space caret 'left
			; rrow:  spaces/ctx/rich-content-ctx/caret-to-row space caret 'right
			; rowbox: if lrow [spaces/ctx/rich-content-ctx/row-to-box space lrow]
			; lcarbox: spaces/ctx/rich-content-ctx/caret-to-box space caret 'left
			; rcarbox: spaces/ctx/rich-content-ctx/caret-to-box space caret 'right
			; ?? [caret offset lrow rrow rowbox lcarbox rcarbox]
		; ]
		row tight [
			column tight weight= 1 [
				box left forest [rich-paragraph align= 'left]
				box right blue  [rich-paragraph align= 'right]
			]
			column tight weight= 1 [
				box center blue [rich-paragraph align= 'center]
				box left forest [rich-paragraph align= 'fill]
			]
			column tight weight= 1 [
				box center forest [rich-paragraph align= 'scale]
				box center blue   [rich-paragraph align= 'upscale]
			]
		]
	] react [
		face/size: face/parent/size - 200x100
		status/size/x: face/parent/size/x - 20
	]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 400x60
] [offset: 400x10] 'resize

either system/build/config/gui-console? [run-console][do-events]
