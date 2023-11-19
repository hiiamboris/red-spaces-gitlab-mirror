Red [
	title:   "DROP-BOX and DROP-FIELD widgets for Spaces"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Current limitations:
		- no scaling/rotation/skew is expected in all parents of drop-downs (track REP #144)
		- lists themselves are clipped by the host (track REP #40)
	}
]


context with spaces/ctx expand-directives [
	on-box-data-change: function [space [object!] word [word!] data [block! hash!]] [
		space/selected: any [:data/1 copy {}]
	]
	
	on-field-data-change: function [space [object!] word [word!] data [block! hash!]] [
		space/selected: to string! any [:data/1 {}]
	]
	
	;; this prevents modifications in field text from affecting the original data set
	on-field-selected-change: function [space [object!] word [word!] text [string!]] [
		either find/same space/data text [
			space/selected: copy text					;-- this reenters the same func with a copy
		][
			space/spaces/box/text: text
		]
	]
	
	;; used to spawn very similar drop-box and drop-field
	;; otherwise `box` space in `drop-field` would be created twice (1st in drop-box, then replaced in drop-field)
	box-skeleton: [
		spaces: object [
			arrow:  make-space 'triangle  [dir: 's size/x: 14]
			;; button is used to enlarge clickable area size around triangle in case row is thick:
			button: make-space 'clickable [weight: 0 margin: 2 content: arrow]
			box:    none								;-- set in specific templates
		] #type [object!]
		
		axes:       [e s]
		content:    reduce [spaces/box spaces/button]
		margin: spacing: 5
		
		list-pages: 5		#type [linear!]				;-- max drop-menu vertical size in drop-box's heights
	]
	
	;; they have to handle keys themselves (drop-box has no focusable field anyway)
	append focus/focusable [drop-box drop-field]
	
	;@@ not a showstopper, but should /selected be an index instead? or maybe add an index facet separately?
	;@@ it probably should not fill the canvas vertically - will need to make 2D /weight for that?
	declare-template 'drop-box/tube reshape [
		@(box-skeleton)
		spaces/box: make-space 'data-view []
		align:      -1x0	#push spaces/box/align
		content:    reduce [spaces/box spaces/button]
		data:       []		#type [block! hash!] :on-box-data-change
		selected:   {}		#push spaces/box/data
	]
	
	declare-template 'drop-field/tube reshape [
		@(box-skeleton)
		spaces/box: make-space 'field [type: 'inner-field]	;-- /type to remove focusability, event handlers, frame
		align:      -1x0								;@@ push this into field when/if it will have alignment support
		content:    reduce [spaces/box spaces/button]
		data:       []		#type [block! hash!] (parse data [any string!]) :on-field-data-change
		;; since field is editable, /selected facet is always a string, and always a copy
		selected:   {}		#type [string!] :on-field-selected-change
	]
	
	item-template: declare-class 'item-in-drop-menu/data-view [	;-- add highlight support to items ;@@ remove when it's generalized
		type:  'item
		wrap?: on
		lit?:  no			#type =? [logic!] :invalidates
	]
	
	show-list: function [
		"Drop down the list of choices for drop list widgets"
		window    [object!]
		drop-down [object!]
		offset    [planar!]
	][
		;@@ list must have a single selection support and key navigation!
		list: make-space 'cell [
			type:   'drop-menu
			owner:   drop-down
			margin:  drop-down/margin
			limits:  drop-down/size .. (drop-down/size * (1 by drop-down/list-pages))
			content: make-space 'list-view [
				selectable: 'single
				source: drop-down/data
				wrap-data: function [item-data [any-type!]] [
					item: make-space 'data-view item-template
					item/align: drop-down/align
					set/any 'item/data :item-data
					item
				]
			]
		]
		popups/show/in list offset window
		list
	]
	
	show-list-on-click: function [space path event] [
		corner: event/offset - path/2 + (space/size * 0x1)
		show-list event/window space face-to-window corner event/face
	]

	show-list-on-key: function [space path event] [
		box:    host-box-of space
		corner: box/1/x . box/2/y
		menu:   show-list event/window space face-to-window corner event/face
		set-focus menu/content							;-- let list-view handle up/down now
	]

	;@@ this is a kludge - I must find a better way to relay events
	pass-key-into-field: function [space path event] [
		path: compose [(head path) (space/spaces/box)]
		events/commands/pass							;-- otherwise stop flag will not let the event thru
		events/process-event path event [] yes
	]
	
	define-handlers [
		drop-box: [
			on-down [space path event] [show-list-on-click space path event]
			on-key [space path event] [
				switch event/key [
					#"^-" [pass exit]							;-- let tabbing thru
					down page-down [show-list-on-key space path event]
				]
			]
		]
		
		drop-field: [
			on-down [space path event] [
				if 'clickable <> get-safe 'path/3/type [pass exit]	;-- ignores down events outside button
				show-list-on-click space path event
			]
			on-key-down [space path event] [
				pass-key-into-field space path event
			]
			on-key [space path event] [
				switch/default event/key [
					#"^-" [pass exit]							;-- let tabbing thru
					down page-down [show-list-on-key space path event]
				] [pass-key-into-field space path event]
			]
			on-focus   [space path event] [space/spaces/box/caret/visible?: yes]
			on-unfocus [space path event] [space/spaces/box/caret/visible?: no]
		]
		
		inner-field: extends 'field []					;-- supports interactivity but not focusability
		
		drop-menu: [
			on-down [space path event] [
				unless set [item:] locate path [obj - .. /type = 'item] [pass exit]
				space/owner/selected: item/data
				popups/hide event/face
			]
			on-over [space path event] [						;-- on-hover item highlight
				unless set [item: item-xy:] locate path [obj - .. /type = 'item] [pass exit]
				item/lit?: item-xy inside? item
			]
			list-view: [;extends 'list-view [
				on-key [space path event] [
					switch/default event/key [
						#"^[" [popups/hide event/face]			;-- hide on escape
						#"^-" [popups/hide event/face pass]		;@@ this should not be required: just on-key-down on tab hiding popup
						#"^M" [
							owner: space/parent/owner
							owner/selected: owner/data/(space/cursor)
							popups/hide event/face
						]
					] [pass]
				]
				on-unfocus [space path event] [
					popups/hide event/face						;-- hide when blurred programmatically
				]
			]
		]
	]
	
	;@@ need an easier way to copy styles over, maybe as get-word/get-path
	set-style 'drop-menu  set-style 'drop-field get-style to path! 'cell	;-- add a frame
	;; no style for inner-field, but general selection and caret styles are still applicable
	
	define-styles [
		drop-box: [
			below: [line-width 1 box 1x1 (size - 1)]
			above: when focused? [						;-- unlike drop-field, requires focus indicator
				fill-pen off line-width 1 pen (styling/checkered-pen) box 3x3 (size - 3)
			]
		]
		drop-box/clickable/triangle:
		drop-field/clickable/triangle: [below: [line-width 1]]
		drop-menu/list-view/window/list/item: [			;-- on-hover item highlight
			below: when lit? [pen off fill-pen (opaque 'text 10%) box 0x0 (size)]
		]
	]
	
	facets: [
		block!	data
		left	[self/align/x: -1]						;@@ self/ is a workaround for #5312
		center	[self/align/x:  0]
		right	[self/align/x:  1]
	]
	extend VID/styles reshape [
		drop-box:   [template: drop-box    facets: @[facets]]
		drop-field: [template: drop-field  facets: @[facets]]
	]
];context with spaces/ctx expand-directives [

