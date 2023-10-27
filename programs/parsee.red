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
#include %../../cli/cli.red

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
			
		Rule profile consist of couples [locus value ...],
		where 'value' can be:
			integer 'start'   -> absolute input offset at rule entry (basis for following pairs)
			pair    'oldXnew' -> input offset change from old to new, relative to 'start'
			word    'result'  -> 'match or 'fail - end result of the rule (for coloring)
		and 'locus' is a pair: ageXregion,
			'region' being incremental number assigned to each separate run of the rule
			it is required to support coloring of reentrant rules
		
		Rule 'marks' are a global sequence of Y=rule+offset(X=age) for each age.
		Since parser works with only one rule at a time, it's a single hash.
		This rule 'offset' is called 'mark' and it's an offset inside rule's molded text.
		For unnamed rules, the offset is inside their named parent's molded text.
		It is used to color the location, where we are in the ruleset right now.
		
		A 'chart' is a mapping from block offsets into molded text marks, for each rule.
		Chart format is: ["molded-text" mark0 mark1 ... markLEN]  
	}

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

	;; returned format: [rule-block chart-block ...] (may be multiple pairs if there are nested unnamed rules)
	chart-rule: function [
		"Obtain molded text offsets for all block offsets of a rule (deeply)"
		rule [block!]
		/base "Override molded text and initial offset"
			text:   (mold/flat rule)
			offset: 0
	][
		result: new-line reduce [rule base: make [] 2 + length? rule] on
		parse rule [
			collect after base [
				keep (text) keep (offset: offset + 1)			;-- skip "["
				any [
					set item block!
					(append result inner: chart-rule/base item text offset)
					keep (offset: 2 + last inner/2)				;-- 2 = "] "
				|	set item skip
					keep (offset: offset + 1 + length? mold/flat item)
				]
				(unless empty? rule [step/down top base])		;-- last item doesn't have a " " following it
			]
		]
		result
	]
	
	#assert [
		[[] ["[]" 1]] = chart-rule []
		[
		    [[]] ["[[]]" 1 3] 
		    [] ["[[]]" 2]
		] = chart-rule [[]]		
		[
			[1 2 ["30" ["40"] []] 5] [{[1 2 ["30" ["40"] []] 5]} 1 3 5 22 23] 
			["30" ["40"] []] [{[1 2 ["30" ["40"] []] 5]} 6 11 18 20] 
			["40"] [{[1 2 ["30" ["40"] []] 5]} 12 16] 
			[] [{[1 2 ["30" ["40"] []] 5]} 19]
		] = chart-rule [1 2 [{30} [{40}] []] 5]
	]
	
	locate-age: function [
		"Return profile at the given age"
		profile [block!] age [integer!]
	][
		if empty? profile [return profile]
		n: half length? profile
		set [o1: f1: o2: f2:] search/for o: 0 n - 1 [profile/(o * 2 + 1)/1] age
		skip profile 2 * case [
			age <= f1 [o1]
			age <= f2 [o2]
			'else [o2 + 1]
		]
	]
	#assert [
		0  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 0
		2  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 1
		4  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 2
		6  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 3
		8  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 4
		8  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 5
		8  = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 10
		10 = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 11
		12 = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 12
		12 = skip? locate-age [0x1 a 1x1 b 2x1 c 3x1 d 10x1 e 11x1 f] 100
	]
	
	replay: function [
		"Apply a limited sequence of profile changes to the input RTD flags"
		profile [block!] (head? profile) flags [block!] age1 [integer!] age2 [integer!]
	][
		step:    2 * sign: sign? age2 - age1
		set [ilocus: ivalue:] pick [[-2 -1] [1 2]] back?: sign = -1
		at-age1: locate-age profile age1
		at-age2: locate-age profile age2
		flag:    skip tail flags -3 
		pos:     at-age1
		options: either back? [[
			pair!    [flag/1/2: value/1]						;-- progress update
			; integer! [flag: skip clear flag -3]					;-- region entry
			word!    [flag/3: light/yellow]						;-- region close = coloring
		]] [[
			pair!    [flag/1/2: either value/2 = 0 [flag/1/2][value/2]]	;-- do not rewind on exit, let color stay ;@@ better way?
			integer! [if tail? flag [reduce/into [(value + 1 by 0) 'backdrop light/yellow] flag]]
			word!    [flag/3: either value = 'match [light/green][light/red]]
		]]
		while [not same? pos at-age2] [
			flag: skip flags pos/:ilocus/2 - 1 * 3
			switch type?/word value: pos/:ivalue options
			pos: skip pos step
		]
		flags
	]
	
	render-profile: function [
		"Create a draw block out of profile data"
		profile [block!]
	][
		append failures:  clear [] [line 0x0]
		append successes: clear [] [line 0x0]
		runs: clear []
		peak: 1
		last-rise: 0
		foreach [locus value] profile [
			age: locus/1
			switch type?/word value [
				pair! [
					peak: max peak value/2
					repend run [(age by value/1) (age by last-rise: value/2)]
				]
				integer! [
					if run [repend run [(age by last-rise) (age by 0)]] ;-- close the outer region if recursing
					repend runs [last-rise run: make [] 64]
					last-rise: 0
				]
				word! [
					target: either value = 'match [successes][failures]
					repend append target run [(age by last-rise) (age by 0)]
					clear set [last-rise: run:] skip tail runs -2
					if run [repend run [(age by 0) (age by last-rise)]]	;-- reopen the outer region if out of recursion
				]
			]
		]
		compose/deep/only [
			pen off scale 1.0 (1.0 / peak)
			;; since shape can't change color on the fly, it's faster to have single shape per color
			fill-pen (colors/red)   shape (copy append failures  'close)
			fill-pen (colors/green) shape (copy append successes 'close)
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
		set [input: events: changes:] dump
		; ?? input ?? changes print ["events:" mold/all events]
		
		marks: make block! (length? events) / 5 + 1 * 2			;-- [rule offset] pairs at each age
		
		named: make hash! []
		if top-level: events/5 [
			named: to hash! scan-rule-names top-level			;-- named rules dictionary: name -> info object
			either found: find/only/same named top-level [		;-- top level rule may be named in case: parse input name
				top-level-name: found/-1
			][
				top-level-name: 'top-level
				#assert [not find named 'top-level]
				repend named ['top-level top-level]
			]
		]
		
		;; chart-rule also lists unnamed nested rules, which are then spread across info objects 
		charts: map-each [name rule] named [chart-rule rule]
		rules: to hash! map-each/eval [rule chart] charts [		;-- registry of all visited rule blocks: rule block -> info object
			info: make rule-info! []
			#assert [head? rule]								;@@ must be ensured by the dumper?
			info/rule:      rule
			info/chart:     chart
			info/profile:   make [] 1024
			info/keyframes: make [] 32
			;; info/depth = none initially: after decoding it indicates that this block is not a rule, or it was never reached
			[rule info]
		]
		map-each/self/eval [name rule] named [
			info: select/only/same/skip rules rule 2
			info/name: name
			[name info]
		]
		
		;; decoder's immediate data
		starts:  make block! 64									;-- stack of input offsets at each rule's (re)entry
		entered: clear []										;-- [scope depth offset...] triples; depth may change for the same scope
		depth:   -1
		age:     -1
		
		unless empty? events [
			;; all profile modification is kept here isolated, otherwise it's messy
			tick: does [
				mark: offset->mark info/chart skip? rule
				;; collect named rule, not current rule as only named rules serve as search keys
				repend marks [head named/:scope/rule  mark]
				age: age + 1
			]
			get-input-offsets: does [
				inp-offset1: either pair? pair: last profile [pair/2][last entered]
				inp-offset2: (skip? inpos) - last starts
			]
			after-entering-rule: does [
				repend profile [tick last starts]
			]
			before-leaving-rule: does [
				repend profile [tick pick [match fail] match?]
			]
			after-rule-movement: does [
				;; these events are used to display rule advancement, don't affect the input
				repend profile [tick 1x1 * inp-offset: (skip? inpos) - last starts]
			]
			after-input-movement: does [
				repend profile [tick inp-offset1 by inp-offset2]
			]
			
			scope: top-level-name
			while [not tail? events] [					;@@ use for-each when fast
				set [_: inpos: event: match?: rule:] events
				info:    select/only/same/skip rules head rule 2
				profile: named/:scope/profile
				switch event [
					fetch match paren [							;-- all intermediate crap
						get-input-offsets
						if inp-offset1 <> inp-offset2 [after-input-movement]
						rul-offset1: skip? any [prev-rule: events/-1 []]
						rul-offset2: skip? rule
						if rul-offset1 <> rul-offset2 [after-rule-movement]
					]
					push [										;-- just entered a rule maybe, or false alarm
						prev-rule: events/-1
						case [
							not all [							;-- if not within the same rule
								prev-rule
								same? head rule head prev-rule
							][
								if info/name [
									depth: depth + 1
									info/depth: min-safe depth info/depth
									append starts skip? inpos
									scope: info/name
									profile: named/:scope/profile 
									after-entering-rule
								]
								inp-offset: (skip? inpos) - last starts
								reduce/into [scope depth inp-offset] entered: tail entered
							]
							not same? rule prev-rule [			;-- within the same rule, at different offsets
								rul-offset1: skip? prev-rule
								rul-offset2: skip? rule
								after-rule-movement
							]
						]
					]
					pop [										;-- about to leave a rule maybe, or false alarm
						get-input-offsets						;-- may happen if popping through this rule
						if inp-offset1 <> inp-offset2 [after-input-movement]
						next-rule: events/10
						case [
							not all [							;-- popping into another rule
								next-rule
								same? head rule head next-rule
							][
								if info/name [
									before-leaving-rule
									take/last starts
								]
								set [scope: depth: _:] entered: skip clear entered -3
							]
							not same? rule next-rule [			;-- popping within the same rule, different offset
								rul-offset1: skip? rule
								rul-offset2: skip? next-rule
								after-rule-movement
							]
						]
					]
				];switch event [
				events: skip events 5
			];while [not tail? events] [
			
			;; some profiles may have been left open, due to exception/return/etc - consider them failed (e.g.  that's how CSV normally works)
			inp-offset2: 0										;-- closing offset of failed rules is zero
			foreach [name info] named [
				if empty? profile: info/profile [continue]
				unless word? pair: last profile [
					inp-offset1: either pair? pair: last profile [pair/2][0]
					if inp-offset1 <> 0 [after-input-movement]
					before-leaving-rule
				]
			]
		];unless empty? events [
		
		marks: make hash! marks
		
		;; remove blocks that either aren't rules or were never reached
		;@@ can dumper handle this instead?
		remove-each [name info] named [not info/depth]
		
		;; profiles here are age-based, need to convert them into ageXrange based for fast replay
		foreach [name info] named [
			irange: nranges: 0
			ranges: clear []
			map-each/self/eval [age value] info/profile [
				switch type?/word value [
					pair! [[age by irange value]]
					integer! [
						append ranges irange: nranges: nranges + 1
						[age by irange value]
					]
					word! [
						old-irange: take/last ranges
						irange: last ranges
						[age by old-irange value]
					]
				]
			] 
		]
		
		;; sort named rules by depth
		compare: func [a b] [b/2/depth - a/2/depth]
		named:   make map! sort/stable/skip/compare/all named 2 :compare
		#assert [hash? rules]
		#assert [hash? marks]
		
		to map! compose/only [
			max-age:  (max 0 age)						;-- >= 0
			named:    (named)							;-- (map)  info of named rules: name -> info-object
			rules:    (rules)							;-- (hash) info of all rules:   [rule-block info-object] pairs
			marks:    (marks)							;-- (hash) rule marks per age:  [rule-block rule-mark] pairs
		]
	];decode-dump: function [dump [block!] (parse dump [series! 2 block!])] [
	
	;; 'replay' is surprisingly fast: about 150us/1k ticks,
	;; so it makes sense to have keyframes at no less than 1k intervals, up to 10k
	key-step: 4096
	
	get-keyframe: function [
		"Ensure keyframe at given age exists and return it"
		keyframes [block!] profile [block!] age [integer!] (age % key-step = 0)
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
		profile   [block!]
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
		
	;; profile-plot custom template
	context [
		~: self
		
		draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
			space/size: space/max-age * space/zoom . 30
			compose/only/deep [
				matrix [1 0 0 -1 0 (space/size/y)] 
				line-width 0.5 fill-pen (colors/canvas) box 0x0 (space/size)
				scale (space/zoom) (space/size/y * 1.0) (space/plot)
				line-width 1 pen (colors/text) translate (space/age by 0) [line 0x0 (0 by space/size/y)]
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
	visualize-parse: function [file [file!] /config conf: #() [map!]] [
		;; load the dump file
		input: first data: load/as file 'redbin
		decoded: decode-dump data
		foreach key [max-age: named: rules: marks:] [set key decoded/:key]
		
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
						input-view: text !(input) limits= 100x100 .. none
							color= colors/text font= monofont
							age= 0 rule= none			;-- last state stored for fast replay
					]]
					; <-> 0x10							;@@ doesn't work when compiled - #5137
					stretch 0x10 text bold "Timeline:"
					timeline: slider 100% focus step= 100% / max 1 max-age
						age= 0 react [age: to integer! 1 + max-age * timeline/offset]	;-- source of changes into other spaces
					; <-> 0x10							;@@ doesn't work when compiled - #5137
					stretch 0x10 text bold "Applied rules:"
					profiles-view: list-view selectable tight source= !(plot-list) selected= [1] cursor= 1
						on-key-down [
							if sign: switch event/key [left [-1] right [1]] [
								timeline/offset: clip 0% 100% timeline/offset + (sign / max-age) stop
							]
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