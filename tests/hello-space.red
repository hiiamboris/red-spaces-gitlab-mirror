Red [needs: view]						;) we need the View module to be able to show graphics

recycle/off								;) without this - often crashes on heisenbugs :(
#include %../everything.red				;) add Spaces to the current program
view [
	host focus [						;) create a Host face that can contain spaces
		list with [axis: 'y] [			;) draw a vertical list on the Host
			paragraph with [text: "Hello, space!"]
			button with [data: "OK" command: [quit]]
		]
	]
]
