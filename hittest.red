Red [
	title:   "Hittest facilities for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export

exports: [hittest]

into-map: function [
	map [block!] xy [pair!] name [none! word!]
	/only names [block!] "Only try to enter selected space names"
][
	either name [
		#assert [find map name]
		geom: select/same map name
		reduce [name  xy - geom/offset]
	][
		either names [
			foreach name names [
				box: select map name
				if within? xy o: box/offset box/size [
					space: get name
					return reduce [name  xy - o]
				]
			]
		][
			foreach [name box] map [
				if within? xy o: box/offset box/size [
					space: get name
					return reduce [name  xy - o]
				]
			]
		]
		none
	]
]

;-- has to be fast, for on-over events
hittest: function [
	"Map a certain point deeply into the tree of spaces"
	space [word!] "Top space in the tree (host/space usually)"
	xy [pair!] "Point in that top space"
	/into "Append into a given buffer"
		path [block! path!]
	;-- this is required for dragging, as we need to follow the same path as at the time of click
	/as "Force coordinate translation to follow a given path"
		template [block! path! none!]
][
	space: get name: space
	#assert [space? space]
	path: any [path  make [] 16]
	either template [
		#assert [name = template/1]
		forall template [
			set [name: _: name2:] template
			repend path [name xy]
			space: get name
			#assert [xy]
			; #assert [name2]							;-- can be none!
			case [
				into: select space 'into [
					set [_ xy] do copy/deep [into/force xy name2]	;@@ workaround for #4854 - remove me
					; set [_ xy] into/force xy name2
				]
				map: select space 'map [
					set [_ xy] into-map map xy name2
				]
			]
			template: next template
		]
	][
		while [
			all [
				name
				space: get name
				any [
					none? space/size			;-- infinite spaces include any point ;@@ but should none mean infinite?
					within? xy 0x0 space/size
				]
			]
		][
			repend path [name xy]
			#assert [xy]
			case [
				into: select space 'into [
					set [name xy] into xy
				]
				map: select space 'map [
					set [name xy] into-map map xy none
				]
				'else [break]
			]
		]
	]
	new-line/all path no
]

export exports
