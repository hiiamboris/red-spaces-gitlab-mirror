Red [
	title:   "Standard event handlers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires events.red (on load)

is-key-printable?: function [event [event! object!]] [
	to logic! all [
		char? char: event/key
		char >= #" "
		not event/ctrl?
	]
]

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
				down       [[space/move-by pick [page line] event/ctrl? 'forth 'y]]
				up         [[space/move-by pick [page line] event/ctrl? 'back  'y]]
				right      [[space/move-by pick [page line] event/ctrl? 'forth 'x]]
				left       [[space/move-by pick [page line] event/ctrl? 'back  'x]]
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
	;@@ TODO: when dragging and slide succeeds, the canvas jumps
	;@@       need to update drag-parameter from `slide` or something..
	inf-scrollable: extends 'scrollable [	;-- adds automatic window movement when near the edges
		on-wheel    [space path event] [space/slide]	;-- faster wheel-scrolling, without slide-timer delays
		;; trick here is that inf-scrollable/on-key fires after scrollable/on-key-down:
		;@@ (otherwise I would have to extend the handler dialect to add delayed handlers, child after parent - maybe I should?)
		on-key [space path event] [space/slide]			;-- most useful for fast seamless scrolling on pageup/pagedown
		slide-timer: [
			on-time [space path event delay] [			;-- during scroller dragging
				path/-1/slide
			]
		]
	]

	;-- *************************************************************************************
	list-view: extends 'inf-scrollable [
		on-down [space path event] [
			; ?? [space/origin space/window/origin space/anchor/offset]		
			unless space/selectable [exit]				;-- this handler is only responsible for selection
			if set [item:] locate path [obj - .. obj/type = 'item] [
				range: space/list/frame/range
				i: range/1 + half -1 + index? find/same space/list/map item
				case [
					event/shift? [
						old: any [space/cursor range/1]
						space/selected: union space/selected
							to space/selected list-range space/cursor: i old	;@@ #5344
					]
					event/ctrl? [alter space/selected space/cursor: i]
					'default [append clear space/selected space/cursor: i]
				]
				trigger 'space/selected					;-- not automatic since /cursor may stay in place, and /selected is undetected
				;@@ add box selection by dragging? esp. tricky if user expects dragging to turn on scrolling and sliding when out of the viewport
				;@@ also it will conflict with current touch-friendly dragging, so must be optional
			]
			;; let scrollable get the event, for dragging viewport by item
		]
		
		on-key-down [space path event] [
			unless space/selectable [exit]				;-- this handler is only responsible for selection
			list:   space/list
			y:      list/axis
			range:  list/frame/range
			multi?: space/selectable = 'multi
			
			;@@ would be nice to use key->plan here but it's tuned for editing text paragraphs
			switch/default event/key [
				#"C" [batch space [copy-items/clip selected]]
				
				#" " [									;-- space/ctrl+space selected item toggle
					if i: space/cursor [
						mode: case [
							multi? ['invert]
							find space/selected i ['exclude]
							'else ['include]
						]
						batch space [select-range/mode here mode]
					]
				]
				
				down up page-down page-up home end [
					old: batch space [here]
					new: switch event/key [
						up        ['line-up]
						down      ['line-down]
						page-up   ['page-up]
						page-down ['page-down]
						home      [either event/ctrl? ['far-head]['head]]
						end       [either event/ctrl? ['far-tail]['tail]]
					]
					new: batch space [locate new]
					case [
						all [multi? event/ctrl? event/shift?] [
							batch space [select-range/mode old by new 'include]
						]
						all [multi? event/shift?] [
							batch space [select-range/mode old by new 'replace]
						]
						not event/ctrl? [
							batch space [select-range/mode new by new 'replace]
						]
					]
					batch space [move-cursor new]
				]
				
			] [exit]									;-- unhandled keys belong to inf-scrollable
			stop/now									;-- handled keys are not passed into inf-scrollable
		]
	]

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
				on-over [space path event] [			;-- on-hover highlight ;@@ should it affect /color though?
					space/color: if path/2 inside? space [mix 'panel opaque 'text 15%]
				]
			]
		]
		ring: [
			clickable: extends 'menu/list/clickable []
			round-clickable: extends 'menu/list/clickable []
		]
		on-click [space path event] [
			item: path/5
			if find [round-clickable clickable] select item 'type [
				do item/command
			]
			popups/hide 1								;-- click on a menu hides all visible menus
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
			unless is-key-printable? event [			;-- handled by on-key-down (e.g. ctrl+BS=#"^~") 
				if event/key = #"^-" [pass]				;-- let tab pass thru
				exit									;@@ what about enter key / on-enter event?
			]
			;@@ TODO: input validation / filtering
			batch space compose [
				(key->plan event space/selected)
				frame/adjust-origin						;@@ should be automatic
			]
			invalidate space							;-- has to reconstruct layout in order to measure caret location
			invalidate/only space/caret					;@@ any way to properly invalidate both at once? -- need layout under cache
		]
		
		on-key-down [space path event] [			;-- control keys & key combos branch (navigation)
			;@@ up/down keys may be used for spatial navigation
			if is-key-printable? event [exit]
			batch space compose [
				(key->plan event space/selected)
				frame/adjust-origin
			]
			invalidate space
		]

		on-key-up [space path event] []					;-- eats the event so it's not passed forth

		on-down [space path event] [
			batch space [
				select-range none
				move-caret frame/point->caret path/2
			]
			start-drag path
		]
		
		on-over [space path event] [
			#assert [space/spaces/text/layout]
			dpath: drag-path
			if all [dpath dpath/1 =? path/1] [			;-- if started dragging also on this field
				batch space [
					select-range frame/point->caret path/2
					frame/adjust-origin
				]
			]
		]
		
		on-up [space path event] [stop-drag]
		
		on-focus   [space path event] [space/caret/visible?: yes]
		on-unfocus [space path event] [space/caret/visible?: no]
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

