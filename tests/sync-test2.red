Red []

; #do [disable-space-cache?: on]
#include %../everything.red
view/flags [
	below
	host white 600x300 [column yello [
		row orange weight= 1 [
			column red weight= 1 [
				row brick weight= 0 [
					cell [text "T"] 25x25 .. none ;[probe 'drag]
				]
				box green 80x80
			]
		]
	]]
	 ; react [face/size: face/parent/size]
	on-over [status/text: mold hittest face/space event/offset]
	status: text 600x30
][resize]
