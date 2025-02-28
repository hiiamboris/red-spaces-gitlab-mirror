Red [
	title:    "Button template for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.templates.button
	depends:  spaces.templates
]

declare-template 'button [
	spec: [
		focusable?:	yes		#type [logic!] "Can be focused by default"
		;@@ enforce constraints on depth or just clip it in the draw func? general design question; enforcement simplifies layout spec
		depth:		0%		#type [percent!] (0% -<= depth -<= 100%) "Used to animate button press: 0% (released) to 100% (pushed down)"
		data:		{}		#type "Text or other value to display within"
			; #on-change [space word new [any-type!]] [
				; space/content: make-space 'text [text: form :new]
			; ]
		content: make-space 'space []	#type [object!] (space? content) "Space that /data translates into"
		;@@ could be better to just let /content accept any-type which gets auto-translated into a space on assignment?
	]
	config: make templates/space/config [
		; rounding: 5		#type [linear!] {Outer frame rounding radius (px)}	;@@ can I have type checking in config?
	]
	tools: object [
		; draw: function [space [object!] canvas [map!]] [
			; frame: make map! compose [
				; size:  100x100
				; drawn: [fill-pen beige box 0x0 100x100 circle 50x50 45]
			; ]
		; ]
	]
]

define-styles with spaces/ctx [
	button: box (
		frame:    0.5
		margin:   3
		fill:     opaque 'panel 100%
		; padding:  3 * space/depth
		padding:  5
		shadow:   (-2,-2) * space/depth + 1
		rounding: 4
		focus:    pick [2 0] focused? space
		center:   space/content
	)
]

spaces/VID/styles/button: #[
	template: button
	facets: #[
		string!	text
	]
]