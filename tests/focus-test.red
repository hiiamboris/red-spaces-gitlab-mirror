Red []

#include %../everything.red

view/no-wait [
	across area 50x50 "1" button "2" field "3" return below
	host [hlist [button "4" button "5" field "6"]]
	group-box "panel" [field "7" button "8" area 50x50 "9"]
	host [hlist [button "10" button "11" field "12"]]
]

view/options [
	group-box [host [hlist [button "A" button "B"]]]
] [offset: 800x300]