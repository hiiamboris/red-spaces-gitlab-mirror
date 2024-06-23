Red [
	title:   "Popup windows support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;; requires events, templates, vid, reshape

;@@ menu command should be able to access the space that opened the menu! - bind it!

declare-template 'hint/box [
	margin: 20x10
	origin: (0,0)	#type =? [point2D! none!]			;-- `none` disables the arrow display (when it's not precise)
]

;@@ should it be here or in vid.red?
lay-out-menu: function [
	spec [block!]
	; /title heading [string!]
	/local code name space value tube list flags radial? round?
][
	;@@ preferably VID/S should be used here and in hints above
	row*:        clear []								;-- space names of a single row
	menu*:       clear []								;-- row names list
	
	=menu=:      [opt =flags= collect into row* [any =menu-item=] #expect end]
	=flags=:     [ahead block! into [any =flag=]]
	=flag=:      [set radial? 'radial | set round? 'round]
	=menu-item=: [not end =content= (do new-item) ahead #expect [paren! | block!] [=code= | =submenu=]]
	=content=:   [ahead #expect [word! | object! | string! | char! | image! | logic!] some [=data= | =name= | =space=]]
	=data=:      [set value [string! | char! | image! | logic!] keep (VID/wrap-value value no)]
	=name=:      [set name word! (#assert [templates/:name]) keep (make-space name [])]
	=space=:     [set space object! (#assert [space? space]) keep (space)]
	; =submenu=:   [ahead block! into =menu=]	;@@ not yet supported
	=code=:      [set code paren! (item/command: code)]
	
	new-item: [
		append menu* item: make-space 'clickable [
			type:    either all [radial? round?] ['round-clickable]['clickable]	;@@ better name??
			margin:  4x4
			color:   none								;-- used for on-hover highlighting
			content: make-space 'tube [spacing: 10x5]
		]
		if radial? [item/limits: 40x40 .. none]			;-- ensures item is big enough to tap at
		;; stretch first text item by default (to align rows), but only if there's another item and no explicit <->
		any [
			not pos: locate row* [.. /type = 'text]		;-- only auto-insert separator after text
			single? pos									;-- don't insert separator at tail
			locate row* [.. /type = 'stretch]			;-- or if already got a separator
			insert next pos make-space '<-> []
		]
		tube: item/content
		tube/content: flush head row*
	]
	parse spec =menu=
	
	list: either radial? [
		make-space 'ring []
	][	make-space 'list [axis: 'y margin: 4x4]
	]
	list/content: flush menu*
	; either title [
		; h-box: make-space 'box [content: make-space 'text [text: heading flags: [bold]]]
		; inner: make-space 'list [axis: 'y margin: 0x4 spacing: 0x0]
		; inner/content: reduce [h-box list]
	; ][
		inner: list
	; ]
	menu: make-space 'cell [type: 'menu  content: inner]
	menu
]

popups: context [
	stack: make hash! 4									;-- currently visible popup faces - single stack for all windows
	
	hint-delay: 0:0:0.5									;-- for hints to appear
	; menu-delay: 0:0:0.5									;-- for submenus to appear on hover

	save: function [
		level  [integer!] ">= 1" (level >= 1)
		face   [object!] "Popup face"
	][
		change enlarge stack level - 1 none face
	]

	hide: function [
		"Hides popups from given level or popup face"
		level [integer! (level >= 1) object! (face? level)] ">= 1 or face"
	][
		old: either integer? level [at stack level][find/same stack level]
		if empty? old [exit]
		#debug popups [#print "hiding popups from (mold/only reduce [level])"]
		shown: sift old [face .. /state /parent]
		foreach face shown [
			window: window-of face
			remove find/same window/pane face
		]
		clear old
		focus/restore									;-- if popup was focused, need to refocus
	]

	show: function [
		"Show a popup at given offset, hiding the previous one(s)"
		space  [object!] "Space or face object to show" (any [space? space is-face? space])
		offset [planar!] "Offset on the window"
		/in window: focus/window [object! none!] "Specify parent window (defaults to focus/window)"
		/owner parent [object! none!] "Space or face object; owner is not hidden"
		/fit "Adjust popup offset for best display if it doesn't fit as is"
	][
		#debug popups [#print "about to show popup (space/type):(space/size) at (offset)"] 
		if space? face: space [							;-- automatically create a host face for it
			face: make-face 'host
			face/space: space
		]
		face/offset: offset
		if host? face [
			if zero? face/size [face/size: none]		;-- hint for render to set its size
			face/draw: render face
		]
		if fit [face/offset: clip 0x0 offset window/size - face/size]
		
		level: 1
		if parent [
			if space? parent [parent: host-of space]
			#assert [find/same stack parent]
			level: 1 + index? find/same stack parent
			window: window-of parent
		]
		
		hide level
		primed/text: none								;-- without this some event asynchrony may trigger hint redisplay and popup hide
		save level face
		unless find/same window/pane face [append window/pane face]
		face											;-- return the popup face
	]

	get-hint: function [
		"Get shown hint host; none if not shown"
	][
		all [
			host: last stack							;-- hint can only be the top level
			host? host
			host/space
			host/space/type = 'hint						;@@ REP 113
			host
		]
	]
	
	get-hint-text: function [
		"Get text of the shown hint; none if not shown"
	][
		all [
			host: get-hint
			host/parent									;-- must be visible
			host/space/content/text
		]
	]

	show-hint: function [
		"Show a hint around pointer in window"
		text    [string!] "Text for the hint"
		pointer [planar!]
		/in window [object!] "Specify parent window (defaults to focus/window)"
	][
		if text =? get-hint-text [exit]					;-- don't redisplay an already shown hint; sameness test makes sense in e.g. grid-ui
		#debug popups [#print "about to show hint (mold text) at (pointer)"] 
		
		center: window/size / 2
		above?: center/y < pointer/y					;-- placed in the direction away from the closest top/bottom edge
		
		host: make-face 'host
		host/rate: none									;-- unlike menus, hints should not add timer pressure
		;; hint is transparent so it can have an arrow
		host/color: svmc/panel + 0.0.0.254
		render host/space: hint: first lay-out-vids [	;-- render sets hint/size
			hint [text text= text] origin= either above? [(0,1)][(0,0)]	;-- corner where will the arrow be (cannot be absolute - no size yet)
		]
		
		offset: pointer + either above? [2 . (-2 - hint/size/y)][2x2]	;@@ should these offsets be configurable or can I infer them somehow?
		limit: window/size - hint/size
		fixed: clip offset 0x0 limit					;-- adjust offset so it's not clipped
		if fixed <> offset [
			offset: fixed
			hint/origin: none							;-- disable arrow in this case
			invalidate hint
		]
		show/in host offset window
	]
	
	hide-hint: function ["Hide hint if it is displayed"] [
		if host: get-hint [hide host]
	]
	
	show-menu: function [
		"Show a popup menu at given offset"
		menu    [block!] "Written using Menu DSL"
		offset  [planar!]
		/owner parent  [object!] "Space or face object; owner is not hidden"
		/in    window  [object!] "Specify parent window (defaults to focus/window)"
		/title heading [string!] "Provide a heading string for the menu" 
		;@@ maybe also a flag to make it appear above the offset?
	][
		host: make-face/spec 'host [rate 25]			;-- reduced timer pressure
		render host/space: lay-out-menu/:title menu heading
		either radial?: has-flag? :menu/1 'radial [		;-- radial menu is centered
			offset: offset + host/space/content/origin
			host/color: svmc/panel + 0.0.0.254			;-- radial menu is transparent but should catch clicks that close it
		][
			fit: on										;-- adjust offset so it's not clipped
		]
		show/owner/in/:fit host offset parent window
	]

	primed: context [									;-- pending hint data
		text:      none
		show-time: now/utc/precise						;-- when to show next hint
		anchor:    (0,0)								;-- pointer offset of the over event (timer doesn't have this info)
	]

	;; event funcs internal data
	context [
		;; global space timers are not called unless event is processed, so timer needs a dedicated event function
		insert-event-func 'spaces-hint-popup auto-show-hint: function [host event] [	;-- displays hints across all host faces when time hits
			all [
				event/type = 'time
				host? host								;-- a host face?
				space? host/space						;-- has a space assigned?
				primed/text								;-- hint is available at current pointer offset
				now/utc/precise >= primed/show-time		;-- time to show it has come
				show-hint/in primed/text primed/anchor event/window
				none   									;-- the event can be processed by other handlers
			]
		]
		
		;; searches the path for a defined facet (lowest/innermost one wins)
		find-facet: function [path [block!] name [word!] types [datatype! typeset!]] [
			type-check: pick [ [types =? type? value] [find types type? value] ] datatype? types
			path: reverse append clear [] path			;-- search order from the innermost
			foreach [_ space] path [					;@@ use for-each/reverse when fast, or locate/back
				value: select space name
				if do type-check [return :value]
			]
			none
		]	
		
		travel: func [event [map!]] [					;-- distance from hint show point to current point
			distance? primed/anchor face-to-window event/offset event/face
		]
		maybe-hide-hint: function [event [map!]] [
			if any [
				event/away?								;-- moved off the hint; away event should never be missed as it won't repeat!
				10 <= travel event						;-- distinguish pointer move from sensor jitter
			][
				hide-hint
			]
			primed/text: none							;-- abort primed hint (if any)
		]
		
		
		;; over event should be tied to spaces and is guaranteed to fire even if no space below
		register-previewer [over] function [
			space [object! none!] path [block!] event [map!]
		][
			; #assert [event/window/type = 'window]
			unless head? path [exit]					;-- don't react on multiple events on the same path
			
			either popup: find/same stack face: event/face [	;-- hovering over a popup face
				;@@ or should I allow popup menus to show hints too?
			    either hint: all [face/space face/space/type = 'hint] [	;-- over a hint
					maybe-hide-hint event
				][
					hide either event/away? [popup/1][1 + index? popup]	;-- hide upper levels or the one pointer just left
				]
			][													;-- hovering over a normal host
				either all [
					space										;-- not on empty area
					not event/away?								;-- still within the host
					text: find-facet path 'hint string!			;-- hint is enabled for this space or one of its parents
				][
					;; prime new hint display after a delay
					primed/text:   text
					primed/anchor: face-to-window event/offset event/face
					unless get-hint-text [						;-- delay only if no other hint is visible, else immediate
						primed/show-time: now/utc/precise + hint-delay
					]
				][												;-- hint-less space or no space below or out of the host
					maybe-hide-hint event
				]
			]
		]
	
		;; context menu display support
		register-finalizer [alt-up] function [					;-- finalizer so other spaces can eat the event
			space [object! none!] path [block!] event [map!]
		][
			;@@ maybe don't trigger if pointer travelled from alt-down until alt-up? 
			if all [
				head? path										;-- don't react on multiple events on the same path
				menu: find-facet path 'menu block!
			][
				;; has to be under the pointer, so it won't miss /away? event closing the menu
				offset: (-1,-1) + face-to-window event/offset event/face
				hide-hint
				show-menu/in menu offset event/window
			]
		]
	
	]
]



