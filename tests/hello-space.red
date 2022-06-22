Red [needs: view]						;) we need the View module to be able to show graphics

#include %../everything.red				;) add Spaces to the current program
view [
	host [								;) create a Host face that can contain spaces
		vlist [									;) draw a vertical list on the Host
			text "Hello, space!"
			button "OK" 80 focus [unview]		;) unview generates an error - #5124 :)
		]
	]
]
