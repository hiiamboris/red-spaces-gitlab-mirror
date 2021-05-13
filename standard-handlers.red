Red [
	title:   "Standard event handlers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires events.red (on load)


define-handlers [

	;-- *************************************************************************************
	scrollable: [
		on-down [space path event] [
			set [_: _: item: _: subitem:] path
			case [
				find [hscroll vscroll] item [					;-- move or start dragging
					move-by: :scrollable-space/move-by
					axis: select get item 'axis
					switch subitem [
						forth-arrow [move-by space 'line 'forth axis  update]
						back-arrow  [move-by space 'line 'back  axis  update]
						forth-page  [move-by space 'page 'forth axis  update]
						back-page   [move-by space 'page 'back  axis  update]
					]
					start-drag/with path space/origin
				]
				item = space/content [
					start-drag/with path space/origin
					pass
				]
			]
		]
		on-up [space path event] [stop-drag pass]
		on-over [space path event] [
			unless dragging? [pass exit]			;-- let inner spaces handle it
			set [_: _: item: _: subitem:] path
			either find [hscroll vscroll] item [
				unless subitem = 'thumb [exit]		;-- do not react to drag of arrows (used by timer)
				scroll: get item
				map: scroll/map
				x: scroll/axis
				size1: scroll/size/:x - map/back-arrow/size/x - map/forth-arrow/size/x - map/thumb/size/x
				cspace: get space/content
				scs: cspace/size
				size2: scs/:x - space/map/(space/content)/size/:x
				ofs: drag-offset skip path 2		;-- get offset relative to the scrollbar
				ofs: ofs * select [x 1x0 y 0x1] x	;-- project offset onto the axis
				ofs: ofs * -1 * size2 / (max 1 size1)	;-- scale scrollbar inner part to the whole content
			][
				ofs: drag-offset path				;-- content is dragged directly
			]
			space/origin: drag-parameter + ofs
			update
		]
		on-key-down [space path event] [
			; unless single? path [pass exit]
			move-by: :scrollable-space/move-by
			move-to: :scrollable-space/move-to
			code: switch event/key [
				down       [[move-by space 'line 'forth 'y]]
				up         [[move-by space 'line 'back  'y]]
				right      [[move-by space 'line 'forth 'x]]
				left       [[move-by space 'line 'back  'x]]
				page-down  [[move-by space 'page 'forth 'y]]
				page-up    [[move-by space 'page 'back  'y]]
				home       [[move-to space 'head]]
				end        [[move-to space 'tail]]
			]
			either code [
				do code
				update
			][
				pass								;-- key was not handled (useful for tabbing)
			]
		]
		on-wheel [space path event] [
			scrollable-space/move-by/scale
				space
				'line
				pick [forth back] event/picked <= 0
				pick [x y] 'hscroll = path/3
				absolute event/picked * 4
			update		;@@ TODO: only update when move succeeded
		]
		scroll-timer: [
			on-time [space path event delay [percent!]] [	;-- press & hold way of scrolling
				unless dragging? [exit]
				set [spc: _: item: _: subitem:] drag-path
				unless spc =? path/-1 [exit]				;-- dragging started inside another space - ignore it
				scrollable-space/move-by/scale
					get path/-1
					switch/default subitem [back-page forth-page ['page] back-arrow forth-arrow ['line]] [exit]
					switch subitem [back-arrow back-page ['back] forth-arrow forth-page ['forth]]
					any [select [hscroll x vscroll y] item  exit]
					delay + 100%
				update
			]
		]
	]

	;-- *************************************************************************************
	;@@ TODO: when dragging and roll succeeds, the canvas jumps
	;@@       need to update drag-parameter from `roll` or something..
	inf-scrollable: extends 'scrollable [	;-- adds automatic window movement when near the edges
		on-down     [space path event] [if update? [space/roll]]	;-- after button clicks
		on-key-down [space path event] [if update? [space/roll]]	;-- during key holding
		roll-timer: [
			on-time [space path event delay] [			;-- during scroller dragging
				space: get path/-1
				if space/roll [update]
			]
		]
	]

	;-- *************************************************************************************
	list-view: extends 'inf-scrollable [
		;@@ just a temporary collapsing test - remove it later!
		; list: [
		; 	item: [
		; 		on-click [space path event] [
		; 			space/limits/max/y: unless space/limits/max/y [20]
		; 			update
		; 		]
		; 	]
		; ]
	]

	;-- *************************************************************************************
	table: [
		columns: extends 'list-view []
	]

	;-- *************************************************************************************
	grid-view: extends 'inf-scrollable []

	;-- *************************************************************************************
	button: [
		on-down [space path event] [
			space/pushed?: yes
			start-drag path
			update
		]
		on-up [space path event] [
			stop-drag
			space/pushed?: no
			update
		]
		; on-click [space path event] [
		; 	do space/command
		; ]
		on-key [space path event] [
			if all [
				find " ^M" event/key
				not space/pushed?
			][
				space/pushed?: yes
				update
			]
		]
		on-key-up [space path event] [
			if all [
				find " ^M" event/key
				space/pushed?
			][
				space/pushed?: no
				update
			]
		]
	]


	;-- *************************************************************************************
	rotor: [
		ring: [
			on-down [space path event] [
				rotor: get path/-2
				start-drag/with path (rotor/angle - path/2/x) // 360
			]
			on-up [space path event] [stop-drag]
			on-over [space path event] [
				unless dragging? [exit]
				rotor: get path/-2
				rotor/angle: (path/2/x + drag-parameter) // 360
				update
			]
		]
	]


	;-- *************************************************************************************
	field: [
		;-- `key-down` supports key-combos like Ctrl+Tab, `key` does not seem to
		;-- OTOH `key` properly reflects Shift state in chars
		;-- so we have to use both
		on-key [space path event] [				;-- char keys branch (inserts stuff as you type)
			k: event/key
			either space/active? [				;-- normal input when active
				unless all [
					char? k
					any [
						k >= #" "							;-- printable char
						k = #"^-"							;-- Tab
						if k = #"^M" [k: #"^/"]				;-- Enter -> NL
					]
				] [exit]
				;@@ allow new-line char only when multiline?
				;@@ TODO: input validation / filtering
				insert at space/text  space/caret-index: space/caret-index + 1  k
				space/invalidate						;@@ TODO: should be caught maybe automatically?
				update
			][									;-- has to handle Enter, or both key-down and key will handle it, twice
				either k = #"^M" [
					maybe space/active?: yes		;-- activate it on Enter
					update							;-- let styles change
				][
					pass						;-- pass keys in inactive state (esp. tab)
				]
			]
		]
		
		on-key-down [space path event] [		;-- control keys & key combos branch (navigation)
			k: event/key
			unless space/active? [pass exit]	;-- keys should be passed thru (tab, arrows, ...); Enter is in on-key
												;-- else, keys should be used on content (e.g. arrows)
			if all [
				char? k							;-- ignore chars without mod keys
				not any [
					find "^[^H" k				;-- use only Esc and BS
					event/ctrl?
				]
			] [exit]

			ci: space/caret-index
			len: length? t: space/text
			switch/default k: event/key [
				left   [ci: ci - 1]			;@@ TODO: ctrl-arrow etc logic
				right  [ci: ci + 1]
				home   [ci: 0]
				end    [ci: len]
				delete [remove skip t ci]
				#"^H"  [remove skip t ci: ci - 1]	;-- backspace
				#"^["  [maybe space/active?: no]	;-- Esc = deactivate
			][exit]									;-- not supported yet key
			maybe space/caret-index: max 0 min length? t ci
			space/invalidate						;@@ TODO: should be caught maybe automatically?
			update
		]

		on-key-up [space path event] []				;-- eats the event so it's not passed forth

		on-click [space path event] [
			#assert [space/para/layout]
			space/caret-index: offset-to-caret space/para/layout path/2
			space/active?: yes				;-- activate, so Enter is not required
			update							;-- let styles update
		]

		on-unfocus [space path event] [
			space/active?: no				;-- deactivate so it won't catch Tab when next tabbed in
		]
	]
]

