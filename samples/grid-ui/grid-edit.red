Red [
	title:   "Feature-packed editable grid demo"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Features:
		- columns can be resized by dragging area between column headers (very slow :/)
		- columns can be reordered by Alt+dragging column headers
		- columns can be shown/hidden from the right-click menu on any column header
		- table can be sorted by any column in descending or ascending order using arrow buttons in the column header
		- multiple columns can be selected by dragging across column headers or clicking and Ctrl-clicking
		- multiple rows can be selected by dragging across row headers or clicking and Ctrl-clicking
		- whole grid data can be selected by clicking on the header intersection "#" or by Ctrl+A key combo
		- limited 2D area can be selected by dragging from between non-header cells
		- cursor navigation across grid using arrow keys (also supports jumps with Ctrl)
		- keyboard selection of 2D data area using Shift and arrow keys (including Ctrl+Shift)
		- whole rows and columns can be selected with Ctrl+Space and Shift+Space keys, and extended with Shift+arrows 
		- cells and headers can be edited with F2 or Enter key press (Enter or Esc to commit)
		- headers can be renamed with Ctrl+F2 key combo
		- selected rows and columns can be removed with Ctrl+- key combo, new ones prepended with Ctrl++
		- copying and pasting using Ctrl+C/Ctrl+V/Ctrl+X/Shift+Ins/Shift+Del standard key combos 
		- undo and redo capability using Ctrl+Z/Ctrl+Shift+Z standard key combos
		  (currently does not affect cell renaming - should it?)
		- big cell content is shown in the tooltip above it
		- import and export of data in .red, .csv and .redbin formats (to compress it, also add .gz)
		- automatic state saving and restoration when editor is closed and reopened
	}
]

;; include Spaces core
#include %../../everything.red

;; include database funcs
#include %database.red

;; include state management
#include %../../../common/data-store.red

