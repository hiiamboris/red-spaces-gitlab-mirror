Red [
	title:   "COLOR-PICKER widget for Spaces"
	author:  @hiiamboris
	license: BSD-3
]

; #include %../everything.red

context expand-directives with spaces/ctx [
	on-HSL-change: function [space word value] [
		if unset? :space/spaces [exit]					;-- uninitialized yet
		if space =? try [get bind 'space :on-rgb-change] [exit]	;-- avoid being triggered by on-rgb-change
		hue: space/hue // 360
		sat: clip 0 1   space/saturation
		lgt: clip 0 1   space/lightness
		space/color:    HSL2RGB/tuple as-point3D 1 * hue 1 * sat 1 * lgt	;-- convert from % into float
		invalidate/only space/spaces/lightness
		invalidate      space/spaces/palette
	]
	
	on-color-change: function [space word value] [
		if unset? :space/spaces [exit]					;-- uninitialized yet
		if space =? try [get bind 'space :on-HSL-change] [exit]	;-- avoid being triggered by on-hsl-change
		do-atomic [										;-- disallow reactions until all 3 values are set
			hsl: RGB2HSL value
			space/hue:        hsl/1
			space/saturation: hsl/2
			space/lightness:  hsl/3
		]
		invalidate/only space/spaces/lightness
		invalidate      space/spaces/palette
	]
	
	declare-template 'color-picker/tube [
		axes:       [s e]
		margin:     0
		spacing:    10
		hue:        0		#type =? [number!] :on-HSL-change	;-- not constrained here, but internally during conversions
		saturation: 0%		#type =? [number!] :on-HSL-change
		lightness:  50%		#type =? [number!] :on-HSL-change
		color:      gray	#type =? [tuple!]  :on-color-change
		spaces: object mapparse/deep [set x issue!] [
			lightness: make-space 'rectangle [
				type:  'lightness
				weight: 0
				drop: function [offset [planar!]] [
					parent/lightness: 100% * clip 0 1 offset/x / size/x
				]
				draw: function [/on canvas fill-x fill-y] [		;@@ use the fill flags?
					width: first finite-canvas canvas
					self/size: width . 20
					pos: clip 3 width - 3 width * parent/lightness
					compose [
						line-width 1
						fill-pen linear #000 #FFF box 0x0 (size)	;-- lightness scale
						fill-pen off box (pos - 3 . 0) (pos + 3 . 20)	;-- selected value outline ;@@ or draw arrows below/above?
					]
				]
			]
			palette: make-space 'rectangle [
				type:  'palette
				weight: 1
				drop: function [offset [planar!]] [
					parent/saturation: 100% - clip 0 1 offset/y / size/y
					parent/hue:         360 * clip 0 1 offset/x / size/x
				]
				draw: function [/on canvas fill-x fill-y /local x] [	;@@ use the fill flags?
					width: first canvas: finite-canvas canvas
					height: either fill-y [canvas/y][0]
					self/size: width . height
					hue: clip 0 1 parent/hue / 360 // 1
					sat: clip 0 1 (1 - parent/saturation)
					lgt: clip 0 1 parent/lightness
					shade: either 0.5 >= lgt
						[    lgt * 2 * #000000FF]
						[1 - lgt * 2 * #000000FF + #FFF]
					pos: as-point2D width * hue height * sat
					drawn: compose [
						line-width 1
						fill-pen linear #F00 #FF0 #0F0 #0FF #00F #F0F #F00	;-- tuples hardcoded to withstand possible override
						box 0x0 (size)					;-- palette itself
						fill-pen linear #808080FF #80808000 0x0 (0 . size/y)
						box 0x0 (size)					;-- fade into gray
						fill-pen (shade) box 0x0 (size)	;-- darkening/whitening by lightness
						fill-pen off clip 0x0 (size) circle (pos) 4	;-- selected color outline
					]
				]
			]
		] [hex-to-rgb x]
		content: reduce with spaces [lightness palette]
	]
	
	define-handlers [
		color-picker: [
			lightness: [
				on-down [space path event] [start-drag path space/drop path/2]	;-- drag to accept over events outside
				on-over [space path event] [if dragging? [space/drop path/2]]
				on-up   [space path event] [stop-drag]
			]
			palette: [
				on-down [space path event] [start-drag path space/drop path/2]
				on-over [space path event] [if dragging? [space/drop path/2]]
				on-up   [space path event] [stop-drag]
			]
		]
	]
	
	; view [host [picker: color-picker 200x200]]
]
