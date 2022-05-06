Red [
	title:   "VID layout support for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

;@@ my.. this needs a lot of work...
;@@ name it VID/S

;@@ TODO: a separate host-based style for each high level space
;@@ also, templates e.g. `vlist` should appear as `list` in the tree but have an `axis: 'y` as default
;@@ also combine them faces and spaces in one object! or not? `draw` will prove difficult, but we can rename it to render

{
	VID Styles:
	row - horizontal tube
	column - vertical tube
	hlist - horizontal list
	vlist - vertical list
}

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
			#assert [word? name "VID/S encountered a non-word space name!"]		;@@ TODO: normal error handling here
			#assert [templates/:name]

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
	
	;; this is rather tricky:
	;;  1. we want `render` to render the content on currently set face/size
	;;  2. yet, in `layout` we set face/size from the rendered content size
	;; so, to avoid double rendering we have to re-apply the host style
	;; this is done inside `render-face` if we set size to none
	;@@ what if size is set explicitly by the user?
	face/size: none
	rendered: render face
	#assert [face/size]						;-- should be set by `render-face`, `size: none` blows up `layout`
	#debug draw [prin "host/draw: " probe~ rendered] 
	
	face/draw: rendered
]


wrap-value: function [
	"Create a space to represent given VALUE; return it's name"
	value [any-type!]
][ 
	switch/default type?/word :value [
		string! [make-space/name 'text  [text:  value]]	;@@ text or paragraph??
		logic!  [make-space/name 'logic [state: value]]
		image!  [make-space/name 'image [data:  value]]
		url!    [make-space/name 'url   [data:  value]]
		;@@ also object & map as grid? and use lay-out-data for block?
	] [make-space/name 'text [text: mold :value]]
]

lay-out-data: function [
	"Create a space layout out of DATA block"
	data [block!] "image, logic, url get special treatment"
	/only "Return only the spaces list, do not create a layout"
][
	result: map-each value data [wrap-value :value]
	either only [
		result
	][
		make-space 'tube [
			margin:    0x0								;-- outer space most likely has it's own margin
			spacing:   10x10
			item-list: result
		]
	]
]

