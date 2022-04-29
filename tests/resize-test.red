Red [
	title:   "Resize test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
	notes:   {
		inspired by https://easings.net
		easing funcs written by @galenivanov
	}
]

#include %../everything.red

;; wrapped by other funcs but not displayed 
ease-in-out-power: func [x n][either x < 0.5 [x ** n * (2 ** (n - 1))][1 - (-2 * x + 2 ** n / 2)]]

easings: object [
    ease-in-sine:      func [x][1 - cos x * pi / 2]
    ease-out-sine:     func [x][sin x * pi / 2]
    ease-in-out-sine:  func [x][(cos pi * x) - 1 / -2]
    
    ease-in-quad:      func [x][x ** 2]
    ease-out-quad:     func [x][2 - x * x]  ; shorter for [1 - (1 - x ** 2)]
    ease-in-out-quad:  func [x][ease-in-out-power x 2]
    
    ease-in-cubic:     func [x][x ** 3]
    ease-out-cubic:    func [x][1 - (1 - x ** 3)] 
    ease-in-out-cubic: func [x][ease-in-out-power x 3]
    
    ease-in-quart:     func [x][x ** 4]
    ease-out-quart:    func [x][1 - (1 - x ** 4)]
    ease-in-out-quart: func [x][ease-in-out-power x 4]
    
    ease-in-quint:     func [x][x ** 5]
    ease-out-quint:    func [x][1 - (1 - x ** 5)]
    ease-in-out-quint: func [x][ease-in-out-power x 5]
    
    ease-in-expo:      func [x][2 ** (10 * x - 10)]
    ease-out-expo:     func [x][1 - (2 ** (-10 * x))]
    ease-in-out-expo:  func [x][
        either x < 0.5 [
            2 ** (20 * x - 10) / 2
        ][
            2 - (2 ** (-20 * x + 10)) / 2
        ]
    ]
    
    ease-in-circ: func [x][1 - sqrt 1 - (x * x)] 
    ease-out-circ: func [x][sqrt 1 - (x - 1 ** 2)]
    ease-in-out-circ: func [x][
        either x < 0.5 [
            (1 - sqrt 1 - (2 * x ** 2)) / 2
        ][
            (sqrt 1 - (-2 * x + 2 ** 2)) + 1 / 2
        ]
    ]
    
    ease-in-back: func [x /local c1 c3][
        c1: 1.70158
        c3: c1 + 1
        x ** 3 * c3 - (c1 * x * x)
    ]
    ease-out-back: func [x /local c1 c3][
        c1: 1.70158
        c3: c1 + 1
        x - 1 ** 3 * c3 + 1 + (x - 1 ** 2 * c1) 
    ]
    ease-in-out-back: func [x /local c1 c2][
        c1: 1.70158           ; why two constants? 
        c2: c1 * 1.525
        either x < 0.5 [
            2 * x ** 2 * (c2 + 1 * 2 * x - c2) / 2
        ][
            2 * x - 2 ** 2 * (c2 + 1 * (x * 2 - 2) + c2) + 2 / 2
        ]
    ]
    
    ;; I "fixed" these two so they stay inside the plot :)
    ease-in-elastic: func [x /local c][
        c: 2 * pi / 3
        0.2 + negate 2 ** (10 * x - 10) * sin x * 10 - 10.75 * c
    ] 
    ease-out-elastic: func [x /local c][
        c: 2 * pi / 3
        (2 ** (-10 * x) * sin 10 * x - 0.75 * c) + 0.8
    ]
    
    ease-in-out-elastic: func [x /local c][
        c: 2 * pi / 4.5
        either x < 0.5 [
            2 ** ( 20 * x - 10) * (sin 20 * x - 11.125 * c) / -2
        ][
            2 ** (-20 * x + 10) * (sin 20 * x - 11.125 * c) / 2 + 1
        ]
    ]
     
    ease-in-bounce: func [x][1 - ease-out-bounce 1 - x] 
    ease-out-bounce: func [x /local n d][
        n: 7.5625
        d: 2.75
        case [
            x < (1.0 / d) [n * x * x]
            x < (2.0 / d) [n * (x: x - (1.5   / d)) * x + 0.75]
            x < (2.5 / d) [n * (x: x - (2.25  / d)) * x + 0.9375]
            true          [n * (x: x - (2.625 / d)) * x + 0.9984375]
        ]
    ]
    ease-in-out-bounce: func [x][
        either x < 0.5 [
            (1 - ease-out-bounce -2 * x + 1) / 2
        ][
            (1 + ease-out-bounce  2 * x - 1) / 2
        ]
    ]
]

;; plot all easing functions on images
img-size: 100x100
icons: map-each/eval [name easefn] to [] easings [
	points: map-each x 101 [as-pair  x * 9.8  add 130 740 * easefn x - 1 / 100]
	plot: draw make image! reduce [img-size glass] compose/deep [
		scale (10 / img-size/x) (10 / img-size/y)
		line-width 20
		pen linear purple 0.0 teal 1.0
		matrix [1 0 0 -1 0 (10 * img-size/y)]
		line (points)
	]
	[form name plot]
]

;; such a tricky layout requires it's own logic: when to have 1 or 2 columns, and how big
adjust-limits: function [width] [
	for-each [low limit | high] layouts [
		unless all [low <= width width < high] [continue]
		tubes: reduce get expand-space-path 'host/scrollable/tube/item-list
		foreach tube tubes [
			if tube/limits/min <> limit [
				tube/limits/min: limit
				invalidate tube
			]
		]
		break
	] 
]

img-sep:     40
triplet-sep: 80
layouts: reduce [
;; tube limits adjustment table
;;  window-width                            limits/min  
	0										img-size/x	;-- 1 column with single icon
	two:   img-size/x * 2 + img-sep			two        	;-- 1 column with 2 icons
	three: img-size/x * 3 + (2 * img-sep)	three		;-- 1 column with 3 icons
	two   * 2 + triplet-sep					two			;-- 2 columns with 2 icons
	three * 2 + triplet-sep					three		;-- 2 columns with 3 icons
	1.#inf
]

;; VID code for a tube containing 3 icons
triplet: compose/only [
	tube with [limits: 300 .. none  margin: 0x0  spacing: img-sep by 20  align: [↑]]
	(append/dup [] [icon with [text: take icons  image: take icons]] 3)
]

;; VID code for all triplets together
triplets: append/dup [] triplet (length? icons) / 6
    
view/no-wait/flags compose/deep [
	host: host [
		scrollable with [size: 600x400] [
			tube with [margin: 0x0 spacing: triplet-sep by 30 align: [↑]] [
				(triplets)
			]
		]
	] react [
		face/size: max 0x0 face/parent/size - 20		;-- adjust face size
		scrollable: get face/space
		scrollable/size: face/size						;-- adjust scrollable size
		adjust-limits scrollable/size/x - 16			;-- set triplet lower size limit; 16 for the scroller
		face/draw: render face
	] 
] 'resize

unless system/build/config/gui-console? [do-events]
