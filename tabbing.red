Red [
	title:   "Tabbing support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
	notes:   {Extends %common/tabbing.red}
]

;; requires events.red & focus.red, common/tabbing.red
#assert [object? tabbing]

;; handler for faces remains the same
;; it should not fire when host is focused (handled by the finalizer below),
;; and that is ensured by host not having a 'focusable flag (in vid.red)
;; scaffolding must be extended to work with spaces as well:
do with tabbing/window-walker [
	window?:     function [face [object!]] [all [is-face? face  face/type = 'window]]
	next-linked: function [face [object!]] [all [is-face? face  select face/options 'next]]
	prev-linked: function [face [object!]] [all [is-face? face  select face/options 'prev]]
	pane-of:     :traversal/pane-of
	has-child?:  function [face [object!]] [not empty? pane-of face]
	first-child: function [face [object!]] [
		all [
			pane: pane-of face
			pos:  find pane object!
			pos/1
		]
	]
	last-child:  function [face [object!]] [
		all [
			pane: pane-of face
			pos:  find/last pane object!
			pos/1
		]
	]
	next-child:  function [parent [object!] child [object!]] [
		all [
			pane: pane-of parent
			pos:  any [find/same/tail pane child  pane]			;-- if child is absent default to 1st drawn
			pos:  find pos object!
			pos/1
		]
	]
	prev-child:  function [parent [object!] child [object!]] [
		all [
			pane: pane-of parent
			pos:  any [find/same pane child  tail pane]			;-- if child is absent default to last drawn
			pos:  find/reverse pos object!
			pos/1
		]
	]
	parent-of:   function [child [object!]] [
		all [
			parent: child/parent
			any [
				not is-face? parent
				parent/type <> 'screen							;-- window is the last allowed parent
			]
			parent
		]
	]
]

;; tabbing visitor must now be able to focus into first/last space on the host
tabbing/visitor: function [parent [object! none!] child [object!]] [
	if all [
		focus/*ace-focusable? child
		focus/*ace-enabled?   child
	][ 
		set-focus child
		break
	]
]

;; handler for spaces - only eats Tab key if space didn't process it
;; has to be `key` event (if it's key-down, the following `key` event after refocus goes into the wrong space)
;@@ consider reacting to key-down and consuming the next key/key-up events when refocused
register-finalizer [key] function [space [object!] path [block!] event [map!]] [
	all [
		event/key = #"^-"
		not event/ctrl?									;-- ctrl-tab must mean smth else
		not stop?										;-- was not eaten by any space
		new: focus/find-next-focal-*ace (pick [back forth] event/shift?)
		set-focus new
	]
]