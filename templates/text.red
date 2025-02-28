Red [
	title:    "Text template for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.templates.text
	depends:  spaces.templates
]

declare-template 'text [

	valid-flag: ['ellipsize | 'bold | 'italic | 'underline | 'strike]	;-- wrapping mode is decided by the canvas, not flags
	
	spec: [
		text:    {}		#type [any-string!] "Text to display"
			; #on-change [space word new [any-type!]] [
				; space/content: make-space 'text [text: form :new]
			; ]
		content: make-space 'space []	#type [object!] (space? content) "Space that /data translates into"
		;@@ could be better to just let /content accept any-type which gets auto-translated into a space on assignment?
	]
	
	config: make templates/space/config [
		flags: []		#type [block!] (parse flags [any valid-flag])
		font:  none		#type [object! (font? font) string! none!]
	]
	
	tools: object [
		set-font-size: function [
			space [object!]
			size  [integer!]									;-- Red doesn't support float sizes yet
		][
		]
	
		make-rich-text: function [
			"Create a new lightweight rich-text face"
			/wrap "Enable word wrapping"
		] bind [
			make either wrap [wrapped-face!][unwrapped-face!] rtd-template
		] context [
			;; rtd-layout is slow! about 200 times slower than object creation (it also invokes VID omg)
			;; just make face! is 120 times slower too, because of on-change handlers
			;; rich text does not require any of that however, so I mimick it using a non-reactive object
			;; achieved construction time is 16us vs 200us
			wrapped-face!: construct map-each w exclude words-of :face! [on-change* on-deep-change*] [to set-word! w]
			unwrapped-face!: copy wrapped-face!
			wrapped-face!/para:   make para! [wrap?: on]		;-- not copied, so can't be modified for each face in place
			unwrapped-face!/para: make para! [wrap?: off]
			rtd-template: compose [
				on-change*:      does []						;-- for whatever reason, crashes without this
				on-deep-change*: does []
				(system/view/VID/styles/rich-text/template)
			]
		]
		
		measure-text: function [								;@@ replaces 'size-text'; see #4841, #5245 on all kludges included here
			"Get size of the text in LAYOUT"
			layout  [object!] "Note that /size/x may affect trailing whitespaces measurement"
			return: [point2D!]
		][
			size1: size-text layout
			size2: to point2D! caret-to-offset/lower layout length? layout/text	;-- include trailing whitespaces
			if layout/size [size2/x: min size2/x layout/size/x]		;-- but not beyond the allowed width
			max size1 size2
		]
	
		word-width?: function [
			"Get width in pixels of the widest word in LAYOUT's /text"
			layout  [object!] "A rich-text face" (:layout/type = 'rich-text)
			return: [float!]
		] with [
			space: exclude charsets/uni-white charset "^/"
		][                                                                                
			size': layout/size									;@@ use 'pretending'
			text: to string! text': layout/text
			parse/case text [any [thru space p: (p/-1: #"^/")]]	;@@ can't use 'change' rule - #4836
			quietly layout/text: text
			quietly layout/size: INFxINF
			width: first measure-text layout
			quietly layout/size: size'
			quietly layout/text: text'
			width
		]
		
		;; limitation: rich-text is very flexible, and can mix different fonts and sizes arbitrarily
		;;   thus, it's impossible to exactly tell which font should be used for ellipsis until that ellipsis is in the text
		;;   so only /font is used for size estimation, not the /flags
		;; 2 modes of ellipsization:
		;;   1. when wrapping is on - add ellipsis to the last visible line if text doesn't fit vertically
		;;   2. when wrapping is off - same but also ellipsize each line horizontally
		;@@ maybe use the ellipsis char "…" ?
		ellipsize: function [
			"Ellipsize /text in LAYOUT to fit its /size (left unchanged if already fits)"
			layout  [object!]  "A rich-text face" (:layout/type = 'rich-text)
			return: [point2D!] "Resulting text size"
		] with [
			;; measuring "..." (3 dots) is unreliable for whatever reason, probably due to some rounding
			;; to avoid the ellipsis disappearing randomly I add 2 more dots to it, which seems to work, though increases padding
			ellipsis-layout: make-rich-text
			ellipsis-layout/text: "……"							;-- experimentally found: "..…" or ". …" isn't enough, "……" is
			space-layout: make-rich-text
			space-layout/text: " "
			;; prefer insignificant clipping over ellipsization; also 'size-text' may return result bigger than /size by some subpixel
			tolerance: 1										;@@ ideally, font-dependent
		][
			;@@ where to optimize for empty string?
			;; edge cases:
			;; - when canvas is less than one line in height, ellipsization won't help with it
			;; - when canvas is less than ellipsis width, full ellipsis can be used, as it will be clipped by canvas anyway
			;; - when last line is less than 3 chars (e.g. "a^/b^/cd"), dots may be mapped to non-linefeed characters
			;;   but I'm not doing that and ellipsizing only the last non-empty line (supposed to be returned by size-text)
			;; - in any case, replaced characters may be narrower than dots, and ellipsization will increase the size (how to prevent?)
			;; also: size-text/x should never be bigger than layout/size/x in multiline layouts, so x-check only applies to unwrapped text
			text-size: size-text layout							;-- result is affected by para/wrap+size/x but may exceed the layout/size
			nlines:    rich-text/line-count? layout
			limit:     tolerance + layout/size
			wrapped?:  text-size/x <= limit/x
			if all [
				wrapped?
				any [
					text-size/y <= limit/y
					nlines <= 1
				]
			] [return text-size]								;-- no ellipsization is needed
			
			quietly space-layout/font:    layout/font
			quietly ellipsis-layout/font: layout/font
			space-width:    first size-text ellipsis-layout
			ellipsis-width: first size-text ellipsis-layout
			
			;; wrapped and unwrapped case: ellipsization of the last line...
			if text-size/y > limit/y [
			
				;; find out what are the extents of the last visible line:
				last-visible-char: -1 + offset-to-char layout layout/size
				last-line-dy: second caret-to-offset/lower layout last-visible-char
				
				;; if last visible line is too much clipped, discard it an choose the previous line (if one exists)
				if over?: last-line-dy - tolerance > layout/size/y [
					last-line-dy: second caret-to-offset layout last-visible-char
				]
					
				;; aim at the char that's going to be preceding the ellipsis
				;; go 1px above line's top/bottom, but not into negative (at least 1 line should be visible even if fully clipped)
				ellipsis-location: max 0 as-point2D layout/size/x - ellipsis-width last-line-dy - 1
				last-visible-char: -1 + offset-to-char layout ellipsis-location
				
				if wrapped? [
					;; last word may have been wrapped to the next line, so we should keep part of it that fits before the ellipsis
					last-visible-char-xy:  caret-to-offset       layout last-visible-char
					last-visible-char-dxy: caret-to-offset/lower layout last-visible-char
					width-to-fill: ellipsis-location/x - last-visible-char-xy/x - space-width
					if width-to-fill > 1 [
						next-line-y: last-visible-char-dxy/y + 1
						last-visible-char: -1 + offset-to-char layout width-to-fill . next-line-y
					]
				]
				
				new-text: copy/part layout/text last-visible-char + 1
				change top new-text "…"							;-- singular ellipsis runs no risk of spanning 2-3 lines
				quietly layout/text: new-text
				text-size: size-text layout
				#assert [(second caret-to-offset/lower layout length? new-text) <= limit/y  "ellipsis wrap detected"]
				;@@ maybe cut another char in this error case?
			]
			
			if text-size/x > limit/x [							;-- unwrapped case: ellipsization also of all long lines
				;; don't change it in place to avoid on-change calls
				;; for this to work, have to traverse the text bottom-up
				either new-text
					[quietly layout/text: ""]					;-- temporary
					[new-text: copy layout/text]
				
				;; go line by line and check every line's length
				y: layout/size/y - 1
				while [y > 0] [
					clipped-char: offset-to-char layout limit/x . y
					clipped-xy1:  caret-to-offset       layout clipped-char
					clipped-xy2:  caret-to-offset/lower layout clipped-char
					line-width: clipped-xy2/x
					if line-width > limit/x [
						last-visible-char: offset-to-char layout max 0 layout/size/x - ellipsis-width . y
						bgn: at new-text last-visible-char
						end: any [find bgn #"^/"  tail bgn]
						change/part bgn "..." end
					]
					y: clipped-xy1/y - 1
				]
				
				quietly layout/text: new-text
				text-size: size-text layout						;@@ because I disabled on-change, this is required for caret measurements
			]
				
			text-size
		]
		
		draw: function [
			space   [object!] 
			canvas  [map!]
			return: [object!] "A rich-text face"
		][
			ellipsize?: find flags: space/config/flags 'ellipsize
; wrap?:      off
			wrap?:      canvas/x <> 'free
			layout:     apply 'make-rich-text [/wrap wrap?]
			flags:      compose [(1 thru length? space/text) (flags)]
			remove find flags 'ellipsize
			quietly layout/text:  space/text
			quietly layout/size:  canvas/size
			quietly layout/flags: flags
			quietly layout/font:  space/config/font
			either ellipsize? [
				text-size: ellipsize layout						;-- min. word width doesn't apply to ellipsized text
			][
				text-size: size-text layout
				if wrap? [										;-- no-wrap mode relies on line width, not word width
					min-width: word-width? layout
					if min-width > text-size/x [
						text-size/x: min-width
						text-size: size-text layout
					]
				]
			]
			frame: make map! compose/deep [
				size:   (text-size)
				drawn:  [text 0x0 (layout)]
				layout: (layout) 
			]
		]
	]

	do reshape [
		VID/styles/text: [
			template: text
			facets: [
				string!		text
				ellipsize	[VID/add-flag self 'ellipsize]
				font-size   @[
					[size [integer!]] -> [
						default config/font: font!
						VID/set-facet self 'config/font/size @[size]
					]
				]
				@(VID/common/facets/font-styles)
			]
		]
	]
]

define-styles [
	; text: box (frame: 2 padding: 3 margin: 3 fill: blue)
	text: box (center: space)
]
