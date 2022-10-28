Red [
	title:   "Hittest facilities for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export

exports: [hittest]

into-map: function [
	map [block!] xy [pair!] child [none! object!]
	/only list [block!] "Only try to enter selected spaces"
][
	either child [
		#assert [find/same map child]
		geom: select/same map child
		reduce [child  xy - geom/offset]
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

;-- has to be fast, for on-over events
hittest: function [
	"Map a certain point deeply into the tree of spaces"
	space [object!] "Top space in the tree (host/space usually)" (space? space)
	xy [pair!] "Point in that top space"
	/into "Append into a given buffer"
		path: (make [] 16) [block! path!]
	;-- this is required for dragging, as we need to follow the same path as at the time of click
	/as "Force coordinate translation to follow a given path"
		template [block! path! (space =? template/1) none!]
][
	either template [
		forall template [
			set [space: _: child:] template
			repend path [space xy]
			#assert [xy]
			; #assert [name2]							;-- can be none!
			case [
				into: select space 'into [
					set [_ xy] do copy/deep [into/force xy child]	;@@ workaround for #4854 - remove me
					; set [_ xy] into/force xy name2
				]
				map: select space 'map [
					set [_ xy] into-map map xy child
				]
			]
			template: next template
		]
	][
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
	]
	new-line/all path no
]

export exports
