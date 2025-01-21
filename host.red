Red [
	title:    "HOST face definition for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.host
	depends:  [global classy-object]
]


global host?: function [
	"Check if OBJ is a HOST face"
	obj [object!]
][
	'host = class? obj
]

;; basic event dispatching face
system/view/VID/styles/host: reshape with [
	host-on-change: function [host word value] [
		;@@ maybe call a tree invalidation instead?
		if object? :host/space [invalidate host/space]
	]
	; host-on-destroy: function [host word new old [any-type!]] [		doesn't work! - #5578
		; #assert [word = 'state]
		; if all [block? :old none? :new] [?? host/state print "DESTROYED" focus/restore]
	; ]
][
	default-actor: worst-actor-ever								;-- worry not! this is useful
	init: [VID/init-spaces-tree self]
	
	template: @[declare-class/manual 'host [
		;; make a chimera of classy-object's and face's on-change so it works as a face and supports class features
		on-change*: function spec-of :classy-object!/on-change*
			with self compose [on-change-dispatch 'host word :old :new (body-of :face!/on-change*)]
		#assert [host? self]									;-- ensure the on-change* magic doesn't distort the class
		
		type:       'base				#type =  [word!] "Host's type will be used for styles and event handlers lookups"
		size:       INFxINF				#type =? [planar! none!] :host-on-change "Host's size (INFxINF turns on autosizing from content)"
		color:      svmc/panel			#type =  [tuple! none!]  :host-on-change "Host background (if fully transparent, will miss pointer events)"
		space:      none				#type =? [object! (space? space) none!] :host-on-change	"Top-level space assigned to this host"
		flags:      'all-over			#type =  [block! word! none!]	"(should contain all-over for proper hovering support)"
		rate:       100					#type =  [integer! time! none!]	"Max. rate of redraw, timers, and other Spaces events"
		; state:		none				#on-change :host-on-destroy			;-- destruction is a trigger for focus restoration -- doesn't work!

		id:         generate-id			#type =  [integer!]	"(used internally by the scheduler to combine host's sameness with the event group)"
		
		generation: 0.0					#type =  [float!]	"Last rendered tree generation number used to detect live spaces (0 = never rendered)"
		
		rendering: object [										;-- context for temporary rendering data (hidden from on-deep-change)
			active?:    false									;-- an indicator that currently a host rendering is in process
			generation: 0.0										;-- pending frame's generation
			visited:    make block! 100							;-- list of visited spaces on current frame (cleared after)
			path:		make path!  16							;-- path (of space/type's) of currently rendered space - for style lookups
			branch:		make block! 16							;-- path (of spaces) of currently rendered space - for parent assignment
		] #type [object!]	"(internal data used by rendering pipeline)"
		
		modify rendering 'owned none							;-- hide custom data from face's on-deep-change (also fixes #5549)
	]]
]
	
	
