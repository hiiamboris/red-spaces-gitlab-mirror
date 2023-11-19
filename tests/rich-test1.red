Red [
	title:   "Rich-content test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

#include %../everything.red

				; rich-paragraph 20 [
					; text "ab cd ef" cyan
					; text "efh" magenta
				; ] breakpoints= reduce [
					; make vector! [11 21]
				; ] align= 'right
				; ] align= 'center
				; ] align= 'fill
				; ] align= 'left
				
source: [
	italic "12 " bold "34 "
	(make-space 'text [text: "ab cde f" color: cyan])
	(make-space 'text [text: "ab cde f " color: cyan margin: 10x0])
	(make-space 'text [text: "ab cde f" color: cyan])
	color: white " 56 " /color /bold /italic
	(make-space 'text [text: "efh" color: yellow])
	" 78"
]
				
view/no-wait/options/flags reshape [
	below
	b: host 200x500 [
		style rich-content: rich-content
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
				box left forest [rich-content @[compose source] align= 'left]
				box right blue  [rich-content @[compose source] align= 'right]
			]
			column tight weight= 1 [
				box center blue [rich-content @[compose source] align= 'center]
				box left forest [rich-content @[compose source] align= 'fill]
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
