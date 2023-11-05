Red [
	title:       "ParSEE"
	description: "Parsing flow visual analysis tool"
	purpose:     "Never again debug Parse rules using randomly inserted print statements"
	author:      @hiiamboris
	license:     'BSD-3
	needs:       [View]
	notes: {
		See https://codeberg.org/hiiamboris/red-spaces/src/branch/master/programs/README.md#parsee-parsing-flow-visual-analysis-tool-parsee-tool-red
	}
]


#include %../everything.red
#process off
do/expand [
#include %../../common/format-number.red
#include %../../cli/cli.red
]
#process on

system/script/header: object [	 						;@@ workaround for #4992
	title:   "ParSEE"
	author:  @hiiamboris
	license: 'BSD-3
]

context with spaces/ctx expand-directives [
	{
		A reminder on how this is all organized and terms.
		
		Dump is decoded into rule profiles and rule marks.
		
		A rule profile is a graph of Y=input-offset(X=age).
		Age works as sort of global internal 'time' of the parser.
		It has an offset semantic: zero-based number between events.
		Each included parser event has a one-based number 'tick'.
			Age:  0_1_2_3_4_5... <- offsets between events
			Tick: |1|2|3|4|5|... <- event number, transition between ages
			
		Rule profile is a vector of quartets [age region input-offset text-offset] delimited by [event]s, where:
		region = an incremental id of the region used for highlighting of reentrant rules
		input-offset = offset in the original input, e.g. for block - in values
		text-offset = offset in molded input, for both string block - in chars
		event = enum defined below (region open, close, and stay)
		
		Rule 'marks' are a global sequence of Y=rule+offset(X=age) for each age.
		Since parser works with only one rule at a time, it's a single hash.
		This rule 'offset' is called 'mark' and it's an offset inside rule's molded text.
		For unnamed rules, the offset is inside their named parent's molded text.
		It is used to color the location, where we are in the ruleset right now.
		
		A 'chart' is a mapping from block offsets into molded text marks, for each rule.
		Chart format is: ["molded-text" mark0 mark1 ... markLEN]  
	}
	
	;; events encoded in the profile (negative just for easier vector reading)
	event-open:	   -1									;-- entry into new named rule
	event-imove:   -2									;-- input movement
	event-rmove:   -3									;-- rule movement
	event-match:   -4									;-- left from a named rule
	event-fail:    -5									;-- ditto
	;; profile data field offsets
	i-age:          1
	i-region:       2
	i-input-offset: 3
	i-text-offset:  4
	i-next-event:   5

	;; colors for the parsing profiles plots need to be fixed, but I adapt them to night/day mode:
	colors: #()													;-- saturated colors
	colors/panel: any [attempt [system/view/metrics/colors/panel] white]
	dark?: (brightness? colors/panel) < 0.5
	extend colors map-each [color [issue!]] either dark?
		[[canvas: #111 red: #F66 yellow: #EB0 green: #2E2 gray: #BBB text: #FFF]]
		[[canvas: #FFF red: #F22 yellow: #DA6 green: #2E2 gray: #AAA text: #000]]
		[hex-to-rgb color]
	;; translucent colors; multiple passes of the same rule should be clearly distinguishable
	light: map-each [color [tuple!]] colors [opaque color either dark? [50%][25%]]
	
	;; spaces mold is not used here
	mold: :native-mold
		
	;@@ remove keywords and scanning
	keywords: make hash! [
		| skip quote none end
		opt not ahead
		to thru any some while
		if into fail break reject
		set copy keep collect case						;-- collect set/into/after? keep pick?
		remove insert change							;-- insert/change only?
		#[true]
	]

	;; I haven't found any other way to extract the names
	;; I tried collecting first words of the 'fetch' event,
	;; but sometimes it may be at 'opt name' and who knows what other cases are possible
	scan-rule-names: function [rule [block!]] [
		result:  make #() 32							;-- only named
		scanned: make hash! 32							;-- also unnamed rules (avoid recursion and double scanning)
		parse rule scan-block: [
			p: if (find/only/same scanned head p) to end
		|	p: (append/only scanned head p)
			any [
				set w word! (
					if all [
						not keywords/:w
						block? try [block: get/any w]
					][
						parse result/:w: block scan-block
					]
				)
			|	ahead block! into scan-block
			|	skip
			]
		]
		result
	]

	;; measure the geometry of molded any-blocks
	decor: make hash! #hide [map-each/eval type (to [] any-block!) [
		molded: mold append make get type 0 [| |]
		parse molded [to "|" item1: skip to "|" item2:]
		prefix: skip? item1
		suffix: length? next item2
		sep: -1 + offset? item1 item2
		[type prefix sep suffix]
	]]
	
	nonws!: complement charset " ^-^/"
	skip-ws: func [s [string!]] [any [find s nonws!  tail s]]
	
	;@@ since this is O(depth^2) it would be better if mold had a callback
	;; returned format: [rule-block chart-block ...] (may be multiple pairs if there are nested unnamed rules)
	chart-block: function [
		"Obtain molded text offsets for all block offsets (deeply)"
		rule [any-block!]
		/flat "Remove newlines"
		/only types: block! [datatype! typeset!] "Include only these datatypes"
		/base text: (mold/:flat rule) "Override molded text or its current offset"
	][
		result: new-line reduce [rule chart: make [] 2 + length? rule] on
		set [prefix: sep: suffix:] next find decor type?/word rule 
		to-item: [keep (skip? text: skip-ws skip text prefix)]
		skip-item: [
			set item types (
				append result inner: chart-block/base item text
				text: skip head text suffix + last inner/2
			)
		|	set item skip (text: skip text length? mold/flat item)
		]
		skip-to-next: [
			end keep (skip? skip-ws text)
		|	keep (skip? text: skip-ws skip text sep)
		]
		parse rule [
			collect after chart [
				keep (head text) to-item any [skip-item skip-to-next]
			]
		]
		result
	]
	
	#assert [
		[[] ["[]" 1]] = chart-block []
		[
		    [[]] ["[[]]" 1 3] 
		    [] ["[[]]" 2]
		] = chart-block [[]]		
		[
			[1 2 ["30" ["40"] []] 5] [{[1 2 ["30" ["40"] []] 5]} 1 3 5 22 23] 
			["30" ["40"] []] [{[1 2 ["30" ["40"] []] 5]} 6 11 18 20] 
			["40"] [{[1 2 ["30" ["40"] []] 5]} 12 16] 
			[] [{[1 2 ["30" ["40"] []] 5]} 19]
		] = chart-block [1 2 [{30} [{40}] []] 5]
	]
	
	locate-age: function [
		"Return profile at the given age"
		profile [vector!] age [integer!]
	][
		if empty? profile [return profile]
		n: (1 + length? profile) / 5
		set [o1: f1: o2: f2:] search/for o: 0 n - 1 [profile/(o * 5 + i-age)] age
		skip profile 5 * either age < f2 [o1][o2]
	]
	#assert [
		0  = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 0
		5  = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 1
		10 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 2
		15 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 3
		15 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 4
		15 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 5
		20 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 10
		25 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 11
		25 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 12
		25 = skip? locate-age make vector! [0 0 0 0 0 1 0 0 0 0 2 0 0 0 0 3 0 0 0 0 10 0 0 0 0 11 0 0 0] 100
	]
	
	replay: function [
		"Apply a limited sequence of profile changes to the input RTD flags"
		profile [vector!] flags [block!] age1 [integer!] age2 [integer!]
	] reshape [
		set [frange: fcolor:] [1 3]
		step:    5 * sign: sign? age2 - age1
		ievent:  pick [-1 5] back?: sign = -1
		at-age1: locate-age profile age1
		at-age2: locate-age profile age2
		; probe new-line/skip to [] profile on 5 ?? at-age1 ?? at-age2
		options: either back? [[
			!(event-imove) [dst-flag/:frange/2: dst-offset + 1 - dst-flag/:frange/1]
			!(event-open)  [src-flag/:frange/2: 0]
			!(event-match)
			!(event-fail)  [dst-flag/:fcolor: light/yellow]
		]] [[		
			;; do not rewind length on exit, let color stay: ;@@ or any better way?
			!(event-imove) [if 0 < len: dst-offset + 1 - dst-flag/:frange/1 [dst-flag/:frange/2: len]]
			!(event-open)  [if tail? dst-flag [reduce/into [(dst-offset + 1 by 0) 'backdrop light/yellow] dst-flag]]
			!(event-match) [src-flag/:fcolor: light/green]
			!(event-fail)  [src-flag/:fcolor: light/red]
		]]
		; ?? [age1 age2]
		dst: at-age1 while [not same? src: dst at-age2] [
			event:      src/:ievent
			dst:        skip src step
			src-flag:   skip flags src/:i-region * 3
			dst-flag:   skip flags dst/:i-region * 3
			dst-offset: dst/:i-text-offset
			; print ""
			; ?? [event src-flag dst-flag dst-offset]
			switch event options
			; ?? [event src-flag dst-flag]
		]
		flags
	]
	
	render-profile: function [
		"Create a draw block out of profile data"
		profile [vector!]
	] reshape [
		repend failures:  clear [] ['fill-pen colors/red]
		repend successes: clear [] ['fill-pen colors/green]
		peak:    1
		old-xy:  0x0
		runs:    make-stack 2x10
		run:     none											;-- initial run is ignored
		; probe new-line/skip to [] profile on 5 
		foreach [event x region iofs tofs] skip profile 4 [
			all [												;-- close the previous segment
				old-xy/y > 0
				run
				either any [
					tail? run
					(end: tail run  end/-2/y <> old-xy/y)		;-- try to join with the last segment
				][
					repend run ['box (old-xy) (x by 0)]
				][
					end/-1/x: x
				]
			]
			switch event [
				!(event-imove) [
					if run [peak: max peak y: iofs - start]
				]
				!(event-open) [
					runs/push [run: make [] 32 start: iofs]		;-- stash the run for later restoration
					y: 0										;-- new run starts at zero height
				]
				!(event-match)
				!(event-fail) [
					target: either event = event-match [successes][failures]
					#assert [run]
					unless empty? run [append/only target run]
					runs/pop
					set [run: start:] runs/top
					if run [peak: max peak y: iofs - start]
				]
			]
			old-xy: x by y
		]
		compose/deep/only [
			pen off scale 1.0 (1.0 / peak) [
				(copy failures)
				(copy successes)
			]
		]
	]

	
	;; holds all rule-related data in one place
	rule-info!: object [
		;; every rule has:
		rule:      none
		chart:     none
		;; only named rules have:
		name:      none
		depth:     none									;-- 0 = top level, >0 rest
		profile:   none
		keyframes: none									;-- state snapshots for fast replay
		plot:      none									;-- draw block
	]
	
	
	get-rule-mark: function [
		"Get molded text offset for given rule at given age"
		marks [hash!] rule-info [object!] age [integer!] (age >= 0)
	][
		any [
			select/same/only/reverse/skip
				skip marks age * 2 - 1
				rule-info/rule
				2
			rule-info/chart/1							;-- default to head before any events
		]
	]
	
	offset->mark: function [
		"Convert block offset within a rule into molded text mark of a named rule"
		chart [block!] offset [integer!]
	][
		skip chart/1 pick chart offset + 2				;-- +1 to skip text, +1 to convert offset into pick-index
	]


	;@@ maybe discard rules that never advanced input? or those that can't advance input (pure code rules)?
	
	;@@ need to use 'changes' block too (only reason why dump has 'age' is to sync changes to parsing)
	;@@ if input is modified, this affects offsets after it, thus text highlighting may shift - need to care for
	decode-dump: function [dump [block!] (parse dump [series! 2 block!])] [
		set [cloned: events: changes:] dump
		#assert [not empty? events]								;-- parse can never generate zero events
		input:     events/2
		top-level: events/5
		; ?? input ?? changes print ["events:" mold/all events]
		
		marks: make block! (length? events) / 6 + 1 * 2			;-- [rule offset] pairs at each age
		
		named: to hash! scan-rule-names top-level				;-- named rules dictionary: name -> info object
		either found: find/only/same named top-level [			;-- top level rule may be named in case: parse input name
			top-level-name: found/-1
		][
			top-level-name: 'top-level
			#assert [not find named 'top-level]
			repend named ['top-level top-level]
		]
		
		if on-block: any-block? input [input-charts: make hash! chart-block input]
		; ?? input-charts
		
		;; chart-block also lists unnamed nested rules, which are then spread across info objects 
		charts: map-each [name rule] named [chart-block/flat rule]
		rules: to hash! map-each/eval [rule chart] charts [		;-- registry of all visited rule blocks: rule block -> info object
			info: make rule-info! []
			#assert [head? rule]								;@@ must be ensured by the dumper?
			info/rule:      rule
			info/chart:     chart
			info/profile:   clear make vector! 4096
			info/keyframes: make [] 32
			;; info/depth = none initially: after decoding it indicates that this block is not a rule, or it was never reached
			text-offset: either on-block [input-charts/2/2][0]
			repend info/profile [0 0 0 text-offset]
			[rule info]
		]
		map-each/self/eval [name rule] named [
			info: select/only/same/skip rules rule 2
			info/name: name
			[name info]
		]
		
		;; decoder's immediate data
		scope-stack: clear []							;-- [scope info pos depth...] quartets; depth may change for the same scope
		depth: 0
		age:   -1
		
		new-age: func [scope info "current, possibly unnamed" pos] [
			mark: offset->mark info/chart skip? pos/:irule
			;; collect named rule, not current rule as only named rules serve as search keys
			repend marks [head scope/rule  mark]
			; ?? [age mark pos/:ievent]
			age: age + 1
		]
		get-text-offset: func [orig-series [series!]] pick [[
			chart: select/only/same/skip input-charts head orig-series 2
			chart/(2 + skip? orig-series)
		][
			skip? orig-series
		]] on-block
		
		scope: named/:top-level-name
		prev-inpos: input
		set [iinput: ievent: imatch?: irule: isubj:] [2 3 4 5 6]
		
		;; handle first push event manually
		#assert [events/:ievent = 'push]
		new:         events
		inp-offset:  skip?           new/:iinput
		text-offset: get-text-offset new/:iinput
		next-age:    new-age scope scope new
		repend scope/profile [event-open next-age 0 inp-offset text-offset]
		repend scope-stack   [scope scope new scope/depth: 0]
			
		;; kludge to handle last event as well
		append events end: skip tail events -6
		poke end 6 + ievent 'end
		
		while [not tail? new: skip old: new 6] [
			;; infer high level features
			old-info: select/only/same/skip rules head old/:irule 2
			new-info: select/only/same/skip rules head new/:irule 2
			into-named?: if
				entered?: all [new/:ievent = 'push  block? new/:isubj]
				[new-info/name]
			from-named?: if
				exited?:  all [old/:ievent = 'pop   block? old/:isubj]
				[old-info/name]
			scope-inout?: any [into-named? from-named?]			;-- possibly into/from the same scope (recursing)
			
			;; update tracked state
			if entered? [
				if into-named? [
					scope: new-info
					depth: depth + 1
					new-info/depth: min-safe depth new-info/depth
				]
				repend scope-stack [scope new-info new depth]
			]
			
			if scope-inout? [
				#assert [not all [entered? exited?]]			;-- should never happen
				either entered? [
					p-event: event-open
					pos:     new
					info:    new-info
				][
					p-event: either old/:imatch? [event-match][event-fail]
					pos:     old
					info:    old-info
				]
				inp-offset:  skip?           pos/:iinput
				text-offset: get-text-offset pos/:iinput
				next-age:    new-age scope info pos 
				repend scope/profile [p-event next-age 0 inp-offset text-offset]
			]
			
			if exited? [
				; clear set [scope: _: _: depth:] skip tail scope-stack -4
				set [scope: _: old: depth:] skip tail scope-stack -8
				clear skip tail scope-stack -4
			]

			any [
				rule-switch?:  not same? head old/:irule  head new/:irule
				rule-move?:    not same?      old/:irule       new/:irule
			]
			any [
				input-switch?: not same? head old/:iinput head new/:iinput
				input-move?:   not same?      old/:iinput      new/:iinput
			]
			
			;; log event into the relevant rule profile
			if any [all [input-move? not input-switch?] rule-switch? rule-move?] [
				p-event:     either all [not input-switch? input-move?] [event-imove][event-rmove]
				inp-offset:  skip?           new/:iinput
				text-offset: get-text-offset new/:iinput
				next-age:    new-age scope new-info new
				repend scope/profile [p-event next-age 0 inp-offset text-offset]
			]
			
		];while [not tail? new: skip old: new 6] [
		
		;; some profiles may have been left open, due to exception/return/etc - consider them failed
		while [not tail? scope-stack] [
			clear set [scope: info: pos: depth:] skip tail scope-stack -4
			if info/name [								;-- pass thru entered unnamed rules, or profile is closed many times
				inp-offset:  skip?           pos/:iinput
				text-offset: get-text-offset pos/:iinput
				next-age:    new-age info info pos 
				repend scope/profile [event-fail next-age 0 inp-offset text-offset]
			]
		]
		
		marks: new-line/skip make hash! marks on 2
		rules: new-line/skip rules on 2
		
		;; remove blocks that either aren't rules or were never reached
		;@@ can dumper handle this instead?
		remove-each [name info] named [not info/depth]
		
		;; enumerate regions of each profile
		foreach [name info] named reshape [
			profile:  info/profile
			nregions: 0
			regions: clear []
			while [event: profile/:i-next-event] [
				profile: skip profile 5
				switch event [
					!(event-open) [
						append regions region: nregions			;-- region is 0-based for faster replay
						nregions: 1 + nregions
					]
					!(event-match)
					!(event-fail) [
						take/last regions
						region: any [last regions 0]
					]
				]
				profile/:i-region: region
			] 
		]
		
		;; sort named rules by depth
		compare: func [a b] [b/2/depth - a/2/depth]
		named:   make map! sort/stable/skip/compare/all named 2 :compare
		#assert [
			hash? rules
			hash? marks
			any [not on-block  hash? input-charts]
		]
		
		; ?? named/top-level
		; ?? named/rule
		
		to map! compose/only [
			max-age:      (max 0 age)					;-- >= 0
			named:        (named)						;-- (map)  info of named rules:    name -> info-object
			rules:        (rules)						;-- (hash) info of all rules:      [rule-block info-object] pairs
			marks:        (marks)						;-- (hash) rule marks per age:     [rule-block rule-mark] pairs
			input-charts: (input-charts)				;-- (hash) any-block input charts: [input-block chart-block] pairs
		]
	];decode-dump: function [dump [block!] (parse dump [series! 2 block!])] [
	
	;; 'replay' is surprisingly fast: about 7ms per profile of 3000 events - that's 2.3us/event
	;; in worst case - 1 event/tick - 5ms will be enough for 2k events, on slower CPU 1k
	;; so it makes sense to have keyframes at 1k intervals give or take
	key-step: 1024
	
	get-keyframe: function [
		"Ensure keyframe at given age exists and return it"
		keyframes [block!] profile [vector!] age [integer!] (age % key-step = 0)
	][
		unless flags: pick keyframes age / key-step + 1 [
			if empty? keyframes [append/only keyframes []]
			flags: last keyframes
			last-age: key-step * (-1 + length? keyframes)
			while [last-age < age] [
				append/only keyframes flags:
					replay profile copy flags last-age last-age: last-age + key-step
			]
		]
		flags
	]
	
	get-flags: function [
		"Get input flags block for a given profile at given age"
		keyframes [block!] "Keyframes data collected so far"
		profile   [vector!]
		age       [integer!]
		/from "Last known age and flags block"
			last-age:   0  [integer!]
			last-flags: [] [block!]
	][
		nearest-key: round/to age key-step
		if (abs age - last-age) >= (abs age - nearest-key) [	;-- last-age farther than keyframe
			last-flags: get-keyframe keyframes profile last-age: nearest-key
		]
		replay profile copy last-flags last-age age
	]
	
	color-input: function [
		"Paint input text with rule profile at given age"
		input [object!] ('text = class? input) rule-info [object!] age [integer!]
	][
		unless all [
			from: input/rule =? rule-info
			input/age = age
		][
			input/flags: get-flags/:from rule-info/keyframes rule-info/profile age input/age input/flags
			input/rule:  rule-info
			input/age:   age
		]
	]
	
	color-rule: function [
		"Paint molded rule text to reflect its offset at given age"
		text [object!] ('text = class? text) marks [hash!] rule-info [object!] age [integer!]
	][
		done: skip? rule-mark: get-rule-mark marks rule-info age
		unless all [
			text/flags/1 = (1 by done)
			text/text    =? head rule-mark
		][
			if empty? text/flags [text/flags: compose [0x0 backdrop (light/green)]]
			text/flags/1: 1 by done
			text/text:    head rule-mark
		]
	]
	
	refresh-progress: function [
		"Update UI to reflect given age"
		input-view [object!] plot-list [block!] marks [hash!] age [integer!] cursor [integer! none!]
	][
		if cursor [
			row: plot-list/:cursor
			color-input input-view row/info age
		]
		foreach row plot-list [
			row/children/plot/age: age							;-- update profile cursor
			color-rule row/children/rule marks row/info age		;-- update rule text
		]
	]
	
	refresh-zoom: function [
		"Update profiles zoom"
		plot-list [block!] zoom [number!]
	][
		foreach row plot-list [row/children/plot/zoom: zoom]
	]
		
	;; profile-plot custom template
	context [
		~: self
		
		draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
			space/size: space/max-age * space/zoom . 30
			compose/only/deep [
				matrix [1 0 0 -1 0 (space/size/y)] 
				line-width 0.5 fill-pen (colors/canvas) box 0x0 (space/size)
				scale (space/zoom) (space/size/y * 1.0) (space/plot)
				line-width 1 pen (colors/text) translate (space/age * space/zoom by 0) [line 0x0 (0 by space/size/y)]
			]
		]
		
		declare-template 'profile-plot/box [
			plot:    [1]	#type [block!] :invalidates
			zoom:    1.0	#type [float! percent!] :invalidates	;@@ need UI to control it, maybe ctrl+wheel?
			age:     0		#type [integer!] :invalidates-look		;-- shows time cursor
			max-age: 0		#type [integer!] :invalidates			;-- determines plot width
			on-move: none	#type [none! function!]					;-- propagates movement up the tree
			draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
		]
		
		define-handlers [
			profile-plot: [
				on-down [space path event] [
					space/on-move space path
					start-drag path
				]
				on-up   [space path event] [stop-drag]
				on-over [space path event] [if dragging? [space/on-move space path]]
			]
		]
	]
	
	monofont: make font! [name: system/view/fonts/fixed]
							
	;@@ layout: grid-view with 2 vlists (1 pinned), so rule names are always visible
	;@@ for that grid-view will have to support row selection, like in list-view
	;@@ BUG: when profiles are too wide it won't allow to scroll to them, likely triggering slide during intermediate redraws
	visualize-parse: function [file [file!] /config conf: #() [map!]] [
		;; load the dump file
		input: first data: load/as file 'redbin
		decoded: decode-dump data
		foreach key [max-age: named: rules: marks: input-charts:] [set key decoded/:key]
		input-text: any [if input-charts [input-charts/2/1] input]
		
		;; turn rule profiles into graphic shapes
		foreach [name info] named [info/plot: render-profile info/profile]
		
		;; generate UI part for each named rule
		rows: map-each [name info] named [
			compose/deep/only [
				rule-row on-created [
					space/info: (info)
					do with children [
						name/text: (form name)
						plot/plot: (info/plot)
						rule/text: (mold/flat info/rule)
					]
				]
			] 
		] 
		plot-list: lay-out-vids reshape [
			style rule-row: hlist tight type= 'item info= none [
				name: text 100
				vlist tight [
					plot: profile-plot max-age= max-age
					on-move= quote !(func [space path] [
						timeline/offset: 100% * clip 0 1 path/2/x / space/size/x
					])
					box left margin= 2x1 color= colors/canvas [
						rule: text font= monofont color= colors/text
					]
				]
			] @(rows)
		]
		
		;; run the UI
		default conf/offset: -8x0 
		default conf/size:   system/view/screens/1/size - 0x60
		prof/reset
		view/tight/options window: layout reshape [
			title !(`"ParSEE - (file)"`) 
			host [
				column [
					text bold "Parsed input:"
					cell color= colors/canvas [scrollable [
						input-view: text !(input-text) limits= 100x100 .. none
							color= colors/text font= monofont
							age= 0 rule= none			;-- last state stored for fast replay
					]]
					; <-> 0x10							;@@ doesn't work when compiled - #5137
					stretch 0x10 text bold "Timeline:"
					timeline: slider 100% focus step= 100% / max 1 max-age
						age= 0 react [age: to integer! 1 + max-age * timeline/offset]	;-- source of changes into other spaces
					; <-> 0x10							;@@ doesn't work when compiled - #5137
					stretch 0x10
					row margin= 0 [
						text bold "Applied rules:"
						stretch
						hlist margin= 0 [
							text bold "Zoom:"
							box [zoom: slider 200 100% marks= 25% step= 1% ratio= 0 react [ratio: 1% ** (1 - zoom/offset)]]
							text 50
								react [text: format-number zoom/ratio 1 2]
								react [refresh-zoom plot-list zoom/ratio]
						] 
					]
					profiles-view: list-view selectable tight source= !(plot-list) selected= [1] cursor= 1
						on-key-down [
							if sign: switch event/key [left [-1] right [1]] [
								timeline/offset: clip 0% 100% timeline/offset + (sign / max-age) stop
							]
						]
						on-wheel [
							if event/ctrl? [zoom/offset: 100% * clip 0 1 zoom/offset + (10% * event/picked)]
						]
						react [refresh-progress input-view plot-list marks timeline/age profiles-view/cursor]
				]
			] react [face/size: face/parent/size - 20]
		] [offset: conf/offset flags: 'resize size: conf/size]
		prof/show
		conf/offset: window/offset
		conf/size:   window/size
	];visualize-parse: function [file [file!]] [
	
	;@@ I need to generalize this; used too often
	get-config-name: function [] [
		if all [
			not system/options/script
			path: system/options/boot
		][
			take/last path: normalize-dir to-red-file path
			set [path: _:] split-path path
			path/parsee.cfg
		]
	]
	load-config: function [] [
		any [
			all [
				conf: get-config-name
				exists? conf
				attempt [to map! load/all conf]
			]
			#()
		]
	]
	save-config: function [config [map!]] [
		if conf: get-config-name [
			attempt [write conf mold/only to [] config]
		]
	]
	
	set 'parsee function [
		"Parsing flow visual analysis tool"
		dump-file [file!] "Path to a .pdump file to analyze"
	][
		config: load-config
		visualize-parse/config dump-file config
		save-config config
	]

];context with spaces/ctx expand-directives [

do [cli/process-into ParSEE]
;@@ remember/restore window offset/size