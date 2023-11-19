Red [
	title:       "RedMark"
	description: "The world's smallest markdown viewer"
	author:      @hiiamboris
	license:     BSD-3
	needs:       view
	notes: {
		Name is chosen to be general enough to pack more tooling into it later. 
		E.g. TOC generation. Or other formats support.
	}
]

#include %../everything.red
#include %toy-markdown.red
#include %../../cli/cli.red								;@@ eventually it should be a GUI tool


;; fonts and other style data
~styling: context [
	svf: system/view/fonts
	
	fonts: object [
		;; font size increase for normal text and headings of levels 1 to 6
		sizes: [0 10 6 4 3 2 1]
		
		text-font!: make font! [size: svf/size name: svf/sans-serif]
		code-font!: make font! [size: svf/size name: svf/fixed]
		text: map-each n sizes [
			make text-font! [size: size + n style: if n > 0 ['bold]]
		]
		code: make map! map-each/eval n sizes [[
			svf/size + n
			make code-font! [size: size + n style: if n > 0 ['bold]]
		]]
		code/base: code/(svf/size)
	]
	
	;; heading flags - those that do not carry over to `code`
	flags: object [
		headings: [[underline] [underline] [] [] [] []]
	]
]

do/expand with spaces/ctx [

	;; 'pre' VID/S style
	VID/styles/pre: copy VID/styles/text
	VID/styles/pre/template: 'pre

	;; pre and code templates for styling
	declare-template 'pre/paragraph []
	declare-template 'code/text []
	declare-template 'thematic-break/stretch [limits: 0x20 .. (1.#inf . 20)]
	declare-template 'rich-content/rich-content [
		;; code inside links should be painted blue
		apply-attributes: function [space attrs] [
			if space/type = 'code [
				space/color: all [attrs/color]
				space/flags: only if attrs/underline [[underline]]
			]
			space
		]
	]
	
	;; extend grid with per-column alignment setting
	declare-template 'grid/grid [
		autofit: 'width-difference						;-- use browser-like fitting
		alignment: []	#type =? [block!] :invalidates	;-- per-column alignments list
		old-wrap-space: :wrap-space
		wrap-space: function [xy [pair!] space [object! none!]] [
			cell: old-wrap-space xy space
			quietly cell/align: any [pick alignment xy/x  -1x0]
			quietly cell/margin: 10x10
			cell
		]
	]
	
	underbox: function [
		"Draw a box to highlight code parts"
		size       [planar!]
		line-width [linear!]
		rounding   [linear!]
	][
		compose/deep [
			push [										;-- solid box under code areas
				line-width (line-width)
				pen (opaque 'text 10%)
				fill-pen (opaque 'text 5%)
				box 0x0 (size) (rounding)
			]
		]
	]
	
	;; a few visual styles for more browser-like experience
	define-styles [
		text: paragraph: link: [
			font: parent/font
			below: when select self 'color [pen (color)]
		]
		rich-content: [
			default font: ~styling/fonts/text/1
			margin: font/size - svf/size * (0,1)
		]
		cell/rich-content: [
			default font: ~styling/fonts/text/1
			align: select #(-1 left 0 center 1 right) parent/align/x	;-- carry cell alignment into text
		]
		pre: [
			margin: 10
			font: ~styling/fonts/code/base
			below: [(underbox size 2 5)]
		]
		code: [
			if parent/font [							;-- different fonts for all headings and text
				font: ~styling/fonts/code/(parent/font/size)
			]
			margin: 4x0
			pen: when color (compose [pen (color)])
			below: reduce [quote (underbox size 1 3) pen]
		]
		thematic-break: [
			below: [
				line-width 3
				pen (opaque 'text 10%)
				line (size * (0,1) / 2 + 5x0) (size / (1,2) - 5x0)
			]
		]
		grid: [
			spacing: 2x2
			below: [
				push [
					pen off fill-pen (opaque 'text 30%)
					box 0x0 (size)
				]
			]
		]
	]
];; do/expand with spaces/ctx


red-mark: function [
	"Red Mark - World's smallest markdown viewer written in Red"
	source [file!] "Filename to view"
][
	resize: does [maybe host/size: host/parent/size - 20]
	; resize: does [maybe host/size: host/parent/size - 20x60]
	view/flags reshape [
		title @[rejoin ["RedMark - " to-local-file clean-path source]]
		on-resize :resize on-resizing :resize
		below
		host: host 600x400 [
			style code-box: box color= opaque 'text 5% align= -1x0 margin= 10
			; scrollable content-flow= 'vertical [vlist @[decode-markdown read/lines source]]
			list-view with [
				slide-length: 800
				pages: 30
				wrap-data: func [data] [data]
				source: lay-out-vids @[decode-markdown read/lines source]
			]
		]; on-over [status/text: mold hittest host/space event/offset]
		; status: text 600x30
		at 0x0 text 0x0 rate 0:0:3 on-time [prof/show prof/reset]
	] 'resize
]

system/script/header: object [	 						;@@ workaround for #4992
	title:   "Red Mark"
	author:  @hiiamboris
	license: 'BSD-3
]

cli/process-into red-mark
