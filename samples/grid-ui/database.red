Red [
	title:   "Sample database for the GridUI demo"
	author:  @hiiamboris
	license: BSD-3
	notes: {
		Requires exoplanets data either as %exoplanets.redbin or %exoplanets.red.gz
		I converted it from the CSV exported from https://exoplanetarchive.ipac.caltech.edu/
	}
]

;; super-simplistic sample database functionality used by the %grid-ui.red
;; this should ideally be done by a real database, not by Red and definitely NOT by the grid
;; as the grid does not contain data, it just displays external data
;; (at most column order could be controlled by the grid itself, but for this demo it's easier to put it into DB)

;; a note on data model:
;; in block of blocks model, first column insertion takes ~15sec (involves a huge number of reallocations)
;; so I'm using flat map model instead: xy[pair!] -> value

;; data serving pipeline: source data => filters => sort order => result
database: context with spaces/ctx expand-directives [
	data:   none												;-- contains whole database as a map
	
	bob->map: function [
		"Convert DB from a block-of-blocks format into a map"
		bob [block!]
	][
		map: make map! (w: length? bob/1) * (h: length? bob) + 2
		repeat y h [repeat x w [put map x by (y - 1) bob/:y/:x]]
		map/cols: w
		map/rows: h - 1											;-- height excluding headers
		map
	]
	
	map->bob: function [
		"Convert DB from a map format into a block-of-blocks"
		map [map!]
	][
		w: map/cols
		h: map/rows + 1
		bob: make block! h
		repeat y h [											;@@ use map-each
			append/only bob row: make block! w
			repeat x w [append row select map x by (y - 1)]		;@@ use map-each
		]
		bob
	]
	
	load: function [
		"Load database from a given file"
		file [file!] "CSV, Red, or Redbin format (possibly gzipped)"
	][
		without-gc [
			either %.gz = suffix? file [
				clock [data: decompress read/binary file 'gzip]
				clear find/last file %.gz
				format: select [%.csv CSV %.redbin redbin] suffix? file	;-- %.red -> none
				clock [data: system/words/load/as data format]
				if error? data [do data]						;@@ workaround for #5521
			][
				clock [data: system/words/load file]
			]
			; print native-mold/part data 1000
			if block? data [clock [data: bob->map data]]
		]
		self/data: data
		#print "DB size: (ncols) columns by (nrows) rows"
		init 
	]
	
	save: function [
		"Save database to a given file"
		file [file!] "CSV, Red, or Redbin format (possibly gzipped)"
	][
		without-gc [
			if gzipped?: %.gz = suffix? gzfile: copy file [
				clear find/last file %.gz
			]
			format: select [%.csv CSV %.redbin redbin] suffix? file		;-- %.red -> none
			data:   self/data
			if 'redbin <> format [clock [data: map->bob self/data]]		;-- text exports are slow...
			
			either gzipped? [
				clock [bin: system/words/save/as #{} data format]
				clock [write/binary gzfile compress bin 'gzip]
			][
				clock [system/words/save file data]
			]
		]
	]
	
	init: function ["Refill inner structures after a DB load"] [
		self/filters: next map-each i ncols + 1 [
			make filter! [column: i - 1]
		]
		self/included: object [
			x: list-range 1 ncols
			y: list-range 1 nrows
		]
		self/ordered: object [
			x: copy included/x
			y: copy included/y
		]
		self/included+ordered: object [
			x: copy ordered/x
			y: copy ordered/y
		]
		set modified no
	]
	
	nrows:   does [data/rows]
	ncols:   does [data/cols]
	size:    does [ncols by nrows]

	;; filtering...
	
	filter!: object [
		column:   0
		text:     {}
		excluded: make bitset! 0
	]
	filters: []													;-- per-column filter list; column=0 is used to hide rows permanently
	included: object [
		x: []													;-- ordered list of included column numbers (only manually altered)
		y: []													;-- ordered list of included row numbers that pass all the filters
	]
	ordered: object [
		x: []													;-- manually arranged list of ALL columns
		y: []													;-- manually arranged list of ALL rows
	]
	included+ordered: object [x: [] y: []]						;-- an intersection of included and ordered
	modified: object [x: y: no]									;-- flags to defer rebuild of included+ordered
	
	;@@ maybe grid should control column order, not DB?
	
	list-rows-except: function [
		"Return row numbers excluding given set"
		excluded [bitset!]
	][
		result: clear []
		repeat row nrows [unless excluded/:row [append result row]]	;@@ use map-each
		copy result
	]
	
	;; for better (O(log(n))) scalability filters could be joined tree-wise, but at 3M cells scale no reason to bother
	join-filters: function [
		"Combine all exclusion filters into one and return it"
		filters [block!]
	][
		if empty? filters [return charset []]
		excluded: filters/-1/excluded							;-- starts with manually excluded rows
		foreach filter filters [excluded: excluded or filter/excluded]
		excluded
	]
	
	;@@ due to #5480 I should not use negated bitsets, so this returns EXCLUDED rows
	update-filter: function [
		"Keep only database rows that contain their filter text in given column"
		column [integer!] (all [1 <= column column <= ncols])
	][
		unless filter: filters/:column [exit]
		result: make bitset! nrows
		unless empty? filter/text [
			repeat row nrows [
				unless find data/(column by row) filter/text [
					result/:row: on
				]
			]
		]
		filter/excluded: result
		modified/y: yes
	]
	
	update-included+ordered: function [
		"Rebuild included+ordered lists from their sources; returns true if rebuilt"
		/only axis [word!] "X or Y"
	][
		rebuilt: no
		foreach [x dim] [x nrows y ncols] [
			if any [
				all [axis axis <> x]
				not modified/:x
			] [continue]
			n: do dim
			if x = 'y [append clear included/y list-rows-except join-filters filters]
			append clear included+ordered/:x
				either n = length? included/:x
					[ordered/:x]
					[intersect ordered/:x included/:x]
			rebuilt: yes
		]
		set modified no
		rebuilt
	]
	
	;; sorting...
	
	sort-by-column: function [
		"Sort current row order by given column (ascending by default)"
		column [integer!] (all [0 <= column column <= ncols]) "0 = sort by row number"
		/reverse "Descending sort"
	][
		either column = 0 [
			sort/:reverse ordered/y								;-- restore original row order
		][
			buffer: clear []
			foreach row ordered/y [
				append append/only buffer :data/(column by row) row
			]
			sort/stable/skip/:reverse buffer 2					;-- /stable to not disturb other columns order
			extract/into next buffer 2 clear ordered/y
		]
		modified/y: yes
	]
	
	;; data access...
	
	pick-row: function [
		"Pick row id after filtering and sorting"
		row [integer!] "Y"
	][
		included+ordered/y/:row
	]
	
	pick-column: function [
		"Pick column id after filtering and sorting"
		column [integer!] "X"
	][
		included+ordered/x/:column
	]
	
	pick-filter: function [
		"Pick filter object for given sorted and filtered column"
		column [integer!] "X"
	][
		all [
			colid: included+ordered/x/:column
			:filters/:colid
		]
	]
	
	pick-value: function [
		"Pick a value from the database at given sorted and filtered row and column"
		column [integer!] "X"
		row    [integer!] "Y"
	][
		all [
			colid: included+ordered/x/:column
			rowid: included+ordered/y/:row
			:data/(colid by rowid)
		]
	]
	
	pick-header: function [
		"Pick header name for given column after filtering and sorting"
		column [integer!] "X"
		/id "Ignore filtering and sorting, 'column' is a column id"
	][
		all [
			colid: either id [column][included+ordered/x/:column]
			:data/(colid by 0)
		]
	]
	
	find-header: function [
		"Get column id from its header title"
		title  [string!]
	][
		repeat icol ncols [if :data/(icol by 0) = title [return icol]]
		none
	]
	
	write-value: function [
		"Replace a value in the database at given sorted and filtered row and column"
		column [integer!] "X"
		row    [integer!] "Y"
		value  [string!]
	][
		data/(included+ordered/x/:column by included+ordered/y/:row): :value
	]
	
	write-header: function [
		"Replace a header title in the database at given sorted and filtered column"
		column [integer!] "X"
		value  [string!]
	][
		data/(included+ordered/x/:column by 0): :value
	]
	
	add-row: function [
		"Insert a new row at given index; return new row's id"
		slot [integer!] (slot >= 0) "After which sorted included row to put it (0 = at the top)"
	][
		rowid: data/rows: data/rows + 1
		repeat icol ncols [put data icol by rowid copy {}]
		append included/y rowid
		order: either slot = 0 [ordered/y][next find ordered/y pick-row slot]
		insert order rowid
		insert skip included+ordered/y slot rowid
		rowid
	]
	
	hide-row: function [
		"Hide row with given id"
		rowid [integer!] (rowid > 0)
	][
		filters/-1/excluded/:rowid: on
		remove find included/y rowid
		remove find included+ordered/y rowid
	]
	
	show-row: function [
		"Show hidden row with given id"
		rowid [integer!] (rowid > 0)
	][
		unless find included/y rowid [
			filters/-1/excluded/:rowid: off
			sort append included/y rowid
			modified/y: yes
		]
	]
	
	add-column: function [
		"Add a new column and include it; return new column's id"
		slot [integer!] (slot >= 0) "After which sorted included column to put it (0 = at the left)"
	][
		colid: data/cols: data/cols + 1
		repeat irow nrows [put data colid by irow copy {}]
		put data colid by 0 copy {}								;-- insert header cell as well
		append filters make filter! [column: colid]
		append included/x colid
		order: either slot = 0 [ordered/x][next find ordered/x pick-column slot]
		insert order colid
		insert skip included+ordered/x slot colid
		colid
	]
	
	hide-column: function [
		"Hide column with given id"
		colid [integer!] (colid > 0)
	][
		remove find included/x colid
		remove find included+ordered/x colid
	]
	
	show-column: function [
		"Show hidden column with given id"
		colid [integer!] (colid > 0)
	][
		unless find included/x colid [
			sort append included/x colid
			modified/x: yes
		]
	]
	
	is-column-shown?: function [
		"True if column with given id is inside included columns list"
		colid [integer!] (colid > 0)
	][
		to logic! find included/x colid
	]
	
	swap-columns: function [
		"Swap the order of columns with given ids"
		colid1 [integer!] (colid1 > 0)
		colid2 [integer!] (colid2 > 0)
	][
		swap find ordered/x colid1
			 find ordered/x colid2
		modified/x: yes
	]
]

