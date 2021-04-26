Red [
	title:   "Default styles for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ needs: map-each, anonymize, reshape

current-style: as path! []	;-- used as a stack during draw composition

do with [
	svmc: system/view/metrics/colors
	svf:  system/view/fonts
	serif-12: make font! [name: svf/serif size: 12]

	;-- very experimental `either` shortener: logic | true-result | false-result
	|: make op! func [a b] [
		switch/default :a [
			#[true] [:b]
			#[false][true]
		] [:a]
	]

	;-- very experimental `either` shortener: value |y true-result |n false-result
	; |y: make op! func [a b] [either :a [:b][:a]]
	; |n: make op! func [a b] [either :a [:a][:b]]
][

	;-- styles should balance between readability, ease of extension and lookup speed
	;-- benchmarks prove that if we define styles as words sequences, lookups are 5x slower (find, parse)
	;-- (because find [a b c [style]] [b] finds the wrong style and requires another inner loop)
	;-- so we should either use paths ('item/subitem) or blocks [item subitem]
	;-- using paths we get another benefit: we can apply the same style to multiple spaces (e.g. hscroll vscroll [style..])
	;-- drawback is that we have to convert words into paths at startup to keep it both readable and efficient
	set 'styles reshape [		;-- styles come before the main drawing code
		host [[
			pen      !(svmc/text)
			fill-pen !(svmc/panel)
			font !(make font! [name: svf/system size: svf/size])
			line-width 2
		]]
		; paragraph [pen green]
		; list [pen green]
		; thumb [(probe self/size/x: 30 ()) pen blue]
		; back-arrow [(self/size: 30x30)]
		; hscroll [(self/size/y: 30 ())]
		; vscroll [(self/size/x: 30 ())]
		paragraph [[
			;-- font can be set in the style!:
			;-- but impossible to debug it, as probe draw lists font with thousands of parents
			; (self/font: serif-12 ())			;@@ #3804 - requires self/ or won't work
			pen blue
		]]
		; list-view/item/paragraph [pen blue]
		list/item [[pen cyan]]
		; button [[
		; 	; fill-pen (pushed? | (svmc/text + 0.0.0.120) | 'off)
		; 	; fill-pen (pushed? |y (svmc/text + 0.0.0.120) |n 'off)
		; 	fill-pen (either pushed? [svmc/text + 0.0.0.120]['off])
		; 		; [pattern 4x4 [pen off fill-pen black box 0x0 2x2 box 2x2 4x4]]	;@@ not working, #4828
		; ]]
		button [
			function [btn] [
				drawn: btn/draw
				bgnd: either btn/pushed? [svmc/text + 0.0.0.120]['off]
				unset 'focus
				if focused? [
					focus: compose/deep [
						line-width 1
						fill-pen off
				        ; pen pattern 6x6 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0 12x12 fill-pen (svmc/panel) box 3x0 9x3 box 3x9 9x12 box 0x3 3x9 box 9x3 12x9]
				        pen pattern 4x4 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0  8x8  fill-pen (svmc/panel) box 1x0 5x1 box 1x5 5x8  box 0x1 1x5 box 5x1  8x5]
				        ; pen pattern 2x2 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0  4x4  fill-pen (svmc/panel) box 1x0 3x1 box 1x3 3x4  box 0x1 1x3 box 3x1  4x3]
						box 3x3 (btn/size - 3)
					]
				]
				compose/only [
					fill-pen (bgnd)
					push (drawn)
					(:focus)
				]
				; [pattern 4x4 [pen off fill-pen black box 0x0 2x2 box 2x2 4x4]]	;@@ not working, #4828
			]
		]
		table [[
			; fill-pen (svmc/text + 0.0.0.120)
			box 0x0 (size)
		]]
		table/headers/list [[
			fill-pen (svmc/text + 0.0.0.120)
			pen off
			box 0x0 (size)
		]]
		table/columns/list [[
			fill-pen (svmc/text + 0.0.0.200)
			pen off
			box 0x0 (size)
		]]
		table/headers/list/row/item
		table/columns/list/row/item [[
			fill-pen (svmc/panel)
			pen off
			box 0x0 (size)
		]]
		grid [[
			fill-pen (svmc/text + 0.0.0.120)
			pen off
			box 0x0 (size)
		]]
		cell [[
			fill-pen (svmc/panel)
			box 0x0 (size)
		]]
		; cell [
		; 	function [cell] [
		; 		drawn: cell/draw			;-- should come before (size) gets known
		; 		bgnd: compose [
		; 			fill-pen (svmc/panel)
		; 			box 0x0 (cell/size)
		; 		]
		; 		compose [(bgnd) (drawn)]	;-- composed order differs from evaluation order!
		; 	]
		; ]
	]
	
	; set 'closures reshape [		;-- closures come after the main drawing code
	; 	; hscroll/thumb vscroll/thumb [
	; 	; 	(when focused?/parent [compose/deep [
	; 	; 		push [
	; 	; 			;@@ MEH DOESNT WORK YET -- CHECK PATTERN PEN WHEN IT"S FIXED
	; 	; 			; pen pattern 4x4 [line-width 0 fill-pen black box 0x0 2x2 box 2x2 4x4]
	; 	; 			; fill-pen 0.100.200.200
	; 	; 			; line-width 0
	; 	; 			; box 0x0 (size)
	; 	; 			; line-width 2
	; 	; 			line-width 0
	; 	; 			fill-pen !(svmc/text + 0.0.0.100)
	; 	; 			box 4x3 (size - 4x3)
	; 	; 			line-width 2
	; 	; 		]
	; 	; 	]])
	; 	; ]	
	; ]

	map-each/only/self [w [word! ]] styles [to path! w]	;-- replace words with paths
	map-each/only/self [b [block!]] styles [do b]		;-- extract blocks, construct functions

]


set 'focused? function [
	"Check if current style is the one in focus"
	/parent "Rather check if parent style is the one in focus"
	;@@ will /parent be enough or need more levels?
][
	all [
		name1: last keyboard/focus						;-- order here: from likely empty..
		name2: either parent [							;-- ..to rarely empty (performance)
			pick tail current-style -2
		][	last current-style
		]
		(get name1) =? get name2
	]													;-- result: true or none
]

style-typeset!: make typeset! [block! function!]	;@@ hide this

;@@ TODO: profile & optimize this a lot
;@@ rename current-style to current-path? as it's not really a style per se..
get-style: function [
	"Fetch styling code object for the current space being drawn"
	/named path [path! block!] "Path to look for (defaults to current-style)"
][
	path: tail as path! either named [path][current-style]
	#assert [not head? path]
	until [												;-- look for the most specific fitting style
		p: back path
		style: any [find/only styles p  style]
		head? path: p
	]
	unless style [return []]
	style: first find style style-typeset!				;-- style groups support
	#debug styles [#print "Style for (p) is (mold/flat :style)"]
	:style
]

set-style: function [name [word! path!] style [block!]] [
	name: to path! name
	pos: any [											;-- `put` does not support paths/blocks so have to reinvent it
		find/only/tail styles name
		insert/only tail styles name
	]
	change/only pos style
]

;-- draw code has to be evaluated after current-style changes, for inner calls to render to succeed
context [
	with-style: function [
		"Draw calls should be wrapped with this to apply styles properly"
		name [word!] code [block!]
	][
		append current-style name
		trap/all/catch code [
			msg: form/part thrown 400						;@@ should be formed immediately - see #4538
			#print "^/*** Failed to render (name)!^/(msg)"
		]
		take/last current-style
	]

	render-face: function [
		face [object!] "Host face"
		/only xy1 [pair! none!] xy2 [pair! none!]
	][
		#assert [is-face? :face]
		#assert [face/type = 'base]
		#assert [in face 'space]
		#assert [empty? current-style]

		with-style 'host [
			host-style: compose/deep bind get-style face	;-- host style can only be a block
			space-style: render-space/only face/space xy1 xy2
			render: reduce [host-style space-style]
		]
		any [render []]
	]

	render-space: function [
		name [word!] "Space name pointing to it's object"
		/only xy1 [pair! none!] xy2 [pair! none!]
	][
		space: get name
		#assert [space? :space]

		with-style name [
			style: get-style							;-- call it before calling draw or draw/only, in case it modifies smth
			either block? :style [
				style: compose/deep bind style space	;@@ how slow this bind will be? any way not to bind? maybe construct a func?
				draw: select space 'draw
				all [
					only
					function? :draw
					find spec-of :draw /only
					draw: draw/only xy1 xy2
				]
				render: reduce [style draw]				;-- call the draw function if not called yet
			][
				#assert [function? :style]
				render: (style space)					;@@ TODO: /only support for it?
			]
		]
		any [render copy []]
	]

	set 'render function [
		space [word! object!] "Space name; or host face as object"
		/only xy1 [pair! none!] xy2 [pair! none!]
	][
		render: either word? space [:render-space][:render-face]
		render/only space xy1 xy2
	]
]
