Red []

#include %../everything.red
#include %../widgets/drop-down-lists.red

view expand-directives [
	h: host [
		vlist 150x250 [
			drop-box  [1 2 3 4 5] right focus react [
				i: index? find/same self/data self/selected
				#print "drop-box: index=(i) item=(mold self/selected)"
			]
			drop-field ["a" "b" "c" "d" "e" "f^/g"] right react [
				i: attempt [index? find self/data self/selected]
				#print "drop-field: index=(i) item=(mold self/selected)"
			] on-key [
				if event/key = #"^M" [space/selected: space/selected]
			]
			; field "cuckoo"
		]
	]
]