Red [
	title:   "VID layout support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ my.. this needs a lot of work...

;@@ TODO: a separate host-based style for each high level space
;@@ also, templates e.g. `vlist` should appear as `list` in the tree but have an `axis: 'y` as default
;@@ also combine them faces and spaces in one object! or not? `draw` will prove difficult, but we can rename it to render

;@@ make it internal?
init-spaces-tree: function [face [object!]] [
	unless spec: select face/actors 'worst-actor-ever [exit]
	face/actors/worst-actor-ever: none
	#assert [function? :spec]
	spec: body-of :spec
	if empty? spec [exit]
	tree-from: function [spec [block!]] [
		r: copy []
		while [not empty? spec] [
			name: spec/1  spec: next spec
			#assert [word? name]		;@@ TODO: normal error handling here
			#assert [spaces/:name  'name]

			with-blk: []
			if spec/1 = 'with [		;-- reserved keyword
				with-blk: :spec/2
				#assert [block? :with-blk]
				spec: skip spec 2
			]

			name: make-space/name name with-blk		;-- this allows `with` to add facets to spaces (e.g. rate)
			append r name
			space: get name
			if block? blk: spec/1 [		;@@ TODO: sizes data and whatever else to make this on par with `layout`
				spec: next spec
				inner: tree-from blk
				unless empty? inner [
					case [		;@@ this is all awkward adhoc crap - need to generalize it!
						t: in space 'content   [space/content: inner/1]
						t: in space 'item-list [append space/item-list inner]
						'else [ERROR "do not know how to add spaces to (name)"]
					]
				]
			]
		]
		r
	]
	tree: tree-from spec
	#assert [any [1 >= length? tree]]
	face/space: tree/1
	face/draw: render face					;@@ required to populate `map`s & get the size
	new-size: select get face/space 'size
	#assert [new-size]			;-- `size: none` blows up `layout`
	face/size: new-size
]


