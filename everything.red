Red []

#include %../common/debug.red
#debug on
; #debug set events
; #debug set styles
; #debug set grid-view
; #debug set list-view

#debug [
	#macro [#include file!] func [s e] [compose/deep [print ["#including" (mold s/2)] do (s/2)]]
]
#include %../common/assert.red
#include %../common/expect.red
#include %../common/setters.red
; #include %../common/composite.red
#include %../common/relativity.red
#include %../common/print-macro.red
#include %../common/error-macro.red
#include %../common/clock.red
#include %../common/profiling.red
#include %../common/extremi.red
#include %../common/map-each.red
#include %../common/xyloop.red
#include %../common/modulo.red
#include %../common/with.red
#include %../common/catchers.red
#include %../common/is-face.red
#include %../common/keep-type.red
; #include %../common/selective-catch.red
#include %../common/reshape.red
#include %../common/do-queued-events.red
#include %../common/show-trace.red
#include %../common/do-atomic.red

#include %auxi.red
#include %styles.red
#include %layouts.red
#include %spaces.red
#include %vid.red
#include %events.red
#include %traversal.red
#include %focus.red
#include %tabbing.red
#include %single-click.red
#include %timers.red
#include %standard-handlers.red
#include %hittest.red
#include %debug-helpers.red
