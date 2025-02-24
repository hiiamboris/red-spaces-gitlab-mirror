Red [
	title:    "Rendering and caching engine for Draw-based widgets"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.rendering
	depends:  [spaces.geometry  global advanced-function]
]


rendering: classy-object [
	"Host and space rendering and frame management"

	;@@ support custom on-invalidate
	;@@ support /info cause scope
	global invalidate: function [
		"Mark SPACE and all of its parents as invalid to force their next redraw"
		space [object!]
	][
		#debug [
			if rendering? [
				#print "*** Invalidation during the render cycle detected in (space-id space) !"
				#tip   "don't invalidate during render, otherwise every frame will trigger a new redraw^/"
			]
		]
		;; relies on assumptions:
		;; - empty /frames means the space is already invalid (true for freshly created spaces)
		;;   in practice this assumes that all spaces above also have an empty /frames, which sounds correct
		;; - face (host) has no /frames, so the loop ends there
		;; there's no deadlock possible: it will visit itself again with an empty frame and stop
		while [not empty? select space 'frame] [
			clear space/frames
			space: space/parent
		]
	]
	
	global dirty?: function [
		"Check if SPACE was invalidated and never rendered since"
		space [object!]
	][
		empty? space/frames
	]
	
	;; cull-old-frames assumes that this condition holds (and it's the reason I collect spaces, not frame maps - maps are compared by equality)
	#assert [2 = length? unique [object [x: 1] object [x: 1]]  "'unique' is expected to compare objects for sameness"]
	
	cull-old-frames: function [
		"Remove all unused frames from spaces in the given list"
		spaces  [block!]
		cur-gen [float!]
	][
		foreach space unique spaces [
			foreach [canvas frame] space/frames [				;@@ should work fine with removal at the same time? use remove-each when fast
				if frame/generation < cur-gen [
					remove/key space/frames canvas
				]
			]
		]
	]
	
	render-host: function [
		"Render a HOST face and return a Draw block"
		host   [object!] (host? host)
		canvas [map!]
	][
		#assert [host/space]									;@@ error out if no space, or silently do nothing?
		focus/restore											;-- before each frame, check if focus is still on a live space
		do with host/rendering [
			active?:    true									;-- an indicator that a host render is currently in progress
			generation: host/generation + 1.0
			clear path
			clear visited
			append clear branch host
		]
		#leaving-safe [
			do with host/rendering [
				host/generation: generation
				active?: false
				clear visited									;-- second clear to free spaces for GC-ing
				clear branch									;-- ditto
			]
		]
		frame: render-space host/space canvas					;-- this may error out; protected by #leaving macro
		cull-old-frames host/rendering/visited host/generation	;-- cull on rendering success only
		if zero? host/size [host/size: host/space/size]			;-- override host/size if its empty
		host/draw: frame/drawn									;-- return and assign the result (since generation is updated anyway)
	]
	
	;; fake host used for out of tree space renders only (needed for performance)
	dummy-host: object [
		generation: 0.0
		rendering: object [
			active?:    false
			generation: none
			visited:    make block! 100
			path:		make path!  16
		]
		reset: does [
			clear rendering/visited								;-- cleaned up on every fetch, because not used
			;@@ FIXME: path can't be cleaned up, so errors during 'render-space' may build it up
			self
		]
	]
	
	rendering?: function
		["Check if some host is currently being rendered"]
		with :render-host [object? try [host]]
	
	get-current-host: function
		["(internal) Get currently rendered host face"]
		with :render-host [any [attempt [host] dummy-host/reset]]
		; with :render-host [trap/catch [host] [dummy-host/reset]]
	
	render-space: function [
		"Render a SPACE, update its /frames info, and return rendered frame"
		space   [object!]
		canvas  [map!]
		; /as type: space/type [word!] "Fake space's type (e.g. to invoke ancestor styles)"
		;@@ /as is problematic: need to pass it through the render-with-style into layout/make - do I need it?
		/force "Bypass the cache for this space (but not for its children)"
		; /only ?
		return: [map!]
	][
		#assert [(space/type valid-canvas? canvas)]				;-- it's not fatal, so I don't want a proper error here (/type is for info only)
		encoded: encode-canvas canvas
		;@@ apply canvas limits right here
		host: get-current-host
		
		either all [
			frame: space/frames/:encoded						;-- less likely condition checked first
			not force
		][
			frame/genesis: 'cached
		][
			append path:   host/rendering/path   space/type
			append branch: host/rendering/branch space			;@@ if 'render' was a function, could take this from 'space' argument on the stack
			; #leaving-safe [take/last path]						;@@ benchmark this and maybe add a message about space/type? 
			
			frame: render-with-style space canvas path			;-- invokes layout/make which invokes tools/draw
			#assert [map? frame  "tools/draw must return a map!"]
			frame/canvas:  encoded
			frame/genesis: 'drawn
			space/frames/:encoded: frame
			append host/rendering/visited space					;-- mark this space as one of those redrawn on this frame
			
			take/last branch 
			take/last path 
			quietly space/parent: last branch
		]
		
		space/frames/last: frame
		; space/frames/history: append any [space/frames/history make [] 4] encoded		;@@ benchmark if this makes sense
		frame/generation:  host/rendering/generation			;-- update generation even for cached slots (or they'll be culled)
		;@@ auto-clipping? when? limits? size>canvas?
		frame
	]
	
	;; for better performance, no dispatcher function: 'render-host' must be used on faces directly
	;@@ or make a dispatcher? need a benchmark
	global render: :render-space

	;@@ duality of the 'frame' term should be reflected in the docs: /frames facet vs whole rendered frame
	render-with-style: function [
		"Render SPACE on a CANVAS using style applicable to PATH"
		space   [object!]
		canvas  [map!]
		path    [path!] (not tail? path)
		return: [map!] "Rendered frame"
	][
		style: any [											;-- base style, not including a possible path-specified alteration
			templates/(last path)/style							;-- if /type is faked, then at render-space level, accounted in the path
			templates/space/style								;-- if template has no style, default to the style of 'space'
		]
		;@@ add some invalidation prevention directly into the facets wrapper? it's a most likely place for such errors
		;@@ 'noinvalidate' or 'validate' or 'valid' or 'isolate(d)'
		;@@ though currently rendered path is not yet valid anyway, and the only risk is removing other cached geometries
		with-space space [										;-- bound to space so one can use expressions inside settings and tags
			do style/facets										;-- apply facets (with-space-bound) before making the layout
			layout: layouts/(style/layout)
			;; performance note: `compose` is 50% faster than chained `make` even without considering the GC
			;@@ maybe use a map when not in debug mode? test performance on grid tests
			settings: make layout-settings! compose [
				(layout/settings)								;-- defaults declared by the layout (unbound)
				(style/settings)								;-- settings declared by the style (with-space-bound)
				(only styling/storage/find-alteration path)		;-- possibly attached style alteration (path-specified) (with-space-bound)
				(only :space/config/style)						;-- unique per-space alteration (tags), e.g. colors set in VID/S ;@@ bind also
			]
		]
		frame: layout/make space canvas settings
		#assert [map? :frame]
		frame
	]
	
	;@@ during ongoing render, should 'live?' relate to the new generation or the previous? or error out?
	global live?: function [
		"Check if space object belongs to the last drawn frame or not"
		space   [object!] (space? space)
		return: [logic!]
	][
		lowest: space/frames/last								;-- with no 'cached' frames, check against the lowest 'drawn' frame
		while [frame: select select space 'frames 'last] [		;-- no /frames = host found (unset), or abrupt tree termination (none)
			if frame/genesis = 'cached [lowest: frame]			;-- each new 'cached' frame replaces the previously found lowest
			space: space/parent
		]
		to logic! all [
			:space/generation = lowest/generation				;-- more likely fail condition than a missing host - comes first
			host? space
			space/state
		]
	]
	
	;; default canvas prototype (init values are arbitrary, should not be relied upon)
	canvas!: make map! compose [size: (INFxINF) x: fill y: fill]
	
	;; having a function frontend is more future-proof than composing canvas as a map everywhere
	make-canvas: function [
		"Make a new canvas! value with provided arguments"
		size [point2D!] (0x0 +<= size)
		x    [word!]    (find [free wrap fill] x)
		y    [word!]    (find [free wrap fill] y)
	][
		make map! compose [size: (size) x: (x) y: (y)]			;@@ or as-map [size x y]? but 2x slower
	]
	
	;; to simplify the rendering functions (reduce the number of assumptions) this is used in 'render'
	;; it ensures that no wrap or fill is requested for an infinite dimension
	valid-canvas?: function [
		"Check the validity of CANVAS"
		canvas [map!]
	][
		to logic! all [
			canvas/size/x >= 0
			canvas/size/y >= 0
			switch/default canvas/x [
				free wrap [yes]
				fill [canvas/size/x < 1.#INF]
			] [no]
			switch/default canvas/y [
				free wrap [yes]
				fill [canvas/size/y < 1.#INF]
			] [no]
		]
	]
	
	encode-canvas: function [
		"Encode CANVAS into a single value for lookups"
		canvas [map!] (valid-canvas? canvas)
	][
		add to point3D! canvas/size
			multiply (0,0,1)
				add switch canvas/x [free [0] wrap [1] fill [2]]
					switch canvas/y [free [0] wrap [4] fill [8]]
	]
	
	#assert [
		(10,10, 0) = encode-canvas #[size: (10,10) x: free y: free]
		(10,10, 5) = encode-canvas #[size: (10,10) x: wrap y: wrap]
		(10,10,10) = encode-canvas #[size: (10,10) x: fill y: fill]
		(10,10, 8) = encode-canvas #[size: (10,10) x: free y: fill]
		(10,10, 1) = encode-canvas #[size: (10,10) x: wrap y: free]
	]
	
	reduce-canvas: function [
		"Reduce CANVAS size by a specified number of pixels"
		canvas [map!] "(copied)"
		amount [planar! linear!]
	][
		canvas: copy canvas
		canvas/size: max (0,0) canvas/size - amount
		canvas
	]
	
	fill-canvas: function [
		"Expand SIZE to fill the CANVAS along dimensions marked as 'fill"
		size    [planar!]
		canvas  [map!]
		return: [point2D!]
	][
		max size as-point2D 
			either canvas/x = 'fill [canvas/size/x][0]
			either canvas/y = 'fill [canvas/size/y][0]
	]
	
]