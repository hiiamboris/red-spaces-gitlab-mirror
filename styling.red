Red [
	title:    "Styling core for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.styling
	depends:  [spaces.colors  global error map-each]
]


;@@ support local tags declaration?
styling: classy-object [
	"Styles management"

	tags:        make map! 50	#type [map!] "Collection of all known styling tags"
	alterations: make map! 50	#type [map!] "Styling alterations optimized for lookup speed"
	assets: #[
		pens:  #[]
		fonts: #[]
	]	#type [map!] "Shared assets for use in stylesheets"
	
	storage:       none
	define-styles: none
]

styling/assets/pens/checkered: reshape [						;-- used for focus indication
	pattern 4x4 [
		scale 0.5 0.5  pen off  fill-pen @[svmc/text]
		box 1x0 5x1  box 1x5 5x8  box 0x1 1x5  box 5x1  8x5
	]
]
	

styling/storage: classy-object [
	"Stylesheets storage and lookups"

	;; note: alterations are specified as paths in the stylesheet and apply *over* the basic template/style
	store-alteration: function [
		"Store ALTERATION for the given tree PATH in the styling context"
		path       [path! block! word!]
		alteration [object!]
	][
		trees/store-path-value/reverse styling/alterations path alteration
	]
	
	;; I also had an idea of memoized lookups from a map of formed paths but it does not speed it up at all according to the benchmarks
	find-alteration: function [
		"Find the most specialized style alteration for the given tree PATH"
		path    [block! path! word!] "Is reversed before lookup"
		return: [object! none!]
	][
		trees/match-path styling/alterations path
	]
]

;@@ function style support
;@@ let tags also alter facets, not only settings?
global styling/define-styles: function [
	"Define styles using Styling DSL"
	sheet [block!]
	/local x tag
][
	=reset=: [(
		settings: copy []
		facets:   copy []
		tags:     copy []
	)]
	=tag-decl=:   [set tag issue! '= set settings paren! (styling/tags/:tag: to block! settings)]
	=tag=:        [set x issue! not '= (append tags     x)]		;-- don't confuse it with #tag = (..) declaration
	=facets=:     [set x block!        (append facets   x)]
	=settings=:   [set x paren!        (append settings x)]
	=layout=:     [set layout opt word!]
	=pattern=:    [set pattern [set-word! | set-path!]]
	=style-decl=: [=reset= =pattern= =layout= any [=settings= | =facets= | =tag=] =process-style=]
	=process-style=: [(
		tags: map-each tag tags [
			any [
				styling/tags/:tag
				ERROR "Unknown tag (mold tag) found in style '(pattern)'"
			]
		]
		space:    in :with-space 'space
		settings: bind-only compose [(settings) (tags)] space	;-- all settings are creation-bound to 'space' to avoid copy on instantiation
		facets:   bind-only facets space
		style:    as-object [layout: settings: facets:]
		either set-path? pattern [
			styling/storage/store-alteration as path! pattern style
		][
			default layout: 'box
			templates/:pattern/style: style
		]
	)]
	; parse sheet [any [=tag-decl= | =style-decl=] #expect end p: (?? p)]	;@@ why #expect is not expanded??
	parse sheet [
		any [=tag-decl= | =style-decl=]
		[end | p: (ERROR "Unexpected syntax at (mold/part p 100)")]
	]
]
	
	
