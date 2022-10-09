Red [
	title:   "Tree traversal for Faces and Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires auxi.red (make-free-list), export

list-spaces:    none									;-- reserve names in the spaces/ctx context
list-*aces:     none
foreach-space:  none
foreach-*ace:   none
path-from-face: none
exports: [list-spaces list-*aces foreach-space foreach-*ace path-from-face]		;-- make them globally available too

;-- tree iteration support
traversal: context [
	depth-limit: 100									;-- used to prevent stack from overflowing in recursive layouts

	reuse-path: function ['target [word!]][
		blk: get target
		set target either path? :blk/1 [				;-- reuse existing paths to minimize allocations
			path: clear head blk/1
			next blk
		][
			path: make path! 10
			change/only blk path
		]
		path
	]

	set 'list-spaces function [
		"Deeply list spaces of a ROOT space"
		root [word!]
		/into target [block!] "Existing content is overwritten"
	][
		target: any [target  make [] 50]
		clear list-spaces* to path! root target				;-- copy root, will modify
		new-line/all target yes
	]

	list-spaces*: function [root [path!] "will be modified" target [block!]] [
		path: reuse-path target
		append path head root								;-- insert current path
		if all [
			map: select get root/1 'map						;-- insert child paths
			depth-limit > length? head root
		][
			root: next root
			foreach [name _] map [
				assert [name]								;-- no junk in the maps please
				change root name
				target: list-spaces* root target
			]
			clear root
		]
		target
	]

	list-*aces*: function [
		root [path!] "will be modified"
		target [block!]
	][
		path: reuse-path target	
		append path head root								;-- insert current path
		root-face: get root/1
		root: next root
		unless empty? pane: select root-face 'pane [		;-- insert child paths
			foreach face pane [
				name: anonymize face/type face
				change root name
				target: list-*aces* root target
			]
			clear root
		]
		if name: select root-face 'space [					;-- insert spaces if any
			#assert [word? name]
			change root name
			target: list-spaces* root target
			clear root
		]
		target
	]

	set 'list-*aces function [
		"Deeply list spaces and faces of a FACE"
		face [object! word!]
		/into target [block!] "Existing content is overwritten"
	][
		target: any [target  make [] 100]
		#assert [is-face? any [all [word? face  get face] face] "face! object expected"]
		if object? :face [face: anonymize face/type face]
		clear list-*aces* to path! face target
		new-line/all target yes
	]

	set 'path-from-face function [
		"Return FACE's path from the screen"
		face [object!]		;@@ no need in spaces support here?
	][
		r: make path! 10
		until [
			insert r anonymize face/type face
			none? face: face/parent
		]
		r
	]
]


context [
	cache: make-free-list block! [make [] 100]

	;-- break & continue will work!
	foreach*: function [					;-- tree iterator
		spec     [word! set-word! block!]
		path     [word! path! block!]
		code     [block!]
		lister   [function!]
		reverse? [logic!]
		next?    [logic!]
		;@@ any point in not making it cyclic?
	][
		if any-word? spec [spec: to [] to word! spec]
		path: either word? path [to path! path][as path! path]
		#assert [not empty? path "Tree iteration expects a face in the path"]
		if empty? path [exit]								;-- no paths to iterate over

		buf: cache/get										;-- so we can call foreach-*ace from itself
		list: lister/into path/1 buf
		if reverse? [reverse list]

		either pos: find-same-path list path [
			#debug focus [
				if attempt [get bind 'dir :find-next-focal-space] [
					#print "Found (as path! path) at index (index? pos)"
				]
			]
			if next? [remove pos]
			unless head? pos [
				move/part  head pos  tail pos  skip? pos	;-- rearrange to cover the whole tree
			]
		][
			#debug focus [
				if attempt [get bind 'dir :find-next-focal-space] [
					#print "NOT found (as path! path) in spaces tree"
				]
			]
			pos: list										;-- if empty path or path is invalid: go from head
		]

		foreach path head pos [
			set spec head change change/only [] path get last path
			do code
		]

		cache/put buf										;-- save the block for later use
		()			;-- no return value
	]

	set 'foreach-space function [
		"Evaluate CODE for each space starting with PATH"
		'spec [word! set-word! block!] "path or [path space]"
		path  [word! path! block!] "Starting path (index determines tree root)"
		code  [block!]
		/reverse "Traverse in the opposite direction"
		/next    "Skip the PATH itself (otherwise includes it)"
	][
		foreach* spec path code :list-spaces reverse next
	]

	set 'foreach-*ace function [
		"Evaluate CODE for each face & space starting with PATH"
		'spec [word! set-word! block!] "path or [path *ace]"
		path  [word! path! block! object!] "Starting path (index determines tree root)"
		code  [block!]
		/reverse "Traverse in the opposite direction"
		/next    "Skip the PATH itself (otherwise includes it)"
	][
		if object? path [path: anonymize path/type path]
		foreach* spec path code :list-*aces reverse next
	]
]

export exports	;-- make them globally available too

