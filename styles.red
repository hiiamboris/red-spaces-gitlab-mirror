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
	;-- `compose` readability helper variant 2
	when: func [test value] [either :test [do :value][[]]]

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
		root [				;@@ how to name the root style? maybe slash `/`? it should be unique..
			pen      !(svmc/text)
			fill-pen !(svmc/panel)
			font !(make font! [name: svf/system size: svf/size])
			line-width 2
		]
		; paragraph [pen green]
		; list [pen green]
		; thumb [(probe self/size/x: 30 ()) pen blue]
		; back-arrow [(self/size: 30x30)]
		; hscroll [(self/size/y: 30 ())]
		; vscroll [(self/size/x: 30 ())]
		paragraph [
			;-- font can be set in the style!:
			(self/font: serif-12 ())			;@@ #3804 - requires self/ or won't work
			pen blue
		]
		; list-view/item/paragraph [pen blue]
		list/item [pen cyan]
		button [
			; fill-pen (pushed? | (svmc/text + 0.0.0.120) | 'off)
			; fill-pen (pushed? |y (svmc/text + 0.0.0.120) |n 'off)
			fill-pen (either pushed? [svmc/text + 0.0.0.120]['off])
				; [pattern 4x4 [pen off fill-pen black box 0x0 2x2 box 2x2 4x4]]	;@@ not working, #4828
		]
		table [
			; fill-pen (svmc/text + 0.0.0.120)
			box 0x0 (size)
		]
		table/headers/list [
			fill-pen (svmc/text + 0.0.0.120)
			pen off
			box 0x0 (size)
		]
		table/columns/list [
			fill-pen (svmc/text + 0.0.0.200)
			pen off
			box 0x0 (size)
		]
		table/headers/list/row/item
		table/columns/list/row/item [
			fill-pen (svmc/panel)
			pen off
			box 0x0 (size)
		]
	]
	
	set 'closures reshape [		;-- closures come after the main drawing code
		; hscroll/thumb vscroll/thumb [
		; 	(when focused?/parent [compose/deep [
		; 		push [
		; 			;@@ MEH DOESNT WORK YET -- CHECK PATTERN PEN WHEN IT"S FIXED
		; 			; pen pattern 4x4 [line-width 0 fill-pen black box 0x0 2x2 box 2x2 4x4]
		; 			; fill-pen 0.100.200.200
		; 			; line-width 0
		; 			; box 0x0 (size)
		; 			; line-width 2
		; 			line-width 0
		; 			fill-pen !(svmc/text + 0.0.0.100)
		; 			box 4x3 (size - 4x3)
		; 			line-width 2
		; 		]
		; 	]])
		; ]	
	]

	do with [table: none] [
		foreach table [styles closures] [						;-- replace words with paths
			set table map-each/only [w [word!]] get table [to path! w]
		]
	]

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

get-style: function [
	"Fetch styling code for the current space being drawn"
	/named path [path! block!] "Path to look for (defaults to current-style)"
	/closing "Fetch a closure instead"
][
	table: either closing [closures][styles]
	path: tail as path! either named [path][current-style]
	#assert [not head? path]
	until [												;-- look for the most specific fitting style
		p: back path
		style: any [find/only table p  style]
		head? path: p
	]
	unless style [return []]
	style: first find style block!
	#assert [block? style]
	space: get last path								;-- need to expose it's context to the style
	; print ["style for " head path "is" mold style]
	compose/deep bind style space			;@@ how slow this bind will be? any way not to bind?
]

set-style: function [name [word! path!] style [block!]] [
	name: to path! name
	pos: any [											;-- `put` does not support paths/blocks so have to reinvent it
		find/only/tail styles name
		insert/only tail styles name
	]
	change/only pos style
]

get-style-name: function [
	"Transform MAP name into STYLE name"
	name [word!]
][
	space: get name
	all [
		new-name: select space 'style 					;-- allow space to enforce it's style
		name <> new-name
		;-- enforced name has to not to leak into globals and should have the same value as the name in map
		return anonymize new-name space					;@@ any easier way?
	]
	name
]

;-- draw code has to be evaluated after current-style changes, for inner calls to render to succeed
render: function [space [word!] /as style [word!] /only xy1 [pair!] xy2 [pair!] /draw cmds [block! function!]] [
	either style [
		style: anonymize style space: get space
	][
		style: space
		space: get space
	]
	append current-style style			;-- used by get-style
	#assert [space? space]
	style: get-style					;-- call it before calling draw or draw/only, in case it modifies smth
	draw: any [:cmds :space/draw]
	all [
		only
		function? :space/draw
		find spec-of :draw /only
		draw: draw/only xy1 xy2
	]
	r: compose/deep [push [(style) (draw) (get-style/closing)]]		;-- push should shield from style propagation
	take/last current-style
	;@@ TODO: after error cleanup
	:r
]


