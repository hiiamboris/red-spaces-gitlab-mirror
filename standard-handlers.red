Red [
	title:   "Standard event handlers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires events.red (on load)

is-key-printable?: function [event [map!]] [
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
			set [item: _: subitem:] skip path 2
			case [
				find [hscroll vscroll] select item 'type [		;-- move or start dragging
					axis: item/axis
					switch select subitem 'type [
						forth-arrow [space/move-by 'line 'forth axis]
						back-arrow  [space/move-by 'line 'back  axis]
						forth-page  [space/move-by 'page 'forth axis]
						back-page   [space/move-by 'page 'back  axis]
						thumb       [drag?: on]
					]
				]
				any [item =? space/content  item = none] [		;-- 'none' is useful if content is smaller than the scrollable
					drag?: find [pan scroll] space/behavior/draggable
					clear skip (path: clone/flat path) 4		;-- drag by content, not by its child (child may override this)
					pass										;-- content may still handle it (e.g. grid-view within grid-view)
				]
			]
			;; don't override drags from inherited handlers (grid-view, etc.), but override from parent handlers (child takes priority)
			if all [drag?  not dragging?/from space] [start-drag path]
			
			space/last-xy: path/2								;@@ kludge
		]
		
		on-up [space path event] [
			either dragging?/from space [						;-- since 'down' is sent to children, let 'up' be sent as well
				if (drag-offset path) +<= (3,3) [pass]			;-- do not eat clicks on content, only drags (experimental) ;@@ or pass anyway?
				stop-drag
			][
				pass
			]
		]
		
		on-over [space path event] [
			unless own?: dragging?/from space [pass exit]		;-- let inner spaces handle it
			
			set [item: _: subitem:] skip path 2
			switch/default select item 'type [					;-- item may be none
				hscroll vscroll [
					unless all [
						own?
						thumb?: 'thumb = select subitem 'type	;-- do not react to drag of arrows (used by timer)
					] [exit]
					scroll: item
					x:      scroll/axis
					;; map/subitem/size should take precedence over subitem/size
					;; because map can get fetched from cache without affecting subitem object sizes (they become invalid at this point)
					forth-arrow-geom: select/same scroll/map scroll/forth-arrow
					back-arrow-geom:  select/same scroll/map scroll/back-arrow
					band:   scroll/size/:x - forth-arrow-geom/size/:x - back-arrow-geom/size/:x
					csize:  space/content/size					;@@ may get out of sync with the map?
					vport:  space/viewport
					hidden: csize/:x - vport/:x
					ofs: drag-offset skip path 2				;-- get offset relative to the scrollbar
					ofs: ofs/:x / max 1 band					;-- scale it down by scrollbar's size 
					ofs: ofs * (csize * axis2pair x)			;-- now scale up by content size
				]
			][
				switch space/behavior/draggable [
					pan [
						if own? [ofs: negate drag-offset path]
					]
					scroll [
						space/last-xy: path/2					;@@ kludge
					]
				]
			]
			if ofs [space/clip-origin space/origin - ofs]		;-- clipping in the event handler guarantees validity of size
			if own? [
				if any [
					thumb?
					not find [scroll select] space/behavior/draggable
				] [start-drag path]								;-- restart from the new offset or it will accumulate
			]
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
			if event/ctrl? [exit]						;-- ignore ctrl+wheel, which is used for zoom usually
			if 100 < absolute amount: event/picked [	;@@ workaround for #5110
				amount: -256 * sign? amount + amount
			]
			horz?: to logic! any [						;-- shift+wheel changes direction - wish #9
				path/3 =? space/hscroll
				all [path/3 =? space/content event/shift?]
			] 
			space/move-by/scale
				'line
				pick [forth back] amount <= 0
				pick [x y] horz?
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
			on-time [space path event delay [percent!]] [		;-- press & hold way of scrolling
				unless all [
					drag-path
					found: find/reverse/same next drag-path path/-1
				] [exit]
				set [scrollable: xy: item: _: subitem:] found
				switch/default select item 'type [				;-- 'item' can be none
					hscroll vscroll [
						scrollable/move-by/scale
							switch/default select subitem 'type [back-page forth-page ['page] back-arrow forth-arrow ['line]] [exit]
							switch subitem/type [back-arrow back-page ['back] forth-arrow forth-page ['forth]]
							any [select [hscroll x vscroll y] item/type]
							delay + 100%
					]
				][
					;; scroll viewport when dragging out of it (useful for content selection)
					;; this relies on on-over rewriting drag-path on every event, because timer doesn't have access to offsets
					if all [
						scrollable/behavior/draggable = 'scroll
						not (xy: scrollable/last-xy) inside? scrollable		;@@ kludge
					][
						cxy: xy - center: half scrollable/size
						cxy': cxy / center						;-- normalized to [-1,-1]..[1,1]
						ofs: cxy' - (cxy' / max abs cxy'/x abs cxy'/y) * center
						unless zero? ofs [
							scrollable/clip-origin scrollable/origin - ofs
						]
					]
				]
			]
		]
	]

	;-- *************************************************************************************
	inf-scrollable: extends 'scrollable [	;-- adds automatic window movement when near the edges
		on-wheel [space path event] [space/slide]		;-- faster wheel-scrolling, without slide-timer delays
		;; trick here is that inf-scrollable/on-key fires after scrollable/on-key-down:
		;@@ (otherwise I would have to extend the handler dialect to add delayed handlers, child after parent - maybe I should?)
		on-key   [space path event] [space/slide pass]	;-- most useful for fast seamless scrolling on pageup/pagedown
		slide-timer: [
			on-time [space path event delay] [			;-- during scroller dragging
				path/-1/slide
			]
		]
	]

	;-- *************************************************************************************
	list-view: extends 'inf-scrollable [
		on-focus   [space path event] [if space/behavior/selectable [invalidate space/list]]
		on-unfocus [space path event] [if space/behavior/selectable [invalidate space/list]]
		
		on-down [space path event] [
			multi?: space/behavior/selectable = 'multi
			if set [item:] locate path [obj - .. obj/type = 'item] [
				i: space/list/frame/range/1 + half skip? find/same space/list/map item
				mode: case [
					all [event/shift? multi?] ['extend]
					all [event/ctrl?  multi?] ['invert]
					'default                  ['replace]
				]
				range: either all [event/shift? multi?] [i][i thru i]
				batch space [
					select-range/mode range mode
					if i <> here [move-cursor i]				;-- don't move the already selected item around
				]
			]
			; if all [multi? space/behavior/draggable <> 'pan] [start-drag path]	;-- start selection by dragging
			;; let scrollable get the event, for dragging viewport by item
		]
		
		on-up [space path event] [
			if dragging?/from space [stop-drag]
		]
		
		on-over [space path event] [
			unless all [
				drag-path
				found: find/reverse/same next drag-path space	;-- dragging from inside of this list-view, maybe from the item
				multi?: space/behavior/selectable = 'multi
			] [exit]
			y:    space/list/axis
			wxy1: found/4
			wxy2: path/4
			set-pair [i1: i2:] batch space [frame/items-between wxy1/:y wxy2/:y]
			mode: case [
				all [event/shift? multi?] ['extend]
				all [event/ctrl?  multi?] ['invert]
				'default                  ['replace]
			]
			batch space [
				select-range/mode i1 thru i2 mode
				if i2 <> here [move-cursor i2]			;-- don't move the already selected item around
			]
		]
		
		on-key-down [space path event] [
			unless space/behavior/selectable [exit]		;-- this handler is only responsible for selection
			list:   space/list
			y:      list/axis
			range:  list/frame/range
			multi?: space/behavior/selectable = 'multi
			
			;@@ would be nice to use key->plan here but it's tuned for editing text paragraphs
			switch/default event/key [
				#"C" [if event/ctrl? [batch space [copy-items/clip selected]]]
				
				#" " [									;-- space/ctrl+space selected item toggle
					if i: space/cursor [
						mode: case [
							multi? ['invert]
							find space/selected i ['exclude]
							'else ['replace]
						]
						batch space [select-range/mode here mode]
					]
				]
				
				down up page-down page-up home end [
					old: batch space [here]
					target: switch event/key [
						up        ['line-up]
						down      ['line-down]
						page-up   ['page-up]
						page-down ['page-down]
						home      [either event/ctrl? ['far-head]['head]]
						end       [either event/ctrl? ['far-tail]['tail]]
					]
					new: batch space [locate target]
					far-jump?: find [far-head far-tail] target
					
					;; do not(!) move to items that are not drawn yet (too many bugs with that)
					;; (must avoid anchor-moving branch of kit/move-to)
					unless far-jump? [
						range: space/list/frame/range
						new:   clip range/1 range/2 new
					]
					select?: case [
						;; dangerous to select items with far-jump (can be billions)
						all [multi? event/shift? not far-jump?]	['range]
						any [far-jump? not event/ctrl?] ['single]
					]
					batch space [slide]					;-- slide it before it was modified ;@@ needs to consider invalidation type ideally
					switch select? [
						range [
							mode: either event/ctrl? ['include]['extend]
							batch space [select-range/mode old thru new mode]
						]
						single [
							batch space [select-range/mode new thru new 'replace]
						]
					]
					batch space [
						move-cursor/no-clip new			;-- /no-clip is safe as long as given margin does not exceed list/margin
					]
				]
				
			] [exit]									;-- unhandled keys belong to inf-scrollable
			stop/now									;-- handled keys are not passed into inf-scrollable
		]
	]

	;-- *************************************************************************************
	grid-view: extends 'inf-scrollable [
		on-down [gview path event] [
			set [grid: _: cell:] skip path 4
			if 'cell <> select cell 'type [exit]
			cxy:    grid-ctx/get-cell-address grid cell
			unless cxy [exit]
			multi?: gview/behavior/selectable = 'multi
			mode:   either all [event/ctrl? multi?] ['invert]['replace]
			cursor: max cxy grid/pinned + 1 
			unless all [multi? event/shift?] [gview/selection-start: cursor]
			start:  gview/selection-start
			batch grid [move-cursor cursor] 
			case [
				grid/pinned +< cxy [
					batch grid [
						select-range start cxy
						drag?: on
					]
				]
				not multi? ['done]
				cxy +<= grid/pinned [
					batch grid [select-range 1x1 'far-tail]		;-- include headers into selection
				]
				x: case [
					cxy/y <= grid/pinned/y ['x]
					cxy/x <= grid/pinned/x ['y]
				] [
					batch grid [
						select-along ortho x 'all
						select-along/mode x start/:x thru cxy/:x mode
					]
					drag?: on
				]
			]
			if drag? [
				if locate path [o - .. find [hscroll vscroll] o/type] [	;-- allow scrollbars in children to override grid dragging ;@@ a kludge!
					pass exit
				]
				clear skip (path': clone/flat path) 6			;-- drag around grid, not around its cell
				start-drag path'
				stop/now
			]
			; stop/now
			; pass
		]
		
		on-over [gview path event] [
			unless all [
				dragging?/from gview
				not event/ctrl?									;-- handle only ctrl-click, not ctrl-drag
				start: gview/selection-start
				gview/behavior/selectable = 'multi
			] [pass exit]
			set [grid: _: cell:] skip path 4
			if all ['cell = select cell 'type] [
				#assert [grid/type = 'grid]
				cxy: grid-ctx/get-cell-address grid cell
				unless cxy [exit]
				case [
					all [cxy/x <= grid/pinned/x cxy/y > grid/pinned/y] [	;-- rows after header
						batch grid [
							select-columns 'all
							select-rows    start/y thru cxy/y
						]
					]
					all [cxy/y <= grid/pinned/y cxy/x > grid/pinned/x] [	;-- columns after header
						batch grid [
							select-rows    'all
							select-columns start/x thru cxy/x
						]
					]
					grid/pinned +< cxy [						;-- 2D range selection
						batch grid [select-range start cxy]
					]
				]
				batch grid [move-cursor max cxy grid/pinned + 1]
				stop/now
			]
		]
		
		;; guidelines: https://www.w3.org/WAI/ARIA/apg/patterns/grid/
		on-key-down [gview path event] [
			unless gview/behavior/selectable [exit]				;-- has to be selectable to have cursor
			cursor: batch grid: gview/grid [here]
			switch/default event/key [
				#"A" [
					if event/ctrl? [
						batch grid [select-range 1x1 'far-tail]	;-- include headers into selection
					]
				]
			
				#"C" insert [
					if event/ctrl? [
						batch grid [copy-selection/clip]
					]
				]
			
				#" " [											;-- column or row selection
					if axis: case [
						event/ctrl?  ['x]
						event/shift? ['y]
					][
						gview/selection-start: none				;-- indicate it's not an area selection
						batch grid [
							select-along ortho axis 'all
							select-along axis cursor/:axis
						]
					]
				]
				
				;@@ consider navigation across multicells - follow spreadsheets behavior
				up down left right page-up page-down home end [
					target: pick select [
						up        [column-head line-up]
						down      [column-tail line-down]
						home      [far-head head]
						end       [far-tail tail]
						left      [row-head prev-cell]
						right     [row-tail next-cell]
						page-down [page-down page-down]
						page-up   [page-up   page-up]
					] event/key event/ctrl?
					multi?: all [gview/behavior/selectable = 'multi event/shift?]
					batch gview [cursor: locate target]
					batch grid [
						old-cursor: here
						;@@ these should be known automatically, in the frame or where
						cell1: first grid/locate-point org: negate gview/window/origin
						cell2: first grid/locate-point org + gview/window/size
						; ?? [org cell1 cell2 old-cursor]
						cursor-drawn?: cell1 +<= old-cursor +<= cell2
						repeatable?: find [line-up line-down prev-cell next-cell page-up page-down] target
						;@@ temporary limit until redesign:
						;@@ moving cursor outside the currently drawn area shows empty space until filled by multiple slides
						;@@ it's slow when holding arrow keys, so I disable it (but for far jumps it's a necessity to have it)
						if any [cursor-drawn? not repeatable?] [
							move-cursor cursor
							old-sel: selected-range
							either all [multi? old-sel not gview/selection-start] [	;-- current selection is not a limited area, but bits
								axis: either cursor/y = old-cursor/y ['x]['y]
								select-along/mode axis old-cursor/:axis thru cursor/:axis 'include
							][									;-- current selection is either empty or a limited area
								either multi? [
									default gview/selection-start: old-cursor
								][
									gview/selection-start: cursor
								]
								select-range gview/selection-start cursor
							]
						]
					]
					batch gview [pan-to-cursor]
					gview/slide									;@@ put into the batch
				]
			][exit]												;-- let unhandled keys go into inf-scrollable
			stop/now
		]
	]

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
		on-down [space path event] []					;-- prevent clicks from passing over to children
		on-up   [space path event] []
	]
	
	data-clickable: extends 'clickable []
	
	menu: [
		list: [
			clickable: extends 'clickable [
				; on-up [space path event] [
					; hide-popups event/window 1			;-- click on a menu item hides all visible menus
				; ]
				on-over [space path event] [			;-- on-hover highlight ;@@ should it affect /color though?
					space/color: if path/2 inside? space [impose 'panel opaque 'text 15%]
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
				unless find [#"^[" #"^M" #"^H" left right delete home end insert] event/key [pass]	;-- keys unhandled by field can go to the parent
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
		
		on-key-down [space path event] [				;-- control keys & key combos branch (navigation)
			if is-key-printable? event [exit]
			unless any [
				event/ctrl?
				find [#"^[" #"^M" #"^H" left right delete home end insert] event/key
			] [pass exit]	;-- keys unhandled by field can go to the parent
			batch space compose [
				(key->plan event space/selected)
				frame/adjust-origin
			]
			invalidate space
		]

		on-key-up [space path event] [					;-- eats the event so it's not passed forth
			unless any [
				is-key-printable? event
				event/ctrl?
				find [#"^[" #"^M" #"^H" left right delete home end insert] event/key
			] [pass]									;-- keys unhandled by field can go to the parent
		]

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

	slider: [
		on-down [space path event] [
			space/offset: batch space [frame/x->offset path/2/x]
			start-drag path								;-- keep tracking knob when pointer leaves the slider
		]
		on-up   [space path event] [stop-drag]
		on-over [space path event] [
			if event/down? [space/offset: batch space [frame/x->offset path/2/x]]
		]
		on-key  [space path event] [
			if integer? step: space/step [
				step: step / (space/size/x - space/knob/size/x)
			]
			either offset: switch event/key [
				left  up   [space/offset - step]
				right down [space/offset + step]
				page-up    [space/offset - max 10% step * 20]
				page-down  [space/offset + max 10% step * 20]
				home       [0%]
				end        [100%]
			][
				space/offset: 100% * clip 0 1 offset
			][
				pass									;-- ignore other keys, esp. tab
			]
		]
		on-focus   [space path event] [invalidate space]
		on-unfocus [space path event] [invalidate space]
	]
	
	fps-meter: [
		on-time [space path event] [
			time: now/precise/utc
			limit: time - space/aggregate
			frames: space/frames
			forall frames [
				if frames/1 > limit [
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

