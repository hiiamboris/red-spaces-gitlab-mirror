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

host-on-change: function [host word value] [
	;@@ maybe call a tree invalidation instead?
	?? word
	if object? :host/space [invalidate host/space]
]

host-on-destroy: function [host word value] [
	#assert [word = 'state]
	unless :value [focus/restore]
]

;; basic event dispatching face
system/view/VID/styles/host: reshape [
	default-actor: worst-actor-ever								;-- worry not! this is useful
	init: [VID/init-spaces-tree self]
	
	template: @[declare-class/manual 'host [
		;; make a chimera of classy-object's and face's on-change so it works as a face and supports class features
		on-change*: function spec-of :classy-object!/on-change*
			with self compose [on-change-dispatch 'host word :old :new (body-of :face!/on-change*)]
		#assert [host? self]									;-- ensure the on-change* magic doesn't distort the class
		
		type:       'base					#type =  [word!]	;-- word will be used to lookup styles and event handlers
		;; no size by default - used by init-spaces-tree as a hint to resize the host itself:
		size:       INFxINF					#type =? [planar! none!] :host-on-change
		;; makes host background opaque otherwise it loses mouse clicks on most of it's part:
		;; (except for some popups that must be almost transparent)
		color:      svmc/panel				#type =  [tuple! none!] :host-on-change
		space:      none					#type =? [object! (space? space) none!] :host-on-change
		flags:      'all-over				#type =  [block! word! none!]		;-- else 'over' events won't make sense over spaces
		rate:       100						#type =  [integer! time! none!]		;-- for space timers to work
		state:		none					#on-change :host-on-destroy			;-- destruction is a trigger for focus restoration

		;; host id is used by scheduler to combine sameness of the host with the event group
		id:         generate-id				#type =  [integer!]
		
		;; rendered generation number, used to detect live spaces (0 = never rendered):
		generation: 0.0						#type =  [float!]
		
		rendering: object [										;-- context for temporary rendering data (hidden from on-deep-change)
			active?:    false									;-- an indicator that currently a host rendering is in process
			generation: 0.0										;-- pending frame's generation
			visited:    make block! 100							;-- list of visited spaces on current frame (cleared after)
			path:		make path!  16							;-- path (of space/type's) of currently rendered space - for style lookups
		] #type [object!]
		
		modify rendering 'owned none							;-- hide custom data from face's on-deep-change (also fixes #5549)
	]]
]
	
	
