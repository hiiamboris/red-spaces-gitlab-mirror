Red [
	title:   "Tree traversal for Faces and Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]


;-- requires auxi.red (make-free-list), export
;@@ now that this is used sparingly, it can be simplified (deoptimized)

list-spaces:    none									;-- reserve names in the spaces/ctx context
list-*aces:     none
foreach-space:  none
foreach-*ace:   none
path-from-face: none
exports: [list-spaces list-*aces foreach-space foreach-*ace path-from-face]		;-- make them globally available too

;-- tree iteration support
traversal: context [
	depth-limit: 100									;-- used to prevent stack from overflowing in recursive layouts

	reuse-path: in-out-func ['target [word!]] [
		block: target
		target: either path? :block/1 [					;-- reuse existing paths to minimize allocations
			path: clear head block/1
			next block
		][
			path: make path! 10
			change/only block path
		]
		path
	]

	set 'list-spaces function [
		"Deeply list spaces of a ROOT space"
		root [object!] (space? root)
		/into target: (make [] 50) [block!] "Existing content is overwritten"
	][
		clear list-spaces* to path! root target
		new-line/all target yes
	]

	list-spaces*: function [root [path!] "will be modified" target [block!]] [
		path: reuse-path target
		append path head root							;-- insert current path
		if all [
			map: select root/1 'map						;-- insert child paths
			depth-limit > length? head root
		][
			root: next root
			foreach [space _] map [
				#assert [space? space]					;-- no junk in the maps please
				change root space
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
		append path head root							;-- insert current path
		root-face: root/1
		root: next root
		unless empty? pane: select root-face 'pane [	;-- insert child paths
			foreach face pane [
				change root face
				target: list-*aces* root target
			]
			clear root
		]
		if space? space: select root-face 'space [		;-- insert spaces if any
			change root space
			target: list-spaces* root target
			clear root
		]
		target
	]

	set 'list-*aces function [
		"Deeply list spaces and faces of a FACE"
		face [object!] (is-face? face)
		/into target: (make [] 100) [block!] "Existing content is overwritten"
	][
		clear list-*aces* to path! face target
		new-line/all target yes
	]

	set 'path-from-face function [
		"Return FACE's path from the screen"
		face [object!] (is-face? face)					;@@ no need in spaces support here?
	][
		buf: as path! clear []
		until [
			insert buf face
			none? face: face/parent
		]
		copy buf
	]
]


context [
	cache: make-free-list block! [make [] 100]

	;-- break & continue will work!
	foreach*: function [					;-- tree iterator
		spec     [word! set-word! block!]
		path     [path! block! (not empty? path) object!]
		code     [block!]
		lister   [function!]
		reverse? [logic!]
		next?    [logic!]
		;@@ any point in not making it cyclic?
	][
		if any-word? spec [spec: to [] to word! spec]
		path: as path! either object? path [reduce [path]][path]

		buf: cache/get											;-- so we can call foreach-*ace from itself
		list: lister/into path/1 buf
		if reverse? [reverse list]

		either pos: find-same-path list path [
			#debug focus [
				if attempt [get bind 'dir :find-next-focal-*ace] [
					#print "Found (mold as path! path) at index (index? pos)"
				]
			]
			if next? [remove pos]
			unless head? pos [
				move/part  head pos  tail pos  skip? pos		;-- rearrange to cover the whole tree
			]
		][
			#debug focus [
				if attempt [get bind 'dir :find-next-focal-*ace] [
					#print "NOT found (mold as path! path) in spaces tree"
				]
			]
			pos: list											;-- if empty path or path is invalid: go from head
		]

		foreach path head pos [
			set spec head change change/only [] path last path
			do code
		]

		cache/put buf											;-- save the block for later use
		exit													;-- no return value
	]

	set 'foreach-space function [
		"Evaluate CODE for each space starting with PATH"
		'spec [word! set-word! block!] "path or [path space]"
		path  [object! (space? path) path! block!] "Starting path (index determines tree root)"
		code  [block!]
		/reverse "Traverse in the opposite direction"
		/next    "Skip the PATH itself (otherwise includes it)"
	][
		foreach* spec path code :list-spaces reverse next
	]

	set 'foreach-*ace function [
		"Evaluate CODE for each face & space starting with PATH"
		'spec [word! set-word! block!] "path or [path *ace]"
		path  [object! (is-face? path) path! block!] "Starting path (index determines tree root)"
		code  [block!]
		/reverse "Traverse in the opposite direction"
		/next    "Skip the PATH itself (otherwise includes it)"
	][
		foreach* spec path code :list-*aces reverse next
	]
]

export exports	;-- make them globally available too

