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
#do [verbose-inclusion?: yes]							;-- enable to dump filenames
#include %../common/include-once.red					;-- the rest can use the improved include
#do [
	;; when compiling, this needs `inline` to get the `-t os` argument!
	linux?: either Rebol								;-- to unify compiled & interpreted workaround logic
		[system/version/4 = 4]
		[system/platform = 'Linux]
]

#process off											;-- do not expand the rest using the default #include
do/expand [
	#include %../common/debug.red						;-- need #debug macro so it can be process rest of this file
	
	#debug off										;-- turn off type checking and general (unspecialized) debug logs
	; #debug set draw									;-- turn on to see what space produces draw errors
	; #debug set profile								;-- turn on to see rendering and other times
	; #debug set changes								;-- turn on to see value changes and invalidation
	; #debug set cache 									;-- turn on to see what gets cached (can be a lot of output)
	; #debug set sizing 								;-- turn on to see how spaces adapt to their canvas sizes
	; #debug set focus									;-- turn on to see focus changes and errors
	; #debug set events									;-- turn on to see what events get dispatched by hosts
	; #debug set popups									;-- turn on to see popups show/hide events
	; #debug set timer									;-- turn on to see timer events
	; #debug set styles									;-- turn on to see which styles get applied
	; #debug set paragraph								;-- turn on to see words inside paragraph layout
	; #debug set clipboard								;-- turn on to see clipboard writes and 'format' result
	; #debug set grid-view
	; #debug set list-view
	
	#include %../common/assert.red
	#assert off
	#include %../common/setters.red
	#include %../common/with.red
	#include %../common/trace-deep.red
	#include %../common/expect.red
	#include %../common/catchers.red
	#include %../common/composite.red
	#include %../common/relativity.red
	#include %../common/xyloop.red
	#include %../common/without-gc.red
	#include %../common/tree-hopping.red
	#include %../common/tabbing.red						;-- extended by spaces/tabbing.red
	#include %../common/scoping.red
	#include %../common/collect-set-words.red
	#include %../common/print-macro.red
	#include %../common/error-macro.red
	#include %../common/prettify.red
	#include %../common/charsets.red
	#include %../common/exponent-of.red
	#include %../common/format-readable.red
	#include %../common/shallow-trace.red
	#include %../common/profiling.red
	#include %../common/extrema.red
	#include %../common/selective-catch.red
	#include %../common/reshape.red
	#include %../common/new-apply.red
	#include %../common/new-each.red
	#include %../common/modulo.red
	#include %../common/interleave.red
	#include %../common/join.red
	#include %../common/split.red
	#include %../common/is-face.red
	#include %../common/color-models.red
	#include %../common/contrast-with.red
	#include %../common/keep-type.red
	#include %../common/clip.red
	#include %../common/step.red
	#include %../common/count.red
	#include %../common/typecheck.red
	#include %../common/forparse.red
	#include %../common/mapparse.red
	#include %../common/sift-locate.red
	#include %../common/do-queued-events.red
	#include %../common/show-trace.red
	#include %../common/do-atomic.red
	#include %../common/classy-object.red
	#include %../common/advanced-function.red			;-- included by search.red
	#include %../common/search.red
	#include %../common/load-anything.red				;-- required to load data saved by custom 'save'
	
	; random/seed now/precise
	#local [											;-- don't spill macros into user code
		spaces: context [
			ctx: context [								;-- put all space things into a single context
				#include %debug-helpers.red
				#include %auxi.red
				#include %styles.red
				#include %cache.red
				#include %rendering.red
				#include %layouts.red
				#include %source.red
				#include %clipboard.red
				#include %templates.red					;-- requires clipboard on inclusion
				#include %vid.red
				#include %event-scheduler.red			;-- requires vid (host? func)
				#include %events.red					;-- requires auxi, event-scheduler, layouts, styles
				#include %timers.red					;-- must come after events (to set events/on-time), but before templates
				#include %popups.red
				#include %traversal.red
				#include %focus.red
				#include %hittest.red
				#include %tabbing.red					;-- requires traversal/pane-of
				#include %single-click.red
				#include %timelines.red
				#include %edit-keys.red
				#include %standard-handlers.red
				#include %hovering.red
				#include %actors.red
			]
	
			;; makes some things readily available:
			events:    ctx/events
			templates: ctx/templates
			styles:    ctx/styles
			layouts:   ctx/layouts
			focus:     ctx/focus
			VID:       ctx/VID
		]
	]
]
#process on

];#if not value? 'spaces-included? [ 