context with spaces/ctx expand-directives [
					
	;; database source (uncompressed is too big to put into the repo, compressed is too slow to load)
	db-origin:  %exoplanets.red.gz
	
	;; database in its optimal state (fast to load, but big and slow to save)
	db-optimal: %database.redbin
	
	;; populate with exoplanets data...
	either exists? db-optimal [
		print "Loading DB..."
		database/load db-optimal
	][
		#print "No database found. Loading from the source '(db-origin)'..."
		database/load db-origin
		; #print "Saving converted DB as '(db-optimal)'..."
		; database/save db-optimal
	]
	
	
	;; let 'filter' be a special kind of 'field' that knows what column it belongs to and can update it when edited
	;; it will be used for per-column cell filtering
	declare-template 'filter/field [
		source: none											;-- previous field text for change detection
		update: does [database/update-filter source/column]
	]
	;; inherit its style from 'field'
	set-style 'filter get-style to path! 'field
	;; make it focusable as well
	append focus/focusable 'filter
	;; behavior is extended by an 'update' call after a key press
	define-handlers [
		filter: extends 'field [
			late on-key [space path event] [
				if space/text <> space/source/text [			;-- case-insensitive
					space/source/text: copy space/text
					space/update
				]
			]
		]
	]
	
	;; add mandatory 'hint' field into data-view (basis for grid cells), to avoid replacing the stock 'wrap-data' wrapper
	;; this will allow us to simply assign /hint to any cell when we need to
	declare-template 'data-view/data-view [hint: none]
	
	;; a kludge to create a scrollable that doesn't catch focus on clicks (trick is not adding it to focus/focusable list)
	;; because we don't want a click on a header cell (which is a scrollable) to steal focus from the grid-edit
	declare-template 'inactive-scrollable/scrollable []
	;; it inherits the style and behavior of scrollable
	set-style 'inactive-scrollable get-style to path! 'scrollable
	define-handlers [inactive-scrollable: extends 'scrollable []]
	
	;; grid-edit will be an extension of grid-view with all the added bells and whistles
	append focus/focusable 'grid-edit
	;; inherit styles for grid-edit from grid-view (currently kludgey, until better inheritance is designed)
	set-style 'grid-edit get-style to path! 'grid-view
	set-style 'grid-edit/window get-style 'grid-view/window
	
	declare-template 'grid-edit/grid-view [
		timeline: make timeline! []								;-- add undo/redo capability
		edited:   none	#type [pair! none!]						;-- address of the cell currently being edited
		
		;; some default configuration
		window/pages: 5x5										;-- decrease the window size (in pages) to speed it up
		grid/autofit: none										;-- disable autofitting of content which is not scalable to big data
		behavior/draggable:  'scroll							;-- disable panning by dragging, scroll instead when leaving the viewport (useful for selection by dragging)
		behavior/selectable: 'multi								;-- allow multiple cell selection
		
		;; helper function used after sorts and filters
		;; grid assumes its content does not change all the time (an important optimization)
		;; so we have to manually clear the cells cache
		;; header-cache is a kludge to keep filters and headers from being rebuilt (so they can retain focus)
		refresh: function [/headers] [
			unless empty? grid/content [						;-- avoid repopulating it with header cache after a full cleanup
				clear grid/content
				unless headers [extend grid/content header-cache]
			]
			invalidate grid
		]
		header-cache: #[]
		
		;; cell wrapper that caches header cells separately and also sets alignment for the filters cell
		grid-wrap-space: :grid/wrap-space
		grid/wrap-space: function [xy [pair!] space [object! none!]] [
			cell: grid-wrap-space xy space
			if xy/y <= 2 [header-cache/:xy: cell]				;-- stash created headers and filters rows
			cell/align: either xy = 1x2 [1x0][-1x0]				;-- right-align "Filters:" cell
			cell
		]
		
		;; helper called by the grid-field to commit current changes
		commit-edit: function [] [
			cell:  grid/cells/pick edited
			old:   select (data/pick edited) 'text
			new:   either edited/y = 1
				[cell/content/content/1/content/text]			;@@ very inelegant way to address a field in the header cell :/
				[cell/content/text]
			unless old == new [
				left:  compose/deep [data/write (edited) (copy old)]
				right: compose/deep [data/write (edited) (copy new)]
				timeline/put self left right
				do right
			]
		]
				
		;; helper called on header sort button clicks
		sort-by-column: function [icol [integer!] b-up [object!] b-dn [object!] /reverse] [ 
			database/sort-by-column/:reverse icol
			b-up/content/text: pick ["△" "▲"] reverse
			b-dn/content/text: pick ["▼" "▽"] reverse
			refresh
		]
		
		;; helper used when hiding or showing a column from the popup menu
		flip-column: function [colid [integer!]] with database [
			either is-column-shown? colid
				[hide-column colid]
				[show-column colid]
			refresh/headers
		]
		
		;; helper used to paste data into multiple cells
		set-many: function [cells [block!]] [
			foreach [addr text] cells [data/write addr text]
			refresh
		]
		
		
		;; database-provided data is extended by a headers row (objects stored here) and filters row (objects stored in the DB)
		;; in the current grid-view implementation, 'wrap-data' function doesn't have access to the cell address
		;; so any info has to be carried by the data itself (in this case by an object)
		
		;; header objects store the data that helps handle column header events
		make-header: function [icol [integer!]] [
			object [
				type:    'header
				text:    any [if icol > 0 [database/pick-header icol]  "#"]
				column:  icol
				edited?: (icol + 1 by 1) = edited
			]
		]
		;; field object used on a cell that is currently edited (it would be suboptimal to make all cells fields)
		make-field: function [txt [string!]] [
			object [
				type: 'field
				text: txt
			]
		]
		
		;; data source description for the grid
		;; it tells which cells contain values from the DB, filters, headers
		data: function [
			/size  "Get the grid size"
			/pick  "Get cell's content"
				pxy   [pair!]   "Cell address"
			/write "Change cell's content"
				wxy   [pair!]   "Cell address"
				value [string!] "New content"
		][
			case [
				size [
					1x2 + as-pair								;-- 1x2 = numbers column, headers row and filters row
						length? database/included/x
						length? database/included/y
				]
				pick [
					y: pxy/y  x: pxy/x - 1
					case [
						pxy = 1x1 [make-header 0]				;-- special header '#'
						pxy = 1x2 ["Filter:"]
						pxy/x = 1 [database/pick-row y - 2]		;-- row numbers column
						y = 1 [make-header x]					;-- headers row
						y = 2 [database/pick-filter x]			;-- filters row
						edited = pxy [							;-- currently edited cell
							make-field database/pick-value x y - 2
						]
						'else [database/pick-value x y - 2]		;-- normal cell
					]
				]
				write [
					#assert [
						wxy/x  > 1
						wxy/y <> 2
					]
					either wxy/y > 2
						[database/write-value  wxy/x - 1 wxy/y - 2 :value]
						[database/write-header wxy/x - 1           :value]
					; grid/invalidate-range wxy wxy
				]
			]
		]
		
		;; wrap-data takes cell's data and turns it into a space object to display inside a grid cell
		;; we extend the default wrapper to support headers, filters, editable cell, and add a hint
		gridview-wrap-data: :wrap-data
		wrap-data: function [item-data [any-type!]] [
			if object? :item-data [								;-- turn data object into a custom space tree
				type: select item-data 'type
				item-data: switch/default type [
					header [make-header-layout item-data]
					field [first lay-out-vids reshape [grid-field text= @(copy item-data/text)]]
				][
					make-space 'filter [
						source: item-data
						text: copy source/text
					]
				]
			]
			space: gridview-wrap-data :item-data				;-- default 'data-view' space supports space objects as data
			space/hint: has [addr] with space [					;-- display hint on cells that clip content
				if addr: grid-ctx/get-cell-address grid self [
					unless size +<= grid/cell-size? addr [content/text]	;@@ make the hint multiline?
				]
			]
			space
		]
		
		;; helper that creates a space tree for the column header with the sort buttons
		make-header-layout: function [data [object!]] [
			style: pick [grid-field text] data/edited?
			first lay-out-vids reshape [
				tube [
					inactive-scrollable [@[style] text= copy data/text] with [hscroll/size/y: 7]
						hint= "Drag to select, Alt+drag to reorder columns"
					style sort-buttons: vlist tight [			;-- style allows isolate b-up and b-dn words
						b-up: clickable [text "△"]
							hint= "Sort in ascending order"
							command= [sort-by-column         @[data/column] b-up b-dn]
						b-dn: clickable [text "▽"]
							hint= "Sort in descending order"
							command= [sort-by-column/reverse @[data/column] b-up b-dn]
					]
					sort-buttons
				]
			]
		]
		
		;; extend default draw with automatic refreshment after changes in the database
		gridview-draw: :draw
		draw: function [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			if database/update-included+ordered [refresh]		;-- refresh grid if database had pending commits
			drawn: gridview-draw/on canvas fill-x fill-y
			;@@ row-height?'s 1st render of cells is problematic: triggers parent sharing detection
			; grid/heights/1: grid/row-height? 1					;-- remember auto-estimated headers height
			drawn
		]
	];declare-template 'grid-edit/grid-view [
	
	;; 'grid-field' adds grid-edit related functionality to 'field'
	declare-template 'grid-field/field []
	set-style 'grid-field get-style to path! 'field				;-- inherit the style
	append focus/focusable 'grid-field							;-- make it focusable
	
	;@@ catch-tab? flag is a kludge used to block the default tabbing handler for grid-field
	;@@ its purpose is to carry the state from the on-key-down to the next on-key event (until better event comms are designed)
	catch-tab?: no
	define-handlers [
		grid-field: extends 'field [
			on-key [space path event] [
				either all [catch-tab? event/key = #"^-"] [stop/now][pass]
			]
			on-key-down [space path event] [
				gedit: above space 'grid-edit
				switch event/key [
					#"^[" #"^M" [
						if event/key = #"^M" [gedit/commit-edit]
						gedit/edited: none
						gedit/refresh/headers
						set-focus gedit
					]
					#"^-" up down [								;-- nav keys not handled by the field are used to move it
						size: gedit/grid/cells/size
						addr: gedit/edited
						addr: addr + case [
							event/key = 'up [0x-1]
							event/key = 'down [0x1]
							event/shift? [-1x0]
							'else [1x0]
						]
						if addr/x < 2 [addr/x: size/x  addr/y: addr/y - 1]
						if addr/x > size/x [addr/x: 2  addr/y: addr/y + 1]
						either all [2 < addr/y addr/y <= size/y] [
							gedit/commit-edit
							gedit/edited: addr
							gedit/refresh/headers
							render host-of gedit				;@@ kludge (can't focus a space that does not exist yet)
							cell: gedit/grid/cells/pick addr
							set-focus cell/content
							if event/key = #"^-" [set 'catch-tab? true]
						][
							pass
						]
					]
				]
			]
			; on-key [space path event] [stop/now]
			; on-key-up [space path event] [stop/now]
		]
		
		grid-edit: extends 'grid-view [
			;; on click: just a demo to receive clicks
			on-click [gedit path event] [
				set [grid: grid-offset: cell: cell-offset:] skip path 4		;-- skip 'grid-edit' and 'window'
				if 'cell = select cell 'type [
					cell-xy: first gedit/grid/locate-point/screen grid-offset
					#print "click on a cell (cell-xy)"
					pass										;-- let cell children handle the click
				]
			]
			
			;; right-click: shows enabled/disabled columns list
			on-alt-up [gedit path event] [
				; unless dragging?/from gedit [exit]
				; unless (abs drag-offset path) +<= 5x5 [exit]	;-- only show menu on clicks, not drags
				set [grid: grid-offset: cell: cell-offset:] skip path 4
				if 'cell <> select cell 'type [exit]
				cell-xy: first gedit/grid/locate-point/screen grid-offset
				if cell-xy/y <> 1 [exit]						;-- right click on a header
				rows: map-each colid database/ncols [
					shown?: database/is-column-shown? colid
					title:  database/pick-header/id colid
					reshape [
						clickable [
							row tight spacing= 5x0 [
								switch state= @(shown?) text text= @[title]
							]
						] target= @(gedit) command= [
							content/content/1/state: not content/content/1/state
							target/flip-column @(colid)
						]
					]
				]
				menu: first lay-out-vids reshape [cell [vlist margin= 0x5 [
					box center [text bold @("Select columns to show:")]
					scrollable vertical [vlist @[rows]] 0x100 .. (1.#inf, 300)
				]]]
				wxy: face-to-window (second head path) (host-of first head path)
				popups/show/fit menu wxy - 2
				; if dragging? [stop-drag]
			]
			
			;; do not allow children to override dragging with Alt on: let grid-view handle it
			on-down [gedit path event] [
				;; scrollable will remove children during start-drag but we need them for on-over, so handling it here
				start-drag path									
				
				if find event/flags 'alt [stop/now]
			]
			on-up [gedit path event] [
				if dragging? [stop-drag]
			]
			
			;; dragging cases not handled by the grid-view: columns resizing and rearrangement with Alt
			on-over [gedit path event] [
				unless dragging?/from gedit [exit]
				set [grid': grid-offset': cell': cell-offset':] skip drag-path 4
				set [grid:  grid-offset:  cell:  cell-offset: ] skip path 4
				set [cell-addr:  cell-offs: ] gedit/grid/locate-point/screen grid-offset
				set [cell-addr': cell-offs':] gedit/grid/locate-point/screen grid-offset'
				pass											;-- by default, pass event to children
				either find event/flags 'alt [
					if all [
						1 = cell-addr/y
						1 = cell-addr'/y
						cell-addr/x  > 1
						cell-addr'/x > 1
						cell-addr/x <> cell-addr'/x
					][
						colid1: database/pick-column (col1: cell-addr/x ) - 1	;-- excluding the row numbers column
						colid2: database/pick-column (col2: cell-addr'/x) - 1
						database/swap-columns colid1 colid2
						w1: grid/widths/:col1
						w2: grid/widths/:col2
						either w1 [grid/widths/:col2: w1][remove/key grid/widths col2]
						either w2 [grid/widths/:col1: w2][remove/key grid/widths col1]
						gedit/refresh/headers
						stop-drag
						start-drag path
						stop/now
					]
				][
					if cell-offs'/x < 0 [
						col:   cell-addr'/x - 1
						extra: first drag-offset path
						if all [col > 0 extra <> 0] [
							grid/widths/:col: 
								max grid/widths/min
								extra + any [
									grid/widths/:col 
									grid/widths/default
								] 
							gedit/refresh/headers
							stop-drag
							start-drag path
							stop/now
						]
					]
				]
			]
			
			;; keyboard-driven grid editing: copying/pasting of data, removal and insertion of columns and rows, undo/redo
			on-key-down [gedit path event] [
				case [
					find [#"^M" F2] event/key [edit?: on]
					all [event/ctrl? find [#"C" insert] event/key] [copy?: on]
					any [										;@@ use edit-keys?
						all [event/ctrl?  event/key = #"X"] 
						all [event/shift? event/key = 'delete]
					] [copy?: clear?: on]
					any [
						all [event/ctrl?  event/key = #"V"] 
						all [event/shift? event/key = 'insert]
					] [paste?: on]
					all [event/ctrl? event/key = #"+"] [extend?: on]
					all [event/ctrl? event/key = #"-"] [reduce?: on]
					all [event/ctrl? event/key = #"Z"] [either event/shift? [redo?: on][undo?: on]]
				]
				left:  clear []
				right: clear []

				if edit? [
					addr: batch gedit/grid [here]
					if event/ctrl? [addr/y: 1]					;-- ctrl+F2 to edit the header
					gedit/edited: addr
					gedit/refresh/headers
					invalidate gedit/grid
					render host-of gedit						;@@ kludge (can't focus a space that does not exist yet)
					cell: gedit/grid/cells/pick addr
					set-focus either addr/y = 1
						[cell/content/content/1/content]		;@@ very inelegant way to address a field in the header cell :/
						[cell/content]
				]

				if any [copy? clear?] [
					;; default copy mechanism is too slow for this, because it formats cells (spaces)
					;; to scale I have to replace it here with plain data copy
					xs: unroll-bitset gedit/grid/selected/x
					ys: unroll-bitset gedit/grid/selected/y
					rows: make [] 16
					row:  make [] 16
					foreach y ys [
						if all [copy? y <> 2] [					;-- skip the filter
							foreach x xs [append row gedit/data/pick x by y]
							append rows join row #"^-"
							clear row
						]
						if all [clear? y > 2] [					;-- skip headers
							foreach x xs [
								if x > 1 [
									xy: x by y
									repend left  [xy  gedit/data/pick xy]
									gedit/data/write xy new-text: copy {}
									repend right [xy  new-text]
								]
							]
						]
					]
					if clear? [gedit/refresh]
					if copy? [clipboard/write text: join rows #"^/"]	;@@ or copy as a 2D Red structure?
					stop/now
				]

				if paste? [										;@@ should paste select the modified area?
					text: clipboard/read/text
					rows: map-each/only row split text #"^/" [split row #"^-"]
					base: batch gedit/grid [here - 1x1]
					unless empty? rows [
						clip-size: (length? rows/1) by (length? rows)
						data-size: gedit/data/size
						if clip-size/x >= data-size/x [base/x: 0]	;-- headers are in the data? paste whole rows/cols
						if clip-size/y >= data-size/y [base/y: 0]
						xyloop xy clip-size [
							if gedit/grid/pinned +< (base + xy) [	;-- never replace the headers
								xy': base + xy
								repend left  [xy'  gedit/data/pick xy']
								gedit/data/write xy' new-text: rows/(xy/y)/(xy/x)
								repend right [xy'  new-text]
							]
						]
						batch gedit/grid [select-range base + 1 base + clip-size] 
						gedit/refresh
					]
					stop/now
				]

				unless empty? left [
					left:  reduce ['set-many copy/deep left]
					right: reduce ['set-many copy/deep right]
					gedit/timeline/put gedit left right
				]

				if any [extend? reduce?] [
					batch gedit/grid [cur-sel: selected-range cursor: here]
					sel-size: cur-sel/2 - cur-sel/1 + 1
					data-size: gedit/data/size
					case [
						sel-size/x = data-size/x [				;-- requires either column or row to be selected
							slot: cursor/y - 2
							either extend? [
								rowid: database/add-row slot - 1
								left:  [database/hide-row (rowid)]
								right: [database/show-row (rowid)]
							][
								database/hide-row rowid: database/pick-row slot
								left:  [database/show-row (rowid)]
								right: [database/hide-row (rowid)]
							]
							gedit/timeline/put gedit compose left compose right
							gedit/refresh
						]
						sel-size/y = data-size/y [
							slot: cursor/x - 1
							either extend? [
								colid: database/add-column slot - 1
								left:  [database/hide-column (colid)]
								right: [database/show-column (colid)]
							][
								database/hide-column colid: database/pick-column slot
								left:  [database/show-column (colid)]
								right: [database/hide-column (colid)]
							] 
							gedit/timeline/put gedit compose left compose right
							gedit/refresh/headers
						]
					]
				]
				
				if redo? [gedit/timeline/redo  gedit/refresh/headers]
				if undo? [gedit/timeline/undo  gedit/refresh/headers]
			]
		]
	];define-handlers [ 
	
	block-ui: function [
		"Block the editor, showing a dialog with given title until code finishes"
		title [string!]
		code  [block!]
	][
		modal: view/no-wait/flags compose [
			title (title)
			base glass 300x100 "Hold on!^/This may take a few minutes!"
		] 'modal
		following code [unview/only modal]
	]
	
	save-state: function ["Save the editor state"] [
		state: make map! reshape [
			view-size:		@[window/size]
			view-offset:	@[window/offset]
			window-origin:	@[gedit/window/origin]
			gedit-origin:	@[gedit/origin]
			col-widths:		@[gedit/grid/widths]
			; database-file:	@[db-optimal]
			cols-included:	@[database/included/x]
			rows-included:	@[database/included/y]
			cols-order:		@[database/ordered/x]
			rows-order:		@[database/ordered/y]
		]
		data-store/save-state state
	]
	
	save-db: function ["Save the database"] [
		database/save db-optimal
	]
	
	load-state: function ["Restore the editor state"] [
		state: data-store/load-state
		case/all [
			planar?	x: state/view-size		[window/size:         x]
			planar?	x: state/view-offset	[window/offset:       x]
			planar?	x: state/window-origin	[gedit/window/origin: x]
			planar?	x: state/gedit-origin	[gedit/origin:        x]
			map?	x: state/col-widths		[gedit/grid/widths:   x]
			block?	x: state/cols-included	[database/included/x: x]
			block?	x: state/rows-included	[database/included/y: x]
			block?	x: state/cols-order		[database/ordered/x:  x]
			block?	x: state/rows-order		[database/ordered/y:  x]
		]
		; gedit/grid/refresh
		invalidate gedit/grid
	]
	
	view window: layout/flags [
		on-created [load-state]
		on-close   [
			save-state
			if gedit/timeline/count > 0 [						;-- only save when there are changes
				unview
				block-ui "Saving the data..." [save-db]
			]
		]
		title "Grid Editor demo"
		host 600x400 react [face/size: face/parent/size - 20] [
			column tight [
				gedit: grid-edit focus with [
					do with grid [
						;; default configuration of the grid layout
						pinned:				1x2
						heights/1:			'auto
						heights/2:			30
						heights/default:	40
						widths/1:			50
						widths/default:		100
						; attempt [widths/(1 + database/find-header "Discovery Facility"): 200]
					]
				]
				row center [
					button "Import data..." [
						file: request-file/filter
							["Red/Redbin/CSV" "*.redbin;*.red;*.csv;*.redbin.gz;*.red.gz;*.csv.gz"]
						if file [
							block-ui "Loading..." [
								database/load file
								gedit/refresh/headers
							]
						]
					]
					button "Export data..." [
						file: request-file/save/filter
							["Red/Redbin/CSV" "*.redbin;*.red;*.csv;*.redbin.gz;*.red.gz;*.csv.gz"]
						if file [
							block-ui "Saving..." [
								database/save file
							]
						]
					]
				]
			]
		]
	] 'resize
	; prof/show
]

