Red [
	title:   "Hittest facilities for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export

exports: [hittest]

into-map: function [
	map [block!] xy [pair!] child [object! (space? child) none!]
	/only list [block!] "Only try to enter selected spaces"
][
	either child [
		#debug events [#assert [find/same map child]]	;-- may fail, but still worth seeing it
		;; geom=none possible if e.g. hittest on 'up' event uses drag-path of 'down' event
		;; and some code of 'down' event replaces part of the tree;
		;; also %hovering.red on tree modification uses a no longer valid path
		xy: either geom: select/same/only map child [xy - geom/offset][0x0] 
		reduce [child xy]
	][
		either list [
			foreach child list [
				box: select/same map child
				if within? xy o: box/offset box/size [
					return reduce [child  xy - o]
				]
			]
		][
			foreach [child box] map [
				if within? xy o: box/offset box/size [
					return reduce [child  xy - o]
				]
			]
		]
		none
	]
]

;; has to be fast, for on-over events
hittest: function [
	"Map a certain point deeply into the tree of spaces"
	space [object! (space? space) block! path!]
		"Top space in the tree (host/space usually), or path of spaces to follow"
		;; path/block is required for dragging, as we need to follow the same path as at the time of click
	xy [pair!] "Point in that top space"
	/into "Append into a given buffer"
		path: (make [] 16) [block! path!]
][
	either object? space [
		while [
			all [
				space
				any [
					none? space/size			;-- infinite spaces include any point ;@@ but should none mean infinite?
					within? xy 0x0 space/size
				]
			]
		][
			repend path [space xy]
			#assert [xy]
			case [
				into: select space 'into [
					set [space xy] into xy
				]
				map: select space 'map [
					set [space xy] into-map map xy none
				]
				'else [break]
			]
		]
	][
		template: space
		forall template [
			set [space: _: child:] template
			repend path [space xy]
			#assert [xy]
			case [
				into: select space 'into [
					set [_ xy] do copy/deep [into/force xy child]	;@@ workaround for #4854 - remove me
				]
				map: select space 'map [
					set [_ xy] into-map map xy child
				]
			]
			template: next template
		]
	]
	new-line/all path no
]

export exports
