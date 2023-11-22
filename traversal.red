Red [
	title:   "Tree traversal for Faces and Spaces"
	author:  @hiiamboris
	license: BSD-3
]

;; requires export, tree-hopping, provides pane-of for tabbing

list-*aces:   none										;-- reserve names in the spaces/ctx context
foreach-*ace: none
exports: [list-*aces foreach-*ace]						;-- make them globally available too

traversal: context [
	depth-limit: 100									;-- used to prevent stack from overflowing in recursive layouts
	
	pane-of: function [*ace [object!]] [
		case [
			not is-face? *ace [select *ace 'map]
			host? *ace        [reduce [*ace/space]]
			'other-face       [*ace/pane]
		]
	]

	walker: make batched-walker! [
		branch: function [*ace [object!] /from depth [integer!]] [
			pane: pane-of *ace
			if empty? pane [exit]
			depth: 1 + any [depth -1]
			clear batch
			foreach child pane [						;@@ use for-each
				unless object? :child [continue]
				repend/only batch ['visit *ace child]
				if depth < depth-limit [
					repend/only batch ['branch/from child depth]
				]
			]
			insert next plan batch
		]
	]
	
	set 'list-*aces function [
		"Deeply list faces & spaces from ROOT face or space"
		root [object!] (any [is-face? root space? root])
		/into target: (make [] 100) [block!] "Existing content is overwritten"
	][
		append target root
		foreach-node root walker [append target key]
		new-line/all target on
	]

	set 'foreach-*ace function [
		"Evaluate CODE for each face & space from ROOT face or space"
		'word [word! set-word!] "Word to receive face or space"
		root  [object!] (any [is-face? root space? root])
		code  [block!]
	][
		foreach-node root walker [set word key do code]
	]
]

export exports

