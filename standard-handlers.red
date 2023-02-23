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
				find [hscroll vscroll] select item 'type [		;-- move or start dragging
					axis: item/axis
					switch select subitem 'type [
						forth-arrow [space/move-by 'line 'forth axis]
						back-arrow  [space/move-by 'line 'back  axis]
						forth-page  [space/move-by 'page 'forth axis]
						back-page   [space/move-by 'page 'back  axis]
					]
				]
				item =? space/content [pass]			;-- let content handle it, but still start dragging (e.g. grid-view within grid-view)
				; item = none []							;-- dragging by the empty area of scrollable
			]
			;; remove cells or other content from the path, as they do not have to persist during window moves:
			unless find [hscroll vscroll] select item 'type [clear skip path 2]
			;; start dragging anyway, e.g. for dragging by content or by empty area:
			start-drag path
		]
		on-up [space path event] [stop-drag pass]
		on-over [space path event] [
			unless dragging?/from space [pass exit]		;-- let inner spaces handle it
			set [_: _: item: _: subitem:] path
			either find [hscroll vscroll] select item 'type [	;-- item may be none
				if 'thumb <> select subitem 'type [exit]		;-- do not react to drag of arrows (used by timer)
				scroll: item
				x:      scroll/axis
				;; map/subitem/size should take precedence over subitem/size
				;; because map can get fetched from cache without affecting subitem object sizes (they become invalid at this point)
				forth-arrow-geom: select/same scroll/map scroll/forth-arrow
				back-arrow-geom:  select/same scroll/map scroll/back-arrow
				band:   scroll/size/:x - forth-arrow-geom/size/:x - back-arrow-geom/size/:x
				csize:  space/content/size				;@@ may get out of sync with the map?
				vport:  space/viewport
				hidden: csize/:x - vport/:x
				ofs: drag-offset skip path 2			;-- get offset relative to the scrollbar
				ofs: ofs/:x / max 1 band				;-- scale it down by scrollbar's size 
				ofs: ofs * (csize * axis2pair x)		;-- now scale up by content size
			][
				ofs: negate drag-offset path			;-- dragged by an empty area
			]
			space/clip-origin space/origin - ofs		;-- clipping in the event handler guarantees validity of size
			start-drag path								;-- restart from the new offset or it will accumulate
		]
		on-key-down [space path event] [
			; unless single? path [pass exit]
			code: switch event/key [
				down       [[space/move-by 'line 'forth 'y]]
				up         [[space/move-by 'line 'back  'y]]
				right      [[space/move-by 'line 'forth 'x]]
				left       [[space/move-by 'line 'back  'x]]
				page-down  [[space/move-by 'page 'forth 'y]]
				page-up    [[space/move-by 'page 'back  'y]]
				home       [[space/move-to 'head]]
				end        [[space/move-to 'tail]]
			]
			either code [
				do code
			][
				pass									;-- key was not handled (useful for tabbing)
			]
		]
		on-wheel [space path event] [
			if 100 < absolute amount: event/picked [	;@@ workaround for #5110
				amount: -256 * sign? amount + amount
			]
			space/move-by/scale
				'line
				pick [forth back] amount <= 0
				pick [x y] 'hscroll = path/3
				abs amount * 4
		]
		on-focus [space path event] [
			invalidate space/hscroll/thumb
			invalidate space/vscroll/thumb
		]
		on-unfocus [space path event] [
			invalidate space/hscroll/thumb
			invalidate space/vscroll/thumb
		]
		scroll-timer: [
			on-time [space path event delay [percent!]] [	;-- press & hold way of scrolling
				unless dragging? [exit]
				set [spc: _: item: _: subitem:] drag-path
				unless spc =? path/-1 [exit]				;-- dragging started inside another space - ignore it
				scrollable: path/-1
				scrollable/move-by/scale
					switch/default select subitem 'type [back-page forth-page ['page] back-arrow forth-arrow ['line]] [exit]
					switch subitem/type [back-arrow back-page ['back] forth-arrow forth-page ['forth]]
					any [select [hscroll x vscroll y] select item 'type  exit]
					delay + 100%
			]
		]
	]

	;-- *************************************************************************************
	;@@ TODO: when dragging and roll succeeds, the canvas jumps
	;@@       need to update drag-parameter from `roll` or something..
	inf-scrollable: extends 'scrollable [	;-- adds automatic window movement when near the edges
		on-down     [space path event] [				;-- after button clicks
			without-children: as path! copy/part head path next path	;@@ should I make a function for this?
			space/roll/in without-children				;-- /in is used to provide proper styling context to out-of-tree render!
		]
		on-key-down [space path event] [				;-- during key holding
			without-children: as path! copy/part head path next path
			space/roll/in without-children
		]
		roll-timer: [
			on-time [space path event delay] [			;-- during scroller dragging
				without-children: as path! copy/part head path path
				path/-1/roll/in without-children
			]
		]
	]

	;-- *************************************************************************************
	list-view: extends 'inf-scrollable []

	;-- *************************************************************************************
	grid-view: extends 'inf-scrollable []

	;-- *************************************************************************************
	switch: [
		on-up [space path event] [
			space/state: not space/state
		]
	]
	
	;-- *************************************************************************************
	link: [
		;; without explicit start-drag here
		;; parent (e.g. scrollable) may start it's own dragging
		;; and -up event won't reach the link
		on-down [space path event] [start-drag path] 
		on-up   [space path event] [stop-drag]
		
		on-click [space path event] [
			do space/command
		]
	]
	
	;-- *************************************************************************************
	clickable: [
		on-click [space path event] [
			do space/command
		]
	]
	
	data-clickable: extends 'clickable []
	
	menu: [
		list: [
			clickable: extends 'clickable [
				; on-up [space path event] [
					; hide-popups event/window 1			;-- click on a menu item hides all visible menus
				; ]
				on-over [space path event] [
					unless :highlight =? space [		;@@ this mechanism should be generalized
						if space? :highlight [invalidate highlight]
						set 'highlight space
						invalidate space
					]
				]
			]
		]
		on-click [space path event] [
			item: path/5
			if find [round-clickable clickable] select item 'type [
				do item/command
			]
			hide-popups event/window 1					;-- click on a menu hides all visible menus
		]
	]

	button: [											;-- focusable unlike `clickable` space
		on-down [space path event] [
			space/pushed?: yes
			start-drag path								;-- otherwise `up` event might not be caught, leaving button "pressed"
		]
		on-up [space path event] [
			space/pushed?: no		;@@ TODO: avoid the command when pointer goes out of button box (also maybe ESC key)
			stop-drag
		]
		on-key [space path event] [
			either all [
				find " ^M" event/key
				not space/pushed?
			][
				space/pushed?: yes
			][pass]
		]
		on-key-up [space path event] [
			either all [
				find " ^M" event/key
				space/pushed?
			][
				space/pushed?: no
			][pass]
		]
	]


	;-- *************************************************************************************
	rotor: [
		ring: [
			on-down [space path event] [
				rotor: path/-2
				ofs: path/-1 - (rotor/size / 2)
				angle: arctangent2 ofs/y ofs/x
				start-drag/with path reduce [rotor/angle angle]
			]
			on-up [space path event] [stop-drag]
			on-over [space path event] [
				unless dragging? [exit]
				rotor: path/-2
				ofs: path/-1 - (rotor/size / 2)
				angle: arctangent2 ofs/y ofs/x
				parm: drag-parameter
				rotor/angle: (parm/1 + angle - parm/2) // 360
			]
		]
	]


	;-- *************************************************************************************
	field: [
		;; `key-down` supports key-combos like Ctrl+Tab, `key` does not seem to
		;; OTOH `key` properly reflects Shift state in chars
		;; so we have to use both, just separate who handles what
		on-key [space path event] [					;-- char keys branch (inserts stuff as you type)
			printable?: all [
				char? char: event/key
				char >= #" "
				not event/ctrl?							;-- handled by on-key-down (e.g. ctrl+BS=#"^~")
			]
			unless printable? [ 
				if char = #"^-" [pass]					;-- let tab pass thru
				exit									;@@ what about enter key / on-enter event?
			]
			;@@ TODO: input validation / filtering
			space/edit key->plan event space/selected
			quietly space/origin: field-ctx/adjust-origin space	;@@ should be automatic
			invalidate space							;-- has to reconstruct layout in order to measure caret location
			invalidate/only space/caret					;@@ any way to properly invalidate both at once? -- need layout under cache
		]
		
		on-key-down [space path event] [			;-- control keys & key combos branch (navigation)
			printable?: all [
				char? char: event/key
				char >= #" "
				not event/ctrl?							;-- handled by on-key-down (e.g. ctrl+BS=#"^~")
			]
			if printable? [exit]
			space/edit key->plan event space/selected
			quietly space/origin: field-ctx/adjust-origin space
			invalidate space
		]

		on-key-up [space path event] []					;-- eats the event so it's not passed forth

		on-down [space path event] [
			new-ofs: space/offset-to-caret path/2
			space/edit compose [select none move to (new-ofs)]
			start-drag path
		]
		
		on-over [space path event] [
			#assert [space/spaces/text/layout]
			dpath: drag-path
			if all [dpath dpath/1 =? path/1] [			;-- if started dragging also on this field
				new-ofs: space/offset-to-caret path/2
				space/edit compose [select to (new-ofs)]
				quietly space/origin: field-ctx/adjust-origin space
			]
		]
		
		on-up [space path event] [stop-drag]
	]

	fps-meter: [
		on-time [space path event] [
			time: now/precise/utc
			frames: space/frames
			forall frames [
				if frames/1 + space/aggregate > time [
					remove/part frames frames: head frames
					break
				]
			]
			append frames time							;-- let frames never be empty, so frame/1 is not none
			elapsed: to float! difference time frames/1
			fps: (length? frames) / (max 0.01 elapsed)	;-- max for overflow protection
			space/text: rejoin ["FPS: " 0.1 * to integer! 10 * fps]
		]
	]
]

