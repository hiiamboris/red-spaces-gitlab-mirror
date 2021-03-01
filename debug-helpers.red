Red [
	title:   "Simple debug helpers for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

dump-spaces: function [root [word!] /local path] [
	foreach-space path root [
		spc: get last path
		print [spc/size "^-" path]
	]
]

;@@ TODO: simplify path to automatically look into `items`
get-space: function ['path [path!]] [
	o: get path/1
	foreach x next path [
		either all [block? o word? x] [
			o: get first find o x
		][
			o: o/:x
		]
		if word? :o [o: get o]
	]
	o
]

;-- debug helper
?s: function ['path [path!]] [
	path: get-space (path)
	? path
]

