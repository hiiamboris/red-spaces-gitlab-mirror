Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

; #do [disable-space-cache?: yes]
#include %../everything.red

append spaces/keyboard/focusable 'grid-view

view/no-wait/options [
	below
	b: host [
		gv: grid-view focus 400x400 
		with [
			source: #(
				1x1 "1x1 abadh" 2x1 "2x1 afhoah afhohaf" 3x1 "3x1 afhyewon bwoy auojoo"
				1x2 "1x2 hao" 2x2 "2x2 qupe opqie" 3x2 "3x2 zvnbi qvoeop qeboukj yhdu aohfoh yqweypy jobaod pjadph adobohdohoh"
				1x3 "1x3 hafoyg fhuot" 2x3 "2x3 hjjdoyo" 3x3 "3x3 qyeyyndo" 
				size: 3x3
			)
			spaces/ctx/grid-ctx/autofit grid 200
			; grid/bounds: 10x10
			; grid/bounds: [x: 10 y: auto]
			; grid/set-span 1x1 2x1
			; grid/set-span/force 2x2 3x2
			; set-span/force 1x1 1x3
			; grid/heights/2: 200
			; grid/widths/default: 300
			; grid/heights/default: 300
		]
	]
	on-over [
		status/text: form hittest face/space event/offset
	]
	status: text 300x40
] [offset: 10x10]

; spaces/ctx/grid-ctx/autofit gv/grid 200
; b/dirty?: yes
			
; dump-tree
either system/build/config/gui-console? [print "---"][do-events]

