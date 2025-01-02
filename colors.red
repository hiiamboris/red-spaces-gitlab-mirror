Red [
	title:    "Color-related helper funcs for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.colors
	depends:  [advanced-function color-models]
]

svf:  system/view/fonts
svm:  system/view/metrics
svmc: system/view/metrics/colors

resolve-color: function [
	"Turn COLOR into a tuple! value"
	color [tuple! word! issue!] "Word resolves to system theme colors"
][
	switch type?/word color [
		word!  [svmc/:color]
		issue! [hex-to-rgb color]
		tuple! [color]
	]
]

impose: function [
	"Impose COLOR onto BGND and return the resulting color"
	bgnd  [tuple! word!] "Alpha channel ignored"
	color [tuple! word!] "Alpha channel determines blending amount"
][
	c3: c4: 0.0.0.0 + resolve-color color
	c3/4: none
	bg-amnt: c4/4 / 255
	interpolate c3 (resolve-color bgnd) bg-amnt
]

#assert [
	0.0.0   = impose 0.0.0     0.0.0
	0.0.0   = impose 100.50.10 0.0.0
	50.25.5 = impose 100.50.10 0.0.0.128
]


blend: context [
	HSL->HL2S: function [p [point3D!] o [float!]] [as-point3D p/1 p/3 ** o p/2]
	HL2S->HSL: function [p [point3D!] o [float!]] [as-point3D p/1 p/3 p/2 ** (1.0 / o)]
	adjust: function [p1 [point3D!] p2 [point3D!]] [
		case [
			any [p1/2 = 0 p1/2 = 1]	[p1/1: p2/1  p1/3: p2/3]	;-- L(/2) cylinders must be prioritized over the S(/3) plane
			p1/3 = 0				[p1/1: p2/1]				;-- then there's no "jump" between 0.0.0 and 0.0.1-like colors
		]
		p1
	]
	
	;; see %tests/blend-lab.red header for design notes
	return function [
		"Get new color from a projection of BGND->COLOR vector in HSL cylinder scaled by AMOUNT"
		bgnd   [tuple! word!] "(alpha channel is ignored)"
		color  [tuple! word!] "(alpha channel is ignored)"
		amount [number!] "0..100% = bgnd..color, <0% and >100% is extrapolation"
		/order order': 1.5 [float!] "Polynomial order for the lightness (radius) component"
	][
		bg: HSL->HL2S (RGB->HSL resolve-color bgnd ) order'
		fg: HSL->HL2S (RGB->HSL resolve-color color) order'
		bg: cylindrical->cartesian adjust bg fg
		fg: cylindrical->cartesian adjust fg bg
		amount: clip amount -1e10 1e10							;-- clip to avoid NaNs when amount is infinite
		result: interpolate bg fg amount
		result: HL2S->HSL (cartesian->cylindrical result) order'
		HSL->RGB/tuple clip (-1.#inf, 0, 0) (1.#inf, 1, 1) result
	]
]


#assert [
	255.0.0     = blend red green   0
	0.255.0     = blend red green   1
	177.88.0    = blend red green   1 / 3
	161.161.0   = blend red green   0.5
	255.233.240 = blend red green  -1
	233.255.240 = blend red green   2
	cyan        = blend black red  -1
	cyan        = blend red black   2
	yellow      = blend black blue -1
	yellow      = blend blue black  2
	255.150.150 = blend cyan red    1.5
	white       = blend cyan red    2
	white       = blend red green  -1.#inf
	white       = blend red green   1.#inf
]
; do with self load %tests/blend-test.red quit
; do with self load %tests/blend-lab.red quit


;@@ any better name?
opaque: function [
	"Add alpha channel to the COLOR"
	color [tuple! word! issue!] "If a word, looked up in system/view/metrics/colors"
	alpha [percent! float!] (all [0 <= alpha alpha <= 1])
][
	color: 0.0.0.0 + resolve-color color
	color/4: to integer! 255 - (255 - color/4 * alpha)
	color
]

