Red [needs: view]

#include %../everything.red

;@@ drop-down will need a higher-level list with selected item and interactivity

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
		v: vlist 100 .. 300 spacing= 10x10 [; hint="This is the host face"
			hl: hlist spacing= 10x0 [
				text "Clickable URL:"
				url 150 .. 200 hint="Click to follow"
					https://codeberg.org/hiiamboris/red-spaces
			]
			row tight margin= 50x10 [ 
				rocket hint="Retro-styled racing space ship" with [
					rocket: self
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
				wheel hint="Just a travelling cog"
					menu=[[radial]
						"A" (print "A chosen")
						"very long sentence" (print "okay")
						"even longer sentence wow" (print "wooow")
						"BB" (print "B chosen")
						"CCC" (print "C chosen")
						"DDDD" (print "D chosen")
						"E E E E E" (print "E chosen")
					]
				rocket hint="Gray can't find his marbles"
					menu=[[radial round]
						"۶" (print "۶ chosen")
						"🙣" (print "🙣 chosen")
						"Ͽ" (print "Ͽ chosen")
						"ϟ" (print "ϟ chosen")
						"⚼" (print "⚼ chosen")
					]
					with [
						text: "👽"
						set-style 'menu/ring/round-clickable/tube/text [(font: big-font ())]
					]
			]
			; list [switch switch with [state: on]]
			label #"⚡" "Zapper here"      hint="Be careful"
			label #"🌐" "Funny globe"     hint="No continents"
			label #"💥" "Hit"             hint="Score +100"
			label #"💨" "Whoosh"          hint="Time to move on"
			label #"💮" "Flower store"    hint="50C piece"
			label "Label without a sigil" hint="Some hint"
			label "Label with empty sigil" hint="Other hint" with [image: ""]
			label #"🍄" "Label with a heading^/and some text" hint="Yet another hint"
			label "👩‍🚀" "Label with a heading^/and some text^/on two lines" hint="Not helpful"
		]
	]
	; base 0x0 rate 0:0:5 on-time [prof/show prof/reset print ["mem:" stats]]
]
; debug-draw 
prof/show prof/reset
unless system/build/config/gui-console? [do-events]