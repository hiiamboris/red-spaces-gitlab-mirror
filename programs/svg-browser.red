Red [
	title:   "SVG browser demo"
	purpose: "Have a handy overview of SVG test suite"
	author:  @hiiamboris
	needs:   [XML View]
]

#include %../everything.red
; #include %/d/devel/red/red-src/red/environment/codecs/XML.red
#process off
context with spaces/ctx expand-directives [

#include %/d/devel/red/common/glob.red

;@@ SVG.red can't be compiled - #5007, so I have to decompress it at runtime
do load/as #do keep [
	dir: what-dir
	change-dir %/d/devel/red/red-src/red/environment/codecs/
	call/wait {d:\devel\red\cli\mockups\inline\inline.exe -e SVG.red SVG-full.red}
	change-dir dir
	save/as #{} load %/d/devel/red/red-src/red/environment/codecs/SVG-full.red 'redbin
] 'redbin
; #include %/d/devel/red/red-src/red/environment/codecs/SVG.red

ordered?: function [
	"Check if value1 comes before value2 in sort order"
	value1 [any-type!] value2 [any-type!]
][
	:value1 =? first sort reduce/into [:value1 :value2] clear []
]

files: [%"🢀"]

file-sorter: func [a b] [
	to logic! any [
		all [dir? a not dir? b]
		ordered? a b
	]
]
read-files: function [] [
	listing: union
		glob/limit/dirs 0
		glob/limit/only/files 0 ["*.svg" "*.svgz"]
	insert clear next files listing
]

declare-template 'preview/list [
	axis: 'y
	spacing: 0x0
	file: make-space 'text  [text: ""]		#type :invalidates
	tile: make-space 'image [data: none]	#type :invalidates
	content: reduce [file tile]
	data: none	#type =? #on-change [space word value] [
		if value [
			space/tile/limits: 90x60 .. 90x60
			space/tile/data:   value
		]
	]
]

declare-template 'data-view/data-view [color: none]

define-styles [
	list-view/window/list/item: [
		margin:  (4,2)
		spacing: (0,0)
		maybe/same file/flags: when find file/text ".svg" [italic]
	]
]

read-files
scales: [scale 1.0 1.0]
use-file: function [index [integer! none!]] [
	case [
		not index [exit]
		index = 1 [change-dir %../]
		dir? file: to file! lister/data/pick index [change-dir file]
		find [%.svg %.svgz] suffix? file [canvas/file: file exit]
		'else [exit] 
	]
	read-files
	trigger 'lister/source
	lister/origin: (0,0)
]

svg-load: function [file [file!] canvas [planar!]] [
	#print "^/loading (file) ..."
	system/codecs/SVG/decode/on file canvas
]

view [
	title "SVG Browser"
	host [
		row [
			column [
				scrollable 600x400 [
					canvas: image scale= 1.0 file= none source= []
					react [canvas/data: compose [scale (canvas/scale) (canvas/scale) (canvas/source)]]
					react [canvas/source: only attempt [svg-load canvas/file canvas/parent/size]]
				]
				row middle 600 [
					text "Zoom level:"
					zoom-slider: scrollable limits= 0x0 .. 500x16 [box 10000] origin= (-5000,0)
					zoom-text: text 50 "100%" data= 0 react [
						zoom-text/data: zoom: power 10 (abs zoom-slider/origin/x / 5e3) - 1
						zoom-text/text: form round/to zoom-text/data 1%
						change/dup next canvas/data zoom-text/data 2
						canvas/limits: (size: canvas/parent/size * zoom) .. size
						canvas/parent/origin: (0,0) 
					]
					button "See the code..." [
						view compose [
							title (rejoin ["Source of " form canvas/file])
							area 600x400 with [
								font: make font! [name: system/view/fonts/fixed]
								text: mold/all prettify/draw canvas/source
							]
						]
					]
				]
			]
			lister: list-view 150 focus selectable source= files
				wrap-data= function [item-data [file!]] [
					make-space 'preview [
						type:  'item
						file/text: item-data
					]
				]
			on-click [if locate path [obj - .. /type = 'item] [use-file lister/selected/1]]
			on-key [
				switch event/key [
					#"^M" right [use-file lister/selected/1]
					#"^H" left [use-file 1]
				]
			]
			timer 4 [
				foreach [item _] lister/list/map [
					file: as file! item/file/text
					if any [item/data  file = files/1  dir? file] [continue]
					item/data: only attempt [svg-load file 90x60]
					exit
				]
			]
		]
	]
];view [

];context with spaces/ctx expand-directives [
