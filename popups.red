Red [
	title:   "Popup windows support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;; requires events, templates, reshape

;@@ ideally I want a stick pointing to the original pointer offset: it will make hints clearer on what they refer to
;@@ but long as face itself cannot be transparent, nothing can visually stick out of it, so no luck - see REP #40

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

templates/hint: make-template 'cell [margin: 5x5]		;-- renamed for styling

popup-registry: make hash! 2

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
	unless face: pick stack level + 1 [
		change (enlarge stack level none) face: make-face 'host
	]
	face
]

show-popup: function [
	"Show a popup in the WINDOW at LEVEL and OFFSET"
	window [object!]  "Each window has it's own popups stack"
	level  [integer!] ">= 0"
	offset [pair!]    "Desired offset (adjusted to not be clipped)"
	face   [object!]  "Previously created popup face"
][
	limit: window/size - face/size
	face/offset: clip [0x0 limit] offset
	unless level = 0 [									;-- no need to hide the hint - it's reused
		hide-popups window 0							;-- hide hints if menu was shown
		hide-popups window level + 1
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
	either level = 0 [
		remove find/same window/pane stack/1			;-- only hide the hint
	][
		foreach face pos: skip stack level [			;-- hide all popups but the hint
			remove find/same window/pane face
		]
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
		hint: make-popup window 0						;@@ working around #5131 here, can't use `layout`
		hint/rate: none									;-- unlike menus, hints should not add timer pressure
		space: get hint/space: make-space/name 'hint []
		space/content: make-space/name 'text compose [text: (text)]
		hint/extra: reduce [text none]					;-- text for `hint-text?`, none for pointer travel estimation
		hint/size: none									;-- to make render set face/size
		hint/draw: render hint
		
		center: window/size / 2
		above?: center/y < pointer/y					;-- placed in the direction away from the closest top/bottom edge
		offset: either above? [hint/size * 0x-1 + 8x-8][8x16]	;@@ should these offsets be configurable or can I infer them somehow?
		show-popup window 0 pointer + offset hint 
	]
]

lay-out-menu: function [spec [block!] /local code' data'] reshape [	;@@ DSL is ~20% implemented only
	;@@ preferably VID/S should be used here and in hints above
	=menu=:      [any =menu-item= !(expected end)]
	=menu-item=: [=layout= opt =hotkey= =action=]
	=layout=:    [not end set data' !(expected [string! | block!]) (
		append list/item-list anonymize 'clickable item: make-space 'clickable [data: data']
	)]
	=hotkey=:    [issue!]
	=action=:    [ahead !(expected [block! | paren!]) =code= | =submenu=]
	=submenu=:   [ahead block! into =menu=]
	=code=:      [set code' paren! (item/command: code')]
	
	list: none
	layout: make-space/name 'cell [						;@@ must be 'menu
		content: make-space/name 'list [axis: 'y set 'list self]
	]
	parse spec =menu=
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
		space [object! none!] path [block!] event [event! none!]
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
		space [object! none!] path [block!] event [event! none!]
	][
		if menu: find-field path 'menu block! [
			;; has to be under the pointer, so it won't miss /away? event closing the menu
			offset: -1x-1 + face-to-window event/offset event/face
			reset-hint event
			show-menu event/window 1 offset menu
		]
	]

	;@@ should context menu eat next click outside of it? I'm not convinced on the necessity
]

