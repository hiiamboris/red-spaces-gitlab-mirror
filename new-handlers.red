Red [
	title:   "Standard event handlers for Spaces"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires events.red (on load)

define-handlers [

	;-- *************************************************************************************
	scrollable: [
		/scrollbar [ 
			;@@ all scrollbar children should share a single timer
			/forth-arrow [
				;@@ make a spaces-specific wrapper? e.g. 'space/kit/arm-timer/now forth-arrow' - derived from 'space'?
				;@@ or even better: using forth-arrow [arm-timer/now] ? or just a global func, not kit? or both? `arm-timer/now forth-arrow`
				;@@ name collision between the two won't be welcome, so must decide
				* down         [timers/arm/now forth-arrow/config/timer]
				; * down         [arm-timer/now forth-arrow]
				* time (delay) [scroll/along/lines      1 + delay scrollbar/axis]
				* up           [timers/disarm  forth-arrow/config/timer]
			]
			/back-arrow  [
				* down         [timers/arm/now back-arrow/config/timer]
				* time (delay) [scroll/along/lines/back 1 + delay scrollbar/axis]
				* up           [timers/disarm  back-arrow/config/timer]
			]
			/forth-page  [
				* down         [timers/arm/now forth-page/config/timer]
				* time (delay) [scroll/along/pages      1 + delay scrollbar/axis]
				* up           [timers/disarm  forth-page/config/timer]
			]
			/back-page   [
				* down         [timers/arm/now back-page/config/timer]
				* time (delay) [scroll/along/pages/back 1 + delay scrollbar/axis]
				* up           [timers/disarm  back-page/config/timer]
			]
			;@@ ratio should be defined as 'viewport / total' in the kit
			/thumb [* down + over (xy dxy) [scroll/along dxy / ratio scrollbar/axis]]
			
			wheel [scroll/along event/moved scrollbar/axis]
		]
			
		* down + over (xy) [
			sink												;-- let children exhaust the movement if they can
			if switch scrollable/behavior/draggable [
				pan    [not zero? dxy: event/moved]				;-- they may have modified event/moved
				scroll [dxy: xy outside? space]					;@@ outside should return 'none' when inside, 2D distance vector otherwise
			] [
				unless zero? event/moved: scroll dxy [bubble]	;-- first space that fully handles the scrolling, stops it
			]
		]
		;@@ 'scroll' mode should work on time instead of on-over
		; * time (delay) []
		
		control + key
		key [
			sink												;-- let children check the key first
			unless match-key event [
				;@@ leverage key->plan instead!
				@Ctrl+Down
				@PageDown   [scroll/along/pages +1 'y]
				@Ctrl+Up
				@PageUp     [scroll/along/pages -1 'y]
				@Ctrl+Right [scroll/along/pages +1 'x]
				@Ctrl+Left  [scroll/along/pages -1 'x]
				@Down       [scroll/along/lines +1 'y]
				@Up         [scroll/along/lines -1 'y]
				@Right      [scroll/along/lines +1 'x]
				@Left       [scroll/along/lines -1 'x]
				@Home       [scroll 'head]
				@End        [scroll 'tail]
			] [bubble]											;-- pass unhandled keys up
		]
		
		;; ignore ctrl+wheel, which is used for zoom usually
		shift + wheel
		wheel [
			sink												;-- let children take the wheel first
			unless zero? event/moved [
				axis: pick [x y] event/shift?					;-- shift+wheel changes direction - wish #9
				unless zero? event/moved: scroll/along event/moved axis [bubble]
			]
		]
		
		* unfocus
		* focus [sink  invalidate scrollable]					;@@ make it re-render thumbs
	]

	; inf-scrollable: below 'scrollable [	;-- adds automatic window movement when near the edges
		; on-wheel [space path event] [space/slide]		;-- faster wheel-scrolling, without slide-timer delays
		; ;; trick here is that inf-scrollable/on-key fires after scrollable/on-key-down:
		; ;@@ (otherwise I would have to extend the handler dialect to add delayed handlers, child after parent - maybe I should?)
		; on-key   [space path event] [space/slide pass]	;-- most useful for fast seamless scrolling on pageup/pagedown
		; slide-timer: [
			; on-time [space path event delay] [			;-- during scroller dragging
				; path/-1/slide
			; ]
		; ]
	; ]

	list-view: below 'scrollable [
		;; list draws a focus indicator when focused
		* focus * unfocus [sink  either list-view/behavior/selectable [invalidate list-view/list][bubble]]
		
		;; children get the event first: e.g. if list-view contains inner list-views or other interactive content
		* control + down (xy) [sink  select-range/move/mode xy 'invert ]	;@@ 'select-range' should check multi-selectable flag and apply
		* shift + down (xy)   [sink  select-range/move/mode xy 'extend ]	;@@ /move to move the cursor too
		* down (xy)           [sink  select-range/move/mode xy 'replace]
		
		;@@ subtract from event/moved and bubble
		* down + over [sink  select-range/move/mode event/moved 'extend]	;-- let children exhaust over event before list-view
		
		* key [
			sink												;-- children and scrollable get the key first
			unless list-view/behavior/selectable [bubble]		;-- this handler is only responsible for selection
			unless match-key event [
				@Copy                [copy-items/clip selected]
				@Space               [toggle-item here]	;@@ let 'toggle-item' switch between 'invert/exclude/replace depending on selection mode? 
				;@@ leverage key->plan here:
				;@@ also both move and select should call pre-render to add necessary items into the map
				@Up                  [move-cursor/select line-up]
				@Down                [move-cursor/select line-down]
				@PageUp              [move-cursor/select page-up]
				@PageDown            [move-cursor/select page-down]
				@Home                [move-cursor/select near-head]
				@End                 [move-cursor/select near-tail]
				@Ctrl+Up             [move-cursor line-up]
				@Ctrl+Down           [move-cursor line-down]
				@Ctrl+PageUp         [move-cursor page-up]
				@Ctrl+PageDown       [move-cursor page-down]
				@Ctrl+Home           [move-cursor far-head]
				@Ctrl+End            [move-cursor far-tail]
				@Shift+Up            [select-range/move/mode line-up   'extend]	;@@ let it dispatch into move-cursor in single item mode?
				@Shift+Down          [select-range/move/mode line-down 'extend]
				@Shift+PageUp        [select-range/move/mode page-up   'extend]
				@Shift+PageDown      [select-range/move/mode page-down 'extend]
				@Shift+Home          [select-range/move/mode near-head 'extend]
				@Shift+End           [select-range/move/mode near-tail 'extend]
				@Ctrl+Shift+Up       [select-range/move/mode line-up   'include]
				@Ctrl+Shift+Down     [select-range/move/mode line-down 'include]
				@Ctrl+Shift+PageUp   [select-range/move/mode page-up   'include]
				@Ctrl+Shift+PageDown [select-range/move/mode page-down 'include]
				;; it's dangerous to select items with far-jump (can be billions), so only movement allowed
				;; so e.g. instead of treating Ctrl+Shift+End as Shift+(Ctrl+End), it is treated as Ctrl+(Shift+End): 
				@Ctrl+Shift+Home     [select-range/move/mode near-head  'include]
				@Ctrl+Shift+End      [select-range/move/mode near-tail  'include]
			] [bubble]
		]
	]

	grid-view: below 'scrollable [
		grid: [													;-- grid translation automatically accounts for the header/data location
			/headers [
				;; down handler is not on a cell, so it can work inbetween cells
				down (xy)
				;@@ subtract from event/moved and bubble for 'over' only
				down + over (xy) [sink  select-range/move/whole grid/selected/1 .. xy]	;@@ /whole to select whole cols/rows?
			]
			/content [
				;@@ should select-range here be named select-area?
				;@@ make selection work on a plain grid, inbetween cells
				down (xy)
				;@@ subtract from event/moved and bubble for 'over' only
				down + over (xy) [sink  select-range/move grid/selected/1 .. xy]
			]
		
			;; guidelines: https://www.w3.org/WAI/ARIA/apg/patterns/grid/
			key [
				sink
				;@@ can key->plan apply? or this is hardcoded behavior?
				unless match-key event [ 
					; @SelectAll		[select-range far-head .. far-tail]	;@@ these have to evaluate into a pair, or pass them to 'locate'?
					@SelectAll		[select-range everything]		;@@ these have to evaluate into a pair, or pass them to 'locate'?
					@Copy			[copy-selection/clip]
					@Ctrl+Space		[select-columns cursor/x]
					@Shift+Space	[select-rows    cursor/y]
					@Up				[extend-selection/move row-up]		;@@ /move should autopan
					@Down			[extend-selection/move row-down]
					@Left			[extend-selection/move cell-left]
					@Right			[extend-selection/move cell-right]
					@PageUp			[extend-selection/move page-up]
					@PageDown		[extend-selection/move page-down]
					@Home			[extend-selection/move near-head]
					@End			[extend-selection/move near-tail]
					@Ctrl+Up
					@Ctrl+PageUp	[extend-selection/move column-head]
					@Ctrl+Down
					@Ctrl+PageDown	[extend-selection/move column-tail]
					@Ctrl+Left		[extend-selection/move row-head]
					@Ctrl+Right		[extend-selection/move row-tail]
					@Ctrl+Home		[extend-selection/move far-head]
					@Ctrl+End		[extend-selection/move far-tail]
				] [bubble]
			]
		]
	]

	switch:    [click [switch/state: not switch/state]]
	
	link:
	data-clickable: 
	clickable: [
		;@@ let the style use /lit? facet
		over (xy) [clickable/lit?: xy inside? space]			;-- possible on-hover highlight
		down      [clickable/pushed?: yes]						;-- possible on-down highlight
		up        [clickable/pushed?: no]
		click     [run-action]
	]
	
	menu: [
		/list
		/ring [
			/round-clickable
			/clickable above 'clickable [
				click [sink  popups/hide 'all]					;@@ make this hide all(?) popups? or just this menu?
			]
		]
	]

	button: above 'clickable [									;-- focusable unlike `clickable` space
		key key-up [
			unless match-key event [
				@Enter @Space [
					unless button/pushed? [run-action]			;-- runs only on first key
					button/pushed?: event/type = 'key
				]
			] [bubble]
		]
	]

	field: [
		key [
			;@@ leverage key->plan here
			any [
				match-key event [
					@Enter [run-action]							;@@ let field have an action attached? or let form catch enter?
				]
				unless empty? plan: key-plan field event [using field plan]	;@@ let key-plan also execute it?
				is-printable? event [insert-data here event/key]
				bubble
			]
		]
		
		down (xy) [
			select-range none
			move-caret frame/point->caret xy
		]
		down + over (xy) [
			select-range frame/point->caret xy
		]
		
		focus   [field/caret/visible?: yes]						;@@ let /visible be set from focus state? just invalidate here?
		unfocus [field/caret/visible?: no]
	]

	slider: [
		down (xy)
		down + over (xy) [slider/offset: frame/x->offset xy/x]
		
		key [
			;@@ use key->plan here??
			unless match-key event [							;@@ let it auto-bubble since it's used in events only anyway?
				@Left  @Up		[shift-knob/by negate slider/step]
				@Right @Down	[shift-knob/by        slider/step]
				@PageUp			[shift-knob/by negate max 10% step * 20]
				@PageDown		[shift-knob/by        max 10% step * 20]
				@Home			[shift-knob 0%]				;@@ near-head?
				@End			[shift-knob 100%]			;@@ near-tail?
			] [bubble]
		]
		
		focus unfocus [invalidate slider]
	]
]

