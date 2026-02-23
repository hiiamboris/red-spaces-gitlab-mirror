Red [
	title:   "Hittest facilities for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;-- requires export

exports: [hittest]

into-map: function [
	map [block!] xy [planar!] child [object! (space? child) none!]
	/only list [block!] "Only try to enter selected spaces"
][
	either child [
		#debug events [#assert [find/same map child]]	;-- may fail, but still worth seeing it
		;; geom=none possible if e.g. hittest on 'up' event uses drag-path of 'down' event
		;; and some code of 'down' event replaces part of the tree;
		;; also %hovering.red on tree modification uses a no longer valid path
		xy: either geom: select/same/only map child [xy - geom/offset][(0,0)] 
		reduce [child xy]
	][
		;@@ foreach here is not applicable in case of intersecting spaces: must be foreach/reverse
		;@@ since map is ordered in drawing order, last drawn space is 'on top' so it must catch the point first
		either list [
			foreach child list [
				box: select/same map child
				#assert [box/size  "map should not contain infinite sizes"]
				if within? xy o: box/offset box/size [
					return reduce [child  xy - o]
				]
			]
		][
			foreach [child box] map [
				#assert [box/size  "map should not contain infinite sizes"]
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
	xy [planar!] "Point in that top space"
	/into "Append into a given buffer"
		path: (make [] 16) [block! path!]
][
	unless object? template: space [					;-- follow given path until it ends
		forall template [								;@@ use for-each
			set [space: _: child:] template
			repend path [space xy]
			#assert [xy]								;-- forced into and map should always return the pair, if child is not none
			set [child xy] case [
				into: select space 'into [into/force xy child]
				map:  select space 'map  [into-map map xy child]
			]
			template: next template
		]
		space: child									;-- continue forth from the child (if lands on any)
	]
	if object? space [
		while [all [space  xy inside? space]] [
			repend path [space xy]
			#assert [xy]
			set [space xy] case [
				into: select space 'into [into xy]
				map:  select space 'map  [into-map map xy none]
			]
		]
	]
	new-line/all path no
]

export exports
