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

big-font: make font! [size: 15]

;; just for fun
spaces/templates/wheel: make-template 'text [
	font: make font! [size: 27]
	angle: 0
	text: "⚙"
	text-draw: :draw
	draw: does [
		angle: angle + 1 % 360
		drawn: text-draw
		compose/only [rotate (angle) (size / 2) (drawn)]
	]
	rate: 67
]

spaces/templates/rocket: make-template 'wheel [
	disp: 10x10
	text: "🚀"
	burn?: yes
	draw: does [
		if burn? [disp: clip [0x0 20x20] disp + (random 3x3) - 2x2]
		drawn: text-draw
		size: size + 20x20
		compose/only [rotate (angle) (size / 2) translate (disp) (drawn)]
	]
]
define-handlers [
	wheel: [on-time [space path event] [invalidate space update]]
	rocket: extends 'wheel []
]

view/no-wait [
	h: host [
		list with [
			axis: 'y limits: 100 .. 300 spacing: 10x10
			; hint: "This is the host face"
		][
			list with [spacing: 10x0] [
				text with [text: "Clickable URL:"]
				url with [
					text: https://codeberg.org/hiiamboris/red-spaces
					limits: 150 .. 200
					hint: "Click to follow"
				]
			]
			tube with [margin: 50x10] [ 
				rocket with [
					rocket: self
					hint: "Retro-styled racing space ship"
					menu: reshape [
						"Approve the course" #[true] (print "On our way") 
						"Alter the course" #[false] (rocket/angle: random 360 invalidate rocket print "Adjusting...")
						"Beam me up" "🔭" (print "Zweeee..^/- Welcome onboard!")
						"Thrusters overload" !(anonymize 'switch r-switch: make-space 'switch [state: on]) (
							r-switch/state: rocket/burn?: not rocket/burn?
							print pick ["Thrusters at maximum" "Keeping quiet"] rocket/burn?
						)
					]
				]
				wheel with [
					hint: "Just a travelling cog"
					menu: [[radial]
						"A" (print "A chosen")
						"very long sentence" (print "okay")
						"even longer sentence wow" (print "wooow")
						"BB" (print "B chosen")
						"CCC" (print "C chosen")
						"DDDD" (print "D chosen")
						"E E E E E" (print "E chosen")
					]
				]
				rocket with [
					text: "👽"
					hint: "Gray can't find his marbles"
					menu: [[radial round]
						"۶" (print "۶ chosen")
						"🙣" (print "🙣 chosen")
						"Ͽ" (print "Ͽ chosen")
						"ϟ" (print "ϟ chosen")
						"⚼" (print "⚼ chosen")
					]
					set-style 'menu/ring/round-clickable/tube/text [(font: big-font ())]
				]
			]
			; list [switch switch with [state: on]]
			label with [image: #"⚡" text: "Zapper here" hint: "Be careful"]
			label with [image: #"🌐" text: "Funny globe" hint: "No continents"]
			label with [image: #"💥" text: "Hit" hint: "Score +100"]
			label with [image: #"💨" text: "Whoosh" hint: "Time to move on"]
			label with [image: #"💮" text: "Flower store" hint: "50C piece"]
			label with [text: "Label without a sigil" hint: "Some hint"]
			label with [image: "" text: "Label with empty sigil" hint: "Other hint"]
			label with [image: #"🍄" text: "Label with a heading^/and some text" hint: "Yet another hint"]
			;@@ there must be both image="string" and just #"char" ways of adding an image to the label
			label with [image: "👩‍🚀" text: "Label with a heading^/and some text^/on two lines" hint: "Not helpful"]
		]
	]
	base 0x0 rate 0:0:5 on-time [prof/show prof/reset print ["mem:" stats]]
]

; debug-draw 
prof/show prof/reset
unless system/build/config/gui-console? [do-events]