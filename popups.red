Red [
	title:   "Popup windows support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;; requires events, templates, vid, reshape

;@@ for tooltips:
;@@ ideally I want a stick pointing to the original pointer offset: it will make hints clearer on what they refer to
;@@ but long as face itself cannot be transparent, nothing can visually stick out of it, so no luck - see REP #40

;@@ menu command should be able to access the space that opened the menu! - bind it!

{	;@@ document this
	Menu DSL - unlike View's default:
	
	menu: a block! [any menu-item]
	menu-item: [layout opt hotkey action]
	layout:    [string! | block!]
		string is interpreted simply as text,
		while block may include other data as accepted by data-view
	hotkey:    [issue!] e.g. #Ctrl+O
	action:    [code | menu] (block is a submenu in this case)
	code:      [paren!]
}

templates/hint: make-template 'box [margin: 20x10 origin: 0x0]

;@@ use a single stack maybe? not sure if View will handle cross-window face transfer though
popup-registry: make hash! 2

has-flag?: function [
	"Test if FLAGS is a block and contains FLAG"
	flags [any-type!]
	flag  [word!]
][
	none <> all [block? :flags  find flags flag]
]

is-popup?: function [									;-- must be blazing-fast, used in global event function
	"Check within WINDOW if FACE is a popup host; return popup level or none"
	window [object!] face [object!]
][
	all [
		found: find/same select/same popup-registry window face
		-1 + index? found
	]
]

get-popups-for: function [
	window [object!] "Each window has it's own popups stack"
][
	#assert [window/type = 'window]
	any [
		stack: select/same popup-registry window
		repend popup-registry [window stack: make hash! 4]
	]
	stack
]

save-popup: function [
	window [object!] "Each window has it's own popups stack"
	level  [integer!] ">= 0"
	face   [object!] "Popup face"
][
	#assert [level >= 0]
	stack: get-popups-for window
	change enlarge stack level none face
]

;@@ `layout` cannot work - see #5131, so have to reuse the faces and refrain from VID
make-popup: function [
	"Create a popup face of LEVEL but don't show it yet (reuse if exists)"
	window [object!]
	level  [integer!]
][
	stack: get-popups-for window
	either face: pick stack level + 1 [
		invalidate-face face
	][
		change (enlarge stack level none) face: make-face 'host
	]
	face
]

show-popup: function [
	"Show a popup in the WINDOW at LEVEL and OFFSET"
	window [object!]  "Each window has it's own popups stack"
	level  [integer!] ">= 0"
	offset [pair!]    "Offset on the window"
	face   [object!]  "Previously created popup face"
][
	face/offset: offset
	if level > 0 [										;-- no need to hide the hint - it's reused
		hide-popups window 0							;-- hide hints if menu was shown
		hide-popups window level + 1					;-- hide lower level menus
	]
	save-popup window level face
	unless find/same window/pane face [append window/pane face]
]

hide-popups: function [
	"Hides popup faces of a WINDOW from LEVEL and above"
	window [object!] "Each window has it's own popups stack"
	level [integer!] ">= 0; if zero, only hint is hidden"
][
	stack: get-popups-for window
	do-async [											;@@ workaround for #5132
		either level = 0 [
			if stack/1 [
				invalidate-face stack/1
				remove find/same window/pane stack/1	;-- only hide the hint
			]
		][
			foreach face pos: skip stack level [		;-- hide all popups but the hint
				invalidate-face face
				remove find/same window/pane face
			]
		]
	]
	show window
]

invalidate-face: function [
	"Remove all spaces used by HOST face from cache"
	host [object!]
][
	foreach path list-spaces host/space [
		invalidate-cache get last path
	]
]

hint-text?: function [
	"Get text of the shown hint for WINDOW; none if not shown"
	window [object!] "Each window has it's own popups stack"
][
	stack: get-popups-for window
	all [
		face: stack/1
		find/same window/pane face						;-- must be visible
		face/extra/1
	]
]

show-hint: function [
	"Immediately show a TEXT hint in the WINDOW around POINTER"
	window  [object!]
	pointer [pair!]
	text    [string!]
][
	unless text == old-text: hint-text? window [		;-- don't redisplay an already shown hint
		center: window/size / 2
		above?: center/y < pointer/y					;-- placed in the direction away from the closest top/bottom edge
		
		hint: make-popup window 0						;@@ working around #5131 here, can't use `layout`
		hint/rate: none									;-- unlike menus, hints should not add timer pressure
		space: get hint/space: make-space/name 'hint []
		space/content: make-space/name 'text compose [text: (text)]
		space/origin: either above? [0x1][0x0]			;-- corner where will the arrow be (cannot be absolute - no size yet)
		hint/extra: reduce [text none]					;-- text for `hint-text?`, none for pointer travel estimation
		hint/size: none									;-- to make render set face/size
		hint/draw: render hint
		;; hint is transparent so it can have an arrow
		hint/color: system/view/metrics/colors/panel + 0.0.0.254
		
		offset: pointer + either above? [2 by (-2 - hint/size/y)][2x2]	;@@ should these offsets be configurable or can I infer them somehow?
		limit: window/size - hint/size
		fixed: clip [0x0 limit] offset					;-- adjust offset so it's not clipped
		if fixed <> offset [
			offset: fixed
			space/origin: none							;-- disable arrow in this case
			invalidate-cache space
			hint/draw: render hint						;-- have to redraw content to remove the arrow
		]
		show-popup window 0 offset hint 
	]
]

;@@ should it be here or in vid.red?
lay-out-menu: function [spec [block!] /local code name tube list flags radial? round?] reshape [
	;@@ preferably VID/S should be used here and in hints above
	data*:       clear []								;-- consecutive data values
	row*:        clear []								;-- space names of a single row
	menu*:       clear []								;-- row names list
	
	=menu=:      [opt =flags= any =menu-item= #expect end]
	=flags=:     [ahead block! into [any =flag=]]
	=flag=:      [set radial? 'radial | set round? 'round]
	=menu-item=: [=content= (do new-item) ahead #expect [paren! | block!] [=code= | =submenu=]]
	=content=:   [ahead #expect [word! | string! | char! | image! | logic!] some [=data= | =space=]]
	=data=:      [collect into data* some keep [string! | char! | image! | logic!] (do flush-data)]
	=space=:     [set name word! (#assert [space? get/any name]) (append row* name)]
	; =submenu=:   [ahead block! into =menu=]	;@@ not yet supported
	=code=:      [set code paren! (item/command: code)]
	
	flush-data: [
		append row* VID/lay-out-data/only data*
		clear data*
	]
	new-item: [
		name: either all [radial? round?] ['round-clickable]['clickable]	;@@ better name??
		append menu* anonymize name item: make-space 'clickable [
			margin: 4x4
			content: anonymize 'tube set 'tube make-space 'tube [spacing: 10x5]
		]
		if radial? [item/limits: 40x40 .. none]			;-- ensures item is big enough to tap at
		;; stretch first text item by default (to align rows), but only if there's another item and no explicit <->
		any [
			empty? pos: find/tail row* 'text		
			find row* '<->
			find row* 'stretch
			insert pos in generic '<->
		]
		tube/item-list: flush row*
	]
	parse spec =menu=
	
	list: either radial? [
		make-space name: 'ring []
	][	make-space name: 'list [axis: 'y margin: 4x4]
	]
	list/item-list: flush menu*
	layout: anonymize 'menu make-space 'cell [
		content: anonymize name list
	]
	layout
]

show-menu: function [
	"Immediately show a menu LAYOUT at OFFSET and LEVEL in WINDOW"
	window  [object!]
	level   [integer!]
	offset  [pair!]
	menu    [block!] "Written using Menu DSL"
	;@@ maybe also a flag to make it appear above the offset?
][
	#assert [level > 0]
	face: make-popup window level
	face/rate:  10										;-- reduced timer pressure
	face/space: lay-out-menu menu
	face/size:  none									;-- to make render set face/size
	face/draw:  render face
	either radial?: has-flag? :menu/1 'radial [			;-- radial menu is centered ;@@ REP #113
		cont: get select get face/space 'content
		offset: offset + cont/origin
		;; radial menu is transparent but should catch clicks that close it
		face/color: system/view/metrics/colors/panel + 0.0.0.254
	][
		limit: window/size - face/size
		offset: clip [0x0 limit] offset					;-- adjust offset so it's not clipped
	]
	show-popup window level offset face
]


hint-delay: 0:0:0.5										;-- for hints to appear
; menu-delay: 0:0:0.5										;-- for submenus to appear on hover

context [
	;; event function that displays hints across all host faces when time hits
	popup-event-func: function [host event] [
		all [
			event/type = 'time
			word? select host 'space					;-- a host face?
			on-time host event
			none   										;-- the event can be processed by other handlers
		]
	]
	unless find/same system/view/handlers :popup-event-func [
		insert-event-func :popup-event-func
	]
	
	;; global space timers are not called unless event is processed, so timer needs a dedicated event function
	hint-text: none
	show-time: now/utc/precise							;-- when to show next hint
	anchor:    0x0										;-- pointer offset of the over event (timer doesn't have this info)
	on-time: function [host event] [
		all [
			hint-text
			show-time <= now/utc/precise
			show-hint event/window anchor hint-text
		]
	]

	;; searches the path for a defined field (lowest one wins)
	find-field: function [path [block!] name [word!] types [datatype! typeset!]] [
		path: tail path
		type-check: pick [ [types =? type? value] [find types type? value] ] datatype? types
		until [											;@@ use for-each/reverse
			path: skip path -2
			space: get path/1
			value: select space name
			if do type-check [return :value]
			head? path
		]
		none
	]	
	
	reset-hint: func [event [event!]] [
		if hint-text [
			hint-text: none
			anchor: face-to-window event/offset event/face
		]
		if any [
			event/away?									;-- moved off the hint; away event should never be missed as it won't repeat!
			10 <= travel event							;-- distinguish pointer move from sensor jitter
		][
			hide-popups event/window 0
		]
	]
	
	travel: func [event [event!]] [
		distance? anchor face-to-window event/offset event/face
	]
	
	;; over event should be tied to spaces and is guaranteed to fire even if no space below
	register-previewer [over] function [
		space [object! none!] path [block!] event [event!]
		/extern hint-text show-time anchor
	][
		; #assert [event/window/type = 'window]
		either level: is-popup? window: event/window host: event/face [	;-- hovering over a popup face
			either level = 0 [
				reset-hint event						;-- no hint can trigger other hint
			][
				;@@ this is very simpistic now - need multiple levels support
				if event/away? [hide-popups event/window level]
				; reset-hint event
			]
		][												;-- hovering over a normal host
			either all [
				space
				not event/away?
				text: find-field path 'hint string!		;-- hint is enabled for this space or one of it's parents
			][
				hint-text: text
				anchor: face-to-window event/offset event/face
				unless hint-text? window [				;-- delay only if no other hint is visible
					;; by design no extra face should be created until really necessary to show it
					;; so creation is triggered by timer, renewed on each over event
					show-time: now/utc/precise + hint-delay		;-- show tooltip at some point in the future
				]
			][											;-- hint-less space or no space below
				reset-hint event
			]
		]
	]

	
	;; context menu display support
	register-finalizer [alt-up] function [				;-- finalizer so other spaces can eat the event
		space [object! none!] path [block!] event [event!]
	][
		;@@ maybe don't trigger if pointer travelled from alt-down until alt-up? 
		if menu: find-field path 'menu block! [
			;; has to be under the pointer, so it won't miss /away? event closing the menu
			offset: -1x-1 + face-to-window event/offset event/face
			reset-hint event
			show-menu event/window 1 offset menu
		]
	]

	;; eats touch events outside the visible menu window
	register-previewer [down] function [				;-- previewer so it takes precedence on menu things
		space [object! none!] path [block!] event [event!]
	][
		stack: get-popups-for event/window
		if all [
			menu: stack/2								;-- menu exists
			find/same event/window/pane menu			;-- menu visible
			not same? event/face menu					;-- click didn't land on menu host
		][
			hide-popups event/window 1
			stop										;-- eat the event, closing the menu
		]
	]
]

