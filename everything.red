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

#process off											;-- do not expand the rest using the default #include
do/expand [
	#include %../common/debug.red						;-- need #debug macro so it can be process rest of this file
	
	#debug on
	; #debug set draw										;-- turn on to see what space produces draw errors
	#debug set profile									;-- turn on to see rendering times
	; #debug set cache 									;-- turn on to see what gets cached (can be a lot of output)
	; #debug set focus
	; #debug set events
	; #debug set styles
	; #debug set grid-view
	; #debug set list-view
	
	#include %../common/assert.red
	; #assert off
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
	#include %../common/map-each.red
	#include %../common/xyloop.red
	#include %../common/modulo.red
	#include %../common/with.red
	#include %../common/catchers.red
	#include %../common/is-face.red
	; #include %../common/keep-type.red
	#include %../common/typecheck.red
	; #include %../common/selective-catch.red
	#include %../common/reshape.red
	#include %../common/do-queued-events.red
	#include %../common/show-trace.red
	#include %../common/do-atomic.red
	
	; random/seed now/precise
	
	;-- below trickery is used to put all space things into a single context...
	spaces: #()
	context [
		; joined: clear []
		set 'joined clear []
		script-dir: what-dir
		change-dir #do keep [what-dir]
		include: function [file [file!]] [
			#debug [print ["loading" mold file]]
			#debug [append joined compose/deep [print ["#including" (mold file)]]]
			append joined load/all file
			; print ["loaded" mold file]
		]
	
		include %auxi.red
		include %styles.red
		include %rendering.red
		include %layouts.red
		include %spaces.red
		include %vid.red
		include %events.red
		include %traversal.red
		include %focus.red
		include %tabbing.red
		include %single-click.red
		include %timers.red
		include %standard-handlers.red
		include %hittest.red
		include %debug-helpers.red
	
		spaces/ctx: do/expand compose/only [context (joined)]
	
		;-- makes some things readily available:
		spaces/events:    spaces/ctx/events
		spaces/templates: spaces/ctx/spaces
		spaces/styles:    spaces/ctx/styles
		spaces/layouts:   spaces/ctx/layouts
		spaces/keyboard:  spaces/ctx/keyboard
		
		change-dir script-dir
	]
]
#process on
