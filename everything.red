Red [
	title:  "Red Spaces main include file"
	author: @hiiamboris
	; needs:  view										;@@ doesn't work, has to be in the main script
]

;@@ I only partially understand why/how all this magic works
;@@ a huge lot of bugs is fixed by using %include-once
;@@ since it's a macro, it has to be #included, not `do`ne (`do` forgets macros)
;@@ for some reason, it won't affect #includes of this very file,
;@@ so a second preprocessor's pass is required for #includes to be handled by %include-once

#include %../common/include-once.red					;-- the rest can use the improved include
#do [
	;; when compiling, this needs `inline` to get the `-t os` argument!
	linux?: any [										;-- to unify compiled & interpreted workaround logic
		system/platform = 'Linux
		all [Rebol system/version/4 = 4]
	]
]

#process off											;-- do not expand the rest using the default #include
do/expand [
	#include %../common/debug.red						;-- need #debug macro so it can be process rest of this file
	
	#debug off
	; #debug on											;-- type checking and general (unspecialized) debug logs
	; #debug set draw									;-- turn on to see what space produces draw errors
	; #debug set profile								;-- turn on to see rendering and other times
	; #debug set changes								;-- turn on to see value changes and invalidation
	; #debug set cache 									;-- turn on to see what gets cached (can be a lot of output)
	; #debug set sizing 								;-- turn on to see how spaces adapt to their canvas sizes
	; #debug set focus									;-- turn on to see focus changes and errors
	; #debug set events									;-- turn on to see what events get dispatched by hosts
	; #debug set styles									;-- turn on to see which styles get applied
	; #debug set grid-view
	; #debug set list-view
	
	#include %../common/assert.red
	#assert off
	#include %../common/expect.red
	#include %../common/setters.red
	; #include %../common/composite.red
	#include %../common/relativity.red
	#include %../common/scoping.red
	#include %../common/print-macro.red
	#include %../common/error-macro.red
	#include %../common/prettify.red
	#include %../common/clock.red
	#include %../common/profiling.red
	#include %../common/extremi.red
	; #include %../common/map-each.red
	#include %../common/new-apply.red
	#include %../common/new-each.red
	#include %../common/xyloop.red
	#include %../common/modulo.red
	#include %../common/with.red
	#include %../common/catchers.red
	#include %../common/is-face.red
	#include %../common/contrast-with.red
	#include %../common/keep-type.red
	#include %../common/typecheck.red
	; #include %../common/selective-catch.red
	#include %../common/mapparse.red
	#include %../common/reshape.red
	#include %../common/do-queued-events.red
	#include %../common/show-trace.red
	#include %../common/do-atomic.red
	#include %../common/classy-object.red
	#include %../common/advanced-function.red
	
	; random/seed now/precise
	#local [											;-- don't spill macros into user code
		spaces: context [
			ctx: context [								;-- put all space things into a single context
				#include %debug-helpers.red
				#include %auxi.red
				#include %styles.red
				#include %rendering.red
				#include %layouts.red
				#include %vid.red
				#include %events.red
				#include %timers.red					;-- must come after events (to set events/on-time), but before templates
				#include %templates.red
				#include %popups.red
				#include %traversal.red
				#include %focus.red
				#include %tabbing.red
				#include %single-click.red
				#include %standard-handlers.red
				#include %hittest.red
				#include %actors.red
			]
	
			;; makes some things readily available:
			events:    ctx/events
			templates: ctx/templates
			styles:    ctx/styles
			layouts:   ctx/layouts
			keyboard:  ctx/keyboard
			VID:       ctx/VID
		]
	]
]
#process on
