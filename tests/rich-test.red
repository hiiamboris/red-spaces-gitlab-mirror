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
	italic "12 " bold "34^/ "
	(make-space 'text [text: "ab cde f" color: cyan])
	color: white " 56 " /color /bold /italic
	(make-space 'text [text: "efh" color: yellow])
	" 78"
]
				
view/no-wait/options/flags [
	below
	b: host 200x500 [
		row tight [
			column tight weight= 1 [
				box left forest [rich-content source= compose source align= 'left]
				box right blue  [rich-content source= compose source align= 'right]
			]
			column tight weight= 1 [
				box center blue [rich-content source= compose source align= 'center]
				box left forest [rich-content source= compose source align= 'fill]
			]
		]
	] react [
		face/size: face/parent/size - 200x100
		status/size/x: face/parent/size/x - 20
	]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 400x60
] [offset: 10x10] 'resize

either system/build/config/gui-console? [halt][do-events]
