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

	;; colors for the parsing profiles plots need to be fixed, but I adapt them to night/day mode:
	colors: #()													;-- saturated colors
	colors/panel: any [attempt [system/view/metrics/colors/panel] white]
	dark?: (brightness? colors/panel) < 0.5
	extend colors map-each [color [issue!]] either dark?
		[[canvas: #111 red: #F66 yellow: #EB0 green: #2E2 gray: #BBB text: #FFF]]
		[[canvas: #FFF red: #F22 yellow: #BA0 green: #0E0 gray: #AAA text: #000]]
		[hex-to-rgb color]
	;; translucent colors; multiple passes of the same rule should be clearly distinguishable
	light: map-each [color [tuple!]] colors [opaque color either dark? [50%][25%]]
		
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
	
	get-rule-offset: function [offsets [hash!] rule [block!] offset [integer!] "age"] [	;@@ need clearer naming than 'offset'
		second any [
			find/same/only/reverse 						;-- adding /skip is too tricky; fuck index magic
				skip offsets offset * 2
				rule
			[0 0]
		]
	]
	
	rule-offset->text-offset: function [charts [hash!] rule [block!] offset [integer!] "block offset"] [
		chart: select/only/same charts rule
		skip chart/1 pick chart offset + 2
	]

	;@@ maybe discard rules that never advanced input? or those that can't advance input (pure code rules)?
	
	;@@ need to use 'changes' block too (only reason why dump has 'age' is to sync changes to parsing)
	;@@ if input is modified, this affects offsets after it, thus text highlighting may shift - need to care for
	
	;; returned: rule profiles consist of couples [age value ...], where 'value' can be:
	;;   integer 'start'   -> absolute input offset at rule entry (basis for following pairs)
	;;   pair    'oldXnew' -> input offset change from old to new, relative to 'start'
	;;   word    'result'  -> 'match or 'fail - end result of the rule (for coloring)
	;; and 'age' is a unique monotonically increasing integer, seen as virtual time
	decode-dump: function [input [series!] events [block!] changes [block!]] [
		if top-level: events/5 [
			named: to hash! scan-rule-names top-level	;-- rules dictionary: name -> rule (not listed are all unnamed)
			repend named ['top-level top-level]
		]
		; ?? named
		; rules:     make hash!  64						;-- registry of all visited rule blocks
		offsets:   make block! (length? events) / 5 * 2 + 1	;-- [rule offset] pairs at each age
		depths:    make map!   64						;-- rule depths: name -> depth (0 = top level, >0 rest)
		starts:    make block! 64						;-- stack of input offsets at each rule's (re)entry
		profiles:  make map!   64						;-- each rule's offsets as ageXoffset pairs: name -> block
		entered:   clear []								;-- [scope depth ...] pairs; depth may change for the same scope
		depth:     -1
		age:       0
		
		unless empty? events [
			;; all profile modification is kept here isolated, otherwise it's messy
			tick: does [
				repend offsets [head rule skip? rule]
				age: age + 1
			]
			get-rule-name: does [
				all [
					found: find/only/same/skip next named rule 2
					found/-1
				]
			]
			get-profile: func [scope] [
				any [
					profiles/:scope
					profiles/:scope: make block! 1024
				]
			]
			get-input-offsets: does [
				inp-offset1: either pair? pair: last profile [pair/2][0]
				inp-offset2: (skip? inpos) - last starts
			]
			after-entering-rule: does [
				repend profile [tick last starts]
			]
			before-leaving-rule: does [
				repend profile [tick pick [match fail] match?]
			]
			after-rule-movement: does [
				;; these events are used to display rule advancement
				repend profile [tick 1x1 * inp-offset: (skip? inpos) - last starts]
			]
			after-input-movement: does [
				repend profile [tick inp-offset1 by inp-offset2]
			]
			
			scope: 'top-level
			while [not tail? events] [					;@@ use for-each when fast
				set [_: inpos: event: match?: rule:] events
				name:    get-rule-name
				profile: get-profile scope
				; if scope = 'top-level [?? [age event inpos match rule]]
				switch event [
					fetch match paren [
						get-input-offsets
						if inp-offset1 <> inp-offset2 [after-input-movement]
						rul-offset1: skip? any [prev-rule: events/-1 []]
						rul-offset2: skip? rule
						if rul-offset1 <> rul-offset2 [after-rule-movement]
					]
					push [
						prev-rule: events/-1
						case [
							not all [								;-- if not within the same rule
								prev-rule
								same? head rule head prev-rule
							][
								; unless find/only/same rules rule [append/only rules rule]	;-- gather all visited rules list
								if name [
									depth: depth + 1
									depths/:name: min-safe depth depths/:name
									append starts skip? inpos
									profile: get-profile scope: name
									after-entering-rule
								]
								reduce/into [scope depth] entered: tail entered
							]
							not same? rule prev-rule [				;-- within the same rule, at different offsets
								rul-offset1: skip? prev-rule
								rul-offset2: skip? rule
								after-rule-movement
							]
						]
					]
					pop [
						get-input-offsets							;-- may happen if popping through this rule
						if inp-offset1 <> inp-offset2 [after-input-movement]
						next-rule: events/10
						case [
							not all [								;-- popping into another rule
								next-rule
								same? head rule head next-rule
							][
								if name [
									before-leaving-rule
									take/last starts
								]
								set [scope: depth:] entered: skip clear entered -2
							]
							not same? rule next-rule [				;-- popping within the same rule, different offset
								rul-offset1: skip? rule
								rul-offset2: skip? next-rule
								after-rule-movement
							]
						]
					]
				]
				events: skip events 5
			]
			
			;; some profiles may have been left open, due to exception/return/etc - consider them failed (e.g.  that's how CSV normally works)
			inp-offset2: 0									;-- closing offset of failed rules is zero
			foreach [name profile] profiles [
				if empty? profile [continue]
				unless word? pair: last profile [
					inp-offset1: either pair? pair: last profile [pair/2][0]
					if inp-offset1 <> 0 [after-input-movement]
					before-leaving-rule
				]
			]
			
		]
		offsets:  make hash! offsets
		;; remove blocks that either aren't rules or were never reached
		remove-each [name rule] named [not depths/:name]
		;; sort maps by depth
		compare:  func [a b] [depths/:b - depths/:a]
		depths:   make map! sort/stable/skip/compare to [] depths   2 2
		named:    make map! sort/stable/skip/compare named          2 :compare
		profiles: make map! sort/stable/skip/compare to [] profiles 2 :compare
		charts:   make hash! map-each [name rule] named [chart-rule rule]
		; ?? age ?? depths ?? starts ?? named print ["profiles:" mold/all/deep profiles]
		
		to map! compose/only [
			max-age:  (age)								;-- >= 1
			charts:   (charts)							;-- (hash) charts of all rules: [rule-block chart-block] pairs
			named:    (named)							;-- (map)  only named rules:    name -> block
			depths:   (depths)							;-- (map)  min nesting depths:  name -> integer
			profiles: (profiles)						;-- (map)  rule profiles:       name -> block
			offsets:  (offsets)							;-- (hash) offsets per age:     [rule offset] pairs
		]
	]
	
	locate-offset: function [profile [block!] offset [integer!]] [
		if empty? profile [return profile]
		n: half length? profile: head profile
		set [i1: f1: i2: f2:] search/for i: 1 n [profile/(i * 2 - 1)] offset + 1
		i: i2 + either f2 <= offset [1][0]
		skip profile i - 1 * 2
	]
	#assert [
		0  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 0
		2  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 1
		4  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 2
		6  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 3
		8  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 4
		8  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 5
		8  = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 9
		10 = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 10
		12 = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 11
		12 = skip? locate-offset [1 a 2 b 3 c 4 d 10 e 11 f] 100
	]
	
	;; age should be treated like index - actual value, actual change
	;; offsets though are zero-based and are between the ages
	replay: function [profile [block!] (head? profile) flags [block!] from-offset [integer!] to-offset [integer!]] [
		step: 2 * sign: sign? to-offset - from-offset
		ivalue: pick [-1 2] back?: sign = -1
		at-from-offset: locate-offset profile from-offset
		at-to-offset:   locate-offset profile to-offset
		flag: skip tail flags -3 
		pos:  at-from-offset
		while [not same? pos at-to-offset] either back? [[
			switch type?/word value: pos/:ivalue [
				pair! [flag/1/2: value/1]					;-- progress update
				integer! [flag: skip clear flag -3]			;-- region entry
				word! [flag/3: light/yellow]				;-- region close = coloring
			]
			pos: skip pos step
		]] [[
			switch type?/word value: pos/:ivalue [
				pair! [										;-- progress update
					flag/1/2: 
						; value/2
						either value/2 = 0 [flag/1/2][value/2]	;-- do not rewind on failures, let color stay ;@@ better way?
				]
				integer! [									;-- region entry
					reduce/into [(value + 1 by 0) 'backdrop light/yellow] flag: tail flags
				]
				word! [										;-- region close = coloring
					flag/3: either value = 'match [light/green][light/red]
				]
			]
			pos: skip pos step
		]]
		flags
	]
	
	key-step: 128										;@@ what should be optimal key step?
	get-flags: function [frames [map!] name [word!] profile [block!] offset [integer!]] [
		nearest: round/to offset key-step
		keyframes: any [
			frames/:name
			frames/:name: make [] 32
		]
		unless flags: pick keyframes nearest / key-step + 1 [
			if empty? keyframes [append/only keyframes make [] 24]
			last-offset: key-step * (-1 + length? keyframes)
			flags: last keyframes
			while [last-offset < nearest] [
				append/only keyframes
					flags: replay profile copy flags last-offset last-offset: last-offset + key-step
			]
		]
		replay profile copy flags nearest offset
	]
	
	color-input: function [input [object!] frames [map!] name [word!] profile [block!] old-offset [integer! none!] offset [integer!]] [
		input/flags: either all [
			old-offset																	;-- old offset known
			(round/to old-offset key-step) = (round/to offset key-step)					;-- closest keyframe for both is the same
			(round/floor/to old-offset key-step) = (round/floor/to offset key-step)		;-- not jumping over the keyframe (else inefficient)
		][
			;; replaying directly from current flags is faster than from the keyframe
			;@@ TODO: automatically create keyframes when they are crossed? it makes sense for forward crossing only
			do-atomic [replay profile input/flags old-offset offset]
		][
			get-flags frames name profile offset
		]
	]
	
	color-rule: function [text [object!] ('text = class? text) charts [hash!] rule [block!] offsets [hash!] offset [integer!]] [
		rule-offset: get-rule-offset offsets rule offset
		text-pos: rule-offset->text-offset charts rule rule-offset
		done: skip? text-pos
		unless all [
			text/text =? head text-pos
			text/flags/1
			text/flags/1/2 = done
		][
			text/text: head text-pos
			text/flags: compose [(1 by done) backdrop (light/green)]
		]
	]
	
	render-profile: function [profile [block!]] [
		append failures:  clear [] [line 0x0]
		append successes: clear [] [line 0x0]
		run:  clear []
		peak: 1
		foreach [age value] profile [
			switch type?/word value [
				pair! [
					peak: max peak value/2
					append append run (age by value/1) (age by last-rise: value/2)
				]
				integer! [
					append run (age by last-rise: 0)
				]
				word! [
					target: either value = 'match [successes][failures]
					append append append target run (age by last-rise) (age by 0)
					clear run
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

	monofont: make font! [name: system/view/fonts/fixed]
							
	;@@ layout: grid-view with 2 vlists (1 pinned), so rule names are always visible
	;@@ for that grid-view will have to support row selection, like in list-view
	visualize-parse: function [file [file!]] [
		set [input: events: changes:] data: load/as file 'redbin
		assert [string? input]
		; ?? input ?? events ?? changes print ["events:" mold/all events]
		info: decode-dump input events changes
		set [max-age: charts: named: depths: profiles: offsets:] values-of info
		rea: reactor [age: 0]
		keyframes: make map! length? named
		; ?? profiles probe keys-of named ?? depths
		profile-plots: map-each [name block] profiles [
			first lay-out-vids compose/deep/only [
				hlist tight with [name: (to lit-word! name) profile: (block) type: 'item] [
					text 100 (form name)
					column left tight [
						rule-profile plot= (render-profile block) max-age= max-age react [age: rea/age]
							on-down [
								move-marker space path
								start-drag path
							]
							on-up [stop-drag]
							on-over [if dragging? [move-marker space path]]
						box left margin= 2x1 color= colors/canvas [
							text font= monofont color= colors/text text= mold/flat named/:name
						]
					]
				]
			]
		]
		move-marker: function [space [object!] path [block!]] [
			timeline/offset: clip 0% 100% to percent! path/2/x / space/size/x
		]
		last-offset: none
		last-name: none
		refresh-progress: function [offset [percent!] index [integer! none!]] [
			rea/age: to integer! offset * max-age
			if index [
				name: profile-plots/:index/name
				if name <> last-name [set 'last-offset none]
				color-input text-view keyframes name profiles/:name last-offset rea/age
				for-each [/i rule-name _] profiles [ 
					rule-text: profile-plots/:i/content/2/content/2/content
					color-rule rule-text charts named/:rule-name offsets rea/age
				]
				set 'last-offset rea/age
				set 'last-name name
			]
		]
		screen: system/view/screens/1
		view/no-wait/tight/options reshape [
			title !(`"ParSEE - (file)"`) 
			host [
				column [
					text bold "Parsed input:"
					cell color= colors/canvas [scrollable [
						text-view: text !(input) limits= 100x100 .. none
							color= colors/text font= monofont
					]]
					; <-> 0x10							;@@ doesn't work when compiled
					stretch 0x10
					text bold "Timeline:"
					timeline: slider 100% focus step= 100% / max 1 max-age
					; <-> 0x10							;@@ doesn't work when compiled
					stretch 0x10
					text bold "Applied rules:"
					profiles-view: list-view selectable tight source= !(profile-plots) selected= [1] cursor= 1
						react [refresh-progress timeline/offset profiles-view/cursor]
						on-key-down [
							switch event/key [
								left  [timeline/offset: clip 0% 100% timeline/offset - (1 / max-age) stop]
								right [timeline/offset: clip 0% 100% timeline/offset + (1 / max-age) stop]
							]
						]
				]
			] react [face/size: face/parent/size - 20]
		] [offset: -8x0 flags: 'resize size: screen/size - 0x60]
		; dump-tree
		prof/reset
		do-events
		prof/show
	]
	
	
	
	context [
		~: self
		
		draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
			space/size: space/max-age / space/zoom . 30
			compose/only/deep [
				matrix [1 0 0 -1 0 (space/size/y)] 
				line-width 0.5 fill-pen (colors/canvas) box 0x0 (space/size)
				scale 1.0 (space/size/y * 1.0) (space/plot)
				line-width 1 pen (colors/text) translate (space/age by 0) [line 0x0 (0 by space/size/y)]
			]
		]
		
		declare-template 'rule-profile/box [
			plot:    [1]	#type [block!] :invalidates
			zoom:    1.0	#type [float! percent!] :invalidates
			age:     0		#type [integer!] :invalidates
			max-age: 0		#type [integer!] :invalidates
			draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
		]
	]
	
	set 'parsee function [
		"Parsing flow visual analysis tool"
		dump-file [file!] "Path to a .pdump file to analyze"
	][
		visualize-parse dump-file
	]

	; visualize-parse %"20231010-201839-055.pdump"
	; visualize-parse %"20231016-182712-875.pdump"
	; visualize-parse %"20231016-200151-136.pdump"
	; visualize-parse %"20231021-193224-947.pdump"
	
];context with spaces/ctx expand-directives [

do [cli/process-into ParSEE]
;@@ remember/restore window offset/size