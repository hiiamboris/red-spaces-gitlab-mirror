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
	"12 34 "
	make-space 'text [text: "ab cde f" color: cyan]
	" 56 "
	make-space 'text [text: "efh" color: yellow]
	" 78"
]
				
view/no-wait/options/flags [
	below
	b: host 200x500 [
		row tight [
			column tight weight= 1 [
				box left forest [rich-content source= reduce source align= 'left]
				box right blue  [rich-content source= reduce source align= 'right]
			]
			column tight weight= 1 [
				box center blue [rich-content source= reduce source align= 'center]
				box left forest [rich-content source= reduce source align= 'fill]
			]
		]
	] react [face/size: face/parent/size - 100x0]
	; on-over [
		; status/text: mold as path! hittest face/space event/offset
	; ]
	; status: text 400x40
] [offset: 10x10] 'resize

either system/build/config/gui-console? [halt][do-events]
