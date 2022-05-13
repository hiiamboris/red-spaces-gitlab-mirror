Red [needs: view]						;) we need the View module to be able to show graphics

#include %../everything.red				;) add Spaces to the current program

list: make-space 'list [				;) make-space is used to instantiate spaces
	axis: 'y							;) lists can be horizontal(x) or vertical(y)

	item-list: reduce [					;) item-list is a block of NAMES of spaces

		make-space/name 'text [			;) each make-space/name returns a name referring to an object
			text: "Hello, space!"		;) like `make prototype [spec..]`, make-space allows to define facets
		]
		make-space/name 'button [
			data: "OK"					;) data can be any Red type
			width: 80					;) width makes the button bigger than it's data
			command: [unview]			;) code that is evaluated when button is released
		]
	]
]

host: make-face 'host					;) host face we need to draw spaces on
host/space:  'list						;) host must have exactly one space attached to it - here it's `list`
host/draw:   render host				;) `render` returns a list of draw commands, but also sets the /size facet of spaces
host/size:   list/size					;) now we know how big host face we need from previously set list/size
host/offset: 10x10						;) apply default VID margin

window: make-face 'window				;) create window to put host into
window/pane: reduce [host]				;) add host to it
window/size: host/size + 20x20			;) add default VID margins to host/size to infer window/size
window/offset: system/view/screens/1/size - window/size / 2		;) center the window

show window								;) finally, we display the layout
set-focus host							;) focus host for it to receive keyboard events
do-events								;) enter View event loop
