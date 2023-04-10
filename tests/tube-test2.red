Red [needs: view]

#include %../everything.red
	
view [
	style block: host 300x300
	;; should be a visible band:
	host 300x300 [row [box blue box green box red]]
	;; should be 2 visible bands:
	host 300x300 [ 
		column [
			row 0x40 .. none [box blue box green box red]
			row 0x40 .. none [box blue box green box red]
		]
	]
	;; should stretch 1st row to fill the available height
	host 300x300 [
		column [
			row 100x40 .. none [box blue box green box red] weight= 1
			row 100x40 .. none [box blue box green box red]
		]
	] return
	;; should not become wider than 300 px - but how?? lets call it a feature instead
	host 610x300 [
		column 300 [
			row 0x50 .. none [box blue box green box red]
			row 0x80 .. none [box blue box green box red]
			row 0x100 .. none [box blue box green box red]
			row 0x120 .. none [box blue box green box red]
			row 0x150 .. none [box blue box green box red]
		]
	]
    ;; should be a column with paragraphs, not spaced to fill whole height because paragraphs dont fill
    host 300x300 [
		column [
			paragraph "123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 "
			paragraph "123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 "
			paragraph "123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 123456789 "
		]
	]
]
