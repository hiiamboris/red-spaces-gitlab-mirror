Red [
	title:    "Layout functions for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.layouts
	depends:  [spaces.rendering  reshape classy-object]
]


layout-settings!: copy classy-object!

layouts: to map! to block! object [								;@@ REP #165

	;@@ benchmark it - if type checking is acceptable (though I rely on caching, but for grids it's still critical)
	;; 'box' is the most ubiquitous layout which adds a frame around a single space
	;; when canvas 'fill' is requested, it stretches the box to fill the canvas even if content does not do that
	box: object [
		; settings: declare-class 'layout-settings-box with :with-space [
		settings: declare-class 'layout-settings-box [
			;@@ in theory I could use 'scale' to support planar! frame, but is it useful? and it'll distort pen pattern
			padding:	0		#type [planar! ((0,0) +<= padding) linear! (0 <= padding)]	;-- spacing between the frame and the edge
			margin:		0		#type [planar! ((0,0) +<= margin) linear! (0 <= margin)]	;-- spacing between the frame and the content
			frame:		0		#type [linear! (0 <= frame)]	;-- outside frame thickness (adds to padding/margin!)
			;@@ negative 'focus' values reserved to put it into the 'padding' area
			focus:		0		#type [linear! (0 <= focus)]	;-- focal frame thickness (adds to margin)
			rounding:	0		#type [linear! (0 <= rounding)]	;-- boxes corner radius
			
			;@@ support pattern pen and fill
			pen:		none	#type [none! tuple!]			;-- frame color (none = inherits current pen, trasparent = force no color)
			fill:		glass	#type [none! tuple!]			;-- background color (none = inherits current pen, trasparent = force no color)
			; frame-pen:		reserved
			; focal-pen:		reserved
			; focal-geometry:	reserved
			; shadow-pen:		reserved
			shadow:		none	#type [planar! none!]			;-- shadow offset; or none to disable it
			; shadow-blur:		reserved
			
			center:		none	#type [none! object!]			;-- space (content) to put inside the frame  ;@@ or rename to 'content'?
			;@@ or get rid of center?
		]
		
		;@@ can I split some functionality out of this func? it's too complicated for the simplest of layouts
		make: function [
			"Make a new BOX layout with given SETTINGS"
			space    [object!]
			canvas   [map!]
			settings [object!]
		] with rendering [
			!: settings											;-- 'settings' is way too verbose here
			padding: to point2D! !/frame + !/margin + !/padding + !/focus
			draw-canvas: reduce-canvas canvas padding * 2		;-- subtract paddings from the drawing canvas
			space: any [!/center space]							;-- default to 'space' when no /center is provided
			draw:  any [
				:templates/(space/type)/tools/draw
				:templates/space/tools/draw						;-- space may omit /draw to be fully drawn via layout
			]
			frame: (draw space draw-canvas)						;-- mind the 'draw' arity, which may be wrong
			frame/size: (draw-size: frame/size) + (padding * 2)	;-- add box+frame to size even if it's transparent
			if canvas/mode = 'fill [
				frame/size: fill-canvas frame/size canvas
				padding: frame/size - draw-size / 2
			]
			if any [not zero? padding !/fill <> glass] [		;-- only draw box+frame when visible
				; ?? [padding frame/size canvas/size draw-size]
				frame/drawn: reshape [
					push [
						push [
							fill-pen off
							pen @(styling/assets/pens/checkered)
							line-width @[!/focus]
							box @[start: !/margin + !/focus * (0.5, 0.5) + !/padding + !/frame]	;-- center focus frame in the margin
								@[frame/size - start]
								@[!/rounding]			/if !/rounding > 0
						]								/if !/focus > 0
						fill-pen   @[!/fill]			/if !/fill			;-- when not set, inherited from above
						pen        @[!/pen]				/if !/pen			;-- ditto
						line-width @[!/frame]								;-- always set, to avoid inheriting from above
						shadow @[to pair! !/shadow] 3 0.0.0	/if !/shadow	;@@ shadow does not yet support point2D or word colors
						box @[start: !/frame * (0.5, 0.5) + !/padding]
							@[frame/size - start]
							@[!/rounding]				/if !/rounding > 0
					]									/if any [!/frame > 0  !/fill <> glass  !/shadow] 
					translate @[padding]				/if not zero? padding
					@[frame/drawn]
				]
			]
			frame
		]
	]
	
]
	
