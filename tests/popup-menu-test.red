Red [needs: view]

#include %../everything.red

;@@ THIS NEEDS ACTORS DONE FIRST
;@@ but for now I'm just using a button

;@@ drop-down will need a higher-level list with selected item and interactivity

spaces/templates/popup: make-template 'button [
	layout:  []
] 

define-handlers [
	popup: [
		on-over [space path event] [
			point: face-to-window event/offset event/face
			spaces/ctx/show-hint event/window point "This is a hint!"
			; host: first layout/only compose/only [
				; host (space/layout)
				; on-over [if event/away? [remove find/same event/window/pane face]]
				; on-over [remove find/same event/window/pane face]
			; ]
			; point: face-to-window event/offset event/face
			; center: event/window/size / 2
			; ;; it's placed in the direction towards the center (off the edge)
			; mask: point - center						;-- center-relative offset
			; mask/x: pick [-1 1] mask/x > 0				;-- direction of face placement
			; mask/y: pick [-1 1] mask/y > 0
			; offset: point - (2 * mask) + (host/size - 1 * min 0x0 mask)
			; offset: clip [0x0 event/window/size - host/size] offset		;-- account for window borders as it cannot stick out
			; host/offset: offset
			; append event/window/pane host
		]
	]
]

;; just for fun
spaces/templates/wheel: make-template 'space [
	size: 50x50
	angle: 0
	font: make font! [size: 27]
	draw: does [
		angle: angle + 1 % 360
		compose [translate 25x25 rotate (angle) translate -25x-25 font (font) text 0x0 "⚙"]
	]
	rate: 67
]
define-handlers [
	wheel: [on-time [space path event] [invalidate space update]]
]

view/no-wait [
	h: host [
		tube with [width: 130 spacing: 5x5 hint: "Tube hint"] [
			wheel with [hint: "Just a travelling cog"]
			; popup with [
				; data: "click me buddy" layout: [button with [data: "WTF"]]
			; ]
			label with [image: #"🎯" text: "Assigned" hint: "Hint 1"
				menu: [
					"calc 1+1"   (probe 1 + 1)
					"calc 2*2"   (probe 2 * 2)
					"beam me up" (print "Zweeee")
				]
			]
			label with [image: #"💬" text: "Participating" hint: "Hint 2"]
			label with [image: #"✋" text: "Mentioned" hint: "Hint 3"]
			label with [image: #"🙌" text: "Team mentioned" hint: "Hint 4"]
			label with [image: #"👀" text: "Review requested" hint: "Hint 5"]
		]
	]
]

unless system/build/config/gui-console? [do-events]