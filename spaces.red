Red [
	title:  "Red Spaces main include file"
	author: @hiiamboris
	; needs:  view										;@@ doesn't work, has to be in the main script
]

;; check to prevent double inclusion (esp. when running tests from spaces-console)
#if not value? 'spaces-included? [
set 'spaces-included? true 								;-- must be done in the code, not in the preprocessor, bcuz inclusion is 2-stage!  

;@@ I only partially understand why/how all this magic works
;@@ a huge lot of bugs is fixed by using %include-once
;@@ since it's a macro, it has to be #included, not `do`ne (`do` forgets macros)
;@@ for some reason, it won't affect #includes of this very file,
;@@ so a second preprocessor's pass is required for #includes to be handled by %include-once
; #do [verbose-inclusion?: yes]							;-- enable to dump filenames

;; >>>>>>>>>> %../common/include-once.red >>>>>>>>>

;@@ TODO: instead of printing, use `try/all` and report the file where the error happens

#if all [
	not object? :rebol									;-- do nothing when compiling
	not block? :included-scripts						;-- do not reinclude itself (does not shield from double evaluation though)
][
	; #do [verbose-inclusion?: yes]						;-- comment this out to disable file names dump
	#do [	
		system/words/included-scripts: reduce [			;@@ no /extern support - #5386
			append what-dir %include-once.red			;-- add itself to avoid double evaluation
		]
	]
	
	;; since it's now running in Red, we don't need R2 compatibility
	#macro [#include] function [[manual] s e] [
		indent: ""
		unless file? :s/2 [
			do make error! rejoin [
				"#include expects a file argument, not " mold/part :s/2 100
			]
		]
		
		file: clean-path to-red-file :s/2				;-- use absolute paths to ensure uniqueness
		if find included-scripts file [					;-- if already included, skip it
			return remove/part s 2
		]
		if verb?: true = :verbose-inclusion? [
			print rejoin ["including " mold file]
		]
		data: try [load file]
		if error? data [								;-- on loading error, report & skip
			print data
			return remove/part s 2
		]
		
		old-path: what-dir
		set [path: name:] split-path file
		if 'Red == :data/1 [							;-- skip the header in case Red word is defined to smth else
			header: construct data/2
			if provides: select header 'provides [append included-scripts provides]
			if depends:  select header 'depends [
				missing: exclude compose [(depends)] included-scripts
				unless empty? missing [
					sfx: either single? missing ["y"]["ies"]
					print rejoin ["^/*** WARNING: File " mold name " requires '" mold/only missing "' dependenc" sfx "^/"]
				]
			]
			data: skip data 2
		]
		
		prelude:  compose [change-dir (path)]			;-- evaluate inside script's path
		postlude: compose [change-dir (old-path)]		;-- restore path after evaluation (unless errors out or halts..)
		if verb? [
			prelude: compose/deep [
				print rejoin [append (indent) " " "processing " (mold file)]
				(prelude)
			]
			postlude: compose/deep [
				(postlude)
				print rejoin [" " remove (indent) "finished " (mold file)]
			]
		]
		
		;@@ dilemma here is that we want to include file as is, exposing all set-words into the context
		;@@ but on the other hand we want to be able to assign the result to a word, and can't have both :(
		change/part s compose/deep [					;-- insert contents
			(to issue! 'do) [change-dir (path)]			;-- preprocess inside script's path
			(prelude)
			(data)
			(postlude)
			(to issue! 'do) [change-dir (old-path)]
		] 2
		; print ["===" file "expands into:^/" mold s]
		append included-scripts file
		s												;-- continue processing from contents itself
	]
]

;; <<<<<<<<<< %../common/include-once.red <<<<<<<<<
					;-- the rest can use the improved include
#do [
	;; when compiling, this needs `inline` to get the `-t os` argument!
	linux?: either Rebol								;-- to unify compiled & interpreted workaround logic
		[system/version/4 = 4]
		[system/platform = 'Linux]
]

											;-- do not expand the rest using the default #include
do/expand [
	
#do [if block? :included-scripts [append included-scripts [without-gc]]]

;; >>>>>>>>>> %../common/without-gc.red >>>>>>>>>


without-GC: function [
	"Evaluate CODE with GC temporarily turned off"
	code [block!]
][
	if state: system/state/GC/active? [recycle/off]
	also do code  if state [recycle/on]
]

;; <<<<<<<<<< %../common/without-gc.red <<<<<<<<<

	without-GC [										;-- speeds up startup time by 5-20ms
		
#do [if block? :included-scripts [append included-scripts [debug]]]

;; >>>>>>>>>> %../common/debug.red >>>>>>>>>


#macro [#debug 'on       ] func [s e] [*debug?*: on  []]
#macro [#debug 'off      ] func [s e] [*debug?*: off []]
#macro [#debug 'set word!] func [s e] [
	either block? get/any '*debug?* [
		append *debug?* s/3
	][
		*debug?*: reduce [s/3]
	]
	[]
]
; #macro [#debug not ['on | 'off | 'set] opt word! block!] func [[manual] s e /local code] [	;-- not R2-compatible!
#macro [#debug [['on | 'off | 'set] (c: [end skip]) | (c: [])] c opt word! block!] func [[manual] s e /local code] [
	; if either block? s/2 [:*debug?* <> off][attempt [find *debug?* s/2]] [	;-- not R2-compatible
	if either block? s/2 [all [value? '*debug?*  off <> get/any '*debug?*]][attempt [find *debug?* s/2]] [
		code: e/-1
	]
	remove/part s e
	if code [insert s code]
	s
]

; #debug on		;@@ this prevents setting it to a word value because of double-inclusion #4422
#do [unless value? '*debug?* [*debug?*: on]]			;-- only enable it for the first time

;; <<<<<<<<<< %../common/debug.red <<<<<<<<<
					;-- need #debug macro so it can be process rest of this file
		
		#debug off										;-- turn off type checking and general (unspecialized) debug logs
		; #debug set draw								;-- turn on to see what space produces draw errors
		; #debug set profile							;-- turn on to see rendering and other times
		; #debug set changes							;-- turn on to see value changes and invalidation
		; #debug set cache 								;-- turn on to see what gets cached (can be a lot of output)
		; #debug set sizing 							;-- turn on to see how spaces adapt to their canvas sizes
		; #debug set slides 							;-- turn on to see window slide events
		; #debug set focus								;-- turn on to see focus changes and errors
		; #debug set events								;-- turn on to see what events get dispatched by hosts
		; #debug set popups								;-- turn on to see popups show/hide events
		; #debug set timer								;-- turn on to see timer events
		; #debug set styles								;-- turn on to see which styles get applied
		; #debug set paragraph							;-- turn on to see words inside paragraph layout
		; #debug set clipboard							;-- turn on to see clipboard writes and 'format' result
		; #debug set grid-view
		; #debug set list-view
		
		
#do [if block? :included-scripts [append included-scripts [assert]]]

;; >>>>>>>>>> %../common/assert.red >>>>>>>>>


;@@ TODO: eventually, `assert` scope should isolate leaked words (what's currently done with #hide), but currently that would incur an unacceptable peformance hit for cases where assertions are inlined in function body


#macro [#assert 'on]  func [s e] [assertions: on  []]
#macro [#assert 'off] func [s e] [assertions: off []]
#do [unless value? 'assertions [assertions: on]]		;-- only reset it on first include

#macro [#assert block!] func [[manual] s e /local nl] [	;-- allow macros within assert block!
	nl: new-line? s										;-- preserve newline marker state before #assert
	either assertions [change s 'assert][remove/part s e]
	new-line s nl
]

assert: none
context [
	next-newline?: function [b [block!]] [
		forall b [if new-line? b [return b]]
		tail b
	]

	set 'assert function [
		[no-trace]
		"Evaluate a set of test expressions, showing a backtrace if any of them fail"
		tests [block!] "Delimited by new-line, optionally followed by an error message"
		/local result
	][
		while [not tail? tests] [
			set/any 'result do/next bgn: tests 'tests
			all [
				:result
				any [
					new-line? tests
					tail? tests
					all [string? :tests/1 new-line? next tests]
				]
				continue								;-- total success, skip to the next test
			]

			end: next-newline? tests
			if 0 <> left: offset? tests end [			;-- check assertion alignment
				if any [
					left > 1							;-- more than one free token before the newline
					not string? :tests/1				;-- not a message between code and newline
				][
					do make error! form reduce [
						"Assertion is not new-line-aligned at:"
						mold/part bgn 100				;-- mold the original code
					]
				]
				tests: end								;-- skip the message
			]

			unless :result [							;-- test fails, need to repeat it step by step
				msg:     either left = 1 [first end: back end][""]
				print ["ASSERTION FAILED!" msg]
				expr:    copy/part bgn end
				full:    any [attempt [to integer! system/console/size/x] 80]
				half:    to integer! full - 22 / 2		;-- 22 is 1 + length? "  Check  failed with "
				result': mold/flat/part :result half
				expr':   mold/flat/part :expr   half
				print ["  Check" expr' "failed with" result' "^/  Reduction log:"]
				trace/all expr
				print find append form try [do make error! ""] "^/" "* Stack:"
				;; no error thrown, to run other assertions
			]
		]
		exit											;-- no return value
	]
]

; #include %hide-macro.red
; #hide [#assert [
	; a: 123
	; not none? find/only [1 [1] 1] [1]
	; 1 = 1
	; 100
	; 1 = 2
	; ;3 = 2 4
	; 2 = (2 + 1) "Message"
	; 3 + 0 = 3

	; 2													;-- valid multiline assertion
	; -
	; 1
	; =
	; 1
	
	; #assert [1 + 1 > 3]									;-- reentry should be supported, as some assertions use funcs with assertions
; ]]

;; <<<<<<<<<< %../common/assert.red <<<<<<<<<

		
		
#do [if block? :included-scripts [append included-scripts [once default maybe global export quietly anonymize pretending]]]

;; >>>>>>>>>> %../common/setters.red >>>>>>>>>



; #include %assert.red


once: func [
	"Set value of WORD to VALUE only if it's unset"
	'word   [set-word! set-path!]
	value   [default!] "New value"
	return: [default!] "VALUE is always returned"
][
	if unset? get/any word [set word :value]
	:value
]

default: func [
	"If WORD's value is none, set it to VALUE"
	'word   [set-word! set-path!]
	value   [default!] "New value"
	return: [default!] "VALUE is always returned"
][
	switch get/any word [#(none) [set word :value]]		;-- 20% faster than `none =?` which is 5% faster than `none =` and 2x faster than `none?`
	:value
]

maybe: func [
	"If WORDS's value is not strictly equal to VALUE, set it to VALUE (for use in reactivity)"
	'word   [set-word! set-path!]
	value   [default!] "New value"
	/same "Use =? as comparator instead of =="
	return: [default!] "VALUE is always returned"
][
	if either same [:value =? get/any word][:value == get/any word] [return :value]
	set word :value
]

global: function [
	"Export single word into the global namespace"
	'word   [set-word! set-path!]
	value   [default!]
	return: [default!] "VALUE is always returned"
][
	alias: either set-path? word [last word][word]
	set bind alias system/words set word :value
]

export: function [
	"Export a set of bound words into the global namespace"
	words [block! object!]
][
	if object? words [words: words-of words]
	foreach w words [set/any bind w system/words get/any :w]
]

anonymize: function [
	"Return WORD bound in an anonymous context and set to VALUE"
	word    [any-word!]
	value   [any-type!]
	return: [any-word!]
][
	o: construct change [] to set-word! word
	set/any/only o :value
	bind word o
]

pretending: function [
	"Evaluate CODE with WORD set to VALUE, then restore the old value"
	word [any-word! any-path!] value [default!] code [block!]
	/method method' [word!] "Preferred method: [trace (default) trap (faster) do (fastest, unsafe)]"
][
	old: get word
	set word :value
	following/:method code [set word :old] method'
]


;-- there's a lot of ways this function can be written carelessly...



;; macro allows to avoid a lot of runtime overhead, thus allows using `quietly` with paths in critical code
;@@ unfortunate limitation: only applicable to objects, set-quiet cannot work with /x /y of a pair or components of time/date
#macro [p: 'quietly :p word! [set-path! | set-word!]] func [s e /local path] [
	either set-word? s/2 [
		compose [set-quiet quote (s/2)]					;-- set-quiet returns the value after #5146
	][
		path: to block! s/2								;-- required for R2 that can't copy/part paths!
		token: switch type?/word token: last path [
			word! [to lit-word! token]
			get-word! paren! [token]
		]
		compose [set-quiet in (to path! copy/part path back tail path) (:token)]	
	]	
]

;; <<<<<<<<<< %../common/setters.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [with]]]

;; >>>>>>>>>> %../common/with.red >>>>>>>>>



; #include %hide-macro.red
; #include %assert.red


with: func [
	"Bind CODE to a given context CTX"
	ctx [any-object! function! any-word! block!]
		"Block [x: ...] is converted into a context, [x 'x ...] is used as a list of contexts"
	code [block!]
][
	case [
		not block? :ctx  [bind code :ctx]
		set-word? :ctx/1 [bind code context ctx]
		'otherwise       [foreach ctx ctx [bind code do :ctx]  code]		;-- `do` decays lit-words and evals words, but doesn't allow expressions
		; 'otherwise       [while [not tail? ctx] [bind code do/next ctx 'ctx]  code]		;-- allows expressions
		; 'otherwise       [foreach ctx reduce ctx [bind code :ctx]  code]	;-- `reduce` is an extra allocation
	]
]

#hide []

;; <<<<<<<<<< %../common/with.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [trace-deep]]]

;; >>>>>>>>>> %../common/trace-deep.red >>>>>>>>>



trace-deep: none
context [
	eval-types: make typeset! reduce [		;-- value types that should be traced
		paren!		;-- recurse into it

		; block!	-- never known if it's data or code argument - can't recurse into it
		; set-word!	-- ignore it, as it's previous value is not used
		; set-path!	-- ditto

		word!		;-- function call or value acquisition - we wanna know the value
		path!		;-- ditto

		get-word!	;-- value acquisition - wanna know it
		get-path!	;-- ditto

		native!		;-- literal functions should be evaluated but no need to display their source; only result
		action!		;-- ditto
		routine!	;-- ditto
		op!			;-- ditto
		function!	;-- ditto
	]

	;; this is used to prevent double evaluation of arguments and their results
	;@@ TODO: remove this once we have `apply` native
	wrap: func [x [any-type!]] [
		if any [										;-- quote non-final values (that do not evaluate to themselves)
			any-word? :x
			any-path? :x
			any-function? :x
			paren? :x
		][
			return as paren! reduce ['quote :x]
		]
		:x												;-- other values return as is
	]

	;; reduces each expression in a chain
	rewrite: func [code inspect preview] [
		code: copy code									;-- will be modified in place; but /deep isn't applicable as we want side effects
		while [not empty? code] [code: rewrite-next code :inspect :preview]
		head code										;-- needed by `trace-deep`
	]
	
	;; fully reduces a single value, triggering a callback
	rewrite-atom: function [code inspect preview] [
		if find eval-types type: type? :code/1 [
			to-eval:   copy/part      code 1			;-- have to separate it from the rest, to stop ops from being evaluated
			to-report: copy/deep/part code 1			;-- report an unchanged (by evaluation) expr to `inspect` (here: can be a paren with blocks inside)
			change/only code
				either type == paren! [
					as paren! rewrite as block! code/1 :inspect :preview
				][
					preview to-report
					wrap inspect to-report do to-eval
				]
		]
	]

	;; rewrites an operator application, e.g. `1 + f x`
	;; makes a deep copy of each code part in case a value gets modified by the code
	rewrite-op-chain: function [code inspect preview] [
		until [
			rewrite-next/no-op skip code 2 :inspect :preview	;-- reduce the right value to a final, but not any subsequent ops
			to-eval:   copy/part      code 3			;-- have to separate it from the rest, to stop ops from being evaluated
			to-report: copy/deep/part code 3			;-- report an unchanged (by evaluation) expr to `inspect`
			preview to-report
			change/part/only code wrap inspect to-report do to-eval 3
			not all [									;-- repeat until the whole chain is reduced
				word? :code/2
				op! = type? get/any :code/2
			]
		]
	]

	;; deeply reduces a single expression, recursing into subexpressions
	rewrite-next: function [code inspect preview /no-op /local end' r] [
		;; determine expression bounds & skip set-words/set-paths - not interested in them
		start: code
		while [any [set-path? :start/1 set-word? :start/1]] [start: next start]		;@@ optimally this needs `find` to support typesets
		if empty? start [do make error! rejoin ["Unfinished expression: " mold/flat skip start -10]]
		end: preprocessor/fetch-next start
		no-op: all [no-op  start =? code]				;-- reset no-op flag if we encounter set-words/set-paths, as those ops form a new chain

		set/any [v1: v2:] start							;-- analyze first 2 values
		rewrite?: yes									;-- `yes` to rewrite the current expression and call a callback
		case [											;-- priority order: op (v2), any-func (v1), everything else (v1)
			all [											;-- operator - recurse into it's right part
				word? :v2
				op! = type? get/any v2
			][
				rewrite-atom start :inspect :preview		;-- rewrite the left part
				if no-op [return next start]				;-- don't go past the op if we aren't allowed
				rewrite-op-chain start :inspect :preview	;-- rewrite the whole chain of operators
				rewrite?: no								;-- final value; but still may need to reduce set-words/set-ops
			]

			all [										;-- a function call - recurse into it
				any [
					if word? :v1 [fpath: v1]
					all [									;-- get the path in objects/blocks.. without refinements
						path? :v1
						also set/any [fpath: _:] preprocessor/value-path? v1
							if single? fpath [fpath: :fpath/1]	;-- turn single path into word
					]
				]
				find [native! action! function! routine!] type?/word get/any fpath
			][
				v2: get fpath
				arity: either path? v1 [
					preprocessor/func-arity?/with spec-of :v2 v1
				][	preprocessor/func-arity?      spec-of :v2
				]
				end: next start
				loop arity [end: rewrite-next end :inspect :preview]	;-- rewrite all arguments before the call, end points past the last arg
			]

			paren? :v1 [								;-- recurse into paren; after that still `do` it as a whole
				change/only start as paren! rewrite as block! v1 :inspect :preview
			]

			'else [										;-- other cases
				rewrite-atom start :inspect :preview
				rewrite?: no								;-- final value
			]
		]

		if any [
			rewrite?									;-- a function call or a paren to reduce
			not start =? code							;-- or there are set-words/set-paths, so we have to actually set them
		][
			preview copy/deep/part code end
			set/any 'r either rewrite? [
				to-report: copy/deep/part code end
				inspect to-report do/next code 'end'
			][
				do/next code 'end'
			]
			;; should not matter - do (copy start end) or do/next, if preprocessor is correct
			unless end =? end' [
				do make error! rejoin [
					"Miscalculated expression bounds detected at "
					mold/flat copy/part code end
				]
			]
			change/part/only code wrap :r end
		]
		return next code
	]

	set 'trace-deep function [
		"Deeply trace a set of expressions"				;@@ TODO: remove `quote` once apply is available
		inspect	[function!] "func [expr [block!] result [any-type!]]"
		code	[block!]	"If empty, still evaluated once"
		/preview
			pfunc [function! none!] "func [expr [block!]] - called before evaluation"
	][
		do rewrite code :inspect :pfunc					;-- `do` will process `quote`s and return the last result
	]
]

; inspect: func [e [block!] r [any-type!]] [print [pad mold/part/flat/only e 20 20 " => " mold/part/flat :r 40] :r]

; #include %assert.red			;@@ assert uses this file; cyclic inclusion = crash

; 	() = trace-deep :inspect []
; #assert [() = trace-deep :inspect [()]]
; #assert [() = trace-deep :inspect [1 ()]]
; #assert [3  = trace-deep :inspect [1 + 2]]
; #assert [9  = trace-deep :inspect [1 + 2 * 3]]
; #assert [4  = trace-deep :inspect [x: y: 2 x + y]]
; #assert [20 = trace-deep :inspect [f: func [x] [does [10]] g: f 1 g * 2]]
; #assert [20 = trace-deep :inspect [f: func [x] [does [10]] (g: f (1)) ((g) * 2)]]


#hide []
;; <<<<<<<<<< %../common/trace-deep.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [expect]]]

;; >>>>>>>>>> %../common/expect.red >>>>>>>>>



; #include %trace-deep.red

expect: function [
	"Test a condition, showing full backtrace when it fails; return true/false"
	expr [block!] "Falsey results: false, none and unset!"
	/buffer buf [string!] "Print into the provided buffer rather than the console"
	/local r
][
	orig: copy/deep expr								;-- preserve the original code in case it changes during execution
	red-log: make block! 20								;-- accumulate the reduction log here
	err: try/all [										;-- try/all as we don't want any returns/breaks inside `expect`
		set/any 'r trace-deep
			func [expr [block!] rslt [any-type!]] [
				repend red-log [expr :rslt]
				:rslt
			]
			expr
		'ok
	]

	if all [value? 'r  :r] [							;-- `value?` if not unset, `:r` if not false/none (or error=none)
		return yes
	]

	;; now that we have a failure, let's report
	buf: any [buf make string! 200]
	append buf form reduce [
		"ERROR:" mold/flat/part expr 100
		either error? err [
			reduce ["errored out with^/" err]
		][	reduce ["check failed with" mold/flat/part :r 100]
		]
		"^/  Reduction log:^/"
	]
	foreach [expr rslt] red-log [
		append buf form reduce [
			"   " pad mold/part/flat/only expr 30 30
			"=>" mold/part/flat :rslt 50 "^/"
		]
	]
	unless buffer [prin buf]
	no
]

;; <<<<<<<<<< %../common/expect.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [trap pcatch fcatch following]]]

;; >>>>>>>>>> %../common/catchers.red >>>>>>>>>


; #include %hide-macro.red
; #include %assert.red

thrown: pcatch: fcatch: trap: following: none
context [
	with-thrown: func [code [block!] /thrown] [			;-- needed to be able to get thrown from both *catch funcs
		do code
	]

	;-- this design allows to avoid runtime binding of filters
	;@@ should it be just :thrown or attempt [:thrown] (to avoid context not available error, but slower)?
	set 'thrown func ["Value of the last THROW from FCATCH or PCATCH"] bind [:thrown] :with-thrown

	set 'pcatch function [
		"Eval CODE and forward thrown value into CASES as 'THROWN'"
		cases [block!] "CASE block to evaluate after throw (normally not evaluated)"
		code  [block!] "Code to evaluate"
	] bind [
		with-thrown [
			set/any 'thrown catch [return do code]
			;-- the rest mimicks `case append cases [true [throw thrown]]` behavior but without allocations
			forall cases [if do/next cases 'cases [break]]	;-- will reset cases to head if no conditions succeed
			if head? cases [throw :thrown]					;-- outside of `catch` for `throw thrown` to work
			do cases/1										;-- evaluates the block after true condition
		]
	] :with-thrown
	;-- bind above binds `thrown` and `code` but latter is rebound on func construction
	;-- as a bonus, `thrown` points to a value, not to a function, so a bit faster

	set 'fcatch function [
		"Eval CODE and catch a throw from it when FILTER returns a truthy value"
		filter [block!] "Filter block with word THROWN set to the thrown value"
		code   [block!] "Code to evaluate"
		/handler        "Specify a handler to be called on successful catch"
			on-throw [block!] "Has word THROWN set to the thrown value"
	] bind [
		with-thrown [
			set/any 'thrown catch [return do code]
			unless do filter [throw :thrown]
			either handler [do on-throw][:thrown]
		]
	] :with-thrown

	set 'trap function [					;-- backward-compatible with native try, but traps return & exit, so can't override
		"Try to DO a block and return its value or an error"
		code [block!]
		/all   "Catch also BREAK, CONTINUE, RETURN, EXIT and THROW exceptions"
		/keep  "Capture and save the call stack in the error object"
		/catch "If provided, called upon exception and handler's value is returned"
			handler [block! function!] "func [error][] or block that uses THROWN"
			;@@ maybe also none! to mark a default handler that just prints the error?
		/local result
	] bind [
		with-thrown [
			plan: [set/any 'result do code  'ok]
			set 'thrown try/:all/:keep plan				;-- returns 'ok or error object
			case [
				thrown == 'ok   [:result]
				block? :handler [do handler]
				'else           [handler thrown]		;-- if no handler is provided - this returns the error
			]
		]
	] :with-thrown
	
	set 'following function [
		"Guarantee evaluation of CLEANUP after leaving CODE"
		code    [block!] "Code that can use break, continue, throw"
		cleanup [block!] "Finalization code"
		/method method' [word!] "Preferred method: [trace (default) trap (faster) do (fastest, unsafe)]"
	][
		switch/default method' [
			trap [
				;; trap doesn't slow down the code and can be reentrant, but cannot pass 'break', 'continue', 'throw' 
				also trap/all/keep/catch code [do cleanup do thrown]
					 do cleanup
			]
			do [
				;; this version is only useful if underlying code handles exceptions already
				also do code
					 do cleanup
			]
		][
			;@@ of course this traps `return` because of #4416; and unfortunately it's not reentrant!
			do/trace code :cleaning-tracer
		]
	]
	cleaning-tracer: func [[no-trace]] bind [[end] do cleanup] :following	;-- [end] filter minimizes interpreted slowdown
]


#hide []

{
	;-- this version is simpler but requires explicit `true [throw thrown]` to rethrow values that fail all case tests
	;-- and that I consider a bad thing

	set 'pcatch function [
		"Eval CODE and forward thrown value into CASES as 'THROWN'"
		cases [block!] "CASE block to evaluate after throw (normally not evaluated)"
		code  [block!] "Code to evaluate"
	] bind [
		with-thrown [
			set/any 'thrown catch [return do code]
			case cases									;-- case is outside of catch for `throw thrown` to work
		]
	] :with-thrown
}

;; <<<<<<<<<< %../common/catchers.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [composite]]]

;; >>>>>>>>>> %../common/composite.red >>>>>>>>>



; #include %assert.red
; #include %with.red			;-- used by composite func to bind exprs
; #include %catchers.red		;-- used by composite func to trap errors


composite: none
context [
	non-paren: charset [not #"("]

	trap-error: function [on-err [function! string!] :code [paren!]] [
		trap/catch
			as [] code
			pick [ [on-err thrown] [on-err] ] function? :on-err
	]

	set 'composite function [
		"Return STR with parenthesized expressions evaluated and formed"
		ctx [block!] "Bind expressions to CTX - in any format accepted by WITH function"
		str [any-string!] "String to interpolate"
		/trap "Trap evaluation errors and insert text instead"	;-- not load errors!
			on-err [function! string!] "string or function [error [error!]]"
	][
		s: as string! str
		b: with ctx parse s [collect [
			keep ("")									;-- ensures the output of rejoin is string, not block
			any [
				keep copy some non-paren				;-- text part
			|	keep [#"(" ahead #"\"] skip				;-- escaped opening paren
			|	s: (set [v: e:] transcode/next s) :e	;-- paren expression
				keep (:v)
			]
		]]

		if trap [										;-- each result has to be evaluated separately
			forall b [
				if paren? b/1 [b: insert b [trap-error :on-err]]
			]
			;@@ use map-each when it becomes native
			; b: map-each/eval [p [paren!]] b [['trap-error quote :on-err p]]
		]
		as str rejoin b
		; as str rejoin expand-directives b		-- expansion disabled by design for performance reasons
	]
]


;; has to be both Red & R2-compatible
;; any-string! for composing files, urls, tags
;; load errors are reported at expand time by design
#macro [#composite any-string! | '` any-string! '`] func [[manual] ss ee /local r e s type load-expr wrap keep] [
	set/any 'error try [								;-- display errors rather than cryptic "error in macro!"
		s: ss/2
		r: copy []
		type: type? s
		s: to string! s									;-- use "string": load %file/url:// does something else entirely, <tags> get appended with <>

		;; loads "(expression)..and leaves the rest untouched"
		load-expr: has [rest val] [						;-- s should be at "("
			rest: s
			either rebol
				[ set [val rest] load/next rest ]
				[ val: load/next rest 'rest ]
			e: rest										;-- update the end-position
			val
		]

		;; removes unnecesary parens in obvious cases (to win some runtime performance)
		;; 2 or more tokens should remain parenthesized, so that only the last value is rejoin-ed
		;; forbidden _loadable_ types should also remain parenthesized:
		;;   - word/path (can be a function)
		;;   - set-word/set-path (would eat strings otherwise)
		;@@ TODO: to be extended once we're able to load functions/natives/actions/ops/unsets
		wrap: func [blk] [					
			all [								
				1 = length? blk
				not find [word! path! set-word! set-path!] type?/word first blk
				return first blk
			]
			to paren! blk
		]

		;; filter out empty strings for less runtime load (except for the 1st string - it determines result type)
		keep: func [x][
			if any [
				empty? r
				not any-string? x
				not empty? x
			][
				if empty? r [x: to type x]				;-- make rejoin's result of the same type as the template
				append/only r x
			]
		]

		marker: to char! 40								;@@ = #"(": workaround for #4534
		do compose [
			(pick [parse/all parse] object? rebol) s [
				any [
					s: to marker e: (keep copy/part s e)
					[
						"(\" (append last r marker)
					|	s: (keep wrap load-expr) :e
					]
				]
				s: to end (keep copy s)
			]
		]
		;; change/part is different between red & R2, so: remove+insert
		remove/part ss ee
		insert ss reduce ['rejoin r]
		return next ss									;-- expand block further but not rejoin
	]
	print ["***** ERROR in #COMPOSITE *****^/" :error]
	ee													;-- don't expand failed macro anymore - or will deadlock
]







;-- -- -- -- -- -- -- -- -- -- -- -- -- -- TESTS -- -- -- -- -- -- -- -- -- -- -- -- -- --








; #assert [			;-- this is unloadable because of tag limitations
; 	[#composite <tag flag="(form 1 + 2)">] == [
; 		rejoin [
; 			<tag flag=">	;-- result is a <tag>
; 			(form 3)
; 			{"}				;-- other strings should be normal strings, or we'll have <<">> result
; 		]
; 	]
; ]






;; <<<<<<<<<< %../common/composite.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [relativity]]]

;; >>>>>>>>>> %../common/relativity.red >>>>>>>>>



units-to-pixels: pixels-to-units: window-of: parent-of?:
face-to-window: window-to-face: face-to-screen: screen-to-face: face-to-face:
	does [do make error! "No View module!"]
	
if object? :system/view [								;-- CLI programs skip this
	context [
		dpi: any [attempt [system/view/metrics/dpi] 96]			;@@ temporary workaround for #4740
		ppd: dpi / 96.0	 						       			;-- pixels per (logical) dot = display scaling factor / 100%
		u2p:  func [x] [round/to x * ppd 1]						;-- units to pixels, one-dimensional
		u2p': func [x] [x * ppd]
		p2u:  func [x] [round/to x / ppd 1]						;-- pixels to units, one-dimensional
		p2u': func [x] [x / ppd]
	
		set 'units-to-pixels function [
			"Convert amount in virtual pixels into screen pixels"
			size [pair! point2D! integer! float!]
		][
			switch type?/word size [
				pair! [as-pair u2p size/x u2p size/y]
				point2D! [u2p' size]
				integer! float! [u2p size]
			]
		]
	
		;; should be careful here not to turn 1 into 0 (dangers of zero division, zero sized images..)
		;; does it make sense to clip the result at 1x1 (2D) and 1 (1D)?
		set 'pixels-to-units function [
			"Convert amount in screen pixels into virtual pixels"
			size [pair! point2D! integer!]
		][
			switch type?/word size [
				pair!    [as-pair p2u size/x p2u size/y]
				point2D! [p2u' size]
				integer! [p2u size]
			]
		]
	
		set 'window-of func [
			"Get the window object of FACE"
			face [object!]
		][
			while [all [face  'window <> face/type]] [face: face/parent]
			face
		]
	
		set 'parent-of? make op! func [
			"Checks if PA is a (probably deep) parent of FA"
			pa [object!]
			fa [object!]
		][
			while [fa: select fa 'parent] [if pa =? fa [return yes]]
			no
		]
	
		translate: func [
			"Translate coordinate XY between face FA and screen, using OP"
			xy [pair! point2D!]
			fa [object!]
			op [op!] ":+ for face-to-screen; :- for screen-to-face"
			/limit lim [word!] "Stop at this face type (default: 'screen)"
		][
			lim: any [lim 'screen]
			while [fa/type <> lim] [
				xy: xy op fa/offset
				fa: fa/parent
				
			]
			xy
		]
	
		set 'face-to-window func [
			"Translate a point XY in FACE space into window space"
			xy [pair! point2D!] face [object!]
		][
			translate/limit xy face :+ 'window
		]
	
		set 'window-to-face func [
			"Translate a point XY in window space into FACE space"
			xy [pair! point2D!] face [object!]
		][
			translate/limit xy face :- 'window
		]
	
		set 'face-to-screen func [
			"Translate a point in face space into screen space"
			xy [pair! point2D!] face [object!]
			/real "Translate to screen pixels (not scaled by DPI)"
		][
			xy: translate xy face :+
			if real [xy: units-to-pixels xy]
			xy
		]
	
		set 'screen-to-face func [
			"Translate a point in screen space into face space"
			xy [pair! point2D!] face [object!]
			/real "XY is in screen pixels (not scaled by DPI)"
		][
			if real [xy: pixels-to-units xy]
			translate xy face :-
		]
	
		set 'face-to-face func [
			"Translate a point XY from FACE1 space into FACE2 space"
			xy [pair! point2D!] face1 [object!] face2 [object!]
		][
			screen-to-face face-to-screen xy face1 face2
		]
	]
];if object? :system/view [

;; <<<<<<<<<< %../common/relativity.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [xyloop]]]

;; >>>>>>>>>> %../common/xyloop.red >>>>>>>>>



;@@ BUG: diverts return and exit
xyloop: function [
	"Iterate over 2D series or size"
	'word	[word! set-word!]
	srs		[pair! image!]
	code	[block!]
][
	any [pair? srs  srs: srs/size]
	repeat i srs/y * w: srs/x compose [
		set word as-pair  i - 1 % w + 1  i - 1 / w + 1		;-- OMG those index magicks
		(code)
	]
]

;; <<<<<<<<<< %../common/xyloop.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [tree-hopping]]]

;; >>>>>>>>>> %../common/tree-hopping.red >>>>>>>>>



; #include %with.red										;-- used in series-walker
; #include %without-gc.red								;-- gives massive speedup
; #include %xyloop.red									;-- for image iteration

;; by default tree walker branches only into any-block, object and map
;@@ make a REP with this typeset? seems useful, also defined in Spaces
;@@ container is defined as a type that we use to hold (unlike error) any kind of values (unlike strings)
container!: make typeset! [any-block! map! object!]
container?: function [
	"Test if value is a container"
	value [any-type!]
][
	find container! type? :value
]
	
walker!: object [										;-- minimal tree walker template
	plan:   []
	init:   does [clear plan]							;-- ensures clean slate (esp. when iteration doesn't finish correctly)
	reset:  does [plan: make [] 128]					;-- used to free (possibly big) series
	branch: func [:node] []
	visit:  func [:node :key] []
]

batched-walker!: make walker! [							;-- GC-smarter basic template
	batch:  []											;-- 'batch' can be used to hold 'plan' changes before insertion
	reset:  does [
		plan:  make [] 128
		batch: make [] 128
	]
]

series-walker!: make batched-walker! [					;-- template that visits all values in all series
	;; NOTE: given a container, visitor MUST return new (or old) container to branch into it
	
	walkable: make typeset! [any-block! any-object! any-string! vector! binary! map! image!]
	if datatype? :event! [walkable: union walkable make typeset! [event!]]	;-- only exists in View module
	
	;; avoids deadlocks and double visiting by keeping track of visits
	history: make hash! []
	unique-filter: func [value [any-type!]] [
		all [
			not find/only/same history :value
			append/only history :value
		]
	]
	no-filter: func [value [any-type!]] [true]
	filter: :unique-filter
	
	init: does [
		clear plan
		clear history
	]
	reset: does [
		plan:    make block! 128
		history: make hash!  128
		batch:   make block! 128
	]
	
	;; controls whether iteration is ordered or fast
	; schedule: :append
	schedule: :insert
	
	branch: function [:node [any-type!]] [branch' :node]		;-- entry point requires get-arg
	branch': function [node [any-type!]] compose/deep [			;-- any-type because container! may be replaced
		clear batch
		switch type?/word :node [
			(to [] any-block!) (to [] any-string!) vector! binary!
					[repeat  key length? node [push :node/:key]]
			(to [] any-object!)
					[foreach key keys-of node [push :node/:key]]
			;; while map can be iterated without keys-of, keys will become set-words, which isn't great
			;; also maps are case-sensitive, so without iteration select/case has to be used
			;; another reason to use keys-of is to avoid loops when keys themselves are modified by the visitor
			map!	[foreach key keys-of node [push select/case node :key]]
			image!	[xyloop key node [push node/:key]]			;@@ use for-each
			event!	[foreach key system/catalog/accessors/event! [push node/:key]]
		]
		schedule next plan batch
	]
	
	push: func [value [any-type!]] with :branch' [
		repend/only batch
			either all [find walkable type? :value  filter :value]
				[['branch' 'visit node key]]
				[['visit node key]]
	]
]

make-series-walker: function [
	"Make a series-walker! that branches into TYPES only"
	types [block! typeset!] "Any subset of series-walker!/walkable"
	/unordered "Unordered branching (faster)"
	/unsafe    "Assume all branches are unique (faster)"
][
	make series-walker! [
		walkable: make typeset! types
		if unordered [schedule: :append]
		if unsafe    [filter: :no-filter]
		bind body-of :push :branch'
		reset											;-- this recreates all walker's buffers
	]
]

foreach-node: function [
	"Iterate over the tree starting at root"
	root    [any-type!]        "Starting node"
	walker  [object!]          "A walker! object specifying the manner of iteration"
	visitor [function! block!] "A visitor function [node key] that may read or modify data"
	/extern plan
][
	walker/visit: either block? :visitor [func [:node :key] visitor][:visitor]
	walker/init
	repend/only walker/plan [in walker 'branch :root]	;@@ to visit root will need its address somehow
	also without-gc bind/copy [forall plan [do plan/1]] walker	;-- without copy can't be reentrant
		walker/reset
]


#hide []

;; <<<<<<<<<< %../common/tree-hopping.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [tabbing]]]

;; >>>>>>>>>> %../common/tabbing.red >>>>>>>>>



	
if object? :system/view [								;-- CLI programs skip this
unless object? get/any 'tabbing [						;-- avoid multiple inclusion and multiple handler functions

	tabbing: context [
		
		window-walker: make walker! [
			;; abstraction functions that can be overridden
			window?:     function [face [object!]] [face/type = 'window]
			next-linked: function [face [object!]] [select face/options 'next]
			prev-linked: function [face [object!]] [select face/options 'prev]
			first-child: function [face [object!]] [if face/pane [face/pane/1]]
			last-child:  function [face [object!]] [if face/pane [last face/pane]]
			has-child?:  function [face [object!]] [not empty? face/pane]
			next-child:  function [parent [object!] child [object!]] [
				select/same parent/pane child
			]
			prev-child:  function [parent [object!] child [object!]] [
				if found: find/same parent/pane child [found/-1]
			]
			parent-of:   function [child [object!]] [
				all [
					parent: child/parent
					parent/type <> 'screen				;-- window is the last allowed parent
					parent
				]
			]
			
			;; tree iteration logic
			next-face: function [face [object!]] [
				any [
					next-linked face
					first-child face
					(
						while [parent: parent-of face] [
							if sibling: next-child parent face [return sibling]
							face: parent
						]
						first-child face				;-- 'face' is different now (usually a window)
					)
				]
			]
			bottom: function [face [object!]] [
				while [has-child? face] [face: last-child face]
				face
			]
			prev-face: function [face [object!]] [
				any [
					prev-linked face
					unless parent: parent-of face [bottom face]
					if sibling: prev-child parent face [bottom sibling]
					if window? parent [bottom parent]
					parent
				]
			]
		
			;; chooses iteration direction
			forward?: yes
			
			;; entry point - iterates over all other faces within the window
			branch: function [face [object!]] [
				fetch: either forward? [:next-face][:prev-face]
				start: unless window? face [face]		;-- window will never be visited again, so avoid deadlock
				while [
					all [
						face: fetch face': face
						not same? face start
						not same? face face'			;-- avoid deadlock on short circuited faces
					]
				] [
					repend/only plan ['visit parent-of face face]
					start: any [start face]
				]
			]
		]

		enabled?: function [face [object!]] [
			while [face] [
				unless all [face/enabled? face/visible?] [return no]
				face: face/parent
			]
			yes
		]
		focusable?: function [face [object!]] [
			any [
				face/flags = 'focusable
				all [
					block? face/flags
					find face/flags 'focusable
				]
			]
		]
		
		visitor: function [parent [object! none!] child [object!]] [
			if all [focusable? child enabled? child] [ 
				set-focus child
				break
			]
		]
							
		tab-handler: function [face event] [
			all [
				event/key = #"^-"								;-- this automatically covers all key- events
				not event/ctrl?									;-- let area and tab-panel handle ctrl-tab
				any [focusable? face face/type = 'window]		;-- don't disable tab-completion in console and other custom faces
				result: 'stop									;-- stop to avoid area inserting Tab char
				if event/type = 'key-down [						;-- only react to one event type (should be repeatable - key or key-down)
					window-walker/forward?: not event/shift?
					foreach-node face window-walker :visitor
				]
			]
			result
		]
	
		remove-event-func 'tab							;-- disable native tabbing handler
		unless find/same system/view/handlers :tab-handler [insert-event-func 'tabbing :tab-handler]
	]
];unless object? get/any 'tabbing [
];if object? :system/view [

;; <<<<<<<<<< %../common/tabbing.red <<<<<<<<<
					;-- extended by spaces/tabbing.red
		
#do [if block? :included-scripts [append included-scripts [scoping]]]

;; >>>>>>>>>> %../common/scoping.red >>>>>>>>>



;; this is useful when errors/throws are not normally expected in the code and end of block is known to be reached
;; one strategy is to insert `also` before last token of the block, but this does not reverse the finalization order
;; another is to use `also do rest do finalizer` but `do` will prevent compilation
;; previously used `also if true [rest] (finalizer)` to avoid stack issues with parens
;; using `also (rest) (finalizer)` now that stack issues have been fixed
#macro [#leaving block!] func [[manual] s e /local rest cleanup] [
	either tail? e [									;-- unlikely case, but have to secure against it
		change s 'do
	][
		cleanup: to paren! s/2
		rest:    to paren! e
		clear change/only change/only change s 'also rest cleanup
	]
	new-line s on
]

;@@ need a better name, maybe #leaving/safe, but issues don't unstick refinements
#macro [#leaving-safe block!] func [[manual] s e /local rest cleanup] [
	either tail? e [									;-- unlikely case, but have to secure against it
		change s 'do
	][
		cleanup: s/2
		rest: copy e
		clear change change/only change/only change/only s 'following/method rest cleanup quote 'trap
	]
	new-line s on
]


; probe [1 + 2 #leaving [3]]
; probe do probe [1 + 2 #leaving [3 * 4] #leaving ['x] 5 + 6]

;; <<<<<<<<<< %../common/scoping.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [collect-set-words]]]

;; >>>>>>>>>> %../common/collect-set-words.red >>>>>>>>>



collect-set-words: function [
	"Deeply collect set-words from a block of code"
	code [block!]
	/local w
][
	spec: spec-of function [] code
	parse spec [remove /local any change set w word! (to set-word! w)]
	spec
]

comment {
	;-- this version is 4x slower, but uses 10x less RAM
	collect-set-words: function [
		"Deeply collect set-words from a block of code"
		code [block!]
	][
		rule: [any [
			ahead [block! | paren!] into rule
		|	keep set-word!
		|	skip
		]]
		parse code [collect rule]
	]
}
;; <<<<<<<<<< %../common/collect-set-words.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [print]]]

;; >>>>>>>>>> %../common/print-macro.red >>>>>>>>>



; #include %composite.red									;-- doesn't make sense to include this file without #composite also

#macro [#print skip] func [[manual] s e] [
	unless string? s/2 [
		print form make error! "#print macro expects a string! argument"
	]
	insert remove s [print #composite]
	s		;-- reprocess it again so it expands #composite
]

;; <<<<<<<<<< %../common/print-macro.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [error]]]

;; >>>>>>>>>> %../common/error-macro.red >>>>>>>>>



									;-- doesn't make sense to include this file without #composite also

;; I'm intentionally not naming it `#error` or the macro may be silently ignored if it's not expanded
;; (due to many issues with the preprocessor)
#macro [
	p: 'ERROR
	(either "ERROR" == mold p/1 [p: []][p: [end skip]]) p		;@@ this idiocy is to make R2 accept only uppercase ERROR
	skip
] func [[manual] ss ee] [
	unless string? ss/2 [
		print form make error! form reduce [
			"ERROR macro expects a string! argument, not" mold copy/part ss/2 50
		]
	]
	remove ss
	insert ss [do make error! #composite]
	ss		;-- reprocess it again so it expands #composite
]

;; <<<<<<<<<< %../common/error-macro.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [prettify]]]

;; >>>>>>>>>> %../common/prettify.red >>>>>>>>>



prettify: none
context [
	draw-commands: make hash! [
		line curve box triangle polygon circle ellipse text arc spline image
		matrix reset-matrix invert-matrix push clip rotate scale translate skew transform
		pen fill-pen font line-width line-join line-cap anti-alias
	]
	shape-commands: make hash! [
		move hline vline line curv curve qcurv qcurve arc
	]
	
	VID-styles: make hash! any [attempt [keys-of :system/view/VID/styles] 0]
	VID-panels: make hash! [panel group-box tab-panel]
	
	stack: make hash! 16
	head': func [s] [either map? s [s][head s]]

	set 'prettify function [
		"Reformat BLOCK with new-lines to look readable"
		block [block! paren! map!] "Modified in place, deeply"
		/data  "Treat block as data (default: as code)"
		/draw  "Treat block as Draw dialect"
		/spec  "Treat block as function spec"
		/parse "Treat block as Parse rule"
		/vid   "Treat block as VID layout"
		/from  "Keep block flat if it molds in less chars than limit"
			limit "Default = 80, to always expand use 0" 
		/local body word
	][
		if empty? orig: block [return orig]
		either find/only/same stack head' orig					;-- cycle protection
			[return orig]
			[append/only stack head' orig]
		unless map? block [new-line/all block no]				;-- start flat
		default limit: 80										;-- expansion margin
		
		; print [case [data ["DATA"] spec ["SPEC"] parse ["PARSE"] 'else ["CODE"]] mold block lf]
		loop 1 [case [
			map? block [
				block: values-of block
				while [block: find/tail block block!] [
					prettify/data/from block limit
				]
			]
			data [												;-- format data as key/value pairs, not expressions
				while [block: find/tail block block!] [
					prettify/data/from inner: block/-1 limit	;-- descend recursively
				]
				if any [
					inner										;-- has inner blocks?
					limit <= length? mold/part orig limit		;-- longer than limit?
				][
					new-line/skip orig yes 2					;-- expand as key/value pairs
				]
			]
			spec [
				if limit > length? mold/part orig limit [break]
				new-line orig yes
				forall block [
					if all-word? :block/1 [new-line block yes]	;-- new-lines before argument/refinement names
					if /local == :block/1 [break]
				]
			]
			parse [
				if limit > length? mold/part orig limit [break]
				new-line orig yes
				forall block [
					case [
						'| == :block/1 [new-line block yes]		;-- new-lines before alt-rule
						block? :block/1 [prettify/parse/from block/1 limit]
						paren? :block/1 [prettify/from       block/1 limit]
					]
				]
			]
			vid [
				styles: copy VID-styles
				split:  [(new-line split?: p yes)]
				system/words/parse block layout: [any [p:
					set word word! if (find styles word) split (style: word)
				|	'at pair! opt set-word! set style word! split	;-- preferable split point
				|	set-word! set style word! split					;-- ditto
				|	'style set word set-word! set style word! split
					(append styles to word! word) 				;-- new styles are collected FWIW
				|	'draw
					change only set block block! (prettify/draw/from block limit)
				|	['data | 'extra] 
					change only set block block! (prettify/data/from block limit)
				|	change only set block block! (
						vid: to logic! find VID-panels style
						prettify/:vid/from block limit
					) 
				|	skip
				]]
				if split? [new-line orig not split? =? orig]	;-- don't expand single-face VID
			]
			draw [
				if limit > length? mold/part orig limit [break]
				split: [p: (new-line back p yes)]
				system/words/parse orig rule: [any [
					ahead block! p: (new-line/all p/1 off) into rule
				|	set word word! [
						'shape any [
							set word word! if (find shape-commands word) split
						|	skip
						]
					|	if (find draw-commands word) split
					]
				|	skip
				]]
			]
			'code [
				code-hints!: make typeset! [any-word! any-path!]
				until [
					new-line block yes							;-- add newline before each independent expression
					tail? block: preprocessor/fetch-next block
				]
				system/words/parse orig [any [p:
					ahead word! ['function | 'func | 'has]		;-- do not mistake words for lit-/get-words
					set spec block! (prettify/spec/from spec limit)
					set body block! (prettify/from      body limit)
				|	ahead word! 'draw pair! set block block! (prettify/draw/from block limit)
				|	set block block! (
						unless empty? block [
							part: min 50 length? block			;@@ workaround for #5003
							case [
								not find/part block code-hints! part [	;-- heuristic: data if no words nearby
									prettify/data/from block limit
								]
								find/case/part block '| part [	;-- heuristic: parse rule if has alternatives
									prettify/parse/from block limit
								]
								'else [prettify/from block limit]
							]
							if new-line? block [new-line p no]	;-- no newline before expanded block
						]                                       
					)
				|	set block paren! (prettify/from block limit)
				|	skip
				]]
			]
		]]
		take/last stack
		orig
	]
]

; probe prettify load mold/flat :prettify

;; <<<<<<<<<< %../common/prettify.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [charsets from-latin-1]]]

;; >>>>>>>>>> %../common/charsets.red >>>>>>>>>


charsets: context [
	space:				charset " "
	non-space:			negate space
	space+tab:			charset " ^-"
	non-space+tab:		negate space+tab
	white:				charset " ^-^/^M"
	non-white:			negate white
	digit:				charset [#"0" - #"9"]
	nonzero-digit:		charset [#"1" - #"9"]
	non-digit:			negate digit
	hex-digit:			charset [#"0" - #"9" #"a" - #"f" #"A" - #"F"]
	hex-digit-lower:	charset [#"0" - #"9" #"a" - #"f"]
	hex-digit-upper:	charset [#"0" - #"9" #"A" - #"F"]
	alpha:				charset [#"a" - #"z" #"A" - #"Z"]
	alpha-lower:		charset [#"a" - #"z"]
	alpha-upper:		charset [#"A" - #"Z"]
	alpha+digit:		union alpha digit
	ascii:              charset [00h - 7Fh]
	latin-1-supplement: charset [80h - FFh]
	latin-1:            charset [00h - FFh]
	; uni-alpha: ...
	;; excluded from uni-white are: 00A0 - NO-BREAK SPACE, 202F - NARROW NO-BREAK SPACE,
	;; because they're supposed to be part of the word, not a delimiter
	uni-white:			union white charset "^(1680)^(2000)^(2001)^(2002)^(2003)^(2004)^(2005)^(2006)^(2007)^(2008)^(2009)^(200A)^(2028)^(2029)^(205F)^(3000)"
	printable: 			charset [not 0 - 31 127]				;-- reference: https://en.wikipedia.org/wiki/Graphic_character
]

;; bytes 80h-FFh map to unicode codepoints 80h-FFh, so the conversion is straightforward and never fails
from-latin-1: function [
	"Convert BINARY into text assuming ISO-8859-1 encoding"
	binary  [binary!]
	return: [string!]
	/local c
] bind [
	=ascii=: [s: some ascii e: keep (to string! copy/part s e)]
	=ext=:   [some [set c latin-1-supplement keep (to char! c)]]
	result:  make {} length? binary
	parse/case binary [collect after result any [=ascii= | =ext=]]
	result
] charsets

;; <<<<<<<<<< %../common/charsets.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [exponent-of]]]

;; >>>>>>>>>> %../common/exponent-of.red >>>>>>>>>


;; returns none for: zero (undefined exponent), +/-inf (overflow), NaN (undefined)
exponent-of: function [
	"Returns the exponent E of number X = m * (10 ** e), 1 <= m < 10"
	x [number!]
][
	attempt [to 1 round/floor log-10 absolute to float! x]
]

;; <<<<<<<<<< %../common/exponent-of.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [format-readable]]]

;; >>>>>>>>>> %../common/format-readable.red >>>>>>>>>


; #include %assert.red
; #include %exponent-of.red
; #include %charsets.red
; #include %show-trace.red

format-readable: none
context [
	; digit:   charset [#"0" - #"9"]
	; dig19:   charset [#"1" - #"9"]
	; nonzero: charset [not #"0"]

	insert-separators: function [formed] bind [			;-- does not expect separators to be already inserted
		parse formed [
			to [digit | #"."]										;-- skip optional sign, but not leading dot
			s: any digit e: (len: offset? s e)						;-- count digits until suffix/dot/end
			:s (lead: len + 2 % 3 + 1) lead skip					;-- skip leading group
			(grps: max 0 len - lead / 3) grps [insert #"'" 3 skip]	;-- insert separators
		]
		formed
	] charsets

	

	set 'format-readable function [
		"Format a number for readability, in decimal or exponential form"
		num [number!]									;-- original number is needed for rounding to work
		/size   "Specify the number of significant figures"
			n [integer!] "Defaults to 2"
		/exp    "Format in exponential form instead of decimal, using E as exponent"
			e [integer! word!] "E.g. E=0 NUM=123 => 123e0 output; 'auto to deduce E automatically"
		/extend "Let numbers starting with '1' get an additional digit"
		/clean  "Remove trailing zeroes after the dot and leading zero before the dot"
	][
																	;@@ ideally we want string-based precise rounding here

		;-- setup
		n: any [n 2]
		e: any [e 0]
		num': 1e50 * absolute num						;-- convert percent/int into float, force exp output
		if percent? num [num': num' * 100]
		
		;-- determine the rounding digit and round it
		do renew: [
			e0: -50 + any [exponent-of num'  50]			;-- extract original exponent
			if 'auto = e [e: e0]
			formed: form num'
			ext: make integer! extend and (#"1" = formed/1)	;-- add a digit for 1.xx numbers
			n-digits: max									;-- determine the number of digits for rounding
				n + ext										;-- requested size + possibly extended by 1
				e0 - e + 1									;-- number of whole digits which we don't want to zero out
		]
		num': round/to num' 10 ** (e0 - n-digits + 1) * 1e50

		;-- form rounded result and update width
		do renew
		
		;-- clean up formed result and ensure proper length
		clear find (remove find formed #".") #"e"			;-- leave only digits
		clear skip formed n-digits							;-- clean up possible rounding errors e.g. 0.9900000000002
		append/dup formed #"0" n-digits - length? formed	;-- right-pad with zeroes up to N size
		if e0 < e [											;-- left-pad the future dot with zeroes
			insert/dup formed #"0" e - e0
			e0: e
		]

		;-- insert the dot, but only if there are digits after it
		dot: skip formed e0 - e + 1
		unless tail? dot [insert dot #"."]

		;-- remove unnecessary zeroes as visual noise
		if clean [
			parse reverse dot [remove [any #"0" opt #"."]]	;-- trailing zeroes
			reverse dot
			parse formed [remove [#"0" ahead skip]]			;-- leading zero
		]

		if exp [append append formed #"e" e]			;-- add the exponent if requested
		if percent? num [append formed #"%"]			;-- type sigil
		if num < 0 [insert formed #"-"]					;-- sign
		insert-separators formed
	]

	
]


{
	;-- reversed version - not better if done correctly, because has to skip a lot of extra stuff
	insert-separators: function [formed] [
		parse reverse formed [
			opt #"%"
			opt [some digit opt #"-" #"e"]
			opt [some digit #"."]
			any [3 digit ahead digit insert #"'"]
		]
		reverse formed
	]

	;-- a bit more convoluted version, and limited by exponent range even more
	;-- instead of forming in e-form it forms in decimal form internally (but that works up to 1e20 max)
	;-- has a bug, /exp is not implemented
	format-readable: function [
		"Format a number in decimal form, using N significant digits"
		num [number!]
		/size "Defaults to -2; numbers starting with '1' get an additional digit"
			n [integer!] "Negative N won't round integer part of NUM (i.e. 9876.5 -> 9877, not 9900)"
		; /exp "Format with exponent instead of decimal form"
		; 	e [integer!] "E.g. E=0 NUM=123 => 123e+0 output"
		/clean "Remove trailing zeroes after the dot"
	][
		n: any [n -2]
		e: any [e 0]

		;-- need to move all visible digits after the dot to get non-exp output from `form`
		|n|: absolute n
		either num = 0 [								;-- special case for zero, where log-10 = -inf
			whole: 1
			power: 0
		][
			whole: 1 + to 1 round/floor/to log-10 num / 2 1.0	;-- number of whole digits; /to 1 is buggy (#4882) so using 1.0
																;-- num / 2 allows to add a digit to numbers starting with "1"
			power: |n| - whole							;-- power of 10 to multiply the num with to get rid of fractional part
		]
		if n < 0 [power: max 0 power]					;-- don't round integers if n<0
		
		;-- multiply by power of 10 so `form` does not result in exponential notation
		rounded: round/to 10.0 ** power * num 1.0
		formed: form rounded
		
		;-- find the dot position and remove the ".0" suffix
		clear skip tail formed -2
		dot: (1 + length? formed) - power				;-- dot was shifted by power digits
		whole: dot - 1
		
		;-- ensure max(n,whole) digits even if num=0
		append/dup formed #"0" (max |n| whole) - length? formed
		
		;-- insert the new dot
		dot: either dot <= 1 [							;-- dot should be inserted at head or earlier?
			next head insert/dup formed #"0" 2 - dot	;-- pad with zeroes before the dot then
		][
			at formed dot
		]
		insert dot #"."

		;-- cleanup
		case/all [
			clean [										;-- remove trailing zeroes when clean=on
				clear find/last/tail dot nonzero
			]
			#"." = last formed [						;-- don't leave trailing dot without any more digits
				take/last formed
			]
			all [clean find/match formed "0."] [		;-- remove leading zero when clean=on
				take formed
			]
		]
		if percent? num [append formed #"%"]
		formed
	]

}


;; <<<<<<<<<< %../common/format-readable.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [trace]]]

;; >>>>>>>>>> %../common/shallow-trace.red >>>>>>>>>


shallow-trace: func [
	"Evaluate each expression in CODE and pass it's result to the INSPECT function"
	inspect	[function!] "func [result [any-type!] next-code [block!]]"
	code	[block!]	"If empty, still evaluated once (resulting in unset)"
	/local r
][
	; #assert [parse spec-of :inspect [thru word! quote [any-type!] thru word! not to word! to end]]	;@@ affects clock-each
	set/any 'r do/next code 'code					;-- eval at least once - to pass unset from an empty block
	inspect :r code
	either tail? code [:r][shallow-trace :inspect code]
]

{
	;-- this version deadlocked if traced code contained `continue` (because it then applied to the `until` of `trace`)

	trace: func [
		"Evaluate each expression in CODE and pass it's result to the INSPECT function"
		inspect	[function!] "func [result [any-type!] next-code [block!]]"
		code	[block!]	"If empty, still evaluated once (resulting in unset)"
		/local r
	][
		#assert [parse spec-of :inspect [thru word! quote [any-type!] thru word! not to word! to end]]	;@@ affects clock-each
		until [
			set/any 'r do/next code 'code					;-- eval at least once - to pass unset from an empty block
			inspect :r code
			tail? code
		]
		:r
	]
}
;; <<<<<<<<<< %../common/shallow-trace.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [profiling]]]

;; >>>>>>>>>> %../common/profiling.red >>>>>>>>>








; #macro [ahead word! '*** to end] func [[manual] s e] [	;-- [manual] to support macros inside of it ;@@ + workaround for #3554
#macro [p: word! :p '*** to end] func [[manual] s e] [	;-- [manual] to support macros inside of it ;@@ + workaround for #3554
	back clear change s reduce ['clock-each copy next s]
]

; #macro [ahead paren! into [ahead word! '* some [thru [ahead word! '*]]]] func [[manual] s e] [	-- this doesn't work in compiler (R2 parse)
#macro [
	p: paren! :p into [
		p: word! :p '* to end p: (p: back p) :p word! :p '* end
	]
] func [[manual] s e] [
	e: s/1
	if '* = pick e length? e [							;-- R2 compatibility headaches
		remove s
		remove back tail e
		insert s reduce ['prof/each/quiet to block! next e]
	]
	s
]

;@@ need to use tracer's EXPR event for /each profiling to descend into scopes!
clock-each: none
prof: context [
	;; data format: [marker [iteration-count total-time total-ram] ...] (can't use a map because marker is code (block))
	data:         make hash! 20
	
	;; stack of markers of currently entered into scopes (used by /manual)
	marker-stack: make block! 60
	
	;; memoized copied expression blocks (used by /each)
	expressions:  make hash! 60
	
	last-time:    none
	last-stats:   none

	reset: func ["Forget all collected profiling stats"] [
		clear data
		clear marker-stack
		clear expressions
		set [last-time last-stats] none
	]

	format-delta: function [
		"Number formatter used internally by PROF/EACH"
		delta [number!] dot-index [integer!]
	][
		s: case [
			nan?     delta ["NaN"]
			percent? delta [format-readable/size/clean   delta 0]
			'else          [format-readable/extend/clean delta]
		]
		dot: index? any [find s #"."  tail s]			;-- align the dot
		pad/left s dot-index - dot + length? s
	]

	ordered?: function [
		"Check if value1 comes before value2 in sort order"
		value1 [any-type!] value2 [any-type!]
	][
		value =? first sort reduce/into [:value1 :value2] clear []
	]
	
	;@@ get stats as a table (block)
	show: function [
		"Print all profiling stats collected so far" 
		/order column [word! block!] "Order output by one or more of: [count share time bytes marker]"
		/reverse "Reverse the output order"
		/header  "Output the column header"
	][
		if empty? data [exit]									;-- nothing to show
		width:   any [attempt [system/console/size/x - 43] 40]	;-- 42 = len(<999999> 99% 9'999.99999 ms 999'000'000 B )
		t-total: elapsed: 0:0									;-- collect totals first
		foreach [marker info] data [
			if marker [t-total: t-total + info/2]				;-- no need to count time between markers
			elapsed: elapsed + info/2
		]
		t-total: 1e3 * to float! t-total
		elapsed: 1e3 * to float! elapsed
		
		;; form a queue to sort it
		either column [
			queue: append clear [] data
			set [marker: info: count: time: bytes:] [1 2 1 2 3]
			foreach column compose [(column)] [
				
				cmp: func [a b] switch column [
					count  [[a/:info/:count >= b/:info/:count]]
					time   [[(a/:info/:time  / a/:info/:count) >= (b/:info/:time  / b/:info/:count)]]
					bytes  [[(a/:info/:bytes / a/:info/:count) >= (b/:info/:bytes / b/:info/:count)]]
					share  [[a/:info/:time  >= b/:info/:time]]
					marker [[ordered? a/1 b/1]]			;-- ascending order here by default
				]
				sort/skip/compare/all queue 2 :cmp
			]
		][
			queue: data
		]
		if reverse [system/words/reverse/skip queue 2]
		
		if header [print "Count   Share    Time/Run         Bytes/Run    Marker"]
		foreach [marker info] queue [
			if marker = none [continue]							;-- no need to show the baseline or time between markers
			set [n: dt: ds:] info
			dt:     (1e3 * to float! dt) / n					;-- always switch to millisecs so bigger times stand out
			time:   pad format-delta dt 5 11					;-- 9'999.99999 ms: dot=5 total=11
			ram:    format-delta (round/to ds / n 1) 12			;-- 999'999'999 b: dot=12, total=11
			count:  pad mold to tag! n 9						;-- '<999999> ' iterations: total=9
			share:  pad format-delta 100% * dt * n / t-total 4 4	;-- '100%' = 4 chars total
			marker: system/tools/tracers/mold-part marker width
			print to string! reduce [count share " " time "ms " ram " B " marker]
		]
		if last-time [
			load: format-readable/size 100% * (t-total / elapsed) 2
			print ["CPU load of profiled code:" load]
		]
		exit													;-- no return value
	]

 	commit: function [marker [immediate! any-string! block!] dt [time!] "elapsed time" ds [integer!] "RAM change"] [
		same: block? marker
		either cell: select/skip/only/:same data marker 2 [
			change change change cell
				cell/1 + 1
				cell/2 + dt
				cell/3 + ds
		][
			reduce/into [marker cell: reduce [1 dt ds]] tail data
		]
		cell
	]
	
	manual: function [
		"Profile time between start and end (can be reentrant)"
		marker [immediate! any-string!] "ID token that should be same for start and end"
		/start /end
		/extern last-time last-stats
	][
		time: now/precise/utc
		
		either last-time [
			dt: difference time last-time
			ds: stats - last-stats
			commit last marker-stack dt ds				;-- commit last interval (no marker = unrelated code)
		][
			last-time:  time
			last-stats: stats
		]
		
		
		either start [
			append/only marker-stack :marker
		][
			
			take/last marker-stack
		]
		last-stats: stats
		last-time:  now/precise/utc						;-- repeat timestamp for more precision
	]

	set 'clock-each										;-- left for backward compatibility
	each: function [									;-- new interface: PROF/EACH
		"Display execution time of each expression in CODE"
		code [block!] "Evaluation result is only returned if N = 1"
		/times n [integer! float!] "Repeat the whole CODE N times (default: once); displayed time/RAM is per iteration"
		/quiet "Don't print anything, just save the results for later display via PROF/SHOW"
		/local result
	][
		n: to integer! any [n 1]
		code-copy: copy/deep code						;-- preserve the original code in case it changes during execution ;@@ copy maps too
		test-code: compose [#(none) #(none) (code)]		;-- need 2 no-ops to: (1) negate startup time of `shallow-trace`, (2) establish a baseline
		
		timer: func [result [any-type!] pos [block!]] [	;-- collects timing of each expression
			t2: now/utc/precise							;-- 2 time markers here - to minimize `timer` influence on timings
			s2: stats
			switch/default i: index? pos [
				2 []									;-- ignore startup-related 'none'
				3 [base: difference t2 t1]
			][
				code-pos: at head code i: i - 2			;-- use original (unique) code block+offset as marker
				unless expr: select/only/same/skip expressions code-pos 2 [
					expr: copy/part code-copy code-copy: at head code-copy i
					append/only append/only expressions code-pos expr
				]
				dt: max 0:0 (difference t2 t1) - base
				commit expr dt (s2 - s1)
			]
			s1: stats
			t1: now/utc/precise							;-- /utc is 2x faster
			:result
		]

		without-GC [
			loop n [									;-- profile the code
				s1: stats
				t1: now/utc/precise
				set/any 'result shallow-trace :timer test-code	;-- this may throw out of the profiler
			]
		]

		unless quiet [show/header reset]
		either n = 1 [:result][exit]					;-- result is needed for transparent profiling with `***` and `(* *)`
	]
	
]

; ; loop 10000 [(* 1 2 3 *)]
; loop 10 [(* wait 0.1 wait 0.01 wait 0.03 make [] 100000 *)]
; loop 100 [(* 1 2 3 wait 0.002 *)]
; prof/show
; prof/each/times [1] 10000

; prof/manual/start 'x
; wait 0.5
; prof/manual/start 'y
; wait 0.5
; prof/manual/start 'z
; wait 0.5
; prof/manual/end 'z
; prof/manual/end 'y
; wait 0.5
; prof/manual/end 'x
; prof/show

; prof/manual/start 'x
; prof/manual/start 'x
; wait 0.5
; prof/manual/end 'x
; wait 0.5
; prof/manual/end 'x
; prof/show

; loop 10000 [(* 1 2 3 continue 4 5 6 7 *) 2]
; probe 1
; prof/show
; halt


;; <<<<<<<<<< %../common/profiling.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [extrema]]]

;; >>>>>>>>>> %../common/extrema.red >>>>>>>>>


minmax-of: function [
	"Compute [min max] pair along XS"
	xs [block! hash! vector! image! binary! any-string!]
][
	x-: x+: first xs
	foreach x next xs [x-: min x- x  x+: max x+ x]
	reduce [x- x+]
]

minimum-of: maximum-of: none
context [
	;; these versions are usually 3-4 times slower
	brute-minimum-of: func [
		"Find minimum value among XS"
		xs [block! hash! vector! image! binary! any-string!]
	][
		x-: first xs
		foreach x next xs [x-: min x- x]
		x-
	]

	brute-maximum-of: func [
		"Find minimum value among XS"
		xs [block! hash! vector! image! binary! any-string!]
	][
		x+: first xs
		foreach x next xs [x+: max x+ x]
		x+
	]

	containers: object [
		block!:  make system/words/block!  50
		hash!:   make system/words/block!  50
		string!: make system/words/string! 50
		email!:  make system/words/string! 50
		file!:   make system/words/string! 50
		ref!:    make system/words/string! 50
		url!:    make system/words/string! 50
		binary!: make system/words/binary! 50
		;; not for image! and tag! - those should use the brute version
		;; not for vector! - since they are of incompatible types which are unknown
	]

	set 'minimum-of func [
		"Find minimum value among XS"
		xs [block! hash! vector! image! binary! any-string!]
	][
		either buf: select containers type?/word :xs [
			also first sort append buf xs
				clear buf
		][	brute-minimum-of xs
		]
	]

	set 'maximum-of func [
		"Find minimum value among XS"
		xs [block! hash! vector! image! binary! any-string!]
	][
		either buf: select containers type?/word :xs [
			also last sort append buf xs
				clear buf
		][	brute-maximum-of xs
		]
	]
]

;; <<<<<<<<<< %../common/extrema.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [selective-catch]]]

;; >>>>>>>>>> %../common/selective-catch.red >>>>>>>>>


;@@ BUG: this turns return/exit/break/continue into errors (when not caught) - they should be rethrown separately using their natives
;@@ BUG: throw cannot be used from inside CODE block, because it will be turned into an error before being rethrown!
selective-catch: func [
	"Evaluate CODE and return errors of given TYPE & ID only, while rethrowing all others"
	type	[word!]
	id		[word!]
	code	[block!]
	/default value [any-type!] "Return this value on successful catch instead of the error object"
	/local e r
][
	all [
		error? e: try/all/keep [set/any 'r do code  'ok]	;-- r <- code result (maybe error or unset);  e <- error or ok
		any [											;-- muffle & return the selected error only
			e/type <> type
			e/id <> id
			return either default [:value][e]
		]
		do e											;-- rethrow errors we don't care about
	]
	:r													;-- pass thru normal result
]

;;@@ catching it is all cool, but how to actually propagate it further up as `return`,
;;   not as an error, considering `return` will be caught by the function anyway?
catch-return:  func [
	"Evaluate CODE catching RETURN and EXIT (for use in loops)"
	code	[block!]
][
	selective-catch 'throw 'return code
]

;;@@ should this use some /default value or detection by error is okay?
catch-a-break:  func [
	"Evaluate CODE catching BREAK (for use in loops)"
	code	[block!]
][
	selective-catch 'throw 'break code
]

catch-continue: func [
	"Evaluate CODE catching CONTINUE (for use in loops)"
	code	[block!]
][
	selective-catch/default 'throw 'continue code ()	;-- return unset on continue, in accord with other loops
]

;; <<<<<<<<<< %../common/selective-catch.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [reshape]]]

;; >>>>>>>>>> %../common/reshape.red >>>>>>>>>


; #include %hide-macro.red
; #include %assert.red

;@@ TODO: implement it in R/S to be more useful, also see REP #133
reshape: none
context [
	keep?: func [x [any-type!]] [
		switch/default type?/word :x [none! unset! [[]]] [:x]
	]
	
	swap: function [a b] [								;@@ export me somehow
		x: get a
		set a get b
		set b :x
	]
	
	;; new and limited reshape syntax:
	;; @[] inserts as value
	;; @() splices
	;; /if after non-empty line - enables/disables the line
	;; /if after empty line - enables/disables section (until next such /if or end)
	;; optional /with refinement to replace the default [@ /if] tokens (instead of /skip)
	set 'reshape function [
		"Deeply rewrite the block using provided grammar"
		block [any-list!]
		/with "If provided, becomes the 1st argument"
			grammar [any-list!] "A block of 1-2 values: [substitution-marker if-marker], default: [@ /if]"
		/sub  "Provide a value substitution function"
			do-sub [function! action! native! routine!] "Must be unary, defaults to `do`"
		/local succ?
	] bind [
		either with [swap 'grammar 'block][grammar: [@ /if]]
		unless :do-sub [do-sub: :do]
		=sub=:	any [grammar/1 [fail]]
		=if=:	any [grammar/2 [fail]]
		parse/case result: copy/deep block =block=: [
			at-line: opt =if-section= 
			any [p:
				end
			|	if (new-line? p) at-line: =if-section=
			|	=sub= [
					block! change only p (do-sub p/2)
				|	paren! change p (keep? do-sub p/2)
				]
			|	at-if: =if= =do-cond= [if (succ?) =rem-if= | =rem-line=]
			|	ahead any-list!
				(append/only lines at-line)
				into =block=
				(at-line: take/last lines)				;-- restore the start-of-line
			|	skip
			]
		]
		result
	] rules: context [									;-- rules are out for faster operation
		lines:			make [] 4
		=do-cond=:		[p: (succ?: do/next p 'p) :p]
		=rem-if=:		[p: remove at-if]
		=rem-line=:		[p: remove at-line]
		=rem-section=:	[[to [p: =if= if (new-line? p)] | to end] remove at-if]
		=if-section=:	[at-if: =if= =do-cond= [if (:succ?) =rem-if= | =rem-section=]]
	]
	bind body-of rules :reshape
]

comment {	;-- two-pass version about 2x slower, but does not evaluate skipped substitutions
		result: copy/deep block
		;; first pass - process ifs
		if grammar/2 [
			parse/case result =block=: [
				at-line: opt =if-section= 
				any [p:
					end
				|	if (new-line? p) at-line: =if-section=
				|	at-if: =if= =do-cond= [if (succ?) =rem-if= | =rem-line=]
				|	ahead any-list!
					(append/only lines at-line)
					into =block=
					(at-line: take/last lines)				;-- restore the start-of-line
				|	skip
				]
			]
		]
		;; second pass - process substitutions
		types: make typeset! reduce [any-list! type? =sub=]
		parse/case result =block=: [
			any [to types [p:
				=sub= [
					block! change only p (do p/2)
				|	paren! change p (keep? do p/2)
				]
			|	ahead any-list! into =block=
			|	skip
			]]
		]
}

#hide []

comment [	;-- speed tests - reshape is ~10x slower than compose, which is great result for a mezz
	recycle/off
	; clock/times [compose []] 1e6
	; clock/times [reshape-light []] 1e6
	; clock/times [reshape []] 1e6
	
	clock/times [compose/deep [(1 + 2) 3 4 (5 * 6)]] 1e6
	; clock/times [reshape-light [@(1 + 2) 3 4 @(5 * 6)]] 1e6
	clock/times [reshape [@(1 + 2) 3 4 @(5 * 6)]] 1e6

	pname: "program"
	ver: "1.0"
	desc: none
	author: none
	clock/times [
		form compose/deep [  ;-- uses ability of FORM to skip unset values
			(pname) (ver)
			(any [desc ()])
			(either author [rejoin ["by "author]][()])
			#"^/"
		]
	] 1e5
	clock/times [
		form reshape [
			@(pname) @(ver)	@(desc)
			"by"	/if author
			@(author) #"^/"
		]
	] 1e5
	clock/times [
		form reshape/with [@] [
			@(pname) @(ver)	@(desc)
			"by"	/if author
			@(author) #"^/"
		]
	] 1e5
]

;; <<<<<<<<<< %../common/reshape.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [apply]]]

;; >>>>>>>>>> %../common/new-apply.red >>>>>>>>>



; #include %assert.red
; #include %error-macro.red
; #include %hide-macro.red

;@@ NOTE: this impelementation is intentionally not optimized as Red code, but written in R/S style for easier transition!
;@@ TODO: automatically set refinement to true if any of it's arguments are provided?
mezz-apply: function [									;@@ name to be used during transition; to be excluded eventually
	"Call a function NAME with a set of arguments ARGS"
	;@@ support path here or `(in obj 'name)` will be enough?
	;@@ operators should be supported too
	'name [word! function! action! native!] "Function name or literal"
	args [block! function! object! word!] "Block of [arg: expr ..], or a context to get values from"
	/verb "Do not evaluate expressions in the ARGS block, use them verbatim"
	/local value
][
	if word? :args [args: context? args]
	if all [not verb  block? :args] [					;-- evaluate expressions, create a /verb-like block
		buf: clear copy args
		pos: args
	 	while [not tail? bgn: pos] [
	 		either word? :pos/1 [
	 			repend buf [pos/1 get/any pos/1]
	 			pos: next pos
	 		][
		 		unless set-word? :pos/1 [
		 			ERROR "Expected word or set-word at (mold/part args 30)"
		 		]
		 		while [set-word? first pos: next pos][]	;-- skip 1 or more set-words
		 		set/any 'value do/next end: pos 'pos
		 		repeat i offset? bgn end [repend buf [bgn/:i :value]]
		 	]
	 	]
	 	args: buf
	]
	
	;@@ TODO: hopefully in args=block case we'll be able to make it O(n)
	;@@ by having O(1) lookups of all set-words into some argument array specific to each particular function
	;@@ this implementation for now just uses `find` within args block, which makes it O(n^2)
	
	either word? :name [
		set/any 'fun get/any name
		unless any-function? :fun [ERROR "NAME argument (name) does not refer to a function"]
	][
		anonymous: fun: :name
		name: 'anonymous
	]

	;@@ won't be needed in R/S
	call: reduce [path: to path! name]					;@@ in Red - impossible to add refinements to function literal
	
	get-value: [
		either block? :args [
			select/skip args to set-word! word 2
		][
			w1: to word! word
			all [
				not w1 =? w2: bind w1 :args				;-- if we don't check it, binds to global ctx
				get/any w2
			]
		]
	]

	use-words?: yes
	foreach word spec-of :fun [
		;@@ the below part will be totally different in R/S,
		;@@ hopefully just setting values at corresponding offsets
		type: type? word
		case [
			type = refinement! [
				if set/any 'use-words? do get-value [append path to word! word]
			]
			not use-words? []							;-- refinement is not set, ignore words
			type = word!     [repend call ['quote do get-value]]
			;@@ extra work that won't be needed in R/S:
			type = lit-word! [append call as paren! reduce [do get-value]]
			type = get-word! [repend call [do get-value]]
			;@@ type checking - where? should interpreter do it for us?
		]
	]
	; print ["Constructed call:" mold call]
	do call
]

#hide []

; value: "d"
; probe apply find [series: "abcdef" value: value only: case: yes]

; probe apply find object [series: "abcde" value: "d" only: case: yes]

; my-find: function spec-of :find [
	; case: yes
	; only: no
	; apply find 'only
; ]
; probe my-find/only "abcd" "c"

;; <<<<<<<<<< %../common/new-apply.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [for-each map-each remove-each]]]

;; >>>>>>>>>> %../common/new-each.red >>>>>>>>>


; recycle/off

#do [if block? :included-scripts [append included-scripts [hide]]]

;; >>>>>>>>>> %hide-macro.red >>>>>>>>>


#macro [#hide block!] func [[manual] s e] [				;-- allow macros within local block!
	remove/part insert s compose/deep/only [do reduce [function [] (s/2)]] 2
	s													;-- reprocess
]


;; <<<<<<<<<< %hide-macro.red <<<<<<<<<


; #include %error-macro.red
; #include %setters.red
; #include %selective-catch.red
; #include %reshape.red

; #include %show-trace.red

for-each: map-each: remove-each: none
context [
	;-- this should be straightforward and fast in R/S
	;-- one particular side effect of type checking is we can avoid/accept `none` we get when outside series limits
	types-match?: function [
		"Check if items in SERIES match TFILTER"
		ii [object!]
	][
		s: skip ii/series ii/offset
		foreach i ii/tfilter-idx [
			unless find ii/tfilter/:i type? :s/:i [return no]
		]
		yes
	]

	;-- this should also be a piece of cake
	;-- again, value can be used to filter in/out `none` values outside series limits
	values-match?: function [
		"Check if items in SERIES match VFILTER for all chosen VFILTER-IDX"
		ii [object!]
	][
		op: :ii/cmp
		s: skip ii/series ii/offset
		foreach i ii/vfilter-idx [
			unless :s/:i op :ii/vfilter/:i [return no]
			if tail? at s i [return no]					;-- special case: after-the-tail `none` should not count as sought value=none
		]												;@@ TODO: raise this design question in docs
		yes
	]
	; #assert [r: values-match? [1 2 3] [   ] [3 2 3] := 'r]
	; #assert [r: values-match? [1 2 3] [3  ] [3 2 3] := 'r]
	; #assert [r: values-match? [1 2 3] [2 3] [3 2 3] := 'r]

	ranges!:   make typeset! [integer! pair!]			;-- supported non-series types
	is-range?: func [x] [find ranges! type? :x]

	;; helpers for non-series types (ranges) iteration:
	int2pair: func [i [integer!] w [integer!]] [1x1 + as-pair  i - 1 % w  i - 1 / w]
	fill-with-ints: function [spec [block!] from [integer!] dim [integer!]] [
		foreach w spec [
			set w all [from <= dim  from]				;-- none after the 'tail'
			from: from + 1
		]
	]
	fill-with-pairs: function [spec [block!] from [integer!] dim [pair!]] [
		foreach w spec [
			xy: int2pair from dim/x
			set w all [xy/y <= dim/y  xy]				;-- none after the 'tail'
			from: from + 1
		]
	]
	append-ints: function [tgt [block!] from [integer!] count [integer!]] [
		loop count [
			append tgt from
			from: from + 1
		]
	]
	append-pairs: function [tgt [block!] from [integer!] count [integer!] dim [pair!]] [
		loop count [
			append tgt int2pair from dim/x
			from: from + 1
		]
	]

	;; `compose` readability helper - won't be needed in RS
	when: make op! func [value test] [either :test [:value][[]]]


	;-- this structure is required to share data between functions
	;-- (although it's one step away from a proper iterator type)
	;-- in R/S it will be set by foreach and used by foreach-next
	iteration-info!: object [
		matched?:    no
		offset:      0				;-- zero-based; cannot (easily) be series, as need to be able to point past the end or before the head
		iter:        0

		spec:        none
		series:      none
		code:        none
		cmp:         none
		fill:        none			;-- how many words to fill in the spec at every iteration - if series is shorter, fails
		width:       0				;-- how many words are in the spec (to fill)
		step:        none			;-- none value is used to detect duplicate pipes; <0 if iterating backward
		vfilter:     none			;-- none when filter is not used
		vfilter-idx: none
		tfilter:     none			;-- none when filter is not used
		tfilter-idx: none
		pos-word:    none
		idx-word:    none
	]

	fill-info: function [
		spec [word! block!]
		series [series! map! pair! integer!]
		code [block!]
		back-flag [logic!]
		case-flag [logic!]
		same-flag [logic!]
	][
		if case [
			integer? series [series <= 0]
			pair?    series [any [series/x <= 0 series/y <= 0]]
			'else [empty? series]
		] [return none]			;-- optimization; also works for /reverse, as we don't go before the current index

		on-series?: series? series
		if map? series [
			series: to hash! series
			forall series [								;@@ temporary adjustment - won't be needed in RS
				if set-word? :series/1 [series/1: to word! series/1]
			]
		]

		ii: copy iteration-info!
		ii/spec:   spec: compose [(spec)]
		ii/series: series
		ii/code:   copy/deep code						;-- copy/deep or binding will be shared on recursive calls!
		ii/cmp: get pick pick [[=? =?] [== =]] same-flag case-flag
		if all [same-flag case-flag] [
			ERROR "/case and /same refinements are mutually exclusive"
		]

		switch type?/word spec/1 [						;@@ TODO: consider supporting both iteration and position?
			set-word! [
				ii/pos-word: to word! spec/1
				unless on-series? [						;-- fail on ranges and maps (latter cannot be modified as series)
					ERROR "Series index can only be used when iterating over series"
				]
				remove spec
			]
			refinement! [
				ii/idx-word: to word! spec/1
				remove spec
			]
		]

		ii/vfilter:     copy []
		ii/tfilter:     copy []
		ii/vfilter-idx: copy []
		ii/tfilter-idx: copy []
		while [not tail? spec] [
			value: types: none
			switch/default type?/word spec/1 [
				paren! [
					if is-range? series [				;-- complicates filter and makes little sense
						ERROR "Cannot use value filters on ranges"
					]
					set/any 'value do spec/1
					append ii/vfilter-idx index? spec
					change spec anonymize '_ none		;-- at R/S side it will be just dumb loop rather than single `set`
				]
				word! [
					case [
						spec/1 = '| [
							if ii/step [ERROR "Duplicate pipe in spec"]
							ii/fill: yes
							ii/step: -1 + index? spec
							; if ii/step = 0 [ERROR ""]	;@@ error or not? one can use such loop to advance manually
							remove spec
							continue					;-- don't add this entry
						]
						block? spec/2 [
							if is-range? series [		;-- pointless: we always know the item type in ranges
								ERROR "Cannot use type filters on ranges"
							]
							;@@ TODO: use single typesets and types as is, without allocating a new typeset
							types: make typeset! spec/2
							append ii/tfilter-idx index? spec
							remove next spec
						]
					]
				]
			][
				ERROR "Unexpected occurrence of (mold spec/1) in spec"
			]
			append/only ii/vfilter :value
			append/only ii/tfilter :types
			spec: next spec
		]												;-- spec is now native-foreach-compatible
		spec: head spec
		if empty? spec [ERROR "Spec must contain at least one mandatory word"]

		
		

		if empty? ii/tfilter-idx [ii/tfilter: ii/tfilter-idx: none]		;-- disable empty filters
		if empty? ii/vfilter-idx [ii/vfilter: ii/vfilter-idx: none]

		ii/width: length? spec
		ii/step: any [ii/step ii/width]
		ii/fill: either ii/fill [ii/width][1]
		if all [0 = ii/step  not ii/pos-word] [
			ERROR "Zero step is only allowed with series index"			;-- otherwise deadlocks
		]

		ii/offset: 0
		if back-flag [									;-- requires step known
			n: case [
				integer? series [series]
				pair? series [series/x * series/y]
				'else [length? series]
			]
			n: n - ii/fill								;-- ensure needed number of words is filled
			; n: round/floor/to n max 1 ii/step			;-- align to step
			n: n - (n % max 1 ii/step)					;-- align to step
			if pair? p: series [n: as-pair  n % p/x  n / p/x]
			ii/offset: n
		]

		if back-flag [ii/step: 0 - ii/step]

		;@@ in R/S we won't need this, as `function` supports `foreach`:
		anon-ctx: construct collect [
			foreach w spec [keep to set-word! w]
			if ii/pos-word [keep to set-word! ii/pos-word]
			if ii/idx-word [keep to set-word! ii/idx-word]
		]
		bind ii/spec anon-ctx
		if ii/pos-word [ii/pos-word: bind ii/pos-word anon-ctx]
		if ii/idx-word [ii/idx-word: bind ii/idx-word anon-ctx]
		bind ii/code anon-ctx

		ii					;-- fill OK
	]


	more-of?: function [ii [object!] size [integer!]] [
		either ii/step < 0 [
			ii/offset >= 0
		][
			case [
				pair? ii/series [
					ii/series/x * ii/series/y - ii/offset >= size
				]
				integer? ii/series [
					ii/series - ii/offset >= size
				]
				'else [
					(length? ii/series) - ii/offset >= size	;-- supports series length change during iteration
				]
			]
		]
	]

	more-items?: function [ii [object!]] [more-of? ii 1]
	more-iterations?: function [ii [object!]] [more-of? ii ii/fill]

	copy-to: function [
		"Append a part of II/series into TGT"
		tgt  [series!]
		ii   [object!] "iterator info"
		ofs  [integer! series!] "from where to start a copy"
		part [integer! series! none!] "number of items or offset; none for unbound copy"
	][
		case [
			series? ii/series [
				src: skip ii/series ofs
				part: either part [
					copy/part src part					;@@ append/part doesn't work - #4336
				][	copy      src						;-- still need a copy so series is not shared (in case appending a string to block)
				]
				if vector? part [part: to [] part]		;@@ workaround: append block vector enforces /only
				append tgt part
			]
			integer? ii/series [
				unless part [part: ii/series - ofs - 1]
				append-ints  tgt 1 + ofs part
			]
			'pair [
				unless part [part: ii/series/x * ii/series/y - ofs - 1]
				append-pairs tgt 1 + ofs part ii/series
			]
		]
	]


	;@@ should maps iteration be restricted to [k v] or not?
	;@@ I don't like arbitrary restrictions, but here it's a question of how easy it will be
	;@@ to support unrestricted iteration in possible future implementations of maps
	;@@ leave this question in docs!

	{
		for-each allows loop body to modify `pos:` and then possibly call `continue`
		in R/S we'll be able to catch `continue` directly
		in Red it's tricky: need to not let `continue` mess index logic, and yet allow `break` somehow
		the only solution I've found is to save the pos-word, then check it for changes before each iteration
	}

	for-each-core: function [
		ii [object!] "iteration info"
		on-iteration [block!] "evaluated when spec matches"
		after-iteration [block!] "evaluated after on-iteration succeeds and offsets are updated"
		/local new-pos
	][
		upd-pos-word?: [								;-- code that reads user modifications of series position
			if ii/pos-word [
				set/any 'new-pos get/any ii/pos-word
				unless series? :new-pos [
					ERROR "(ii/pos-word) does not refer to series"
				]
				unless same? head new-pos head ii/series [	;-- most likely it's a bug, so we report it
					ERROR "(ii/pos-word) was changed to another series"
				]
				ii/offset: offset? ii/series new-pos
			]
		]

		to-next-possible-match: [						;-- by default tries to match series at every step
			if more-iterations? ii [ii/iter: ii/iter + 1]
		]
		if all [										;-- however when vfilter is defined...
			ii/vfilter									;-- we can use find to faster locate matches, esp. on hash & map
			ii/step <> 0								;-- but step=0 means find direction is undefined and can't benefit from this optimization
		][
			val-ofs: ii/vfilter-idx/1
			val: ii/vfilter/:val-ofs
			if typeset? :val [							;@@ #4911 - typeset is too smart - this is a workaround
				val: compose [(val)]					;@@ however this still disables hash advantages
				no-only?: yes							;@@ to be removed once #4911 is fixed
			]
			|skip|: absolute ii/step

			if all [
				ii/step < 0									;-- when going backwards
				tail? at skip ii/series ii/offset val-ofs	;-- and sought value is after the tail
			][
				ii/offset: ii/offset - |skip|				;-- then we can skip this iteration already
				ii/iter: ii/iter + 1						;-- as after-the-tail `none` does not count as value `none`
			]
			;-- this special case may be disabled
			;-- but then `from` may be misaligned with `/skip` as Red doesn't allow after-the-tail positioning
			;-- so if disabled, it will require special index adjustment during first two iterations (should be easier in RS)

			find-call: as path! compose [				;-- construct a relevant `find` call
				find
				skip
				('reverse when (ii/step < 0))
				('only when not no-only?)				;@@ /only disables "type!" smarts, but not "typeset!" - #4911
				('case when (:ii/cmp =? :strict-equal))
				('same when (:ii/cmp =? :same?))
			]

			to-next-possible-match: reshape [
				all [
					pos: @[find-call] from: at skip ii/series ii/offset val-ofs :val |skip|
					ii/offset: (index? pos) - val-ofs
					more-iterations? ii
					ii/iter: add  ii/iter  (offset? from pos) / ii/step
				]
			]
		]

		catch-a-break [									;@@ destroys break/return value
			while to-next-possible-match [
				;-- do all updates before calls to `continue` are possible
				case [
					ii/pos-word [set ii/pos-word skip ii/series ii/offset]
					ii/idx-word [set ii/idx-word ii/iter]	;-- unfortunately with this design, image does not get a pair index
				]

				;-- do filtering
				if ii/matched?: all [
					any [not ii/tfilter  types-match? ii]
					any [not ii/vfilter  values-match? ii]
				][
					;-- fill the spec - only if matched
					case [
						series?  ii/series [foreach (ii/spec) skip ii/series ii/offset [break]]
						integer? ii/series [fill-with-ints  ii/spec 1 + ii/offset ii/series]
						'pair              [fill-with-pairs ii/spec 1 + ii/offset ii/series]
					]
					catch-continue [
						continued?: yes
						do on-iteration
						continued?: no
					]
				]

				do upd-pos-word?
				ii/offset: ii/offset + ii/step
				if all [ii/matched? not continued?] after-iteration
			]
		]
	]

	;-- the frontend
	set 'for-each function [
		[no-trace]
		"Evaluate CODE for each match of the SPEC on SERIES"
		'spec  [word! block!]                "Words & index to set, values/types to match"
		series [series! map! pair! integer!] "Series, map or limit"
		code   [block!]                      "Code to evaluate"
		/reverse "Traverse in the opposite direction"
		/case    "Values are matched using strict comparison"
		/same    "Values are matched using sameness comparison"
		/local r
	][
		unset 'r										;-- returns unset by default (empty series, fill-info failed)
		if ii: fill-info spec series code reverse case same [
			for-each-core ii [
				if ii/matched? [						;-- not matched iterations do not affect the result
					unset 'r							;-- in case of `continue`, result will be unset
					set/any 'r do ii/code
				]
			] []
		]
		:r
	]

	set 'map-each function [
		[no-trace]
		"Map SERIES into a new one and return it"
		'spec  [word! block!]                "Words & index to set, values/types to match"
		series [series! map! pair! integer!] "Series, map or range"
		code   [block!]                      "Should return the new item(s)"
		/only "Treat block returned by CODE as a single item"
		/eval "Reduce block returned by CODE (else includes it as is)"
		/drop "Discard regions that didn't match SPEC (else includes them unmodified)"
		/case "Values are matched using strict comparison"
		/same "Values are matched using sameness comparison"
		/self "Map series into itself (incompatible with ranges)"
		/local part
	][
		all [
			self
			scalar? series								;-- change/part below relies on this error
			ERROR "/self is only allowed when iterating over series or map"
		]

		;-- where to collect into: always a block, regardless of the series given
		;-- because we don't know what type the result should be and block can be converted into anything later
		buf: make [] system/words/case [				;-- try to guess the length
			integer? series [series]
			pair? series [series/x * series/y]
			'else [length? series]
		]
		if all [eval not only] [red-buf: copy []]		;-- buffer for reduce/into
		;@@ TODO: trap & rethrow errors (out of memory, I/O, etc), ensuring buffers are freed on exit

		;-- in map-each ii/step is never negative as it does not support backwards iteration
		add-skipped-items: [skip-bgn: skip-end]
		add-rest: []
		unless drop [
			add-skipped-items: [
				if skip-end > skip-bgn [				;-- can be <= in case of step=0 or user intervention - in this case don't add anything
					copy-to buf ii skip-bgn skip-end - skip-bgn
				]
				skip-bgn: skip-end
			]
			add-rest: [
				ii/offset: skip-bgn						;-- offset used by `more-items?`
				if more-items? ii [copy-to buf ii skip-bgn none]
			]
		]

		if ii: fill-info spec series code no case same [	;-- non-empty series/range?
			skip-bgn: ii/offset
			for-each-core ii [
				skip-end: ii/offset						;-- remember skipped region before ii/offset changes in iteration code
				set/any 'part do ii/code
				if all [eval block? :part] [			;-- /eval only affects block results by design (for more strictness)
					part: either only [					;-- has to be reduced here, in case it calls continue or break, or errors
						reduce      part				;-- /only has to allocate a new block every time
					][	reduce/into part clear red-buf	;-- else this can be optimized, but buf has to be cleared every time in case it gets partially reduced and then `continue` fires
					]
				]
			][
				do add-skipped-items					;-- by putting it here, we can group multiple `continue` calls into a single append
				either only [append/only buf :part][append buf :part]
				;-- `max` is used to never add the same region twice, in case user rolls back the position:
				skip-bgn: skip-end: max skip-end ii/offset
			]
			do add-rest									;-- after break or last continue, add the rest of the series

			;-- to avoid O(n^2) time complexity of in-place item changes (e.g. inserted item length <> removed),
			;-- original series is changed only once, after iteration is finished
			;-- this produces a single on-deep-change event on owned series
			;-- during iteration, intermediate changes will not be detected by user code
			if self [
				either map? series [
					extend clear series buf
				][
					change/part series buf tail series
				]
			]
		]												;-- otherwise, empty series: buf is already empty

		;@@ TODO: in R/S free the `red-buf` here (not possible in Red)
		either self [ 									;-- even if never iterated, a block or series is returned
			;@@ TODO: in R/S free the `buf` here (not possible in Red)
			series
		][
			buf											;-- no need to free it
		]
	]

	;@@ TODO: maps require a special fill function so keys don't appear as set-words, also to avoid a copy
	;@@ at RS level it's a hash so it'll be easier there
	;@@ so, map at least should be converted into a hash, not block
	set 'remove-each function [
		[no-trace]
		"Remove parts of SERIES that match SPEC and return a truthy value"
		'spec  [word! block!]                "Words & index to set, values/types to match"
		series [series! map! pair! integer!] "Series, map or range"
		code   [block!]                      "Should return the new item(s)"
		/drop "Discard regions that didn't match SPEC (else includes them unmodified)"
		/case "Values are matched using strict comparison"
		/same "Values are matched using sameness comparison"
		/local part
	][
		unless ii: fill-info spec series code no case same [	;-- early exit - series is empty
			return either any [series? series map? series] [series] [copy []]
		]

		;-- where to collect into: always a block, regardless of the series given
		;-- because we don't know what type the result should be and block can be converted into anything later
		buf: make [] system/words/case [				;-- try to guess the length
			integer? series [series]
			pair? series [series/x * series/y]
			'else [length? series]
		]
		;@@ TODO: trap & rethrow errors (out of memory, I/O, etc), ensuring `buf` is freed on exit

		skip-bgn: ii/offset
		for-each-core ii [
			skip-end: ii/offset							;-- remember skipped region before ii/offset changes in iteration code
			set/any 'drop-this? do ii/code
		][
			unless drop [copy-to buf ii skip-bgn skip-end - skip-bgn]
			unless :drop-this? [copy-to buf ii skip-end ii/step]
			skip-bgn: skip-end: ii/offset
		]
		unless drop [copy-to buf ii skip-bgn none]

		;-- to avoid O(n^2) time complexity of in-place item removal,
		;-- original series is changed only once, after iteration is finished
		;-- this produces a single on-deep-change event on owned series
		;-- during iteration, intermediate changes will not be detected by user code
		system/words/case [
			series? series [
				either any-string? series [
					change/part series rejoin buf tail series		;@@ just a workaround for #4913 crash
				][
					change/part series        buf tail series
				]
			]
			map? series [
				extend clear series buf
			]
			'ranges [
				return buf								;-- no need to free it
			]
		]
		;@@ TODO: in R/S free the buffer (not possible in Red)
		series
	]

]


#hide []



;; <<<<<<<<<< %../common/new-each.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [modulo]]]

;; >>>>>>>>>> %../common/modulo.red >>>>>>>>>



; #include %hide-macro.red
; #include %assert.red

modulo: //: mod: none
context [
	abs: :absolute
	positives!: make typeset! [char! tuple!]				;-- limited types (can't be negated)
	roundable!: make typeset! [float! time!]				;-- types that may be rounded

	set 'modulo function [
		"Returns a modulo R of A divided by B. Defaults to Euclidean definition of modulo (R >= 0)"
		a [number! char! pair! any-point! tuple! vector! time!]
		b [number! char! pair! any-point! tuple! vector! time!]
		/floor "Follow the Floored definition: sgn(R) = sgn(B)"
		/trunc "Follow the Truncated definition: sgn(R) = sgn(A)"
		/round "Round near-terminal results (e.g. near zero or near B) to zero"
		; return: [number! char! pair! tuple! vector! time!] "Same type as A"
	][
		

		r: a % b
		case [
			find positives! type? a [
				
			]
			trunc   []
			floor   [r: r + b % b]
			'euclid [|b|: abs b  r: r + |b| % b]
		]

		;; integral types just skip rounding
		;; in vectors we would have to round every item separately, which is inefficient, so we skip them too
		if all [round  find roundable! type? r] [		;-- force result to satisfy `0 <= abs(r) < abs(b)` equation
			|b|:  any [|b| abs b]
			|r|+|b|: |b| + abs r
			if any [
				|r|+|b| - |b| == |b|					;-- result is near b, as it turns into b with r+b-b
				|r|+|b| + |b| == (|b| * 2)				;-- result is near 0, as it gets lost by appending 2b
														;-- (r+2b=2b is more aggressive than r+b=b, for symmetry with r+b-b)
			][
				r: r * 0								;-- zero multiplication preserves the original type and sign (even zero sign)
			]
		]

		r
	]

	set '// make op! set 'mod func [
		"Returns a modulo R of A divided by B, following Euclidean definition of it (R >= 0)"
		a [number! char! pair! any-point! tuple! vector! time!]
		b [number! char! pair! any-point! tuple! vector! time!]
		; return: [number! char! pair! any-point! tuple! vector! time!] "Same type as A"
	][
		modulo a b
	]
]

;@@ TODO: Linux and esp. ARM may produce different results for floats, and may need tests update

#hide []
;; <<<<<<<<<< %../common/modulo.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [interleave]]]

;; >>>>>>>>>> %../common/interleave.red >>>>>>>>>


; #include %reshape.red

interleave: context [											;-- this is a similar design, just uses list items instead of the delimiter
	;@@ use map-each when it's native instead of this mess
	in1-list: make [] group: 128
	in2-list: make [] group
	mix-list: make [] group * 2
	dlm-list: make [] group * 2
	i: repeat i group [
		append in1-list to word! rejoin ["x" i]
		append in2-list to word! rejoin ["y" i]
		repend mix-list [
			to get-word! rejoin ["x" i]
			to get-word! rejoin ["y" i]
		]
		repend dlm-list [
			to get-word! rejoin ["x" i]
			quote :series2
		]
	]
	
	;; lists are inlined in this function for two reasons:
	;; - so all the words become local to it (for reentrancy)
	;; - so the func is easy to copy
	;; but it hurts readability badly...
	return function [ 
		"Interleave the items of two series"
		series1 [any-list!]										;@@ `reduce` and `set` don't work on strings... hence the type limitation
		series2 [any-type!] "When not a list, repeated as a single value"
		/between "Treat series2 as a single value and omit it at the tail"
		/into result [any-list!] "Provide an output buffer"
		; /into result: (make block! 2 * length? series1) [series!]
	] reshape [
		n: length? series1
		unless result [result: make block! 2 * n]
		if zero? n [return result] 
		; #assert [any [between  equal? length? series1 length? series2]]	;@@ accept unequal? fill with 'none'?
		either any [between not any-list? :series2] [			;-- delimit mode
			if 0 < trail: n % @(group) [
				rest: @(group) - trail
				set (skip @[in1-list] rest) series1
				reduce/into (skip @[dlm-list] rest * 2) tail result
			]
			series1: skip series1 trail
			foreach @[in1-list] series1 [
				reduce/into @[dlm-list] tail result
			]
			if between [take/last result]
		][														;-- interleave mode
			if 0 < trail: n % @(group) [
				rest: @(group) - trail
				set (skip @[in1-list] rest) series1
				set (skip @[in2-list] rest) series2
				reduce/into (skip @[mix-list] rest * 2) tail result
			]
			series1: skip series1 trail
			series2: skip series2 trail
			foreach @[in1-list] series1 [
				set @[in2-list] series2
				series2: skip series2 @(group)
				reduce/into @[mix-list] tail result
			]
		]
		result
	]
]




comment {
	;; these simple versions become slower after 10 items, and up to 4x slower after 100 items
	;; only append variant does not require an intermediate buffer for string output, but it's a tiny speedup
	
	delimit1: function [
		"Insert delimiter between all items in the list"
		list      [any-list!]
		delimiter [any-type!]
		/into result: (make block! 2 * length? list) [series!]
	][
		parse list [collect after result [keep skip any [end | keep (:delimiter) keep skip]]]
		result
	]
	
	delimit2: function [
		"Insert delimiter between all items in the list"
		list      [any-list!]
		delimiter [any-type!]
		/into result: (make block! 2 * length? list) [series!]
	][
		append/only result :list/1
		foreach item next list [append/only append/only result :delimiter :item]
		result
	]
	
	delimit3: function [
		"Insert delimiter between all items in the list"
		list  [any-list!]
		delim [any-type!]
		/into result: (make block! 2 * length? list) [series!]
	] reshape [
		append/only result :list/1
		foreach item next list [reduce/into [:delimiter :item] tail result]
		result
	]
}

;; <<<<<<<<<< %../common/interleave.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [join]]]

;; >>>>>>>>>> %../common/join.red >>>>>>>>>


; #include %delimit.red

join: function [
	"Delimit a list and join as a string"
	list  [any-list!]
	delim [any-type!]
][
	to string! interleave/between list :delim
]


;; <<<<<<<<<< %../common/join.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [split]]]

;; >>>>>>>>>> %../common/split.red >>>>>>>>>


; #include %assert.red
; #include %error-macro.red
; #include %with.red

split: :system/words/split
splitting: context [
	skip?: func [series [series!]] [-1 + index? series]	;@@ split this out?
	by: make op! :as-pair								;@@ split this out?
	
	;@@ support true/false (slow) finders like :< ? unary finders like :odd? ?
	split-by-finder: function [
		series [series!]
		mode   [word!] ;(find [by around before after slice] mode)
		finder [any-function!] ;(2 = preprocessor/func-arity? spec-of :finder)
		result [any-block!]
	][
		
		if mode = 'before [bgn: 1]
		pos:   1
		range: 0x0
		
		state: make [] 2								;-- lets finder initialize itself
		while [range: finder at series pos: pos + range/2 state] switch mode [
			by     [[append result 0 by range/1 + pos]]
			after  [[append result 0 by range/2 + pos]]
			before [[append result bgn by bgn: pos + range/1]]
			around [[append append result 0 by range/1 + pos range + pos]]
			slice  [[append result range + pos]]
		]
		if mode = 'before [pos: bgn]
		
		if mode <> 'slice [append result as-pair pos 1 + length? series]
		forall result [result/1: copy/part series result/1]
		result
	]
	
	#hide []
	
	split-by-rule: function [
		series [series!]
		mode   [word!] ;(find [by around before after] mode)
		rule   [series! char! bitset! datatype! typeset!]
		result [any-block!]
		/case
	][
		finder: [to rule delim: rule end:]
		keeper: switch mode [
			by     [ [keep (copy/part start delim) (start: end)] ]
			before [ [keep (copy/part start start: delim)] ]
			after  [ [keep (copy/part start start: end)] ]
			around [ [keep (copy/part start delim) keep (copy/part delim start: end)] ]
			slice  [ [keep (copy/part delim start: end)] ]
		]
		parse/:case series [
			collect after result [
				start: any [finder keeper] to end if (mode <> 'slice) keep (copy start)
			]
		]
		result
	]
	
	
	
	set 'split function [
		series    [series!]   "Series to be split"
		delimiter [any-type!] "Use integer!/float! for parts of absolute, and percent! - of relative length"
		; /by     "Exclude delimiter from results"
		/before "Split before the delimiter"
		/after  "Split after the delimiter"
		; /around "Split both before and after the delimiter"
		/rule   "Treat delimiter as parse rule"
		/slices "Treat delimiter as a list of slices; also makes /rule keep matches instead"
		/only   "Treat token as a single value when splitting any-block! series"
		/case   "Use case sensitive comparison"
		/same   "Use sameness comparison (incompatible with /rule)"
		/into result [any-block!] "A buffer to write into"
		;; incompatible refinements:
		;; /same and /rule - parse has no sameness check
		;; /case and /same - different modes
		;; /only and /rule - /only is only meaningful for normal delimiters ?
		;; /by /before /after /around /slices - different modes
		;; /slices w/o /rule and any of /only /case /same - they have no meaning for slice lengths
	][
		;@@ check refinements compatibility
		unless result   [result: make [] sqrt length? series]
		if tail? series [return append/only result copy series]
		mode: either slices ['slice][pick pick [[around before] [after by]] before after]
		any [
			if rule [
				if only [delimiter: reduce ['quote :delimiter]]
				split-by-rule/:case series mode :delimiter result
			]
			if slices [
				unless block? :delimiter [delimiter: reduce [:delimiter]]
				split-by-finder series 'slice :list-slicer result
			]
			unless only [
				switch type?/word :delimiter [
					integer! [									;-- parts of given fixed length
						if delimiter <= 0 [ERROR "Invalid part length: (delimiter)"]
						split-by-finder series 'by :integer-slicer result
					]
					float!										;-- parts of given fixed length
					percent! [									;-- parts of relative length
						if delimiter <= 0 [ERROR "Invalid part length: (delimiter)"]
						if percent? delimiter [delimiter: to float! delimiter * length? series]
						split-by-finder series 'by :float-slicer result
					]
					function! native! action! routine! [		;-- custom finder func
						split-by-finder series mode :delimiter result
					]
					op! [										;-- adjacent items comparator
						split-by-finder series 'by :op-slicer result
					]
				]
			]
			;; no type in switch above leads here too
			if any-string? series [								;-- parse splitting is faster for strings
				unless bitset? :delimiter [delimiter: form delimiter]
				split-by-rule/:case series mode :delimiter result
			]
			split-by-finder series mode :delimiter-slicer result
		]
		result
	]
	
	;; factory default finder functions...
	
	integer-slicer: function [pos [series!] state [block!] "unused"] with :split [
		if delimiter < length? pos [1x1 * delimiter]
	]
	
	;; state format:
	;;   1. integer! length added so far
	;;   2. integer! limit for end detection
	float-slicer: function [pos [series!] state [block!]] with :split [
		unless state/1 [
			n: round/ceiling/to n': (length? series) / delimiter 1
			if n' + 1 = n [n: n - 1]					;-- fix for rounding of epsilon (split "1234567890" 100% / 3 case)
			append append state 0 n 
		]
		;; flooring gives more expected results eg on split "12345" 1.5: ["1" "23" "4" "5"] vs ["12" "3" "45" ""]
		end: to integer! delimiter * state/1: state/1 + 1
		if state/1 < state/2 [1x1 * (end - skip? pos)]
	]
	
	op-slicer: function [pos [series!] state [block!] "unused"] with :split [
		end: next pos: next pos
		forall end [
			if :end/-2 delimiter :end/-1 [
				return 1x1 * offset? pos end
			]
		]
		none
	]
	
	;; state format: 1. delimiter length in source series
	delimiter-slicer: function [pos [series!] state [block!]] with :split [
		if bgn: find/:case/:same/:only pos :delimiter [
			unless state/1 [
				end: find/:case/:same/:only/match/tail bgn :delimiter
				append state offset? bgn end
			]
			0 by state/1 + offset? pos bgn
		]
	]
	
	list-slicer: function [pos [series!] state [block!] "unused" /extern delimiter] with :split [
		switch/default type?/word also range: :delimiter/1 delimiter: next delimiter [
			integer! [0 by range]						;-- just slice length
			pair!    [range/1 * 0x1 + range]			;-- slice begin and end
			none!    [none]								;-- range = none at list tail, terminating the search
		][												;-- single delimiter
			bgn: find/:only/:case/:same pos :delimiter
			end: find/:only/:case/:same/match bgn :delimiter
			(0 by offset? bgn end) + offset? pos bgn
		]
	]
]

#hide []
	
;; <<<<<<<<<< %../common/split.red <<<<<<<<<

		
;; >>>>>>>>>> %../common/is-face.red >>>>>>>>>



; #include %map-each.red

is-face?: none
if object? :face! [										;-- for non-view-enabled builds
	context [
	
		set 'is-face? function [
		    "Test if VALUE is a face! instance"
		    value      "Value to test"
		    /alive     "Return TRUE only if the face has a low-level handle"
		    ; return:	[logic!]
		][
			to logic! all [
				object? :value
				any [
					(class-of value) = class-of face!
					all tests
				]
				any [
					not alive
					all [
						block? state: select value 'state
						handle? first state
					]
				]
			]
		]
	
		tests: map-each/eval w words-of face! [[
			'in bind 'value :is-face? to lit-word! w
		]]
	]
]

comment {
	this version is 2x faster but it allocates ~440 bytes per call!

	model: words-of face!
	set 'is-face? function [
	    "Test if VALUE is a face! instance"
	    value      "Value to test"
	    /alive     "Return TRUE only if the face has a low-level handle"
	    ; return:	[logic!]
	][
		to logic! all [
			object? :value
			any [
				(class-of value) = class-of face!
				find/match words-of value model			;@@ words-of allocates, unfortunately, ~400b per call
			]
			any [
				not alive
				all [
					block? state: select value 'state
					handle? first state
				]
			]
		]
	]

	
}
;; <<<<<<<<<< %../common/is-face.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [color-models]]]

;; >>>>>>>>>> %../common/color-models.red >>>>>>>>>


; #include %assert.red
; #include %hide-macro.red

;@@ consider moving these out into another module
;; these are designed to be statistically neutral:
;; 0/255    1/255    2/255     ..       253/255      254/255      255/255 <- [0,1]
;; ^        ^        ^         ..             ^            ^            ^ <- how byte range maps into [0,1]
;; 0        1        2         ..           253          254          255 <- byte range
;; ^^^^^^^^ ^^^^^^^^ ^^^^^^^^  ..  ^^^^^^^^^^^^ ^^^^^^^^^^^^ ^^^^^^^^^^^^ <- how [0,1] maps into byte range
;; 0..1/256 1..2/256 2..3/256  ..  253..254/256 254..255/256 255..256/256 <- [0,1]
;; so each 1/256th inteval during roundtrip conversion collapses into a point in the same interval
;; this point's offset within the inteval is (N-1)/(255*256) where N is the interval number 1-256
;; but most importantly 0 maps to 0 and 1 to 1, to have pure black/white colors during color conversion
to-byte: function [
	"Convert VALUE from [0,1] range into a byte [0..255]"
	value [number!]
][
	to integer! value * 255.999'999'999'999				;-- 256 would round contested values up
]
from-byte: function [
	"Convert byte value [0..255] into [0,1] range"
	value [integer!]
][
	value / 255
]

#hide [
	
]

;@@ consider moving these out into another module
tuple->point: function [
	"Convert tuple into a point3D"
	tuple [tuple!]
][
	as-point3D
		from-byte tuple/1
		from-byte tuple/2
		from-byte tuple/3
]
point->tuple: function [
	"Convert point3D into a tuple"
	point [point3D!]
][
	as-color											;@@ this routine may overflow if > 255 - need bounds checking
		to-byte point/1
		to-byte point/2
		to-byte point/3
]

;; https://en.wikipedia.org/wiki/HSL_and_HSV#Color_conversion_formulae
RGB->HSL: RGB2HSL: function [
	"Convert colors from RGB(1,1,1) into HSL(360,1,1) color model"
	RGB [point3D! tuple!] "0-1 each if point"
	/tuple "Return as a 3-tuple"
][
	if tuple? RGB [RGB: tuple->point RGB]
	R: RGB/1  G: RGB/2  B: RGB/3
	X+: max max R G B									;-- max of channels = value
	X-: min min R G B									;-- min of channels
	C:  X+ - X-											;-- chroma
	L:  X+ + X- / 2										;-- lightness
	S:  either C = 0 [0.0][C / 2 / min L 1 - L]			;-- saturation
	H:  60 * case [										;-- hue
		C  =  0 [0.0]
		X+ == R [G - B / C // 6]
		X+ == G [B - R / C +  2]
		X+ == B [r - G / C +  4]
	]
	HSL: as-point3D H S L
	if tuple [HSL: point->tuple HSL / (360,1,1)]
	HSL
]

HSL->RGB: HSL2RGB: function [
	"Convert colors from HSL(360,1,1) into RGB(1,1,1) color model"
	HSL [point3D! tuple!] "0-360 hue, 0-1 others if point"
	/tuple "Return as a 3-tuple"
][
	if tuple? HSL [HSL: (360,1,1) * tuple->point HSL]
	H: HSL/1 // 360  S: HSL/2  L: HSL/3
	H': H / 60
	C:  S * 2 * min L 1 - L								;-- chroma
	D:  L - (C / 2)										;-- darkest channel
	B:  C + D											;-- brightest channel
	M:  C * (1 - absolute H' % 2 - 1) + D				;-- middle channel
	RGB: switch to integer! H' [
		0 6 [as-point3D B M D]							;-- 6=0 - for H=360 case
		1   [as-point3D M B D]
		2   [as-point3D D B M]
		3   [as-point3D D M B]
		4   [as-point3D M D B]
		5   [as-point3D B D M]
	]
	if tuple [RGB: point->tuple RGB]
	RGB
]


#hide []



brightness?: none
context [
	;; gamma (transfer function) comes from https://en.wikipedia.org/wiki/SRGB#Transformation
	gamma-inverse: func [c] [
		either (c: c / 255) <= 0.04045 [c / 12.92][c + 0.055 / 1.055 ** 2.4]
	]
	gamma: func [x] compose/deep [
		either x <= 0.0031308 [x * 12.92][x ** (1 / 2.4) * 1.055 - 0.055]
	]

	;; CIELab L* formula comes from https://stackoverflow.com/a/13558570 
	;; see also https://en.wikipedia.org/wiki/Relative_luminance#Relative_luminance_and_%22gamma_encoded%22_colorspaces
	;; grayscale example:  https://i.gyazo.com/bbdfa22004bc06ecd0cfa1a6276b784b.jpg
	set 'brightness? function [
		"Get brightness [0..1] of a color tuple as CIELAB achromatic luminance L*"
		color [tuple!]
	][
		gamma add add
			0.212655 * gamma-inverse color/1
			0.715158 * gamma-inverse color/2
			0.072187 * gamma-inverse color/3
	]
]


;; <<<<<<<<<< %../common/color-models.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [contrast-with]]]

;; >>>>>>>>>> %../common/contrast-with.red >>>>>>>>>





contrast-with: function [
	"Pick a color that would contrast with the given one"
	color [tuple!]
	/both other [tuple!] "Should contrast with both given colors"
][
	either all [both other <> color] [
		;@@ this should be done in Lab space, otherwise prone to bad choices, esp on blue
		hsl1: RGB2HSL color
		hsl2: RGB2HSL other
		h: hsl1/1 + hsl2/1 / 2									;-- pick hue contrast to the average hue of both
		if (absolute h - hsl1/1) < 90 [h: h + 180 % 360]		;-- pick the longer arc center
		l+: max hsl1/3 hsl2/3
		l-: min hsl1/3 hsl2/3
		l: l+ + l- / 2
		d: l+ - l- / 2											;-- distance from l to both colors lightness
		foreach l' [0.8 0.2] [									;-- pick best of 3 variants of lightness: l1+l2/2, 0.2 and 0.8
			d': min absolute l' - l- absolute l' - l+			;-- distance from l' to closest color lightness
			if d' > d [d: d' l: l']
		]
		HSL2RGB/tuple as-point3D h 1 l							;-- always saturated
	][
		bw: either 0.5 > brightness? color [white][black]		;-- pick black or write: what's more contrast 
		white - color / 5 + (bw * 0.8)							;-- 20% of inverted color + 80% of B/W
	]
]


comment {
	;; Dual color test
	colors: map-each/drop [n t [tuple!]] body-of system/words [to word! n]
	view/tight [
		b1: base "TEXT" bold right b2: base "TEXT" bold left rate 1 on-time [
			b1/color: get probe random/only colors
			b2/color: get probe random/only colors
			b1/font/color: b2/font/color: contrast-with/both b1/color b2/color
		]
	]

	;; Single color test (up to 30% factor works best, but closer to 0% loses hue)
	factor: 5.0
	brightness: func [c] [(c/1 / 240 ** 2) + (c/2 / 200 ** 2) ** 0.5]	;-- doesn't count blue for speed
	contrast-with: function [c][
		bw: either 1 > brightness c [white][black]
		; white - c / 5 + (bw * 0.8)
		(white - c / factor) + (bw * (1.0 - (1.0 / factor)))
	]
	colors: reduce extract load help-string tuple! 2	;-- predefined color selection
	insert colors 75.142.254
	forall colors [if attempt [colors/1/4] [remove colors]]
	; colors: collect [repeat i 100 [keep random white]]	;-- random selection
	view collect [
		keep [sl: slider data 20% focus [factor: 1 / (max 1% face/data)] text react [face/data: 100% / factor sl/data] return]
		n: round/ceiling/to sqrt length? colors 1
		repeat i n [
			repeat j n [
				if c: pick colors i - 1 * n + j [
					keep reduce [
						'base 50x50 "TEXT^/TEXT" c white
						'react [sl/data face/font/color: contrast-with face/color]
					]
				]
			]
			keep 'return
		]
	]
}


;; <<<<<<<<<< %../common/contrast-with.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [keep-type]]]

;; >>>>>>>>>> %../common/keep-type.red >>>>>>>>>



;@@ TODO: more general keep-thing function that can filter on charsets - opposite of trim/all/with
keep-type: function [
	"Make a list including only values of type TYPE from the original LIST"
	list [any-block!]
	type [datatype! typeset!] "Typesets are accepted"
][
	r: clear copy list
	parse list [collect into r any thru keep type]				;-- can use FORPARSE here, but this is faster
	r
]

comment {

	;; this version is 10% slower and is only working in the fast-lexer branch (commit 54a0db76)
	keep-type: function [
		"Make a list including only values of type TYPE from the original LIST"
		list [any-block!]
		type [datatype! typeset!] "Typesets are accepted"
	][
		r: make type? list 10
		while [list: find/tail list type] [append/only r :list/-1]
		r
	]

	;; this version is 2x (or more, depending on the length) times slower
	keep-type: function [
		"Make a list including only values of type TYPE from the original LIST"
		list [any-block!]
		type [datatype! typeset!] "Typesets are accepted"
	][
		remove-each x list: copy list
			either datatype? type
				[[ type <> type? :x ]]
				[[ not find type type? :x ]]
		list
	]
}









;; <<<<<<<<<< %../common/keep-type.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [clip]]]

;; >>>>>>>>>> %../common/clip.red >>>>>>>>>


; #include %assert.red



;@@ remove it if PR #5194 gets merged
clip: func [
	"Return A if it's within [B,C] range, otherwise the range boundary nearest to A"
	a [scalar!] b [scalar!] c [scalar!]
	return: [scalar!]
][
	min max a b max min a b c
]



;; <<<<<<<<<< %../common/clip.red <<<<<<<<<

		
;; >>>>>>>>>> %../common/step.red >>>>>>>>>


; #include %hide-macro.red

step: none
context [
	ref-type!: union any-word! any-path!
	
	set 'step function [
		"Steps (increments) a value or series index by 1"
		target [any-word! any-path! block! hash! vector! binary! image!]
		      "Value referenced must be a series or scalar (incl. within a series)"
		/down "Reverse step direction (decrement)"
		/by   "Change by this amount, instead of 1"
			amount [integer! float! pair! percent! time! tuple! money!] ;-- = exclude [scalar!] [char! date!]
	][
		amount: any [amount 1]
		name:   either find ref-type! type? target [target]['target/1]
		value:  get name
		set name case [
			series?  :value [skip value amount * pick [-1  1 ] down]
			percent? :value [add  value amount * pick [-1% 1%] down]	;-- 1% to avoid /by
			down [:value - amount]										;-- `-` for tuples
			'up  [:value + amount]
		]
	]
]


#hide []

;; <<<<<<<<<< %../common/step.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [count]]]

;; >>>>>>>>>> %../common/count.red >>>>>>>>>




; #include %new-apply.red

count: function [
	"Count occurrences of value in series (using `=` by default)"
	series [series!]									;-- docstrings & arg names mirror FIND action
	value  [any-type!]
	/part "Limit the counting range"
		length [number! series!]
	/only "Treat series and typeset value arguments as single values"
	/case "Perform a case-sensitive search"
	/same {Use "same?" as comparator}
	/skip "Treat the series as fixed size records"
		size [integer!]
	; /reverse only complicates it - use /part instead
	;  also /reverse makes little sense since counting has no direction, while /part adds meaning of counting region
	; /any & /with - TBD in FIND
	; return: [integer!]
][
	n: 0
	reverse: negative? any [length 0] 
	either skip [										;-- /skip support doesn't work with the /tail trick
		while [series: find/:only/:case/:same/:part/:reverse/skip series :value length size] [
			n: n + 1
			series: system/words/skip series size
		]
	][
		while [series: find/:only/:case/:same/:part/:reverse/tail series :value length] [n: n + 1]
	]
	n
]





;; <<<<<<<<<< %../common/count.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [typecheck]]]

;; >>>>>>>>>> %../common/typecheck.red >>>>>>>>>


; #include %assert.red
; #include %setters.red									;-- uses 'anonymize'
; #include %catchers.red
; #include %hide-macro.red


typecheck: none
typechecking: context [
	;; another approach is to put 'do' directly into on-change-dispatch (and bind to it)
	;; but then even unchecked words will pay the price of a function call
	;; and unfortunately, both these approaches are unfit for advanced-function
	;; as it will either become a mold hell, or not copyable (due to use of a bound decorated word for matrix)
	make-check-func: function [field [get-word!] types [block! none!] fallback [paren! none!]] [
		set [types: options:] if types [extract-value-checks types]
		matrix: make-type-matrix field types fallback options
		check: function compose [(to word! field) [any-type!]] compose [
			;; trick here is to use paths (faster), and that needs a word (can't start it with a map)
			;; besides, map is quite big, in case function gets molded (on error?) it's no good
			do (as path! reduce [
				anonymize 'matrix matrix
				as paren! compose [type?/word (field)]
			])
		]
		foreach [key blk] matrix [if block? blk [bind blk :check]]
		:check
	]
	
	;; must return 'none' when check succeeded!
	skeleton: copy []									;@@ use map-each (not using to avoid dependency)
	#hide [
		foreach type to [] any-type! [repend skeleton [type none]]
	]
	skeleton: make map! skeleton
	
	make-type-matrix: function [word [get-word!] types [block! none!] fallback-check [paren! none!] options [block! none!]] [
		matrix:   copy skeleton
		accepted: either types [make typeset! types][any-type!]
		if types [type-error: make-type-error word types]
		foreach [type _] matrix [
			matrix/:type: case [
				not find accepted get type [type-error]
				check: any [
					if pos: find find options type paren! [pos/1]
					fallback-check
				][
					make-value-check word check
				]
			]											;@@ or use remove/key instead of 'none'?
		] 
		matrix
	]
	
	make-value-check: function [field [get-word!] check [paren!]] [
		compose/deep [
			unless (check) [
				form reduce ["Failed" (mold check) "for" type? (field) "value:" mold/flat/part (field) 40]
			]
		]
	]
	
	make-type-error: function [field [get-word!] types [block!]] [
		compose/deep [									;@@ use reshape for this when it's fast
			rejoin [(compose pick [						;-- new-lines matter here
				["Word " (form field) " is locked and cannot be set to " mold/flat/part (field) 40]
				["Word " (form field) " can't accept " type? (field) " value: " mold/flat/part (field) 40 ", only " (mold types)]
			] empty? types)]
		]
	]

	extract-value-checks: function [types [block!] /local check words] [
		typeset: clear []
		options: clear []
		parse types [any [
			copy words some word! (append typeset words)
			opt [
				set check paren! (
					mask: to block! make typeset! words	;-- break typesets into type names
					append/only append options mask check
				)
			]
		]]
		reduce [typeset options]						;-- no copy needed, temporary blocks
	]
	
	

	
	;; each check block is compiled once, saved here, then reused
    memoized-typechecks: make hash! 64
    
    compile-spec: function [spec [block!]] [
		checks: clear []
		parse spec [any [
			set field word! set types opt block! set fallback opt paren! (
				field: to get-word! field
				test:  make-check-func field types fallback
				compose/deep/into [
					if (:test) (field) [do make error! (:test) (field)]
				] tail checks
			)
		]]
		copy checks
	]
		
	set 'typecheck function [
		"Check types of all given words"
		spec [block!] "A sequence of: word [type! (type-test) ...] (global-test)"
	][
		unless checks: select/only/same memoized-typechecks spec [
			repend memoized-typechecks [spec checks: compile-spec spec] 
		]
		trap/catch [do checks  yes] [print thrown  no]
	]
]


#hide []

;; <<<<<<<<<< %../common/typecheck.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [forparse]]]

;; >>>>>>>>>> %../common/forparse.red >>>>>>>>>



; #include %selective-catch.red
; #include %new-apply.red

;@@ BUG: this traps exit & return - can't use them inside forparse
;@@ BUG: break/return will return nothing, because - see #4416
forparse: function [
	"Evaluate body for every match of pattern in series"
	pattern	[block!] "Parse rule to match"
	series	[any-block! any-string! binary!] "Series to parse"
    body    [block!] "Block of code to evaluate"
    /deep  "Match inside all sub-lists as well"
    /case  "Search for pattern case-sensitively"
    /part  "Limit the length of iteration"
    	length [number! any-block! any-string! binary!]
	/local r
][
	unset 'r											;-- unset if never matched the spec
	unless any-block? :series [deep: no]

	=else=: pick [
		[ahead any-list! into =rule= | skip]
		[skip]
	] deep
	=match=: [pattern (set/any 'r catch-continue body)]	;-- set r to result of last iteration
	=rule=: [any [=match= | =else=]]
	if error? catch-a-break [parse/:case/:part series =rule= length] [
		unset 'r										;-- break should return unset
	]
	:r
]


;; <<<<<<<<<< %../common/forparse.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [mapparse]]]

;; >>>>>>>>>> %../common/mapparse.red >>>>>>>>>




; #include %new-apply.red

;@@ BUG: this traps exit & return - can't use them inside forparse
;@@ BUG: break/return will return nothing, because - see #4416
;@@ modifies series in place, similar to replace (undecided if it's good or not)

;@@ BUG: Parse will deadlock if used carelessly,
;@@   e.g. `mapparse [any rule] "whatever" ["x"]` will insert "x" indefinitely
;@@   should we detect if match is empty and not evaluate the body for it?

;@@ or name it `rewrite`? but `mapparse` name is consistent with `forparse`
mapparse: function [
	"Changes every match of pattern in series with result of body evaluation"
	;-- pattern then series rather than series then pattern: follows other loops and forparse in particular
    pattern [any-type!] "Parse rule to match"
    series  [any-block! any-string! binary!] "The series to be modified in place"	;-- types accepted by parse
    body    [block!] "Block of code to evaluate"
    ; /all   "Replace all matches, not just the first"
    ; /deep  "Replace pattern in all sub-lists as well (implies /all)"
    /once  "Replace only first match, return position after replacement"	;-- makes no sense with /deep, returns series unchanged if no match
    																		;-- not sure /once is even needed as we have break
    /only  "Treat series result of body evaluation as single value"			;-- no effect on pattern
    /deep  "Replace pattern in all sub-lists as well"
    /case  "Search for pattern case-sensitively"
    /part  "Limit the length of replacement"
    	length [number! any-block! any-string! binary!]
][
	; if deep [all: true]									;-- /deep doesn't make sense without /all
	; if deep [once: false]								;-- /deep doesn't make sense with /once
	if all [deep once] [do make error! "/deep and /once refinements are mutually exclusive"]
	unless any-block? :series [deep: no]

	=else=: pick [
		[ahead any-list! into =rule= | skip]
		[skip]
	] deep
	=change=: pick [
		[change only pattern (catch-continue body)]
		[change      pattern (catch-continue body)]
	] only
	=rule=: pick [
		[thru =change= series:]
		[any [=change= | =else=]]
	] once
	catch-a-break [parse/:case/:part series =rule= length]
	series
]


; probe mapparse [set x integer!] [0 1.0 "abc" 2] [probe x x * 2]

;; <<<<<<<<<< %../common/mapparse.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [sift locate]]]

;; >>>>>>>>>> %../common/sift-locate.red >>>>>>>>>


; #include %include-once.red
; #include %hide-macro.red
; #include %assert.red

; #include %setters.red									;-- we need `anonymize`
; #include %new-each.red									;-- based on extended foreach/map-each capabilities
; #include %new-apply.red									;-- need `apply` to dispatch refinements


sift: locate: none
context [
	ref-or-block!: make typeset! [refinement! block!]
	expand-paths: function [
		tests   [block!] "Modified in place!"
		subject [word! none!]
		/local ref
	][
		repl: pick [
			(as path! compose [(subject) (to word! ref)])
			(ERROR "Cannot use refinements without column selected at (mold/only/part p 40)")
		] word? subject
		parse tests rule: compose/deep [any [
			p: change only set ref refinement! (repl)
		|	ahead block! into rule
		|	to [ref-or-block! | end]
		]]
		tests
	]
	
	
	
	run-tests: function [
		tests   [block!] "Paths should be expanded already"
		subject [block!] "Code to get subject or to throw the error" 
	][
		trap/catch [									;@@ without /all may crash - #5239
			while [not any [tail? tests :tests/1 == '|]] [	;-- succeed by reaching tail or pipe
				set/any 'result do/next pos: tests 'tests
				if pos =? back tests [					;-- standalone token
					switch type?/word :result [
						block!    [if block? :pos/1 [result: run-tests pos/1 subject]]		;-- new ruleset
						datatype! [if word?  :pos/1 [result: result = type? do subject]]
						typeset!  [if word?  :pos/1 [result: find result type? do subject]]
					]
				]
				any [
					:result								;-- succeed, test forward
					tests: find/case/tail tests '|		;-- fail, find next alternative
					return no							;-- fail the whole
				]
			]
			yes
		][
			unless all [
				error? e: thrown
				e/type = 'script
				find [unset-path invalid-path bad-path-type bad-path-type2] e/id
				find/only/same pos e/arg1				;-- path comes from the tests, not from deeper code
			][
				do e
			]
			no
		]
	]
	

	anonymous-hyphen: anonymize '- none					;-- a safe-to-assign hyphen for use in spec
	
	prepare: function [series pattern] [
		;; split pattern into spec and tests
		parse/case pattern [
			;; spec may extend up to the tail, useful e.g. for sifting of some columns unconditionally
			copy spec to [quote .. | end] opt skip tests:
		]
		tests: copy/deep tests							;-- will be deeply modified
		;; anonymize hyphens and collect word/paren slots (to figure out if default subject is possible to assign)
		subject: parse/case spec [collect any [
			change quote - (anonymous-hyphen)
		|	ahead word! '| to end						;-- no subject after pipe delimiter
		|	block!
		|	keep skip
		]]
		;; subject can only be an explicit word
		;; default subject only possible if spec is empty (no hyphens, no parens)
		words: either set-word? :spec/1 [next spec][spec]	;-- [p:] is considered an empty spec - needs a subject
		system/words/case [
			tail? words [insert words subject: anonymize 'subject none]
			all [single? subject] [subject: subject/1]
			'else [subject: none]
		]
		
		expand-paths tests subject
		subject: either subject [
			reduce [to get-word! subject]
		][
			[ERROR "Cannot use type checks without column selected"]	;-- no space in the message for location :(
		]
		
		reduce [spec tests subject]
	]
	
	set 'locate function [
		"Locate a row within SERIES that matches PATTERN"
		series  [series!] "Will be returned at found row index"
		pattern [block!]  "[row spec .. chain of tests]"
		/back "Locate last occurrence (starts from the tail)"
		/case "Values are matched using strict comparison"
		/same "Values are matched using sameness comparison"
		/local spec tests pos result
	][
		set [spec: tests: subject:] prepare series pattern
		unless set-word? spec/1 [						;-- we need position to track & return
			insert spec to set-word! 'pos
		]
		__iter: func [tests subject 'pos] [				;@@ temporary kludge - there's risk of spec overriding used words
			if run-tests tests subject [
				set/any 'result get/any pos
				break
			]
		]
		code: compose/only [__iter (tests) (subject) (spec/1)]
		apply 'for-each [(spec) series code /case case /same same /reverse back]
		result
	]

	;-- cannot be based on remove-each because it also selects columns not marked by '-'
	set 'sift function [
		"Select only rows of SERIES that match PATTERN, and only named columns"
		series  [series! map! integer! pair!]					;-- all types supported by map-each
		pattern [block!]  "[row spec .. chain of tests]"
		/case "Values are matched using strict comparison"
		/same "Values are matched using sameness comparison"
	][
		set [spec: tests: subject:] prepare series pattern
		columns: parse spec [collect any [				;-- selected columns to keep in the result
			'- | '| | set w word! keep (to get-word! w)
		|	skip
		]]
		buf: copy columns
		__iter: func [tests subject columns] [			;@@ temporary kludge - there's risk of spec overriding used words
			reduce/into columns clear buf				;-- tests may change word values, so we have to reduce them before that
			; either run-tests tests subject [buf][continue]	;@@ no longer works when tests evaluate to unset!
			any [all [run-tests tests subject  buf] continue]
		]
		unless scalar? series [series: copy series]		;-- don't modify the original
		code: compose/only [__iter (tests) (subject) (columns)]
		map-each/self/drop/:case/:same (spec) series code	;-- /self/drop to preserve input type, omit rows not passing the tests
	]
	
]


#hide []
; #include %prettify.red
; print "------ WORK HERE ------"

;; <<<<<<<<<< %../common/sift-locate.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [do-queued-events]]]

;; >>>>>>>>>> %../common/do-queued-events.red >>>>>>>>>


do-queued-events: does [
	loop 100 [unless do-events/no-wait [break]]		;-- capped at 100 in case of a deadlock
]

;; <<<<<<<<<< %../common/do-queued-events.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [show-trace]]]

;; >>>>>>>>>> %../common/show-trace.red >>>>>>>>>



; #include %shallow-trace.red

; #macro [ahead word! '??? copy code to end] func [[manual] s e] [	ahead is not known to R2, can't compile
#macro [p: word! :p '??? copy code to end] func [[manual] s e] [	;-- has to support inner `???`s inside the `???` block
	back clear change s reduce ['show-trace code]
]

show-trace: function [
	"Print the step by step evaluation log of a set of expressions"
	code [block!] "Code to evaluate"
	/widths "Specify custom output column widths"
		left  [integer!] "Expression column (default: 40)"
		right [integer!] "Result column (default: 40)"
][
	unless widths [left: right: 40]
	orig: copy/deep code								;-- preserve the original code in case it changes during execution
	shallow-trace
		func [rslt [any-type!] more [block!]] compose [
			print [
				pad mold/part/flat/only
						copy/part orig part: offset? code more
					(left) (left)
				"=>" mold/part/flat :rslt (right)
			]
			code: more
			orig: skip orig part
			:rslt
		]
		code
]

comment {
	;; nested test
	do [
		1 + 2
		???
		3 * 4
		do [
			5 ** 6
			???
			append [] [1 2 3 4 5]
		]
		this-is-an-error!
	]
}

;; <<<<<<<<<< %../common/show-trace.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [do-atomic]]]

;; >>>>>>>>>> %../common/do-atomic.red >>>>>>>>>


do-atomic: none
make reactor! [
    react/later job: [do self/job]						;-- `do`es itself when changed

    ; set 'hold-horses									;@@ what name is better?
    ; set 'do-async
    set 'do-atomic func [
    	"Execute CODE as an atomic (from reactivity's POV) operation"
    	code [block!] "Will not be interrupted by reactions; reactive targets remain unchanged"
    ][
        either empty? system/reactivity/queue [job: code][do code]
    ]
]

;; <<<<<<<<<< %../common/do-atomic.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [classy-object]]]

;; >>>>>>>>>> %../common/classy-object.red >>>>>>>>>


; #include %debug.red
; #include %assert.red
; #include %with.red
; #include %setters.red
; #include %catchers.red
; #include %error-macro.red
; #include %count.red
; #include %typecheck.red


on-change-dispatch: function [
	"General on-change function built for object validation"
	class [word!]
	word  [any-word!]
	old   [any-type!]
	new   [any-type!]
][
	if info: classes/:class/:word [
		;; love nice names but they add considerable overhead, so calling `info/i` directly
		;; left as a reminder:  set [equals: check: on-change:] info 
		unless info/1 :old :new [
			; word: bind to word! word obj				;@@ bind part fixed early Sept 2022
			word: to word! word							;@@ to word! required for now
			#debug [									;-- disable checks in release ver
				if info/2 :new [
					set-quiet word :old
					do make error! info/2 :new
				]
			]
			info/3 context? word word :new :old
		]
	]
]

classify-object: function [
	"Assign a class to the object"
	obj   [object!]
	class [word!]
][
	;; using 'parse' because during object construction it can change its class many times
	;; but only standard unaltered on-change handler can be shared
	either parse body-of :obj/on-change* ['on-change-dispatch lit-word! 3 word! end] [
		; set-quiet in obj 'on-change* :classes/:class/#on-change	;-- shared on-change* helps save RAM - REP #115
		set-quiet in obj 'on-change* select classes/:class #on-change	;-- shared on-change* helps save RAM - REP #115; workaround for #5007 :(
	][
		call: find body-of :obj/on-change* 'on-change-dispatch
		unless call [ERROR "Object is unfit for classification: (mold/part obj 100)"]
		change next call to lit-word! class
	]
]


;; note: implementation of 'class?' is a choice of tradeoffs
;; timings and RAM of try-based and all-based versions are as follows:
;; _________________________________ 
;; |     |  success  |  failure    | 
;; | try | 1.10us 0B | 2.45us 700B | 
;; | all | 1.70us 0B | 0.90us   0B | 
;; |  %  |  ~64%     |  ~270%      | 
;; |_____|___________|_____________| 
;; I find that my code is significantly biased towards successful checks
;; thus I have chosen the try-based implementation here

; class?: function [										;-- class-of is taken already
	; "Determine class of an object"
	; obj     [object!]
	; return: [word! none!] "NONE if not classified"
; ][
	; all [												;-- `try` approach is slower
		; function? select obj 'on-change*				;-- may be unset, have to verify
		; type: select body-of :obj/on-change* 'on-change-dispatch
		; to word! :type
	; ]
; ]

					;-- the following 'class?' implementation relies on it

class?: function [										;-- class-of is taken already
	"Determine class of an object"
	obj     [object!]
	return: [word! none!] "NONE if not classified"
][
	try [return to word! select body-of :obj/on-change* 'on-change-dispatch]
	none
]

classes: make map! 20

modify-class: context [
	;; used as default equality test, which always fails and allows to trigger on-change even if value is the same
	falsey-compare: func [x [any-type!] y [any-type!]] [no]
	
	;; used as default value check (that always fails) - this simplifies and speeds up the check
	falsey-test: func [x [any-type!]] [no]

	return function [
		"Modify a named class"
		class [word!]  "Class name (word)"
		spec  [block!] "Spec block with validity directives"
		/local next-field
	][
		unless cmap: classes/:class [
			ERROR "Unknown class (class), defined are: (mold/flat words-of classes)"
		]
		field?: [(unless field [ERROR "A set-word expected before (mold/flat/part p 50)"])]
		parse spec: copy spec [
			opt [remove set desc string! (put cmap #description desc)]
			any [
				remove [p: #type (field?) 0 5 [
					set types block!
				|	set fallback paren!
				|	ahead word! set op ['== | '= | '=?]
				|	set name [get-word! | get-path!]
				|	set doc string!
				]] p: (new-line p on)
			|	remove [p: #on-change (field?) [
					set args block! if (find [3 4] count args any-word!) set body block!
				|	set name [get-word! | get-path!]
				|	(ERROR "Invalid #on-change handler at (mold/flat/part p 50)")
				]]
			|	set next-field [set-word! | end] (
					if any [op types fallback name args body doc] [	;-- don't include untyped words (for speed)
						field: to get-word! field
						info: any [cmap/:field cmap/:field: reduce [:falsey-compare :falsey-test none none none none]]
						if op     [info/1: switch op [= [:equal?] == [:strict-equal?] =? [:same?]]]
						if any [types fallback] [info/2: typechecking/make-check-func field info/4: types info/5: fallback]
						if any [body name] [info/3: either name [get name][function args body]]
						info/6: doc
						set [op: types: fallback: args: body: name: doc:] none
					]
					field: next-field
				)
			|	skip 
			]
		]
		spec
	]
]
	
declare-class: function [
	"Declare a named class (overrides if already exists), return preprocessed spec"
	class       [word! path!]  "Class name (word) or class-name/prototype-name (path)"
	spec        [block!]       "Spec block with validity directives"
	/manual                    "Don't insert classify-object call automatically"
][
	; if classes/:class [ERROR "Class (class) is already declared"]
	if path? class [
		
		set [class: proto:] class
	]
	classes/:class: either proto [
		unless pmap: classes/:proto [ERROR "Unknown class: (proto)"]
		copy/deep pmap
	][
		make map! 20
	]
	spec: modify-class class spec
	put classes/:class #on-change						;-- issue is used as a key to avoid conflict with possible object words
		func [word [any-word!] old [any-type!] new [any-type!]] compose [
			on-change-dispatch (to lit-word! class) word :old :new
		]
	unless manual [
		insert spec compose [
			classify-object self (to lit-word! class)
		]
	]
	spec												;-- spec can be passed to `make` now
]

classy-object: function [
	"Create a unique object with type/value checking in it"
	spec [block!]
][
	name: ["unnamed-classy-object-" 0]
	name/2: name/2 + 1
	make classy-object! declare-class to word! to string! name spec
]


;; simplest validated object prototype and basic class (needed for classes/:class to be valid)
classy-object!: object declare-class/manual 'classy-object! [
	on-change*: function [word [any-word!] old [any-type!] new [any-type!]] [
		on-change-dispatch 'classy-object! word :old :new
	]
	classify-object self 'classy-object!
]


if function? :source [									;-- only exists if help is included
	context [
		format-columns: function [								;@@ export this?
			"Format text as columns"
			rows    [block!] "Block of blocks, each representing a row"
			/header "Format first row as header"
			/align widths [block!] "Column widths (omit to auto-estimate)"
			return: [string!]
		][
			if empty? rows [return copy {}]
			ncols: length? rows/1
			unless widths [widths: copy []]
			append/dup widths 0 ncols - length? widths
			repeat i ncols [unless integer? widths/:i [widths/:i: 0]]
			foreach row rows [									;-- calculate column widths
				
				
				repeat i ncols [widths/:i: max widths/:i length? row/:i]	;@@ use maximum-of with sift
			]
			if header [											;-- format the header
				repeat i ncols [
					rows/1/:i: pad/with uppercase copy rows/1/:i widths/:i #"`"
				]
			]
			output: clear {}
			foreach row rows [									;@@ use map-each
				repeat i ncols [
					pads: widths/:i + 2 - length? row/:i
					append/dup append output row/:i #" " pads
				]
				change back tail output #"^/"
			]
			copy output
		]
		
		class-info: function [
			"Get class information as formatted string"
			class   [word! object!] "Class name or object of that class"
			return: [string! none!] "None if class is not registered"
		][
			if object? class [unless class: class? obj: class [return none]]
			unless cmap: classes/:class [return none]
			
			align: copy [0]
			if obj [											;-- align words column
				funcs: exclude words-of obj [on-change* on-deep-change*]
				remove-each word funcs [not any-function? get/any word]	;@@ use map-each or sift
				
				ctxs: words-of obj
				remove-each word ctxs  [not object? get/any word]	;@@ use map-each
				
				longest: 0
				foreach word compose [(funcs) (ctxs)] [longest: max longest length? form word]	;@@ use map-each
				align: reduce [longest + 3]						;-- "  " prefix and ":" word suffix
				
				if empty? funcs [funcs: none]
				if empty? ctxs  [ctxs: none]
			]
			
			cols: copy/deep [["``FIELD" "DESCRIPTION" "EQ" "TYPES" "ON-CHANGE"]]
			foreach [word info] cmap [							;-- list class fields
				if issue? word [continue]						;@@ remove funcs & objects from this list?
				set [eq: _: on-change: types: fallback: doc:] info
				eq: case [
					:eq =? :equal?        ["="]
					:eq =? :strict-equal? ["=="]
					:eq =? :same?         ["=?"]
				]
				if types [
					types: mold/flat types
					if fallback [repend types [" " mold/flat fallback]]
				]
				if :on-change [on-change: rejoin [mold/flat/part :on-change 70]]
				repend/only cols [
					rejoin ["  " mold word ":"]
					any [doc ""]
					any [eq ""]
					any [types ""]
					any [on-change ""]
				]
			]
			fields: unless single? cols [format-columns/header/align cols align]
			
			if funcs [											;-- list also funcs
				cols: copy/deep [["``FUNCTION" "DESCRIPTION" "ARGS"]]
				foreach word funcs [
					parse spec: copy spec-of get word [opt block! set doc opt string! spec:]
					parse spec [any [remove [string! | [refinement! to end]] | skip]]
					repend/only cols [
						rejoin ["  " mold word ":"]
						any [doc ""]
						mold/only/flat spec
					]
				]
				funcs: format-columns/header/align cols reduce [align/1]
			] 
			
			if ctxs [											;-- list also contexts
				cols: copy/deep [["``CONTEXT" "DESCRIPTION" "WORDS"]]
				foreach word ctxs [
					desc': select select classes class? get word #description
					words: exclude words-of get word [on-change* on-deep-change*]
					repend/only cols [
						rejoin ["  " mold word ":"]
						any [desc' ""]
						mold/only/flat/part words 70
					]
				]
				ctxs: format-columns/header/align cols reduce [align/1]
			] 
			
			all [
				desc: select cmap #description
				not find desc #"^/"
				#"." <> last desc
				append desc #"."
			]
			
			output: copy {}
			case/all [
				desc   [repend output ["^/  " desc "^/^/"]]
				fields [repend output [fields "^/"]]
				funcs  [repend output [funcs "^/"]]
				ctxs   [repend output [ctxs "^/"]]
			]
			output
		]

		body: copy/deep body-of :source
		insert body/case [
			object? :val [
				either all [class: class? val info: class-info val]		;-- pass object to also get info about functions
					[[uppercase mold word "is an object of class" rejoin ["'" class "':^/"] info]]
					[[uppercase mold word "is an unclassified object, so no template info is available."]]
			]
		]
		set 'source function [
			"Print the source of a function or class of an object"
			'word [word! path!] "The name of the function or object"
			/local val
		] body 
	]
]


#debug [#hide []];; #debug [#hide [#assert []]]


;; <<<<<<<<<< %../common/classy-object.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [advanced-function]]]

;; >>>>>>>>>> %../common/advanced-function.red >>>>>>>>>



; #include %error-macro.red
; #debug off


; function: :system/words/function						;@@ unset inside context, unless this file is the first included
if native? :function [
	context [
		make-check: function [check [paren!] word [get-word!]] [
			compose/deep [
				unless (check) [
					do make error! form reduce [
						"Failed" (mold check) "for" type? (word) "value:" mold/flat/part (word) 40
					]
				]
			]
		]
	
		make-switch: function [word [get-word!] options [block!] values [block! none!]] [
			compose/only pick [[						;-- options may be empty; new-lines matter here
				switch/default type? (word) (options) (values)
			][
				switch type? (word) (options)
			]] block? values
		]
		
		extract-value-checks: function [field [any-word!] types [block!] values [block! none!] /local check words] [
			field: to get-word! field
			typeset: clear []
			options: clear []
			parse types [any [
				copy words some word! (append typeset words)
				opt [
					set check paren! #debug [(
						mask: reduce to block! make typeset! words		;-- break typesets into types
						append/only append options mask make-check check field
					)]
				]
			]]
			reduce [copy typeset  copy options]
		]
	
		spec-word!: make typeset! [word! lit-word! get-word!]
		defaults!: make typeset! [
			scalar! series! map!								;-- most types with lexical forms (save for hash & vector)
			word! lit-word! get-word! refinement! issue!		;-- words excluding set-word
		]
		
		insert-check: function [
			body            [block!]
			word            [get-word!]
			ref?			[logic!] "True if words comes after a refinement"
			default         [defaults! none!]
			types           [block! none!]
			options         [block! none!]
			general-check   [block! none!]
		][
			if types [typeset: make typeset! types]
			if default [
				default: either paren? default
					[compose      [(to set-word! word) (as block! default)]]
					[compose/only [(to set-word! word) (default)]]
				logic?:  either types [to logic! find typeset logic!][yes]
			]
			need-none-check?: all [ref? either types [not find typeset none!][no]]
			check: case [
				any [not empty? options  all [default logic?]] [	;-- general case - switch
					unless options [options: make block! 2]
					if default [insert options reduce [none! default] ]
					new-line/skip options on 2
					make-switch word options general-check
				]
				all [default general-check] [					;-- optimizations...
					compose/only [								;-- new-line matters here
						either (word) (general-check) (default)
					]
				]
				default [
					compose/only [								;-- new-line matters here
						unless (word) (default)
					]
				]
				all [general-check need-none-check?] [			;-- 'none' = no parameter, and should not be checked
					compose/only [								;-- new-line matters here
						if (word) (general-check)
					]
				]
				general-check [general-check]					;-- 'none' is valid and should be checked as any other value
				'else [ [] ]
			]
			new-line insert body check on
		]
		
		native-function: :function
		set 'function native-function [
			"Defines a function, making all set-words in the body local, and with default args and value checks support"
			spec [block!] body [block!]
			/local word
		][
			ref?: no
			parse spec: copy spec [any [				;-- copy so multiple functions can be created
				[	set word spec-word!
				|	not quote return: change set word set-word! (to word! word)
					[	remove set default defaults!
					|	pos: (ERROR "Invalid default value for '(word) at (mold/flat/part :pos 20)")
					]
				]
				pos: set types opt block!
				opt string!
				remove set values opt paren!
				(
					#debug [general-check: if values [make-check values to get-word! word]]
					if types [
						set [types: options:] extract-value-checks word types general-check
						change/only pos types
					]
					if any [types values default] [
						insert-check body to get-word! word ref? default types options general-check
					]
					set [default: values: options: general-check:] none
				)
			|	refinement! (ref?: yes)					;-- refinements args can be none even if it's not in the typeset
			|	skip
			]]
			native-function spec body
		]
	]
]

; #include %assert.red



; do [
comment [
	probe do probe [f: function [x: 1 [integer! float! (x >= 0)] (x < 0)] [probe x]]
	probe do probe [f: function [x: 1] [probe x]]
	probe do probe [f: function [x: 1 (x < 0)] [probe x]]
	probe do probe [f: function [x: 1 [integer! float!] (x < 0)] [probe x]]
	probe do probe [f: function [x [integer! float!] (x < 0)] [probe x]]
	probe do probe [f: function [x: 1 [integer! (x >= 0)]] [probe x]]
	probe do probe [f: function [/ref x: 1  [integer! (x >= 0) string!]  (find x "0")] [probe x]]
]

;; <<<<<<<<<< %../common/advanced-function.red <<<<<<<<<
		;-- included by search.red
		
#do [if block? :included-scripts [append included-scripts [search]]]

;; >>>>>>>>>> %../common/search.red >>>>>>>>>



; #include %hide-macro.red	
; #include %assert.red	
; #include %advanced-function.red	
	
array-search: search: none
context [
	abs: :absolute
	
	;; useful when either array is big or when value is not present in it as is; also in tests
	set 'array-search function [
		"Look for a smallest segment in a sorted array that contains value, return [X1 X2]"
		array [block! hash! vector!]
		value [number!]
		/skip period: 1 [integer!] (period > 0) "Data record size (searches in 1st column)"
		/mode "Use predefined [binary interp jump] or custom func [x1 f1 x2 f2] guessing algorithm (default: binary)"
			guess [word! function!]
	][
		f:     pick [[array/:i] [array/(i - 1 * period + 1)]] period = 1
		n:     round/ceiling/to (length? array) / period 1		;-- round up because it may be not at 1st column
		found: search/for/:mode i: 1 n f value :guess
		i1:    found/1 - 1 * period + 1
		i2:    found/3 - 1 * period + 1
		head clear change change found i1 i2
	]
	
	set 'search function [
		"Iteratively narrow down segment X1..X2 while it contains F(x)=offset, return [X1 F(X1) X2 F(X2)] box"
		'word [word! set-word!] "X argument name for the F(x) function"
		X1    [number!] "When both X1 and X2 are integers, treats X as discrete variable"
		X2    [number!] (same? type? X1 type? X2)
		F     [block!]  "Monotonic function F(x)"
		/for   "F(x) value to look for (default: 0)"
			offset: 0 [number!]
		/range "Minimally acceptable X1..X2 interval to stop the search (default: 0)"
			xrange: 0 [number!] (xrange >= 0)
		/error "Minimally acceptable F(X1)..F(X2) interval to stop the search (default: 0)"
			frange: 0 [number!] (frange >= 0)
		/limit "Max number of allowed iterations (throws an error if doesn't converge within it, default: 100)"
			nmax: 100 [integer!] (nmax > 0)
		;; 'binary chosen for robustness, e.g. 'interp can't work with infinity at either side
		/mode "Use predefined [binary interp jump] or custom func [x1 f1 x2 f2] guessing algorithm (default: binary)"
			guess: 'binary [word! (find [binary interp jump] guess) function!]
		/with "Provide F(X1) and F(X2) if they are known"
			F1: (call-f X1) [number!] 
			F2: (call-f X2) [number!] 
	][
		;; special cases not handled by the general algorithm - for more robustness
		case [
			f1 == offset [return reduce [x1 f1 x1 f1]]				;-- zero is already found
			f2 == offset [return reduce [x2 f2 x2 f2]]
			same? sign? df1: f1 - offset sign? df2: f2 - offset [	;-- F(x) does not intersect zero
				return reduce pick [ [x2 f2 x2 f2] [x1 f1 x1 f1] ] (abs df1) > (abs df2) 
			]
		]
		
		discrete?: integer! = type: type? x1
		sign: sign? f2 - f1
		if word? :guess [
			if guess = 'jump [
				if type <> integer! [ERROR "Jump guessing mode is only applicable to discrete dataset"]
				step: max 1 to integer! sqrt abs x2 - x1
			]
			guess: get bind guess self
		]
		
		loop nmax + 1 [									;-- +1 to keep nmax meaning as "maximum _allowed_ iterations"
			either any [
				xrange >= abs x2 - x1
				frange >= abs f2 - f1					;-- this also ensures f1<>f2 for guess functions
			][
				return reduce [x1 f1 x2 f2]
			][
				fx: call-f x: guess x1 f1 x2 f2
				; print [to tag! i: 1 + any [i 0] x1 f1 ".." x2 f2 "->" x fx]
				if any [x == x1 x == x2] [return reduce [x1 f1 x2 f2]]	;-- avoid deadlock on discrete sets with xrange=0
				switch sign * sign? fx - offset [
					 1 [x2: x f2: fx]					;-- F(x) has the sign of F2(x), replaces it
					-1 [x1: x f1: fx]					;-- F(x) has the sign of F1(x), replaces it
					 0 [return reduce [x fx x fx]]		;-- found zero, may stop right here
				]
			]
		]
		ERROR "Search did not converge in (nmax) iterations for (mold :f)"	;-- too much precision will slow it down, better to error out
	]
	
	call-f: func [x] with :search [set word x do f]
	
	binary: func [x1 f1 x2 f2] with :search [to type x1 + x2 / 2] 
	
	;; slope = (f2-f1)/(x2-x1) = f2/(x2-x) = f1/(x1-x), so x = x2 - f2/slope = x1 - f1/slope
	;; x = x2 - f2*(x2-x1)/(f2-f1) = (x2f2-x2f1-x2f2+x1f2)/(f2-f1) = (x1f2-x2f1)/(f2-f1)
	;; constant case f1=f2 is handled by frange check in the search body
	interp: func [x1 f1 x2 f2 /local x] with :search [
		either discrete? [
			to type divide subtract f2 - offset * (x1 + 1) f1 - offset * x2 f2 - f1
		][
			divide subtract f2 - offset * x1 f1 - offset * x2 f2 - f1
		]
	] 
	
	;; only defined on discrete sets, so can fall back to +1 linear scanning
	jump:   func [x1 f1 x2 f2] with :search [
		either step < abs x2 - x1 [x1 + step][x1 + 1]
	]
]

#hide []
 
;; <<<<<<<<<< %../common/search.red <<<<<<<<<

		
#do [if block? :included-scripts [append included-scripts [load-anything]]]

;; >>>>>>>>>> %../common/load-anything.red >>>>>>>>>


;; let compiler and inline tool keep the macro for runtime so it keeps working while expanding loaded data
;@@ ugly because includes workarounds for #5462,3
#if rebol [
	expand-directives [#do keep [load {
		#macro [## any-list!] func [[manual] s e] [
			change/only remove s do expand-directives s/1
		]
	}]]
]
#if all [value? 'inlining? get 'inlining?] [
	;; this needs to skip #macro while inlining, but use it when compiling
	expand-directives [#do keep [[#do keep]] [load {
		#macro [## any-list!] func [[manual] s e] [
			change/only remove s do expand-directives s/1
		]
	}]]
]

#macro [## any-list!] func [[manual] s e] [
	change/only remove s do expand-directives s/1
]

...: none												;-- try to avoid errors from loading molded cyclic data

;; <<<<<<<<<< %../common/load-anything.red <<<<<<<<<
			;-- required to load data saved by custom 'save'
		
		#local [										;-- don't spill macros into user code
			spaces: context [
				ctx: context [							;-- put all space things into a single context
					
;; >>>>>>>>>> %debug-helpers.red >>>>>>>>>


;-- requires export, prettify

exports: [dump-event dump-tree expand-space-path fix-paths dorc mold probe save ?? ? help debug-draw]


;-- debug func
dump-event: function [event] [
	event: object map-each/eval w system/catalog/accessors/event! [
		[to set-word! w 'quote event/:w]
	]
	help event
]

get-full-path: function [*ace [object!]] [
	path: append clear [] *ace
	while [*ace: *ace/parent] [append path *ace]
	reverse copy path
]

dump-tree: function [
	"List hierarchical tree of currently rendered faces & spaces"
	/from host [object!] "Root face to list from (by default - the screen)" (host? host)
][
	foreach-*ace *ace: any [host system/view/screens/1] [
		probe as path! get-full-path *ace
	]
	exit
]

dorc: does [do read-clipboard]

color-names: make map! map-each/eval [name value [tuple!]] to [] system/words [[value to word! name]]
color-name: function [color [tuple! none!]] [			;-- used for debug output to easier identify spaces
	any [
		select color-names color 
		color
		'colorless
	]
]

space-id: function [[no-trace] space [object!]] [		;-- used to identify spaces in debug sessions
	#composite "(color-name select space 'color) (space/type):(space/size)"	
]


add-indent: function [text [string!] size [integer!]] [
	indent: append/dup clear "" #" " size
	parse text [any [#"^/" not end insert indent (lf?: yes) | skip]]
	if lf? [insert text indent]
	text
]

mold: :system/words/mold								;-- let it always be available in Spaces context
if action? :mold [
	native-mold: :mold
	
	;; this monstrosity is adjusted to make more user-friendly output
	;; without /all it will not expand inner objects/maps, and will output spaces in compact form type:size
	;; and generally will be closer to `help` output
	;; mold/all will output loadable info in format acceptable by %load-anything.red
	context [
		; system/words/native-mold: :mold
		decor*: [[
			block!    ["[" "]"]
			paren!    ["(" ")"]
			path!     ["" ""]
			lit-path! ["'" ""]
			get-path! [":" ""]
			set-path! ["" ":"]
			hash!     ["##[make hash! [" "]]"] 
			map!      ["##[make map! [" "]]"] 
			event!    ["##[make event! [" "]]"] 
			object!   ["##[construct/only [" "]]"]
			function! ["##[func" "]"] 
			action!   ["##[make action!" "]"]			;-- can't use native mold since it will use it's own indentation 
			native!   ["##[make native!" "]"] 
			routine!  ["##[routine" "]"] 
			image!    ["##[make image! [" "]]"] 
		][
			block!    ["[" "]"]
			paren!    ["(" ")"]
			path!     ["" ""]
			lit-path! ["'" ""]
			get-path! [":" ""]
			set-path! ["" ":"]
			hash!     ["hash [" "]"] 
			map!      ["#[" "]"] 
			event!    ["event [" "]"] 
			object!   ["object [" "]"] 
			function! ["func" ""] 
			action!   ["action" ""] 
			native!   ["native" ""] 
			routine!  ["routine" ""] 
			image!    ["image [" "]"] 
		]]
		
		set 'mold function [
			[no-trace]
			{Returns a source format string representation of a value}
			value [any-type!]
			/only   "Exclude outer brackets if value is a block" 
			/all    "Return value in loadable format" 
			/flat   "Exclude all indentation"
			/deep   "Expand nested structures on all levels"
			/native "Pass over arguments to the native mold instead" 
			/part   "Limit the length of the result" 
				limit: (pick [100'000'000  10'000] all) [integer!] (limit >= 0)
		][
			indent: make string! 32
			depth:  0
			mold* :value limit
		]
		
		~: system/words
			
		;@@ perhaps I should not override global mold, but only probe/??/save
		;@@ otherwise high chance of breaking user code
		mold-stack: make hash! 100						;-- used to avoid cycles
		mold*: function [[no-trace] value [any-type!] limit /extern deep flat] with :mold reshape [
			if native [return native-mold/:only/:all/:flat/:part :value limit]
			; print native-mold reduce [only all :value]
			sp: " "
			output: make string! 16
			decor: select pick decor* all type: type?/word :value
			if decor [
				if ~/all [only depth = 0] [decor: ["" ""] noindent?: yes]
				vhead: either series? :value [head value][:value]
				if find/same/only mold-stack :vhead [return emit ["..."]]
			]
			unless deep [
				if 0 < depth [
					if all ['block! = type not all] [
						try [							;-- fails on system/words
							parse value: copy value [any [	;-- simple grouping ;@@ TODO: also find periodic patterns
								s: ahead [set x skip (xtype: type? :x) 19 xtype] [	;@@ how many items minimum to group?
									skip change [some x e:] (to word! rejoin ['x offset? s e])
								|	change xtype (to word! xtype)
									change [some xtype e:]  (to word! rejoin ['x offset? s e])
								]
							|	skip
							]]
						]
					]
					if 'object! = type [
						string: case [
							face? value [
								either 'rich-text = :value/type [ 
									native-mold value/text
								][
									if point2D? set/any 'size :value/size [try [size: to pair! value/size]] 
									rejoin [:value/type ":" mold* :size limit]
								]
							]
							space? value [
									if point2D? set/any 'size :value/size [try [size: to pair! value/size]] 
								rejoin [:value/type ":" mold* :size limit]
							]
							(class-of value) = class-of font! [native-mold value/name]
							'else [
								size: any [attempt [system/console/size/x] 80]
								rejoin [
									decor/1
									native-mold/only/part words-of value size - length? indent	;@@ ellipsize it
									decor/2
								]
							]
						]
						return emit [string] 
					]
				]
			]
			
			if decor [append/only mold-stack :vhead]
			switch/default type [
				object! map! @(to [] any-block!) event! [
					if any-path? value [sp: "/" flat': flat flat: yes]
					step 'depth
					;; output events too ;@@ won't be loadable since can't make events
					if 'event! = type [
						value: construct/only map-each/eval word system/catalog/accessors/event! [
							[to set-word! word  :value/:word]
						]
					]
					;; emit skip for series in /all mode (strings are below)
					if ~/all [
						all
						series? :value
						skip?: unless head? value [-1 + index? value]
					][
						skip-decor: reduce ["##[skip " rejoin [" " skip? "]"]]
						emit [skip-decor/1]
						value: head value
					]
					pos: block: to block! value
					if find [object! event!] type [				;@@ workaround for #5140 - restore words
						values: values-of value
						repeat i length? values [
							poke block i * 2 :values/:i
						]
						new-line/skip new-line/all block off on 2	;@@ workaround for #5417 - restore newlines
					]
					;; emit opening
					unless noindent? [
						if ~/all [not empty? block new-line? block] [	;@@ not empty = workaround for #5235
							append/dup indent #" " 4
						]
					]
					lf: unless flat [rejoin ["^/" indent]]
					emit [decor/1]
					;; emit contents
					if ~/all [							;-- exclude on-change in normal mold
						not deep
						object? value
					][
						remove/part find/skip pos 'on-change* 2 2
						remove/part find/skip pos 'on-deep-change* 2 2
						~/all [
							(length? pos) < 100			;-- exclude system/words and copies, which also return true on space? check
							space? value
							pos': find/skip pos 'cached 2
							block? :value/cache
							block? :value/cached
							change/only next pos' extract pos'/2 (3 + length? value/cache)	;-- minify /cached to only canvas sizes
						]
					]
					if ~/all [not flat  find [object! map!] type] [	;-- find max word length (excluding on-change possibly) 
						align: 1 + any [
							maximum-of map-each [word _] block [length? form word]
							0
						]
					]
					either ~/all [						;-- abbreviate huge blocks
						type = 'block!
						not deep
						not all
						depth > 1
						(length? pos) >= 16				;-- if this block is small, better to abbreviate a deeper one
						(n: 256) = length? native-mold/part pos n
					][
						string: `"block of (length? block) values..."`
						locally-flat: on
						emit [string]
					][
						forall pos [					;-- emit items
							if new-line? pos [emit [lf]]
							string: mold* :pos/1 limit
							emit [string]
							unless tail? next pos [
								if align [
									string: append/dup clear "" " " align - length? string
									emit [string]
								]
								emit [sp]
							]
							if limit <= 0 [break]
						]
					]
					if ~/all [not empty? block new-line? block] [	;@@ not empty = workaround for a heisenbug
						unless noindent? [clear skip tail indent -4]
						unless any [flat locally-flat] [
							lf: rejoin ["^/" indent]
							emit [lf]
						]
					]
					;; emit closing & skip closing
					emit [decor/2]
					if skip-decor [emit [skip-decor/2]]
					step/down 'depth
					if any-path? value [flat: flat']
				]
				image! [
					size:  value/size
					either ~/all [not deep depth >= 1] [
						emit [decor/1 (native-mold size) " ..." decor/2]
					][
						rgb:   value/rgb
						alpha: value/alpha
						emit [decor/1 (native-mold size) sp]	;-- mulitple emits will update limit on the go
						emit [(mold* rgb limit) sp]
						emit [(mold* alpha limit) decor/2]
					]
				]
				@(to [] any-string!) [
					either ~/all [
						all
						skip?: unless head? value [-1 + index? value]
					][
						string: native-mold/:all/:flat head value
						skip-decor: reduce ["##[skip " rejoin [" " skip? "]"]]
						emit [skip-decor/1 string skip-decor/2]
					][
						string: native-mold/:all/:flat value
						emit [string]
					]
				]
				function! action! native! routine! [
					spec: spec-of :value
					body: body-of :value
					if ~/all [not deep depth > 1] [
						new-line/all spec: copy spec no
						parse spec [
							any [/local remove to end | not 'return all-word! | remove skip]
						]
						body: [...]
					]
					if find [action! native!] type [body: [...]]	;-- body is unknown to runtime
					deep': deep  deep: yes				;-- don't shorten function bodies
					emit [decor/1 sp (mold* spec limit) sp (mold* body limit) decor/2]
					deep: deep'
				]
				handle! [										;-- make handles loadable by converting to integers
					value: second transcode/one next native-mold/all value	;-- extract the integer
					string: rejoin [form to-hex value "h"]		;-- convert to hex
					emit [string]
				]
				point2D! [
					unless all [value: round/to value 0.1]
					string: native-mold/:all/:flat :value
					emit [string]
				]
			][
				string: native-mold/:all/:flat :value
				emit [string]
			]
			if decor [clear find/same/only mold-stack :vhead]
			
			output
		]
		
		emit: function [strings [block!] /extern limit] with [:mold :mold*] [
			foreach string reduce strings [
				if paren? string [string: do string]
				unless string [continue]
				append/part output string limit
				limit: max 0 limit - length? string
			]
			output
		]
			
	]
]

probe: function [
	"Returns a value after printing its molded form"
	value [any-type!]
	/deep /all
][
	print mold/:deep/:all :value
	:value
]

??: function [
	"Prints a word and the value it refers to (molded)"
	'value [any-type!] "Word, path, multiple words/paths in a block, or any value"
][
	case [
		any [any-word? :value any-path? :value] [
			prin value prin ": "
			print mold get/any value
		]
		block? :value [									;-- multiple named values on a single line
			print form map-each word value [
				`"(word): (mold/part/flat get/any word 20) "`
			]
		]
		'else [print mold :value]
	]
]

help: ?: none
if function? :system/words/help [						;-- if console present, remove the annoying trailing new-line
	set 'help set '? function [
		{Displays information about functions, values, objects, and datatypes}
		'word [any-type!]
	][
		if #"^/" = last msg: help-string :word [take/last msg]	;@@ unfortunately, help-string is happy to dump full images: #4464
		print msg
	]
]

save: none
context [												;-- replace compiled mold with interpreted mold, and add /deep
	body: body-of :system/words/save
	parse body rule: [any [
		ahead any-list! into rule
	|	ahead any-path! into [thru 'mold insert ('native) to end]
	|	change only 'mold ('mold/native)
	|	skip
	]]
	set 'save func spec-of :system/words/save body
]


; form: :system/words/form								;-- let it always be available in Spaces context
; if action? :form [
	; native-form: :form
	
	; set 'form function [
		; "Returns a user-friendly string representation of a value"
		; value [any-type!] 
		; /part "Limit the length of the result" 
			; limit [integer!] 		
	; ][
		; switch/default type?/word :value [
			; object! [mold value]
			; block! hash! paren! path! get-path! set-path! lit-path! [
				; sp: either any-path? value ["/"][" "]
				; left: limit
				; r: rejoin next map-each/eval x value [
					; either part [
						; s: form/part :x limit
						; left: left - 1 - length? s
					; ][
						; s: form :x
					; ]
					; [sp s]
				; ]
				; if part [clear skip r limit]
				; r
			; ]
		; ][
			; either part
				; [native-form/part :value limit]
				; [native-form      :value]
		; ]
	; ]
; ]



;@@ TODO: at least 3 canvases: none (and maybe 0x0), half-infinite, and finite; configurable size
debug-draw: function ["Show GUI to inspect spaces Draw block"] [
	context [
		list: code: free: sized: drawn: path: obj: none
		rea: reactor [canvas?: no]
		fixed: make font! [name: system/view/fonts/fixed]
		;; can't put paths into list-view/data because of face's aggressive ownership system
		paths: []
		update: has [i] [
			clear paths
			list/data: collect [
				i: 0
				foreach-*ace obj: system/view/screens/1 [
					append/only paths path: get-screen-path obj
					keep reduce [mold path i: i + 1]
				]
			]
		]
		view/no-wait/options [
			below list: text-list focus 400x400 on-created [update]
			panel 2 [
				origin 0x0 space 10x-5
				text 195 "w/o canvas" text "with canvas"
				free:  box 195x170 on-up [rea/canvas?: no] 
					react [face/color: do pick [white silver] not rea/canvas?]
				sized: box 195x170 on-up [rea/canvas?: yes]
					react [face/color: do pick [white silver] rea/canvas?]
			] return
			code: area 400x600 font fixed react [
				face/text: either any [
					not list/selected
					not path: pick paths list/selected
				][
					"Select a space in the list"
				][
					either is-face? obj: last path [
						sized/draw: none
						either free/draw: drawn: obj/draw [
							mold prettify/draw drawn
						][
							"Face has no Draw block!"
						]
					][
						drawn: reduce [
							free/draw:  render    last path
							sized/draw: render/on last path to point2D! sized/size yes yes
						]
						mold prettify/draw pick drawn not rea/canvas?
					]
				] 
			]
			at 350x10 button "Update" [update]
		][
			actors: object [
				on-created: func [face] [
					face/offset: face/parent/size - face/size * 1x0
					foreach other face/parent/pane [
						unless other =? face [
							other/offset/x: face/offset/x - other/size/x - 5
							break
						]
					]
				]
			]
		]
	]
]

export exports

;; <<<<<<<<<< %debug-helpers.red <<<<<<<<<

					
;; >>>>>>>>>> %auxi.red >>>>>>>>>


; #include %../common/assert.red
;@@ not sure if infxinf should be exported, but it's used by custom styles, e.g. spiral
exports: [by thru . abs half skip? linear! linear? planar! planar? range! range? make-range .. using when only trigger impose clip ortho boxes-overlap? infxinf opaque blend batch]

; ;; readability helper instead of reduce/into [] clear [] ugliness
; #macro [#reduce-in-place block!] func [[manual] s e] [
	; change/only s 'reduce/into
	; insert/only insert e 'clear copy []
	; s
; ]

; ;@@ watch out for #5009 for a better way to specify refinements
; #macro [#compose-in-place any refinement! block!] func [[manual] s e /local path] [
	; path: copy 'compose/into
	; e: next s
	; while [refinement? :e/1] [append path to word! take e]
	; change/only s path
	; insert/only insert e 'clear copy []
	; s
; ]

by: thru: make op! :as-pair
.:        make op! :as-point2D							;@@ unfortunately, comma is not for the taking :(
abs: :absolute
svf:  system/view/fonts
svm:  system/view/metrics
svmc: system/view/metrics/colors

digit!: charset [#"0" - #"9"]							;@@ add typical charsets to /common repo

INFxINF: (1.#inf, 1.#inf)								;-- used too often to always type it numerically
;@@ consider: OxINF Ox-INF INFxO -INFxO (so far they don't seem useful)

skip?: func [series [series!]] [-1 + index? series]

half: func [x] [x / 2]
round-down: func [x] [round/to/floor   x 1]
round-up:   func [x] [round/to/ceiling x 1]

planar!: make typeset! [pair! point2D!]
linear!: make typeset! [integer! float!]				;@@ or real! ? real is more like single datatype, while linear is a typeset
planar?: func [value [any-type!]] [find planar! type? :value]
linear?: func [value [any-type!]] [find linear! type? :value]

along: make op! function [
	"Pick PAIR's dimension along AXIS (integer is treated as a square)"
	pair [planar! linear!]
	axis [word!] (find [x y] axis)
][
	pick pair * 1x1 axis
]

block-of?: make op! func [
	"Test if all of BLOCK's values are of type TYPE"
	block [block!] type [datatype!]
][
	parse block [any type]
]

using: function [
	"Return CODE bound to a context with WORDS local to it"
	words [block!] "List of words" (words block-of? word!)
	code  [block!]
][
	words: construct map-each w words [to set-word! w]
	with words code
]

get-safe: function [path [any-path! any-word!]] [		;@@ REP 113; this in case of error is 10x slower than 'get'
	try [return x: get path] none						;@@ workaround for #5300 here
]

; set-many: function [
	; "Set each target to a result of the corresponding expression evaluation"
	; targets [block!] exprs [block!]
; ][
	; forall targets [set :targets/1 do/next exprs 'exprs]
	; exprs
; ]


;@@ copy/deep does not copy inner maps (#2167), clone tries to encode system/words, so this kludge is still must have
copy-deep-map: function [m [map!]] [
	m: make map! copy/deep to [] m						;@@ workaround for copy/deep #(map) not copying nested strings/blocks
	foreach [k v] m [if map? :v [m/:k: copy-deep-map v]]
	m
]

clone: function [										;@@ should space cloning be based on this?
	"Obtain a complete deep copy of the data"
	data [any-object! map! series!]
	/flat "Make a shallow copy (unlike native copy, keeps items before head)"
] with system/codecs/redbin reshape [
	either flat [
		switch type?/word :data [
			@(to [] series!) [
				at	append (clear copy head data) head data
					index? data
			]
			map! @(to [] any-object!) [copy data] 
		]
	][
		decode encode data none
	]
]

;; ranges support needed by layout, until such datatype is introduced, have to do with this
;; since it's for layout usage only, I don't care about a few allocated objects, no need to optimize it
;; ranges are used by spaces to constrain their size, but those are read-only
;; object = 468 B, block = 92 B, map = 272 B (cannot be reacted to)
;; space with draw=[] = 512 B, rectangle = 1196 B, timer does not need this at all
range!: object [min: max: none]
range?: func [x [any-type!]] [all [object? :x (class-of x) = class-of range!]]
..: make op! make-range: function [						;-- name `to` cannot be used as it's a native
	"Make a range from A to B"
	a [scalar! none!]
	b [scalar! none!]
][
	
	make range! [min: a max: b]
]


;; kludges for very limited bitset functionality
nonzero-byte: charset [1 - 255]
lowest-bit: function [bs [bitset!]] [
	if bs/0 [return 0]									;-- negated bitset?
	bin: to #{} bs
	unless p: find bin nonzero-byte [return none]
	base: 8 * skip? p
	repeat i 8 [if find bs bit: base + i - 1 [break]]
	bit
]

highest-bit: function [bs [bitset!]] [
	if bs/2'147'483'647 [return none]					;-- negated bitset
	bin: to #{} bs
	unless p: find/last bin nonzero-byte [return none]
	base: 8 * skip? p
	repeat i 8 [if find bs bit: base + 8 - i [break]]
	bit
]



unroll-bitset: function [bs [bitset!]] [
	result: clear []
	if lo: lowest-bit bs [
		hi: highest-bit bs
		for i: lo hi [if bs/:i [append result i]]		;@@ this is really dumb
	]
	copy result
]


{
	useful pair invariants to test in which quadrant a point is located
	points: a, b
	a = min a b <=> 0x0 = min 0x0 b - a <=> B is in Q1 to A, axis-inclusive <=> A is in Q3 to B, axis-inclusive
	a = max a b <=> 0x0 = max 0x0 b - a <=> B is in Q3 to A, axis-inclusive <=> A is in Q1 to B, axis-inclusive
	                1x1 = min 1x1 b - a <=> B is in Q1 to A, axis-exclusive <=> A is in Q3 to B, axis-exclusive
	            -1x-1 = max -1x-1 b - a <=> B is in Q3 to A, axis-exclusive <=> A is in Q1 to B, axis-exclusive
	a = min a b <=> b = max a b   
}

;; chainable pair comparison - instead of `within?` monstrosity
; >> 1x1 +< 2x2 +<= 3x3 +< 4x4
; == 4x4

;; very hard to find a sigil for these ops
;; + resembles intersecting coordinate axes, so can be read as "2D comparison"
+<=: make op! func [
	"Chainable pair comparison (non-strict)"
	a [planar! none!] b [planar!]
][
	all [a a == min a b  b]								;-- strict equality, otherwise 0 <= -1e30 will pass
	; all [a a/x <= b/x a/y <= b/y  b]
]
+<:  make op! func [
	"Chainable pair comparison (strict)"    
	a [planar! none!] b [planar!]
][
	all [a a/x < b/x a/y < b/y  b]
]
;+>:  make op! func [a b] [a = max a b + 1]
;+>=: make op! func [a b] [a = max a b]

inside?: make op! function [
	"Test if POINT is inside the SPACE"
	point [planar!] space [object!]
][
	within? point 0x0 space/size
]

above: function [										;-- a replacement for space/parent/parent/parent/parent shit
	"Get parent space of specific type (or none)"
	child [object!]
	type  [word!]
][
	while [space? child: child/parent] [if child/type = type [return child]]	;@@ use locate + tree iterator
	child
]

host-of: function [space [object!]] [
	all [path: get-host-path space  path/1]
]

host-box-of: function [									;@@ temporary until REP #144
	"Get host coordinates of a space (kludge! not scaling aware!)"
	space [object!] (space? space)
][
	box: reduce [(0,0) space/size]	
	while [parent: space/parent] [
		if host? parent [return box]
		
		geom: select/same parent/map space
		
		forall box [box/1: box/1 + geom/offset]
		space: parent
	]
	none
]

boxes-overlap?: function [
	"Get nonzero intersection size of boxes A1-A2 and B1-B2, or none if they don't intersect"
	A1 [planar!] A2 [planar!]
	B1 [planar!] B2 [planar!]
][
	(0,0) +< ((min A2 B2) - max A1 B1)					;-- 0x0 +< intersection size
]



segments-overlap?: function [
	"Get nonzero intersection size of segments A1-A2 and B1-B2, or none if they don't intersect"
	A1 [linear!] A2 [linear!]
	B1 [linear!] B2 [linear!]
][
	sec: (min A2 B2) - max A1 B1
	all [sec > 0 sec]									;-- 0 < intersection size
]

vec-length?: function [v [planar!]] [					;-- this is still 2x faster than compiled `distance? 0x0 v`
	v/x ** 2 + (v/y ** 2) ** 0.5
]

closest-box-point?: function [
	"Get coordinates of the point on box B1-B2 closest to ORIGIN"
	B1 [planar!] "inclusive" B2 [planar!] "inclusive"
	/to origin: (0,0) [planar!] "defaults to 0x0"
][
	clip origin B1 B2
]

box-distance?: function [
	"Get distance between closest points of box A1-A2 and box B1-B2 (negative if overlap)"
	A1 [planar!] "inclusive" A2 [planar!] "non-inclusive"
	B1 [planar!] "inclusive" B2 [planar!] "non-inclusive"
][
	either isec: boxes-overlap? A1 A2 B1 B2 [			;-- case needed by box arrangement algo
		negate min isec/x isec/y
	][
		AC: A1 + A2 / 2
		BC: B1 + B2 / 2
		AP: closest-box-point?/to A1 A2 BC
		BP: closest-box-point?/to B1 B2 AP
		vec-length? BP - AP
	]
]
; test for it:
; view [a: base 100x20 loose b: base 20x100 loose return t: text 100 react [t/text: form box-distance? a/offset a/offset + a/size b/offset b/offset + b/size]]

~=: make op! function [a [number!] b [number!]] [
	to logic! any [
		a = b
		(abs a - b) < 1e-6
	]
]

; slope?: function [
	; "Get the slope of the line (X1,Y1)-(X2,Y2)"
	; x1 [float!] y1 [float!]
	; x2 [float!] y2 [float!]
; ][
	; (y2 - y1) / (x2 - x1)
; ]


;@@ move into common?
make-stack: function [
	"Create a stack of given row size"
	size [pair!] (size/1 > 0) "row size X row count"
][
	context [
		data:  make [] size/1 * size/2
		push:  func [values [block!]] [data: tail reduce/into values data]
		pop:   does compose [clear data: skip data (negate size/1)]
		top:   does compose [skip data (negate size/1)]
		empty: does [data: clear head data]
	]
]


; block-buffers: make hash! 100
; buffer-for: function [block [block!]] [
	; any [
		; clear buf: select/only/same/skip buffers block 2	;@@ unfortunately #4466 - search is linear
		; repend buffers [buf: copy []]
	; ]
	; buf
; ]
; cached-reduce: function [block [block!]] [
	; reduce/into block buffer-for block
; ]
; cached-compose: function [block [block!]] [
	; compose/into block buffer-for block
; ]


;; MEMO: requires `function` scope or `~~p` will leak out
#macro [#expect skip] func [[manual] bgn end /local quote? rule error name] [
	quote?: all [word? bgn/2  bgn/2 = 'quote  remove next bgn]
	rule: reduce [bgn/2]
	if quote? [insert rule 'quote]						;-- sometimes need to match block literally
	name: either string? bgn/2 [bgn/2][mold/flat bgn/2]
	error: compose/deep [
		do make error! rejoin [
			(rejoin ["Expected "name" at: "]) mold/part ~~p 100
		]
	]
	change/only remove bgn compose [(rule) | ~~p: (to paren! error)]
	bgn 
]


;@@ move this into /common once debugged
in-out-func: function [spec [block!] body [block!]] [
	lit-words: keep-type spec lit-word!
	block-rule: [any [
		ahead set w get-word! if (find lit-words w)
		change only skip (as paren! reduce ['get/any to word! w])
	|	ahead set w word!     if (find lit-words w)
		change only skip (as paren! reduce ['get to word! w])
	|	ahead set w set-word! if (find lit-words w)
		insert ('set) change skip (to word! w)
	|	ahead any-list! into block-rule
	|	ahead any-path! into path-rule
	|	ahead word! 'quote skip
	|	skip
	]]
	path-rule: [any [
		ahead set w get-word! if (find lit-words w) change only skip (as paren! reduce ['get/any to word! w])
	|	ahead any-list! into block-rule
	|	skip
	]]
	parse body: copy/deep body block-rule
	function spec body
]


include-into: function [
	"Include flag into series if it's not there"
	series [series!] flag [any-type!] /same
][
	unless find/only/:same series :flag [append/only series :flag]
	series
]

exclude-from: function [
	"Exclude flag into series if it's there"
	series [series!] flag [any-type!] /same
	
][
	remove find/only/:same series :flag
	series
]

set-flag: function [
	"Include or exclude flag from series depending on present? value"
	series [series!] flag [any-type!] present? [logic! none!]
][
	either present? [include-into series :flag][exclude-from series :flag]
]

has-flag?: function [									;-- used in popups
	"Test if FLAGS is a block and contains FLAG"
	flags [any-type!]
	flag  [word!]
][
	none <> all [block? :flags  find flags flag]
]

toggle: function [
	"Flip the value of a boolean flag"
	flag [path!]
][
	set flag not get flag
]

trigger: function [
	"Trigger on-change reaction on the target"
	target [word! path!]
][
	set/any target get/any target
]


flush: function [
	"Grab a copy of SERIES, clearing the original"
	series [series!]
][
	also copy series clear series
]

before: function [
	"Set PATH to VALUE, but return the previous value of PATH"
	'path [any-path! any-word!] value
][
	also get path set path :value 
]

explode: function [										;@@ use map-each when fast; split produces strings not chars :(
	"Split string into a block of characters"
	string [string!]
	/into buffer [any-list!]
][
	unless buffer [buffer: make [] length? string]
	parse string [collect after buffer keep pick to end]
	buffer
]

zip: function [
	"Interleave a list with another list or scalar"
	list1 [series!]
	list2 [any-type!]
	/into result: (make list1 2 * length? list1) [series!]
][
	
	repeat i length? list1 pick [
		[append/only append/only result :list1/:i :list2/:i]
		[append/only append/only result :list1/:i :list2]
	] series? :list2
	result
]


delimit: function [
	"Insert VALUE between all items of the SERIES"
	series [any-list!]
	value  [any-type!]
][
	interleave/between series :value
]

;@@ make a REP with this? (need use cases)
;@@ this is no good, because it treats paths as series
native-swap: :system/words/swap
swap: function [a [word! series!] b [word! series!]] [
	either series? a [
		native-swap a b
	][
		set a before (b) get a
	]
]

only: function [
	"Turn falsy values into empty block (useful for composing Draw code)"
	value [any-type!] "Any truthy value is passed through"
][
	any [:value []]		;-- block is better than unset here because can be used in set-word assignments
]

;-- `compose` readability helper variant 2
; when: func [test value] [only if :test [do :value]]

;-- `compose` readability helper variant 3
;-- by the way, works in rejoin/composite as empty block results in empty string!!!
when: func [
	"If TEST is truthy, return VALUE, otherwise an empty block"
	test   [any-type!]
	:value [any-type!] "Paren is evaluated, block or other value is returned as is"
][
	only if :test [either paren? :value [do value][:value]]
]

;-- simple shortcut for `compose` to produce blocks only where needed
wrap: func [
	"Put VALUE into a block"
	value [any-type!]
][
	reduce [:value]
]

remake: function [proto [object! datatype!] spec [block!]] [
	construct/only/with compose/only spec proto
]

area?: function [xy [planar!]] [
	either nan? area: xy/x * 1.0 * xy/y [0.0][area]		;-- 1.0 to support infxinf here (overflows otherwise)
]

span?: func [xy [planar!]] [abs xy/y - xy/x]			;@@ or range? but range? tests for range! class
order-pair: function [xy [planar!]] [either xy/1 <= xy/2 [xy][reverse xy]]
order: function [a [word! path!] b [word! path!]] [		;@@ should this receive a block of any number of paths?
	if greater? get a get b [set a before (b) get a]
]

bit-range: func [range [pair!]] [
	range: order-pair range
	charset reduce [range/1 '- range/2]
]


;@@ this should be just `clip` but min/max have no vector support
clip-vector: function [v1 [vector!] v2 [vector!] v3 [vector!]] [
	repeat i length? r: copy v1 [r/:i: clip v1/:i v2/:i v3/:i]
	r
]

resolve-color: function [color [tuple! word! issue!]] [
	case [
		word?  color [svmc/:color]
		issue? color [hex-to-rgb color]
		'else [color]
	]
]

impose: function [
	"Impose COLOR onto BGND and return the resulting color"
	bgnd  [tuple! word!] "Alpha channel ignored"
	color [tuple! word!] "Alpha channel determines blending amount"
][
	c3: c4: (resolve-color color) + 0.0.0.0
	c3/4: none
	bg-amnt: c4/4 / 255
	(resolve-color bgnd) * bg-amnt + (1 - bg-amnt * c3)
]




HSL2XYZ: function [
	"Transform HSL cylindrical coordinate into cartesian XYZ"
	HSL [point3D!]
][
	as-point3D
		HSL/2 * cosine HSL/1
		HSL/2 * sine   HSL/1
		HSL/3
]

XYZ2HSL: function [
	"Transform cartesian XYZ coordinate into HSL cylindrical"
	XYZ [point3D!]
][
	as-point3D
		(arctangent2 XYZ/2 XYZ/1) + 360 % 360			;-- map [-180,180] into [0,360)
		vec-length? XYZ/1 . XYZ/2						;-- this doesn't check if it's >1, assumes correct
		XYZ/3
]

blend: function [
	"Get new color from a projection of BGND->COLOR vector scaled by AMNT (alpha channels ignored)"
	bgnd  [tuple! word!]
	color [tuple! word!]
	amnt  [number!] "< 100% to pull color closer to bgnd, > 100% to push further"
][
	;; in XYZ space it's possible to e.g. push red->green towards cyan
	bg-xyz: HSL2XYZ RGB2HSL resolve-color bgnd
	fg-xyz: HSL2XYZ RGB2HSL resolve-color color
	hsl: XYZ2HSL fg-xyz - bg-xyz * (clip -1e10 1e10 amnt) + bg-xyz	;-- avoid 1.#inf - leads to unwanted NaNs
	HSL2RGB/tuple clip (0,0,0) (360,1,1) hsl
]



enhance: function [
	"Push COLOR further from BGND (alpha channels ignored)"
	bgnd  [tuple! word!]
	color [tuple! word!]
	amnt  [number!] "Should be over 100%" (amnt >= 100%)
][
	bg-hsl: RGB2HSL resolve-color bgnd
	fg-hsl: RGB2HSL resolve-color color
	sign: pick [1 -1] fg-hsl/3 >= bg-hsl/3
	fg-hsl/3: clip 0 1 fg-hsl/3 + (amnt - 1 / 2 * sign)
	HSL2RGB/tuple fg-hsl
]

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


list-range: function [a [integer!] b [integer!]] [		;-- directional by design (used by list-view selection)
	step:   sign? range: b - a
	result: make [] 1 + abs range
	append result a
	while [a <> b] [append result a: a + step]			;@@ use map-each
	result
]

min-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b min a b] a b]
]

max-safe: function [a [scalar! none!] b [scalar! none!]] [
	any [all [a b max a b] a b]
]

update-EMA: function [
	"Update exponential moving average with new parameter measurements"
	estimate    [word! path!] "Current EMA"
	measurement [number!]     "New measurement result"
	period      [integer!]    "Averaging period"
	/batch num: 1 [integer!]  "Apply a whole batch of identical measurements"
][
	weight: 1 - (1 / period) ** num
	set estimate
		to type? get estimate							;-- required when modifying component of a pair
		add (get estimate) * weight measurement * (1 - weight)
]

interpolate: function [
	"Interpolate a value between V1 and V2"
	v1 [number!]
	v2 [number!]
	t  [number!] "[0..1] corresponds to [V1..V2]"
	/clip        "Force T within [0..1], making outside regions constant"
	/reverse     "Treat T as a point on [V1..V2], return a point on [0..1]"
][
	case/all [
		reverse     [t: t - v1 / (v2 - v1)]
		clip        [t: max 0.0 min 1.0 t]
		not reverse [t: add  v1 * (1.0 - t)  v2 * t]
	]
	t
]



build-index: reproject: reproject-range: none			;-- don't make these global, keep in spaces/ctx
context [
	;@@ can parts of this context be generalized and put into /common?
	;@@ maybe indexed search can be included into %search.red?
	
	set 'build-index function [
		"Build an index of given length for fast search over points"
		points [block! vector!] (4 <= length? points)
		length [integer!] (length >= 1)
	][
				;@@ I may want to generalize it later, but no need yet
		yindex: copy xindex: make vector! length
		clear xindex  clear yindex
		top:    skip tail points -2
		xrange: max 1e-10 top/1 - points/1				;-- 1e-10 to avoid zero division by step
		yrange: max 1e-10 top/2 - points/2
		dx: xrange * 1.000001 / length					;-- stretch a bit to ensure never picking at the tail
		dy: yrange * 1.000001 / length
		ix: iy: 1
		ipoint: -1  foreach [xi yi] next next points [	;@@ use for-each/reverse?
			ipoint: ipoint + 2
			ix: 1 + to integer! xi / dx
			iy: 1 + to integer! yi / dy
			append/dup xindex ipoint     ix - length? xindex
			append/dup yindex ipoint + 1 iy - length? yindex
		]
		obj: construct [points: xstep: ystep: xindex: yindex:]
		set obj reduce [points  dx     dy     xindex  yindex]
		obj
	]
	
	
	locate: function [
		points [block!]
		index  [vector!]
		step   [number!] (step > 0)
		value  [number!]
	][
		
		pos: at points pick index 1 + to integer! value / step
		;; find *first* segment that contains the value
		while [all [pos/5 value > pos/3]] [pos: skip pos 2]		;@@ use general locate when fast
			;-- 0.1 to account for rounding error
		pos
	]
	find-x: function [fun [object!] x [number!]] [
		locate fun/points fun/xindex fun/xstep x
	]
	find-y: function [fun [object!] y [number!]] [
		locate fun/points fun/yindex fun/ystep y
	]
	#hide []
	
	;; 'reproject' meaning get inverse projection from X to function line and then project into Y
	;@@ maybe there's a better name I don't see yet... X2Y and Y2X func pair?
	set 'reproject function [
		"Find value Y=F(X) given X on a non-decreasing function"
		fun [object!] "Indexed function as a sequence of points [X1 Y1 ... Xn Yn]"
		x   [number!] "X value" (not nan? x)
		/up       "If Y is not unique, return highest corresponding value (default: lowest)"
		/inverse  "Given Y find an X"
		/truncate "Convert result to integer"
	][
		xs: either inverse [find-y fun x][find-x fun x]
		;; find *last* segment that contains the value
		if up [while [all [xs/5  xs/3 <= x]] [xs: skip xs 2]]	;@@ use for-each
		ys: either inverse [back xs][next xs]
		t: either xs/1 == xs/3 [						;-- avoid zero-division
			either up [1][0]
		][
 			clip 0 1 x - xs/1 / (xs/3 - xs/1)			;-- clip to work around rounding issues
		]
		y: interpolate ys/1 ys/3 t
		if truncate [y: to integer! y]
		y
	]
	comment [											;-- interactive test
		f: build-index [0 0 1 2 2 4 2 5 4 5 7 8]
		sc: 400 / 8
		view [
			base white 400x400 all-over on-over [try [
				trace: map-each [x y] f/points [as-point2D sc * x sc * y]
				x: event/offset/x / sc
				y: event/offset/y / sc
				y1: sc * reproject    f x
				y2: sc * reproject/up f x
				x1: sc * reproject/inverse    f y
				x2: sc * reproject/inverse/up f y
				face/draw: compose/deep [
					pen magenta line (trace)
					pen cyan
					shape [
						move (event/offset) vline (y1)
						move (event/offset) hline (x1)
						move (0 by y1) 'hline (event/offset/x)
						move (0 by y2) 'hline (event/offset/x)
						move (x1 by 0) 'vline (event/offset/y)
						move (x2 by 0) 'vline (event/offset/y)
					]
				]
			]]
		]
	]
	
	set 'reproject-range function [
		"Return segment [Y1 Y2] projected by function FUN from segment [X1 X2]"
		fun [object!] "Indexed function as a sequence of points [X1 Y1 ... Xn Yn]"
		x1  [number!]
		x2  [number!] (x2 >= x1)
		/inverse  "Given Ys find Xs"
		/truncate "Convert result to integers"
	][
		reduce [
			reproject/:inverse/:truncate    fun x1
			reproject/:inverse/:truncate/up fun x2
		]
	]
]

;; constraining is used by `render` to impose soft limits on space sizes
constrain: function [
	"Clip SIZE within LIMITS"
	size    [planar!] "use infxinf for unlimited; negative size will become zero"
	limits  [object! (range? limits) none!] "none if no limits"
][
	unless limits [return size]							;-- most common case optimization
	;@@ NOTE: always use type?/word, not type? here, otherwise construction syntax is lost during 'inline' call
	;@@ see #5387
	min: switch/default type?/word limits/min [
		pair! point2D!  [limits/min]
		integer! float! [limits/min . 0]				;-- numeric limits only affect /x
	] [0x0]												;-- none and invalid treated as 0x0
	max: switch/default type?/word limits/max [
		pair! point2D!  [limits/max]
		integer! float! [limits/max . 1.#inf]			;-- numeric limits only affect /x
	] [infxinf]											;-- none and invalid treated as infinity
	clip size min max
]



;@@ rewrite this using inoutfunc?
for: function ['word [word! set-word!] i1 [integer! pair!] i2 [integer! pair!] (same? type? i1 type? i2) code [block!]] [
	either integer? i1 [
		if i2 < i1 [exit]			;@@ return none or unset? `while` return value is buggy anyway
		set word i1 - 1
		while [i2 >= set word 1 + get word] code
	][
		range: i2 - i1 + 1
		unless 1x1 +<= range [exit]	;-- empty range
		xyloop i: range [
			set word i - 1 + i1		;@@ does not allow index changes within the code, but allows in integer part above
			do code
		]
	]
]

closest-number: function [n [number!] list [block!]] [
	p: remove find/case (sort append list n) n
	case [
		head? p [p/1]
		tail? p [p/-1]
		(n - p/-1) < (p/1 - n) [p/-1]
		'else   [p/1]
	]
]




polar2cartesian: func [radius [linear!] angle [linear!]] [
	as-point2D (radius * cosine angle) (radius * sine angle)
]

ortho: func [
	"Get axis orthogonal to a given one"
	xy [word! pair!] "One of [x y 0x1 1x0]"
][
	;; switch here is ~20% faster than select/skip
	; select/skip [x y y x 0x1 1x0 1x0 0x1] xy 2
	switch xy [x ['y] y ['x] 0x1 [1x0] 1x0 [0x1]]
]

set-pair: function [
	"Set words to components of a pair value"
	words [block!]
	pair  [planar! block!] "Can be a block (works same as set native then)"
][
	set words/1 pair/1
	set words/2 pair/2
]
#hide []

set-axis: function [
	"Change VALUE of a given AXIS of an anonymous POINT"
	point [planar!]
	axis  [word!] (find [x y] axis)
	value [linear!]
][
	point/:axis: value
	point
]



axis2pair: func [xy [word!]] [
	switch xy [x [1x0] y [0x1]]
]

anchor2axis: func [nesw [word!]] [
	; switch nesw [n s ['y] w e ['x]];
	switch nesw [n s ↑ ↓ ['y] w e → ← ['x]]				;-- arrows are way more readable, if harder to type (ascii 24-27)
]

anchor2pair: func [nesw [word!]] [
	; switch nesw [n [0x-1] s [0x1] w [-1x0] e [1x0]]
	switch nesw [e → [1x0] s ↓ [0x1] n ↑ [0x-1] w ← [-1x0]]
]

normalize-alignment: function [
	"Turn block alignment into a -1x-1 to 1x1 pair along provided Ox and Oy axes"
	align [block! pair!] "Pair is just passed through"
	ox [pair!] oy [pair!]
][
	either pair? align [
		align
	][
		;; center/middle are the default and do not need to be specified, but double arrows are still supported ;@@ should be?
		dict: [n ↑ [0x-1] s ↓ [0x1] e → [1x0] w ← [-1x0] #(none) ↔ ↕ [0x0]]
		align: ox + oy * add switch align/1 dict switch align/2 dict
		either ox/x =? 0 [reverse align][align]
	]
]




decode-canvas: function [
	"Turn pair canvas into positive value and fill flags"
	canvas [point2D!] "can be positive or infinite (no fill), negative (fill)"
][
	reduce/into [
		abs canvas
		canvas/x < 0									;-- only true if strictly negative, not zero
		canvas/y < 0
	] clear []
]



encode-canvas: function [
	|canvas| [point2D!] (0x0 +<= |canvas|)
	fill-x   [logic!]
	fill-y   [logic!]
][
	x-sign: any [all [fill-x |canvas|/x < 1.#inf -1] 1]	;-- finite part may flip sign
	y-sign: any [all [fill-y |canvas|/y < 1.#inf -1] 1]	;-- infinite part stays positive
	x-sign . y-sign * |canvas|
]

#hide []


finite-canvas: function [
	"Turn infinite dimensions of CANVAS into zero"
	canvas [point2D!] (0x0 +<= canvas)
][
	case/all [
		canvas/x = 1.#inf [canvas/x: 0]
		canvas/y = 1.#inf [canvas/y: 0]
	]
	canvas
]



extend-canvas: function [
	"Make one of CANVAS dimensions infinite"
	canvas [point2D!]
	axis   [word!] "X or Y" (find [x y] axis)
][
	canvas/:axis: infxinf/x
	canvas
]

;; useful to subtract margins, but only from finite dimensions
subtract-canvas: function [
	"Subtract PAIR from CANVAS if it's finite, rounding negative results to 0x0"
	canvas [point2D!]
	pair   [planar!]
][
	max canvas - pair 0x0
]




fill-canvas: function [
	"Set unfilled and infinite canvas dimensions to zero"
	canvas [point2D!] fill-x [logic!] fill-y [logic!]
][
	as-point2D
		either all [fill-x canvas/x < 1.#inf] [canvas/x][0] 
		either all [fill-y canvas/y < 1.#inf] [canvas/y][0] 
]

top: func [
	"Return SERIES at it's position before the last item"
	series [series!]
][
	back tail series
]

rechange: function [
	"Sequence multiple changes into SERIES"
	series [series!]
	values [block!] "Reduced"
][
	change series reduce values
]

#hide []

compose-after: function [target [any-list!] template [block!]] [
	compose/only/deep/into template tail target
]

;; main problem with these is they can't be used in performance critical areas, which is quite often the case
>>: make op! function [
    "Return series at an offset from head or shift bits to the right"
    data   [series! integer!]
    offset [integer!]
][
    if integer? data [return shift-right data offset]
    skip head data offset
]

<<: make op! function [
    "Return series at an offset from tail or shift bits to the left"
    data   [series! integer!]
    offset [integer!]
][
    if integer? data [return shift-left data offset]
    skip tail data negate offset
]

; abs-pick: func [series [series!] index [integer!]] [	;@@ what's a better name?
	; pick either index < 0 [tail series] [series] index
; ]

filtered-event-func: function [
	"Make a filtered global View event function"
	spec [block!] "Function spec"
	body [block!] "Function body, should start with a list of supported event types" (block? :body/1)
	/local event-name
][
	parse spec [thru word! to word! set event-name skip]
	function spec compose/deep [
		switch (as path! reduce [event-name 'type]) [
			(body/1) [(next body)]
		]
	]
]
	
;-- faster than for-each/reverse, but only correct if series length is a multiple of skip
;@@ use for-each when becomes available
foreach-reverse: function [spec [word! block!] series [series!] code [block!]] [
	if empty? series [exit]
	step: 0 - length? spec: compose [(spec)]
	series: tail series
	until [										;-- clear the map of invisible spaces ;@@ should be for-each/reverse
		set spec series: skip series step
		do code
		head? series
	]
]

;; O(1) remove that doesn't preserve the order (useful for hashes)
fast-remove: function [block [any-block!] length [integer!]] [
	last-entry: skip tail block negate length
	unless block =? last-entry [change block last-entry]
	clear last-entry
]

;@@ extend & expand are taken already, maybe prolong?
;; it's similar to pad/with but supports blocks, returns insert position, and should be faster
enlarge: function [
	"Ensure certain SIZE of the BLOCK, fill empty space with VALUE"
	block [any-block! any-string!] size [integer!] value [any-type!]
][
	
	insert/only/dup skip block size :value size - length? block
	;; returns after size
]

;-- see REP #104, but this is still different: we don't care what context word belongs to, only it's spelling and value
same-paths?: function [p1 [block! path!] p2 [block! path!]] [
	to logic! all [
		any [
			find/match/same as [] p1 as [] p2
			tail? p2									;-- find always fails when second argument is empty (e.g. find [] [])
		]
		(length? p1) = length? p2
	]
]

find-same-path: function [block [block!] path [path!]] [
	forall block [
		all [
			path? :block/1
			same-paths? block/1 path
			return block
		]
	]
	none
]

#hide []


kit-catalog: make map! 40

;@@ add on-change to kit to lock it from modification
make-kit: function [name [path! (parse name [2 word!]) word!] spec [block!]] [
	unless word? name [
		base: kit-catalog/(name/2)
		spec: append copy/deep base spec
		name: name/1
	]
	kit-catalog/:name: copy/deep spec
	kit: object append keep-type spec set-word! [do-batch: none]	;-- must not be named 'batch' since global batch is used by kits
	kit/do-batch: function
		["(Generated) Evaluate plan for given space" space [object!] plan [block!]]
		with kit [do bind/copy plan self]				;-- must copy or may get context not available errors on repeated batch
	do with [:kit :kit/do-batch] spec
	kit
]

batch: function ["Evaluate plan within space's kit" space [object!] plan [block!]] [
	either kit: select space 'kit [kit/do-batch space plan][do plan]	;@@ or error if no kit?
]

;; this function assumes no scaling or anything fishy, plain map
;; uses geom/size/x, not space/size/x because parent's map may have been fetched from the cache,
;; while children sizes may not have been updated
;; it's not totally error-proof but I haven't come up with a better plan
generate-sections: function [
	"Generate sections block out of list of spaces; returns none if nothing to dissect"
	map     [block!]  "A list in map format: [space [size: ...] ...]" (parse map [end | object! block! to end])
	width   [linear!] "Total width (may be affected by limits/min)" (width >= 0)
	buffer  [block!]
][
	case [
		not tail? buffer [return buffer]				;-- already computed
		tail? map [										;-- optimization
			if width > 0.02 [append buffer width]		;-- treat margins as significant
			return buffer
		]
	]
	offset: 0
	frame: []											;-- when no sections in space, uses local value
	foreach [space geom] map [
		if (skipped: offset - geom/offset/x) < -0.02 [	;-- avoid adding too tiny (rounding error) values
			append buffer skipped
		]
		case [
			sec: batch space [
				sec: select frame 'sections
				sec										;-- calls if a function, may return none
			][
				append buffer sec
			]
			geom/size/x > 0 [append buffer geom/size/x]			;-- don't add empty (0) spaces
		]
		offset: offset - skipped + geom/size/x
	]
	if all [buffer/1 buffer/1 < 0] [buffer/1: abs buffer/1]		;-- treat margins as significant
	if width - offset > 0.02 [append buffer width - offset]
	
	buffer
]

	
	
;; this function is used by tube layout to expand items in a row (which should be blazingly fast)
;; it is quite tricky, because limits (constraints) of each item affect all others in a row
;; goal here is to make Red level code linear of complexity, while R/S part can be quadratic or nlogn
;; implementation sorts items by the available extension size normalized to weight
;; then it eliminates slices from the shortest to the longest,
;; subtracting each item's extension size multiplied by number of items left
;@@ maybe extract this into /common? maybe with /limits being an optional refinement?
distribute: function [
	"Distribute a numeric AMOUNT across items with given WEIGHTS"
	amount  [number!] "Any nonnegative number" (amount >= 0)
	weights [block!] "Zero for items that do not receive any part of AMOUNT" ((length? limits) = length? weights)
	limits  [block!] "Maximum part of AMOUNT each item is able to receive; NONE if unlimited" (0 < length? limits)
][
	data: clear []
	sum-weights: 0.0
	repeat i count: length? weights [
		weight: 1.0 * any [weights/:i 0]
		either weight <= 0 [
			repend data [i 0.0 0.0]
		][
			limit: 1.0 * max 0 any [limits/:i 1.#inf]
			sum-weights: sum-weights + weight
			repend data [i weight limit / weight]
		]
	]
	
	result: append/dup make block! count amount * 0 count
	if sum-weights <= 0 [return result]
	sort/stable/skip/compare data 3 3
	
	left: 1.0 * amount
	foreach [i weight slice] data [
		if left <= 0 [break]
		part: min slice left / sum-weights
		left: left - used: to amount part * weight
		sum-weights: sum-weights - weight
		result/:i: used
	]
	result
]




new-rich-text: none
context [
	;; rtd-layout is slow! about 200 times slower than object creation (it also invokes VID omg)
	;; just make face! is 120 times slower too, because of on-change handlers
	;; rich text does not require any of that however, so I mimick it using a non-reactive object
	;; achieved construction time is 16us vs 200us
	; light-face!: construct map-each w exclude words-of :face! [on-change* on-deep-change*] [to set-word! w]
	light-face!: make face! [
		on-change*: does []								;-- for whatever reason, crashes without this
		on-deep-change*: does []
		; para: make para! [wrap?: on]					;@@ whatever it was needed for, #5758 disables it
	]
	; rtd-template: make face! compose [
	rtd-template: compose [
		(system/view/VID/styles/rich-text/template)
		color: none
	]
	set 'new-rich-text does [make light-face! rtd-template]
]


export exports

;; <<<<<<<<<< %auxi.red <<<<<<<<<

					
;; >>>>>>>>>> %styles.red >>>>>>>>>


;; needs: map-each, anonymize, reshape, export, contrast-with

exports: [set-style remove-style define-styles]

styles: make hash! 50

;; used to keep above/below words from leaking out
style-ctx: context [below: above: none]
	


;; reminder: set-style 'a get-style 'b should work without any nasty tricks, binding errors, shared state, etc.
;; `style-ctx` is shared by functions, but gets read before evaluation, so it's fine
set-style: function [
	"Define a named style"
	name [word! path!]
	style [block! function!]
	/unique "Warn about duplicates"
][
	name: to path! name
	either pos: find/only/tail styles name [					;-- `put` does not support paths/blocks so have to reinvent it
		if unique [ERROR "Duplicate style found named `(mold name)`"]
	][
		pos: insert/only tail styles name
	]
	either block? :style [
		;; let it collect set-words, to prevent leakage and bind-related errors caused by words being shared by some object:
		;; also bind above/below words so even if function uses `return`, they are still set
		style: function [/extern above below] bind style style-ctx	;-- function copies the body deeply
	][
		style: func spec-of :style body-of :style
	]
	
	change pos :style
	:style
]

remove-style: function [
	"Forget a named style"
	name [word! path!]
][
	name: to path! name
	remove/part find/only styles name 2
]

define-styles: function [
	"Define one or multiple styles using Styling dialect"
	styles [block!] "Stylesheet"
	/unique "Warn about duplicates"
	/local style
][
	=style-name=: [set-word! | set-path!]
	=names=:  [not end ahead #expect =style-name= copy names some =style-name=]
	=expr=:   [p: (set/any 'style do/next p 'p) :p]
	=commit=: [(
		foreach name names [
			if set-word? name [name: to word! name]		;-- to path! set-word keeps the colon
			name: to path! name
			set-style/:unique name :style
		]
	)]
	parse styles [any [=names= =expr= =commit=]]
]

do with styling: context [
	;@@ TODO: ideally colors & fonts should not be inlined - see REP #105
	unless svm/colors [svm/colors: copy #[]]			;@@ MacOS fix for #4740
	unless svmc/text  [svmc/text: black]				;@@ GTK fix for #4740
	unless svmc/panel [svmc/panel: white - svmc/text]	;@@ GTK fix for #4740
	checkered-pen: reshape [							;-- used for focus indication
		pattern 4x4 [
			scale 0.5 0.5 pen off
			; fill-pen @[svmc/panel]  box 0x0  8x8
			fill-pen @[svmc/text] box 1x0 5x1  box 1x5 5x8  box 0x1 1x5  box 5x1  8x5
		]
	]
	; serif-12: make font! [name: svf/serif size: 12 color: svmc/text]	;@@ GTK fix for #4901

	;-- very experimental `either` shortener: logic | true-result | false-result
	|: make op! func [a b] [
		switch/default :a [
			#(true) [:b]
			#(false)[true]
		] [:a]
	]

	;-- very experimental `either` shortener: value |y true-result |n false-result
	; |y: make op! func [a b] [either :a [:b][:a]]
	; |n: make op! func [a b] [either :a [:a][:b]]
	
	make-box: function [
		size [planar!]
		line [linear!]
		pen [word! tuple! block! none!]
		fill-pen [word! tuple! none!]
		/round radius [linear!]
		/margin mrg: (line . line / 2) [planar!]
	][
		reshape [
			push [
				pen      @(pen)				/if pen
				fill-pen @(fill-pen)		/if fill-pen
				line-width @(line)
				box @(mrg) @(size - mrg) @(radius)
			]
		]
	]
][
	;@@ fill this with some more ;@@ should it be part of system/view/metrics/fonts?
	fonts: make map! reduce [
		'text      make font! [name: svf/system size: svf/size]
		'code      make font! [name: svf/fixed  size: svf/size]
		'label     make font! [name: svf/system size: svf/size + 1]
		'switch    make font! [name: svf/system size: svf/size + 6]
		'sigil     make font! [name: svf/system size: svf/size + 1]
		'sigil-big make font! [name: svf/system size: svf/size + 8]
		'comment   make font! [name: svf/system size: svf/size]
	]

	;@@ TODO: organize this internally as a map of nested words-blocks
	define-styles/unique reshape/with [@! /if!] [
		base: [
			below: [
				fill-pen @![svmc/panel]
				font     @![fonts/text]
				line-width 2
				pen      @![svmc/text]
			]
		]

		text: paragraph: link: fps-meter: [
			default font: fonts/text
			; #if linux? [(font: serif-12 ())]	;@@ GTK fix for #4901
			below: when select self 'color [pen (color)]
		]

		field: [
			margin: 3x3									;-- better default when having a frame (and frame comes from style, not template)
			below: [(make-box size 1 select self 'color none)]
		]
		caret: [
			; [pen off fill-pen @![contrast-with svmc/panel]]
			below: [pen off fill-pen @![svmc/text]]
		]
		selection: [
			; below: [pen (checkered-pen) fill-pen @![opaque 'text 30%]]
			below: [pen off fill-pen @![opaque 'text 30%]]
			;@@ workaround for #5133 needed by workaround for #4901: clipping makes fill-pen black
			#if linux? [
				below: [pen @![svmc/text] fill-pen off line-width 1 box 1x1 (size - 2)]
			]
		]
		
		tube: list: box: [									;-- allow color override for containers
			below: when select self 'color [
				; (#assert [size])
				(make-box size 0 'off color)
			]
		]
		
		;; cell is a box with a border around it; while general box is widely used in borderless state
		menu/list: cell: [
			below: [(make-box size 1 none select self 'color)]	;@@ add frame (pair) field and use here?
		]
		
		grid/cell: function [cell /on canvas fill-x fill-y] [	;-- has no frame since frame is drawn by grid itself
										;-- grid should provide finite canvas
			drawn: cell/draw/on canvas fill-x fill-y
			;; when cell content is not compressible, cell/size may be bigger than canvas, but we draw up to allowed size only
			canvas: min canvas cell/size
			color: any [
				select cell 'color
				if cell/pinned? [impose 'panel opaque 'text 10%]
			]
			bgnd: make-box canvas 0 'off color			;-- always fill canvas, even if cell is constrained
			reduce [bgnd drawn]
		]
		grid/selection: [
			below: [(make-box size 0 'off (opaque 'text 20%))]
			; below: [(make-box size 0 'off glass)]
		]
		grid/cursor: [
			below: when focused?/above 3 [(make-box size 1 checkered-pen 'off)]
		]
		
		grid/cell/paragraph: grid/cell/text: [			;-- make pinned text bold
			;; careless setting causes full tree invalidation on each render, though if style is applied it's already invalid
			set-flag flags 'bold parent/pinned?
		]
		
		list-view/window/list/selection: [
			below: [(make-box size 0 'off (opaque 'text 10%))]
			; below: [(make-box size 0 'off glass)]
		]
		list-view/window/list/cursor: [
			below: when focused?/above 3 [(make-box size 1 checkered-pen 'off)]
		]
		list-view/window/list/item: [
			lview:  parent/parent/parent				;@@ how to simplify this?
			margin: either lview/behavior/selectable [(4,2)][(0,0)]	;-- add little margin to draw frame on
		]
		
		;; "☒☐" make lines too big! needs custom draw code, not symbols
		;; this doesn't use /draw at all (what's there to use?)
		;; it also cannot be written in block style, since draw will nullify the size (given text is empty)
		switch: function [self] [						;-- clickable
			cross?: when self/state [line 3x3 13x13 line 13x3 3x13]
			frame:  make-box self/size: (16,16) 1 none none
			reduce [frame cross?]
		]
		logic: [										;-- readonly
			data/font: fonts/text
			maybe data/data: either state ["✓"]["✗"]	;-- maybe still required here because /data: doesn't check for equality
		]
		
		label: [
			if spaces/image-box/content = 'sigil [
				big?: spaces/body/content/2 = 'comment
				spaces/sigil/limits/min: pick [32 20] big? 
				spaces/sigil/font: select fonts pick [sigil-big sigil] big?
			]
			below: when select self 'color [pen (color)]
		]
		label/text-box/body/text:    [font: fonts/label  ]
		label/text-box/body/comment: [font: fonts/comment]

		clickable: data-clickable: [
			below: when select self 'color [(make-box size 0 'off color)]
		]
		button: [
			fill:    either pushed? [opaque 'text 50%][['off]]
			; below: [shadow 2x4 5 0 (green)]				;@@ not working - see #4895; not portable (Windows only)
			overlay: compose [make-box/round size 1 none (fill) rounding]
			focus?:  when focused? (
				inner-radius: max 0 rounding - 2
				compose [make-box/round/margin size 1 checkered-pen 'off (inner-radius) 4x4]
			)
			above:   reduce [as paren! overlay  as paren! focus?]	;-- paren delays evaluation until 'size' is ready (after render)
		]
		
		hscroll/thumb: vscroll/thumb: [
			above: when focused?/above 2 (
				make-box/margin size 1 checkered-pen none 4x3
			)
		]

		grid-view/window: [
			; #assert [size]
			below: [(make-box size 0 'off @![opaque 'text 50%])]
		]

		menu/ring/clickable: [
			below: [(make-box size 1 none color)]
		]
		
		menu/ring/round-clickable: [
			below: [(make-box/round size 1 none color 50)]
		]
		
		hint: function [box] [
			drawn: box/draw								;-- draw to obtain the size
			m: box/margin / 2
			o: box/origin
			reshape [
				@(make-box/round/margin box/size 1 none none 3 1x1 + m)
				;@@ TODO: arrow can be placed anywhere really, just more math needed
				push [
					matrix [1 0 0 -1 0 @(box/size/y)]	/if o <> 0x0
					shape [move @(m + 4x1) line 0x0 @(m + 1x4)]
				]										/if o	;-- no arrow if hint was adjusted by window borders
				@[drawn]
			]
		]
		
		rich-content: [
			below: reshape [
				font @(font)		/if font
				pen @(color)		/if color
			]
		]
		rich-content/text: rich-content/paragraph: [	;-- these override font with their own, so [font] draw command isn't enough
			default font: any [parent/font fonts/text]
			below: when select self 'color [pen (color)]
		]
		;@@ scrollbars should prefer host color
		
		slider: function [slider /on canvas fill-x fill-y] [
			drawn: slider/draw/:on canvas fill-x fill-y
			knob:  slider/knob
			right: slider/size - left: half knob/size/x . slider/size/y
			stop:  right - left * slider/offset * 1x0 + left
			compose/deep [
				push [
					line-width 4
					pen (opaque svmc/text 70%) line (left) (stop)
					pen (opaque svmc/text 30%) line (stop) (right)
				]
				(drawn)
			]
		]
		
		slider/knob: [
			fill:  opaque svmc/text either focused?/parent [100%][40%]
			above: reshape [line-width 1 fill-pen @(fill) circle (size / 2) (size/x / 2) (size/y / 2)]
		]
		slider/mark: function [mark /on canvas fill-x fill-y] [
			h: second mark/size: 1 . either canvas [canvas/y][1]
			compose [line-width 1 line (0.5, 0) (0.5 . (h * 0.15)) line (0.5 . (h * 0.85)) (0.5 . h)]
		]
	]
]


export exports

;; <<<<<<<<<< %styles.red <<<<<<<<<

					
;; >>>>>>>>>> %cache.red >>>>>>>>>


exports: [invalidate invalidate-tree get-host-path]


cache: context [
	last-canvas: function [
		"Get canvas of the last rendered frame of SPACE"
		space [object!] (space? space)
	][
		space/cached/-3
	]
	
	last-generation: function [
		"Get generation of the last rendered frame of SPACE"
		space [object!] (space? space)
	][
		space/cached/-2
	]
	
	current-generation: none							;-- out-of-tree renders have 'none' as their generation
	
	with-generation: function [							;-- reentrant, though it's an unlikely need ;@@ use scopes for this
		"Evaluate CODE with generation set to GEN"
		gen  [float!]
		code [block!]
	][
		old: current-generation
		set 'current-generation gen						;@@ need a general scope mechanism for this
		trap/all/catch code [error: thrown]
		set 'current-generation old
		if error [do error]
	]
	
	update-generation: function [
		"Update generation data of SPACE if it's an in-tree render"
		space  [object!] (space? space)
		state  [word!] "One of [cached drawn]" (find [cached drawn] state)
		canvas [point2D!] "Encoded canvas of the current state"
	][
		if current-generation [							;-- only update for in-tree renders
			change change change head space/cached canvas current-generation state
		]
	]
	
	; get-slot-size: function [							;-- for internal use, abstracts the slot size computation
		; space [object!] (space? space)
	; ][
		; if space/cache [3 + length? space/cache]
	; ]
	
	;@@ should have a global safe wrapper
	parents-list: make hash! 32
	list-parents: function [
		"Get a (STATIC, NOT COPIED) list of parents of SPACE in bubbling order (host comes last)"
		space [object!]
	][
		clear parents-list
		while [
			all [
				not host? space							;-- stop at host, no need to list further
				space: space/parent
				not find/same parents-list space		;-- cycle prevention
			]
		] [append parents-list space]
		parents-list
	]
	
	fetch: function [
		"If SPACE's draw caching is enabled and valid, return its cached slot for given canvas"
		space  [object!] (space? space)
		canvas [point2D!]
	][
		#debug profile [prof/manual/start 'cache]
		result: all [
			space/cache
			slot: find/same/skip space/cached canvas 4 + length? space/cache
			reduce [space/cache skip slot 2]			;-- skips canvas & generation, expose children and drawn
		]
		#debug cache [
			name: space/type
			if cache: space/cache [period: 4 + length? space/cache]
			either slot [
				n: (length? space/cached) / period
				#print "Found cache for (name):(space/size) on canvas=(mold canvas) out of (n): (mold/flat/only/part slot 40)"
			][
				reason: case [
					cache [rejoin ["cache=" mold extract space/cached period]]
					not space/parent ["never drawn"]
					not space/cache ["cache disabled"]
					empty? space/cached ["invalidated"]
					'else ["unknown reason"]
				]
				#print "Not found cache for (name):(space/size) on canvas=(mold canvas), reason: (reason)"
			]
		]
		#debug profile [prof/manual/end 'cache]
		result
	]
	
	#debug [max-slots: 0  culprit: none]
	commit: function [
		"Save SPACE's Draw block and cached facets on given CANVAS in the cache"
		space    [object!] (space? space)
		canvas   [point2D!]
		children [block!]
		drawn    [block!]
	][
		unless space/cache [exit]						;-- do nothing if caching is disabled
		#debug profile [prof/manual/start 'cache]
							;@@ should I enable caching of infinite spaces? see no point so far
		cur-gen: any [current-generation space/cached/-2]
		old-gen: cur-gen - 1.0
		period: 4 + length? space/cache					;-- custom words + (canvas + drawn + gen + children)
		words:  compose [canvas cur-gen children drawn (space/cache)]
		
		unless slot: find/same/skip space/cached canvas period [
			;; if same canvas isn't found, try to reuse an old slot
			slots: space/cached
			forall slots [								;@@ use for-each
				if all [
					slots/2 < old-gen					;-- slot is old
					not all [
						nan? slots/1/x / slots/1/x		;-- keep [infxinf infx0 0xinf 0x0] canvases (always relevant, unlike 0x319 or smth)
						nan? slots/1/y / slots/1/y
					]
					;@@ maybe fetch should also ignore old finite slots?
				][
					slot: slots
					break
				]
				slots: skip slots period - 1 
			] 
		]
		either slot [rechange slot words] [repend slots words]
		#debug cache [
			#print "Saved cache for (space/type):(space/size) on canvas=(canvas): (mold/flat/only/part drawn 40)"
			nslots: (length? space/cached) / period
			if nslots > max-slots [
				set 'max-slots nslots
				set 'culprit `"(space/type):(space/size)"`
				#print "Max cache slots=(nslots) in (culprit)"
			]
		]
		#debug profile [prof/manual/end 'cache]
	]
	
	invalidate: function [								;-- to be used by custom invalidators
		"Invalidate SPACE's cache, to force it's next redraw (low-level, doesn't call custom invalidators)"
		space [object!] (space? space)
	][
		#debug cache [if space/cache [#print "Invalidating (space/type):(space/size)"]]
		clear space/cached
	]
]


invalidate-tree: function [
	"Deeply invalidate spaces tree of given HOST"
	host [object!] (host? host)							;@@ or accept space instead?
][
	foreach-*ace space: host/space [invalidate/only space]
]
	
	
; invalidated?: function [
	; "Check if SPACE was invalidated and not yet rendered"
	; space [object!] (space? space)
; ][
	; to logic! all [
		; empty? space/cached
		; block? space/cache								;-- for uncached spaces cannot tell! 
	; ]
; ]

invalidate: function [
	"Invalidate SPACE cache, to force it's next redraw"
	space [object!] (space? space) "If present, space/on-invalidate is called instead of cache/invalidate"
	/only "Do not invalidate parents (e.g. if they are invalid already)"
	/info "Provide info about invalidation"
		cause [object! (space? cause) none!]
			"Invalidated child object or none"			;@@ support word that's changed? any use outside debugging?
		scope [word! (find [size look] scope) none!]
			"Invalidation scope: 'size or 'look"
	/local custom										;-- can be unset during construction
][
	 
	
	unless space/cached/-1 [exit]						;-- space was never rendered; early exit (for faster tree construction)
	#debug profile [prof/manual/start 'invalidation]
	default scope: 'size
	either function? select space 'on-invalidate [
		space/on-invalidate space cause scope			;-- custom invalidation procedure
	][
		cache/invalidate space							;-- generic (full) invalidation
	]
	if all [space/parent not only] [					;-- no matter if cache is valid, parents have to be invalidated
		host: take/last parents: cache/list-parents space		;-- no need to invalidate the host, as it has no cache
		;; only proceed if space is already connected to the tree (traceable to a host face)
		;; otherwise, it's likely still being created
		;; it's still possible that this space belongs to an orphaned subtree, but it's faster to allow it than to forbid
		if all [host  host? host] [
			#debug changes [
				path: as path! compose [(reverse to [] parents) (space)]
				#print "invalidating from (mold path), scope=(scope), cause=(if cause [cause/type])"
			]			
			cause: space								;-- cause is the child object
			foreach space copy parents [				;-- copy in case some custom handler calls list-parents
				invalidate/only/info space cause scope
				cause: space							;-- parent becomes the next child in sequence
			]
		]
	]
	#debug profile [prof/manual/end 'invalidation]
]
	
	
;; this uses generation data to detect outdated (orphaned) spaces, and returns none for them
;; timers.red relies on this to remove no longer valid timers from its list
get-host-path: function [
	"Get host-relative path for SPACE on the last rendered frame, or none if it's not there"
	space  [object!] (any [space? space  host? space])
	; return: [path! none!]
][
	if host? space [return as path! reduce [space]]		;-- for use with focus/current when it's a host face
	
	; #assert [space/parent]
	unless all [										;-- fails on self-containing grid
		space/parent
		host: first parents: reverse cache/list-parents space
		host? host
	] [return none]
	
	gen:  host/generation
	append parents space								;-- space's generation has to be verified as well 
	foreach obj next parents [
		if obj/cached/-2 < gen [return none]			;-- space generation is older than the host: orphaned (unused) subtree
		if obj/cached/-1 = 'cached [break]				;-- don't check generation numbers inside cached subtree
	]
	
	to path! parents
]

get-screen-path: function [
	"Get screen-relative path for space or face on the last rendered frame, or none if it's not there"
	obj [object!] (any [space? obj  is-face? obj])
][
	either space? obj [
		if path: get-host-path obj [face: path/1]
	][
		path: reduce [face: obj]
	]
	while [all [face face: face/parent]] [insert path face]
	all [path  path/1/type = 'screen  path]
]


#if true = get/any 'disable-space-cache? [
	; clear body-of :invalidate							custom invalidation must still work, since I can't turn it off
	clear body-of :cache/invalidate
	append clear body-of :cache/fetch none
	clear body-of :cache/commit
]


export exports

;; <<<<<<<<<< %cache.red <<<<<<<<<

					
;; >>>>>>>>>> %rendering.red >>>>>>>>>



;; uses timers (to prime them) at runtime

render: none				;-- reserve names in the spaces/ctx context
exports: [render]

current-path: as path! []								;-- used as a stack during draw composition

style-typeset!: make typeset! [block! function!]		;@@ hide this

empty-style: does []

;@@ TODO: profile & optimize this a lot
;@@ devise some kind of style cache tree if it speeds it up
get-style: function [
	"Fetch style for some tree path"
	path [path! block!]
][
	
	path: tail path
	until [												;-- look for the most specific fitting style
		p: back path									;@@ use for-each/reverse when fast
		style: any [select/only/skip styles p 2  :style]
		head? path: p
	]
	default style: :empty-style
	#debug styles [#print "Style for (p) is (mold/flat :style)"]
	:style
]
	
get-current-style: function [
	"Fetch styling code object for the current space being drawn"
][
	path: copy current-path
	forall path [path/1: path/1/type]
	get-style as path! path
]


apply-current-style: function [
	"Apply relevant style to current space being drawn"
	space [object!] "Face or space object"
][
	;; fast way to check if it accepts arguments (a function style) or not (a block style):
	style-func?: any-word? first spec-of style: get-current-style
	unless style-func? [								;-- function style is not applied here, only in render
		set style-ctx none								;-- clean the shared style context from old values
		bind body-of :style space
		(style)											;-- eval the style to preset facets
		style: copy/deep values-of style-ctx			;-- block is much smaller than copying the context; deep copy avoids rebind on nesting!
	]
	:style
]

combine-style: function [
	"Combine style & draw code into final block"
	drawn [block!] "Draw code produced by space/draw"
	style [block!] "Styling block from apply-current-style"
][
	reduce [
		compose/deep only style/1 
		drawn
		compose/deep only style/2
	]
]

;@@ what may speed everything up is a rendering mode that only sets the size and nothing else
context [
	check-parent-override: function [space [object!] new-parent [object!]] [	;-- only used before changing the /parent
		all [
			last-gen: cache/last-generation space
			next-gen: cache/current-generation
			last-gen = next-gen
			:space/parent
			unless :space/parent =? :new-parent [
				print `"*** Warning on rendering of (space/type):"`
				assert [:space/parent =? :new-parent "Parent sharing detected!"]
			]
		]
	]

	;; this is very important to see in profile results, as it's the main cause for slowdown
	;; so I moved this from 'changes' to 'profile' category (must be synced with render-face)
	#debug profile [
		;; checks after full face render for any invalidated spaces (have /cache enabled but /cached empty):
		verify-validity: function [host [object!] (host? host)] [
			paths: sift list-*aces host/space [			;-- obtain a list of possibly invalidated spaces
				obj .. 
				obj/cache								;-- cache enabled?
				empty? obj/cached						;-- no cached slots?
				obj/size +< infxinf						;-- has a finite size? (else can't be cached)
				not zero? area? obj/size				;-- not empty size? (may have no cached slots otherwise)
				not :obj/on-invalidate					;-- not using custom cache? (otherwise this heuristic doesn't apply)
			]
			unless empty? paths [
				print "*** Unwanted invalidation of the following spaces detected during render: ***"
				print mold/only new-line/all paths on
			]
		]
	]
	
	;; draw code has to be evaluated after current-path changes, for inner calls to render to succeed
	;@@ apply at least host style when path is given; other styles carryover should not be endorsed
	set 'with-style function [							;-- exported for an ability to spoof the tree (for slide, basically)
		"Draw calls should be wrapped with this to apply styles properly"
		space [block! path! (parse space [any object!]) object!]
			;@@ maybe when path given it should override the current one?
			"Inserted into current rendering path (if any)"		;-- path support is useful for out of tree renders (like slide)
		code  [block!]
	][
		top: tail current-path
		; #assert [any [object? space not find space pair!]  "style path can't contain pairs!"]
		append current-path space
		
		thrown: try/all [do code  ok?: yes]				;-- result is ignored for simplicity
		unless ok? [
			msg: form/part thrown 10000					;@@ should be formed immediately - see #4538
			#print "*** Failed to render (space/type)!^/(msg)^/"
		]
		;@@ would be great to use trap here instead, but it slows down cached renders obviously
		; trap/all/catch code [
			; msg: form/part thrown 1000					;@@ should be formed immediately - see #4538
			; #print "*** Failed to render (space/type)!^/(msg)^/"
		; ]
		clear top
	]
	
	;; format: [child canvas ...]
	children-stack: make hash! 100						;-- used to track lists of children for each canvas size in the cache
	
	render-face: function [
		face [object!] "Host face"
	][
		#debug styles [#print "render-face on (face/type) with current-path: (mold current-path)"]
		

		children-mark: tail children-stack
		cache/with-generation face/generation + 1.0 [
			without-GC [								;-- speeds up render by 60%
				with-style face [
					style:  apply-current-style face	;-- host style can only be a block
					canvas: all [face/size to point2D! face/size]
					drawn:  render-space/on face/space canvas yes yes	;-- fill by default
					
					unless face/size [					;-- initial render: define face/size
						
						face/size: face/space/size
						drawn: render-space/on face/space face/size yes yes	;-- re-render since it couldn't fill the infinite canvas
						style: apply-current-style face	;-- reapply the host style using new size
					]
					drawn: combine-style drawn style
				]
			]
			face/generation: cache/current-generation	;-- only updated if no error happened during render
		]
		clear children-mark
		#debug profile [
			prof/manual/start 'verify-validity
			verify-validity face						;-- check for unwanted invalidations during render, which may loop it
			prof/manual/end   'verify-validity
		]
		any [drawn copy []]								;-- drawn=none in case of error during render
	]

	restore-from-cache: function [space [object!] words [block!] slot [block!] deep? [logic!]] [
		set words skip slot 2 							;-- skip [children drawn]: at [size map etc..]
		if deep? [
			foreach [child ccanvas] slot/1 [
				if all [
					ccanvas <> cache/last-canvas child
					set [words': slot':] cache/fetch child ccanvas
				][
					restore-from-cache child words' slot' yes
					cache/update-generation child 'cached ccanvas
				] 
			] 
			#debug cache [#print "restored (half length? slot/1) immediate children states of (space-id space): (mold/flat slot/1)"]
		]
	]

	add-child: function [space [object!] canvas [point2D!]] [	;-- list child in its parent's children list
		either pos: find/same/skip/tail children-stack space 2 [
			change pos canvas
		][
			append append children-stack space canvas
		]
	]
				
	;@@ since 'apply' doesn't support silently ignoring refinements not present in the function, have to manually dispatch :(
	safe-draw: function [
		draw   [function!]
		space  [object! none!]
		xy1    [point2D! none!]
		xy2    [point2D! none!]
		canvas [point2D!]
		fill-x [logic!]
		fill-y [logic!]
	][
		window: in :draw /window
		if on:  in :draw /on [
			if canvas/x = 1.#inf [fill-x: no]			;-- inf canvas cannot be filled (result of canvas extension)
			if canvas/y = 1.#inf [fill-y: no]
		]
		index:  (either on [1][0]) + (either window [2][0]) + (either space [4][0])
		do pick [
			;; return below shields from the bug of refinements accepting less arguments than they should
			[return draw                                             ]
			[return draw/on                      canvas fill-x fill-y]
			[return draw/window          xy1 xy2                     ]
			[return draw/window/on       xy1 xy2 canvas fill-x fill-y]
			[return draw           space                             ]
			[return draw/on        space         canvas fill-x fill-y]
			[return draw/window    space xy1 xy2                     ]
			[return draw/window/on space xy1 xy2 canvas fill-x fill-y]
		] index + 1
	]
					
	render-space: function [
		space [object!] (space? space)
		/window xy1 [point2D! none!] xy2 [point2D! none!]
		/on canvas: infxinf [point2D! none!] fill-x: no [logic!] fill-y: no [logic!]
		/crude
	][
		; if name = 'cell [?? canvas]
		#debug profile [prof/manual/start 'render]
		name: space/type
		
		encoded-canvas: encode-canvas canvas fill-x fill-y
		#debug cache [#print "Rendering (color-name select space 'color) (name) on (encoded-canvas)"]	
		; #print "Rendering (color-name select space 'color) (name) on (encoded-canvas)"	

		unless tail? current-path [						;-- can be at tail on out-of-tree renders
			#debug [check-parent-override space last current-path]
			quietly space/parent: last current-path		;-- should be set before any child render call! so styles can access /parent
		]
		with-style space [
			window?: all [
				any [xy1 xy2]
				in :space/draw /window
				;@@ this should also check if style func supports /window but it's already too much hassle, maybe later
			]
			
			either all [
				not window?								;-- usage of region is not supported by current cache model
				set [words: slot:] cache/fetch space encoded-canvas
			][
				set [children: drawn:] slot
				do-atomic [								;-- prevent reactions from invalidating the cache while it's used by `set`
					#debug profile [prof/manual/start 'deep-restore]
					restore-from-cache space words slot not crude
					#debug profile [prof/manual/end 'deep-restore]
				]
				cache/update-generation space 'cached encoded-canvas
				add-child space encoded-canvas
				#debug cache [							;-- add a frame to cached spaces after committing
					if space/size [
						drawn: compose/only [(drawn) pen green fill-pen off box 0x0 (space/size)]
					]
				]
			][
				; if name = 'list [print ["canvas:" canvas mold space/content]]
				#debug profile [prof/manual/start name]
				style: apply-current-style space
				children-mark: tail children-stack
				
				either block? :style [
					drawn: safe-draw :space/draw none xy1 xy2 canvas fill-x fill-y
					drawn: combine-style :drawn style
				][
					drawn: safe-draw :style space xy1 xy2 canvas fill-x fill-y
					
				]
				
				unless any [xy1 xy2] [cache/commit space encoded-canvas to [] children-mark drawn]
				cache/update-generation space 'drawn encoded-canvas
				clear children-mark								;-- forget children of this space
				add-child space encoded-canvas
				
				if select space 'rate [timers/prime space]		;-- render enables timer for this space if /rate facet is set
				
				#debug profile [prof/manual/end name]
					;@@ should grid be allowed to have infinite size?
			]
		]
		#debug profile [prof/manual/end 'render]	
		either drawn [									;-- drawn=none in case of error during render
			reduce ['push drawn]						;-- don't carry styles over to next spaces
		][
			[]											;-- never changed, so no need to copy it
		]
	]

	set 'render function [
		"Return Draw code to draw a space or host face, after applying styles"
		space [object!] "Space or host face as object"
		/window "Limit rendering area to [XY1,XY2] if space supports it"
			xy1 [point2D! none!] xy2 [point2D! none!]
		/on canvas: infxinf [point2D! none!] "Specify canvas size as sizing hint"
			fill-x: no [logic!] "Try to fill finite canvas width"
			fill-y: no [logic!] "Try to fill finite canvas height"
		/crude "For spaces only - speed up caching on intermediate canvases"	;-- children may be out of sync!
	][
		drawn: either host? space [
			render-face space
		][
			render-space/window/on/:crude space xy1 xy2 canvas fill-x fill-y
		]
		#debug draw [									;-- test the output to figure out which style has a "Draw error"
			if error? error: try/keep [draw 1x1 drawn] [
				prin "*** Invalid draw block: " probe drawn
				do error
			]
		]
		drawn
	]
]


export exports

;; <<<<<<<<<< %rendering.red <<<<<<<<<

					
;; >>>>>>>>>> %layouts.red >>>>>>>>>


;-- requires export, typecheck

exports: [layouts make-layout]

;@@ can this be layouts/make ?
make-layout: function [
	"Create a layout (arrangement of spaces on a plane)"
	type     [word!]            "Layout name (list, tube, ring)"
	spaces   [block! function!] "List of space names or a picker function"
	settings [block!]           "Block of words referring to setting values"
	; return: [block!] "[size [planar!] map [block!]]
][
	layouts/:type/create :spaces settings
]

layouts: make map! to block! context [					;-- map can be extended at runtime
	import-settings: function [settings [block!] ctx [word!]] [
		bound:  bind append clear [] settings ctx
		values: head reduce/into settings clear []
		set bound values
	]

	list: context [
		;; shared by list/create and list-view/draw
		get-item-canvas: function [list-canvas [point2D!] limits [object! none!] axis [word!] margin [planar!]] [
			extend-canvas (subtract-canvas (constrain list-canvas limits) margin * 2) axis	;-- list is infinite along its axis
		]
		
		;; used to preallocate map buffer when count is unknown/infinite, but length (in px) is provided
		item-size-estimate: (100,20)
		
		;; settings for list layout:
		;;   axis             [word!]      x or y
		;;   margin          [planar!]        >= 0x0, always added around edge items, even if 'range' limits displayed items
		;;   spacing      [planar! integer!]  >= 0x0 (integer used by the document!)
		;;   canvas        [point2D! none!]   >= 0x0
		;;   fill-x fill-y [logic! none!]  fill along canvas axes flags: flag along 'axis' is ignored completely,
		;;      while the opposite flag controls whether whole list width extends to canvas or not (but items always fill the width)
		;;   limits        [object! none!]
		;;   origin       [point2D! none!]  unrestricted, offsets whole map, default=0x0
		;;   anchor       [integer! none!] index of the item at axis=margin (used by list-view), default=1
		;;   length        [linear! none!] in pixels, when to stop adding items (used by list-view), default=unlimited
		;;                                 does not include anchor size and both margins
		;;   reverse?       [logic! none!] true if items should be counted back from the anchor (used by list-view), default=false
		;;   do-not-extend? [logic! none!] true if sticking out items cannot extend list's width (used by list-view); default=false
		;;                                 (list-view has to maintain fixed width across slides and scrolls)
		;; result of all layouts is a frame object with size, map and possibly more; map geometries contain `drawn` block so it's not lost!
		;; settings are passed as a list of bound words, not as context
		;; this is done to make the list explicit, to avoid unexpected settings being read from the space object
		;; some of the words are also calculated directly in `draw`, so object is a bad fit to pass these
		create: function [
			"Build a list layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [axis margin spacing canvas fill-x fill-y limits origin anchor length reverse? do-not-extend?]"
			;; settings - imported locally to speed up and simplify access to them:
			/local axis margin spacing canvas fill-x fill-y limits origin anchor length reverse? do-not-extend?
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
							;-- this layout only supports finite number of items or limited length
			default count: 1.#inf
			if count <= 0 [return compose/deep [size: (margin * 2) map: []]]	;-- empty list optimization
			#debug [typecheck [
				axis     [word! (find [x y] axis)]
				margin   [planar! (0x0 +<= margin)]
				spacing  [planar! (0x0 +<= spacing) integer! (0 <= spacing)]
				canvas   [point2D! (0x0 +<= canvas) none!]
				fill-x   [logic! none!]
				fill-y   [logic! none!]
				limits   [object! (range? limits) none!]
				origin   [point2D! none!]
				anchor   [integer! (anchor > 0) none!]
				length   [linear! (length >= 0) none!]
				reverse? [logic! none!]
				do-not-extend? [logic! none!]
			]]
			default origin:   (0,0)
			default canvas:   infxinf
			default fill-x:   no
			default fill-y:   no
			default anchor:   1
			default length:   1.#inf
			default reverse?: no
			spacing: spacing * 1x1						;-- pair normalization needed by document
			direction: either reverse? [-1][1]
			default do-not-extend?: no
					;@@ need to find this bug: anchor is sometimes 0 or >count
			anchor: clip anchor 1 count
			x: ortho y: axis
			guide: axis2pair y
			item-canvas: get-item-canvas canvas limits axis margin
			;@@ this should be documented in the sizing/canvas docs (to be written)
			;; NOTE: fill/:x does not affect whether items fill the final width or not
			;;   they always do (and fill/:x cannot be true for inf width anyway)
			;;   fill/:x affects whether list extends its width to finite canvas width if former is smaller, or not
			;;   otherwise I will have to enable fill flag for the infinite canvas to make items fill the final width
			;; list can be rendered in two modes:
			;; - on infinitely wide canvas: first render each item on unlimited, then on final (finite) list width
			;;   final width is set to that of the widest visible item (it may change upon scrolling e.g. list-view)
			;;   since width is infinite, scrolling won't affect items height, only resulting list width
			;; - on finitely wide canvas: then fill/:x=true may be done in a single render (unless some item sticks out)
			;;   - if list length is finite:
			;;     wide sticking out items extend the final width, but not beyond limits/max/:x
			;;     (esp. useful when zero canvas is given, e.g. in tube)
			;;     if width has been extended or fill/:x=false (width determined by 1st render),
			;;     then 2nd render fills items along the final width
			;;   - if list has infinite number of items, no width extension is possible,
			;;     because such extension will affect items heights, and items will become denser
			;;     (that would break window-filling logic of list-view)
			;;     if fill/:x=false (for list), 2nd render fills items along width of the widest visible item (changes while scrolling)
			;;     however this layout doesn't know about infinite item count, so forbid-widening? flag is used instead
			;;   so if fill/:x is set, final width cannot be thinner than finite canvas, otherwise it can be
			;; constraining: limits/:x is applied to canvas before rendering items
			;;   then limits/:x is checked when extending or contracting the list width
			;;   along main axis items canvas is always infinite
			;;   but final list length is clipped/extended by limits/:y (hiding items or adding empty space)
			loop 2 [									;-- two render cycles
				size: (0,0)
				map:  fill abs length direction			;@@ avg+2dev, estimator/corrector
				
				;; total width (size/:x) is used for new canvas when:
				;; - fill/:x = off and total width < canvas width
				;; - 1st render was on infinite width (included into previous case since fill/:x is off for infinity)
				;; - total width > canvas width and count is finite
				if switch sign? size/:x - item-canvas/:x [
					-1 [not either x = 'x [fill-x][fill-y]]
					 1 [not do-not-extend?]
				][
					new-canvas: get-item-canvas size + (margin * 2) limits axis margin	;-- only size/:x is accounted for
					#debug sizing [#print "list c1=(item-canvas) c2=(new-canvas)"]
					if new-canvas <> item-canvas [
						item-canvas: new-canvas
						continue
					]
				]
				break									;-- no second render cycle if canvas is the same
			]
			
			if direction < 0 [reverse/skip map 2]		;-- order items top-down
			geom1:    map/2
			geom2:    last map
			size/:y:  geom2/offset/:y + geom2/size/:y - geom1/offset/:y
			item-len: max 1 size/:y + spacing/:y / n: half length? map	;-- don't let it become zero, or will overflow
			update-ema/batch 'item-size-estimate/:y item-len 1000 n 
			size:     size + (2 * margin)
			if direction < 0 [							;-- make all offsets positive
				shift: set-axis size x 0
				foreach [_ geom] map [geom/offset: geom/offset + shift]
			]
			range:    order-pair range 
			filled:   size/:y - margin/:y				;-- filled length is not constrained and only has 1 margin (used by 'available?')
			size:     constrain size limits				;-- do not let size exceed the limits (this clips the drawn layout)
			
			; prin [count "^-"] ?? [canvas size]
			;@@ omit some of these?
			frame: compose/only [
				size:         (size)
				map:          (map)
				axis:         (axis)
				margin:       (margin)
				spacing:      (spacing)
				origin:       (origin)
				anchor:       (anchor)
				range:        (range)
				length:       (length)					;-- requested length to fill
				reverse?:     (reverse?)
				filled:       (filled)					;-- actually filled length (may be both bigger and smaller)
				canvas:       (canvas)
				fill-x:       (fill-x)
				fill-y:       (fill-y)
				item-canvas:  (item-canvas)
				limits:       (if limits [copy limits])
			]
		]
		
		;; fills at least given amount of pixels with items in given direction (but may stop when runs out of items)
		;; increases size, returns map
		;; consideration: even if whole edge item is hidden (together with spacing), it still should be in the map
		;; because when tabbing around list-view, we need to have this item to switch to it and then pan the view
		;; for the same reason it should draw at least one item even if length=0 or less than margin
		fill: function [
			length [linear!] (length >= 0) sign [integer!] (1 = abs sign)
			/extern y spaces count func? origin margin spacing anchor range item-canvas size
		] with :create [
			ith-item: pick [[spaces/pick i][spaces/:i]] func?
			;; requested length does not include margin, otherwise if margin is big it may happen that window intersects the margin
			; length:   max 0 length - (margin/:y * 2)	;-- w/o margin = length of items themselves (and their spacing)
			count~:   either length < 1.#inf [length / item-size-estimate/:y][count]
			map':     make [] count~ * 110% + 5			;-- add extra space to lower the need for reallocations
			i:        anchor
			range:    anchor * 1x1
			pos:      origin + (margin * set-axis 1x1 y sign)
			add-item: [
				compose-after map' [
					(item) [offset (pos) size (item/size) drawn (drawn)]
				]
			]
			draw-next: [
				unless item: do ith-item [break]				;-- stop if no more items
				drawn: render/on item item-canvas yes yes		;-- items always fill the width (render disables fill for infinity)
								;-- sanity check that items are finite
				size:  max size item/size						;-- accumulate width
				i:     sign + range/2: i						;-- `range/2: i` relies on guaranteed add-item after draw-next
			]
			
			do draw-next
			length: length + item/size/:y				;-- don't count anchor in the length (required by list-view)
			limit:  pos/:y + (sign * length) 
			forever pick [
				[										;-- going down
					do add-item
					pos/:y: pos/:y + item/size/:y
					if pos/:y > limit [break]					;-- stop if pos > length (last item box intersects bottom margin)
					pos/:y: pos/:y + spacing/:y
					do draw-next
				][										;-- going up
					pos/:y: pos/:y - item/size/:y
					do add-item
					if pos/:y < limit [break]					;-- stop if pos < length (last item box intersects top margin)
					pos/:y: pos/:y - spacing/:y
					do draw-next
				]
			] sign > 0
			map'
		]
		
		;; return format for list of n items:
		;; - before 1st item               [margin 1 1   offset], -INF <= offset < 0 (margin-size is unused)
		;; - inside k-th item              [item   k k   offset], 0 <= offset < item-size,    1 <= k <= n
		;; - between k-th and k+1-th items [space  k k+1 offset], 0 <= offset < spacing-size, 1 <= k < n
		;; - after last item               [margin n n   offset], 0 <= offset <= INF, n is useful for ranges
		;; NOTE: 'margin' in list-view relates to anything outside the current frame, including non-drawn items and spacing
		;; so for list-view margin index will not be 1 or n, but frame/range/1 or frame/range/2 
		locate-line: function [
			frame [block! object! map!]
			level [linear!] "Map-relative (level=0 maps to frame/origin)"
		][
			
			y: frame/axis
			set [k: offset:] search/mode/for k: 1 n: half length? frame/map [
				geom: pick frame/map k * 2
				geom/offset/:y
			] 'interp level
			geom:   pick frame/map k * 2
			offset: offset - geom/offset/:y
			k:      k - 1 + frame/range/1
			reduce case [
				offset < 0            [['margin k k     offset]]
				offset < geom/size/:y [['item   k k     offset]]
				k = frame/range/2     [['margin k k     offset - geom/size/:y]]
				'else                 [['space  k k + 1 offset - geom/size/:y]]
			]
		]
		
	]
	
	tube: context [
		;; settings for tube layout:
		;;   axes          [block! none!]   2 words, any of [n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s] (also supports arrows)
		;;                                  in essence, any of n/e/s/w but both should be orthogonal, total 4x2
		;;                                  default = [e s] - left-to-right items, top-down rows
		;;   align       [block! pair! none!]   pair of -1x-1 to 1x1: x = list within row, y = item within list
		;;                                      default = -1x-1 - both x/y stick to the negative size of axes
		;;   margin           [planar!]     >= 0x0
		;;   spacing          [planar!]     >= 0x0
		;;   canvas       [none! point2D!]  >= 0x0; if none=inf, width determined by widest item
		;;   fill-x fill-y [logic! none!]    fill along canvas axes flags
		;;   limits        [none! object!]
		create: function [
			"Build a tube layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [axes align margin spacing canvas fill-x fill-y limits]"
			;; settings - imported locally to speed up and simplify access to them:
			/local axes align margin spacing canvas fill-x fill-y limits
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			if count <= 0 [return compose/deep [size: (margin * 2) map: []]]
			#debug [typecheck [
				axes     [
					block! (
						find/only [
							[n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s]
							[→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←]
						] axes
					)
					none!
				]
				align    [
					pair! (-1x-1 +<= align +<= 1x1)
					block! (
						all [
							2 >= length? align
							find [#(none) n s e w ↑ ↓ → ← ↔ ↕] align/1
							find [#(none) n s e w ↑ ↓ → ← ↔ ↕] align/2
						]
					)
					none!
				]
				margin   [planar!] (0x0 +<= margin)
				spacing  [planar!] (0x0 +<= spacing)
				canvas   [point2D! (0x0 +<= canvas) none!]
				fill-x   [none! logic!]
				fill-y   [none! logic!]
				limits   [object! (range? limits) none!]
			]]
			default axes:   [e s]
			default align:  -1x-1
			default canvas: infxinf						;-- none to pair normalization
			default fill-x: no
			default fill-y: no
			y: ortho x: anchor2axis axes/1				;-- X/Y align with default representation (row)
			ox: anchor2pair axes/1
			oy: anchor2pair axes/2
			align: normalize-alignment align ox oy
			reverse?: either x = 'x [:do][:reverse]
			
			;; to support automatic sizing, each item's constraints (`limits`) has to be analyzed
			;; obviously there can be two strategies:
			;;  1. fill everything with max size, then shrink, and rearrange as possible
			;;  2. fill everything with min size, then expand within a single row
			;;  2nd option seems more predictable and easier to implement
			;; constraint presence does not mean that space can reach that size as content affects it too,
			;; so it should only be used as hint (canvas size passed to render) to obtain real min size
			;; then, every item has to be rendered 2-3 times:
			;;  1. to get it's narrowest appearance
			;;  2. to expand it horizontally (changes row height) - only for items with nonzero weight
			;;  3. to fully fill row height
			;; quite a rendering torture, but there's no way around it
			
			;; constraints question is also a tricky one
			;; I decided to estimate min. size of each space by using 0x2e9 and 2e9x0 canvases (best fit for text/tube)
			;; (or 0xN / Nx0 when canvas is of fixed width)
			;; then each space will report the "narrowest" possible form of it, suiting tube needs
			;; when limits/min is set, it overrides the half-unlimited canvas
			;; when only limits/max is set, it's "height" overrides the infinite 2e9, "width" stays zero
			
			;; obtain constraints info
			;; `info` can't be static since render may call another layout/create; same for other arrays here
			;; info format: [space-object draw-block available-extension weight]
			info: make [] count * 4
			
			;; clipped canvas - used for allowed width / height fitting
			min-size: subtract-canvas (constrain (0,0) limits) 2 * margin
			stripe: ccanvas: subtract-canvas constrain canvas limits 2 * margin
			;; along X finite canvas becomes 0 (to compress items initially), infinite stays as is
			;; along Y canvas becomes of canvas size
			stripe/:x: either ccanvas/:x < 1.#inf [0][1.#inf]
			#debug sizing [#print "tube canvas=(canvas) ccanvas=(ccanvas) stripe=(stripe)"]
			
			repeat i count [
				space: either func? [spaces/pick i][spaces/:i]
				
				;; 1st render needed to obtain min *real* space/size, which may be > limits/max
				drawn: render/crude/on space stripe no no	;-- fill is not used for 1st render
				weight: any [select space 'weight 0]
				
				available: 1.0 * case [					;-- max possible width extension length, normalized to weight
					weight <= 0 [0]						;-- fixed size
					not max-size: all [space/limits space/limits/max] [1.#inf]	;-- unlimited extension possible ;@@ REP #113
					planar? max-size [max-size/:x - space/size/:x / weight]
					number? max-size [
						either x = 'x [				 	;-- numeric max-size only used on vertical tubes
							max-size - space/size/:x / weight
						][								;-- vertical is considered unbound
							1.#inf
						]
					]
				]
				;; if width is infinite, this 1st `drawn` block and `space/size` will be used as there's no meaningful width to fill
				;; otherwise they're just drafts and will be replaced by proper size & block
				repend info [space drawn available weight]
			]
			
			;; split info into rows according to found min widths
			;; rows coordinate system is always [x=e y=s] for simplicity; results are later normalized
			rows: make [] 30
			row:  make [] count * 4
			row-size: -1x0 * spacing					;-- works because no row is empty, so spacing will be added (count=0 handled above)
			allowed-row-width: ccanvas/:x				;-- how wide rows to allow (splitting margin)
			peak-row-width: 0							;-- used to determine full layout size when some row is bigger than the canvas
			total-length:   0							;-- used to extend row heights to fill finite canvas
			row-weight:     0							;-- later used to expand rows with >0 peak weight
			foreach [space drawn available weight] info [
				new-row-size: as-point2D				;-- add item-size and check if it hangs over
					row-size/x + space/size/:x + spacing/:x
					max row-size/y space/size/:y		;-- height will only be needed in infinite width case (no 2nd render)
				either any [							;-- row either fits allowed-row-width, or has no items yet?
					new-row-size/x <= allowed-row-width
					tail? row
				][										;-- accept new width
					row-size:   new-row-size
					row-weight: max row-weight weight
				][										;-- else move this item to next row
					append (new-row: make [] length? row) row
					repend rows [row-size row-weight new-row]
					total-length: total-length + row-size/y		;-- add before resetting row-size
					clear row
					row-size: reverse? space/size
					row-weight: weight
				]
				peak-row-width: max peak-row-width row-size/x
				repend row [space drawn available weight]
			]
			repend rows [row-size row-weight row]
			total-length: total-length + row-size/y

			;; expand row items - facilitates a second render cycle of the row
			;; this collects row heights (canvas/:y is still infinite)
			if allowed-row-width < 1.#inf [				;-- only if width is constrained
				allowed-row-width: max allowed-row-width peak-row-width		;-- expand canvas to the biggest row
				peak-row-width: 0						;-- will have to recalculate it during expansion
				total-length:   0
				forall rows [							;@@ use for-each
					set [row-size: row-weight: row:] rows
					free: allowed-row-width - row-size/x
					if all [row-weight > 0 free > 0] [	;-- any space left to distribute?
						;; free space distribution mechanism relies on continuous resizing!
						;; render itself doesn't have to occupy max-size or the size we allocate to it
						;; and since we don't know what render is up to,
						;; we can only "fix" it by re-rendering until we fill whole row space
						;; but this will be highly inefficient, and not even guaranteed to ever finish
						;; so a proper solution in this case should be to use a custom layout or resize hook
						;@@ this needs to be documented, and maybe another sizing type should be possible: a list of valid sizes
						weights: clear []				;-- can be static, not used after distribute
						extras:  clear []
						foreach [_ _ available weight] row [	;@@ use 2 map-eachs
							append weights weight
							append extras  available
						]
						extensions: distribute free weights extras
						; ?? [free extensions weights extras]
						
						row-size: -1x0 * spacing
						repeat i length? extensions [	;@@ use for-each
							set [space:] item: skip row i - 1 * 4
							if extensions/:i > 0 [		;-- only re-render items that are being extended
								desired-size: reverse? space/size/:x + extensions/:i . ccanvas/:y
								;; fill is enabled for width only! otherwise it will affect row/y and later stage of row extension!
								; ?? [desired-size space/content/size]
								item/2: render/crude/on space desired-size x = 'x x = 'y
							]
							row-size: as-point2D		;-- update row size with the new render results
								row-size/x + space/size/:x + spacing/:x
								max row-size/y space/size/:y
						]
						rows/1: row-size
					]
					peak-row-width: max peak-row-width row-size/x
					total-length: total-length + row-size/y
					rows: skip rows 2
				]
			]
			
			;; add spacing to total-length (previously not accounted for)
			nrows: (length? rows) / 3
			total-length: total-length + (nrows - 1 * spacing/:y)
			
			;; extend row heights evenly before filling rows in the following cases:
			;; - when canvas has height bigger than all rows height and filling is requested along height 
			;;   this makes it possible to align tube with the canvas without resorting to manual geometry management
			;; - when min height limit is bigger than all rows height (regardless of the fill flag) 
			fill-length: all [ccanvas/:y < 1.#inf  either x = 'x [fill-y][fill-x]]	;-- only fill if finite and requested to fill
			min-length: max-safe min-size/:y if fill-length [ccanvas/:y]				;-- but also if cannot be smaller
			free: min-length - total-length
			if 0 < free: min-length - total-length [
				weights: extract/into next rows 3 clear []	;@@ use map-each
				extras:  append/dup clear [] free nrows
				shares:  distribute free weights extras
				repeat i nrows [						;@@ use for-each
					i3: i - 1 * 3 + 1
					rows/:i3/y: rows/:i3/y + shares/:i
				]
				total-length: min-length
			]
			
			;; third render cycle fills full row height if possible; doesn't affect peak-row-width or row-sizes
			;; it must always be performed for other cycles to be used as /crude
			;@@ maybe it should affect (contract) row widths?
			foreach [row-size row-weight row] rows [
				repeat i (length? row) / 4 [			;@@ use for-each
					set [space:] item: skip row i - 1 * 4
					;; always re-renders items, because they were painted on an infinite canvas
					;; finite canvas will most likely bring about different outcome
					desired-size: reverse? space/size/:x . row-size/y
					item/2: render/on space desired-size yes yes
				]
			]
			
			;; build the map & measure the final layout size using results of 1st or 2nd render
			map:   clear []
			row-y: margin/:y
			shift: min 0x0 oxy: ox + oy					;-- offset correction for negative axes
			row-shift:    align/1 + 1 / 2
			in-row-shift: align/2 + 1 / 2
			total-width:  max-safe peak-row-width if allowed-row-width < 1.#inf [allowed-row-width] 
			foreach [row-size _ row] rows [
				ofs: reverse? margin/:x + (total-width - row-size/x * row-shift) . row-y
				foreach [space drawn _ _] row [
					ofs/:y: row-size/y - space/size/:y * in-row-shift + row-y
					geom: reduce ['offset ofs * oxy + (space/size * shift) 'size space/size 'drawn drawn]
					repend map [space geom]
					ofs/:x: ofs/:x + spacing/:x + space/size/:x
				]
				row-y: row-y + spacing/:y + row-size/y
			]
			;; fill the desired canvas width if canvas is given:
			size: (2,2) * margin + reverse? total-width . total-length
			if shift <> 0x0 [							;-- have to add total size to all offsets to make them positive
				shift: size * abs shift
				foreach [_ geom] map [geom/offset: geom/offset + shift]
			]
			#debug sizing [#print "tube c=(canvas) cc=(ccanvas) stripe=(stripe) >> size=(size)"]
			
			frame: compose/only [
				size: (size)
				map:  (copy map)
			]
		]
	]
	
	;; unlike tube this allows the single space to span multiple lines, wrapping it accordingly
	;; wrapping occurs between spaces and between sections (if supported by each item)
	;; it is able to wrap any space without that space knowing about it, letting it keep simple box-like rendering logic
	;; has no support for axes or weight
	;@@ maybe remove limits and apply them to canvas in advance?
	paragraph: context [
		;; paragraph has 3 coordinate spaces (CS):
		;; - 1D CS ("original") - all spaces form a single tight row, vertically aligned along the baseline
		;;   this is the CS /map is expressed in
		;; - 1D' CS (aka "unrolled 2D") - Y is the same as in 1D CS, X usually bigger, sometimes smaller
		;;   it may have words scaled, padded with spaces, etc.
		;;   it consists of whole rows of fixed width, so row number = x / total-width
		;;   this CS is used by mapping function from 1D CS (since mapping has to be monotonic)
		;; - 2D CS ("rolled 2D") - 1D' CS split into chunks, so x here = 1D'x % total-width
		;;   Y depends on each rows height
		;;   this is what user actually sees, where clicks land, etc
		;; coordinates usually include the CS name to avoid confusion
		
		;; builds a tight (no spacing/margin) map in 1D space, vertically aligned
		;@@ must be rebuilt on spacing or baseline change (or content or any item's size change)
		;@@ it shares a lot with list layout (1st phase) - can I unify them?
	    build-map: function [spaces [block! function!] baseline [float! percent!]] [
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
	    	map:   make [] count * 2
	    	if count <= 0 [return reduce [map 0x0]]
	    	
	    	offset: total: (0,0)						;-- margin is not accounted for in the map, so it's easier to change
	    	ith-item: either func? [[spaces/pick i]][[spaces/:i]]
			repeat i count [
				space: do ith-item
				
				drawn: render space						;-- for subparagraphs and lists canvas is infinite
				compose-after map [
					(space) [offset: (offset) size: (space/size) drawn: (drawn)]
				]
				offset/x: offset/x + space/size/x
				total: max total space/size				;-- need row height for aligning items
			]
			total/x: offset/x
			
			foreach [space geom] map [					;-- align vertically along a common baseline
				geom/offset/y: total/y - space/size/y * baseline	
			]
	    	reduce [map total]
	    ]

		;; builds a mapping 1Dx -> offset-in-map, to locate relevant spaces quickly
		index-map: function [map [block!]] [
			points: clear []
			repend points [x: 0 o: 0]					;@@ need 1-based offsets, more convenient to use with pick
			foreach [space geom] map [					;@@ use map-each
				repend points [x: x + geom/size/x  o: o + 1]
			]
			
			if points = [0 0 0 1] [points/3: 1]			;-- hack to make it all work with a zero-wide map
			build-index copy points n: 1 + round-down x / 32	;-- 1 point per 32 px
		]
		
		;; lists all sections of all child spaces in 1D space! - so not the same as space/sections
		list-sections: function [map [block!] total [linear!]] [
	    	generate-sections map total sections: clear []
	    	;@@ make leading spaces significant?
	    	if empty? sections [append sections 1]
	    	copy sections
		]
	    
		words-period: 4								;-- helpful constant
			
	    ;; groups sections by their sign into 'words', and returns them in this format:
	    ;; [word-x1-1D thru word-x2-1D(point as range)   word-width(linear)   white?(logic)   sections-slice(pair)]
	    list-words: function [sections [block!]] [
	    	words: clear []
	    	unless empty? sections [
		    	offset: width: sec-end: sec-bgn: 0
				white?: sections/1 < 0
		    	foreach w sections [					;@@ use for-each
		    							;-- zero reserved for tabs
		    		sec-end: sec-end + 1
		    		next-white?: if next-sec: sections/(sec-end + 1) [next-sec < 0]
					width: width + abs w
		    		if white? <> next-white? [
			    		repend words [
			    			0 . width + offset			;-- word's x1..x2 in 1D
			    			width						;-- word's 1D' width (= 1D width now, may be scaled later)
			    			white?						;-- whether word's empty or not
			    			sec-bgn thru sec-end		;-- sections slice used by the word
			    		]
			    		white?: next-white?
			    		sec-bgn: sec-end
			    		offset: offset + width
			    		width: 0
		    		]
		    	]
	    	]
	    	copy words
	    ]
	    
	    
	    ;@@ ensure this is not called with /force-wrap 
	    ;; estimates minimum total width of the paragraph (without margin) given indents and words
	    get-min-total-width-2D: function [words [block!] indent1 [linear!] indent2 [linear!]] [
			;; tricky algorithm to account for the case where indent1 < indent2:
			;; indent1-> w1 w2 long-word
			;; indent2          -> long-word
			;; i.e. it's more optimal to keep long-word in the 1st row than the 2nd
			;; after a few iterations only indent2+width matters then
	    	total: indent1
	    	first?: yes
	    	foreach [wordx width white? _] words [		;@@ use accumulate
	    		unless white? [
	    			either first? [						;-- first non-white word is always on the first row 
			    		total: max total (indent1 + wordx/2)
			    		first?: no
		    		][
			    		total: max total min (indent1 + wordx/2) (indent2 + wordx/2 - wordx/1)
		    		]
	    		]
	    	]
	    	total
	    ]
	    
	    
		;; copy words into buffer, until it fits row-width (or until scaling factor worsens in 'scale mode)
		fill-row: function [buffer [block!] words [block!] sections [block!] row-avail-width [linear!] align [word!] wrap? [logic!]] [
			accept-word?: pick [
				[new-used-width <= row-avail-width]
				[										;-- 'scale mode may exceed row-avail-width
					new-scale: new-used-width / row-avail-width
					old-scale: row-used-width / row-avail-width
					;; plot of best scale func: https://i.gyazo.com/87bf83b060f2a6c6a12a12cbb4e29164.png
					(max new-scale 1.0 / new-scale) < (max old-scale 1.0 / old-scale)	;-- may succeed once when crosses row-avail-width
				]
			] align <> 'scale 
			
			set [word-x-1D: word-width: white?: word-sections:] words-end: words	;-- always add at least one word
			row-used-width: either white? [0][word-width]
			while [not tail? words-end: skip words-end words-period] [
				if white?: words-end/3 [continue]				;-- add as many empty words as possible
				new-used-width: words-end/1/2 - word-x-1D/1
				unless do accept-word? [break]
				row-used-width: new-used-width
			]
			
			append/part row-words: tail buffer words words-end
			if all [									;-- split the word itself if it's bigger than the canvas
				align <> 'scale
				row-used-width > (row-avail-width + 0.2)	;-- 0.2px tolerance to account for rounding errors
			][
				; #assert [words-period = offset? words words-end]	;-- single word in the row -- doesn't check for white words before!
											;-- no-wrap mode must have adjusted the row-avail-width
				
									;-- whitespace does not increase used width
				
				;; try adding part of the word section by section
				unless block? sec-slice: word-sections [		;-- it's only block after a word gets split
					sec-slice: copy/part sections 1 + word-sections
				]
				sec-width: 0
				sec-added: 0
				foreach w sec-slice [					;@@ use for-each
					sec-width: sec-width + abs w
					if new-used-width > row-avail-width [break]
					sec-width: new-used-width
					sec-added: sec-added + 1
				]
				either sec-added = 0 [					;-- add only a part of the section
					
					sec-width: row-avail-width
					;; modify the sections themselves for next iteration to work
					sec-slice/1: (abs w) - sec-width * (sign? w)
					word-sections: sec-slice
				][
					word-sections: sec-added thru 0 + word-sections
				]
				word1: (0 . sec-width) + word-x-1D/1	;-- commit only part the the word
				word2: (sec-width . 0) + word-x-1D
				rechange row-words [word1 sec-width white? none]	;-- sections are unused in row-words (can be none)
				rechange words [									;-- subtract the committed part from the next word
					word2 (word-width - sec-width) white? word-sections
				]
				row-used-width: sec-width
				words-end: words						;-- no word was added
			]
			
			reduce [row-used-width words-end]
		]
		
		float-vector: make vector! [float! 64 10]
		;; evenly distributes remaining whitespace in fill mode
		distribute-whitespace: function [words [block!] size [linear!]] [
			;; last (trailing) whitespace should not be changed, so need to get rid of it first
			whites: clear {}
			foreach [_ _ white? _] words [append whites pick " +" white?]	;@@ use map-each or sift
			trim/tail whites							;@@ due to #5119 find/last/skip cannot be used
			trim/with whites #"+"
			n-white: length? whites
			if n-white = 0 [exit]						;-- no empty words in the row, have to leave it left-aligned
			
			white: 1.0 * size / n-white
			while [not tail? words] [					;-- skip 1st word ;@@ use for-each
				if white?: words/3 [
					words/2: words/2 + white			;-- modifies word-width-1D
					if zero? n-white: n-white - 1 [break]
				]
				words: skip words words-period
			]
		]
		
		;; unifies all words except trailing whitespace into one (for faster drawing)
		;, also groups trailing whitespace
		group-words: function [words [block!]] [
			-skip: negate words-period
			group-end: tail words
			while [group-end/-2 = yes] [				;@@ due to #5119 find/last/skip cannot be used 
				group-end: skip group-end -skip
			]
			; if words-period < length? group-end [  		;-- group whitespace
				; words-end: tail group-end
				; range-1D: group-end/1/1 . words-end/-4/2 
				; clear rechange group-end [range-1D span? range-1D yes none]
			; ]
			if words-period < offset? words group-end [	;-- group words
				range-1D: words/1/1 . group-end/-4/2 
				remove/part
					rechange words [range-1D span? range-1D no none]
					group-end
			]
		]
		
		;; measures y1 (upper) and y2 (lower) of spaces spanned by the row
		get-row-y1y2: function [
			map [block!]
			map-offset1 [integer!] (map-offset1 >= 0)
			map-offset2 [integer!] (map-offset2 >= map-offset1)
		][
			y1: 2e9  y2: 0
			for i: map-offset1 + 1 map-offset2 + 1 [
				geom: pick map i * 2
				y1: min y1 geom/offset/y
				y2: max y2 geom/offset/y + geom/size/y
			]
			reduce [y1 y2]
		]
				
		;; return format skeleton for paragraph layout
		frame!: object [
			size-1D:     (0,0)
			size-1D':    (0,0)
			size-2D:     (0,0)
			margin:      (0,0)
			spacing:     0
			map:         []
			sections:    []
			drawn:       []
			nrows:       0
			y-levels:    []
			x1D->x1D':   none
			x1D->map:    none
			y2D->row:    none
			caret-boxes: none							;-- not filled by layout/create - only on demand
		]
		
		empty-mapping: build-index [0 0 0 0] 1			;-- cached for faster 0x0 layout
				
		;; settings for paragraph layout:
		;;   align          [none! word!]     one of: [left center right fill scale upscale], default: left
		;;   baseline         [number!]       0=top to 1=bottom(default) normally, otherwise sticks out - vertical alignment in a row
		;;   margin           [planar!]       >= 0x0
		;;   spacing         [integer!]       >= 0 - vertical distance between rows
		;;   canvas       [none! point2D!]    >= 0; if infinite, produces a single row
		;;   fill-x fill-y [logic! none!]     fill along canvas axes flags
		;;   limits        [none! object!]
		;;   indent        [none! block!]     [first: integer! rest: integer!], first and rest are independent of each other
		;;   force-wrap?      [logic!]        prioritize canvas width and allow splitting words at *any pixel, even inside a character*
		;@@ ensure spacing is used for vertical distancing (may forget it :)
		;@@ move canvas constraining into render, remove limits?
		create: function [
			"Build a paragraph layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [align baseline margin spacing canvas fill-x fill-y limits indent force-wrap?]"
			;; settings - imported locally to speed up and simplify access to them:
			/local align baseline margin spacing canvas fill-x fill-y limits indent force-wrap?
		][
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			#debug [typecheck [
				align    [word! (find [left center right fill scale upscale] align) none!]
				baseline [number!]
				margin   [planar! (0x0 +<= margin)]
				spacing  [integer! (0 <= spacing)]		;-- vertical only!
				canvas   [point2D! (0x0 +<= canvas) none!]
				fill-x   [none! logic!]
				fill-y   [none! logic!]
				limits   [object! (range? limits) none!]
				indent   [block! (parse indent [2 [set-word! integer!]]) none!]
			]]
			default canvas: infxinf
			default fill-x: no
			default fill-y: no
			set [map: total-1D:] build-map :spaces 1.0 * baseline
			if empty? map [								;@@ return value needs optimization
				return make frame! compose/only [
					margin:    (margin)
					spacing:   (spacing)
					map:       (map)
					sections:  (reduce [margin/x margin/x])
					x1D->x1D':
					x1D->map:
					y2D->row:  (copy/deep empty-mapping)	;-- single shared mapping is OK since they're read only
				]
			]
			default align:  'left
			default canvas: infxinf						;-- none to pair normalization
			default indent: []
			indent1: any [indent/first 0]
			indent2: any [indent/rest  0]
			
			;; clipped canvas - used to find desired paragraph width
			ccanvas: subtract-canvas constrain canvas limits 2 * margin
			#debug sizing [#print "paragraph canvas=(canvas) ccanvas=(ccanvas)"]
			
			x-1D-to-map-offset: index-map map
			sections: list-sections map total-1D/x
							;-- too hard to adapt the algorithm for that case
			total-1D/x: max 1 total-1D/x				;-- ditto
			words: list-words sections
			total-2D: (ccanvas/x . 0)					;-- without margins
			if any [
				ccanvas/x = 1.#inf						;-- convert infinite canvas into single-row canvas
				not fill-x								;-- contract width if not asked to fill it
			][
				total-2D/x: min total-2D/x total-1D/x
			]
			unless force-wrap? [						;-- extend width to the longest predicted row
				total-2D/x: max total-2D/x get-min-total-width-2D words indent1 indent2
			]
			
			
			;; lay out rows...
			
			indent:            indent1
			nrows:             0
			row-y1-2D:         0
			x-1D-1D'-points:   clear []
			y-irow-points:     clear []
			y-levels:          clear []
			layout-drawn:      clear []
			get-in-row-indent: switch/default align [
				right  [[row-left-width]]
				center [[half row-left-width]]
			] [0]
			while [not tail? words] [
				;; consume some words (or part of a single word)
				row-words: clear []
				row-avail-width: max 1 total-2D/x - indent		;-- disallow rows of 0 pixels ;@@ 1px may still be rather slow!
				set [row-used-width: words:] fill-row row-words words sections row-avail-width align force-wrap?
				
				last-word:  skip tail row-words -4
				row-left-width: max 0 row-avail-width - row-used-width
				
				row-x1-1D:  row-words/1/1
				row-x2-1D:  last-word/1/2				;-- row x1-x2 includes the trailing whitespace, unlike used-width
				row-x1-1D': nrows     * total-2D/x
				row-x2-1D': nrows + 1 * total-2D/x
					;-- empty row only allowed for empty input
				
				;; unify, pad, scale words
				
				if 1 < length? row-words [
					either align <> 'fill [
						group-words row-words			;-- leaves row-words/2 unset (zero)
					][
						if all [
							row-left-width > 0
							not tail? words				;-- don't fill the last row
						][
							distribute-whitespace row-words row-left-width
						]
					]
				]
				if align <> 'fill [
					row-words/2: either find [scale upscale] align
						[row-avail-width][row-used-width]
				]
			
				;; collect x mapping points
				in-row-indent: do get-in-row-indent
				words-offset-1D': row-x1-1D' + indent + in-row-indent
				repend x-1D-1D'-points [
					row-x1-1D row-x1-1D'				;-- left visible row margin (before indenting)
					row-x1-1D words-offset-1D'			;-- indent's end = word's start
				]
				offset-1D': words-offset-1D'
				foreach [word-x-1D word-width-1D' white? _] row-words [		;-- add all words' end
					offset-1D': min row-x2-1D' offset-1D' + word-width-1D'	;-- clip x at row's end
					repend x-1D-1D'-points [word-x-1D/2 offset-1D']
				]
				
				;; measure the row vertically
				set [map-ofs1: map-ofs2:] reproject-range/truncate x-1D-to-map-offset row-x1-1D max row-x1-1D row-x2-1D - 1
				set [row-y1-1D: row-y2-1D:] get-row-y1y2 map map-ofs1 map-ofs2
				row-y2-2D:  row-y1-2D + (row-y2-1D - row-y1-1D)
				row-y0-2D:  row-y2-2D - row-y2-1D
				row-height: row-y2-1D - row-y1-1D
				repend y-levels [row-y0-2D row-y1-2D row-y2-2D]
				repend y-irow-points [row-y1-2D nrows row-y2-2D nrows]	;-- zero-based row number
				; ?? [row-y1-1D row-y2-1D row-y0-2D row-y1-2D row-y2-2D]
				
				;; draw the row
				row-drawn: clear []
				word-offset: 0
				foreach [word-x-1D word-width-1D' white? _] row-words [
					
					word-scale: word-width-1D' / span? word-x-1D
					set [map-ofs1: map-ofs2:] reproject-range/truncate x-1D-to-map-offset word-x-1D/1 word-x-1D/2 - 1
					
					
					geom1: pick map map-ofs1 + 1 * 2
					row-origin-1D: geom1/offset * 1x0
					spaces-drawn: clear []
					for i: map-ofs1 + 1 map-ofs2 + 1 [
						geom: pick map i * 2
						compose-after spaces-drawn [
							translate (geom/offset - row-origin-1D) (geom/drawn)
						]
					]
					
					offset1: geom1/offset/x - word-x-1D/1		;-- negative x offset of 1st space within the word
					
					word-span: span? word-x-1D
					word-drawn: compose/deep/only [
				  		translate (word-offset . 0)				;-- move to the 2D point
						#debug paragraph [push [
							translate (0 . row-y1-1D)
							fill-pen off pen magenta line-width 1
							box 0x0 (word-width-1D' . row-height)
						]]
				  		scale (word-scale) 1.0
				  		clip 0x0 (word-span . total-1D/y)
				  		translate (offset1 . 0)					;-- account for word's offset within geom/size/x
				  		(copy spaces-drawn)
					]
					repend row-drawn ['push word-drawn]
					word-offset: word-offset + word-width-1D'
				]
				word-x1-2D: indent + in-row-indent
				compose-after layout-drawn [
					translate (indent + in-row-indent . row-y0-2D)
					(copy row-drawn)
				]
			
				indent: indent2
				row-y1-2D: row-y2-2D + spacing
				nrows: nrows + 1
			]
			total-2D/y: row-y2-2D
			drawn: compose/only [translate (margin) (copy layout-drawn)]
			total-1D': (last x-1D-1D'-points) . total-1D/y
			
			frame: make frame! compose/only [
				size-1D:   (total-1D)
				size-1D':  (total-1D')
				size-2D:   (total-2D)					;-- size without margins
				margin:    (margin)
				spacing:   (spacing)
				map:       (map)
				sections:  (sections)
				drawn:     (drawn)
				nrows:     (nrows)
				y-levels:  (copy y-levels)
				x1D->x1D': (build-index copy x-1D-1D'-points 1 + round-down total-1D/x / 32)
				x1D->map:  (x-1D-to-map-offset)
				y2D->row:  (build-index copy y-irow-points   1 + round-down total-2D/y / 4)
			]
			
			frame
		]
	]		
	
	ring: context [
		;; settings for ring layout:
		;;   angle    [linear! none!]   unrestricted, defaults to 0
		;;     in degrees - clockwise direction to the 1st item (0 = right, aligns with math convention on XY space)
		;;   radius      [linear!]   >= 0
		;;     minimum distance (pixels) from the center to the nearest point of arranged items
		;;   round?      [logic!]   default: false
		;;     whether items should be considered round, not rectangular
		create: function [
			"Build a ring layout out of given spaces and settings as bound words"
			spaces [block! function!] "List of spaces or a picker func [/size /pick i]"
			settings [block!] "Any subset of [angle radius round?]"
			/local angle radius round?
		][
			func?: function? :spaces
			count: either func? [spaces/size][length? spaces]
			if count <= 0 [return copy/deep [size: (0,0) map: []]]	;-- empty layout optimization
			import-settings settings 'local				;-- free settings block so it can be reused by the caller
			#debug [typecheck [
				angle  [linear! none!]
				radius [linear!] (0 <= radius)
				round? [logic! none!]
			]]
			default angle: 0
			default round?: no
			
			map: make [] 2 * count
			origin: (0,0)
			total:  (0,0)
			step:   360 / count
			
			either round? [
				;; round items are also considered almost equal in size, so it's easy math
				repeat i count [
					space:  either func? [spaces/pick i][spaces/:i]
					
					drawn:  render space
					center: space/size / 2
					rad:    radius + max center/x center/y
					point:  (polar2cartesian rad angle) - center
					compose-after map [
						(space) [offset (pos) size (space/size) drawn (drawn)]
					]
					origin: min origin pos				;-- find leftmost topmost point
					total:  max total pos + space/size	;-- find total dimensions
					angle:  angle + step
				]
			][
				;; measures real distance from the box to 0x0 and pushes `rad` closer to `radius`
				;; input: [size rad angle radius] output: [rad pos r-move]
				adjust-radius: [
					pos:    (polar2cartesian rad angle) - (size / 2)
					r-move: radius - vec-length? closest-box-point? pos pos + size
					rad:    rad + r-move
					pos:    (polar2cartesian rad angle) - (size / 2)
				]
						
				;; initially arrange box centers uniformly around the 0x0 point
				items: make [] count * period: 7
				
				repeat i count [
					space: either func? [spaces/pick i][spaces/:i]
					
					drawn: render space
					size:  space/size
					rad:   radius
					do adjust-radius
					repend items [i space angle rad pos space/size drawn]
					angle: angle + step
				]
				
				;; now repeatedly move boxes around (tangentially) until they look equidistant
				limit: 2								;-- optimization criterion: 2px of irregularity allowed
				loop 10 [								;-- cap at 10 iterations in case of a bug
					max-move: 0
					repeat i count [					;@@ should be for-each but it binds `rad` which adjust-radius modifies
						item-1: skip items i - 2 // count * period
						item:   skip items i - 1          * period
						item+1: skip items i     // count * period
						set [_: _: angle: rad: pos: size:] item
						dist-1: box-distance? pos pos + size o: item-1/5 o + item-1/6
						dist+1: box-distance? pos pos + size o: item+1/5 o + item+1/6
						a-move: dist+1 - dist-1 / 2 / rad * #do keep [180 / pi]
						angle:  angle + a-move
						do adjust-radius
						change change change at item 3 angle rad pos
						max-move: max max max-move abs a-move abs r-move	;@@ should be done with HOFs
					]
					if max-move <= limit [break]		;-- stop optimization attempts
				]
				
				;; lay out boxes into a map and estimate boundaries
				foreach [_ space _ _ pos size drawn] items [
					compose-after map [
						(space) [offset (pos) size (size) drawn (drawn)]
					]
					origin: min origin pos				;-- find leftmost topmost point
					total:  max total pos + size		;-- find total dimensions
				]
			]
			
			frame: compose/only [
				size:   (total - origin)
				map:    (map)
				origin: (origin)						;-- container will auto translate contents if origin is returned
			]
		]
	]
]

export exports

;; <<<<<<<<<< %layouts.red <<<<<<<<<

					
;; >>>>>>>>>> %source.red >>>>>>>>>


;@@ should there be a single items/attributes array for the whole document composed from many paragraphs sources?

;; this context proceeds from lowest level (ranges) to highest level (source) below
rich: context [											;@@ what would be a better name?
	~: self

	;; catalog holds every attribute combo ever encountered
	;; format: [hash [attr value ...] ...] - hash is used to look up by attribute combo (binary is hashed by hash! type)
	;; but normally attributes are indexed by integer (half offset, zero-based), since it's more readable on mold
	;; attrs are in a block because there usually aren't many anyway, no reason to use a map
	;; attr names must always all be lowercase or hashing would have to be slowed down with auto-lowecasing
	;@@ test lowercase in high-level funcs
	catalog: make hash! 1024
	
	hash-attrs: function [attrs [block!]] [
		attrs: sort/skip append clear [] attrs 2				;-- sort to guarantee uniqueness of the combo
		checksum (native-mold/all/flat/only attrs) 'sha1		;-- native mold is much faster than save into redbin
	]
	
	store-attrs: function [attrs [block!]] [
				;-- only truthy values are allowed for attrs
		hash: hash-attrs attrs
		unless pos: find catalog hash [
			pos: tail catalog 
			repend catalog [hash copy/deep attrs]
		]
		half skip? pos
	]
	
	index->attrs: function [index [integer!]] [
		copy/deep pick catalog index + 1 * 2			;-- copy ensures attrs are never modified in place
	]
	
	attrs->index: function [attrs [block!]] [
		hash: hash-attrs attrs
		if pos: find catalog hash [half skip? pos]
	]
	
	store-attrs []										;-- empty attribute set is always present and has zero index
	
	
	
	ranges: context [
		to-rtd-pair: function [
			"Convert source range into RTD range"
			range [pair!]
		][
			range/1 + 1 thru span? range
		]
	
		from-rtd-pair: function [
			"Convert RTD range into source range"
			range [pair!]
		][
			0 thru range/2 + range/1 - 1
		]
		
		
		
	]
		
	extract-ranges: function [data [block!] (even? length? data)] [
		ranges: clear []
		range-code: 0
		offset:     0
		flush: [
			if range-code > 0 [
				range: range-start thru offset
				attrs: index->attrs range-code
				repend ranges [range attrs]
			]
		]
		foreach [item code] data [						;@@ use for-each
			if code <> range-code [
				do flush
				range-start: offset
				range-code:  code
			]
			offset: offset + 1
		]
		do flush
		copy ranges
	]
	
	

	;; external context allows me to use /copy word without shadowing the global one
	attributes: context [
		to-rtd-flag: make-rtd-flags: change: mark: clear: pick: exclude: compatible?: none
	]
	
	attributes/to-rtd-flag: function [attr [word!] value [tuple! logic! string! integer!]] [
		switch attr [
			bold italic underline strike [attr]
			color size font [value]
			backdrop [compose [backdrop (value)]]
		]
	]
	
		
	value-types!: make typeset! [tuple! logic! string! integer!]
	rtd-attrs: make hash! [bold italic underline strike color backdrop size font]
	
	attributes/make-rtd-flags: function [
		"Make an RTD flags block out of data attributes"
		data [block!] limits [pair!] "segment to extract"		;-- segment used in to-spaces to create individual paragraphs
	][
		limits: clip limits 0 half length? data
		data:   append/part clear [] (skip data limits/1 * 2) (2 * span? limits)
		result: clear []
		ranges: extract-ranges data
		foreach [range attrs] ranges [ 
			flags: clear []
			pair: ~/ranges/to-rtd-pair range
			foreach [attr value] attrs [						;@@ use map-each
				unless find value-types! type? :value [
					ERROR "rich-content attribute value cannot be (type? :value) = (mold/flat/part :value 60)"
				]
				attr: attributes/to-rtd-flag to word! attr value
				if attr [append append flags pair attr]			;-- only collects attributes supported by RTD
			]
			append result flags
		]
		copy result
	]
	
	
	
	attributes/change: function [
		attrs [block!] "modified"
		attr  [word!]
		value
	][
		pos: find/skip attrs attr 2
		either :value [
			change/only change any [pos tail attrs] attr :value
		][
			remove/part pos 2
		]
		attrs
	]
	
	attributes/mark: function [							;@@ maybe rename to set! ?
		data  [block!] "modified" (parse data [end | 1 3 [skip integer!] to end])
		range [word! ('all = range) pair!]
		attr  [word!]
		value
	][
		if range = 'all [range: 0 thru 2e9]
		range: clip range 0 half length? data			;-- avoid runaway repeat if range is infinite
		repeat i span? range [							;@@ use for-each!
			code: pick data i2: range/1 + i * 2
			either last-code = code [					;-- streaming optimization
				code: new-code
			][
				attrs: copy index->attrs last-code: code
				attributes/change attrs attr :value
				new-code: code: store-attrs attrs
			]
			data/:i2: code 
		]
		data
	]
	
	
	;; unlike /mark, clears all attributes in the range
	attributes/clear: function [
		data  [block!] "modified" (parse data [end | 1 3 [skip integer!] to end])
		range [word! ('all = range) pair!]
	][
		if range = 'all [range: 0 thru 2e9]
		range: clip range 0 half length? data			;-- avoid runaway repeat if range is infinite
		repeat i span? range [poke data (range/1 + i * 2) 0]	;@@ use map-each/self!
		data
	]
	
	attributes/pick: function [attrs [integer! block!] attr [word!]] [
		if integer? attrs [attrs: index->attrs attrs]
		select/skip attrs attr 2 
	]
	
	
	attributes/exclude: function [set1 [block!] set2 [block!]] [
		result: copy set1
		remove-each [name value] result [
			:value == select/case/skip set2 name 2
		]
		result
	]
	
	
	;; used to split text on font size change, to ease alignment
	attributes/compatible?: function [index1 [integer!] index2 [integer!]] [
		to logic! any [
			index1 =? index2
			all [
				attrs1: index->attrs index1
				attrs2: index->attrs index2
				size1: select/skip attrs1 'size 2 
				size2: select/skip attrs2 'size 2
				size1 =? size2 
				font1: select/skip attrs1 'font 2 
				font2: select/skip attrs2 'font 2 
				font1 = font2
			]
		]
	]
	
	
	source: context [deserialize: serialize: format: to-spaces: none]

	source/format: function [
		"Convert decoded source into plain text"
		data [block!] "[item attr ...] block" (even? length? data)
		/local format: {}								;-- used when item has no /format in the kit
	][
		result: make {} half length? data
		foreach [item attr] data [						;@@ use map-each
			case [
				char?  :item [append result item]
				space? :item [append result batch item [format]]
			]
		]
		#debug clipboard [#print "  rich/source/format: (mold/part result 120)"]
		result
	]
	
	
	;@@ leverage prototypes for this
	source/to-spaces: function [
		"Transform decoded source into a list of spaces (for use in rich-content)"
		data [block!] "[item attr ...] block" (even? length? data)
		; return: [block!] "[content ranges]"
		/local char
	][
		content: clear []
		ranges:  clear []								;-- range spans of items that caret can dive into
		;@@ or trim linefeed? or silently split into multiple paragraphs (hard)?
		
		buf:     clear {}
		parse data [any [
			[	s: [set char char! set attr1 integer! (append buf char)]
				any [
					set char char! set attr2 integer!
					if (attributes/compatible? attr1 attr2) (append buf char)
				] e: (
					append content obj: make-space 'text []
					append obj/text buf
					clear buf
					range: half as-pair skip? s skip? e
					obj/flags: attributes/make-rtd-flags data range
				)
			|	set obj [object! integer!] (			;@@ apply attribute to the object?
					append content obj
					range: 0x1 + half skip? s
				)
			] (repend ranges [obj range])
		|	end
		|	(ERROR "Unsupported data in the source: (mold/part s 40)")
		]]
		reduce [copy content  make hash! ranges]
	]
		
	source/deserialize: function [
		"Split source into decoded block of [item attr ...]"
		source [block!]
		/local attr value item
	][
		result: clear []								;@@ should items be just chars and objects? other types support, e.g. image?
		attrs:  clear []
		parse source [any [
			set attr [
				word! (value: on)
			|	set-word! p: (value: do/next p 'p) :p	;-- reduce words (color names) to their values
			]
			(attributes/change attrs to word! attr :value)
		|	set attr refinement!						;-- attributes work stack-like and do not close automatically
			(attributes/change attrs to word! attr none)
		|	set item string! (							;@@ make it a module
				code: store-attrs attrs
				zip/into explode item code result
			)
		|	set item skip (
				code: store-attrs attrs
				repend result [item code]
			)
		]]
		copy result
	]
	
	
	source/serialize: function [
		"Create a source block out of decoded data"
		data [block!] "[item attr ...] block" (even? length? data)
	][
		result:     clear []
		string:     clear {}
		last-attrs: clear []
		last-code:  0
		flush-string: [
			unless empty? string [
				append result copy string
				clear string
			]
		]
		foreach [item code] data [
			if last-code <> code [
				do flush-string
				attrs: index->attrs last-code: code
				opened: attributes/exclude attrs last-attrs 2	;-- native 'exclude' is useless since it ignores value slot
				closed: attributes/exclude last-attrs attrs 2
				last-attrs: attrs
				foreach [name value] closed [			;@@ use map-each
					append result to refinement! name
				]
				foreach [name value] opened [			;@@ use map-each
					repend result either true = :value [[name]] [[to set-word! name :value]]
				]
			]
			either char? :item [
				append string item
			][
				do flush-string
				append/only result :item
			]
		]
		do flush-string
		;@@ no reason to auto-close opened attributes?
		copy result
	]
	
	
]

;; <<<<<<<<<< %source.red <<<<<<<<<

					
;; >>>>>>>>>> %clipboard.red >>>>>>>>>
	

exports: [clipboard]

clipboard: context [
	;; prototype for custom clipboard formats
	text!: make classy-object! format!: declare-class 'clipboard-format [
		name:   'text							#type [word!]
		data:   {}
		length: does [length? data]				#type [function!]
		format: does [system/words/copy data]	#type [function!]	;-- must return text only
		copy:   does [system/words/copy self]	#type [function!]	;-- must return shallow copy
		clone:  does [system/words/copy self]	#type [function!]	;-- must clone everything inside or omit
	]
	
	;; text is used to detect if some other program wrote to clipboard
	;; if read text = last written text, we can use `data`
	;; otherwise data is invalid and clipboard is read as plain text string
	
	data: copy text!									;-- last copied data
	
	read: function [
		"Get clipboard contents"
		/text "Return text even if data is non-textual"
		/extern data
	][
		read: read-clipboard
		unless string? read [read: copy {}]				;@@ support wrapping of other clipboard formats? image?
		unless read == as-text: data/format [			;-- last copy comes from outside the running script
			self/data: make text! [data: read]
			if text [as-text: data/format]
		]
		either text [as-text][data/clone]
	]
	
	write: function [
		"Write data to clipboard"
		content [object! ('clipboard-format = class? content) string!]
	][
		self/data: either string? content
			[make text! [data: system/words/copy content]]
			[content/clone]
		write-clipboard self/data/format
	]
]

export exports
;; <<<<<<<<<< %clipboard.red <<<<<<<<<

					
;; >>>>>>>>>> %templates.red >>>>>>>>>


;-- requires `for` loop from auxi.red, layouts.red, clipboard.red, export
exports: [make-space declare-template space?]

;@@ I need to move out the core functionality from here out, leave only templates

space-object!: copy classy-object!

templates: #[]											;-- map for extensibility

;; default on-change function to avoid replicating it in every template
invalidates: function [space [object!] word [word!] value [any-type!]] [
	#debug changes [#print "change/size of (space/type)/(word) to (mold/flat/part :value 40)"]
	invalidate space
]

invalidates-look: function [space [object!] word [word!] value [any-type!]] [
	#debug changes [#print "change/look of (space/type)/(word) to (mold/flat/part :value 40)"]
	invalidate/info space none 'look
]

;; normalizes /margin & /spacing to a pair, for easier handling
on-margin-spacing-change: function [space [object!] word [word!] value [linear! planar!] old [any-type!]] [
	if :old <> value [
		quietly space/:word: new: (1,1) * value			;-- force margin into correct type
		if :old <> new [invalidates space word new]		;-- only invalidate if really changed
	] 
]

templates/space: declare-class 'space [					;-- minimum basis to build upon
	type:	'space		#type = [word!]					;-- used for styling and event handler lookup, may differ from template name!
	size:   (0,0)		#type = [point2D! (0x0 +<= size)]	;-- none (infinite) must be allowed explicitly by templates supporting it
	parent: none		#type   [object! none!]
	draw:   :no-draw  	#type   [function!]
	;; `drawn` is an exception and not held in the space, so just `size`:
	cache:  [size]		#type   [block! none!]
	cached: tail copy [(0,0) 0.0 #(none)]	#type [block!]	;-- used internally to check if space is connected to the tree, and holds cached facets
	limits: none		#type   [object! (range? limits)  none!] :invalidates
	; rate: none
]

;; a trick not to enforce some facets (saves RAM) but still provide default typechecks for them:
;; (specific values are only for readability here and they have no effect)
modify-class 'space [
	map:     []		#type [block!]
	into:    none	#type [function!]
	;; rate change -> invalidation -> next render puts it into rated-spaces list
	rate:    none	#type =  [linear! time! (rate >= 0) none!]
	color:   none	#type =? :invalidates-look [tuple! none!]
	margin:  0x0	#type =  :on-margin-spacing-change [linear! planar!] (0x0 +<= ((1,1) * margin))
	spacing: 0x0	#type =  :on-margin-spacing-change [linear! planar!] (0x0 +<= ((1,1) * spacing))
	weight:  0		#type =  :invalidates [number!] (weight >= 0)
	origin:  (0,0)	#type =  :invalidates-look [point2D!]
	font:    none	#type =? :invalidates [object! none!]	;-- can be set in style, as well as margin ;@@ check if it's really a font
	command: []		#type [block! paren!]
	kit:     none	#type [object!]
	on-invalidate: 	#type [function! none!]
]	

space?: function ["Determine of OBJ is a space! object" obj [any-type!]] [
	all [
		object? :obj
		any [
			templates/(class? obj)						;-- fast check, but will fail for e.g. list-in-list-view
			all [										;-- duck check ;@@ what words are strictly required to qualify?
				in obj 'cached							;-- starts with less common words ;@@ needs REP #102
				in obj 'cache
				in obj 'limits
				in obj 'parent
				in obj 'type
				in obj 'size
				in obj 'draw
			]
		]
	]
]

make-space: function [
	"Create a space from a template TYPE"
	type [word!]  "Looked up in templates"
	spec [block!] "Extension code"
	/block "Do not instantiate the object"
][
	base: templates/:type
	
	r: append copy/deep base spec
	unless block [
		;; without trapping it's impossible to tell where the error happens during creation if it's caused e.g. by on-change
		e: trap/catch [r: make space-object! r] [			;@@ slower than `try` by 5% on make-space 'space []
			#print "*** Unable to make space of type (type):"
			do thrown
		]
		;; replace the type if it was not enforced by the template:
		;; `class?` is used instead of `type` to force `<->` have type `stretch`
		if r/type = 'space [quietly r/type: class? r]
	]
	r
]

remake-space: function [
	"Safely create a space from a template TYPE"
	type [word!]  "Looked up in templates"
	spec [block!] "Extension code - composed, not evaluated"
][
	also r: make-space type []
	do bind compose/only spec r
]

;; doesn't copy objects: font should be shared and child spaces can't be just copied like that ;@@ but /limits?
;; used mainly for copy/paste functionality
copied!: make typeset! [series! bitset! map!]
clone-space: function [
	"Make a space that is a copy of ORIGINAL, carrying data but not state"
	original [object!] (space? original)
	words    [block!] "Only these words are copied, rest is reset to defaults"
][
	clone: make-space original/type []
	clone/size: original/size
	clone/limits: if object? value: original/limits [copy value]	;-- the only object copied
	foreach word words [
		if word: in clone word [						;-- allow specifying more words (e.g. command in link but not text)
			value: select original word					;-- no get/any or set-quiet by design, to maintain consistency via on-change
			set word either find copied! type? :value [copy/deep :value][:value]
		]
	]
	clone
]

make-template: function [
	"Create a space template"
	base [word!]  "Type it will be based on"  
	spec [block!] "Extension code"
][
	make-space/block base spec
]

;; #push directive expands into #on-change directive for classy-object's declare-class func
;;   it pushes every facet change into all targets (used to expose inner facets into outer template)
;;   and then back from targets into the source (because children may modify the source, e.g. convert margin into pair value)
;; syntax:
;;   facet: value  #push target/path							;-- accepts a path
;;   facet: value  #push [target/path1 target/path2 ...]		;-- or block of paths
;; spaces do not export any macros by design, so this function call is required when using #push in declare-class directly
expand-template: function [
	"Expand template directives"
	spec [block!] "Only #push is supported at the moment"
	/local path
][
	mapparse [#push set path [path! | block!]] copy spec [
		paths: either path? path [reduce [path]][path]
		body: collect [
			foreach path paths [
				insert path: copy path 'space
				keep compose [
					(to set-path! path) :value					;-- pushes the value forth
					quietly space/:word: (to get-path! path)	;-- mirrors back its corrected value
				]
			]
		]
		compose/only [#on-change [space word value] (body)]
	]
]

declare-template: function [
	"Declare a named class and put into space templates"
	name-base [path!] "template-name/prototype-name"
	spec      [block!]
][
	set [name: base:] name-base
	templates/:name: make-template base declare-class name-base expand-template spec
]


;-- helps having less boilerplate when `map` is straightforward
compose-map: function [
	"Build a Draw block from MAP"
	map "List of [space [offset XxY size XxY] ...]"
	/only list [block!] "Select which spaces to include"
	/window xy1 [point2D!] xy2 [point2D!] "Specify viewport"	;@@ it's unused; remove it?
][
	r: make [] round/ceiling/to (1.5 * length? map) 1	;-- 3 draw tokens per 2 map items
	foreach [space box] map [
		all [list  not find/same list space  continue]	;-- skip names not in the list if it's provided
		; all [limits  not boxes-overlap? xy1 xy2 o: box/offset o + box/size  continue]	;-- skip invisibles ;@@ buggy - requires origin
		cmds: render/:window space xy1 xy2
		unless any [
			empty? cmds									;-- don't spawn empty translate/clip structures
			zero? area? box/size						;-- don't render empty elements (also works around #4859)
		][
			compose-after r [translate (box/offset) (cmds)]
		]
	]
	r
]


declare-template 'timer/space [							;-- template space for timers
	rate:  0											;-- unlike space, must always have a /rate facet
	cache: none
]		

;; used by some templates that don't draw anything
no-draw: does [[]]

;; used internally for empty spaces size estimation
set-empty-size: function [space [object!] canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
	canvas: either all [w: select space 'weight  w > 0]
		[fill-canvas canvas fill-x fill-y][(0,0)]		;-- don't stretch what isn't supposed to stretch
	space/size: constrain canvas space/limits
]

;; empty stretching space used for alignment ('<->' alias still has a class name 'stretch')
context [
	~: self
	
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		set-empty-size space canvas fill-x fill-y
		[]
	]
	
	put templates '<-> declare-template 'stretch/space [	;@@ affected by #5137
		weight: 1
		cache:  none
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			~/draw self canvas fill-x fill-y
		]
	]
]

rectangle-ctx: context [
	~: self
	
	declare-template 'rectangle/space [
		size:   (20,10)	#on-change :invalidates
		margin: 0
		draw:   does [compose [box (margin) (size - margin)]]
	]
]

;@@ maybe this should be called `arrow`? because it doesn't have to be triangle-styled
triangle-ctx: context [
	~: self
	
	draw: function [space [object!]] [
		set [p1: p2: p3:] select [
			n [(0,2) (1,0) (2,2)]						;--   n
			e [(0,0) (2,1) (0,2)]						;-- w   e
			w [(2,0) (0,1) (2,2)]						;--   s
			s [(0,0) (1,2) (2,0)]
		] space/dir
		rad: space/size / 2 - space/margin
		compose/deep [
			translate (space/margin) [triangle (p1 * rad) (p2 * rad) (p3 * rad)]
		]
	]
		
	declare-template 'triangle/space [
		size:    (16,10)	#on-change :invalidates
		dir:     'n			#type =    :invalidates [word!] (find [n s w e] dir)
		margin:  0
		
		;@@ need `into` here? or triangle will be a box from the clicking perspective?
		draw: does [~/draw self]
	]
]

image-ctx: context [
	~: self
	
	draw: function [image [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		mrg2: 2 * mrg: image/margin
		switch type?/word image/data [
			none! [
				image/size: constrain mrg2 image/limits			;-- empty image should obey constraints too
				[]
			]
			;@@ this feature needs to be doc'd but I'm not sure about it,
			;@@ since it fills all canvas up to /limits but draw code knows nothing about canvas size
			block! [
				image/size: constrain finite-canvas canvas image/limits
				free: subtract-canvas image/size mrg2
				compose/only [translate (mrg) clip 0x0 (free) (image/data)]
			]
			image! [
				limits:        image/limits
				isize:         image/data/size
				;; `constrain` isn't applicable here because doesn't preserve the ratio, and because of canvas handling
				if all [limits  limits/min  low-lim:  max (0,0) limits/min - mrg2] [	;@@ REP #113 & 122
					min-scale: max  low-lim/x / isize/x  low-lim/y / isize/y	;-- use bigger one to not let it go below low limit
				]
				if all [limits  limits/max  high-lim: max (0,0) limits/max - mrg2] [	;@@ REP #113 & 122
					max-scale: min  high-lim/x / isize/x  high-lim/y / isize/y	;-- use lower one to not let it go above high limit
				]
				if all [image/weight > 0  canvas <> infxinf] [		;-- if inf canvas, will be unscaled, otherwise uses finite dimension
					set-pair [cx: cy:] subtract-canvas canvas mrg2
					canvas-max-scale: min  cx / isize/x  cy / isize/y	;-- won't be bigger than the canvas
					if fill-x [cx: 1.#inf]							;-- don't stick to dimensions it's not supposed to fill
					if fill-y [cy: 1.#inf]  
					canvas-scale: min  cx / isize/x  cy / isize/y	;-- optimal scale to fill the chosen canvas dimensions
					canvas-scale: min canvas-scale canvas-max-scale
				]
				default min-scale:    0.0
				default max-scale:    1.#inf
				default canvas-scale: 1.0
				scale: clip canvas-scale min-scale max-scale 
				; echo [canvas fill low-lim high-lim scale min-scale max-scale lim isize]
				image/size: (to point2D! isize) * scale + (2 * mrg)
				reduce ['image image/data mrg image/size - mrg]
			]
		]
	]

	declare-template 'image/space [
		margin: 0
		weight: 0
		data:   none	#type =? :invalidates [none! image! block!]		;-- images are not recyclable, so `none` by default
		
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


cell-ctx: context [
	~: self

	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		#debug sizing [#print "cell/draw with (if space/content [space-id space/content]) on (canvas) (fill-x) (fill-y)"]
		space/sec-cache: copy []						;-- alloc new (minimal) sections block for new canvas
		unless space/content [
			set-empty-size space canvas fill-x fill-y
			return quietly space/map: []
		]
		canvas:  constrain canvas space/limits
		mrg2:    space/margin * 2
		content: space/content
		drawn:   render/on content (subtract-canvas canvas mrg2) fill-x fill-y
		size:    content/size + mrg2
		;; canvas can be infinite or half-infinite: inf dimensions should be replaced by space/size (i.e. minimize it)
		size:    max size fill-canvas canvas fill-x fill-y		;-- only extends along fill-enabled axes
		space/size: constrain size space/limits
		; #print "size: (size) space/size: (space/size) fill: (fill-x) (fill-y) limits: (space/limits)"
		
		free:   space/size - content/size - mrg2
		offset: (to point2D! space/margin) + max (0,0) free * (space/align + 1) / 2
		unless tail? drawn [
			drawn: compose/only [translate (offset) (drawn)]
			unless fits?: content/size +<= space/size [			;-- only use clipping when required! (for drop-downs)
				drawn: compose/only [clip 0x0 (space/size) (drawn)]
			]
		]
		quietly space/map: compose/deep [(space/content) [offset: (offset) size: (space/size)]]
		#debug sizing [#print "box with (mold space/content) on (canvas) -> (space/size)"]
		drawn
	]
	
	kit: make-kit 'box [
		clone: function [] [
			cloned: clone-space space [align margin weight command]
			all [
				space? child: select space 'content
				object? ckit: select child 'kit
				function? select ckit 'clone
				cloned/content: batch child [clone]
			]
			cloned
		]
		format: function [] [
			format: copy {}								;-- used when child has no format
			all [
				child: space/content
				format: batch child [format]
			]
			#debug clipboard [#print "  box/format (\(space-id space): (mold/part format 120)"]
			format
		]
		frame: object [
			sections: does [generate-sections space/map space/size/x space/sec-cache]
		]
	]
	
	declare-template 'box/space [
		kit:     ~/kit
		;; margin is useful for drawing inner frame, which otherwise would be hidden by content
		margin:  0
		weight:  1										;@@ what default weight to use? what default alignment?
		;@@ consider more high level VID-like specification of alignment
		align:   0x0	#type =? :invalidates-look [pair!] (-1x-1 +<= align +<= 1x1)
		content: none	#type =? :invalidates [object! none!]
		;@@ should /color be always present?
		
		map:     []
		cache:   [size map sec-cache]
		sec-cache: []									;-- holds last valid sections block if computed
		
		;; draw/only can't be supported, because we'll need to translate xy1-xy2 into content space
		;; but to do that we'll have to render content fully first to get it's size and align it
		;; which defies the meaning of /only...
		;; the only way to use /only is to apply it on top of current offset, but this may be harmful
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
	
	declare-template 'cell/box [margin: 1x1]			;-- same thing just with a border and background ;@@ margin - in style?
]

;@@ TODO: externalize all functions, make them shared rather than per-object
;@@ TODO: automatic axis inferrence from size?
scrollbar: context [
	~: self
	
	into: func [space [object!] xy [planar!] child [object! none!]] [
		any [space/axis = 'x  xy: reverse xy]
		into-map space/map xy child
	]
	
	arrange: function [content [block!]] [				;-- like list layout but simpler/faster
		map: make block! 2 * length? content
		pos: (0,0)
		foreach name content [	;@@ should be map-each
			space: get name
			append map compose/deep [
				(space) [offset: (pos) size: (space/size)]
			]
			pos: space/size * (1,0) + pos
		]
		map
	]
	
	draw: function [space [object!]] [
		size2: either space/axis = 'x [space/size][reverse space/size]
		h: size2/y  w-full: size2/x
		w-arrow: size2/y * space/arrow-size
		w-inner: w-full - (2 * w-arrow)
		;-- in case size is too tight to fit the scrollbar - compress inner first, arrows next
		if w-inner < 0 [w-arrow: w-full / 2  w-inner: 0]
		w-thumb: case [									;-- 3 strategies for the thumb
			w-inner >= (2 * h) [max h w-inner * space/amount]	;-- make it big enough to aim at
			w-inner >= 8       [      w-inner * space/amount]	;-- better to have tiny thumb than none at all
			'else              [0]								;-- hide thumb, leave just the arrows
		]
		w-pgup: w-inner - w-thumb + (w-inner * space/amount) * space/offset
		w-pgdn: w-inner - w-pgup - w-thumb
		quietly space/back-arrow/size:  w-arrow . h
		quietly space/back-page/size:   w-pgup  . h
		quietly space/thumb/size:       w-thumb . h
		quietly space/forth-page/size:  w-pgdn  . h
		quietly space/forth-arrow/size: w-arrow . h
		space/map: arrange with space list: [back-arrow back-page thumb forth-page forth-arrow]
		
		foreach item list [invalidate/only get item]
		compose/deep [
			push [
				matrix [(select [x [1 0 0 1] y [0 1 1 0]] space/axis) 0 0]
				(compose-map space/map)
			]
		]
	]
	
	declare-template 'scrollbar/space [
		;@@ maybe leverage canvas size?
		;@@ size should not cause invalidation here, or each deep cache fetch sets it, repainting whole tree
		size:       (100,16)	;#type =? :invalidates		;-- opposite axis defines thickness
		axis:       'x		#type =  :invalidates [word!] (find [x y] axis)
		offset:     0%		#type =  :invalidates-look [number!] (all [0 <= offset offset <= 1])
		amount:     100%	#type =  :invalidates-look [number!] (all [0 <= amount amount <= 1])
		;; arrow length in percents of scroller's thickness:
		arrow-size: 90%		#type =  :invalidates-look [number!] (0 <= arrow-size) 
		
		map:         []
		cache:       [size map]
		back-arrow:  make-space 'triangle  [type: 'back-arrow  margin: 2  dir: 'w] #type (space? back-arrow)	;-- go back a step
		back-page:   make-space 'rectangle [type: 'back-page   draw: :no-draw]     #type (space? back-page)		;-- go back a page
		thumb:       make-space 'rectangle [type: 'thumb       margin: 2x1]        #type (space? thumb)			;-- draggable
		forth-page:  make-space 'rectangle [type: 'forth-page  draw: :no-draw]     #type (space? forth-page)	;-- go forth a page
		forth-arrow: make-space 'triangle  [type: 'forth-arrow margin: 2  dir: 'e] #type (space? forth-arrow)	;-- go forth a step
		
		into: func [xy [planar!] /force space [object! none!]] [~/into self xy space]
		draw: does [~/draw self]
	]
]

scrollable-ctx: context [
	~: self

	set-origin: function [
		space   [object!]
		origin  [point2D! word!]
		no-clip [logic!]
	][
		unless no-clip [
			csize: space/content/size
			box:   min csize space/viewport					;-- if viewport > content, let origin be 0x0 always
			origin: clip origin box - csize 0x0
		]
		space/origin: origin
	]
	
	;@@ or /line /page /forth /back /x /y ? not without apply :(
	;@@ TODO: less awkward spec possible?
	move-by: function [
		space   [object!]
		amount  [word! linear!]
		dir     [word!]
		axis    [word!]
		scale   [number! none!]
		no-clip [logic!]
	][
		dir:  select [forth 1 back -1] dir
		unit: axis2pair axis
		default scale: either amount = 'page [0.8][1]
		switch amount [line [amount: 16] page [amount: space/size]]		;@@ hardcoded 16 offset
		set-origin space space/origin - (amount * scale * unit * dir) no-clip
	]

	move-to: function [
		space     [object!]
		xy        [planar! word!] "Point in content coordinates or [head tail]"
		margin: 0 [linear! planar! none!]		;-- space to reserve around XY
		no-clip   [logic!]
	][
		mrg: margin * (1,1)
		switch xy [
			head [xy: (0,0)]
			tail [xy: space/content/size * 0x1]			;-- no right answer here, csize or csize*0x1 ;@@ won't work for infinity
		]
		box: space/viewport
		mrg: clip (0,0) mrg box - 1 / 2					;-- if box < 2xmargin, choose half box size as margin
		xy1: mrg - space/origin							;-- left top margin point in content's coordinates
		xy2: xy1 + box - (mrg * 2)						;-- right bottom margin point
		dxy: (0,0)
		foreach x [x y] [
			case [
				xy/:x < xy1/:x [dxy/:x: xy/:x - xy1/:x]
				xy/:x > xy2/:x [dxy/:x: xy/:x - xy2/:x]
			]
		]
		set-origin space space/origin - dxy no-clip
		; ?? [box mrg xy1 xy2 xy dxy space/origin]
	]

	into: function [space [object!] xy [planar!] child [object! none!]] [
		if r: into-map space/map xy child [
			all [
				r/1 =? space/content
				r/2: r/2 - space/origin
				not any [child  r/2 inside? space/content]
				r: none
			]
		]
		r
	]

	;; sizing policy (for cell, scrollable, window):
	;; - use content/size if it fits the canvas (no scrolling needed) and no fill flag is set
	;; - use canvas/size if it's less than content/size or if fill flag is set
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		;; apply limits in the earnest - canvas size will become the upper limit
		;@@ maybe render should do this?
		canvas: constrain canvas space/limits
		
		;; canvas and fill flags used by scrollable are not the same as those given to its content
		;; content-flow disables filling for inf dimensions to avoid glitches
		;; but leaves canvas finite, mainly for window to properly size itself (it can't on infinity)
		cfill-x: cfill-y: no
		ccanvas: canvas									;-- canvas for the child space - may differ by scroller size
		switch space/content-flow [
			vertical   [cfill-x: fill-x]
			horizontal [cfill-y: fill-y]
		]
		
		;; empty canvas or no content just leads to canvas filled according to content-flow rules (optimization)
		content: space/content
		if any [
			not content 
			zero? area? canvas
		][
			set-empty-size space canvas cfill-x cfill-y
			return quietly space/map: []
		]
		
		;; two rendering flows possible: with scrollbar subtracted and without it
		;; it is more correct to start without it, though this also leads to double render of big content
		;; an unfortunate slowdown, but mostly alleviated by caching
		hscroll:   space/hscroll
		vscroll:   space/vscroll
		scrollers: vscroll/size/x . hscroll/size/y
		cdrawn:    render/on content ccanvas cfill-x cfill-y
		sshow:     0x0											;-- scrollers show mask 0=hidden, 1=visible
		if all [
			axis: switch space/content-flow [vertical ['y] horizontal ['x]]
			content/size/:axis > canvas/:axis
		][														;-- have to add the scroller and subtract it from canvas width
			sshow/:axis: 1										;-- for long vertical reduce xsize and enable vscroll
			ccanvas: subtract-canvas ccanvas (scrollers * reverse sshow)
			cdrawn: render/on content ccanvas cfill-x cfill-y
		]
		
		viewport: min canvas ccanvas							;-- viewport is area not occupied by scrollbars
		csize:    content/size
		origin:   space/origin									;-- must be read after render (& possible roll)
		;; no origin clipping can be done here, otherwise it's changed during intermediate renders
		;; and makes it impossible to scroll to the bottom because of window resizes!
		;; clipping is done by /clip-origin, usually in event handlers where size & viewport are valid (final)
		
		;; determine what scrollers to show
		loop 2 [												;-- each scrollbar affects another's visibility
			if viewport/x < csize/x [sshow/x: 1]
			if viewport/y < csize/y [sshow/y: 1]
			;; 'reverse' because sshow/x means _horizontal_ scroller which eats up _vertical_ space
			viewport: subtract-canvas canvas scrollers * reverse sshow	;-- viewport may be infinite if canvas is
		]
		;; quiet to avoid deep invalidation
		quietly hscroll/size: (viewport/x * sshow/x) . hscroll/size/y	;-- masking avoids infinite size
		quietly vscroll/size: vscroll/size/x . (viewport/y * sshow/y)
		
		;; final size is viewport + free space filled by fill flags + scrollbars
		free:   subtract-canvas viewport csize
		hidden: subtract-canvas csize viewport
		desired-size: (min viewport csize) + (fill-canvas free fill-x fill-y) + (scrollers * reverse sshow)
		space/size: constrain desired-size space/limits			;-- constrain again: with fill=0 limits/min may be missed by canvas
		; ?? [free fill-x fill-y space/size]
		; ?? [canvas ccanvas viewport csize sshow free hidden space/size]
		
		;; set scrollers but avoid multiple recursive invalidation when changing srcollers fields
		;; (else may stack up to 99% of all rendering time)
		;@@ maybe move this into the scrollers?
		csize': max 1x1 csize							;-- avoid division by zero
		quietly hscroll/amount: 100% * amnt: min 1.0 viewport/x / csize'/x
		quietly hscroll/offset: 100% * clip 0 1 - amnt (negate origin/x) / csize'/x
		quietly vscroll/amount: 100% * amnt: min 1.0 viewport/y / csize'/y
		quietly vscroll/offset: 100% * clip 0 1 - amnt (negate origin/y) / csize'/y
		
		;@@ TODO: fast flexible tight layout func to build map? or will slow down?
		unless fits? [render space/scroll-timer]				;-- scroll-timer has to appear in the tree for timers
		space/scroll-timer/rate: pick [0 16] fits?: sshow = 0x0	;-- turns off timer when unused!
		viewport: space/size - (scrollers * reverse sshow)		;-- include 'free' size in the viewport
		quietly space/map: reshape [
			@(content) [offset: (0,0) size: @(viewport)]
			@(hscroll) [offset: @(viewport * 0x1) size: @(hscroll/size)]	/if sshow/x = 1
			@(vscroll) [offset: @(viewport * 1x0) size: @(vscroll/size)]	/if sshow/y = 1
			@(space/scroll-timer) [offset: (0,0) size: (0,0)]				/if not fits?	;-- list it for tree correctness
		]
		
		invalidate/only hscroll									;-- let scrollers know they were changed
		invalidate/only vscroll
		
		cdrawn: compose/only [translate (origin) (cdrawn)]
		unless fits? [cdrawn: compose/only [clip 0x0 (viewport) (cdrawn)]]	;-- only use clipping when required! (for drop-down)
		compose/only [(cdrawn) (compose-map/only space/map reduce [hscroll vscroll])]
	]
		
	kit: make-kit 'scrollable [
		format: function [] [
			format: copy {}								;-- used when child has no format
			all [
				child: space/content
				format: batch child [format]
			]
			#debug clipboard [#print "  scrollable/format (space-id space): (mold/part format 120)"]
			format
		]
	]
	
	declare-template 'scrollable/space [
		kit:          ~/kit
		;; at which point `content` to place: >0 to right below, <0 to left above:
		origin:       (0,0)
		weight:       1
		content:      none		#type =? :invalidates [object! none!]	;-- should be defined (overwritten) by the user
		content-flow: 'planar	#type =  :invalidates [word!] (find [planar horizontal vertical] content-flow)
		
		hscroll:  make-space 'scrollbar [type: 'hscroll axis: 'x]						#type (space? hscroll)
		vscroll:  make-space 'scrollbar [type: 'vscroll axis: 'y size: reverse size]	#type (space? vscroll)
		;; timer that scrolls when user presses & holds one of the arrows
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		scroll-timer: make-space 'timer [type: 'scroll-timer]							#type (space? scroll-timer)

		map:   []
		cache: [size map]

		behavior: make map! [draggable: pan]			;-- dragging: false=disabled; pan=pan content; scroll=scroll when out of the viewport
		
		;@@ temporary kludge for scroll-dragging, until I decide how to better handle it
		last-xy: (0,0)
			
		into: func [xy [planar!] /force child [object! none!]] [
			~/into self xy child
		]
		
		viewport: does [								;-- much better than subtracting scrollers; avoids exposing internal details
			any [all [map/2 map/2/size] size]			;@@ REP #113
		] #type [function!]

		;@@ move these into kit
		move-by: func [
			"Offset viewport by a fixed amount"
			amount [word! linear!] "'line or 'page or offset in pixels"
			dir    [word!]          "'forth or 'back"
			axis   [word!]          "'x or 'y"
			/scale factor [number!] "Default: 0.8 for page, 1 for the rest"
			/no-clip "Allow showing empty regions external to window"
		][
			~/move-by self amount dir axis factor no-clip
		] #type [function!]

		move-to: func [
			"Ensure point XY of content is visible, scroll only if required"
			xy          [planar! word!]    "'head or 'tail or an offset pair"
			/margin mrg [linear! planar!] "How much space to reserve around XY (default: 0)"
			/no-clip "Allow showing empty regions external to window"
		][
			~/move-to self xy mrg no-clip
		] #type [function!]
		
		clip-origin: func [
			"Change the /origin facet, ensuring no empty area is shown"
			origin [point2D!] "Clipped between (viewport - scrollable/size) and (0,0)"
		][
			~/set-origin self origin no
		] #type [function!]
	
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

paragraph-ctx: context [
	~: self
	
	;@@ rich-text also splits after hyphen - should I do this too?
	whitespace!: charset " ^-"							;-- wrap on tabs as well, although it's glitch-prone (sizing is hard)
	non-space!: negate whitespace!
	
	#if linux? [										;@@ workaround for #5353
		caret-to-offset: function [face [object!] pos [integer!] /lower] [
			system/words/caret-to-offset/:lower face max 1 pos
		]
	]
	
	size-text2: function [layout [object!]] [			;@@ see #4841, #5245 on all kludges included here
		size1: to point2D! size-text layout
		size2: to point2D! caret-to-offset/lower layout length? layout/text	;-- include trailing whitespaces
		if layout/size [size2/x: min size2/x layout/size/x]		;-- but not beyond the allowed width
		max size1 size2
	]
	
	ellipsize: function [layout [object!] text [string!] canvas [point2D!]] [
		;; save existing buffer for reuse (if it's different from text)
		buffer: unless layout/text =? text [layout/text]
		len: length? text
		
		;; measuring "..." (3 dots) is unreliable
		;; because kerning between the last letter and first "." is not accounted for, resulting in random line wraps
		quietly layout/text: "...."
		ellipsis-width: first ellipsis-size: size-text layout
		canvas: max canvas ellipsis-size				;-- prevent canvas/y=0 from triggering ellipsization
		
		quietly layout/text: text
		text-size: size-text layout						;@@ size-text required to renew offsets/carets because I disabled on-change in layout!
		tolerance: 1									;-- prefer insignificant clipping over ellipsization ;@@ ideally, font-dependent
		if any [										;-- need to ellipsize if:
			text-size/y - tolerance > canvas/y				;-- doesn't fit vertically (for wrapped text)
			text-size/x - tolerance > canvas/x				;-- doesn't fit horizontally (unwrapped text)
		][
			;; find out what are the extents of the last visible line:
			last-visible-char: -1 + offset-to-char layout canvas
			last-line-dy: -1 + second caret-to-offset/lower layout last-visible-char
			
			;; if last visible line is too much clipped, discard it an choose the previous line (if one exists)
			if over?: last-line-dy - tolerance > canvas/y [
				;; go 1px above line's top, but not into negative (at least 1 line should be visible even if fully clipped)
				last-line-dy: max 0 -1 + second caret-to-offset layout last-visible-char
			]
			
			;; this only works if text width is >= ellipsis, otherwise ellipsis itself gets wrapped to an invisible line
			;@@ more complex logic could account for ellipsis itself spanning 2-3 lines, but is it worth it?
			ellipsis-location: (max 0 canvas/x - ellipsis-width) . last-line-dy
			last-visible-char: -1 + offset-to-char layout ellipsis-location
			unless buffer [buffer: make string! last-visible-char + 3]
			quietly layout/text: append append/part clear buffer text last-visible-char "..."
			; system/view/platform/update-view layout
			text-size: size-text layout
		]
		text-size
	]
	
	;; flags effect:
	;; wrap=elli=off -> canvas=inf
	;; wrap=on elli=off -> canvas=fixed
	;; wrap=off elli=on -> canvas=fixed, but wrapping should be off, i.e. layout/size=inf (don't use none! draw relies on this)
	;; wrap=elli=on -> canvas=fixed
	;@@ font won't be recreated on `make paragraph!`, but must be careful
	lay-out: function [space [object!] canvas [point2D!] (0x0 +<= canvas) "positive!" ellipsize? [logic!] wrap? [logic!]] [
		canvas: subtract-canvas canvas mrg2: space/margin * 2
		width:  canvas/x								;-- should not depend on the margin, only on text part of the canvas
		;; cache of layouts is needed to avoid changing live text object! ;@@ REP #124
		layout: new-rich-text
		; layout: any [space/layouts/:width  space/layouts/:width: new-rich-text]	@@ this creates unexplainable random glitches!
		unless empty? flags: space/flags [
			;@@ unfortunately this way 'wrap & 'ellipsize cannot precede low-level flags, or pair test fails
			flags: either pair? :flags/1 [				;-- flags may be already provided in low-level form 
				copy flags
			][
				compose [(1 thru length? space/text) (space/flags)]
			]
			;; remove only after copying!
			remove find flags 'wrap						;-- leave no custom flags, otherwise rich-text throws an error
			remove find flags 'ellipsize				;-- this is way faster than `exclude`
		]
		;; every setting of layout value is slow, ~12us, while set-quiet is ~0.5us, size-text is 5+ us
		;; set width to determine height; but special case is ellipsization without wrapping: limited canvas but infinite layout
		quietly layout/font: space/font					;@@ careful: fonts are not collected by GC, may run out of them easily
		quietly layout/data: flags						;-- support of font styles - affects width
		either all [ellipsize? canvas +< infxinf] [		;-- size has to be limited from both directions for ellipsis to be present
			;; ellipsization prioritizes the canvas, so may split long words
			quietly layout/size:  max (1,1) canvas
			quietly layout/extra: ellipsize layout (as string! space/text)
				either wrap? [canvas][canvas * 1x0]		;-- without wrapping should be a single line
		][
			;; normal mode prioritizes words, so have to estimate min. width from the longest word
			quietly layout/size: infxinf
			if all [wrap? canvas/x < 1.#inf] [			;@@ perhaps this too should be a flag?
				words: append clear "" as string! space/text
				trail: any [find/last/tail words non-space!  words]
				parse/case/part words [any [to whitespace! p: skip (change p #"^/")]] trail
				quietly layout/text: words				;@@ memoize results?
				min-width: (1,0) * size-text2 layout
				quietly layout/size: max (1,1) max canvas min-width
			]
			quietly layout/text:  copy as string! space/text	;-- copy so it doesn't update its look until re-rendered!
			; system/view/platform/update-view layout
			;; NOTE: #4783 to keep in mind
			quietly layout/extra: size-text2 layout		;-- 'size-text' is slow, has to be cached (by using on-change)
		]
		quietly space/layout: layout					;-- must return layout
	]

	;; can be styled but cannot be accessed (and in fact shared)
	;; because there's a selection per every row - can be many in one rich-content
	;@@ unify this with /clone and rich-content
	selection-prototype: make-space 'rectangle [
		type: 'selection
		cache: none										;-- this way I can avoid cloning /cached facet
	]
	draw-box: function [xy1 [planar!] xy2 [planar!]] [
		selection: copy selection-prototype
		quietly selection/size: (to point2D! xy2) - xy1
		compose/only [translate (xy1) (render selection)]		;@@ need to avoid allocation
	]
	
	draw: function [space [object!] canvas: infxinf [point2D! none!]] [	;-- text ignores fill flags
		space/sec-cache: copy []						;-- reset computed sections
		if canvas/x < 1.#inf [							;-- no point in wrapping/ellipsization on inf canvas
			ellipsize?: find space/flags 'ellipsize
			wrap?:      find space/flags 'wrap
		]
		layout:   space/layout
		|canvas|: either any [wrap? ellipsize?][
			constrain canvas space/limits
		][
			infxinf
		]
		layout: lay-out space |canvas| to logic! ellipsize? to logic! wrap?

		;; size can be adjusted in various ways:
		;;  - if rendered < canvas, we can report either canvas or rendered
		;;  - if rendered > canvas, the same
		;; it's tempting to use canvas width and rendered height,
		;; but if canvas is huge e.g. 2e9, then it's not so useful,
		;; so just the rendered size is reported
		;; and one has to wrap it into a data-view space to stretch
		mrg2: 2 * mrg: space/margin
		text-size: max (0,0) (constrain layout/extra + mrg2 space/limits) - mrg2	;-- don't make it narrower than min limit
		space/size: mrg2 + text-size					;@@ full size, regardless if canvas height is smaller?
		#debug sizing [#print "paragraph=(space/text) on (canvas) -> (space/size)"]
		
		;; this is quite hacky: rich-text is embedded directly into draw block
		;; so when layout/text is changed, we don't need to call `draw`
		;; just reassigning host's `draw` block to itself is enough to update it
		;; (and we can't stop it from updating)
		;; direct changes to /text get reflected into /layout automatically long as it scales
		;; however we wish to keep size up to date with text content, which requires a `draw` call
		drawn: compose [text 0x0 (layout)]
		
		if caret: space/caret [
			unless caret/parent =? space [render caret]	;-- this lets caret invalidation (e.g. /visible? change) propagate to text
			if all [caret/visible?  not ellipsize?] [
				box: caret->box space caret/offset caret/side
				quietly caret/size: caret/size/x . second box/2 - box/1	;@@ need an option for caret to be of char's width
				invalidate/only caret
				cdrawn: render caret
				drawn: compose/only [push (drawn) translate (box/1) (cdrawn)]
			]
		]
		;; add selection if enabled
		if all [sel: space/selected  not ellipsize?] [	;@@ I could support selection on ellipsized, but is there a point?
			boxes: batch space [frame/item-boxes sel/1 sel/2]
			sdrawn: make [] 1.5 * length? boxes
			foreach [xy1 xy2] boxes [append sdrawn draw-box xy1 xy2]	;@@ use map-each
			drawn: compose/only [push (drawn) (sdrawn)]
		]
		compose/only [translate (mrg) (drawn)]
	]
	
	get-layout: function [space [object!]] [
		any [space/layout  ERROR "(space/type) wasn't rendered with text=(mold/part space/text 40)"]
	]
	
	caret->box: function [space [object!] offset [integer!] side [word!]] [
		layout: get-layout space
		offset: clip offset 0 n: length? space/text
		index:  clip 1 n offset + pick [0 1] side = 'left
		;; line feed in rich text belongs to the upper line, so caret after it can only have right side:
		if all [layout/text/:index = #"^/" offset = index] [index: min n index + 1]
		box: batch space [frame/item-box index]
		;; make caret box of zero width:
		either left?: index = offset [box/1/x: box/2/x][box/2/x: box/1/x]
		box 
	]
			
	;; TIP: use kit/do [help self] to get help on it
	kit: make-kit 'text [
		clone:  does [clone-space space [text flags color margin weight font command]]
		format: does [
			#debug clipboard [#print "  text/format (\(space-id space)): (mold/part space/text 120)"]
			copy space/text
		]
		
		;@@ space/text or space/layout/text here?
		;@@ what isn't drawn doesn't exist and using space/text may lead to offsets > current /size
		;@@ but space/layout/text is not where the edits take place and I want to be in sync with them
		;@@ it also depends if 'length' can be a valid call before space is rendered or not
		length: function ["Get text length"] [
			length? space/text
		]
		
		everything: function ["Get full range of text"] [		;-- used by macro language, e.g. `select everything`
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [
			all [sel: space/selected  sel/1 <> sel/2  sel]
		]
		
		select-range: function ["Replace selection" range [point2D! none!]] [
			space/selected: if range [clip range 0 length]
		]
		
		frame: object [
			line-count: function ["Get line count on last frame"] [
				rich-text/line-count? get-layout space
			]
			
			point->caret: function [
				"Get caret offset and side near the point XY on last frame"
				xy [planar!]
			][
				layout: get-layout space
				caret:  offset-to-caret layout xy			;-- these never fail if layout/text is set
				char:   offset-to-char  layout xy			;-- but -char may return 1 for empty text
				side:   pick [left right] caret > char
				compose [offset: (caret - 1) side: (side)]
			]
			
			caret-box: function [
				"Get box [xy1 xy2] for the caret at given offset and side on last frame"
				offset [integer!] side [word!] (find [left right] side)
			][
				~/caret-box space offset side
			]
			
			item-box: function [							;; named 'item' for consistency with rich text
				"Get box [xy1 xy2] for the char at given index on last frame"
				index [integer!]
			][
				layout: get-layout space
				index:  clip index 0 length
				xy1:    caret-to-offset       layout index 
				xy2:    caret-to-offset/lower layout index 
				reduce [xy1 xy2]
			]
			
			item-boxes: function [
				"Get boxes [xy1 xy2 ...] for all chars in given range on last frame (unifies subsequent boxes)"
				start [integer!] end [integer!]
			][
				layout: get-layout space
				order 'start 'end
				if start = end [return copy []]
				boxes: clear []
				xy1: caret-to-offset       layout start + 1
				xy2: caret-to-offset/lower layout start + 1
				for i start + 2 end [
					xy1': caret-to-offset       layout i
					xy2': caret-to-offset/lower layout i
					either all [								;@@ should grouping be optional?
						xy1'/x = xy2/x
						xy1'/y = xy1/y
						xy2'/y = xy2/y
					][
						xy2/x: xy2'/x
					][
						repend boxes [xy1 xy2]
						xy1: xy1' xy2: xy2'
					]
				]
				repend boxes [xy1 xy2]
				copy boxes
			]
			
			;@@ an issue with this function is that caret-to-offset returns result truncated to pair (integer)
			;@@ and then some rows in rich-paragraph may become offset by 1px, i.e. not perfectly aligned
			sections: function ["Get section widths on last frame as list of integers"] [
				layout: get-layout space
				mrg: space/margin/x
				case [
					not empty? sections: space/sec-cache ['done]	;-- already computed
					empty? space/text [
						if space/size/x > 0 [append sections space/size/x]
					]
					1 <> frame/line-count [						;-- avoid breaking multiline text
						
						repend sections pick [
							[mrg space/size/x - (mrg * 2) mrg]
							[space/size/x]
						] mrg > 0
					]
					'else [
						spaces: clear []
						parse/case space/text [collect after spaces any [	;-- collect index interval pairs of all contiguous whitespace
							any non-space! s: any whitespace! e:
							keep (as-pair index? s index? e)
						]]										;-- it often produces an empty interval at the tail (accounted for later)
						
						if mrg > 0 [append sections mrg]
						right: 0
						foreach range spaces [
							left:  first caret-to-offset layout range/1
							if left <> right [append sections left - right]		;-- added as positive - chars up to the whitespace
							right: first caret-to-offset layout range/2
							if left <> right [append sections left - right]		;-- added as negative - whitespace chars
						]
						if mrg > 0 [append sections mrg]
						width: mrg * 2 + first size-text2 layout
						if 0.02 < left: space/size/x - width [append sections left]	;-- additional margin introduced by limits/min
					]
				]
				sections
			]
		];frame: object [
	];kit: make-kit [
	
	;@@ 'sections' is subverted by #5433, which ruins rich-test0
	
	
	;@@ in the current design it is rendered by text, so can only be styled as field/text/caret, not field/caret
	;@@ should I move rendering into field? (need to consider document as well)
	declare-template 'caret/rectangle [
		cache:  none
		;; size/y should be set by parent's /draw to line-height
		size:   (1,10)
		width:  1		#type =? :invalidates [integer!] (width > 0)
						#on-change [space word value] [space/size/x: width]
		;; offset and side do not affect the caret itself, but serve for it's location descriptors within the parent
		offset: 0		#type =? :invalidates [integer!]
		side:  'right	#type =  :invalidates [word!] (find/case [left right] side)
		visible?: no	#type =? :invalidates [logic!]	;-- controls caret visibility (necessary focusable spaces wrapping field)
	]
	
 	declare-template 'text/space [
		kit:    ~/kit
		text:   ""		#type    :invalidates [any-string!]	;-- every assignment counts as space doesn't know if string itself changed
		flags:  []		#type    :invalidates [block!]	;-- [bold italic underline strike wrap] supported ;@@ typecheck that all flags are words
		;; NOTE: every `make font!` brings View closer to it's demise, so it has to use a shared font
		;; styles may override `/font` with another font created in advance 
		font:   none									;-- can be set in style, as well as margin
		color:  none									;-- placeholder for user to control
		margin: 0
		weight: 0										;-- no point in stretching single-line text as it won't change
		
		;; caret disabled by default, can be set to a caret space
		caret:     none	#type    :invalidates [object! (space? caret) none!]
		;; there's no /selection facet, because paragraph may have multiple selection boxes
		selected:  none	#type =? :invalidates [pair! none!]

		sec-cache: []	#type [block!]
		
		layout: none	#type [object! none!]			;-- last rendered layout, text size is kept in layout/extra
		quietly cache: [size layout sec-cache]
		quietly draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas]
	]

	;; unlike text, paragraph is wrapped
	declare-template 'paragraph/text [
		quietly weight: 1								;-- used by tube, should trigger a re-render
		quietly flags:  [wrap]
	]

	;; url is underlined in style; wrapped for it's often long
	declare-template 'link/paragraph [
		quietly flags: [wrap underline]
		quietly color: 50.80.255						;@@ color should be taken from the OS theme
		command: [browse as url! text]					;-- can't use 'quietly' or no set-word = no facet
	]
]


;-- layout-agnostic template for list, ring & other layout using space collections
container-ctx: context [
	~: self

	;; all rendering is done by layout, because container by itself doesn't have enough info to perform it
	draw: function [
		cont [object!]
		type [word!]
		settings [block!]
		; xy1 [point2D! none!]								;@@ unlikely window can be supported by general container
		; xy2 [point2D! none!]
		; canvas [point2D! none!]
	][
		; #assert [(none? xy1) = none? xy2]				;-- /only is ignored to simplify call in absence of `apply`
		len: cont/items/size
		
		
		drawn: make [] len * 6
		items: make [] len
		repeat i len [append items cont/items/pick i]	;@@ use map-each
		frame: make-layout type items settings
		
		foreach [_ geom] frame/map [
			pos: geom/offset
			siz: geom/size
			drw: take remove find geom 'drawn			;-- no reason to hold `drawn` in the map anymore
			
			; skip?: all [xy2  not boxes-overlap?  pos pos + siz  0x0 xy2 - xy1]
			; unless skip? [
			org: any [geom/origin (0,0)]
			compose-after drawn [
				;; clip has to be followed by a block, so `clip` of the next item is not mixed with previous
				; clip (pos) (pos + siz) [			;-- clip is required to support origin ;@@ but do we need origin?
				translate (pos + org) (drw)
				; ]
			]
			; ]
		]
		quietly cont/map: frame/map		;-- compose-map cannot be used because it renders extra time ;@@ maybe it shouldn't?
		cont/size: constrain frame/size cont/limits		;@@ is this ok or layout needs to know the limits?
		cont/origin: any [frame/origin (0,0)]
		drawn: compose/only [translate (negate cont/origin) (drawn)]
		unless frame/size +<= cont/size [drawn: compose/only [clip 0x0 (cont/size) (drawn)]]
		drawn
	]
	
	format-items: function [space [object!]] [
		format: copy {}
		list: map-each i space/items/size [				;-- copy what is visible (items), not what is present (content)
			batch item: space/items/pick i [format]
		]
	]
	
	format: function [space [object!] separator [string!]] [
		list: format-items space
		unless empty? separator [list: delimit list separator]
		#debug clipboard [#print "  container/format (\(space-id space)): (mold/part to {} list 120)"]
		to {} list
	]
	
	kit: make-kit 'container [
		format: does [~/format space "^-"]
	]

	declare-template 'container/space [
		kit:     ~/kit
		origin:  (0,0)									;-- used by ring layout to center itself around the pointer
		content: []		#type :invalidates 				;-- no type check as user may redefine it and /items freely
		
		items: func [/pick i [integer!] /size] [
								;-- check type in the default items provider instead
			either pick [content/:i][length? content]
		] #type :invalidates [function!]
		
		map:   []
		cache: [size map]
		into: func [xy [planar!] /force child [object! none!]] [
			into-map map xy + origin child
		]

		draw: func [
			; /on canvas [point2D! none!]					;-- not used: layout gets it in settings instead
			/layout type [word!] settings [block!]
		][
			
			~/draw self type settings; xy1 xy2
		]
	]
]

;@@ `list` is too common a name - easily get overridden and bugs ahoy
;@@ need to stash all these contexts somewhere for external access
list-ctx: context [
	~: self
		
	;; map generally has no direction, but list map has, and it can be leveraged
	into: function [list [object!] xy [planar!] item [object! none!]] [
		if item [return into-map list/map xy item]
		y: list/axis
		i: first search/mode/for i: 1 half length? list/map [	;@@ unify this with list-view somehow
			geom: pick list/map i * 2
			geom/offset/:y
		] 'interp xy/:y
		set [item: geom:] skip list/map i - 1 * 2
		; ?? [i geom/offset geom/size xy]
		xy: xy - geom/offset
		if xy +< geom/size [reduce [item xy]]
	]
	
	get-sections: function [list [object!]] [
		case [
			not empty? cache: list/sec-cache ['done]
			list/size/x = 0 ['done]						;-- nothing to dissect (not rendered?)
			list/axis <> 'x	[							;-- can't dissect vertical list
				if 0 <> mrg: list/margin/x [repend cache [mrg mrg]]
			]
			'else [generate-sections list/map list/size/x cache]
		]
		cache
	]

	kit: make-kit 'list [
		clone: function [] [		
			cloned: clone-space space [axis margin spacing]	;-- no /origin since that is state
			clone: []									;-- used when item is not cloneable
			foreach item space/content [
				;@@ is it ok to skip non cloneable items silently?
				append cloned/content batch item [clone]
			]
			cloned
		]
		format: does [container-ctx/format space select [x "^-" y "^/"] space/axis]
		frame: object [
			sections: does [~/get-sections space]
		]
	]

	draw: function [list [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [		
		list/sec-cache: copy []							;-- reset computed sections
		settings: with list [axis margin spacing canvas fill-x fill-y limits]
		list/container-draw/layout 'list settings
	]
		
	declare-template 'list/container [
		kit:       ~/kit
		size:      (0,0)	#type [point2D! (0x0 +<= size) none!]		;-- 'none' to allow infinite lists
		axis:      'x		#type =  :invalidates [word!] (find [x y] axis)
		;; default spacing/margins must be tight, otherwise they accumulate pretty fast in higher level widgets
		margin:    0
		spacing:   0

		sec-cache: []
		frame:     []									;-- last frame parameters used by kit and list-view
		cache:     [size map frame sec-cache]			;@@ put sec-cache into container or not?
		
		into: func [xy [planar!] /force item [object! none!]] [~/into self xy item]
		container-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

ring-ctx: context [
	~: self
	
	declare-template 'ring/container [
		;; in degrees - clockwise direction to the 1st item (0 = right, aligns with math convention on XY space)
		angle:  0	#type =  :invalidates-look [linear!]
		;; minimum distance (pixels) from the center to the nearest point of arranged items
		radius: 50	#type =  :invalidates [linear!]
		;; whether items should be considered round, not rectangular
		round?: no	#type =? :invalidates [logic!]

		container-draw: :draw	#type [function!]
		draw: does [container-draw/layout 'ring [angle radius round?]]
	]
]


icon-ctx: context [
	~: self
		
	declare-template 'icon/list [
		axis:   'y
		margin: 0
		
		;@@ TODO: image should be also aligned by a box, when icon fills the canvas
		;@@ or set icon weight to 0 and don't let list stretch zero-weight spaces
		spaces: context [
			image: make-space 'image []
			text:  make-space 'paragraph []
			image-box: make-space 'box [content: image]	;-- used to align image
			text-box:  make-space 'box [content: text]	;-- used to align paragraph
			set 'content reduce [image-box text-box]
		] #type [object!]
		
		;; exposed inner facets for easier access
		image:  none	#on-change [space word value] [space/spaces/image/data: value]
		text:   ""		#on-change [space word value] [space/spaces/text/text:  value]
	]
]



tube-ctx: context [
	~: self

	kit: make-kit 'tube [
		format: function [] [
			list: container-ctx/format-items space
			if find [n w ↑ ←] space/axes/1 [list: reverse list]
			list: join list either find [e w → ←] space/axes/1 ["^-"]["^/"]
			#debug clipboard [#print "  tube/format (\(space-id space)): (mold/part list 120)"]
			list
		]
	]

	draw: function [tube [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [		
		settings: with tube [margin spacing align axes canvas fill-x fill-y limits]
		drawn:  tube/container-draw/layout 'tube settings
		#debug sizing [#print "tube with (tube/content/type) on (mold canvas) -> (tube/size)"]
		drawn
	]
		
	declare-template 'tube/container [
		kit:     ~/kit
		margin:  0
		spacing: 0
		align:   -1x-1	#type :invalidates-look =? [pair! (-1x-1 +<= align +<= 1x1) block!]
		axes:    [e s]	#type :invalidates [block!]
						(find/only [					;-- literal listing allows it to appear in the error output
							[n e] [n w]  [s e] [s w]  [e n] [e s]  [w n] [w s]
							[→ ↓] [→ ↑]  [↓ ←] [↓ →]  [← ↑] [← ↓]  [↑ →] [↑ ←]
						] axes)
		
		container-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


rich-paragraph-ctx: context [							;-- rich paragraph
	~: self

	;; returned point always belongs to the nearest space
	;; 2D: x<0 and x>size/x: projected onto x=0 and x=size/x
	;;     y<0 and y>size/y: these points cannot be meaningfully "unrolled" into x, since height of non-existing rows is unset
	;;       so mapping projects y<0 to y=0 and y>size/y to y=size/y
	;;     y between rows is projected onto the upper row
	;; 1D: x is clipped within [0 size-1D/x]
	;@@ another way is to project y<0 to 0x0 and y>size/y to size - need to think what's better UX-wise
	map-2D->1D: function [
		"Translate a point in 2D (rolled) space into a point in 1D (map) space"
		frame [object!] "Rendered frame data"
		xy    [planar!] "Margin must be subtracted already"
	][
		if empty? frame/map [return (0,0)]
		set-pair [x: y:] xy
		x-2D: clip x 0 frame/size-2D/x
		y-2D: clip y 0 frame/size-2D/y
		rows-above: reproject/truncate frame/y2D->row y-2D
		x-1D': rows-above * frame/size-2D/x + x-2D
		x-1D': clip x-1D' 0 frame/size-1D'/x
		x-1D:  reproject/inverse frame/x1D->x1D' x-1D'
		y0-2D: pick frame/y-levels rows-above * 3 + 1
		y-1D:  clip (y-2D - y0-2D) 0 frame/size-1D/y
		(x-1D . y-1D)
	]
	
	map-x1D->x1D': function [
		frame [object!] "Rendered frame data"
		x-1D  [linear!]
		side  [word!] (find [left right] side) "Skip indentation to left or to right"
	][
		
		apply 'reproject [frame/x1D->x1D' x-1D /up side = 'right]
	]
	
	map-x1D'->row: function [
		"Translate an X offset (without margin) in 1D' (unrolled) space into a closest row number"
		frame [object!]      "Rendered frame data"
		x-1D' [linear!]
		side  [word!] (find [left right] side) "Map contested points to previous or next row"
	][
		rows-above: to integer! rows-above': x-1D' / frame/size-2D/x
		if rows-above = rows-above' [					;-- contested pixel
			rows-above: either side = 'left
				[rows-above - 1]
				[min rows-above frame/nrows - 1]
		]
		1 + max 0 rows-above
	]
	
	map-x1D->row: function [
		"Translate an X offset (without margin) in 1D (map) space into a closest row number"
		frame [object!]      "Rendered frame data"
		x     [linear!]
		side  [word!] (find [left right] side) "Map contested points to previous or next row"
	][
		
		x-1D': map-x1D->x1D' frame x side
		map-x1D'->row frame x-1D' side
	]
	
	;@@ move these funcs into layout/paragraph?
	;; returned point's Y is projected into the 2D row (which is generally smaller than size-1D/y)
	map-1D->2D: function [
		"Translate a point in 1D (map) space into a point in 2D (rolled) space (without margin)"
		frame [object!]      "Rendered frame data"
		xy    [planar!]
		side  [word!] (find [left right] side) "Map contested points to previous or next row"
	][
		if empty? frame/map [return (0,0)]
		set-pair [x-1D: y-1D:] xy
		
		x-1D': map-x1D->x1D' frame x-1D side
		rows-above: -1 + map-x1D'->row frame x-1D' side
		x-2D: x-1D' - (frame/size-2D/x * rows-above)	;-- modulo doesn't work due to left/right duality
		
		set [y0-2D: y1-2D: y2-2D:] skip frame/y-levels rows-above * 3
		
		y-2D:  clip y1-2D y2-2D (y0-2D + y-1D)			;-- do not let it step into other rows
		; ?? [rows-above x-1D' side x-2D y-2D]
		(x-2D . y-2D)
	]
	
	;; return row number for the row that is closest to a 2D point
	;@@ or return none if outside the row?
	map-2D->row: function [
		"Translate a point (without margin) in 2D (rolled) space into a closest row number"
		frame [object!]      "Rendered frame data"
		xy    [planar!]
	][
		y-2D: clip xy/y 0 frame/size-2D/y
		1 + reproject/truncate frame/y2D->row xy/y
	]
	
	map-row->box: function [
		"Get a box [XY1 XY2] in 2D (rolled) space (without margin and skipping indent) bounding the given row number"
		frame [object!]  "Rendered frame data"
		row   [integer!] (row >= 1)
		;@@ need a refinement for indent inclusion? it should be as easy as setting xy1/x: 0 though
	][
		
		set [y0: y1: y2:] skip frame/y-levels row - 1 * 3
		offset-1D': row - 1 * width: frame/size-2D/x
		;; simplest thing would be to locate row in 2D and map it to 1D and back, but that's ambiguous for zero-height rows
		;; so I need to use 1D'->1D->1D' mapping to detect and skip indentation
		x1-1D:  reproject/inverse frame/x1D->x1D' x1-1D': offset-1D'
		x2-1D:  reproject/inverse frame/x1D->x1D' x2-1D': min (offset-1D' + width) frame/size-1D'/x
		x1-1D': reproject/up      frame/x1D->x1D' x1-1D
		x2-1D': reproject         frame/x1D->x1D' x2-1D
		xy1: x1-1D' - offset-1D' . y1
		xy2: x2-1D' - offset-1D' . y2
		reduce [xy1 xy2]
	]
	
	;; unlike /into this always succeeds if there's a child
	;@@ base /into on this
	locate-child: function [
		"Find a child closest to XY and return: [child child-xy child-2D-origin]"
		space [object!] xy [planar!] "Margin must be subtracted already"
	][
		frame: space/frame
		if empty? frame/map [return none]
		xy: xy - frame/margin
		xy-1D: map-2D->1D frame xy
		map: skip frame/map 2 * reproject/truncate frame/x1D->map xy-1D/1
		if tail? map [map: skip map -2]					;-- map last x1D to last child
		set [child: geom:] map
		
		oxy-2D: map-1D->2D frame geom/offset 'right
		child-xy: xy-1D - geom/offset					;-- point in the child is in 1D space (it can be wrapped!)
		reduce [child child-xy oxy-2D + frame/margin]
	]
		
	;; /map is kept in 1D space, so /into is required for translation from 2D
	into: function [
		space [object!]
		xy    [planar!] (xy == xy)						;-- nan check for both coordinates
		child [object! none!]
	][
		unless frame: space/frame [return none]
		;; /frame holds rows data as well alignment and margin used to draw these rows
		;; without it, there's a risk that /into could operate on changed facets not yet synced to rows
		xy-2D: (to point2D! xy) - frame/margin
		either child [
			child-xy: (0,0)
			if geom: select/same frame/map child [		;-- can be none if content changed (see %hovering.red)
				oxy-2D: map-1D->2D frame geom/offset 'right
				child-xy: xy-2D - oxy-2D
			]
			reduce [child child-xy]
		][
			xy-1D:  map-2D->1D frame xy-2D
			xy'-2D: map-1D->2D frame xy-1D 'right		;@@ what side argument to use? doesn't matter?
			; ?? [xy-1D xy-2D xy'-2D]
			if all [									;-- if xy is within 1D range, it back-projects into itself
				xy-2D/1 ~= xy'-2D/1						;-- neglect the rounding error from double conversion
				xy-2D/2 ~= xy'-2D/2
			][
				map: skip frame/map 2 * reproject/truncate frame/x1D->map xy-1D/x
				set [child: geom:] map
				if child [								;-- x-1D = size-1D/x leads to the tail
					child-xy: xy-1D - geom/offset
					if child-xy +< geom/size [reduce [child child-xy]]
				] 
			] 
		]
	]
		
	get-sections: function [space [object!]] [
		if empty? cache: space/sec-cache [
			mrg: space/margin/x							;-- make margin significant
			if 0 <> mrg [append cache mrg]
			if space/frame/nrows = 1 [					;-- not empty or multiline text (/nrows can be none if not rendered)
				append cache space/frame/sections
			]
			if 0 <> mrg [append cache mrg]
		]
		cache
	]
	
	kit: make-kit 'rich-paragraph [
		frame: object [
			sections: does [~/get-sections space]
		]
		format: does [container-ctx/format space ""]
	]
		
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		space/sec-cache: copy []						;-- reset computed sections
		settings: with space [margin spacing align baseline canvas fill-x fill-y limits indent force-wrap?]
		frame: make-layout 'paragraph :space/items settings
		size: (2,2) * space/margin + frame/size-2D
		quietly space/frame: frame
		quietly space/size:  constrain size space/limits	;-- size may be bigger than limits if content doesn't fit
		quietly space/map:   frame/map
		frame/drawn
	]
	
	;; a paragraph layout composed out of spaces, used as a base for higher level rich-content
	declare-template 'rich-paragraph/container [
		kit:         ~/kit
		margin:      0
		spacing:     0		#type =? [integer!] :invalidates	;-- has only vertical row spacing; do not turn it into pair!
		align:       'left	#type = [word!] :invalidates		;-- horizontal alignment
		baseline:    80%	#type = [float! percent!] :invalidates-look		;-- vertical alignment in % of the height
		weight:      1									;-- non-zero default so tube can stretch it
		indent:      none								;-- indent of the paragraph: [first: integer! rest: integer!]
			#type = [block! (parse indent [2 [set-word! integer!]]) none!] :invalidates
		force-wrap?: no		#type =? [logic!] :invalidates		;-- allow splitting words at *any pixel* to ensure canvas is not exceeded
		
		frame:       []		#type  [object! block!]				;-- internal frame data used by /into
		sec-cache:   []
		cache:       [size map frame sec-cache]
		into: func [xy [planar!] /force child [object! none!]] [~/into self xy child]
		
		;; container-draw is not used due to tricky geometry
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


rich-content-ctx: context [								;-- rich content
	~: self
	
	;; returns all xy1-xy2 boxes of carets on 1D space - only empty if no spaces / caret locations, otherwise 2+ boxes
	;@@ or should it just put them into frame?
	;@@ can this be part of the layout? probably not, since uses source data
	list-carets: function [map [block!] ranges [hash! block!]] [
		boxes: clear []
		foreach [child geom] map [
			range: select/same ranges child
			
			xy2: (0,1) * geom/size + xy1: geom/offset
			either 1 >= n: span? range [
				if n = 1 [repend boxes [xy1 xy2]]		;-- span can be zero (empty text), it's not counted then 
			][
				
				
				xy2: xy1 + (0 . rich-text/line-height? child/layout 1)		;-- caret of line size, ignoring margin
				repeat i n [
					offset: caret-to-offset child/layout i 
					repend boxes [xy1 + offset xy2 + offset]
				]
			]
		]
		offset: 1x0 * geom/size
		repend boxes [xy1 + offset xy2 + offset]		;-- n+1 carets for n items, always at least 1 caret
		copy boxes
	]
	    
	caret->box-1D: function [
		"Get [XY1 XY2] box in 1D space for caret at given offset"
		space [object!] caret [integer!]
	][
		boxes: any [
			space/frame/caret-boxes
			space/frame/caret-boxes: list-carets space/map space/ranges	;@@ remove ranges after this?
		]
		unless tail? boxes: skip boxes caret * 2 [		;-- returns none when outside of range or no carets allowed
			copy/part boxes 2
		]
	]
	
	caret->box-2D: function [
		"Get [XY1 XY2] box in 2D space (with margin) for caret at given offset"	;@@ or not add margin?
		space [object!] caret [integer!] side [word!] (find [left right] side)
	][
		if box-1D: caret->box-1D space caret [
			repeat i 2 [								;@@ use map-each
				xy: rich-paragraph-ctx/map-1D->2D space/frame box-1D/:i side
				box-1D/:i: space/frame/margin + xy
			]
			box-1D										;@@ result is pixel-rounded, need more precision?
		]
	]
	
	;@@ consider removing/splitting this func
	locate-point: function [space [object!] xy [planar!] "with margin"] [
		xy: xy - space/frame/margin
		if set [child: child-xy:] rich-paragraph-ctx/locate-child space xy [
			
			crange: select/same space/ranges child
			either 1 = span? crange [
				index: crange/2
				caret: pick crange child-xy/x < (child/size/x / 2)
			][
				index: crange/1     + offset-to-char  child/layout child-xy
				caret: crange/1 - 1 + offset-to-caret child/layout child-xy
			]
			side: pick [left right] index = caret
			reduce [child child-xy index caret side]	;@@ what to return?
		]
	]
	
	xy->caret: function [space [object!] xy [planar!] "with margin"] [
		if found: locate-point space xy [found/4]
	]
	
	caret->row: function [
		"Get row number for specified caret offset (or none if no rows)" 
		space [object!]
		caret [integer!] (caret >= 0)
		side  [word!] (find [left right] side)
	][
		if empty? space/map [return none]
		;; tricky part is zero-height rows - cannot work in 2D space, only in 1D
		if box: caret->box-1D space caret [
			rich-paragraph-ctx/map-x1D->row space/frame box/1/x side	;@@ move mapping into space?
		]
	]
	
	row->box: function [
		"Get bounding box of row's content (offset by margin)"
		space [object!] row-number [integer!]
	][
		box: rich-paragraph-ctx/map-row->box space/frame row-number
		forall box [box/1: box/1 + space/frame/margin]	;@@ use map-each
		box
	]
	
	; ;; these are just `copy`ed, since it's 5-10x faster than full `make-space`
	; linebreak-prototype: make-space 'break [#assert [cache = none]]	;-- otherwise /cached facet should be `clone`d
	; text-prototype:      make-space 'text []
	; link-prototype:      make-space 'link []
	
	;; can be styled but cannot be accessed (and in fact shared)
	;; because there's a selection per every row - can be many in one rich-content
	selection-prototype: make-space 'rectangle [
		type: 'selection
		cache: none										;-- this way I can avoid cloning /cached facet
	]
	
	draw-box: function [xy1 [planar!] xy2 [planar!]] [
		selection: copy selection-prototype
		quietly selection/size: xy2 - xy1
		compose/only [translate (xy1) (render selection)]
	]
	
	draw-selection: function [space [object!]] [
		if any [
			not sel: space/selected
			empty? space/data
		] [return []]
		if sel/1 > sel/2 [sel: reverse sel]
		;@@ this calls fill-row-ranges so many times that it must be super slow
		lrow: caret->row space sel/1 'left  1
		rrow: caret->row space sel/2 'right 1
		set [lcar1: lcar2:] caret->box-2D space sel/1 'left
		set [rcar1: rcar2:] caret->box-2D space sel/2 'right
		; ?? [sel lrow rrow lcar1 lcar2 rcar1 rcar2]
		
		either lrow = rrow [
			draw-box lcar1 rcar2
		][
			collect [
				set [lrow1: lrow2:] row->box space lrow
				keep draw-box lcar1 lrow2
				for irow lrow + 1 rrow - 1 [
					set [row1: row2:] row->box space irow
					if row1/y < row2/y [				;-- ignore empty lines
						keep draw-box row1 row2
					]
				] 
				set [rrow1: rrow2:] row->box space rrow
				keep draw-box rrow1 rcar2
			]
		]
	]
	
	draw-caret: function [space [object!]] [
		unless all [caret: space/caret  caret/visible?] [return []]
		box: batch space [frame/caret-box here caret/side]
		; ?? [caret/offset caret/side box] 
		
		
		quietly caret/size: box/2 - box/1 + (caret/width . 0)
		invalidate/only caret
		drawn: render caret
		compose/only [translate (box/1) (drawn)]
	]
		
	;; adds selection and caret
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		drawn: space/rich-paragraph-draw/on canvas fill-x fill-y
		if space/selected [
			sdrawn: draw-selection space
			drawn: reduce [sdrawn drawn]
		]
		if space/caret [
			cdrawn: draw-caret space
			drawn: reduce ['push drawn cdrawn]
		] 
		drawn
	]
	
	kit: make-kit 'rich-content/rich-paragraph [
		;@@ same Q as for text, length on the frame or length of data?
		length: function ["Get length in items"] [
			half length? space/data
		]
		
		everything: function ["Get full range of text"] [		;-- used by macro language, e.g. `select-range everything`
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [	;-- used by macro language, e.g. `remove-range selected`
			all [sel: space/selected  sel/1 <> sel/2  sel]
		]
		
		here: function ["Get current caret offset"] [
			space/caret/offset
		]
		
		frame: make frame [
			line-count: function ["Get line count on last frame"] [
				space/frame/nrows
			]
			
			point->caret: function [
				"Get caret offset and side near the point XY on last frame"
				xy [planar!]
			][
				set [_: _: index: offset:] ~/locate-point space xy
				side: pick [right left] offset < index
				compose [offset: (offset) side: (side)]
			]
			
			caret->row: function [
				"Get row number for the given caret location on last frame"
				offset [integer!] side [word!]
			][
				~/caret->row space offset side
			]
			
			caret-box: function [
				"Get box [xy1 xy2] for the caret at given offset and side on last frame"
				offset [integer!] side [word!] (find [left right] side)
			][
				~/caret->box-2D space offset side
			]
			
			row-box: function [
				"Get box [xy1 xy2] for the given row on last frame"
				row [integer!]
			][
				~/row->box space row
			]
		]
		
		locate: function [
			"Get offset of a named location"
			name [word!]
		][
			switch/default name [
				head [0]
				tail [length]
			][here]
		]	
		
		format: does [rich/source/format space/data]	;@@ should this format be so different from rich-paragraph's one?
		
		clone: function [] [		
			cloned: clone-space space [margin spacing align baseline weight color font indent force-wrap?]
			clone: none									;-- used when item is not cloneable
			cloned/data: map-each/eval [item [object!] code] space/data [	;-- data may contain spaces
				when item: batch item [clone] [item code]		;-- not cloneable spaces are skipped! together with the code
			]													;-- triggers on-data-change
			cloned
		]
		
		;@@ should source support image! in its content? url! ? anything else?
		deserialize: function [
			"Set up paragraph with high-level dialected data"
			source [block!]
		][
			space/data: rich/source/deserialize source			;-- triggers on-data-change
		]
		serialize: function ["Convert paragraph data into high-level dialected data"] [
			rich/source/serialize space/data
		]
		
		reload: function ["Reload content from data"] [trigger 'space/data]	;-- triggers on-data-change
	
		select-range: function [
			"Replace selection"
			range [pair! none!]
		][
			space/selected: if range [clip range 0 length]
		]
	
		pick-attrs: function [
			"Get attributes code for the item at given index"
			index [integer!]
		][
			if code: pick space/data index * 2 [rich/index->attrs code]
		]
		
		pick-attr: function [
			"Get chosen attribute's value for the item at given index"
			index [integer!] attr [word!]
		][
			if code: pick space/data index * 2 [rich/attributes/pick code attr]
		]
		
		;@@ I hate these -range and -items suffixes but without them there's too much risk of name shadowing
		;@@ adding a sigil to all (or only some) funcs is no better
		copy-range: function [
			"Extract and return given range of data"
			range: 0x0 [pair! none!] /text "Extract as plain text"
		][
			range: clip range 0 length					;-- avoid overflow on inf * 2
			slice: copy/part space/data range * 2 + 1
			if text [slice: rich/source/format slice]
			slice
		]
		
		mark-range: function [
			"Change attribute value over given range"
			range [pair! none!] attr [word!] value "If falsey, attribute is cleared"
		][
			unless all [range  range/1 <> range/2] [exit]
			rich/attributes/mark space/data range attr :value
			reload
		]
	
		unmark-range: function [
			"Remove all attributes from given range"
			range [pair! none!]
		][
			unless all [range  range/1 <> range/2] [exit]
			rich/attributes/clear space/data range
			reload
		]
	
		insert-items: function [
			"Insert items at given offset"
			offset [word! integer!]
			items  [
				object! (space? items)					;-- rich-content not inlined! for inlining use `insert! ofs para/data`
				block!  (even? length? items)
				string!
			]
		][
			if word? offset [offset: locate offset]
			case [
				object? items [items: reduce [items 0]]	;-- items are not auto-cloned! so undo/redo may work on *same* items
				string? items [items: zip explode items 0]
			]
			offset: clip offset 0 length
			insert skip space/data offset * 2 items
			reload
		]
	
		remove-range: function [
			"Remove given range of items"
			range [pair! none!]
		][
			unless all [range  range/1 <> range/2] [exit]		;-- for `remove selected` transparency
			range: clip range 0 length
			remove/part skip space/data range/1 * 2 2 * span? range
			reload
		]
	
		change-range: function [
			"Remove given range and insert items there"
			range [pair!]
			items [
				object! (space? items)					;-- rich-content not inlined! for inlining use `insert! ofs para/data`
				block!  (even? length? items)
				string!
			]
		][
			remove-range range
			insert-items range/1 items
		]
		
		clip-range: function [
			"Leave only given range of items, removing the rest"
			range [pair!]
		][
			range: clip range 0 length
			if range <> everything [
				space/data: copy/part space/data range * 2 + 1
			]
			space/data
		]
	
	];kit: make-kit 'rich-content/rich-paragraph [
		
	on-data-change: function [space [object!] word [word!] data [block!]] [
		;@@ maybe postpone all this until next render?
		set with space [content ranges] rich/source/to-spaces data	;-- /content triggers invalidation
		if empty? space/content [						;-- let rich-content always have at least one line (mainly for document)
			obj: make-space 'text []					;@@ use prototype for this?
			obj/font: space/font
			append space/content obj
			repend space/ranges [obj 0x0]
		]
	]
	
	;; unlike rich-paragraph, this one is text-aware, so has font and color facets exposed for styling
	;; also since it can count items, it supports /selected and /caret (impossible in rich-paragraph)
	declare-template 'rich-content/rich-paragraph [
		kit:         ~/kit
		color:       none												;-- color & font defaults are accounted for in style
		font:        none
		selected:    none	#type =? [pair! none!] :invalidates-look	;-- current selection (set programmatically - use event handlers)
		
		;; caret disabled by default, can be set to a caret space
		caret:       none	#type [object! (space? caret) none!] :invalidates	
		
		;; user may override this to carry attributes (bold, italic, color, font, etc) to a space from the /source
		;@@ need to think more on this one - disabled for now
		; apply-attributes: func [space [object!] attrs [map!]] [space]	#type [function!]
		
		;; internal data [item code ...], generated by decode or from edit operations
		;; ranges preserve info about what spaces were 'single' in the source, and what spaces were created from text
		;; so caret can skip the single ones but dive into the created ones
		ranges:  [] #type [block! hash!]				;-- filled by on-data-change
		;; ranges have to come before /data or empty block assignment resets them!
		data:    []	#type [block!] (even? length? data) :on-data-change		
		
		rich-paragraph-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


rich-text-span!: make clipboard/text! [
	name:   'rich-text-span
	data:   []
	length: does [half length? data]
	format: function [] [
		text: to format: {} map-each [item [object!]] extract data 2 [
			batch item [format]
		]
		#debug clipboard [#print "  rich-text-span/format: (mold/part text 120)"]
		text
	]
	copy:  does [remake rich-text-span! [data: (system/words/copy data)]]
	clone: function [] [
		clone: none										;-- used when item has no /clone
		data: map-each/eval [item [object!] code] self/data [
			item: batch item [clone]
			when item [item code]						;-- not cloneable spaces are skipped! together with the code
		]
		remake rich-text-span! [data: (data)]
	]
]


switch-ctx: context [
	~: self
	
	declare-template 'switch/space [
		state: off		#type =? :invalidates-look [logic!]
		; command: []
		data: make-space 'data-view []	#type (space? data)		;-- general viewer to be able to use text/images
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			also data/draw/on canvas fill-x fill-y		;-- draw avoids extra 'data-view' style in the tree
			size: data/size
		]
	]
	
	declare-template 'logic/switch []					;-- uses different style
]


label-ctx: context [
	~: self
	
	on-image-change: function [label [object!] word [word!] value [any-type!]] [
		spaces: label/spaces
		spaces/image-box/content: case [				;-- invalidated by cell
			image? label/image [
				spaces/image/data: label/image
				spaces/image
			]
			string? label/image [
				spaces/sigil/text: label/image
				spaces/sigil
			]
			char? label/image [
				spaces/sigil/text: form label/image
				spaces/sigil
			]
			'else [none]
		]
	]

	on-text-change: function [label [object!] word [word!] value [any-type!]] [
		spaces: label/spaces
		type: either newline: find label/text #"^/" [
			spaces/text/text: copy/part label/text newline
			spaces/comment/text: copy next newline
			'comment
		][
			spaces/text/text: label/text
			'text
		]
		spaces/body/content: reduce spaces/lists/:type			;-- invalidated by container
	]
	
	on-flags-change: function [label [object!] word [word!] value [any-type!]] [
		spaces: label/spaces
		label/spaces/text/flags: label/spaces/comment/flags: label/flags
	]
	
	declare-template 'label/list [
		axis:    'x
		margin:  0x0
		spacing: 5x0
		
		spaces: object [								;-- all lower level spaces used by label
			image:      make-space 'image []
			sigil:      make-space 'text [limits: 20 .. none]	;-- 20 is for alignment of labels under each other ;@@ should be set in style?
			image-box:  make-space 'box  [content: none]		;-- needed for centering the image/sigil
			text:       make-space 'text []						;-- 1st line of text
			comment:    make-space 'text []						;-- lines after the 1st
			body:       make-space 'list [margin: 0x0 spacing: 0x0 axis: 'y  content: reduce [text comment]]
			text-box:   make-space 'box  [content: body]		;-- needed for text centering
			lists: [text: [text] comment: [text comment]]		;-- used to avoid extra bind in on-change
			set 'content reduce [image-box text-box]
		]

		image: none		#type :on-image-change [image! string! char! none!]
		text:  ""		#type :on-text-change  [any-string!]
		flags: []		#type :on-flags-change [block!]			;-- transferred to text and comment
	]
]



;; a polymorphic style: given `data` creates a visual representation of it
;; `content` can be used directly to put a space into it (useful in clickable, button)
data-view-ctx: context [
	~: self

	push-font: function [space [object!]] [
		all [
			space/content
			in space/content 'font
			maybe/same space/content/font: space/font	;-- should trigger invalidation when changed
		]
	]
	
	push-flags: function [space [object!]] [
		all [
			space/content
			in space/content 'flags
			maybe space/content/flags: space/flags		;-- should trigger invalidation when changed
		]
	]
	
	reset-content: function [space [object!]] [
		space/content: VID/wrap-value :space/data space/wrap?	;@@ maybe reuse the old space if it's available?
		push-font space									;-- push current font into newly created content space
	]
	
	declare-template 'data-view/box [					;-- inherit margin, content, map from the box
		align:        -1x-1								;-- left-top aligned by default; on-change inherited from box
		
		;@@ not used currently, maybe it should be
		; #on-change [space word value] [
			; if all [block? :space/data] ...
		; ]
		; #type =?   spacing: 5x5			;-- used only when data is a block
		
		;; font can be set in style, unfortunately required here to override font of rich-text face
		;; (because font for rich-text layout cannot be set with a draw command - we need to measure size)
		font: none	#on-change [space word value] [push-font space]
		
		;; used by button to expose text styles
		flags: []	#on-change [space word value] [push-flags space]
		
		;@@ remove this wrap and use flags/wrap?
		wrap?: off	#type =? [logic!]							;-- controls choice between text (off) and paragraph (on)
		#on-change [space word value] [
			if :space/data = either value ['text]['paragraph] [	;-- switches from text to paragraph and back
				reset-content space
			] 
		] 
		
		data: none	#on-change [space word value [any-type!]] [reset-content space]		;-- ANY red value
	]
]


window-ctx: context [
	~: self

	;; `available?` should be defined in content
	;; should return how much more the window can be scrolled in specified direction (from it's edge, not current origin!)
	;; if it returns more than requested, window is expanded by returned value
	;; (e.g. user scrolls a chat up, whole message height is added to it, not just 20 pixels of the message)
	available?: function [
		space     [object!]
		axis      [word!]   
		dir       [integer!]
		from      [linear!]
		requested [linear!]
	][
		cspace: space/content
		either function? cavail?: select cspace 'available? [	;-- use content/available? when defined
			cavail? axis dir from requested
		][														;-- otherwise deduce from content/size
			csize: any [cspace/size infxinf]
			clip 0 requested (either dir < 0 [from][csize/:axis - from])
		]
	]

	;; window always has to render content on it's whole size,
	;; otherwise how does it know how big it really is
	;; (considering content can be smaller and window has to follow it)
	;; but only xy1-xy2 has to appear in the render result block and map!
	;; area outside of canvas and within xy1-xy2 may stay not rendered as long as it's size is guaranteed
	draw: function [window [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		#debug grid-view [#print "window/draw is called on canvas=(canvas)"]
		unless content: window/content [
			set-empty-size window canvas fill-x fill-y
			return quietly window/map: []
		]
		
		;; there's no size for infinite spaces so pages*canvas is used as drawing area
		;; no constraining by /limits here, since window is not supposed to be limited ;@@ should it be constrained?
		size: (finite-canvas canvas) * window/pages
		unless zero? area? size [						;-- optimization ;@@ although this breaks the tree, but not critical?
			-org: negate window/origin
			;@@ maybe off fill flags when window is less than content? or off them always?
			; ?? [-org size canvas]
			cdraw: render/window/on content -org -org + size canvas fill-x fill-y
			;; window/origin may have been modified by render of content! (e.g. list-view)
			
			;; once content is rendered, its size is known and may be less than requested,
			;; in which case window should be contracted too, else we'll be scrolling over an empty window area
			if content/size [							;-- size has to be finite
				size: clip (0,0) size content/size + window/origin
			]
		]
		#debug sizing [if window/size <> size [#print "resizing window to (size)"]]
		window/size: size
		; ?? [window/size size content/size window/origin]
		;; map should never contain infinite sizes: clip the drawn child area to window
		mapsize: size - window/origin
		quietly window/map: compose/deep [(content) [offset: (window/origin) size: (mapsize)]]
		when cdraw (compose/only [translate (window/origin) (cdraw)])
	]
	
	declare-template 'window/space [
		;; window size multiplier in canvas sizes (= size of inf-scrollable)
		;; when drawn, auto adjusts it's `size` up to `canvas * pages` (otherwise scrollbars will always be visible)
		pages:   10x10	#type = :invalidates [planar! linear!]
		origin:  (0,0)									;-- content's offset (negative)
		
		;; window does not require content's size, so content can be an infinite space!
		content: none	#type =? :invalidates [object! none!]
		
		map:     []
		cache:   [size map]
		
		available?: func [
			"Returns number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
			axis      [word!]    "x/y"
			dir       [integer!] "-1/1"
			from      [linear!] "axis coordinate to look ahead from"
			requested [linear!] "max look-ahead required"
		][
			~/available? self axis dir from requested
		] #type [function!]
	
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

inf-scrollable-ctx: context [
	~: self
	
	;; must be called from within render so `available?`-triggered renders belong to the tree and are styled correctly
	slide: function [space [object!]] [
		if empty? space/cached [return no]				;-- don't slide if invalidated ;@@ kludge: not gonna work with cache disabled
		#debug grid-view [#print "origin in inf-scrollable/slide: (space/origin)"]
		window: space/window
		unless find/same/only space/map window [return no]	;-- likely window was optimized out due to empty canvas 
		wofs': wofs: negate window/origin				;-- (positive) offset of window within its content
		
		wsize:  window/size
		before: negate space/origin						;-- area before the current viewport offset
					;-- slide attempt on an empty viewport, or map is invalid?
		viewport: space/viewport
								;-- slide on empty viewport is most likely an unwanted slide
		if zero? area? viewport [return no]
		after:  wsize - (before + viewport)				;-- area from the end of viewport to the end of window
		; ?? [before after space/look-around wsize viewport space/origin window/origin]
		foreach x [x y] [
			any [										;-- prioritizes left/up slide over right/down
				all [
					;; NOTE: (- min 0 dir/:x) allows to move the window by long distances onfar jumps in the content (e.g. Ctrl+End)
					before/:x <= space/look-around
					0 < avail: window/available? x -1 wofs/:x space/slide-length - min 0 before/:x
					wofs'/:x: wofs'/:x - avail
				]
				all [
					after/:x  <= space/look-around
					0 < avail: window/available? x  1 wofs/:x + wsize/:x space/slide-length - min 0 after/:x
					wofs'/:x: wofs'/:x + avail
				]
			]
		]
		;; transfer offset from scrollable into window, in a way detectable by on-change
		; ?? [wofs wofs' window/origin space/origin before after wsize viewport]
		if wofs' <> wofs [
			;; effectively viewport stays in place, while underlying window location shifts
			#debug slides [#print "sliding (space-id space) with (space-id space/content) by (wofs' - wofs)"]
			space/origin: space/origin + (wofs' - wofs)	;-- may be watched (e.g. by grid-view)
			window/origin: negate wofs'					;-- invalidates both scrollable and window
			wofs' - wofs								;-- let caller know that slide has happened
		]
	]
	
	draw: function [space [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		#debug sizing [#print "inf-scrollable draw is called on (canvas)"]
		timer: space/slide-timer
		render timer									;-- timer has to appear in the tree for timers to work
		drawn: space/scrollable-draw/on canvas fill-x fill-y
		any-scrollers?: not zero? add area? space/hscroll/size area? space/vscroll/size
		timer/rate: either any-scrollers? [4][0]		;-- timer is turned off when unused
		;; scrollable/draw removes slide-timer, have to restore
		;; the only benefit of this is to count spaces more accurately:
		;; (can't use repend, as map may be a static block)
		quietly space/map: compose [
			(space/map)
			(timer) [offset (0,0) size (0,0)]
		]
		#debug sizing [#print "inf-scrollable with (space/content/type) on (mold canvas) -> (space/size) window: (space/window/size)"]
		
		drawn
	]
	
	declare-template 'inf-scrollable/scrollable [		;-- `infinite-scrollable` is too long for a name
		slide-length: 200	#type [integer!] (slide-length > 0)	;-- how much more to show when sliding (px) ;@@ maybe make it a pair?
		look-around: 50		#type [integer!] (look-around > 0)	;-- zone after head and before tail that triggers slide (px)
		;@@ percents of window height could be supported for look-around? and maybe for slide-length?

		content: window: make-space 'window []	#type (space? window)

		;; timer that calls `slide` when dragging
		;; rate is turned on only when at least 1 scrollbar is visible (timer resource optimization)
		slide-timer: make-space 'timer [type: 'slide-timer]	#type (space? slide-timer)
		slide: does [~/slide self] #type [function!]

		scrollable-draw: :draw	#type [function!]
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]


list-view-ctx: context [
	~: self

	;; constant passed into list layout, just easier to put it here than in draw and available funcs
	;; forbids list width extension by largest item (otherwise width will depend on window/origin, leading to weird UX)
	do-not-extend?: yes								
	
	map-index->list-index: function [
		list      [object!]
		map-index [integer!] (all [0 < map-index map-index <= half length? list/map])
	][
		
		anchor-item: list/items/pick anchor: list/frame/anchor
		anchor-pos: find/same/skip list/map anchor-item 2
		unless anchor-pos [return none]					;-- list may have been cleared, map not updated
		anchor-map-index: half 1 + index? anchor-pos
		anchor - anchor-map-index + map-index
	]
	
	available?: function [
		list      [object!]
		req-axis  [word!] (find [x y] req-axis)
		dir       [integer!] (1 = abs dir) 
		from      [linear!] 
		requested [linear!] (requested >= 0)
	][
        if req-axis <> list/frame/axis [				;-- along orthogonal axis list doesn't extend
        	return clip 0 requested either dir < 0 [from][list/frame/size/:req-axis - from]
        ]
        
        ;; choose temp. anchor item closest to the direction we're looking out into (avoids redrawing the whole window!)
        set [anchor-item: anchor-geom:] either dir < 0 [
        	map-index: 1
        	list/map
        ][
        	map-index: half length? list/map
        	list/map << 2
        ]
        
        y:        req-axis
        anchor:   map-index->list-index list map-index
        unless anchor [return 0]						;-- don't try sliding if list was cleared or updated in this frame
        margin:   list/frame/margin
        window:   list/parent
        frame:    construct list/frame					;-- for bind(with) to work
        reverse?: dir < 0
        ;; since 'from' may not align with the 'start' level, add the difference to requested 'length':
        ;; (this relies on list layout counting length *after* the anchor itself and not including the margins)
        start:    anchor-geom/offset/:y + either dir > 0 [anchor-geom/size/:y][0]	;-- from where length is counted
        length:   max 0 requested + (from - start * dir)
		settings: with [frame 'local] [axis margin spacing canvas fill-x fill-y limits anchor length reverse? do-not-extend?]	;-- origin is unused
		path:     when not same? list last current-path (get-host-path list)	;-- ensures proper styling
		
		with-style path [frame: make-layout 'list :list/items settings]
		;; filled includes whole items span + single margin, so bigger than length by anchor size and some
		filled:   frame/filled - anchor-geom/size/:y - (from - start * dir)
		result:   clip 0 requested filled
		; if result <> 0 [?? [window/origin anchor anchor-geom/offset/:y anchor-geom/size/:y start from length frame/filled filled result]]			
		; ?? frame/map
		#debug list-view [#print "available from (from) along (req-axis)/(dir): (result) of (requested)"]
		result
	]
			
	;; can be styled but cannot be accessed (and in fact shared)
	;; because there's a selection per every row - can be many in one rich-content
	;@@ similar to rich-content - possible to unify?
	selection-prototype: make-space 'space [type: 'selection cache: none]	;-- disabled cache to avoid cloning /cached facet
	cursor-prototype:    make-space 'space [type: 'cursor    cache: none]
	draw-box: function [prototype [object!] size [point2D!]] [
		box: copy prototype
		quietly box/size: size
		render box
	]
	
	;@@ this can be optimized more by limiting first (full-width) draw of scrollable to just enough items to ensure we need a scrollbar
	;@@ then only viewport will have to be filled rather than whole window (but it's tricky in this general model)
	;@@ also I shouldn't redraw it fully if possible after a roll, just the new part, somehow, by reusing the old map if canvas is the same
	;; container/draw only supports finite number of `items`, infinite needs special handling
	;; it's also too general, while this `draw` can be optimized better
	list-draw: function [
		lview  [object!]
		canvas [point2D!] (canvas +< infxinf)			;-- window is never infinite
		xy1    [point2D!]
		xy2    [point2D!]
	][
		#debug sizing [#print "list-view/list draw is called on (canvas), window: (xy1)..(xy2)"]
		window:   lview/window
		anchor:   lview/anchor/index
		list:     lview/list
		axis:     list/axis
		fill-x:   axis <> 'x							;-- always filled along finite axis
		fill-y:   axis <> 'y
		reverse?: lview/anchor/reverse?
		length:   xy2/:axis - xy1/:axis
		moved?:   any [									;-- determine if window offset will change
			lview/anchor/offset <> list/frame/anchor-offset
			lview/anchor/index  <> list/frame/anchor
		]
		;; window/origin is unused because window offsets the list by itself
		settings: with [list 'local] [axis margin spacing canvas fill-x fill-y limits anchor length reverse? do-not-extend?]
		; return list/container-draw/layout 'list settings	;@@ how can it support selected and cursor? put them into list?
		frame:    make-layout 'list :list/items settings
		;; cache cleanup only makes sense after a slide, and after recent draw so we have up to date frame/range
		if moved? [clean-item-cache lview]
		;@@ make compose-map generate rendered output? or another wrapper
		;@@ will have to provide canvas directly to it, or use it from geom/size
		drawn:    make [] 3 * (2 + length? frame/map) / 2
		i:        frame/range/1
		foreach [item geom] frame/map [					;@@ use for-each
									;@@ should never happen?
			item-drawn:  take remove find geom 'drawn	;-- no reason to hold `drawn` in the map anymore
			item-offset: geom/offset
			item-size:   geom/size
			;@@ skip invisible items to lighten the draw block (e.g. for inactive lists)? but that will disable list caching
			compose-after drawn [translate (item-offset) (item-drawn)]
			case/all [
				find lview/selected i [
					compose-after drawn [translate (item-offset) (draw-box selection-prototype item-size)]
				]
				lview/cursor = i [
					compose-after drawn [translate (item-offset) (draw-box cursor-prototype item-size)]
				]
			]
			i: i + 1
		]
		
		;; automatic window positioning based on anchor data
		anchor: lview/anchor
		shift: either anchor/reverse? [
			
										;-- else /size may be constrained and shouldn't be relied upon
			anchor/offset - (max 0 frame/size/:axis - length)	;-- subtract extra part overhanging after the length
		][
			
			anchor/offset
		]
		; window/origin: set-axis (0,0) axis shift				;@@ or move the list instead? a bit slower
		window/origin: set-axis window/origin axis shift		;@@ or move the list instead? a bit slower
		
		; ?? [xy1 xy2 length frame/filled shift anchor/index anchor/offset window/origin lview/origin]
		compose-after frame [
			window-origin: (window/origin)
			anchor-offset: (anchor/offset)
		]
		list/frame: frame
		list/size:  frame/size
		quietly list/map: frame/map
		drawn
	]
	
	clean-item-cache: function [lview [object!] "Forget outdated items in item-cache"] [
		unless range: lview/list/frame/range [exit]		;-- has to be drawn to clean up
		max-range-distance: 300							;@@ arbitrary constants.. expose them?
		max-item-age: 0:3
		range: range + (max-range-distance * -1x1)
		now-time: now/precise/utc
		pos: lview/item-cache
		while [all [
			not tail? set [i: _: time:] pos
			i <> clip i range/1 range/2
			max-item-age < difference now-time time 
		]] [
			pos: skip pos 3
		]
		remove/part head pos pos
	]

	;@@ review this
	;; new class needed to type item-cache & available facets
	;; externalized, otherwise will recreate the class on every new list-view
	list-template: declare-class 'list-in-list-view/list [
		type: 'list										;-- styled normally
		axis: 'y
		
		available?: func [axis [word!] dir [integer!] from [linear!] requested [linear!]] [
			;; must pass positive canvas (uses last rendered list-view size)
			~/available? self axis dir from requested
		] #type [function!]
	]
	
	slide: function [lview [object!]] [
		list:   lview/list
		window: lview/window
		anchor: lview/anchor
		y:      list/axis
		if list/frame/anchor <> anchor/index [return none]		;-- forbid slide after anchor is changed (otherwise it resets anchor back)
		; if window/origin <> list/frame/window-origin [exit]

		;; it's possible that multiple slides occur without a draw, resulting in no visible item suitable as a new anchor
		;; to avoid this I just limit max consecutive slides to half the window
		;@@ there must be a better solution for this, but I don't see a simple one
		if any [
			(abs anchor/offset) > half window/size/:y
			not moved: inf-scrollable-ctx/slide lview
		] [return none]
		#debug slides [#print "post-slide adjustment of (space-id lview)..."]
		
		;; change anchor to first or last (still visible) item, depending on the slide direction
		xy2: window/size + xy1: negate window/origin	;-- new window box inside list map
		extra: lview/look-around + list/spacing/:y
		xy1/:y: xy1/:y - extra							;-- let anchor start a bit outside the window
		xy2/:y: xy2/:y + extra
		set [new-anchor-item: new-anchor-geom:] pos:
			apply 'locate [
				list/map
				[item geom .. segments-overlap? xy1/:y xy2/:y geom/offset/:y geom/offset/:y + geom/size/:y]
				;; if content in window shifted up/left, will draw more items below/right
				;; if content in window shifted down/right, will draw more items above/left:
				/back moved/:y < 0
			]
		
		anchor/index: ~/map-index->list-index list 1 + half skip? pos
		
		;; window/origin is affected indirectly here via anchor/offset,
		;; because only after list/draw it is possible to know full rendered list extent
		anchor/offset: window/origin/:y + new-anchor-geom/offset/:y + 
			either lview/anchor/reverse?: moved/:y < 0 [
				new-anchor-geom/size/:y + list/margin/:y - window/size/:y
			][
				negate list/margin/:y
			]
		
			
		; ?? [moved xy1 xy2 new-anchor-geom/offset new-anchor-geom/size anchor/index anchor/offset list/frame/size]
		moved
	]

	get-items-span: function [
		space   [object!]
		offset1 [linear! planar!] "Offsets are window-relative"
		offset2 [linear! planar!]
		whole?  [logic!] "Items must fully fit or only intersect with the offsets?"
	][
		y: space/list/axis
		offset1: offset1 along y - woy: space/list/frame/window-origin/:y	;-- make offsets map-relative
		offset2: offset2 along y - woy
		if reversed?: offset1 > offset2 [swap 'offset1 'offset2]
		set [type1: i1: i1': y1:] layouts/list/locate-line space/list/frame offset1
		set [type2: i2: i2': y2:] layouts/list/locate-line space/list/frame offset2
		fix: pick [1 0] whole?
		r1: switch type1 [
			item   [i1 + fix]
			space  [i1']
			margin [either y1 <  0 [i1][return none]]
		]
		r2: switch type2 [
			item   [i2 - fix]
			space  [i2]
			margin [either y2 >= 0 [i2][return none]]
		]
		either reversed? [r2 thru r1][r1 thru r2]
	]

	;; an item is "before y" if y >= its (offset/y + size/y), i.e. it wholly fits before y
	;; an item is "after y"  if y < its offset/y, i.e. it wholly fits after y
	;; this returns only indexes of items present in the map!
	get-next-item: function [
		space  [object!]
		offset [linear! planar!] "Window-relative"
		dir    [word!] (find [before after] dir)
	][
		list:  space/list
		y:     list/axis
		range: list/frame/range
		set [type: i: i': dy:] layouts/list/locate-line offset - list/frame/window-origin/:y
		new: switch type [
			item   [either dir = 'before [if i > range/1 [i - 1]][if i < range/2 [i + 1]]]
			space  [either dir = 'before [i][i']]
			margin [either dir = 'before [if dy >= 0 [range/2]][if dy < 0 [range/1]]]
		]
	]
				
	axial-shift: function [								;-- used for paging
		"Find a new item index further along main axis"
		space [object!]
		index [integer!] "From given item (must be in the map)"
		shift [linear!]  "Maximum positive or negative distance to travel"
	][
		list:      space/list
		y:         list/axis
		range:     list/frame/range
		index:     clip range/1 range/2 index			;-- if not visible, choose nearest
		if shift = 0 [return index]
		old-geom:  pick list/map 2 * (index - range/1 + 1)
		
		old-y:     old-geom/offset/:y					;-- shift down counts from item's top
		old-y:     old-y + list/frame/window-origin/:y	;-- it needs window-relative offset
		if shift < 0 [old-y: old-y + old-geom/size/:y]	;-- shift up counts from item's bottom
		new-y:     old-y + shift
		span:      get-items-span space old-y new-y yes
		unless span [return pick range shift < 0]
		sign:      sign? shift
		new-index: clip range/1 range/2 either shift > 0
			[max span/2 index + sign]					;-- move at least by one item
			[min span/2 index + sign]
	]

	kit: make-kit 'list-view [
		here: function ["Get index of the item under cursor (or nearest within current window)"] [
			range: space/list/frame/range
			either space/cursor [clip range/1 range/2 space/cursor][range/1]
		]
		length:    func ["Get number of items in the list (can be infinite)"] [any [space/data/size 2'000'000'000]]	;@@ not sure about 2e9
		selected:  func ["Get a list of selected items indices"] [space/selected]
	
		slide: func ["If window is near its borders, let it slide to show more data"] [~/slide space]
		
		;@@ should this support rich text (if list items are rich text)?
		copy-items: function [
			"Copy text of given items"
			items [block! hash! (parse items [any integer!]) pair!] "A list or a range of item indices"
			/clip "Write it into clipboard"
			; /text
		][
			items: either pair? items [
				limit: any [space/list/items/size 1.#inf]
				list-range clip 1 limit order-pair items
			][
				sort copy items							;-- copy should always be ordered
			]
			format: copy {}								;-- used when item has no format
			result: to string! map-each/eval/drop i items [
				unless item: space/list/items/pick i [continue]
				text: batch item [format]
				[text #"^/"]
			]
			if clip [
				#debug clipboard [#print "list-view/copy-items (\(space-id space)): (mold/part result 120)"]
				clipboard/write result
			]
			result
		]
		
		locate: function [
			"Get index of a named item"
			name [word!]
		][
			switch/default name [
				far-head  [1]
				far-tail  [length]
				head      [pick frame/displayed 1]
				tail      [pick frame/displayed 2]
				line-up   [max 1 here - 1]
				line-down [either space/cursor [min length here + 1][1]]
				page-up   [frame/page-above here]
				page-down [frame/page-below here]
			] [here]									;-- unknown words assume current index
		]
		
		move-cursor: function [
			"Redefine cursor and move viewport to make it fully visible"
			target [word! integer!]
			/margin mrg [integer!] "How much to reserve around the item"
			/no-clip "Allow panning outside the window"
		][
			if word? target [target: locate target]
			target: clip 1 length target
			if space/behavior/follows-cursor? [
				frame/move-to/:margin/:no-clip target mrg
			]
			space/cursor: target
		]
		
		select-range: function [
			"Redefine selection or extend up to a given limit"
			limit [word! integer! pair!] "Pair specifies a range of items"
			/mode "Specify selection mode (default: 'replace)"
				sel-mode: 'replace [word!] (find [replace include exclude invert extend] sel-mode)
		][
			if word?    limit [limit: locate limit]
			if integer? limit [limit: here thru limit]
			old: space/selected
			;; a trick to determine selection range start while it does not exist explicitly:
			;; not fully inaccurate, but good enough: uses first selected item as the start
			if sel-mode = 'extend [
				sel-mode: 'replace
				if old/1 [limit/1: old/1]
			]
							;-- warn about too big selections (as it's most likely a mistake)
			if 1e6 < span? limit [limit/1: limit/2]		;-- also defend from out of memory errors ;@@ clip it within 1M, not reset to 1 item?
			new: make hash! list-range limit/1 limit/2
			new: switch sel-mode [
				replace [new]
				include [union old new]
				exclude [exclude old new]
				invert  [difference old new]
			]
			append clear old new
			trigger 'space/selected
		]
			
		frame: object [
			displayed: func ["Get a range of currently displayed items"] [space/list/frame/range]
		
			items-between: function [
				"Get item index range between given window offsets along primary axis (as pair), or none if outside"
				offset1 [linear! planar!]
				offset2 [linear! planar!]
				/whole "Only count items that fully fit the given primary axis range"
			][
				~/get-items-span space offset1 offset2 whole 
			]
			
			item-before: function [
				"Get item index before given window offset along primary axis; or none"
				offset [linear! planar!]
			][
				~/get-next-item space offset 'before
			]
			
			item-after: function [
				"Get item index after given window offset along primary axis; or none"
				offset [linear! planar!]
			][
				~/get-next-item space offset 'after
			]
			
			page-above: function [
				"Get index of an item one page above the given one"
				index [integer!]
			][
				dist: pick space/viewport space/list/axis
				~/axial-shift space index negate max 1 dist
			]
			
			page-below: function [
				"Get index of an item one page below the given one"
				index [integer!]
			][
				dist: pick space/viewport space/list/axis
				~/axial-shift space index max 1 dist
			]
			
			move-to: function [
				"Pan the view to given window offset or item with the given index"
				target [integer! (all [0 < target target <= length]) planar! word!]
					"Item index or window offset"
				;; normally direction is chosen from the current offset
				;@@ /center to be supported down the road
				/after   "Place the viewport so that item or offset is at its top"
				/before  "Place the viewport so that item or offset is at its bottom"
				/margin   mrg [linear!] "How much to reserve around the item"
				/no-clip "When an offset is given, allow panning outside the window"
			][
				
				if word? target [target: locate target]
				list:     space/list
				window:   space/window
				viewport: space/viewport
				range:    list/frame/range
				default mrg: mrg': list/margin along y: list/axis	;-- list/margin is already included, will subtract it
				direction: case [after ['after] before ['before]]
				
				unless planar? point: target [
					unless target-within-range?: target = clip target range/1 range/2 [
						; if window/origin <> list/frame/window-origin [exit]
						;; have to move the window (and the anchor)
						default direction: case [				;-- default direction based on direction to target from current window
							target < range/1 ['after]
							target > range/2 ['before]
						]
						space/anchor/index:    target
						space/anchor/offset:   0
						space/anchor/reverse?: back?: direction = 'before
						originy: either back?
							[negate space/window/size/:y - viewport/:y + mrg - mrg']
							[mrg - mrg']
						scrollable-ctx/set-origin space (set-axis (0,0) y originy) yes
						; ?? [direction target space/origin window/origin list/frame/window-origin]
						exit									;-- done here
					]
					
					;; window can stay, just scroll the viewport
					target-geom: pick list/map target - range/1 + 1 * 2
					target-xy1:  target-geom/offset + window/origin + space/origin	;-- target from viewport
					; target-xy1:  target-geom/offset + list/frame/window-origin + space/origin	;-- target from viewport
					target-xy2:  target-xy1 + target-geom/size
					xy1: set-axis (0,0) y mrg - mrg'			;-- viewport with margins considered
					xy1: min xy1 viewport / 2					;-- cap at half viewport to avoid margin inversion
					xy2: viewport - xy1
					if all [
						not direction
						any [
							all [								;-- item fully within the viewport
								xy1/:y <= target-xy1/:y target-xy1/:y <= xy2/:y
								xy1/:y <= target-xy2/:y target-xy2/:y <= xy2/:y
							]
							;; this case should prevent huge (>viewport) item from jumping up/down on clicks:
							;@@ still need a smarter algorithm... but not sure how should it work yet
							all [								;-- viewport fully within the item
								target-xy1/:y <= xy1/:y xy1/:y <= target-xy2/:y
								target-xy1/:y <= xy2/:y xy2/:y <= target-xy2/:y
							]
						]
					][
						exit									;-- already visible and no direction forced, so do nothing
					]
					
					default direction: pick [after before]		;-- default direction based on target center offset from viewport center
						target-xy1/:y + target-xy2/:y < (xy2/:y + xy1/:y)
					point: target-geom/offset + window/origin
					; point: target-geom/offset + list/frame/window-origin
					if direction = 'before [point/:y: point/:y + target-geom/size/:y]
					; ?? target-geom
					; ?? [direction target point mrg space/origin window/origin list/frame/window-origin target-xy1 target-xy2]
				];unless planar? point: target [
				
				if pre-move: case [								;-- trick to enforce /before and /after locations
					after  [set-axis (0,0) y point/:y + viewport/:y]
					before [set-axis (0,0) y point/:y - viewport/:y]
				][
					scrollable-ctx/move-to space pre-move 0x0 yes
				]
				mrg: set-axis (0,0) y mrg						;-- /margin has meaning along main axis only in list-view, since it's a 1D widget
				scrollable-ctx/move-to space point mrg no-clip
				; scrollable-ctx/set-origin space (viewport * 0x1) - point yes
				; ?? space/origin
				;@@ can't call /slide here because it needs to draw the items first... but it would be good for UX
			];move-to: function [
					
		]
	]
	
	invalidates-list: function [lview [object!] word [word!] value [any-type!]] [
		if object? :lview/list [invalidate lview/list]
	]

	on-anchor-change: function [anchor [object!] word [word!] value [any-type!]] [
		if anchor/parent [invalidate anchor/parent/list]
	]
	
	;; not a space! object (unlike caret) because it makes no sense to draw it
	anchor-spec: declare-class 'list-view-anchor [
		;; used for invalidation
		parent:   none		#type =? [object! (space? parent) none!]
		
		;; index of the first (or last if /reverse?) visible item in the window
		index:    1			#type =? [integer!] (index > 0)	:on-anchor-change
		
		;; item filling direction starting at /index
		reverse?: no		#type =? [logic!]				:on-anchor-change
		
		;; offset from margin to the top <=0 (or bottom >=0 if /reverse?) of the anchor item
		offset:   0			#type =  [linear!]				:on-anchor-change
	]
		
	;@@ list-view & grid-view on child focus should scroll to child
	;@@ expose top /margin & /spacing that are reflected into /list
	declare-template 'list-view/inf-scrollable [
		kit:    ~/kit
		pages:  10
		source: []	#on-change [space word value [any-type!]] [	;-- no type check for it can be freely overridden
			invalidates-list space word :value
			if any-list? :space/item-cache [clear space/item-cache]
		]
		data: func [/pick i [integer!] /size] [			;-- can be overridden
			either pick [source/:i][length? source]		;-- /size may return `none` for infinite data
		] #type [function!]
		
		wrap-data: func [item-data [any-type!] /local spc] [	;-- can be overridden (but with care)
			spc: make-space 'data-view [
				quietly type:  'item
				quietly wrap?:  on
			]
			set/any 'spc/data :item-data
			spc
		] #type [function!]
		
		;; selected items indices list
		;; hash by default so it can scale out of the box for the general case ;@@ auto convert block to hash? on >3-4 items?
		selected:    make hash! 4	#type    [hash! block!] :invalidates-list
		
		;; current item (for keyboard navigation purposes), doesn't have to be selected 
		cursor:      none			#type =? [integer! (cursor > 0) none!] :invalidates-list
		
		extend behavior [
			;; its still possible to programmatically select anything, but how keys behave highly depends on /selectable
			selectable:      #(none)					;-- none=don't select; single=select one item; multi=many items at once
			follows-cursor?: #(true)					;-- cursor fully shows itself on movement
		]

		;; see anchor description in the spec above
		anchor: make classy-object! anchor-spec
		anchor/parent: self
		
		; frame:       []				#type    [map! block! object!]
		; cache:       [size map frame]
		cache:       [size map]
		
		window/content: list: make-space 'list list-template	#type (space? list)
		content-flow: does [
			select [x horizontal y vertical] list/axis
		] #type [function!]
		
		item-cache: make hash! 48
		list/items: func [/pick i [integer!] /size /local item] with list [
			either pick [
				all [
					0 < i i <= any [data/size 1.#inf]			;-- since data/pick can return any value, this is the only way to limit it
					any [
						;@@ test that value returned by data/pick i is the same as the one used to create item i ?
						select item-cache i						;-- no /skip needed because datatypes enforce it
						also item: wrap-data data/pick i
							repend item-cache [i item now/utc/precise] 
					]
				]
			][data/size]
		]
		
		list/draw: func [/window xy1 [point2D!] xy2 [point2D!] /on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			~/list-draw self canvas xy1 xy2				;-- doesn't use fill flags (main axis always infinite, secondary fills if finite)
		]
		
		; ;; this wrapper is neede to auto-position window/origin based on /anchor
		; ;; it has to draw the list, calculate new origin and change it in the drawn block
		; ;@@ unfortunately this means knowledge of the block format produced by window-draw, and of its spec
		; ;@@ maybe list-draw should offset the list instead? shift all items
		; window-draw: :window/draw
		; window/draw: function [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [
			; old-origin: window/origin
			; quietly window/origin: (0,0)
			; drawn: window-draw/:on canvas fill-x fill-y
			; if :drawn/1 = 'translate [					;-- window isn't empty
				; shift: either anchor/reverse? [
					; #assert [anchor/offset >= 0]
					; anchor-geom: last list/map
					; overhang: anchor-geom/offset/y + anchor-geom/size/y + list/margin/y - window/size/y
					; anchor/offset - overhang
				; ][
					; #assert [anchor/offset <= 0]
					; anchor/offset
				; ]
				; ?? [shift overhang anchor/offset]
				; quietly window/origin: window/map/2/offset: drawn/2: set-axis (0,0) list/axis shift
			; ]
			; drawn
		; ]
		
		;@@ remove it and keep the one in the kit?
		slide: does [~/slide self]
		
		; inf-scrollable-draw: :draw
		; draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!] /window xy1 [none! point2D!] xy2 [none! point2D!]] [
			; ~/draw self canvas fill-x fill-y xy1 xy2
		; ]
	]
]


;@@ TODO: list-view of SPACES?
;@@ TODO: grid layout?

;; grid's key differences from list of lists:
;; * it aligns columns due to fixed column size
;; * it CAN make cells spanning multiple rows (impossible in list of lists)
;; * it uses fixed row heights, and because of that it CAN have infinite width (but requires separate height inferrence)
;;   (by "infinite" I mean "big enough that it's unreasonable to scan it to infer the size (or UI becomes sluggish)")
;; * grid is better for big empty cells that user is supposed to fill,
;;   while list is better for known autosized content
grid-ctx: context [
	~: self
	
	into: function [grid [object!] xy [planar!] cell [object! none!]] [	;-- faster than generic map-based into
		if cell [return into-map grid/map xy cell]				;-- let into-map handle it ;@@ slow! need a better solution!
		set [cell: offset:] locate-point grid xy yes
		mcell: grid/get-first-cell cell
		if cell <> mcell [
			offset: offset + grid/get-offset-from mcell cell	;-- pixels from multicell to this cell
		]
		all [
			mcspace: grid/frame/cells/:mcell
			reduce [mcspace offset]
		]
	]
	
	calc-bounds: function [grid [object!]] [
		if lim: grid/frame/bounds [return lim]			;-- already calculated
		bounds: grid/bounds								;-- call it in case it's a function
		unless any ['auto = bounds/x  'auto = bounds/y] [	;-- no auto limit set (but can be none)
			#debug grid-view [#print "grid/calc-bounds [no auto] -> (bounds)"]
			return grid/frame/bounds: bounds
		]
		lim: copy bounds
		xymax: either empty? grid/content [
			0x0
		][
			remove find xys: keys-of grid/spans 'default	;-- if `spans` is correct, it contains the lowest rightmost multicell coordinate
			append xys keys-of grid/content
			second minmax-of xys						;@@ should be `accumulate`
		]
		if 'auto = lim/x [lim/x: xymax/x]				;-- pass `none` as is
		if 'auto = lim/y [lim/y: xymax/y]
		#debug grid-view [#print "grid/calc-bounds [auto] -> (lim)"]
		grid/frame/bounds: lim
		lim
	]

	break-cell: function [cell1 [pair!]] [				;-- `cell1` must be the starting cell
		if 1x1 <> span: grid/get-span cell1 [
									;-- ensure it's a first cell of multicell
			xyloop xy span [							;@@ should be for-each
				remove/key grid/spans xy': cell1 + xy - 1x1
				invalidate-xy grid xy' 
			]
		]
	]

	unify-cells: function ["Mark cell range as spanned" grid [object!] cell1 [pair!] span [pair!]] [
		if 1x1 <> old: grid/get-span cell1 [
			if old +< 1x1 [
				ERROR "Cell (cell1 + old) should be broken before (cell1)"	;@@ or break silently? probably unexpected move..
			]
			break-cell grid cell1
		]
		xyloop xy span [								;@@ should be for-each
			xy': cell1 + xy - 1x1
			
			grid/spans/:xy': 1x1 - xy					;-- each span points to the first cell
			invalidate-xy grid xy' 
		]
		grid/spans/:cell1: span
	]
	
	set-span: function [grid [object!] cell1 [pair!] span [pair!] force [logic!]] [
		if span = grid/get-span cell1 [exit]
									;-- forbid setting of span to non-positives
		xyloop xy span [								;-- break all multicells within the area
			cell: cell1 + xy - 1
			old-span: grid/get-span cell
			if old-span <> 1x1 [
				all [
					not force
					any [cell <> cell1  1x1 +<= old-span]	;-- only `cell1` is broken silently if it's a multicell
					ERROR "Cell (cell1 + old-span) should be broken before (cell1)"
				]
				break-cell grid cell + min 0x0 old-span
			]
		]
		unify-cells grid cell1 span
	]

	get-offset-from: function [grid [object!] c1 [pair!] c2 [pair!]] [
		r: (0,0)
		foreach [x wh?] [x grid/col-width? y grid/row-height?] [
			x1: min c1/:x c2/:x
			x2: max c1/:x c2/:x
			if x1 = x2 [continue]
			wh?: get/any wh?							;@@ workaround for #4988
			for xi: x1 x2 - 1 [r/:x: r/:x + wh? xi]		;@@ should be sum map
			r/:x: r/:x + (x2 - x1 * (grid/spacing/:x))
			if x1 > x2 [r/:x: negate r/:x]
		]
		r
	]
		
	;; fast row/col locator assuming that widths/heights array size is smaller than the row/col number
	;@@ may replace it with the search algo?
	;; returns any of:
	;;   [margin 1 offset] - within the left margin (or if point is negative, then to the left of it)
	;;   [cell   1 offset] - within 1st cell
	;;   [space  1 offset] - within space between 1st and 2nd cells
	;;   [cell   2 offset] - within 2nd cell
	;;   [space  2 offset]
	;;   ...
	;;   [cell   N offset]
	;;   [margin 2 offset] - within the right margin (only when limit is defined),
	;;                       offset can be bigger(!) than right margin if point is outside the space's size
	;@@ TODO: maybe cache offsets for faster navigation on bigger data
	;; doesn't care about pinned cells, treats grid as continuous
	locate-line: function [
		grid  [object!]
		level [linear!] "pixels from 0"
		array [map!]    "widths or heights"
		axis  [word!]   "x or y"
	][
		mg: grid/margin/:axis
		if level < mg [return reduce ['margin 1 level]]		;-- within the first margin case
		level: level - mg

		bounds: grid/calc-bounds
		sp:     grid/spacing/:axis
		lim:    bounds/:axis
		def:    array/default
											;-- must always be defined
		whole:  0				;@@ what if lim = 0?	;-- number of whole rows/columns subtracted
		size:   none
		keys:   sort keys-of array
		remove find keys 'min
		either 1 = len: length? keys [					;-- 1 = special case - all cells are of their default size
			catch [sub-def* 0 level]					;@@ assumes default size > 0 (at least 1 px) - need to think about 0
		][
			keys: sort keys-of array
			remove find keys 'default
									;-- no zero or negative row/col numbers expected
			key: 0
			catch [
				repeat i len - 1 [						;@@ should be for-each/stride [/i prev-key key]
					prev-key: key
					key: keys/:i
					
					before: key - 1 - prev-key			;-- default-sized cells to subtract (may be 'auto)
					if before > 0 [sub-def* prev-key before]
					
					if 'auto = size: array/:key [		;-- row is marked for autosizing
						
						size: grid/row-height? key		;-- try to fetch it from the cache or calculate
					]
					if 0 = sub* 1 size + sp [throw 1]	;-- this cell contains level
				]
				sub-def* key level						;@@ assumes default size > 0 (at least 1 px) - need to think about 0
			]
		]
		unless size [
			size: either axis = 'x [grid/col-width? 1 + whole][grid/row-height? 1 + whole]	;@@ optimize this?
		]
		reduce case [
			level < size              [['cell   1 + whole level]]
			all [lim lim - 1 = whole] [['margin 2         level - size]]
			'else                     [['space  1 + whole level - size]]
		]
	]
		
	;; funcs used internally by locate-line (to avoid recreation of them every time)
	sub*: func [n size] with :locate-line [
		if lim [n: min n lim - 1 - whole]
		n: min n to 1 level / size
		whole: whole + n
		level: level - (n * size)
		#debug grid-view [#print "sub (n) (size) -> whole: (whole) level: (level)"]
		n
	]
	sub-def*: func [from n /local r j] with :locate-line [
		#debug grid-view [#print "sub-def (from) (n) def: (def)"]
		either linear? def [
			if n <> sub* n sp + def [size: def throw 1]	;-- point is within a row/col of default size
		][												;-- `default: auto` case where each row size is different
			
			repeat j n [
				size: grid/row-height? from + j
				if 0 = sub* 1 sp + size [throw 1]		;-- point is within the last considered row (size is valid)
			]
		]
	]

	locate-point: function [grid [object!] xy [planar!] screen? [logic!]] [
		if screen? [
			unless grid/pinned +<= pinned-area: 0x0 [	;-- nonzero pinned rows or cols?
				pinned-area: grid/margin - grid/spacing + grid/get-offset-from 1x1 (grid/pinned + 1x1)
			]
			;; translate heading coordinates into the beginning of the grid
			foreach x [x y] [
				if xy/:x <= grid/frame/offset/:x [
					xy/:x: xy/:x - grid/frame/offset/:x + pinned-area/:x
				]
			]
		]
		
		bounds: grid/calc-bounds
		r: copy [0x0 (0,0)]
		foreach [x array wh?] reduce [
			'x grid/widths  :grid/col-width?
			'y grid/heights :grid/row-height?
		][
			set [item: idx: ofs:] locate-line grid xy/:x array x
			#debug grid-view [#print "locate-line/(x)=(xy/:x) -> [(item) (idx) (ofs)]"]
			switch item [
				space [ofs: ofs - (grid/spacing/:x)  idx: idx + 1]
				margin [
					either idx = 1 [
						ofs: ofs - (grid/margin/:x)
					][
						idx: bounds/:x
						ofs: ofs + wh? idx
											;-- 2nd margin is only possible if bounds are known
					]
				]
			]
			r/1/:x: idx r/2/:x: ofs
		]
		#debug grid-view [#print "locate-point (xy) -> (mold r)"]
		r
	]

	row-height?: function [grid [object!] y [integer!]][
		if 'auto = r: any [grid/heights/:y grid/heights/default] [
			r: any [grid/frame/heights/:y  grid/frame/heights/:y: calc-row-height grid y]
		]
		r
	]
		
	;@@ ensure it's only called from within render
	;@@ ensure it's called top-down only, so it can get upper row sizes from the cache
	calc-row-height: function [
		"Render row Y to obtain it's height"
		grid [object!] y [integer!]
	][
			;-- otherwise why call it?
		bounds: grid/calc-bounds
		xlim: bounds/x
									;-- row size cannot be calculated for infinite grid
		
		hmin: make block! xlim + 1						;-- can't be static because has to be reentrant!
		append hmin any [grid/heights/min 0]
		path: when not same? grid last current-path (get-host-path grid)	;-- let cells be rendered with proper style path
		 
		with-style path [
			for x: 1 xlim [
				canvas: (grid/col-width? x) . 1.#inf
				span: grid/get-span xy: x by y
				if span/x < 0 [continue]				;-- skip cells of negative x span (counted at span = 0 or more)
				cell1: grid/get-first-cell xy
				height1: 0
				if content: grid/cells/pick cell1 [
					; #assert [not content/parent =? grid  "cyclic cell wrapping detected!"]	;@@ grid-view has transparent wrapping
					cspace: grid/wrap-space cell1 content
					render/on cspace canvas yes no		;-- render to get the size; fill the cell's width
					height1: cspace/size/y
				]
				case [
					span/y = 1 [
						
						append hmin height1
					]
					span/y + y = cell1/y [				;-- multi-cell vertically ends after this row
						for y2: cell1/y y - 1 [
							height1: height1 - (grid/spacing/y) - grid/row-height? y2
						]
						append hmin height1
					]
					;-- else just ignore this and use heights/min
				]
				x: x + max 0 span/x - 1					;-- skip horizontal span
			]
		]
		height: second minmax-of hmin					;-- choose biggest of constraints
		#debug grid-view [#print "calc-row-height (y) -> (height)"]
		height
	]

	;; unlike `cell-height?` this does nothing complex, just sums widths, does not require cached row height
	cell-width?: function [grid [object!] xy [pair!]] [
			;-- should be a starting cell
		xspan: first grid/get-span xy
		r: 0 repeat x xspan [r: r + grid/col-width? x - 1 + xy/x]
		r + (xspan - 1 * (grid/spacing/x))
	]
		
	cell-height?: function [grid [object!] xy [pair!]] [
			;-- should be a starting cell
		#debug grid-view [						;-- assertion doesn't hold for self-containing grids
					;-- cell should be rendered already (for row-heights to return immediately)
		]
		yspan: second grid/get-span xy
		r: 0 repeat y yspan [r: r + grid/row-height? y - 1 + xy/y]
		r + (yspan - 1 * (grid/spacing/y))
	]
		
	;@@ for parts of a multicell this may require row-height/col-width calls - need more designing
	cell-size?: function [grid [object!] xy [pair!]] [
		as-point2D (cell-width? grid xy) (cell-height? grid xy) 
	]
		
	calc-size: function [grid [object!]] [
		if r: grid/size [return r]						;-- already calculated
		#debug grid-view [#print "grid/calc-size is called!"]
		
		bounds: grid/calc-bounds
		bounds: bounds/x by bounds/y					;-- turn block into pair
		#debug grid-view []
		r: (2,2) * grid/margin + (grid/spacing * max (0,0) bounds - 1)
		repeat x bounds/x [r/x: r/x + grid/col-width?  x]
		repeat y bounds/y [r/y: r/y + grid/row-height? y]
		#debug grid-view [#print "grid/calc-size -> (r)"]
		grid/size: r
	]
		
	;; can be styled but cannot be accessed (and in fact shared)
	;@@ similar to rich-content - possible to unify?
	selection-prototype: make-space 'space [type: 'selection cache: none]	;-- disabled cache to avoid cloning /cached facet
	cursor-prototype:    make-space 'space [type: 'cursor    cache: none]
	draw-box: function [prototype [object!] size [point2D!]] [
		box: copy prototype
		quietly box/size: size
		render box
	]
	
	;@@ TODO: at least for the chosen range, cell/drawn should be invalidated and cell/size recalculated
	draw-range: function [
		"Used internally by DRAW. Returns map slice & draw code for a range of cells"
		grid [object!] xy1 [pair!] xy2 [pair!] start [point2D!] "Offset from origin to xy1"
	][
		span:  xy2 - xy1 + 1
		drawn: make [] area: area? span
		map:   make block! area * 2								;-- draw appends it, so it can be obtained
		done:  make map! area									;-- local to this range of cells
																;-- sometimes the same mcell may appear in pinned & normal part
		for xy: xy1 xy2 [
			cell1-to-cell: either xy/x = xy1/x [				;-- pixels from xy1 to this cell's xy
				grid/get-offset-from xy1 xy
			][
				cell1-to-cell + grid/get-offset-from xy - 1x0 xy	;-- faster to get offset from the previous cell
			]

			mcell-xy: grid/get-first-cell xy					;-- row/col of multicell this cell belongs to
			if any [
				done/:mcell-xy									;-- skip mcells that were drawn for this group
				not content: grid/cells/pick mcell-xy			;-- cell is not defined? skip the draw
			] [continue]
			done/:mcell-xy: true								;-- mark it as drawn
			
			mcell-to-cell: grid/get-offset-from mcell-xy xy		;-- pixels from multicell to this cell
			draw-ofs: start + cell1-to-cell - mcell-to-cell		;-- pixels from draw's 0x0 to the draw box of this cell
			
			mcspace: grid/wrap-space mcell-xy content
			canvas: (cell-width? grid mcell-xy) . 1.#inf		;-- sum of spanned column widths
			render/on mcspace canvas yes no						;-- render content to get it's size - in case it was invalidated
			mcsize: canvas/x . cell-height? grid mcell-xy		;-- size of all rows/cols it spans = canvas size
			mcdraw: render/on mcspace mcsize yes yes			;-- re-render to draw the full background
			unless mcspace/size +<= mcsize [
				mcdraw: compose/only [clip 0x0 (mcsize) (mcdraw)]	;-- cell itself doesn't clip content to canvas, so grid has to do that
			]
			;@@ TODO: if grid contains itself, map should only contain each cell once - how?
			geom: compose [offset (draw-ofs) size (mcsize)]
			if sel?: all [grid/selected/x/(mcell-xy/x) grid/selected/y/(mcell-xy/y)] [
				mcdraw: compose/only [(mcdraw) (draw-box selection-prototype mcsize)]	;-- avoid modification in case it's a static block
			]
			if mcell-xy = grid/cursor [							;@@ draw cursor on a cell or multi-cell?
				mcdraw: compose/only [(mcdraw) (draw-box cursor-prototype mcsize)]
			]
			repend map [mcspace geom]							;-- map may contain the same space if it's both pinned & normal
			compose-after drawn [								;-- compose-map calls extra render, so let's not use it here
				translate (draw-ofs) (mcdraw)					;@@ can compose-map be more flexible to be used in such cases?
			]
		]
		reduce [map drawn]
	]

	;; uses canvas only to figure out what cells are visible (and need to be rendered)
	draw: function [
		grid [object!]
		canvas: infxinf [point2D! none!]
		fill-x: no [logic! none!]
		fill-y: no [logic! none!]
		wxy1 [none! point2D!]
		wxy2 [none! point2D!]
	][
		#debug grid-view [#print "grid/draw is called with window xy1=(wxy1) xy2=(wxy2)"]
			;-- bounds must be defined for an infinite grid
		
		do-invalidate grid
		frame: grid/frame
		frame/canvas: encode-canvas canvas fill-x fill-y

		;; prepare column widths before any offset-to-cell mapping, and before hcache is filled
		if all [fill-x  grid/autofit  not grid/infinite?] [
			autofit grid canvas/x grid/autofit
		]
 	
		frame/bounds: grid/cells/size					;-- may call calc-size to estimate number of cells
		
		;-- locate-point calls row-height which may render cells when needed to determine the height
		default wxy1: (0,0)
		unless wxy2 [wxy2: wxy1 + calc-size grid]
		xy1: max (0,0) wxy1 - grid/origin
		xy2: max (0,0) min xy1 + canvas wxy2

		;; affects xy1 so should come before locate-point
		unless (pinned: grid/pinned) +<= 0x0 [			;-- nonzero pinned rows or cols?
			xy0: xy1 + grid/margin						;-- location of drawn pinned cells relative to grid's origin
			set [map: drawn-common-header:] draw-range grid 1x1 pinned xy0
			xy1: xy1 + grid/get-offset-from 1x1 (pinned + 1x1)	;-- location of unpinned cells relative to origin
		]
		#debug grid-view [#print "drawing grid from (xy1) to (xy2)"]

		xy2: max xy1 xy2
		set [cell1: offs1:] grid/locate-point xy1
		set [cell2: offs2:] grid/locate-point xy2
		if none? grid/size [
			either grid/infinite? [grid/size: infxinf][calc-size grid]
		]
										;-- must be set by calc-size or carried over from the previous render

		quietly grid/map: make block! 2 * area? cell2 - cell1 + 1
		if map [append grid/map map]
		
		;@@ create a grid layout?
		if pinned/x > 0 [
			set [map: drawn-row-header:] draw-range grid
				(1 by cell1/y) (pinned/x by cell2/y)
				xy0/x . (xy1/y - offs1/y)
			append grid/map map
		]
		if pinned/y > 0 [
			set [map: drawn-col-header:] draw-range grid
				(cell1/x by 1) (cell2/x by pinned/y)
				(xy1/x - offs1/x) . xy0/y
			append grid/map map
		]

		set [map: drawn-normal:] draw-range grid cell1 cell2 (xy1 - offs1)
		append grid/map map
		frame/offset: xy1
		frame/addr1: cell1
		frame/addr2: cell2
		;; note: draw order (common -> headers -> normal) is important
		;; because map will contain intersections and first listed spaces are those "on top" from hittest's POV
		;; as such, map doesn't need clipping, but draw code does

		;@@ relax clipping when content fits - for dropdowns to be supported by headers
		;@@ current clipping mode was meant for spanned heading cells mainly, and for normal cells translation
		reshape [
			;; headers also should be fully clipped in case they're multicells, so they don't hang over the content:
			clip  0x0         @[xy1]           @[drawn-common-header]	/if drawn-common-header
			clip @[xy1 * 1x0] @[xy2/x . xy1/y] @[drawn-col-header]		/if drawn-col-header
			clip @[xy1 * 0x1] @[xy1/x . xy2/y] @[drawn-row-header]		/if drawn-row-header
			clip @[xy1]       @[xy2]           @[drawn-normal]
		]
	]
	
	;; NOTE: to properly apply styles this should only be called from within draw
	measure-column: function [
		"Measure single column's extent on the canvas of WIDTHxINF (returned size/x may be less than WIDTH)"
		grid  [object!]  "Uses only Y part from margin and spacing"
		index [integer!] "Column's index, >= 1"
		width [linear!]  "Allowed column width in pixels"
		row1  [integer!] "Limit estimation to a given row span"
		row2  [integer!]
	][
		size: (0,2) * grid/margin
		spc:  grid/spacing/y
		if row2 > row1 [size/y: size/y - spc]
		for irow row1 row2 [
			cell: index by irow
			unless space: grid/cells/pick cell [continue]
			cspace: grid/wrap-space cell space			;-- apply cell style too (may influence min. size by margin, etc)
			canvas': either integer? h: any [grid/heights/:irow grid/heights/default] [	;-- row may be fixed
				render/on cspace width . h no no		;-- fixed rows only affect column's width, no filling
			][
				render/on cspace width . 1.#inf no no
				h: cspace/size/y
			]
			span: grid/get-span cell1: grid/get-first-cell cell
			irow: cell1/y + span/y - 1
			;@@ make an option to ignore spanned cells?
			;@@ and theoretically I could subtract spacing from the spanned cells (in case it's big), but lazy for now
			size/y: size/y + spc + (h / span/x)			;-- span/x is accounted for only approximately
			size/x: max size/x cspace/size/x
		]
		size
	]
	
	;@@ when I document these, need a few showcase tables (text, text+images, fields maybe) and how each one works
	;@@ big image + text cell will be a good showcase for hyperbolic algo
	;@@ need a flag for paragraph to never wrap partial words
	;; fast stable content-agnostic column width fitter
	;; NOTE: to properly apply styles this should only be called from within draw (doesn't invalidate for that reason)
	autofit: function [
		"Automatically adjust GRID column widths to minimize grid height"
		grid        [object!]
		total-width [linear!] "Total grid width to fit into"
		method      [word!]    "One of supported fitting methods: [hyperbolic weighted simple-weighted]"	;@@
	][
		
		;; does not modify grid/heights - at least some of them must be `auto` for this func to have effect
		bounds: grid/cells/size
		nx: bounds/x  ny: bounds/y
		if any [nx <= 1 ny <= 0] [exit]					;-- nothing to fit - single column or no rows

		margin:    grid/margin
		spacing:   grid/spacing
		widths:    grid/widths							;-- modifies widths map in place
		min-width: any [widths/min 5]					;@@ make an option to control this?
				
		set [W1 H1 W2 H2] grid/frame/limits				;-- if W1/H1/W2/H2 are cached, use them
		new-vector: [add -1.0 make vector! reduce ['float! 64 nx]]	;-- negative or it will be considered cached
		
		loop 1 [										;-- needed to use `break`
			;; render all columns on zero, get their min widths W1i and heights H1i
			W1: any [W1  do new-vector]
			H1: any [H1  do new-vector]
			repeat i nx [
				if all [W1/:i >= 0 H1/:i >= 0] [continue]		;-- cached, still valid
				size: measure-column grid i 0 1 ny
				W1/:i: 1.0 * max min-width size/x
				H1/:i: 1.0 * size/y
			]
			
			;; estimate space left SL = TW - sum(W1i), TW is total-width requested
			TW: total-width - (2 * margin/x) - (nx - 1 * spacing/x)
			SL: TW - TW1: sum W1
			
			;; if SL <= 0, end here, set widths to found amounts
			if SL <= 0 [W: W1  break]
			
			;; SL > 0 case: render all columns on infinite canvas, now I have min heights H2i and max widths W2i
			W2: any [W2  do new-vector]
			H2: any [H2  do new-vector]
			repeat i nx [
				if all [W2/:i >= 0 H2/:i >= 0] [continue]		;-- cached, still valid
				size: measure-column grid i 1.#inf 1 ny
				W2/:i: max W1/:i 1.0 * size/x		;-- ensure monotony:
				H2/:i: min H1/:i 1.0 * size/y		;-- W2 >= W1, H2 <= H1
			]
			TW2: sum W2
			
			;; if maximum possible width is less than requested, use it
			;@@ maybe make an option to stretch the grid to TW even if there's no point?
			if TW2 <= TW [W: W2  break]
			
			;; now given initial W1-W2/H1-H2 bounds, find an optimum
			switch/default method [
				;; free space (over W1) is distributed by weights=(W2-W1)
				width-difference [						;-- this is what browsers are using, at least PaleMoon
					weights: W2 - W1
					W: weights / (sum weights) * SL + W1
				]
				
				;; total width is distributed by weights=W2, but no less than W1
				;@@ externalize this algo
				width-total [
					weights:  W2
					norm-W1:  W1 / weights
					w-vector: make block! nx * 4
					repeat i nx [						;@@ use map-each
						repend w-vector [norm-W1/:i  W1/:i  weights/:i  i]
					]
					sort/reverse/skip w-vector 4		;-- sorted from most oversized to most relaxed
					left: TW
					W:    copy W2
					wsum: sum weights
					foreach [_ wmin wgt i] w-vector [
						we:   wgt / wsum * left			;-- estimated weighted width for the column
						W/:i: max wmin we				;-- don't let it go lower than W1 (wmin)
						wsum: wsum - wgt				;-- next time normalize to the new sum of weights
						left: left - W/:i
					]
				]
				
				;; unlike width-total, area-total may assign width > W2, so have to clip it, which complicates the algorithm
				area-total			;-- assumes constant (W*H) for each column (equals W2*H2), special case of area-difference
				area-difference [	;-- assumes constant (W*H+C) for each column (equals both W2*H2 and W1*H1)
					either total?: method = 'area-total [
						C:  0.0
						W2*H2: W2 * H2					;-- weights basically
						H+: maximum-of W2*H2 / W1		;-- height where all width estimates become <= W1
					][
						C:  (H2 * W2) - (H1 * W1) / (H1 - H2 + 1e-6)	;-- hyperbolae offsets, +epsilon to avoid zero division
						H+: maximum-of H1
					]
					H-: minimum-of H2
					
					;; total width estimation (im)precision; @@ should be a controllable parameter I guess
					;; bigger requires less iterations but is more "jumpy" when resizing,
					;; since it adds pixels to all columns
					tolerance: 1
					
					WE: copy W1							;-- shortcut for make vector! reduce ['float! 64 length]
					HE2TWE: pick [[						;-- function TWE(HE) as F(x) for binary search
						; WE: (copy W2*H2) / HE
						WE: WE * 0.0 + W2*H2 / HE		;-- this spares me an extra copy on each iteration
						sum clip-vector WE W1 W2		;-- clip within [W1i,W2i] since hyperbola extends outside this segment
					][
						; WE: (copy W2) + C * H2 / HE - C
						WE: WE * 0.0 + W2 + C * H2 / HE - C
						sum clip-vector WE W1 W2
					]] total?
					
					;; now find height estimate HE corresponding to the closest width to TW using binary search
					set [H-: TW+: HE: TWE:]						;-- use lower width as estimate since it's <= TW
						apply 'search [HE: H- H+ HE2TWE /with on TW2 TW1 /for on TW /error on tolerance /mode on 'binary]
					
									
					;; find final widths W from height estimate HE
					W: (copy W2) + C * H2 / HE - C
					W: clip-vector W W1 W2
					W: W + (TW - TWE / length? W)				;-- evenly distribute remaining space
				]
			] [ERROR "Unknown fitting method: (method)"]
			
		]
		
		if grid/frame/limits [grid/frame/limits: reduce [W1 H1 W2 H2]]	;-- save min/max sizes
		
		;; set widths map to found W vector
		changed?: no
		repeat i nx [
			if widths/:i <> W/:i [
				changed?: yes
				widths/:i: W/:i
			]
		]
		if changed? [
			quietly grid/size: none						;-- size is no longer valid
			clear grid/frame/heights					;-- line height cache is no longer valid after widths have changed
		]
	]
	
	on-invalidate: function [
		grid  [object!]
		cell  [none! object!]
		scope [none! word!]
	][
		repend grid/frame/invalid [cell scope]
		cache/invalidate grid							;-- clears the cached canvas+sizes block so render will be called again
	]
	
	invalidate-xy: function [grid [object!] xy [pair!]] [
		remove/key grid/frame/heights xy/y
		foreach vector grid/frame/limits [vector/(xy/x): -1.0]
		quietly grid/size: none
	]
	
	do-invalidate: function [grid [object!]] [
		foreach [cell scope] grid/frame/invalid [
			; print ["INVAL" mold cell scope]
			if scope = 'size [
				either cell [
					if pos: find/same grid/frame/cells cell [
						invalidate-xy grid pick pos -1
					]
				][
					quietly grid/size: none
				]
			]
		]
		clear grid/frame/invalid
	]
	
	get-cell-address: function [grid [object!] cell [object!] ('cell = select cell 'type)] [
		all [
			found: find/same grid/frame/cells cell
			found/-1
		]
	]
	pinned?: function [cell [object!]] [				;-- used by cell/pinned?
		to logic! all [
			grid: above cell 'grid						;-- sometimes grid is not an immediate parent
			xy: get-cell-address grid cell
			grid/is-cell-pinned? xy
		]
	]
	
	format: function [grid [object!]] [
		if grid/infinite? [return copy {}]
		bounds: grid/cells/size
		format: copy {}
		rows: map-each/only irow bounds/y [
			cells: map-each/only icol bounds/x [		;-- /only so even empty cells are separated by tabs
				cell: grid/cells/pick icol by irow
				batch cell [format]
			]
			delimit cells "^-"
		]
		text: to {} delimit rows "^/"
		#debug clipboard [#print "  grid/format (\(space-id grid)): (mold/part text 120)"]
		text
	]
	
	;@@ move grid internal funcs here!
	kit: make-kit 'grid [
		format: does [~/format space]
		
		here: function ["Get address of a cell under cursor"] [
			any [space/cursor space/pinned + 1]
		]
		
		locate: function [
			"Get address of a named location"
			name [word!]
		][
			cursor: here
			minxy:  space/pinned + 1
			maxx:   any [space/frame/bounds/x space/frame/addr2/x]	;-- jump to last rendered cell if unlimited
			maxy:   any [space/frame/bounds/y space/frame/addr2/y]
			switch/default name [
				far-head    [minxy]								;-- ^Home leads to first data (not header) cell
				far-tail    [maxx by maxy]
				head        [minxy/x by cursor/y]
				tail        [maxx by cursor/y]
				line-up     [cursor/x by max cursor/y - 1 minxy/y]
				line-down   [cursor/x by min cursor/y + 1 maxy]
				column-head [cursor/x by minxy/y]
				column-tail [cursor/x by maxy]
				row-head    [minxy/x by cursor/y]
				row-tail    [maxx by cursor/y]
				prev-cell   [(max cursor/x - 1 minxy/x) by cursor/y]
				next-cell   [(min cursor/x + 1 maxx) by cursor/y]
				; page-up   [frame/page-above here]		;@@ TODO - page jumps
				; page-down [frame/page-below here]
			] [here]											;-- unknown words assume current address
		]
		
		;@@ TODO: should be brought into the viewport once I roll out new design (now only possible in grid-view)
		move-cursor: function [
			; "Redefine cursor and move viewport to make it fully visible"	;@@ viewport part is TBD!
			"Redefine cursor"
			target [word! pair! none!] "none disables cursor"
			; /margin mrg [integer!] "How much to reserve around the item"
			; /no-clip "Allow panning outside the window"
		][
			either target [
				if word? target [target: locate target]
				target: max 1x1 target
				bounds: space/frame/bounds
				space/cursor: as-pair
					min-safe target/x bounds/x					;@@ any easier way? 1.#inf will promote pair to point
					min-safe target/y bounds/y					;@@ REP #122
			][
				space/cursor: none
			]
		]
		
		select-columns: function [
			"Redefine columns selection"
			cols [none! word! bitset! integer! pair! block!] "1-based set of integers or an inclusive range"
			/mode sel-mode [word!] "Specify selection mode (default: 'replace)"
		][
			select-along/:mode 'x cols sel-mode 
		]
		
		select-rows: function [
			"Redefine rows selection"
			rows [none! word! bitset! integer! pair! block!] "1-based set of integers or an inclusive range"
			/mode sel-mode [word!] "Specify selection mode (default: 'replace)"
		][
			select-along/:mode 'y rows sel-mode 
		]
		
		select-along: function [
			"Redefine selection along given axis"
			axis [word!] (find [x y] axis) "x or y"
			bits [block! (parse bits [any integer!]) word! (bits = 'all) none! bitset! integer! pair!]
				"1-based set of integers or an inclusive range or 'all"
			/mode "Specify selection mode (default: 'replace)"
				sel-mode: 'replace [word!] (find [replace include exclude invert] sel-mode)
		][
			;@@ TODO: warning on huge bitsets
			switch type?/word bits [
				none!    [bits: charset 0]
				pair!    [bits: bit-range bits]
				integer! [bits: bit-range bits thru bits]
				block!   [bits: charset bits]
				word!    [
					limit: any [space/frame/bounds/:axis space/frame/addr2/:axis]
					bits:  bit-range 1 thru limit
				]
			]
			
			old: space/selected/:axis
			new: switch sel-mode [
				replace [bits]
				include [old or bits]
				exclude [exclude old bits]
				invert  [old xor bits]
			]
			space/selected/:axis: new
			trigger 'space/selected
		]
		
		;@@ how to select nothing? also in list-view
		select-range: function [
			"Redefine selection as a 2D range of cells, or extend up to a given limit"
			start [word! pair!] "Named location, cell address or 'extend to use existing selection start"
			limit [word! pair!] "Named location or cell address"
		][
			if word? limit [limit: locate limit]
			if word? start [start: either start = 'extend [here][locate start]]
			foreach x [x y] [select-along x start/:x thru limit/:x]
		]
		
		;@@ temporary until I find a better interface for it
		deselect: function [
			"Remove any existing selection"
		][
			foreach x [x y] [select-along x none]
		]
		
		selected-range: function ["Get bounding corners of current selection as 2 pairs (or none if no selection)"] [
			range: [0x0 0x0]
			foreach x [x y] [
				bits: space/selected/:x
				unless lo: lowest-bit bits [return none]
				hi: highest-bit bits
				range/1/:x: lo	;max lo space/pinned/:x + 1
				range/2/:x: hi	;min hi any [space/frame/bounds/:x space/frame/addr2/:x]
			]
			copy range
		]
		
		copy-selection: function [
			"Copy and return selected cells text"
			/clip "Write it into clipboard"
		][
			xs: unroll-bitset space/selected/x
			ys: unroll-bitset space/selected/y
			rows: make [] 16
			row:  make [] 16
			format: {}									;-- fallback for non-formattable cells
			
			foreach y ys [
				foreach x xs [
					append row batch space/cells/pick x by y [format]
				]
				append rows join row #"^-"
				clear row
			]
			text: join rows #"^/"
			if clip [
				#debug clipboard [#print "grid/copy-selection (\(space-id space)): (mold/part text 120)"]
				clipboard/write text
			]
			text
		]
	]
	
	;@@ add simple proportional algorithm?
	fit-types: [width-total width-difference area-total area-difference]	;-- for type checking
	
	;@@ base it on container?
	declare-template 'grid/space [
		kit:  ~/kit
		;; grid's /size can be 'none' if it was invalidated and needs a calc-size() call
		;@@ need a better solution than this
		size: none	#type [point2D! none!]
		
		margin:  5
		spacing: 5
		origin:  (0,0)			;-- scrolls unpinned cells (should be <= (0,0)), mirror of grid-view/window/origin ;@@ make it read-only
		content: make map! 8	#on-change :invalidates			;-- XY coordinate -> space (not cell, but cells content)
		spans:   make map! 4	#type [map!]					;-- XY coordinate -> it's XY span (not user-modifiable!!)
		;; widths/min used in `autofit` func to ensure no column gets zero size even if it's empty
		widths:  make map! [default 100 min 10]					;-- map of column -> it's width
			#type [map!] :invalidates
		;; heights/min used when heights/default = auto, in case no other constraints apply
		;; set to >0 to prevent rows of 0 size (e.g. if they have no content)
		heights: make map! [default auto min 0]					;-- height can be 'auto (row is auto sized) or integer (px)
			#type [map!] :invalidates
		autofit: 'area-total									;-- automatically adjust column widths? method name or none
			#type = :invalidates [word! (find ~/fit-types autofit) none!]
		pinned:  0x0						;-- how many rows & columns should stay pinned (as headers), no effect if origin = (0,0)
			#type =? :invalidates-look [pair!] (0x0 +<= pinned)
		bounds:  [x: auto y: auto]								;-- max number of rows & cols
			#type :invalidates [block! function! pair!]
			;@@ none should be forbidden in favor of infinity
			(all [										;-- 'auto=bound /cells, integer=fixed, none=infinite (only within a window!)
				bounds: bounds							;-- call it if it's a function
				any [none =? bounds/x  'auto = bounds/x  all [linear? bounds/x  bounds/x >= 0]]
				any [none =? bounds/y  'auto = bounds/y  all [linear? bounds/y  bounds/y >= 0]]
			])
			
		cursor: none	#type =? [pair! none!] :invalidates-look
		
		;; selected cells are the crossing of two bitsets; 1-based indexing here so bit 0 is unused
		selected: make map! reduce [
			'x charset []
			'y charset []
		] #type [map!] ([all [bitset? :selected/x bitset? :selected/y]]) :invalidates-look
		
		;; data about the last rendered frame, may be used by /draw to avoid extra recalculations
		frame: context [								;@@ hide it maybe from mold? unify with /last-frame ?
			;@@ maybe cache size too here? just to avoid setting grid/size to none in case it's relied upon by some reactors
			;@@ maybe cache drawn and map and only remake the changed parts? is it worth it?
			;@@ maybe width not canvas?
			canvas:  none								;-- encoded canvas of last draw 
			;@@ support more than one canvas? canvas/x affects heights, limits if autofit is on
			bounds:  none								;-- WxH number of cells (pair/block), used by draw & others to avoid extra calculations
			offset:  (0,0)								;-- used to find the headers location on current grid frame
			;@@ also need to know addresses of cells within current window! - for the grid-view key handlers
			addr1:   none								;-- first drawn cell address (excluding pinned)
			addr2:   none								;-- last drawn cell address - useful for frame navigation
			heights: make map!   4						;-- cached heights of rows marked for autosizing
			;; "cell cache" - cached `cell` spaces: [XY cell ...] and [space XY geometry ...]
			;; persistency required by the focus model: cells must retain sameness, i.e. XY -> cell
			;@@ TODO: changes to content must invalidate ccache! but no way to detect those changes, so only manually possible
			cells:   make hash!  8						;-- cells that wrap content, filled by render and height estimator
			;; min & max column widths & heights cache (if not cached, spends 2 more rendering attempts on each render with autofit)
			limits:  make block! 4						;-- either none(disabled) or block; block is filled by autofit: [W1 H1 W2 H2]
			invalid: make block! 8						;-- invalidation list for the next frame
		] #type [object!]
		
		;@@ perhaps 'self' argument should be implicit in on-invalidate?
		on-invalidate: :~/on-invalidate					;-- grid uses custom invalidation or it's too slow
		
		;@@ TODO: margin & spacing - in style??
		;@@ TODO: alignment within cells? when cell/size <> content/size..
		;@@       and how? per-row or per-col? or per-cell? or custom func? or alignment should be provided by item wrapper?
		;@@       maybe just in lay-out-grid? or as some hacky map that can map rows/columns/cells to alignment?
		map: []
		
		;; ccache cannot be stashed/replaced because otherwise it's possible to press a button in a cell,
		;; and upon release there will be another cell, the old one will be lost, so hittest will be confused
		;@@ so when and how to invalidate ccache? makes most sense on content change and when it gets out of the viewport
		; cache: [size map hcache fitcache size-cache]
		cache: []
		
		wrap-space: function [xy [pair!] space [object! none!]] [	;-- wraps any cells/space into a lightweight "cell", that can be styled
			unless cell: frame/cells/:xy [
				cell: make-space 'cell [pinned?: does [grid-ctx/pinned? self]]
				repend frame/cells [xy cell] 
			]
			quietly cell/parent: none					;-- prevent grid invalidation in case new space is assigned
			cell/content: space
			cell
		] #type [function!] :invalidates

		cells: func [/pick xy [pair!] /size] [			;-- up to user to override
			either pick [content/:xy][calc-bounds]
		] #type [function!] :invalidates				;@@ should clear frame/cells too!
		
		into: func [xy [planar!] /force child [object! none!]] [~/into self xy child]
		
		;-- userspace functions for `spans` reading & modification
		;-- they are required to be able to get any particular cell's multi-cell without full `spans` traversal
		get-span: function [
			"Get the span value of a cell at XY"
			xy [pair!] "Column (x) and row (y)"
		][
			any [spans/:xy  1x1]
		] #type [function!]

		get-first-cell: function [
			"Get the starting row & column of a multicell that occupies cell at XY"
			xy [pair!] "Column (x) and row (y); returns XY unchanged if no such multicell"
		][
			span: get-span xy
			if span +< 1x1 [xy: xy + span]
			xy
		] #type [function!]

		set-span: function [
			"Set the SPAN of a FIRST cell, breaking it if needed"
			cell1 [pair!] "Starting cell of a multicell or normal cell that should become a multicell"
			span  [pair!] "1x1 for normal cell, more to span multiple rows/columns"
			/force "Also break all multicells that intersect with the given area"
		][
			~/set-span self cell1 span force
		] #type [function!]
		
		get-offset-from: function [
			"Get pixel offset of left top corner of cell C2 from that of C1"
			c1 [pair!] c2 [pair!]
		][
			~/get-offset-from self c1 c2
		] #type [function!]
		
		locate-point: function [
			"Map XY point on a grid into a cell it lands on, return [cell-xy offset]"
			xy [planar!]
			/screen "Point is on rendered viewport, not on the grid"
			; return: [block!] "offset can be negative for leftmost and topmost cells"
		][
			~/locate-point self xy screen
		] #type [function!]

		row-height?: function [
			"Get height of row Y (only calculate if necessary)"
			y [integer!]
		][
			~/row-height? self y
		] #type [function!]

		col-width?: function [
			"Get width of column X"
			x [integer!]
		][
			any [widths/:x widths/default]
		] #type [function!]

		cell-size?: function [
			"Get the size of a cell XY or a multi-cell starting at XY (with the spaces)"
			xy [pair!]
		][
			~/cell-size? self xy
		] #type [function!]

		is-cell-pinned?: func [
			"Check if XY is within pinned row or column"
			xy [pair!]
		][
			not pinned +< xy
		] #type [function!]

		infinite?: function ["True if not all grid dimensions are finite"] [
			bounds: self/bounds							;-- call it in case it's a function
			not all [bounds/x bounds/y]
		] #type [function!]

		;; returns a block [x: y:] with possibly `none` (unlimited) values ;@@ REP #116 could solve this
		;@@ maybe obsolete (hide) this, since now there's valid /size? although /size can't account for half-infinite bounds
		;@@ I also don't like the name, 'bounds' is too confusing (how is it different from /size?)
		calc-bounds: function ["Estimate total size of the grid in cells (in case bounds set to 'auto)"] [
			~/calc-bounds self
		] #type [function!]
	
		;; hidden because /size should be valid now, and this function triggered out of tree rendering
		; calc-size: function ["Estimate total size of the grid in pixels"] [~/calc-size self]

		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!] /window xy1 [none! point2D!] xy2 [none! point2D!]] [
			~/draw self canvas fill-x fill-y xy1 xy2
		]
	]
]


grid-view-ctx: context [
	~: self
	
	;; gets called before grid/draw by window/draw to estimate the max window size and thus config scrollbars accordingly
	available?: function [
		grid      [object!]
		axis      [word!]
		dir       [integer!]
		from      [linear!] (from >= 0)
		requested [linear!] (requested >= 0)
	][	
		#debug grid-view [print ["grid/available? is called at" axis dir from requested]]	
		bounds: grid/bounds
		
		r: case [
			dir < 0 [from]
			bounds/:axis [
				size: grid-ctx/calc-size grid			;@@ maybe /size will be enough?
				max 0 size/:axis - from
			]
			'infinite [requested]
		]
		
		r: clip 0 r requested
		#debug grid-view [#print "avail?/(axis) (dir) = (r) of (requested)"]
		r
	]
	
	on-source-change: function [gview [object!] word [word!] value [any-type!]] [
		if object? :gview/grid [invalidate gview/grid]
	]

	kit: make-kit 'grid-view [
		format: does [batch space/grid [format]]
		
		locate: function [
			"Get address of a named location"
			name [word!]
		][
			cursor: batch space/grid [here]
			switch/default name [
				page-up   [frame/page-above cursor]
				page-down [frame/page-below cursor]
			] [batch space/grid [locate name]]
		]
		
		frame: object [
			;@@ these, as well as next/prev cell locators, should skip the same multicell
			page-above: function [
				"Get address of an cell one page above the given one"
				addr [pair!]
			][
				vp: space/viewport
				xy: space/grid/margin + space/grid/get-offset-from 1x1 addr
				addr: first space/grid/locate-point xy - (0 . vp/y)
				max addr space/grid/pinned + 1
			]
			
			page-below: function [
				"Get address of an cell one page below the given one"
				addr [pair!]
			][
				vp: space/viewport
				xy: space/grid/margin + space/grid/get-offset-from 1x1 addr
				addr: first space/grid/locate-point xy + (0 . vp/y)
				frame: space/grid/frame
				maxx: any [frame/bounds/x frame/addr2/x]	;-- jump to last rendered cell if unlimited
				maxy: any [frame/bounds/y frame/addr2/y]
				min addr maxx by maxy
			]
		]
		
		;@@ temporary! will be automatic after grid redesign (currently panning can only be done by grid-view, but cursor belongs to the grid)
		;@@ perhaps in multicells it should draw cursor as big as multicell itself? but then it may make some cells inaccessible using keyboard
		pan-to-cursor: function [/margin mrg: 0 [linear! planar!]] [
			csize:  space/grid/cell-size? cursor: space/grid/cursor
			csize:  csize + (space/grid/spacing * 2)
			offset: space/grid/get-offset-from 1x1 cursor
			pinned: space/grid/get-offset-from 1x1 space/grid/pinned + 1	;-- have to consider pinned area
			; ?? [csize offset pinned space/window/origin space/grid/origin]
			target: space/grid/margin - space/grid/spacing + offset + (csize - pinned / 2) 
			space/move-to/margin/no-clip target + space/window/origin (csize + pinned / 2) + mrg
		]
	]

	declare-template 'grid-view/inf-scrollable [
		kit: ~/kit
		;@@ TODO: slide-length should ensure window size is bigger than viewport size + slide
		;@@ situation when jump clears a part of a viewport should never happen at runtime
		;@@ TODO: maybe a % of viewport instead of fixed jump size?
		size: (0,0)		#type = #on-change [space word value] [quietly space/slide-length: min value/x value/y]
		
		;; reminder: window/slide may change this (together with window/origin) when sliding
		;; grid/origin mirrors grid-view/origin: former is used to relocate pinned cells, latter is normal part of scrollable
		origin: (0,0)	#type = #on-change [space word value] [space/grid/origin: value]	;-- grid triggers invalidation
		
		;; while grid supports rendering selection, only grid-view has the handlers to interact with it
		extend behavior [selectable: #(none)]					;-- none=don't select; single=select one cell; multi=cell range
		
		;; used by event handlers to provide familiar selection behavior
		selection-start: none	#type [pair! none!]
		
		content-flow: 'planar
		source: make map! [size: 0x0]	#on-change :on-source-change	;-- map is more suitable for spreadsheets than block of blocks
		data: function [/pick xy [pair!] /size] [
			switch/default type?/word :source [
				block! [
					case [
						pick [:source/(xy/2)/(xy/1)]
						0 = n: length? source [0x0]
						'else [as-pair length? :source/1 n]
					]
				]
				map! [either pick [source/:xy][source/size]]
			][
				ERROR "Unsupported data source type: (mold type? :source)"
			]
		] #type [function!] :invalidates

		;; only called initially or after invalidate-range
		wrap-data: function [item-data [any-type!]] [
			spc: make-space 'data-view [				;@@ 'quietly' used as optimization but must be in sync with data-view/on-change
				quietly type:  'cell
				quietly wrap?:  on						;-- will be considered upon /data change
				quietly margin: 3x3
				quietly align: -1x0
				pinned?: does [grid-ctx/pinned? self]
			]
			set/any 'spc/data :item-data
			spc
		] #type [function!] :invalidates

		;; cacheability requires window to be fully rendered but
		;; full window render is too slow (many seconds), can't afford it
		;; so instead, grid redraws visible part every time
		window/cache: none
		
		window/content: grid: make-space 'grid [
			;; while this should not pose a danger of extra invalidation, since cells are not under user's control,
			;; currently cells is a hash (for reverse lookups), while content is a map
			; frame/cells: content
		
			;; no need to wrap data-view because it's already a box/cell
			wrap-space: function [xy [pair!] space [object!]] [
				; put frame/cells xy get space
				pos: any [find frame/cells xy  tail frame/cells]
				rechange pos [xy space]					;-- used by grid for reverse lookups (e.g. during styling)
				space
			]
			
			available?: function [axis [word!] dir [integer!] from [linear!] requested [linear!]] [	
				~/available? self axis dir from requested
			]
			
			;; currently the only way to make grid forget its rendered content, since we can't "watch" /data
			invalidate-range: function [xy1 [pair!] xy2 [pair!]] [
				xyloop xy xy2 - xy1 + 1 [				;@@ should be for-each
					remove/key grid/content xy + xy1 - 1
				]
				invalidate self
			]
			
			;@@ should grid support selection or just grid-view? or put low level selection into grid, but events in grid-view?
			is-cell-selected?: func [
				"Check if cell XY is marked"
				xy [pair!]								;@@ check if xy within bounds?
			][
				selected/x/(xy/x) and selected/y/(xy/y)
			]
		] #type (space? grid)
		
		grid/cells: func [/pick xy [pair!] /size] [
			either pick [
				any [
					grid/content/:xy					;@@ need to think when to free this up, maybe when cells get hidden
					grid/content/:xy: grid/wrap-space xy wrap-data data/pick xy
				]
			][
				size: data/size
				
				size
			]
		]
		grid/calc-bounds: grid/bounds: does [grid/cells/size]
	]
]


button-ctx: context [
	~: self
	
	declare-template 'clickable/box [					;-- low-level primitive, unlike data-view
		;@@ should pushed be in button rather?
		align:    0x0									;-- center by default
		command:  []									;-- code to run on click (on up: when `pushed?` becomes false)
		
		pushed?:  no	#type =? [logic!]				;-- becomes true when user pushes it; triggers `command`
		#on-change [space word value] [
			invalidate space
			unless value [do space/command]				;-- trigger when released
		]
		;@@ should command be also a function (actor)? if so, where to take event info from?
	]

	;; main point of this being separate from button is to keep it not focusable (and so without a focus frame)
	declare-template 'data-clickable/data-view [		;@@ any better name?
		;@@ should pushed be in button rather?
		align:    0x0									;-- center by default
		command:  []									;-- code to run on click (on up: when `pushed?` becomes false)
		
		pushed?:  no	#type =? [logic!]				;-- becomes true when user pushes it; triggers `command`
		#on-change [space word value] [
			invalidate space
			unless value [do space/command]				;-- trigger when released
		]
		;@@ should command be also a function (actor)? if so, where to take event info from?
	]
	
	declare-template 'button/data-clickable [			;-- styled with decor
		weight:   0										;-- button should not be stretched by tubes
		margin:   10x5
		rounding: 5	#type [integer!] (rounding >= 0)	;-- box rounding radius in px
		; edge:     on	#type =? [logic!]				;-- enables border decor ;@@ more edge styles?
	]
]


;@@ this should not be generally available, as it's for the tests only - remove it!
declare-template 'rotor/space [
	content: none	#type =? :invalidates [object! none!]
	angle:   0		#type =  :invalidates-look [linear!]

	ring: make-space 'space [type: 'ring size: (360,10)]
	tight?: no
	;@@ TODO: zoom for round spaces like spiral

	map: reduce [							;-- unused, required only to tell space iterators there's inner faces
		ring [offset (0,0) size (1e3,1e3)]				;-- 1st = placeholder for `content` (see `draw`)
	]
	cache: [size map]
	
	into: function [xy [planar!] /force child [object! none!]] [
		unless spc: content [return none]
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
		r2: r1 + 10
		c: cosine angle  s: negate sine angle
		p0: p: xy - (size / 2)							;-- p0 is the center
		p: as-point2D  p/x * c - (p/y * s)  p/x * s + (p/y * c)	;-- rotate the coordinates
		xy: p + (size / 2)
		xy1: size - spc/size / 2
		if any [child =? content  r1 > distance? 0x0 p] [
			return reduce [content xy - xy1]
		]
		r: p/x ** 2 + (p/y ** 2) ** 0.5
		a: (arctangent2 0 - p0/y p0/x) // 360					;-- ring itself does not rotate
		if any [child =? ring  all [r1 <= r r <= r2]] [
			return reduce [ring  as-point2D a r2 - r]
		]
		none
	]

	draw: function [] [
		render ring						;-- connect it to the tree
		unless content [return []]
		map/1: spc: content				;-- expose actual name of inner face to iterators
		drawn: render content			;-- render before reading the size
		r1: to 1 either tight? [
			(min spc/size/x spc/size/y) + 50 / 2
		][
			distance? 0x0 spc/size / 2
		]
		self/size: r1 + 10 * (2,2)
		compose/deep/only [
			push [
				line-width 10
				translate (size / 2)
				rotate (angle)
				(collect [
					repeat i 5 [
						keep compose [arc 0x0 (r1 + 5 * 1x1) (a: i * 72 - 24 - 90) 48]
					]
				])
				; circle (size / 2) (r1 + 5)
			]
			translate (size - spc/size / 2) [
				rotate (angle) (spc/size / 2)
				(drawn)
			]
		]
	]
]


;@@ TODO: can I make `frame` some kind of embedded space into where applicable? or a container? so I can change frames globally in one go (margin can also become a kind of frame)
;@@ if embedded, map composition should be a reverse of hittest: if something is drawn first then it's at the bottom of z-order
field-ctx: context [
	~: self
	
	;; caret is separate space so it can be styled, but no `field-caret` template is needed, so it's just a class
	caret-template: declare-class 'field-caret/caret [
		type: 'caret
		look-around: 10		#type = [linear!] (look-around >= 0)	;-- how close caret is allowed to come to field borders
	]
	
	non-ws: negate ws: charset " ^-"
		
	find-prev-word: function [field [object!] from [integer!]] [
		rev: reverse append/part clear {} field/text from
		parse rev [any ws some non-ws rev: (return from - skip? rev)]
		0
	]
	
	find-next-word: function [field [object!] from [integer!]] [
		pos: skip field/text from
		parse pos [any ws some non-ws pos: (return skip? pos)]
		length? field/text
	]
	
	playback: function [field [object!] offset [integer!] selected [pair! none!] text [any-string!]] [
		
		change/part field/text text tail field/text
		
		field/caret/offset: offset
		field/selected: selected
	]
	
	push-to-timeline: function [
		field [object!]
		left  [block!] (parse left  [integer! [pair! | none!] any-string!])
		right [block!] (parse right [integer! [pair! | none!] any-string!])
	][
		left:  reduce ['playback field left/1  left/2  left/3]
		right: reduce ['playback field right/1 right/2 right/3]
		set [space': left': right':] field/timeline/last-event
		if group?: all [
			field =? space'
			elapsed: field/timeline/elapsed?
			elapsed < 0:0:1
		][
			left: left'
			field/timeline/unwind
		]
		unless empty-change?: left/5 == right/5 [		;-- happens when grouping with reverse event
			field/timeline/put field left right
		]
	]
		
	kit: make-kit 'field [
		length: function ["Get text length"] [
			length? space/text
		]
		
		everything: function ["Get full range of text"] [
			0 thru length
		]
		
		selected: function ["Get selection range or none"] [
			all [sel: space/selected  sel/1 <> sel/2  sel]
		]
		
		here: function ["Get current caret offset"] [
			space/caret/offset
		]
		
		frame: object [
			point->caret: function [
				"Get caret location [0..length] closest to given offset on last frame"
				xy [planar! linear!] "If integer, Y=0"
			][
				if number? xy [xy: xy . 0]
				-1 + offset-to-caret
					space/spaces/text/layout
					xy - space/margin - (space/origin . 0)
			]
			
			adjust-origin: function [
				"Adjust field origin so that caret is visible"
			][
				quietly space/origin: ~/adjust-origin space
			]
		]
		
		select-range: function ["Replace selection" range [pair! none!]] [
			space/selected: if range [clip range 0 length]
		]
		
		record: function [code [block!]] [
			set [space': left': right':] space/timeline/last-event 
			left:  reduce [here selected copy space/text]
			do code
			right: reduce [here selected copy space/text]
			~/push-to-timeline space left right
		]
	
		undo: does [space/timeline/undo]
		redo: does [space/timeline/redo]
	
		;@@ move these into text template?
		locate: function [
			"Get offset of a named location"
			name [word!]
		][
			switch/default name [
				head far-head [0]
				tail far-tail [length]
				prev-word [~/find-prev-word space space/caret/offset]
				next-word [~/find-next-word space space/caret/offset]
			] [space/caret/offset]						;-- don't move on unsupported anchors
		]
	
		move-caret: function [
			"Displace the caret"
			pos [word! (not by) integer!]
			/by "Move by a relative integer number of chars"
		][
			if word? pos [pos: locate pos]
			if by        [pos: space/caret/offset + pos]
			space/caret/offset: clip 0 length pos
		]
	
		select-range: function [
			"Redefine selection or extend up to a given limit"
			limit [word! pair! none! (not by) integer!]
			/by "Move selection edge by an integer number of chars"
		][
			set [ofs: sel:] ~/compute-selection space limit by space/caret/offset length selected
			space/caret/offset: ofs
			space/selected: sel
		]
	
		copy-range: function [
			"Copy and return specified range of text"
			range: 0x0 [pair! none!]
			/clip "Write it into clipboard"
		][
			slice: copy/part space/text range + 1
			if clip [
				#debug clipboard [#print "field/copy-range (\(space-id space)): (mold/part slice 120)"]
				clipboard/write slice
			]
			slice
		]
			
		remove-range: function [
			"Remove range from caret up to a given limit"
			limit [word! pair! (not by) integer! none!]
			/by "Relative integer number of char"
			/clip "Write it into clipboard"
		][
			case/all [
				not limit      [exit]					;-- for `remove selected` transparency
				word? limit    [limit: locate limit]
				by             [limit: space/caret/offset + limit]
				integer? limit [limit: as-pair space/caret/offset limit]
				pair? limit [
					limit: system/words/clip 0 length order-pair limit 
					if clip [
						slice: copy/part space/text limit + 1
						#debug clipboard [#print "field/remove-range (\(space-id space)): (mold/part slice 120)"]
						clipboard/write slice
					]
					if limit/1 <> limit/2 [
						record [ 
							remove/part  skip space/text limit/1  n: span? limit
							adjust-offsets space limit/1 negate n
						]
					]
				]
			]
		]
	
		insert-items: function [
			"Insert text at given offset"
			offset [word! integer!]
			text   [any-string!]
		][
			unless empty? text [
				if word? offset [offset: locate offset]
				offset: clip offset 0 length
				record [
					insert (skip space/text offset) text
					adjust-offsets space offset length? text
				]
			]
		]
	
		paste: function [
			"Paste text from clipboard at given offset"
			offset [integer!]
		][
			if str: clipboard/read/text [insert-items offset str] 
		]
	
	]
	
	adjust-offsets: function [field [object!] offset [integer!] shift [integer!]] [
		foreach path [field/selected/1 field/selected/2 field/caret/offset] [
			if attempt [offset <= value: get path] [
				set path max offset value + shift
			]
		]
	]
	
	;; selection anchor to pair converter shared by field and document
	compute-selection: function [
		space     [object!]
		limit     [pair! word! integer! none!]
		relative? [logic!]
		offset    [integer!]
		length    [integer!]
		selected  [pair! none!]
	][
		; ?? [limit relative? offset length selected]
		case [
			not limit      [return reduce [offset none]]
			relative?      [ofs: offset + limit]
			integer? limit [ofs: limit]
			pair?    limit [sel: limit]
			'else [
				switch/default limit [
					none #(none) [sel: none]
					all [sel: 0 thru length]
				][
					ofs: batch space [locate limit]		;-- document's locate can return a block
					if block? ofs [ofs: ofs/offset]		;-- ignores returned side
				]
			]
		]
		either ofs [									;-- selection extension/contraction
			ofs: clip ofs 0 length
			sel: any [selected  1x1 * offset]
			other: case [
				sel/1 = offset [sel/2]
				sel/2 = offset [sel/1]
				'else [offset]							;-- if caret is not at selection's edge, ignore previous selection
			]
			sel: other thru ofs
		][												;-- selection override
			if sel [sel: clip sel 0 length]
			ofs: either sel [sel/2][offset]				;-- 'select none' doesn't move the caret
		]
		reduce [ofs  if sel [order-pair sel]]
	]
	
	adjust-origin: function [
		"Return field/origin adjusted so that caret is visible"
		field [object!]
	][
		cmargin: field/caret/look-around
		;; layout may be invalidated by a series of keys, second key will call `adjust` with no layout
		;; also changes to text in the event handler effectively make current layout obsolete for caret-to-offset estimation
		;; field can just rebuild it since canvas is always known (infinite)
		layout: paragraph-ctx/lay-out field/spaces/text infxinf no no
		
		view-width: field/size/x - first (2 * field/margin)
		text-width: layout/extra/x
		cw: field/caret/width
		if view-width - cmargin - cw >= text-width [return 0]	;-- fully fits, no origin offset required
		co: field/caret/offset + 1
		cx: first caret-to-offset layout co
		min-org: min 0 cmargin - cx
		max-org: clip min-org 0 view-width - cx - cw - cmargin
		clip field/origin min-org max-org
	]
			
	draw: function [field [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		ctext: field/spaces/text						;-- text content
		invalidate/only ctext							;-- ensure text is rendered too ;@@ TODO: maybe I can avoid this?
		drawn: render/on ctext infxinf no no			;-- this sets the size
		; #assert [field/size/x = canvas/x]				;-- below algo may need review if this doesn't hold true
		cmargin: field/caret/look-around
		;; fill the provided canvas, but clip if text is larger (adds cmargin to optimal size so it doesn't jump):
		width: first either fill-x [canvas][min ctext/size + cmargin canvas]	
		field/size: constrain width . ctext/size/y field/limits
		mrg: field/margin
		;; draw does not adjust the origin, only event handlers do (this ensures it's only adjusted on a final canvas)
									;-- should be set after draw, others may rely
		ofs: field/origin . 0
		quietly field/map: compose/deep [
			(ctext) [offset: (ofs) size: (ctext/size)]
		]
		compose/deep/only [
			clip (mrg) (field/size - mrg) [
				translate (ofs) (drawn)
			]
		]
	]
		
	on-change: function [field [object!] word [word!] value [any-type!]] [
		if find [spacing margin] word [set in field word value: value * 1x1]	;-- normalize to pair
		set/any 'field/spaces/text/:word :value			;-- sync these to text space; invalidated by text
		if word = 'text [								;-- count it in the history
			field/caret/offset: length? value			;-- auto position at the tail
			set [_: _: right':] field/timeline/last-event/for field
			left:  either right' [right' << 3][reduce [0 none {}]]
			right: reduce [field/caret/offset field/selected copy field/text]
			push-to-timeline field left right
		]
	]
	
	;@@ field will need on-change handler support for better user friendliness!
	declare-template 'field/space [
		kit:      ~/kit
		;; own facets:
		weight:   1		#type = :invalidates [number!] (weight >= 0)
		origin:   0		#type = :invalidates-look [linear!] (origin <= 0)	;-- offset(px) of text within the field
		timeline: make timeline! [limit: 50]	 #type [object!]	;-- saved states
		map:      []
		cache:    [size map]

		spaces: object [
			text:       make-space 'text      [color: none]		;-- by exposing it, I simplify styling of field
		] #type [object!]
		
		caret: make-space 'caret caret-template					;-- shared between text and field
			#type (space? caret) #push spaces/text/caret		;-- exposed here but belongs to (drawn by) the text space
		
		;; these mirror spaces/text facets:
		selected: none				#type =? :on-change [pair! none!]	;-- none or pair (offsets of selection start & end)
		margin:   0					#type =  :on-change	;-- default = no margin
		flags:    []				#type    :on-change	;-- [bold italic underline strike] supported ;@@ TODO: check for absence of `wrap`
		text:     spaces/text/text	#type    :on-change
		font:     spaces/text/font	#type =? :on-change
		color:    none				#type =? :on-change	;-- placeholder for user to control
				
		draw: func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
	
]


context [
	~: self
	
	draw: function [slider [object!] canvas: infxinf [point2D! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [
		;; knob
		kdrawn: render knob: slider/knob
		size: max slider/knob/size fill-canvas canvas fill-x no	;-- never extend along Y axis 
		slider/size: constrain size slider/limits
		free: slider/size - knob/size
		koffset: 1.0 * slider/offset . 0.5 * free
		
		;; marks
		mdrawn: clear []
		either slider/marks [
			period: slider/marks * either integer? slider/marks
				[either integer? slider/step [slider/step][slider/step * slider/size/x]]
				[free/x]
			nmarks: 1 + round-down free/x + 1e-6 / period
			ssm: slider/spaces/marks
			mksize: 1 . slider/size/y							;-- default; style may disregard
			while [nmarks > length? ssm] [append ssm make-space 'mark []]
			x: half knob/size/x
			foreach mark ssm [									;@@ use map-each
				repend mdrawn ['translate x . 0 render/on mark mksize yes yes]
				x: x + period
			]
		][
			clear slider/spaces/marks
		]
		
		compose/only [(copy mdrawn) translate (koffset) (kdrawn)]	;-- mostly drawn in style, only positioning is here
	]
	
	;@@ given the name, should be generic, just modified here a bit?
	declare-template 'mark/space [
		cache: none										;-- it should be enough to just invalidate the slider
		draw:  :no-draw									;-- drawn by style
	]
	
	declare-template 'knob/space [
		size:  (12,12)
		cache: none										;-- it should be enough to just invalidate the slider
		draw:  :no-draw									;-- drawn by style
	]
	
	kit: make-kit 'slider [
		frame: object [
			x->offset: function [x [linear!] "Convert X coordinate into slider offset"] [
				ofs: x - (space/knob/size/x / 2) / (space/size/x - space/knob/size/x)
				100% * clip 0 1 round/to ofs space/step
			]
		]
	]
	
	declare-template 'slider/space [
		kit:    ~/kit
		
		;; knob location: 0-100%
		offset: 0%						#type =  [percent! float!] (all [0 <= offset offset <= 1]) :invalidates-look
		;; keyboard-driven knob displacement: integer = pixels, otherwise = percent of the whole
		step:   0.5%					#type == [number!] (step > 0)
		;; visual scale marks period: integer = multiple of step, otherwise = percent of the whole
		marks:  none					#type == [number! (marks > 0) none!]
		
		spaces: object [
			knob:  make-space 'knob []
			marks: []
		]
		knob:   spaces/knob				#type =? [object!] (space? knob) :invalidates
		draw:   func [/on canvas [point2D!] fill-x [logic!] fill-y [logic!]] [~/draw self canvas fill-x fill-y]
	]
]

	
declare-template 'fps-meter/text [
	; cache:     off
	rate:      100
	text:      "FPS: 100.0"		#on-change :invalidates	;-- longest text used for initial sizing of it's host
	init-time: now/precise/utc	#type [date!]
	frames:    make [] 400		#type [block!]
	aggregate: 0:0:3			#type [time!]
]

export exports

;; <<<<<<<<<< %templates.red <<<<<<<<<
				;-- requires clipboard on inclusion
					
;; >>>>>>>>>> %vid.red >>>>>>>>>



;-- requires export

;@@ use percent for weight globally?? but can be misleading as weights are summed
;@@ another idea: tag for hint (makes sense if hint is widely used)

VID: context [
	; create VID styles for basic containers
	; #hide [
		; foreach name [hlist vlist row column] [
			; system/view/VID/styles/:name: spec: copy/deep system/view/VID/styles/host
			; spec/template/space: to lit-word! name
		; ]
	; ]
	
	;; these help avoid repetition:
	props: #[
		spacious [margin: spacing: 10x10]
		tight    [tight [margin: spacing: 0x0]]
		align [											;-- used by box and tube
			left   [align/x: -1]
			right  [align/x:  1]
			center [align/x:  0]
			top    [align/y: -1]
			bottom [align/y:  1]
			middle [align/y:  0]
		]
		text-align [									;-- used by rich-paragraph and co
			left   [align: 'left]
			center [align: 'center]
			right  [align: 'right]
			fill   [align: 'fill]
		]
		font-styles [
			bold      [flags: append flags 'bold]
			italic    [flags: append flags 'italic]
			underline [flags: append flags 'underline]
			strike    [flags: append flags 'strike]
			ellipsize [flags: append flags 'ellipsize]
			; wrap      [flags: append flags 'wrap]		;-- no wrap flag by design, choose text vs paragraph instead 
		]
	]
		
	;; specifications for VID/S styles available in `lay-out-vids`
	styles: make map! reshape [
		scrollable [
			template: scrollable
			facets:   [
				vertical   [content-flow: 'vertical]
				horizontal [content-flow: 'horizontal]
			]
		]
		hlist [
			template: list
			spec:     [@(props/spacious) axis: 'x]
			facets:   [@(props/tight)]					;@@ all these should be maps, but see REP #111
		]
		vlist [
			template: list
			spec:     [@(props/spacious) axis: 'y]
			facets:   [@(props/tight)]
		]
		row [
			template: tube
			spec:     [@(props/spacious) axes: [e s]]
			facets:   [@(props/tight) @(props/align)]
		]
		column [
			template: tube
			spec:     [@(props/spacious) axes: [s e]]
			facets:   [@(props/tight) @(props/align)]
		]
		list-view [										;@@ is there ever a need for horizontal list-view?
			template: list-view
			spec:     [list/spacing: 5x5 list/axis: 'y]
			facets:   [
				tight            [list/spacing: 0x0]			;-- different from #tight prop
				selectable       [behavior/selectable: 'single]
				multi-selectable [behavior/selectable: 'multi]
			]
		]
		label [
			template: label
			spec:     [limits: 80 .. none]
			facets:   [
				image!  image
				char!   image
				string! text
				@(props/font-styles)
			]
		]
		paragraph [template: paragraph facets: [string! text @(props/font-styles)]]
		text   [template: text   facets: [string! text @(props/font-styles)]]
		link   [template: link   facets: [string! text url! text block! command]]
		button [
			template: button
			facets: [string! data image! data block! command @(props/font-styles)]
			spec: [limits: 40 .. none]
		]
		data-clickable [
			template: data-clickable
			facets: [string! data image! data block! command @(props/font-styles)]
		]
		field  [
			template: field
			facets: [string! text @(props/font-styles)]
			;@@ unfortunately without deep reactivity there's no way changes in caret can be recognized in owning field
			;@@ so any reactions placed upon field/caret/stuff will not fire unless I explicitly make caret reactive
			;@@ #4529 could solve this for all spaces
			spec: [
				quietly caret/on-change*: func spec-of :caret/on-change* copy body-of :caret/on-change* 
				insert body-of :caret/on-change*
					with [caret :caret/on-change*] [			;-- newlines are imporant here for mold readability
						system/reactivity/check/only self word
					]
			]
		]
		rich-paragraph [
			template: rich-paragraph
			facets:   [percent! baseline @(props/text-align)]
		]
		rich-content [
			template: rich-content
			facets: [
				percent! baseline
				block! @[func [block] [compose/only/deep [kit/do-batch self [deserialize (block)]]]]	;-- high level source dialect support for VID
				@(props/text-align)
			]
		]
		
		box   [template: box    facets: [@(props/align)]]
		cell  [template: cell   facets: [@(props/align)]]
		timer [
			template: timer
			facets:   [
				integer! rate
				float!   rate
				time!    rate
				block!   @[func [block] [
					compose/deep/only [
						actors: object [
							on-time: function [space path event delay] (block)
						]
					]
				]]
			]
		]
		grid [
			template: grid
			layout:   lay-out-grid						;-- uses custom layout function
			facets:   [pair! bounds @(props/tight)]
		]
		slider [
			template: slider
			facets: [
				percent! offset
				float!   offset
			]
		]
	];; styles
	
	for-each [name spec] styles [spec/facets: make map! spec/facets]	;@@ dumb solution for REP #111
		
	;@@ grid-view, switch (with logic auto-facet)
	
	
	host?: func ["Check if OBJ is a HOST face" obj [object!]]['host = class? obj]
	
	host-on-change: function [host word value] [
		;@@ maybe call a tree invalidation instead?
		if space? :host/space [invalidate host/space]
	]
	
	;; basic event dispatching face
	system/view/VID/styles/host: reshape [
		default-actor: worst-actor-ever					;-- worry not! this is useful
		init: [set 'init-window window-of self init-spaces-tree self]
		template: @[declare-class/manual 'host [
			;; make a chimera of classy-object's and face's on-change so it works as a face and supports class features
			on-change*: function spec-of :classy-object!/on-change*
				with self append copy body-of :classy-object!/on-change* compose/only [
					;; this shields space object from being owned by the host and from cascades of on-deep-change events!
					unless word = 'space (body-of :face!/on-change*)
				]
			classify-object self 'host
			
			
			type:       'base					#type =  [word!]	;-- word will be used to lookup styles and event handlers
			;; no size by default - used by init-spaces-tree as a hint to resize the host itself:
			size:       (0,0)					#type =? [planar! none!]  :host-on-change
			;; makes host background opaque otherwise it loses mouse clicks on most of it's part:
			;; (except for some popups that must be almost transparent)
			color:      svmc/panel				#type =  [tuple! none!] :host-on-change
			space:      none					#type =? [object! (space? space) none!] :host-on-change
			flags:      'all-over				#type =  [block! word! none!]		;-- else 'over' events won't make sense over spaces
			rate:       100						#type =  [integer! time! none!]		;-- for space timers to work
			;; render generation number, used to detect live spaces (0 = never rendered):
			generation: 0.0						#type =  [float!]
			queue:      make hash! 200			#type    [hash! block!]	;-- queued events to process
			modify queue 'owned none					;-- otherwise every appended value triggers a 'redraw and deadlocks GTK
		]]
	]
	
	
	;; used internally in host's `init` only
	init-spaces-tree: function [face [object!] (host? face) /local focused] [
		unless spec: select face/actors 'worst-actor-ever [exit]
		face/actors/worst-actor-ever: none
		
		spec: body-of :spec
		if empty? spec [exit]
		
		default focus/window: window-of face			;-- init focus
		focused: track-focus [pane: lay-out-vids spec]
		if 1 < n: length? pane [ERROR "Host face can only contain a single space, given (n)"]
		face/space: pane/1
		;; this is rather tricky:
		;;  1. we want `render` to render the content on currently set face/size
		;;  2. yet, in `layout` we set face/size from the rendered content size
		;; so, to avoid double rendering we have to re-apply the host style
		;; this is done inside `render-face` if we set size to none
		;; for this reason, `host` template contains `size: 0x0`
		;; which is used as a hint to estimate size automatically
		;; user can then explicitly set host size to nonzero, in which case it's not changed
		if zero? face/size [face/size: none]
		drawn: render face
										;-- should be set by `render-face`, `size: none` blows up `layout`
		#debug draw [prin "host/draw: " probe drawn] 
		face/draw: drawn
		
		;; also the tree does not exist until drawn, so focus-space will fail (and see notes on track-focus)
		;; so I have to put focus here, and this also tells View to focus the host
		if focused [set-focus focused]
	]
	
	;; focus is tricky! lay-out-vids should never change focus, because its result may never be part of the tree
	;; but it has to return the pane, so focused space becomes its extra return
	;; lack of apply is no fun: instead of passing a refinement across all layout functions, it's much easier to use a wrapper
	track-focus: function [
		"Wrapper for layout functions that returns the last space with focus marker (or none)"
		code [block!] "Evaluated"
		/local focused
	][
		do code
		:focused
	]
	update-focus: func [space [object!]] with :track-focus [
		try [focused: space]							;-- may fail when called outside of track-focus scope
	]
	
	wrap-value: function [
		"Create a space to represent given VALUE; return it's name"
		value [any-type!]
		wrap  [logic!] "How to lay text out: as a line (false) or paragraph (true)"
	][ 
		switch/default type?/word :value [
			string! [make-space pick [paragraph text] wrap [text: value]]
			logic!  [make-space 'logic [state: value]]
			image!  [make-space 'image [data:  value]]
			url!    [make-space 'link  [text:  value]]
			block!  [lay-out-data/:wrap value]
		][
			either space? :value [						;-- pass spaces as is - common case for list-view/grid-view
				:value
			][
				make-space 'text [text: mold :value]
			]
		]
	]
	
	
	lay-out-data: function [
		"Create a space layout out of DATA block"
		data [block!] "image, logic, url get special treatment"
		/only "Return only the spaces list, do not create a layout"
		/wrap "How to lay text out: as a line (false) or paragraph (true)"
	][
		result: map-each value data [wrap-value :value wrap]
		unless only [
			result: make-space 'tube [
				margin:  0x0							;-- outer space most likely has it's own margin
				spacing: 10x10
				content: result
			]
		]
		result
	]
	
	
	lay-out-grid: function [
		"Turn Grid specification block into a code block"
		spec [block!] "Same as VID/S, with `at pair!` / `at range!` support"
		/styles sheet [map! none!] "Add custom stylesheet to the global one"
		/local x
	][
		code: make block! 20
		xy:   1x1
		step: 1x0
		
		=at-expr=: [s: e: (set/any 'x do/next s 'e) :e]
		=at=: [
			ahead word! 'at =at-expr=
			(case [
				pair? :x [xy: x]
				all [range? :x  pair? x/min  pair? x/max] [
					repend code ['set-span  xy: x/min  x/max + 1 - xy]
				]
				'else [ERROR "Expected pair or range of pairs after 'at' keyword, got (type? :x) at (mold/part s 100)"]
			])
		]
		=batch=: [
			opt =at=
			s: to [ahead word! ['at | 'return | 'across | 'below] | end] e: (	;-- lay out part between keywords
				spaces: lay-out-vids/styles copy/part s e sheet
				foreach space spaces [
					repend code ['put 'content xy space]
					xy: xy + step
				]
			)
		]
		=return=: [ahead word! 'return (xy: 1 + multiply xy reverse step)]
		=across=: [ahead word! 'across (step: 1x0)]
		=below=:  [ahead word! 'below  (step: 0x1)]
		parse spec [any [=return= | =across= | =below= | =batch=]]
		code
	]
	
	datatype-names: to block! any-type!					;-- used to screen datatypes from flags
			
	lay-out-vids: function [
		"Turn VID/S specification block into a forest of spaces"
		spec [block!] "See VID/S manual on syntax" 
		/styles sheet [map! none!] "Add custom stylesheet to the global one"
		/local w b x lo hi late?
		/extern with									;-- gets collected from `def`
	][
		pane: make block! 8
		sheet: any [sheet make map! 4]					;-- new sheet should not persist after leaving lay-out-vids 
		def: construct [								;-- accumulated single style definition
			styling?:										;-- used when defining a new style in VID
			template: 										;-- should not end in `=` (but not checked)
			with:											;-- used to build space, before all other modifiers applied
			link: 											;-- prefix set-word, will be set to the instantiated space object
			style: 											;-- style spec fetched from VID/styles
			reactions:										;-- bound to space
			actors:											;-- unlike event handlers, affects individual space only
			facets:											;-- facets collected by manual and auto-facet
			pane:											;-- unless snatched by auto-facet, assigns /content
			focused?:										;-- to move focus into this space
			children:										;-- collects set-words of a style
		]
		
		commit-style: [
			
			
			
			;; may assign non-existing facets like hint= or menu=
			facets: map-each [facet value] def/facets [
				either facet [ reduce [to set-word! facet 'system/words/quote :value] ][ value ]
			]
			unless empty? def/actors [
				append facets compose/deep/only [
					actors: apply 'construct [
						to [] def/actors
						/with object? :actors :actors	;-- allows block! facet to define an actor too
					]
				]
			]
			either def/styling? [						;-- new style defined, def/style already copied and in the sheet
				unless def/style/payload [append def/style [payload: []]] 
				def/style/payload: copy/deep/part style-bgn style-end
				; #print "saved payload (mold def/style/payload) in (def/link) style based on (def/style/template)"
			][
				space-spec: compose [
					(only def/style/spec)
					(when def/children (compose [children: (def/children)]))
					(facets)
					(def/with)
				]
			
				space: make-space def/style/template space-spec
				if def/link [set def/link space]		;-- set the word before calling reactions
				
				if def/pane [
					unless in space 'content [
						ERROR "Style (def/template) cannot contain other spaces"
					]
					;; allow usage of custom layout function
					either def/style/layout [
						layout: get def/style/layout
						
						do with space layout/styles  def/pane copy sheet	;-- copy sheet so inner styles don't modify parent's
					][
						content: lay-out-vids/styles def/pane copy sheet	;-- copy sheet so inner styles don't modify parent's
						space/content: case [			;-- always trigger on-change just in case
							any-list? :space/content [content]
							immediate? :space/content [
								if 1 < n: length? content [
									ERROR "Style (def/template) can only contain a single space, given (n)"
								]
								content/1				;-- can be none if no items
							]
							'else [						;-- e.g. content is a map in grid
								ERROR "Style (def/template) requires custom content filling function"
							]
						]
					]
				]
				if def/focused? [update-focus space]	;-- does not trigger actors/events (until fully drawn)
				
				if object? actors: select space 'actors [
					foreach actor values-of actors [
						;; bind to space and commands but don't unbind locals:
						with [space events/commands :actor] body-of :actor
					]
				]
				if actor: :def/actors/on-created [actor space none none]	;@@ need this? or need `on-create`?
				
				;; make reactive all spaces that define reactions or have a name
				;@@ this is a kludge for lacking PR #4529, remove me
				;@@ another option would be to make all VID spaces reactive, but this may be slow in generative layouts
				if any [def/link  not empty? def/reactions] [
					quietly space/on-change*: func spec-of :space/on-change* copy body-of :space/on-change* 
					insert body-of :space/on-change*
						with [space :space/on-change*] [		;-- newlines are imporant here for mold readability
							system/reactivity/check/only self word
						]
				]
				foreach [later reaction] def/reactions [
					reaction: bind copy/deep reaction space		;@@ should bind to commands too?
					react/:later reaction
				]
				; #print "finished instantiation of (def/template) -> (space/type):(space/size)"
				
				append pane space
			]
		];; commit-style: []
		
		reset: [
			set def none
			def/actors:    make map!   4
			def/facets:    make block! 8
			def/reactions: make block! 2
			def/with:      make block! 8
		]
		=vids=:              [any [end | (do reset) =do= | =styling= | =instantiating=]]
		=styling=:           [
			ahead word! 'style (def/styling?: yes)
			ahead #expect set-word! =space-name=
			=style-declaration=
		]
		=instantiating=:     [not end opt =space-name= =style-declaration=]
		=style-declaration=: [=style-name= style-bgn: any =modifier= style-end: (do commit-style)]
		=space-name=:        [set w set-word! (def/link: to word! w)]
		=style-name=:        [
			set w #expect word! p: (
				; #print "found style (w)..."
				def/template: w
				def/style: case [
					x: sheet/:w      [x]
					x: VID/styles/:w [x]
					templates/:w     [compose/only [template: (w)]]
					'else            [ERROR "Unsupported VID/S style: (w)"]
				]
				
				if def/styling? [
					put sheet def/link def/style: copy/deep def/style	;-- from now on, linked word ends the definition and instantiates
				]
				if payload: def/style/payload [					;-- style has literal data to insert
					def/children: make [] 4						;-- collect names of the children
					;; literally insert anonymized copy of the payload
					;; to avoid set-words collision when a style with set-words inside is instantiated multiple times:
					def/children: construct collect-set-words payload
					insert p with def/children copy/deep payload
					; #print "inserted payload at: (mold/part p 80)"
				]
			)
		]
		
		=modifier=:   [
			not [
				end
			|	ahead word! 'style						;-- style is a keyword and can't be faceted
			|	set-word!								;-- set-words are reserved for space names
			|	set w word! if (any [sheet/:w VID/styles/:w templates/:w])	;-- style names mark the end of modifiers
			]; p: (#print "modifier at: (mold/part p 80)")
			[=with= | =reaction= | =action= | =facet= | =flag= | =auto-facet= | =focus= | =color= | =pane= | =size=]
			; p: (#print "modifier finished at: (mold/part p 80)")
		]
		
		=with=:       [ahead word! 'with  set b #expect block! (append def/with b)]	;-- collects multiple `with` blocks
		=do=:         [ahead word! 'do    set b #expect block! (do b)]
		
		=reaction=:   [ahead word! 'react set late? opt [ahead word! 'later] set b #expect block! (
			unless def/styling? [						;-- will be created during instantiation
				repend def/reactions [late? b]
			]
		)]
		
		=action=:     [=actor-name= =actor-body=]
		=actor-name=: [
			set w word!
			if (all [find/match x: form w "on-" #"=" <> last x])	;-- don't take facet for actor, e.g. on-move=
			;@@ should look the name up in system/view/evt-names?
		]
		=actor-body=: [
			set b block! (def/actors/:w: function [space path event] b)
		|	set x [get-word! | get-path!] (
				unless function? get/any x [
					ERROR "(mold x) should refer to a function, not (type? get/any x)"
				]
				def/actors/:w: get/any x
			)
		|	ahead word! 'function p: #expect [2 block!] (def/actors/:w: function p/1 p/2)
		|	#expect "actor body"
		]
		
		=focus=:      [ahead word! 'focus (def/focused?: yes)]
		
		=facet=:      [=facet-name= =facet-expr=]
		=facet-name=: [
			set w word! if (#"=" = last s: form w) (
				take/last s  append def/facets to word! s
			)
		]
		=facet-expr=: [s: e: (append/only def/facets do/next s 'e) :e]
		
		=flag=: [
			set w word!
			if (facet: get-safe 'def/style/facets/:w)	;-- flag defined for this style?
			if (not find datatype-names w)				;-- datatype names do not count
			(repend def/facets [none facet])
		]
			
		=auto-facet=: [
			set x any-type!								;-- try to match by value type
			if (facet: get-safe 'def/style/facets/(type?/word :x))
			(repend def/facets pick [[none facet :x] [facet :x]] function? :facet) 
		]
		
		;; I decided to make a special case because color is in principle applicable to all templates
		;; and adding it into every VID/S style would be tedious, plus raw templates won't support it otherwise
		;@@ should there be two colors (fg/bg)? (this may complicate styles a lot)
		=color=:      [
			[	set x tuple!
			|	set w word! if (tuple? x: get-safe w)	;-- safe or may have lost context
			|	set w issue! if (x: hex-to-rgb w)
			]
			(repend def/facets ['color x])
		]
		
		=pane=:       [set b block! (def/pane: b)]		;-- will only be expanded during instantiation
		
		=size=:       [
			[	ahead [skip ahead word! '.. skip]
				=size-component-2= (lo: x) skip =size-component-2= (hi: x)
			|	=size-component-1= (lo: hi: x)
			]
			(repend def/facets ['limits lo .. hi])
		]
		limit!: make typeset! [linear! planar! none!]
		=size-component-1=: [
			set x limit!
		|	set x [word! | get-word!] if (all [
				not VID/styles/:x						;-- protect from bugs if style name is set globally to a number
				not templates/:x
				find limit! type? set/any 'x get-safe x	;-- safe or may have lost context
				none <> :x								;-- ignore single none or unset values!
			])
		]
		=size-component-2=: [
			set x [limit! | word! | get-word! | paren!] (x: do x)
		]
		
		parse copy spec =vids=							;-- copy so styles can insert into it
		pane
	];; lay-out-vids: function
	
	export [lay-out-vids host?]
]

#hide []

;; <<<<<<<<<< %vid.red <<<<<<<<<

					
;; >>>>>>>>>> %event-scheduler.red >>>>>>>>>


;; requires do-queued-events.red
;; uses events/dispatch and events/copy-event


scheduler: context [
	event-types: extract system/view/evt-names 2

	accepted-events: make hash! [						;-- real (not generated) View events that need processing
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		; focus unfocus 	-- internally generated ;@@ but maybe these will be required too
		time
		#(true)											;-- used to be able to use path notation (faster)
	]
	
	delay-norms: #[										;-- delay norm per event type, used for prioritization
		time     500
		; drawing  300									;-- not reported to the event function
		; moving   200									;-- only concerns windows not hosts
		; move     200									;-- same
		; resizing 200									;-- same
		; resize   200									;-- same
		over     100
		drag     100
		wheel    100
	]
	default-delay: 50
	for-each type event-types [default delay-norms/:type: default-delay]
	
	groupable: make hash! append keys-of delay-norms true		;-- 'true' allows to use path notation which is faster than find

	;; event groups determine which events can or cannot be grouped with each other
	groups: #[
		time     time
		drawing  drawing
	]
	for-each type exclude event-types [time drawing] [groups/:type: 'normal]

	;; similar to system/view/handlers but only for host events
	;; goal is to have predictable event order (e.g. hovering may call new 'over event immediately before 'time)
	;; if function throws a 'drop word, event is skipped
	event-filters: #[]

	finish-times: #[]									;-- timestamp of last event of each type processing finish(!)
	for-each type event-types [finish-times/:type: now/utc/precise]
	
	shared-queue: make [] 200							;-- for dispatching events by host
	insert-event: group-next-event: take-next-event: process-next-event: process-any-event: none
	context [
		igroup: 1 ievent: 2 period: 2
		limit: 50										;-- search distance limit
		
		set 'insert-event function [host [object!] event [map!]] [
			
			insert shared-queue host
			insert host/queue reduce [
				groups/(event/type) event
			] 
		] 
		
		set 'take-next-event function [host [object!]] [
			event: host/queue/:ievent
			quietly host/queue: skip host/queue period
			if 100 < index? host/queue [
				; remove/part host/queue quietly host/queue: head host/queue
				remove/part head host/queue host/queue
				quietly host/queue: head host/queue
			]
			event
		]
	
		set 'process-next-event function [host [object!]] [
			if group-next-event host [exit]
			event: take-next-event host
			#debug events [if event/type <> 'time [#print "about to process (event/type) event for (host/type):(host/size)"]]
			#debug focus  [if event/type = 'focus [#print "about to process (event/type) event for (host/type):(host/size)"]]
			if 'drop <> catch [									;@@ should be fcatch, but it would be slower :/
				foreach [_ filter] event-filters [filter host event]	;-- filters may call out-of-turn events/dispatch themselves
				'ok
			][
				events/dispatch host event
			]
			finish-times/(event/type): now/utc/precise			;-- mark the end of processing of this event type
		]
		
		set 'process-any-event function [/extern shared-queue] [	;-- must return true if processes
			unless host: shared-queue/1 [return no]
			
			shared-queue: next shared-queue
			if 100 < index? shared-queue [
				; remove/part shared-queue shared-queue: head shared-queue	;@@ negative part is bugged
				remove/part head shared-queue shared-queue
				shared-queue: head shared-queue
			]
			process-next-event host
			true
		]

		set 'group-next-event function [host [object!]] [
			unless attempt [window-of host] [					;-- ignore out-of-tree events (host or window has been destroyed?)
				#debug events [#print "ignoring outdated (host/queue/:ievent/type) event for (host/type):(host/size)"]
				take-next-event host
				return true
			]
			;; find grouping candidate
			rest: skip this: host/queue period
			type: this/:ievent/type
			unless all [
				groupable/:type											;-- this event type cannot be grouped
				ahead: find/skip/part rest this/:igroup period limit	;-- no similar event ahead
				type = ahead/:ievent/type								;-- similar event of different type blocks grouping
				this/away? = ahead/:ievent/away?						;-- cannot group different away states
			] [return none]
			
			;; check if grouping would lead us to a more delayed event, otherwise abort
			if period <> offset? this rest [					;-- only if skipping another event
				this-delay: difference t-now: now/utc/precise finish-times/:type
				this-norm:  delay-norms/:type
				next-type:  rest/:ievent/type
				next-delay: difference t-now finish-times/:next-type
				next-norm:  delay-norms/:next-type
				if greater? this-delay / this-norm next-delay / next-norm [return none]	;-- abort if this event is more delayed
			]
			
			;; perform grouping
			if type = 'wheel [									;-- the only event that requires summation
				ahead/:ievent/picked: ahead/:ievent/picked + this/:ievent/picked
			]
			take-next-event host
			#debug events [if type <> 'time [#print "grouped (type) event for (host/type):(host/size)"]]
			true												;-- report success
		]
	
	]

	tracked: #[											;@@ remove this if REP #161 gets implemented
		flags:     []
		offset:    (0,0)								;-- screen offset!
		ctrl?:     #(false)
		shift?:    #(false)
		down?:     #(false)
		mid-down?: #(false)
		alt-down?: #(false)
	]
	auto-tracked: exclude words-of tracked [offset]		;@@ workaround for #5670: /offset reported as none on GTK
	
	track-event: function [
		"Stash event flags internally"
		event [event! map!]
	][
		switch event/type [
			over wheel down up click dbl-click 
			alt-down alt-up mid-down mid-up aux-down aux-up
			key-down key key-up [						;-- pointer & key events correctly carry all the flags
				foreach word auto-tracked [				;-- extend can't be used or will include unwanted fields
					tracked/:word: event/:word 
				]
				if event/offset [						;@@ workaround for #5670: /offset reported as none on GTK
					
					tracked/offset: face-to-screen event/offset event/face
				]
			]
		]
		event
	]
	
	heal-event: function [								;@@ need to gather extensive data on which events needs healing
		"Ensure correct flags & offset in all events"
		event [map!]
	][
		if event/type = 'time [
			extend event tracked						;-- timer carries no own state
			event/offset: screen-to-face event/offset event/face
		]
		event
	]
	
	queue-event: function [host event [map!]] [
		
		#debug events [if event/type <> 'time [#print "-> queueing a (event/type) event for (host/type):(host/size)"]]
		append shared-queue host
		append append host/queue groups/(event/type) event
		if event/away? [work-around-5520]
	]
	
	;@@ because of #5520 the logic here is somewhat complex:
	;@@ there's a situation when over events get swapped as described in 5520: A A B A- B B
	;@@ and there's a situation when the face disappears without away event:   A A A B
	;@@ the goal here is to swap to A- and B when they are both adjacent in the queue (very highly likely case)
	work-around-5520: function ["Bug #5520 workaround"] [
		all [
			2 <= length? shared-queue					;-- queue may not be at its head, so the other checks don't guarantee this
			other-host:  pick between: top shared-queue -1
			other-event: last other-host/queue
			other-event/type = 'over
			not other-event/away?
			swap back between between
		]
	]
	
	list-queue: function ["Get a linearized copy of the current event queue"] [
		queue:  make block! 8
		queues: make hash!  4							;-- needs to modify host/queue offset, so it's cached here
		foreach host shared-queue [
			either entry: find/only/same/skip queues host 2
				[entry/2: entry/2 + 2]
				[repend entry: tail queues [host 2]]
			append queue pick host/queue entry/2
		]
		queue
	]
	
	dump-queue: function [] [
		formed: clear {}
		foreach event queue: list-queue [
			host:     event/face
			host-id: `"(host/type):(host/size)/(select host/space 'type)"`
			event-id: uppercase form event/type
			if event/away? [append event-id "/away"]
			append formed `"(event-id)@(host-id) "`
		]
		#print "event queue (length? queue): (formed)"
	]
	
	;; sometimes this gets window as 'host', likely when no face is in focus
	insert-event-func 'spaces-event-dispatcher func [host event] [
		track-event event								;-- keep tracked info up to date, gathering it from ALL faces
		all [
			host? host									;@@ maybe /content field not /space?
			host/space									;-- /space is assigned?
			accepted-events/(event/type)
			queue-event host heal-event events/copy-event event
		]
		none											;-- the event can be processed by other handlers
	]

	
	
	event-loop-depth: 0									;@@ used to work around #5377
	set 'do-events function spec-of native-do-events: :do-events [
		either no-wait [
			trap/all/catch
				[process-any-event]
				[print thrown]
			native-do-events/no-wait
		][
			;@@ the logic here must be synced with native do-events, but it doesn't look sound 
			;@@ see https://github.com/red/red/commit/c8713b65604ea3d9906be1abdc557bc73bcbf464 comments
			;; 'head' to account for GUI console which enters event loop too:
			if window: last head system/view/screens/1/pane [	;@@ what if windows were reordered?
				
				depth: step 'event-loop-depth
				while [all [window/state depth = event-loop-depth]] [	;-- there's one event loop per window, so leave once it's closed
					switch native-do-events/no-wait [			;-- fetch all pending events ;@@ may deadlock?
						#(true)  [continue]
						#(false) []
						#(none)  [break]
					]
					trap/all/catch
						[unless process-any-event [wait 1e-3]]	;-- wait is also tainted by single do-events/no-wait
						[print thrown]
				]
				self/event-loop-depth: depth - 1
				none											;-- return value must be useful for smth..
			]	
		]
	]
	
	;; View is using some functions with compiled version of 'do-events'
	;; I have to recreate it to switch to the new scheduler
	set 'view func spec-of :view body-of :view
]

;; <<<<<<<<<< %event-scheduler.red <<<<<<<<<
		;-- requires vid (host? func)
					
;; >>>>>>>>>> %events.red >>>>>>>>>



;-- requires auxi.red(?), styles (to fix svmc/), error-macro.red, event-scheduler.red


events: context [
	on-time: none										;-- set by timers.red

	;-- previewers and finalizers are called before/after handlers
	;-- both have the same args format: [space [object!] path [block!] event [map! none!]]
	;-- stop? command indicates that event was "eaten" and becomes true after:
	;-- any previewer or finalizer calls `stop`
	;-- any normal event handler does not call `pass`
	;-- "eaten" events do not propagate further into normal event handlers, but do into all previewers & finalizers
	;-- map format: event/type [word!] -> list of functions
	previewers: #[]
	finalizers: #[]

	;-- we want extensibility so this is a map of maps:
	;-- format: space-name [word!] -> on-event-type [word!] -> list of event functions
	;--         space-name [word!] -> sub-space-name [word!] -> ... (reentrant, supports paths)
	handlers: #[]


	event-prototype: make map! collect [
		foreach word system/catalog/accessors/event! [keep to set-word! word keep none]
	]
	
	copy-event: function [event [event! map!]] [
		result: copy event-prototype
		foreach word system/catalog/accessors/event! [result/:word: :event/:word]
		;@@ can't repro this in isolation, but somehow without copy flags of KB events get empty! need to find out why!
		result/flags: copy event/flags
		result
	]
	
	register-as: function [map [map!] types [block!] handler [function!] /priority /local blk] [
		delist-from map :handler						;-- duplicate protection, in case of multiple includes etc.
		
		inject: either priority [:insert][:append]
		foreach type types [
			
			list: any [map/:type  map/:type: copy []]
			inject list :handler
			bind body-of :handler commands
		]
		:handler
	]

	delist-from: function [map [map!] handler [function!]] [
		foreach [_ list] map [
			remove-each fn list [:handler =? :fn]
		]
	]

	register-previewer: func [
		"Register a previewer in the event chain; remove previous instances"
		types [block!] "List of event/type words that this HANDLER supports"
		handler [function!] "func [space path event]"
		/priority "Insert at the start of the event previewers chain"
	][
		register-as/:priority previewers types :handler
	]

	register-finalizer: func [
		"Register a finalizer in the event chain; remove previous instances"
		types [block!] "List of event/type words that this HANDLER supports"
		handler [function!] "func [space path event]"
		/priority "Insert at the start of the event finalizers chain"
	][
		register-as/:priority finalizers types :handler
	]

	delist-previewer: func [
		"Unregister a previewer from the event chain"
		handler [function!] "Previously registered"
	][
		delist-from previewers :handler
	]

	delist-finalizer: func [
		"Unregister a finalizer from the event chain"
		handler [function!] "Previously registered"
	][
		delist-from finalizers :handler
	]

	export [register-previewer register-finalizer delist-previewer delist-finalizer]


	do-previewers: func [path [block!] event [map!] args [block!]] [
		do-global previewers path event args
	]

	do-finalizers: func [path [block!] event [map!] args [block!]] [
		do-global finalizers path event args
	]

	do-global: function [map [map!] path [block!] event [map!] args [block!]] [
		unless list: map/(event/type) [exit]
		space: path/1									;-- space can be none if event falls into space-less area of the host
		;@@ none isn't super elegant here, for 4-arg handlers when delay is unavailable
		code: compose/into [handler space pcopy event (args) none] clear []
		foreach handler list [
			pcopy: clone/flat path						;-- copy in case user modifies/reduces it, preserve index
			trap/all/catch code [
				msg: form/part thrown 1000				;@@ should be formed immediately - see #4538
				kind: either map =? previewers ["previewer"]["finalizer"]
				#print "*** Failed to evaluate event (kind) (mold/part/flat :handler 100)!^/(msg)"
			]
		]
	]

	; copy-handlers: function [
	; 	"Make wrappers for event handlers from STYLE"
	; 	style [word! path! block!] "Style name"		;-- requires style name so we can build paths
	; ][
	; 	r: copy #()
	; 	style: to [] style
	; 	spec: get as path! compose [handlers (style)]
	; 	unless spec [return r]
	; 	foreach [hname hfunc] spec [
	; 		either map? m: :hfunc [
	; 			r/:hname: copy-handlers compose [(style) (hname)]
	; 		][
	; 			spec: copy spec-of :hfunc
	; 			clear find spec refinement!
	; 			r/:hname: func spec compose [
	; 				(as path! compose [handlers (style) (to word! hname)]) (spec)
	; 			]
	; 		]
	; 	]
	; 	r
	; ]

	;-- it's own DSL:
	;-- new-style: [                              
	;--   OR                                      
	;-- new-style: extends 'other-style [         
	;--     on-down [space path event] [...]      
	;--     on-time [space path event delay] [...]
	;--     inner-style: [                        
	;--         ...                               
	;--     ]                                     
	;-- ]                                         
	define-handlers: function [
		"Define event handlers for any number of spaces"
		def [block!] "[name: [on-event [space path event] [...]] ...]"
		/local blk name spec body path late
	][
		prefix: copy [handlers]

		=style-def=: [
			set name set-word! (name: to word! name)
			['extends
				set base #expect [lit-word! | word! | lit-path! | path!] (
					if lit-word? base [base: to word! base]
					;; I'm not inserting whole prefix as then it would need a workaround to remove smth from it
					base: as path! compose [handlers (to [] base)]
				)
			|	(base: none)
			]
			set body #expect block!
			(add-style/from name body base)
		]
		add-style: function [name body /from base [none! path!]] [
			append prefix name
			#debug events [print ["Defining" mold as path! prefix when base ("from") when base (base)]]
			path: as path! prefix
			
			map: either base [copy-deep-map get base][copy #[]]
			set path map
			fill-body body map
			take/last prefix
		]

		fill-body: function [body map] [
			parse body =style-body=
		]
		=style-body=: [
			any [
				not end
				ahead #expect [word! | set-word!]
				=style-def= | =hndlr-def=
			]
		]

		=hndlr-def=: [
			set late opt [ahead 'late word!] 
			set name word!
			set spec [ahead #expect block! into =spec-def=]
			set body #expect block!
			(add-handler name spec body late)
		]
		add-handler: function [name spec body late] [
			#debug events [print ["-" name]]
			path: as path! compose [(prefix) (name)]
			list: any [get path  set path copy []]
			handler: function spec bind body commands
			insert either late [tail list][list] :handler		;-- latest must come first so it can block handlers of its prototype
		]

		=spec-def=: [									;-- just validation, to protect from errors
			#expect word! opt [ahead block! #expect quote [object!]]	;-- space [object!]
			#expect word! opt [ahead block! #expect quote [block!]]		;-- path [block!]
			#expect word! opt [ahead block! #expect quote [map!]]
			opt [if (name = 'on-time) not [refinement! | end]
				#expect word! opt [ahead block! #expect quote [percent!]]
			]
			opt [not end #expect /local to end]
		]

		ok?: parse def [any [not end ahead #expect set-word! =style-def=]]	;-- no handlers in the topmost block allowed
		
	]

	export [define-handlers]
	; export [copy-handlers define-handlers extend-handlers]



	;; stack-like wrappers for `commands` usage
	;; have to be separate because `stop?` is valid until all finalizers are done (e.g. in simulated events)
	with-stop: function [code [block!]] [
		stop?: block?: no								;-- force logic type
		do code
	]

	;-- has to be set later so we can refer to 'events' to get the drag functions
	commands: none

	;; fundamentally there are 3 types of events here:
	;; - events tied to a coordinate (mouse, touch) - then hittest is used to obtain path
	;; - events tied to focus (keyboard, focus changes) - these use focus/current path in the tree
	;; - events without both (timer) - but timer has path too, and also delay
	;; coordinate events' path includes pairs of coordinates (hittest format)
	;; other events' path does not (tree node format)
	;; focus/unfocus events have not 'event' arg!
	;@@ any way to unify these 2 formats?
	dispatch: function [face [object!] event [map!] /local result /extern resolution last-on-time] [
		focused?: no
		with-stop [
			#debug events [if event/type <> 'time [#print "<- dispatching (event/type) event from (face/type):(face/size)"]]
			; #debug events [print ["dispatching" event/type "event from" face/type]]
			path: switch/default event/type [
				over wheel up mid-up alt-up aux-up
				down mid-down alt-down aux-down click dbl-click [	;-- `click` is simulated by single-click.red
					;@@ should spaces all be `all-over`? or dupe View 'all-over flag into each space?
					target: either dragging? [head drag-path][face/space]
					hittest target event/offset
				]
				key key-down key-up enter [
					if all [
						event/type = 'key						;-- workaround for AltGr producing printable keys
						char? event/key
						parse event/flags ['control opt 'shift 'alt]	;-- this seems always sorted
					][
						event/flags: exclude event/flags [control alt]
						event/ctrl?: no
					]
					focused?: yes								;-- event should not be detected by parent spaces
					if face/space [
						if event/window/state [focus/window: event/window]	;-- init /window on 1st event, or if another window got activated
						;; if nothing is focused (but apparently the host has focus), try to focus first focusable
						unless focus/current [
							if target: focus/find-next-focal-*ace 'forth [focus-space target]
						]
						;; but it still may fail if nothing is focusable
						unless focused: focus/current [exit]
						if path: get-host-path focused [
							
							as [] path
						] 
					]
				]
				; focus unfocus ;-- generated internally by focus.red
				time [
					on-time face event							;-- handled by timers.red
					
					;@@ is this check safe enough, or should invalidate set dirty flag for the host?
					if dirty?: empty? face/space/cached [		;-- only timer updates the view because of #4881
						#debug profile [prof/manual/start 'host]
						drawn: render face
						#debug profile [prof/manual/end   'host]
						#debug profile [prof/manual/start 'drawing]
						face/draw: drawn						;@@ #5130 is the killer of animations (really fixed?)
						; unless system/view/auto-sync? [show face]	;@@ or let the user do this manually?
						#debug profile [prof/manual/end   'drawing]
					]
					exit										;-- timer does not need further processing
				]
				;@@ TODO: `enter` should be simulated because base face does not support it
				;@@ menu -- make context menus??
				;@@ select change  -- make these?
				; drag-start drag drop move moving resize resizing close  -- no need
				; zoom pan rotate two-tap press-tap   -- android-only?
				; create created  -- simulate these? (they're still undocumented mostly in View)
			] [exit]											;-- ignore unsupported events
			#debug events [#print "dispatch path: (mold path)"]
			if path [
											;-- for event handler's convenience, e.g. `set [..] path`
				;-- empty when hovering out of the host or over empty area of it
				;-- actually also empty when clicking outside of other spaces, so disabled
				; #assert [any [not empty? path  event/type = 'over]]
				process-event path event [] focused?
			]
		]
	]

	;-- used for better stack trace, so we know error happens not in dispatch but in one of the event funcs
	do-handler: function [spc-name [path!] handler [function!] path [block!] event [map!] args [block!]] [
		space: first path: clone/flat path				;-- copy in case user modifies/reduces it, preserve index
		code: compose/into [handler space path event (args) none] clear []
		trap/all/catch code [
			msg: form/part thrown 400					;@@ should be formed immediately - see #4538
			#print "*** Failed to evaluate (spc-name)!^/(msg)"
		]
	]

	;; this needs reentrancy (events may generate other events), so all blocks must not be static
	;; e.g.: up event closes the menu face, over event slips in and changes template
	do-handlers: function [
		"Evaluate normal event handlers applicable to PATH"
		path [block!] event [map!] args [block!] focused? [logic!]
		/local word _
	][
		if commands/stop? [exit]
		hnd-name: select system/view/evt-names event/type		;-- prepend "on-"
		
		
		spec:  pick [ word [word _] ] object? second path		;-- remove coordinates
		unit:  pick [1 2] object? second path
		wpath: clear copy path									;-- word-only path needed to locate handler
		foreach (spec) path [append wpath word/type]			;@@ use `map-each` - manual fill is slow
		
		
		len: length? wpath
		template: change make path! len + 3 [_ _]				;-- at index=3 (tiny optimization)
		
		i2: either focused? [len][1]							;-- keyboard events should only go into the focused space
		while [i2 <= len] [										;-- walk from the outermost spaces to the innermost
			;; last space is usually the one handler is intereted in, not `screen`
			;; (but can be empty e.g. on over/away? event, then space = none as it hovers outside the host)
			target: skip path i2 - 1 * unit						;-- position path at the space that receives event
			do-previewers target event args
			
			unless commands/stop? [
				hpath: append append/part						;-- construct full path to the handler
					clear template 
					wpath  skip wpath i2						;-- slice [1,i2] of wpath
					hnd-name
				repeat i1 i2 [									;-- walk from the longest (specific) path to the shortest (generic)
					change hpath: next hpath 'handlers
					unless block? list: get-safe hpath [continue]
					commands/stop								;-- stop after current stack unless `pass` gets called
					foreach handler list [						;-- whole list is called regardless of stop flag change
						
						do-handler hpath :handler target event args	;@@ should handler index in the list be reported on error?
						if commands/blocked? [break]
					]
				]
			]
			
			do-finalizers target event args
			i2: i2 + 1
		]
	]

	process-event: function [
		"Process the EVENT calling all respective event handlers"
		path  [block!] "Path on the space tree to lookup handlers in"
		event [map!]   "View event or simulated"
		args  [block!] "Extra arguments to the event handler"
		focused? [logic!] "Skip parents and go right into the innermost space"
	][
		#debug profile [prof/manual/start 'process-event]
		unless commands/stop? [do-handlers path event args focused?]
		#debug profile [prof/manual/end 'process-event]
	]


	;-- pointer can only be captured by single space at a time, so this info is shared:
	drag-in: object [
		head: path: []									;-- `head` alias is needed to avoid a LOT of `head path` calls
		payload: none
	]
	

	dragging?: function [
		"True if in dragging mode"
		/from space [object!] "Only if SPACE started it"
	][
		case [
			empty? drag-in/head [no]
			not from [yes]
			space? source: drag-in/path/1 [space =? source]
		]
	]
	
	stop-drag: function [
		"Stop dragging; return truthy if stopped, none otherwise"
	][
		if dragging? [
			drag-in/payload: none						;-- let GC release it
			clear drag-in/head
		]
	]
	
	start-drag: function [
		"Start dragging marking the initial state by PATH"
		path [path! block!]
		/with param [any-type!] "Attach any data to the dragging state"
	][
		#debug events [if dragging? [#print "WARNING: Dragging override detected: (mold drag-path)->(mold path)"]]
		#debug events [#print "Starting drag on [(mold copy/part path -99) | (mold path)] with (:param)"]
		if dragging? [stop-drag]						;@@ not yet sure about this, but otherwise too much complexity
		
		drag-in/head: head drag-in/path: clone/flat path		;-- drag-path will return it at the same index
		set/any in drag-in 'payload :param
	]

	drag-path: func ["Return path that started dragging (or none)"] [
		if dragging? [:drag-in/path]					;@@ copy or not?
	]
	
	drag-parameter: func ["Fetch the user data attached to the dragging state"] [
		:drag-in/payload
	]
	
	drag-offset: function [
		"Get current dragging offset (or none if not dragging)"
		path [path! block!] "index of PATH controls the space to which offset will be relative to"
	][
		unless dragging? [return none]
		path': at drag-in/head index? path
		set [spc': ofs':] path'
		set [spc:  ofs: ] path
		
		ofs - ofs'
	]

	;@@ export dragging functions or not? (they're available to event handlers anyway)

]

;-- toolkit available to every event handler/previewer/finalizer
;-- designed following REP#80 - commands, not return values
events/commands: context with events [
	;-- flag is local to each handler's call, so we have to use a hack here
	;@@ question here is what is the default behavior: pass the event further or not?
	;@@ let's try with 'stop' by default
	stop:     func [/now] with :with-stop [stop?: yes block?: now]	;-- used by previewers/finalizers, also to block handler stack
	stop?:    does with :with-stop [stop?]
	blocked?: does with :with-stop [block?]
	pass:     does with :with-stop [stop?: block?: no]			;-- stop is ignored for timer events

	;-- the rest does not require a stack but should be available too
	dragging?:      :events/dragging?
	stop-drag:      :events/stop-drag
	start-drag:     :events/start-drag
	drag-path:      :events/drag-path
	drag-parameter: :events/drag-parameter
	drag-offset:    :events/drag-offset
]


;; <<<<<<<<<< %events.red <<<<<<<<<
				;-- requires auxi, event-scheduler, layouts, styles
					
;; >>>>>>>>>> %timers.red >>>>>>>>>


;; requires events.red (extends them on load), uses traversal.red & rendering.red (get-host-path)


timers: context [
	;; to lighten the timer-inflicted CPU load (from 100% really), a registry of /rate-enabled spaces has to be kept
	;; it is achieved by injecting /rate-tracking code into space/on-change
	rated-spaces: make hash! 32

	prime: function [space [object!]] [
		unless find/same rated-spaces space [
			append rated-spaces space
			#debug timer [
				code: mold/part body-of :space/actors/on-time 60
				#print "primed timer for (space/type):(space/size) code: (code), total active (length? rated-spaces)"
			]
		]
	]
	
	;@@ find a way someday to make timers an optional module
	; modify-class 'space-object! [
		; #type =? [none! linear! time!] :on-rate-change
		; (any [none? rate zero? rate positive? rate])
		; rate: none
	; ]	
	
	;-- static map of previous call times of each timer, but `map!` cannot hold objects as keys so using hash!
	marks: make hash! []
	timer-resolution: 0:0								;-- measured automatically
	timer-host: none									;-- a single host face that is used for resolution estimation

	events/on-time: function [face [object!] event [map!]] [	;-- events reserve this slot
		#debug profile [prof/manual/start 'timers]
		either face =? timer-host [update-resolution][update-timer-host face]
		process-timers face event
		#debug profile [prof/manual/end 'timers]
	]

	;; automatically chooses the host with maximum rate
	update-timer-host: function [face [object!] (all [face/rate  not face =? timer-host])] [
		unless number? rate: face/rate [rate: 0:0:1 / rate]
		if all [
			timer-host
			timer-host/state
			rate-old: timer-host/rate
		][
			unless number? rate-old [rate-old: 0:0:1 / rate-old]
			if rate <= rate-old [exit]
		]
		#debug timer [print ["switching timer host to" mold/flat/part face 100]]
		set 'timer-host face
		update-resolution
	]

	;-- resolution estimation with period = O(100) timer events
	last-mark: 1900/1/1
	update-resolution: function [/extern timer-resolution last-mark time] [
		if 0:0:1 > elapsed: difference time: now/utc/precise last-mark [	;-- discard glitches like PC went to sleep etc.
			timer-resolution: timer-resolution * 0.999 + (0.001 * elapsed)
		]
		last-mark: time
	]
	
	time: none											;-- cached to all `now` less often

	process-timers: function [face [object!] event [map!] /extern time] [
		;; timer has no target (as is the case with focused space or pointed at)
		;; and scanning of the whole tree for `rate` facets, all the time, is out of question - or this code will take 99% CPU time
		;; to win performance I maintain a list of all 'armed' timers at the cost of having to explicitly render each timer
		handlers: events/handlers
		hpath: as path! []
		foreach space rated-spaces [
			unless all [
				rate: select space 'rate				;-- previously enabled timer has been disabled? don't react on it again
				path: get-host-path space				;-- space is orphaned (no longer connected to the tree)? remove it so GC can take it
			][
				#debug timer [#print "disabling timer for (mold space)"]
				fast-remove find/same rated-spaces space 1		;-- won't be active until it gets rendered again
				continue
			]
			#debug timer [#print "timer rate (rate) has path (mold path)"]
			if number? rate [rate: 0:0:1 / rate]
			pos: find/same/tail marks space
			set [prev: bias:] any [pos [0:0 0:0]]
			delay: either pos [difference time prev + rate][0:0]		;-- estimate elapsed delay for this timer
			if delay < negate timer-resolution / 2 + bias [continue]	;-- too early to call it?
			
			args: reduce/into [to 1% delay / rate] clear []
			wpath: copy path: new-line/all as [] path no				;@@ need new-line here?
			forall wpath [wpath/1: wpath/1/type]						;@@ use map-each
			;; even if no time handler, actors or previewers/finalizers may be defined
			events/do-previewers top path event args
			forall wpath [
				compose/into [handlers (wpath) on-time] clear hpath		;-- not allocated
				unless block? try [list: get hpath] [continue]			;-- no time handler ;@@ REP #113
				foreach handler list [									;-- call the on-time stack
					
					events/do-handler next hpath :handler top path event args 
				]
			]
			events/do-finalizers top path event args
			
			unless pos [pos: tail append marks space]
			delay: min delay rate * 5					;-- avoid frame spikes after a lag or sleep
			change change pos time bias + delay			;-- mark last timer call time for this space
			;@@ TODO: cap bias at some maximum, for 50+ fps cases, so it won't run away
			
			time: now/utc/precise						;-- update time after handlers evaluation
		]
	]

]

;; <<<<<<<<<< %timers.red <<<<<<<<<
				;-- must come after events (to set events/on-time), but before templates
					
;; >>>>>>>>>> %popups.red >>>>>>>>>



;; requires events, templates, vid, reshape

;@@ menu command should be able to access the space that opened the menu! - bind it!

declare-template 'hint/box [
	margin: 20x10
	origin: (0,0)	#type =? [point2D! none!]			;-- `none` disables the arrow display (when it's not precise)
]

;@@ should it be here or in vid.red?
lay-out-menu: function [
	spec [block!]
	; /title heading [string!]
	/local code name space value tube list flags radial? round?
][
	;@@ preferably VID/S should be used here and in hints above
	row*:        clear []								;-- space names of a single row
	menu*:       clear []								;-- row names list
	
	=menu=:      [opt =flags= collect into row* [any =menu-item=] #expect end]
	=flags=:     [ahead block! into [any =flag=]]
	=flag=:      [set radial? 'radial | set round? 'round]
	=menu-item=: [not end =content= (do new-item) ahead #expect [paren! | block!] [=code= | =submenu=]]
	=content=:   [ahead #expect [word! | object! | string! | char! | image! | logic!] some [=data= | =name= | =space=]]
	=data=:      [set value [string! | char! | image! | logic!] keep (VID/wrap-value value no)]
	=name=:      [set name word! () keep (make-space name [])]
	=space=:     [set space object! () keep (space)]
	; =submenu=:   [ahead block! into =menu=]	;@@ not yet supported
	=code=:      [set code paren! (item/command: code)]
	
	new-item: [
		append menu* item: make-space 'clickable [
			type:    either all [radial? round?] ['round-clickable]['clickable]	;@@ better name??
			margin:  4x4
			color:   none								;-- used for on-hover highlighting
			content: make-space 'tube [spacing: 10x5]
		]
		if radial? [item/limits: 40x40 .. none]			;-- ensures item is big enough to tap at
		;; stretch first text item by default (to align rows), but only if there's another item and no explicit <->
		any [
			not pos: locate row* [.. /type = 'text]		;-- only auto-insert separator after text
			single? pos									;-- don't insert separator at tail
			locate row* [.. /type = 'stretch]			;-- or if already got a separator
			insert next pos make-space '<-> []
		]
		tube: item/content
		tube/content: flush head row*
	]
	parse spec =menu=
	
	list: either radial? [
		make-space 'ring []
	][	make-space 'list [axis: 'y margin: 4x4]
	]
	list/content: flush menu*
	; either title [
		; h-box: make-space 'box [content: make-space 'text [text: heading flags: [bold]]]
		; inner: make-space 'list [axis: 'y margin: 0x4 spacing: 0x0]
		; inner/content: reduce [h-box list]
	; ][
		inner: list
	; ]
	menu: make-space 'cell [type: 'menu  content: inner]
	menu
]

popups: context [
	stack: make hash! 4									;-- currently visible popup faces - single stack for all windows
	
	hint-delay: 0:0:0.5									;-- for hints to appear
	; menu-delay: 0:0:0.5									;-- for submenus to appear on hover

	save: function [
		level  [integer!] ">= 1" (level >= 1)
		face   [object!] "Popup face"
	][
		change enlarge stack level - 1 none face
	]

	hide: function [
		"Hides popups from given level or popup face"
		level [integer! (level >= 1) object! (face? level)] ">= 1 or face"
	][
		old: either integer? level [at stack level][find/same stack level]
		if empty? old [exit]
		#debug popups [#print "hiding popups from (mold/only reduce [level])"]
		shown: sift old [face .. /state /parent]
		foreach face shown [
			window: window-of face
			remove find/same window/pane face
		]
		clear old
		focus/restore									;-- if popup was focused, need to refocus
	]

	show: function [
		"Show a popup at given offset, hiding the previous one(s)"
		space  [object!] "Space or face object to show" (any [space? space is-face? space])
		offset [planar!] "Offset on the window"
		/in window: focus/window [object! none!] "Specify parent window (defaults to focus/window)"
		/owner parent [object! none!] "Space or face object; owner is not hidden"
		/fit "Adjust popup offset for best display if it doesn't fit as is"
	][
		#debug popups [#print "about to show popup (space/type):(space/size) at (offset)"] 
		if space? face: space [							;-- automatically create a host face for it
			face: make-face 'host
			face/space: space
		]
		face/offset: offset
		if host? face [
			if zero? face/size [face/size: none]		;-- hint for render to set its size
			face/draw: render face
		]
		if fit [face/offset: clip 0x0 offset window/size - face/size]
		
		level: 1
		if parent [
			if space? parent [parent: host-of space]
			
			level: 1 + index? find/same stack parent
			window: window-of parent
		]
		
		hide level
		primed/text: primed/host: none					;-- without this some event asynchrony may trigger hint redisplay and popup hide
		save level face
		unless find/same window/pane face [append window/pane face]
		face											;-- return the popup face
	]

	get-hint: function [
		"Get shown hint host; none if not shown"
	][
		all [
			host: last stack							;-- hint can only be the top level
			host? host
			host/space
			host/space/type = 'hint						;@@ REP 113
			host
		]
	]
	
	get-hint-text: function [
		"Get text of the shown hint; none if not shown"
	][
		all [
			host: get-hint
			host/parent									;-- must be visible
			host/space/content/text
		]
	]

	show-hint: function [
		"Show a hint around pointer in window"
		text    [string!] "Text for the hint"
		pointer [planar!]
		/in window [object!] "Specify parent window (defaults to focus/window)"
	][
		if text =? get-hint-text [exit]					;-- don't redisplay an already shown hint; sameness test makes sense in e.g. grid-ui
		#debug popups [#print "about to show hint (mold text) at (pointer)"] 
		
		center: window/size / 2
		above?: center/y < pointer/y					;-- placed in the direction away from the closest top/bottom edge
		
		host: make-face 'host
		host/rate: none									;-- unlike menus, hints should not add timer pressure
		;; hint is transparent so it can have an arrow
		host/color: svmc/panel + 0.0.0.254
		render host/space: hint: first lay-out-vids [	;-- render sets hint/size
			hint [text text= text] origin= either above? [(0,1)][(0,0)]	;-- corner where will the arrow be (cannot be absolute - no size yet)
		]
		
		offset: pointer + either above? [2 . (-2 - hint/size/y)][2x2]	;@@ should these offsets be configurable or can I infer them somehow?
		limit: window/size - hint/size
		fixed: clip offset 0x0 limit					;-- adjust offset so it's not clipped
		if fixed <> offset [
			offset: fixed
			hint/origin: none							;-- disable arrow in this case
			invalidate hint
		]
		show/in host offset window
	]
	
	hide-hint: function ["Hide hint if it is displayed"] [
		if host: get-hint [hide host]
	]
	
	show-menu: function [
		"Show a popup menu at given offset"
		menu    [block!] "Written using Menu DSL"
		offset  [planar!]
		/owner parent  [object!] "Space or face object; owner is not hidden"
		/in    window  [object!] "Specify parent window (defaults to focus/window)"
		; /title heading [string!] "Provide a heading string for the menu" 
		;@@ maybe also a flag to make it appear above the offset?
	][
		host: make-face/spec 'host [rate 25]			;-- reduced timer pressure
		; render host/space: lay-out-menu/:title menu heading
		render host/space: lay-out-menu menu
		either radial?: has-flag? :menu/1 'radial [		;-- radial menu is centered
			offset: offset + host/space/content/origin
			host/color: svmc/panel + 0.0.0.254			;-- radial menu is transparent but should catch clicks that close it
		][
			fit: on										;-- adjust offset so it's not clipped
		]
		show/owner/in/:fit host offset parent window
	]

	primed: context [									;-- pending hint data
		host:      none									;-- host for which hint was primed
		text:      none
		show-time: now/utc/precise						;-- when to show next hint
		anchor:    (0,0)								;-- pointer offset of the over event (timer doesn't have this info)
	]

	;; event funcs internal data
	context [
		;; global space timers are not called unless event is processed, so timer needs a dedicated event function
		insert-event-func 'spaces-hint-popup auto-show-hint: function [host event] [	;-- displays hints across all host faces when time hits
			all [
				event/type = 'time
				host? host								;-- a host face?
				space? host/space						;-- has a space assigned?
				primed/host =? host						;-- hint was primed for this particular host?
				primed/text								;-- hint is available at current pointer offset
				now/utc/precise >= primed/show-time		;-- time to show it has come
				show-hint/in primed/text primed/anchor event/window
				none   									;-- the event can be processed by other handlers
			]
		]
		
		;; searches the path for a defined facet (lowest/innermost one wins)
		find-facet: function [path [block!] name [word!] types [datatype! typeset!]] [
			type-check: pick [ [types =? type? value] [find types type? value] ] datatype? types
			path: reverse append clear [] path			;-- search order from the innermost
			foreach [_ space] path [					;@@ use for-each/reverse when fast, or locate/back
				value: select space name
				if do type-check [return :value]
			]
			none
		]	
		
		travel: func [event [map!]] [					;-- distance from hint show point to current point
			distance? primed/anchor face-to-window event/offset event/face
		]
		maybe-hide-hint: function [event [map!]] [
			if any [
				event/away?								;-- moved off the hint; away event should never be missed as it won't repeat!
				10 <= travel event						;-- distinguish pointer move from sensor jitter
			][
				hide-hint
			]
			primed/text: primed/host: none				;-- abort primed hint (if any)
		]
		
		
		;; over event should be tied to spaces and is guaranteed to fire even if no space below
		register-previewer [over] function [
			space [object! none!] path [block!] event [map!]
		][
			; #assert [event/window/type = 'window]
			unless head? path [exit]					;-- don't react on multiple events on the same path
			
			either popup: find/same stack face: event/face [	;-- hovering over a popup face
				;@@ or should I allow popup menus to show hints too?
			    either hint: all [face/space face/space/type = 'hint] [	;-- over a hint
					maybe-hide-hint event
				][
					hide either event/away? [popup/1][1 + index? popup]	;-- hide upper levels or the one pointer just left
				]
			][													;-- hovering over a normal host
				either all [
					space										;-- not on empty area
					not event/away?								;-- still within the host
					text: find-facet path 'hint string!			;-- hint is enabled for this space or one of its parents
				][
					;; prime new hint display after a delay
					primed/host:   event/face
					primed/text:   text
					primed/anchor: face-to-window event/offset event/face
					unless get-hint-text [						;-- delay only if no other hint is visible, else immediate
						primed/show-time: now/utc/precise + hint-delay
					]
				][												;-- hint-less space or no space below or out of the host
					maybe-hide-hint event
				]
			]
		]
	
		;; context menu display support
		register-finalizer [alt-up] function [					;-- finalizer so other spaces can eat the event
			space [object! none!] path [block!] event [map!]
		][
			;@@ maybe don't trigger if pointer travelled from alt-down until alt-up? 
			if all [
				head? path										;-- don't react on multiple events on the same path
				menu: find-facet path 'menu block!
			][
				;; has to be under the pointer, so it won't miss /away? event closing the menu
				offset: (-1,-1) + face-to-window event/offset event/face
				hide-hint
				show-menu/in menu offset event/window
			]
		]
	
	]
]




;; <<<<<<<<<< %popups.red <<<<<<<<<

					
;; >>>>>>>>>> %traversal.red >>>>>>>>>


;; requires export, tree-hopping, provides pane-of for tabbing

list-*aces:   none										;-- reserve names in the spaces/ctx context
foreach-*ace: none
exports: [list-*aces foreach-*ace]						;-- make them globally available too

traversal: context [
	depth-limit: 100									;-- used to prevent stack from overflowing in recursive layouts
	
	pane-of: function [*ace [object!]] [
		case [
			not is-face? *ace [select *ace 'map]
			host? *ace        [reduce [*ace/space]]
			'other-face       [*ace/pane]
		]
	]

	walker: make batched-walker! [
		branch: function [*ace [object!] /from depth [integer!]] [
			pane: pane-of *ace
			if empty? pane [exit]
			depth: 1 + any [depth -1]
			clear batch
			foreach child pane [						;@@ use for-each
				unless object? :child [continue]
				repend/only batch ['visit *ace child]
				if depth < depth-limit [
					repend/only batch ['branch/from child depth]
				]
			]
			insert next plan batch
		]
	]
	
	set 'list-*aces function [
		"Deeply list faces & spaces from ROOT face or space"
		root [object!] (any [is-face? root space? root])
		/into target: (make [] 100) [block!] "Existing content is overwritten"
	][
		append target root
		foreach-node root walker [append target key]
		new-line/all target on
	]

	set 'foreach-*ace function [
		"Evaluate CODE for each face & space from ROOT face or space"
		'word [word! set-word!] "Word to receive face or space"
		root  [object!] (any [is-face? root space? root])
		code  [block!]
	][
		foreach-node root walker [set word key do code]
	]
]

export exports


;; <<<<<<<<<< %traversal.red <<<<<<<<<

					
;; >>>>>>>>>> %focus.red >>>>>>>>>



;; provides focusing by clicking
;; requires: export and window-of, tabbing context from common


exports: [focused? focus-space set-focus]

;@@ `focus` itself should be somewhere else, as it is used by dispatch and who knows what
focus: make classy-object! declare-class 'focus-context [
	;; template names that can receive focus (affects tabbing & clicking)
	;; class should not matter, name should - then we'll be able to override/extend classes
	;@@ TODO: should paths be allowed here? e.g. if some spaces are only focusable in some bigger context?
	;@@ rework this for compatibility with latest View tabbing model
	focusable: make hash! [scrollable button field area list-view grid-view slider]	#type [hash!]
	focusable-faces: make hash! [field area button toggle check radio slider text-list drop-list drop-down calendar tab-panel]
	
	;; each window has own focus history, format: [window [space ...] ...]
	histories: make hash! 8			#type    [hash!]
	window:    none					#type =? [none! object!]	;-- set by first history access and by global event hook

	;; currently focused space in currently focused window!
	;@@ it's currently not possible to tell what is focused becase Red doesn't tell us which window is active - #3808
	;@@ so this is not very reliable right now and requires a lot of kludges...
	;@@ TODO: /current should be able to return window object (after unfocus - to avoid duplicate unfocus), while /history should not contain it
	current: does [last history]	#type    [function!]		;-- returns space, face, or none
	
	;; the point of /history is to recover focus when last focused space gets hidden/removed from frame/whole window disappears, and Tab is hit
	;; it can be called without a window though, on the first set-focus event, and that should return an empty list
	;@@ TODO: to support per-tab, per-page focus history they may have their own histories, or maybe /focus should handle scope too?
	history: has [w h hist] [									;-- previously focused spaces, including current one
		unless window [
			self/window: last head system/view/screens/1/pane
			unless window [return copy []]						;-- no window = no history ;@@ it's a kludge
		]
		; #assert [window/state]
		unless hist: select/same histories window [
			unless window [ERROR "focus/window must be set before using focus/history"]
			#debug focus [#print "current window detected as: (select window 'type):(select window 'size) (mold select window 'text)"]
			self/histories: sift histories [w h .. w/state]		;-- forget closed windows
			repend histories [window hist: make [] 11]
		]
		hist
	] #type [function!]
	;@@ DOC: history is used when focused face is no longer there
	
	add-to-history: function [space [object!]] [
		#debug focus [#print "adding (space/type):(space/size) to focus history"]
		face: either is-face? space [space][host-of space]
			;@@ maybe call VID/update-focus in this case?
		; unless face [?? histories ?? window ?? space ?? space/content/1 ?? space/content/1/content/1 probe host-of space]		
		w: window-of face
		if w/state [self/window: w] 
		append hist: history space
		remove/part hist hist << 10						;-- limit history length
	]
	
	restore: function [] [
		if path: last-valid-focus [set-focus last path] 
	]
	
	deep-check: function [path [block! path!] facets [block!]] [
		foreach face path [
			unless is-face? face [break]
			unless all with face facets [return no]
		]
		yes
	]
	
	;; path is valid if it's visible still
	;; for faces this means 'state' is not none and 'visible?' is true
	;; spaces validity is checked by get-screen-path itself
	last-valid-focus: function [] [
		for-each/reverse space history [
			all [
				path: get-screen-path space
				deep-check path [state enabled? visible?]
				result: path
				break
			]
		]
		result
	]
		
	send-unfocus: function ["Remove focus from the space" space [object! (any [space? space  is-face? space]) none!]] [
		#debug focus [#print "unfocusing (if space [space/type]):(if space [space/size])"]
		unless space? space [exit]						;-- for faces or none - no action needed
		if all [
			path: get-host-path space
			deep-check path [state]						;-- without /state event is pointless; no visible/enabled in case they get set later
		][
			invalidate space							;-- let space remove its focus decoration
			events/with-stop [							;-- init a separate stop flag for a separate event
				event: copy events/event-prototype
				event/face: path/1
				event/type: 'unfocus
				events/process-event as [] path event [] yes
			]
		]
	]	
	
	send-focus: function ["Put focus on the space" space [object!] (space? space)] [
		if all [
			path: get-host-path space
			deep-check path [visible? enabled?]			;-- tests reachability, /state may be none if window is not yet shown
		][
								;-- or set-focus will deadlock by calling this again
			#debug focus [#print "sending generated 'focus' event to (path/1/type):(path/1/size) on (mold select window-of path/1 'text)"]
			invalidate space							;-- let space paint its focus decoration
			native-set-focus host: path/1
			events/with-stop [							;-- init a separate stop flag for a separate event
				event: copy events/event-prototype
				event/face: host
				event/type: 'focus
				events/process-event as [] path event [] yes
			]
			unless system/view/auto-sync? [show window-of host]	;-- otherwise keys won't be detected
		]
	]
	
	*ace-enabled?:   function [face [object!]] [		;-- spaces has no support for disabling yet
		tabbing/enabled? either is-face? face [face][host-of face]
	]
	*ace-focusable?: function [face [object!]] [
		either is-face? face
			[tabbing/focusable? face]
			[find focus/focusable face/type]
	]
	*ace-visitor: function [parent [object! none!] child [object!]] [
		if all [*ace-focusable? child *ace-enabled? child] [break/return child]
	]
	find-next-focal-*ace: function [dir "forth or back"] [
		if focused: any [current window] [
			tabbing/window-walker/forward?: dir = 'forth
			foreach-node focused tabbing/window-walker :*ace-visitor
		]
	]

]


;; for use within styles
focused?: function [
	"Check if current style is the one in focus"
	/above n "Rather check if space N levels above is the one in focus"
	/parent  "Shortcut for /above 1"
][
	n: 1 + any [n if parent [1] 0]
	to logic! all [
		space1: focus/current
		space2: pick tail current-path negate n
		space1 =? space2
	]
]


;@@ should this refocus windows?
focus-space: function [
	"Focus given space object in it's window (does not refocus windows)"
	space [object!] (space? space)
][
	unless find focus/focusable space/type [return no]	;-- this space cannot be focused
	;; note: same space may appear on multiple hosts and windows (e.g. when put on a new popup all the time)
	if space =? old: focus/current [					;-- no refocusing into the same target, but need to ensure host is focused
		host: host-of space
		;@@ may error out without /parent check - e.g. if click on host hides it, then click continue on focusable child
		;@@ may also error out without host check - e.g. in non-compliant trees like grid-test5-7
		all [host host/parent native-set-focus host]
		return no
	]
	#debug focus [#print "moving focus from (mold/only reduce [old]) to (mold/only reduce [space])"]
	
	;@@ bring focused item into scrollable's view - maybe via on-focus handler?
	focus/send-unfocus old
	focus/send-focus space
	focus/add-to-history space
	
	yes
]

;; overrides (extends) the native function
native-set-focus: :system/words/set-focus
set-focus: function ["Focus face or space object" face [object!]] reshape [
	#debug focus [#print "set-focus call on (face/type):(face/size)"]
	either space? face [
		focus-space face
	][
		focus/send-unfocus focus/current
		unless find [screen window] face/type [			;-- native set-focus errors out on these
			focus/add-to-history face
			@(body-of :native-set-focus)
		]
	]
]

context [
	;@@ due to #3728 focus/unfocus is unreliable as most faces do not report these events on clicks
	;@@ so a partial workaround is to manually test window/selected every time focus may have changed
	;@@ but it's not working when controls are in a panel - see #3808
	;@@ native buttons also silently steal focus on clicks, without affecting window/selected, so they break this
	
	focus-checker: function [face event] [
		; #print "checking focus for (face/type):(face/size)"
		;; focus host on clicks before all other events
		new-focal-face: either host? face
			[maybe/same event/window/selected: face]			;@@ 'maybe' is important to avoid event stack overflow on GTK
			[event/window/selected]
		old-focal-face: all [
			focus/current
			path: get-screen-path focus/current
			path: locate/back path [obj .. is-face? obj]
			first path
		]
		unless new-focal-face =? old-focal-face [
			focus/send-unfocus focus/current
			if all [object? new-focal-face  not host? new-focal-face] [
				focus/add-to-history new-focal-face
			]
			focus/window: event/window
		]
	]
	
	insert-event-func 'spaces-focus-tracker filtered-event-func [face event] [
		[down alt-down mid-down aux-down dbl-click focus]		;-- 'unfocus' here doesn't make sense given focus-checker logic
		focus-checker face event
		none
	]
	
	;@@ this fixes the situation when a host in a new window has got focus but `focus-checker` didn't receive 'focus' event
	register-previewer [key-down] function [space [object!] path [block!] event [map!]] [
		focus-checker event/face event
	]
]


register-previewer/priority
	[down mid-down alt-down aux-down dbl-click]			;-- button clicks on host may change focus
	function [space [object!] path [block!] event [map!]] [
		;@@ should it avoid focusing if stop flag is set?
		#debug focus [#print "attempting to focus (space-id space)"]
		path: get-host-path space
		
		all [
			path										;-- can be none in non-compliant trees, like in grid-test5-7
			focus/deep-check path [state enabled?]		;-- don't focus on a just-destroyed host (popup)
			focus-space space
		]
	]


export exports

;; <<<<<<<<<< %focus.red <<<<<<<<<

					
;; >>>>>>>>>> %hittest.red >>>>>>>>>


;-- requires export

exports: [hittest]

into-map: function [
	map [block!] xy [planar!] child [object! (space? child) none!]
	/only list [block!] "Only try to enter selected spaces"
][
	either child [
		#debug events []	;-- may fail, but still worth seeing it
		;; geom=none possible if e.g. hittest on 'up' event uses drag-path of 'down' event
		;; and some code of 'down' event replaces part of the tree;
		;; also %hovering.red on tree modification uses a no longer valid path
		xy: either geom: select/same/only map child [xy - geom/offset][(0,0)] 
		reduce [child xy]
	][
		;@@ foreach here is not applicable in case of intersecting spaces: must be foreach/reverse
		;@@ since map is ordered in drawing order, last drawn space is 'on top' so it must catch the point first
		either list [
			foreach child list [
				box: select/same map child
				
				if within? xy o: box/offset box/size [
					return reduce [child  xy - o]
				]
			]
		][
			foreach [child box] map [
				
				if within? xy o: box/offset box/size [
					return reduce [child  xy - o]
				]
			]
		]
		none
	]
]

;; has to be fast, for on-over events
hittest: function [
	"Map a certain point deeply into the tree of spaces"
	space [object! (space? space) block! path!]
		"Top space in the tree (host/space usually), or path of spaces to follow"
		;; path/block is required for dragging, as we need to follow the same path as at the time of click
	xy [planar!] (xy == xy) "Point in that top space"	;-- nan check for both coordinates
	/into "Append into a given buffer"
		path: (make [] 16) [block! path!]
][
	unless object? template: space [					;-- follow given path until it ends
		forall template [								;@@ use for-each
			set [space: _: child:] template
			repend path [space xy]
											;-- forced into and map should always return the pair, if child is not none
			set [child xy] case [
				into: select space 'into [into/force xy child]
				map:  select space 'map  [into-map map xy child]
			]
			template: next template
		]
		space: child									;-- continue forth from the child (if lands on any)
	]
	if object? space [
		while [all [space  xy inside? space]] [
			repend path [space xy]
			
			set [space xy] case [
				into: select space 'into [into xy]
				map:  select space 'map  [into-map map xy none]
			]
		]
	]
	new-line/all path no
]

export exports

;; <<<<<<<<<< %hittest.red <<<<<<<<<

					
;; >>>>>>>>>> %tabbing.red >>>>>>>>>


;; requires events.red & focus.red, common/tabbing.red


;; handler for faces remains the same
;; it should not fire when host is focused (handled by the finalizer below),
;; and that is ensured by host not having a 'focusable flag (in vid.red)
;; scaffolding must be extended to work with spaces as well:
do with tabbing/window-walker [
	window?:     function [face [object!]] [all [is-face? face  face/type = 'window]]
	next-linked: function [face [object!]] [all [is-face? face  select face/options 'next]]
	prev-linked: function [face [object!]] [all [is-face? face  select face/options 'prev]]
	pane-of:     :traversal/pane-of
	has-child?:  function [face [object!]] [not empty? pane-of face]
	first-child: function [face [object!]] [
		all [
			pane: pane-of face
			pos:  find pane object!
			pos/1
		]
	]
	last-child:  function [face [object!]] [
		all [
			pane: pane-of face
			pos:  find/last pane object!
			pos/1
		]
	]
	next-child:  function [parent [object!] child [object!]] [
		all [
			pane: pane-of parent
			pos:  any [find/same/tail pane child  pane]			;-- if child is absent default to 1st drawn
			pos:  find pos object!
			pos/1
		]
	]
	prev-child:  function [parent [object!] child [object!]] [
		all [
			pane: pane-of parent
			pos:  any [find/same pane child  tail pane]			;-- if child is absent default to last drawn
			pos:  find/reverse pos object!
			pos/1
		]
	]
	parent-of:   function [child [object!]] [
		all [
			parent: child/parent
			any [
				not is-face? parent
				parent/type <> 'screen							;-- window is the last allowed parent
			]
			parent
		]
	]
]

;; tabbing visitor must now be able to focus into first/last space on the host
tabbing/visitor: function [parent [object! none!] child [object!]] [
	if all [
		focus/*ace-focusable? child
		focus/*ace-enabled?   child
	][ 
		set-focus child
		break
	]
]

;; handler for spaces - only eats Tab key if space didn't process it
;; has to be `key` event (if it's key-down, the following `key` event after refocus goes into the wrong space)
;@@ consider reacting to key-down and consuming the next key/key-up events when refocused
register-finalizer [key] function [space [object!] path [block!] event [map!]] [
	all [
		event/key = #"^-"
		not event/ctrl?									;-- ctrl-tab must mean smth else
		not stop?										;-- was not eaten by any space
		new: focus/find-next-focal-*ace (pick [back forth] event/shift?)
		set-focus new
	]
]
;; <<<<<<<<<< %tabbing.red <<<<<<<<<
				;-- requires traversal/pane-of
					
;; >>>>>>>>>> %single-click.red >>>>>>>>>


;-- requires events.red

context [
	start-offset: none						;-- separate from `start-drag`, which is userspace thing, and this one is hidden

	;-- for `down` it doesn't matter if we use previewer or finalizer
	register-finalizer [down] func [space [object!] path [block!] event [map!]] [
		start-offset: event/offset
	]

	;@@ is it ok that click event will follow up event for normal handlers? but some finalizers will have it unordered
	;@@ or maybe we should schedule some code to be run after the finalizers have finished?
	register-finalizer [up] function [space [object! none!] path [block!] event [map!]] [
		if all [
			event/face							;@@ partial workaround for #5124 - but can do nothing with View internal bugs
			20 >= distance? start-offset event/offset	;-- it's a click, not a drag
			not stop?									;-- up event was not eaten
			head? path									;-- original event, not replicated for children
			;; note: can't leverage children replication here, since `stop` flag has to be shared by the whole stack
		][
			event/type: 'click							;-- Red allows overriding it
			events/with-stop [events/process-event path event [] no]
			event/type: 'up								;-- restore it for the other finalizers
		]
		;@@ TODO: maybe a drag-finished event?
		;@@ but need to decide how to do it properly, e.g. maybe provide a path or axis
		;@@ and if such event is even useful, considering we have on-up and will probably have on-drag
	]

]

;; <<<<<<<<<< %single-click.red <<<<<<<<<

					
;; >>>>>>>>>> %timelines.red >>>>>>>>>
	


timeline!: none

context [
	~: self
	
	;; timeline format: [date space left-action right-action ...]
	period: 4
	
	undo: function [timeline [object!]] [
		if head? timeline/events [exit]
		set [date: space: left: right:] timeline/events: skip timeline/events negate period
		do left
		focus-space space
	]
	
	redo: function [timeline [object!]] [
		if tail? timeline/events [exit]
		set [date: space: left: right:] timeline/events
		timeline/events: skip timeline/events period
		do right
		focus-space space
	]
	
	put: function [timeline [object!] space [object!] left [block!] right [block!] replace? [logic!]] [
		if replace? [timeline/events: skip timeline/events negate period]
		timeline/events: clear rechange timeline/events [
			now/utc/precise
			space
			with space left
			with space right
		]
		if timeline/count > timeline/limit [			;-- trim the head
			n: round/to timeline/limit * 5% 1
			remove/part timeline/events n * period
		]
	]
	
	count: function [timeline [object!]] [
		divide skip? timeline/events period
	]
	
	elapsed?: function [timeline [object!]] [
		if last-time: pick timeline/events negate period [
			difference now/utc/precise last-time
		]
	]
	
	unwind: function [timeline [object!]] [				;-- unlike undo, does not evaluate anything
		also timeline/last-event
		timeline/events: skip timeline/events negate period
	]
	
	last-event: function [timeline [object!] filter [object! none!]] [
		p: timeline/events
		until [
			if head? p [return none]
			p: skip p negate period
			any [not filter  filter =? p/1] 
		]  
		copy/part next p period - 1
	]
		
	;@@ add docstrings? (increases timeline size - critical in fields)
	set 'timeline! make classy-object! declare-class 'timeline [
		events:     []
		limit:      1000	#type [integer!] (limit >= 20)		;-- max number of events to keep
		count:      does [~/count self]							;-- current number of past events
		elapsed?:   does [~/elapsed? self]						;-- can return none if timeline is empty
		last-event: func [/for obj [object!]] [~/last-event self obj]	;-- only returns arguments to 'put', not the time
		undo:       does [~/undo self]
		redo:       does [~/redo self]
		mark:       does [events]								;-- gets current location in the timeline to save
		unwind:     does [~/unwind self]						;-- like 'undo' but does not execute 'left' events
		put: func [space [object!] left [block!] right [block!] /last] [
			~/put self space left right last
		]
	]
]

;; <<<<<<<<<< %timelines.red <<<<<<<<<

					
;; >>>>>>>>>> %edit-keys.red >>>>>>>>>
	

key->plan: none
context [
	near-moves: #[
		left       [by -1]
		right      [by  1]
		backspace  [by -1]
		delete     [by  1]
		home       'head 
		end        'tail
		up         'line-up
		down       'line-down
		page-up    'page-up
		page-down  'page-down
	]
	far-moves:  extend copy near-moves #[
		left      'prev-word
		right     'next-word
		backspace 'prev-word
		delete    'next-word
		home      'far-head
		end       'far-tail
	]

	set 'key->plan function [
		"Turn keyboard event into an edit plan"
		event    [event! map! object!]
		selected [pair! none!] "Current selection state"
	][
		key: event/key
		either printable?: all [
			char? key
			key >= #" "
			not event/ctrl?
		][
			compose [
				remove-range selected
				insert-items here (form key)
			]
		][
			if key = #"^H" [key: 'backspace]
			if all [selected  0 = span? selected] [selected: none]	;-- ignore empty selection
			removal?: find [delete backspace] key
			distance: select either event/ctrl? [far-moves][near-moves] key
			action:   case [removal? ['remove-range] event/shift? ['select-range] 'else ['move-caret]]
			if all [removal?  selected] [distance: 'selected]
			if block? distance [						;-- [move-caret [by 1]] -> [move-caret/by 1]
				distance: distance/2
				action: as path! reduce [action 'by]
			]
			switch/default key [
				left right home end up down page-up page-down [
					deselect?: when all [selected not event/shift?] [select-range none]
					compose [(deselect?) (action) (distance)]
				] 
				delete backspace [compose [(action) (distance)]]
				insert [
					case [
						event/ctrl?  [[copy-range/clip selected]]
						event/shift? [[remove-range selected  paste here]]
						'else        [[]]
					]
				]
				#"A" [[select-range everything]]
				#"C" [[copy-range/clip selected]]
				#"X" [[remove-range/clip selected]]
				#"V" [[remove-range selected  paste here]]
				#"Z" [pick [[redo] [undo]] event/shift?]
			] [[]]										;-- not supported yet key
		]
	]
]

;; <<<<<<<<<< %edit-keys.red <<<<<<<<<

					
;; >>>>>>>>>> %standard-handlers.red >>>>>>>>>



;-- requires events.red (on load)

is-key-printable?: function [event [map!]] [
	to logic! all [
		char? char: event/key
		char >= #" "
		not event/ctrl?
	]
]

define-handlers [

	;-- *************************************************************************************
	scrollable: [
		on-down [space path event] [
			set [item: _: subitem:] skip path 2
			case [
				find [hscroll vscroll] select item 'type [		;-- move or start dragging
					axis: item/axis
					switch select subitem 'type [
						forth-arrow [space/move-by 'line 'forth axis]
						back-arrow  [space/move-by 'line 'back  axis]
						forth-page  [space/move-by 'page 'forth axis]
						back-page   [space/move-by 'page 'back  axis]
						thumb       [drag?: on]
					]
				]
				any [item =? space/content  item = none] [		;-- 'none' is useful if content is smaller than the scrollable
					drag?: find [pan scroll] space/behavior/draggable
					clear skip (path: clone/flat path) 4		;-- drag by content, not by its child (child may override this)
					pass										;-- content may still handle it (e.g. grid-view within grid-view)
				]
			]
			;; don't override drags from inherited handlers (grid-view, etc.), but override from parent handlers (child takes priority)
			if all [drag?  not dragging?/from space] [start-drag path]
			
			space/last-xy: path/2								;@@ kludge
		]
		
		on-up [space path event] [
			either dragging?/from space [						;-- since 'down' is sent to children, let 'up' be sent as well
				if (drag-offset path) +<= (3,3) [pass]			;-- do not eat clicks on content, only drags (experimental) ;@@ or pass anyway?
				stop-drag
			][
				pass
			]
		]
		
		on-over [space path event] [
			unless own?: dragging?/from space [pass exit]		;-- let inner spaces handle it
			
			set [item: _: subitem:] skip path 2
			switch/default select item 'type [					;-- item may be none
				hscroll vscroll [
					unless all [
						own?
						thumb?: 'thumb = select subitem 'type	;-- do not react to drag of arrows (used by timer)
					] [exit]
					scroll: item
					x:      scroll/axis
					;; map/subitem/size should take precedence over subitem/size
					;; because map can get fetched from cache without affecting subitem object sizes (they become invalid at this point)
					forth-arrow-geom: select/same scroll/map scroll/forth-arrow
					back-arrow-geom:  select/same scroll/map scroll/back-arrow
					band:   scroll/size/:x - forth-arrow-geom/size/:x - back-arrow-geom/size/:x
					csize:  space/content/size					;@@ may get out of sync with the map?
					vport:  space/viewport
					hidden: csize/:x - vport/:x
					ofs: drag-offset skip path 2				;-- get offset relative to the scrollbar
					ofs: ofs/:x / max 1 band					;-- scale it down by scrollbar's size 
					ofs: ofs * (csize * axis2pair x)			;-- now scale up by content size
				]
			][
				switch space/behavior/draggable [
					pan [
						if own? [ofs: negate drag-offset path]
					]
					scroll [
						space/last-xy: path/2					;@@ kludge
					]
				]
			]
			if ofs [space/clip-origin space/origin - ofs]		;-- clipping in the event handler guarantees validity of size
			if own? [
				if any [
					thumb?
					not find [scroll select] space/behavior/draggable
				] [start-drag path]								;-- restart from the new offset or it will accumulate
			]
		]
		on-key-down [space path event] [
			; unless single? path [pass exit]
			code: switch event/key [
				down       [[space/move-by pick [page line] event/ctrl? 'forth 'y]]
				up         [[space/move-by pick [page line] event/ctrl? 'back  'y]]
				right      [[space/move-by pick [page line] event/ctrl? 'forth 'x]]
				left       [[space/move-by pick [page line] event/ctrl? 'back  'x]]
				page-down  [[space/move-by 'page 'forth 'y]]
				page-up    [[space/move-by 'page 'back  'y]]
				home       [[space/move-to 'head]]
				end        [[space/move-to 'tail]]
			]
			either code [
				do code
			][
				pass									;-- key was not handled (useful for tabbing)
			]
		]
		on-wheel [space path event] [
			if event/ctrl? [exit]						;-- ignore ctrl+wheel, which is used for zoom usually
			if 100 < absolute amount: event/picked [	;@@ workaround for #5110
				amount: -256 * sign? amount + amount
			]
			horz?: to logic! any [						;-- shift+wheel changes direction - wish #9
				path/3 =? space/hscroll
				all [path/3 =? space/content event/shift?]
			] 
			space/move-by/scale
				'line
				pick [forth back] amount <= 0
				pick [x y] horz?
				abs amount * 4
		]
		on-focus [space path event] [
			invalidate space/hscroll/thumb
			invalidate space/vscroll/thumb
		]
		on-unfocus [space path event] [
			invalidate space/hscroll/thumb
			invalidate space/vscroll/thumb
		]
		scroll-timer: [
			on-time [space path event delay [percent!]] [		;-- press & hold way of scrolling
				unless all [
					drag-path
					found: find/reverse/same next drag-path path/-1
				] [exit]
				set [scrollable: xy: item: _: subitem:] found
				switch/default select item 'type [				;-- 'item' can be none
					hscroll vscroll [
						scrollable/move-by/scale
							switch/default select subitem 'type [back-page forth-page ['page] back-arrow forth-arrow ['line]] [exit]
							switch subitem/type [back-arrow back-page ['back] forth-arrow forth-page ['forth]]
							any [select [hscroll x vscroll y] item/type]
							delay + 100%
					]
				][
					;; scroll viewport when dragging out of it (useful for content selection)
					;; this relies on on-over rewriting drag-path on every event, because timer doesn't have access to offsets
					if all [
						scrollable/behavior/draggable = 'scroll
						not (xy: scrollable/last-xy) inside? scrollable		;@@ kludge
					][
						cxy: xy - center: half scrollable/size
						cxy': cxy / center						;-- normalized to [-1,-1]..[1,1]
						ofs: cxy' - (cxy' / max abs cxy'/x abs cxy'/y) * center
						unless zero? ofs [
							scrollable/clip-origin scrollable/origin - ofs
						]
					]
				]
			]
		]
	]

	;-- *************************************************************************************
	inf-scrollable: extends 'scrollable [	;-- adds automatic window movement when near the edges
		on-wheel [space path event] [space/slide]		;-- faster wheel-scrolling, without slide-timer delays
		;; trick here is that inf-scrollable/on-key fires after scrollable/on-key-down:
		;@@ (otherwise I would have to extend the handler dialect to add delayed handlers, child after parent - maybe I should?)
		on-key   [space path event] [space/slide pass]	;-- most useful for fast seamless scrolling on pageup/pagedown
		slide-timer: [
			on-time [space path event delay] [			;-- during scroller dragging
				path/-1/slide
			]
		]
	]

	;-- *************************************************************************************
	list-view: extends 'inf-scrollable [
		on-focus   [space path event] [if space/behavior/selectable [invalidate space/list]]
		on-unfocus [space path event] [if space/behavior/selectable [invalidate space/list]]
		
		on-down [space path event] [
			multi?: space/behavior/selectable = 'multi
			if set [item:] locate path [obj - .. obj/type = 'item] [
				i: space/list/frame/range/1 + half skip? find/same space/list/map item
				mode: case [
					all [event/shift? multi?] ['extend]
					all [event/ctrl?  multi?] ['invert]
					'default                  ['replace]
				]
				range: either all [event/shift? multi?] [i][i thru i]
				batch space [
					select-range/mode range mode
					if i <> here [move-cursor i]				;-- don't move the already selected item around
				]
			]
			; if all [multi? space/behavior/draggable <> 'pan] [start-drag path]	;-- start selection by dragging
			;; let scrollable get the event, for dragging viewport by item
		]
		
		on-up [space path event] [
			if dragging?/from space [stop-drag]
		]
		
		on-over [space path event] [
			unless all [
				drag-path
				dragging?/from space/content					;-- ignore drags of the scrollbars
				found: find/reverse/same next drag-path space	;-- dragging from inside of this list-view, maybe from the item
				multi?: space/behavior/selectable = 'multi
			] [exit]
			y:    space/list/axis
			wxy1: found/4
			wxy2: path/4
			set-pair [i1: i2:] batch space [frame/items-between wxy1/:y wxy2/:y]
			mode: case [
				all [event/shift? multi?] ['extend]
				all [event/ctrl?  multi?] ['invert]
				'default                  ['replace]
			]
			batch space [
				select-range/mode i1 thru i2 mode
				if i2 <> here [move-cursor i2]			;-- don't move the already selected item around
			]
		]
		
		on-key-down [space path event] [
			unless space/behavior/selectable [exit]		;-- this handler is only responsible for selection
			list:   space/list
			y:      list/axis
			range:  list/frame/range
			multi?: space/behavior/selectable = 'multi
			
			;@@ would be nice to use key->plan here but it's tuned for editing text paragraphs
			switch/default event/key [
				#"C" [if event/ctrl? [batch space [copy-items/clip selected]]]
				
				#" " [									;-- space/ctrl+space selected item toggle
					if i: space/cursor [
						mode: case [
							multi? ['invert]
							find space/selected i ['exclude]
							'else ['replace]
						]
						batch space [select-range/mode here mode]
					]
				]
				
				down up page-down page-up home end [
					old: batch space [here]
					target: switch event/key [
						up        ['line-up]
						down      ['line-down]
						page-up   ['page-up]
						page-down ['page-down]
						home      [either event/ctrl? ['far-head]['head]]
						end       [either event/ctrl? ['far-tail]['tail]]
					]
					new: batch space [locate target]
					far-jump?: find [far-head far-tail] target
					
					;; do not(!) move to items that are not drawn yet (too many bugs with that)
					;; (must avoid anchor-moving branch of kit/move-to)
					unless far-jump? [
						range: space/list/frame/range
						new:   clip range/1 range/2 new
					]
					select?: case [
						;; dangerous to select items with far-jump (can be billions)
						all [multi? event/shift? not far-jump?]	['range]
						any [far-jump? not event/ctrl?] ['single]
					]
					batch space [slide]					;-- slide it before it was modified ;@@ needs to consider invalidation type ideally
					switch select? [
						range [
							mode: either event/ctrl? ['include]['extend]
							batch space [select-range/mode old thru new mode]
						]
						single [
							batch space [select-range/mode new thru new 'replace]
						]
					]
					batch space [
						move-cursor/no-clip new			;-- /no-clip is safe as long as given margin does not exceed list/margin
					]
				]
				
			] [exit]									;-- unhandled keys belong to inf-scrollable
			stop/now									;-- handled keys are not passed into inf-scrollable
		]
	]

	;-- *************************************************************************************
	grid-view: extends 'inf-scrollable [
		on-down [gview path event] [
			set [grid: _: cell:] skip path 4
			if 'cell <> select cell 'type [exit]
			cxy:    grid-ctx/get-cell-address grid cell
			unless cxy [exit]
			multi?: gview/behavior/selectable = 'multi
			mode:   either all [event/ctrl? multi?] ['invert]['replace]
			cursor: max cxy grid/pinned + 1 
			unless all [multi? event/shift?] [gview/selection-start: cursor]
			start:  gview/selection-start
			batch grid [move-cursor cursor] 
			case [
				grid/pinned +< cxy [
					batch grid [
						select-range start cxy
						drag?: on
					]
				]
				not multi? ['done]
				cxy +<= grid/pinned [
					batch grid [select-range 1x1 'far-tail]		;-- include headers into selection
				]
				x: case [
					cxy/y <= grid/pinned/y ['x]
					cxy/x <= grid/pinned/x ['y]
				] [
					batch grid [
						select-along ortho x 'all
						select-along/mode x start/:x thru cxy/:x mode
					]
					drag?: on
				]
			]
			if drag? [
				if locate path [o - .. find [hscroll vscroll] o/type] [	;-- allow scrollbars in children to override grid dragging ;@@ a kludge!
					pass exit
				]
				clear skip (path': clone/flat path) 6			;-- drag around grid, not around its cell
				start-drag path'
				stop/now
			]
			; stop/now
			; pass
		]
		
		on-over [gview path event] [
			unless all [
				dragging?/from gview
				not event/ctrl?									;-- handle only ctrl-click, not ctrl-drag
				start: gview/selection-start
				gview/behavior/selectable = 'multi
			] [pass exit]
			set [grid: _: cell:] skip path 4
			if all ['cell = select cell 'type] [
				
				cxy: grid-ctx/get-cell-address grid cell
				unless cxy [exit]
				case [
					all [cxy/x <= grid/pinned/x cxy/y > grid/pinned/y] [	;-- rows after header
						batch grid [
							select-columns 'all
							select-rows    start/y thru cxy/y
						]
					]
					all [cxy/y <= grid/pinned/y cxy/x > grid/pinned/x] [	;-- columns after header
						batch grid [
							select-rows    'all
							select-columns start/x thru cxy/x
						]
					]
					grid/pinned +< cxy [						;-- 2D range selection
						batch grid [select-range start cxy]
					]
				]
				batch grid [move-cursor max cxy grid/pinned + 1]
				stop/now
			]
		]
		
		;; guidelines: https://www.w3.org/WAI/ARIA/apg/patterns/grid/
		on-key-down [gview path event] [
			unless gview/behavior/selectable [exit]				;-- has to be selectable to have cursor
			cursor: batch grid: gview/grid [here]
			switch/default event/key [
				#"A" [
					if event/ctrl? [
						batch grid [select-range 1x1 'far-tail]	;-- include headers into selection
					]
				]
			
				#"C" insert [
					if event/ctrl? [
						batch grid [copy-selection/clip]
					]
				]
			
				#" " [											;-- column or row selection
					if axis: case [
						event/ctrl?  ['x]
						event/shift? ['y]
					][
						gview/selection-start: none				;-- indicate it's not an area selection
						batch grid [
							select-along ortho axis 'all
							select-along axis cursor/:axis
						]
					]
				]
				
				;@@ consider navigation across multicells - follow spreadsheets behavior
				up down left right page-up page-down home end [
					target: pick select [
						up        [column-head line-up]
						down      [column-tail line-down]
						home      [far-head head]
						end       [far-tail tail]
						left      [row-head prev-cell]
						right     [row-tail next-cell]
						page-down [page-down page-down]
						page-up   [page-up   page-up]
					] event/key event/ctrl?
					multi?: all [gview/behavior/selectable = 'multi event/shift?]
					batch gview [cursor: locate target]
					batch grid [
						old-cursor: here
						;@@ these should be known automatically, in the frame or where
						cell1: first grid/locate-point org: negate gview/window/origin
						cell2: first grid/locate-point org + gview/window/size
						; ?? [org cell1 cell2 old-cursor]
						cursor-drawn?: cell1 +<= old-cursor +<= cell2
						repeatable?: find [line-up line-down prev-cell next-cell page-up page-down] target
						;@@ temporary limit until redesign:
						;@@ moving cursor outside the currently drawn area shows empty space until filled by multiple slides
						;@@ it's slow when holding arrow keys, so I disable it (but for far jumps it's a necessity to have it)
						if any [cursor-drawn? not repeatable?] [
							move-cursor cursor
							old-sel: selected-range
							either all [multi? old-sel not gview/selection-start] [	;-- current selection is not a limited area, but bits
								axis: either cursor/y = old-cursor/y ['x]['y]
								select-along/mode axis old-cursor/:axis thru cursor/:axis 'include
							][									;-- current selection is either empty or a limited area
								either multi? [
									default gview/selection-start: old-cursor
								][
									gview/selection-start: cursor
								]
								select-range gview/selection-start cursor
							]
						]
					]
					batch gview [pan-to-cursor]
					gview/slide									;@@ put into the batch
				]
			][exit]												;-- let unhandled keys go into inf-scrollable
			stop/now
		]
	]

	;-- *************************************************************************************
	switch: [
		on-up [space path event] [
			space/state: not space/state
		]
	]
	
	;-- *************************************************************************************
	link: [
		;; without explicit start-drag here
		;; parent (e.g. scrollable) may start it's own dragging
		;; and -up event won't reach the link
		on-down [space path event] [start-drag path] 
		on-up   [space path event] [stop-drag]
		
		on-click [space path event] [
			do space/command
		]
	]
	
	;-- *************************************************************************************
	clickable: [
		on-click [space path event] [
			do space/command
		]
		on-down [space path event] []					;-- prevent clicks from passing over to children
		on-up   [space path event] []
	]
	
	data-clickable: extends 'clickable []
	
	menu: [
		list: [
			clickable: extends 'clickable [
				; on-up [space path event] [
					; hide-popups event/window 1			;-- click on a menu item hides all visible menus
				; ]
				on-over [space path event] [			;-- on-hover highlight ;@@ should it affect /color though?
					space/color: if path/2 inside? space [impose 'panel opaque 'text 15%]
				]
			]
		]
		ring: [
			clickable: extends 'menu/list/clickable []
			round-clickable: extends 'menu/list/clickable []
		]
		on-click [space path event] [
			item: path/5
			if find [round-clickable clickable] select item 'type [
				do item/command
			]
			popups/hide 1								;-- click on a menu hides all visible menus
		]
	]

	button: [											;-- focusable unlike `clickable` space
		on-down [space path event] [
			space/pushed?: yes
			start-drag path								;-- otherwise `up` event might not be caught, leaving button "pressed"
		]
		on-up [space path event] [
			space/pushed?: no		;@@ TODO: avoid the command when pointer goes out of button box (also maybe ESC key)
			stop-drag
		]
		on-key [space path event] [
			either all [
				find " ^M" event/key
				not space/pushed?
			][
				space/pushed?: yes
			][pass]
		]
		on-key-up [space path event] [
			either all [
				find " ^M" event/key
				space/pushed?
			][
				space/pushed?: no
			][pass]
		]
	]


	;-- *************************************************************************************
	rotor: [
		ring: [
			on-down [space path event] [
				rotor: path/-2
				ofs: path/-1 - (rotor/size / 2)
				angle: arctangent2 ofs/y ofs/x
				start-drag/with path reduce [rotor/angle angle]
			]
			on-up [space path event] [stop-drag]
			on-over [space path event] [
				unless dragging? [exit]
				rotor: path/-2
				ofs: path/-1 - (rotor/size / 2)
				angle: arctangent2 ofs/y ofs/x
				parm: drag-parameter
				rotor/angle: (parm/1 + angle - parm/2) // 360
			]
		]
	]


	;-- *************************************************************************************
	field: [
		;; `key-down` supports key-combos like Ctrl+Tab, `key` does not seem to
		;; OTOH `key` properly reflects Shift state in chars
		;; so we have to use both, just separate who handles what
		on-key [space path event] [					;-- char keys branch (inserts stuff as you type)
			unless is-key-printable? event [			;-- handled by on-key-down (e.g. ctrl+BS=#"^~") 
				unless find [#"^[" #"^M" #"^H" left right delete home end insert] event/key [pass]	;-- keys unhandled by field can go to the parent
				exit									;@@ what about enter key / on-enter event?
			]
			;@@ TODO: input validation / filtering
			batch space compose [
				(key->plan event space/selected)
				frame/adjust-origin						;@@ should be automatic
			]
			invalidate space							;-- has to reconstruct layout in order to measure caret location
			invalidate/only space/caret					;@@ any way to properly invalidate both at once? -- need layout under cache
		]
		
		on-key-down [space path event] [				;-- control keys & key combos branch (navigation)
			if is-key-printable? event [exit]
			unless any [
				event/ctrl?
				find [#"^[" #"^M" #"^H" left right delete home end insert] event/key
			] [pass exit]	;-- keys unhandled by field can go to the parent
			batch space compose [
				(key->plan event space/selected)
				frame/adjust-origin
			]
			invalidate space
		]

		on-key-up [space path event] [					;-- eats the event so it's not passed forth
			unless any [
				is-key-printable? event
				event/ctrl?
				find [#"^[" #"^M" #"^H" left right delete home end insert] event/key
			] [pass]									;-- keys unhandled by field can go to the parent
		]

		on-down [space path event] [
			batch space [
				select-range none
				move-caret frame/point->caret path/2
			]
			start-drag path
		]
		
		on-over [space path event] [
			
			dpath: drag-path
			if all [dpath dpath/1 =? path/1] [			;-- if started dragging also on this field
				batch space [
					select-range frame/point->caret path/2
					frame/adjust-origin
				]
			]
		]
		
		on-up [space path event] [stop-drag]
		
		on-focus   [space path event] [space/caret/visible?: yes]
		on-unfocus [space path event] [space/caret/visible?: no]
	]

	slider: [
		on-down [space path event] [
			space/offset: batch space [frame/x->offset path/2/x]
			start-drag path								;-- keep tracking knob when pointer leaves the slider
		]
		on-up   [space path event] [stop-drag]
		on-over [space path event] [
			if event/down? [space/offset: batch space [frame/x->offset path/2/x]]
		]
		on-key  [space path event] [
			if integer? step: space/step [
				step: step / (space/size/x - space/knob/size/x)
			]
			either offset: switch event/key [
				left  up   [space/offset - step]
				right down [space/offset + step]
				page-up    [space/offset - max 10% step * 20]
				page-down  [space/offset + max 10% step * 20]
				home       [0%]
				end        [100%]
			][
				space/offset: 100% * clip 0 1 offset
			][
				pass									;-- ignore other keys, esp. tab
			]
		]
		on-focus   [space path event] [invalidate space]
		on-unfocus [space path event] [invalidate space]
	]
	
	fps-meter: [
		on-time [space path event] [
			time: now/precise/utc
			limit: time - space/aggregate
			frames: space/frames
			forall frames [
				if frames/1 > limit [
					remove/part frames frames: head frames
					break
				]
			]
			append frames time							;-- let frames never be empty, so frame/1 is not none
			elapsed: to float! difference time frames/1
			fps: (length? frames) / (max 0.01 elapsed)	;-- max for overflow protection
			space/text: rejoin ["FPS: " 0.1 * to integer! 10 * fps]
		]
	]
]


;; <<<<<<<<<< %standard-handlers.red <<<<<<<<<

					
;; >>>>>>>>>> %hovering.red >>>>>>>>>


;-- requires scheduler to assign a filter

;@@ for this design to work, all /into funcs must accept (return none) spaces that are no longer their children!

context [
	last-path: make [] 20								;@@ suffers from REP #129
	over-face: none
	
	scheduler/event-filters/away-generator: function [face event [map!] "assumes healed event"] [
		#debug events [id: #composite "(select face 'type):(select face 'size)"]
		switch event/type [
			down alt-down aux-down up alt-up aux-up [self/over-face: face]
			over [										;-- pointer may have left a space it was in
				#debug events [#print "got 'over' event for (id) away=(event/away?)"]
				#debug events [#print "checking it for space change..."]
				unless event/away? [self/over-face: face]
				detect-away face event
				; if event/away? [clear last-path]
			]
			time [										;-- space may have been moved on the last frame
				;; time event constantly jumps between faces, so only time events for the hovered over host must be accepted:
				if face =? over-face [
					#debug events [#print "got 'time' event while over (id); checking it for space change..."]
					detect-away face event
				]
			]
			down [clear last-path]						;-- dragging initializes a new path (probably shorter than a normal one)
		]
		none											;-- let other event funcs process it
	]
	
	;; logic here is to repeat hittest and see if any space in the new path differs from the last path
	;; last path should be updated by every host's 'over' and 'time' event
	detect-away: function [host [object!] event [map!]] [
		if all [
			drag?: events/dragging?						;-- during dragging away condition is registered routinely
			event/type <> 'time							;-- but it still may have moved on the frame
		] [exit]
		
		#debug events [#print "reached still 'over' detection code for (host/type):(host/size) away=(event/away?)"]
		#debug profile [prof/manual/start 'hovering]
									;-- must be filled by heal-event if /type = 'time
		template: either drag? [last-path][host/space]
		hittest/into template event/offset clear new-path: []
		
		if moved?: not same-paths? last-path new-path [
			#debug events [#print "still movement confirmed based on paths (mold last-path)->(mold new-path)"]
			if event/type = 'time [						;-- need to synthesize the 'over event?
				event: copy event
				event/type: 'over
				; #assert [event/face =? host]				;-- doesn't hold when already moved away from the last host
			]
					
			;; while 'over' now lands into another space, we need to send the event into the old one, as 'away notice'
			hittest/into last-path event/offset clear path: []	;-- update coordinates along the last-path
			events/with-stop [events/process-event path event [] no]
			append clear last-path new-path						;-- stash the modified path
		]
		#debug profile [prof/manual/end 'hovering]
	]
]

;; <<<<<<<<<< %hovering.red <<<<<<<<<

					
;; >>>>>>>>>> %actors.red >>>>>>>>>



;; requires events


actors: context [

	supported-events: [
		down up  mid-down mid-up  alt-down alt-up  aux-down aux-up
		dbl-click over wheel
		key key-down key-up enter
		focus unfocus click							 	;-- internally generated
		time
	]
	
	actor-names: make map! map-each/eval name supported-events [	;-- used to avoid frequent allocations when adding "on-"
		[name to word! rejoin ["on-" name]]
	]

	;; previewer so it takes priority over event handlers and can stop them
	register-previewer supported-events function [
		space [object! none!] path [block!] event [map!] delay [percent! none!]
	][
		all [
			space
			actors: select space 'actors
			name:   select actor-names event/type
			actor:  select actors name
			actor space path event delay
		]
		; if event/type <> 'time [print [event/type mold path] ??~ space]
		; if event/type = 'key [print [event/type mold path] ??~ actors]
	]
	
];; actors

;; <<<<<<<<<< %actors.red <<<<<<<<<

				]
		
				;; makes some things readily available:
				events:    ctx/events
				templates: ctx/templates
				styles:    ctx/styles
				layouts:   ctx/layouts
				focus:     ctx/focus
				VID:       ctx/VID
			];spaces: context [
		];#local [
	];without-GC [
	recycle
];do/expand [


];#if not value? 'spaces-included? [ 
