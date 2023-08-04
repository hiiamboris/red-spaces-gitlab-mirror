Red [
	title:   "Cache for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

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
		#assert [point2D? space/size]					;@@ should I enable caching of infinite spaces? see no point so far
		cur-gen: any [current-generation space/cached/-2]
		old-gen: cur-gen - 1.0
		period: 4 + length? space/cache					;-- custom words + (canvas + drawn + gen + children)
		words:  compose [canvas cur-gen children drawn (space/cache)]
		#assert [period = length? words]
		unless slot: find/same/skip space/cached canvas period [
			;; if same canvas isn't found, try to reuse an old slot
			slots: space/cached
			forall slots [								;@@ use for-each
				if all [
					slots/2 < old-gen					;-- slot is old
					nan? slots/1/x / slots/1/x			;-- keep [infxinf infx0 0xinf 0x0] canvases (always relevant, unlike 0x319 or smth)
					nan? slots/1/y / slots/1/y
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
	foreach-space [path space] host/space [invalidate/only space]
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
	#assert [not unset? :space/cache  "cache should be initialized before other fields"] 
	#assert [4 = index? space/cached]
	unless space/cached/-1 [exit]						;-- space was never rendered; early exit (for faster tree construction)
	#debug profile [prof/manual/start 'invalidation]
	default scope: 'size
	either function? set/any 'custom select space 'on-invalidate [
		custom space cause scope						;-- custom invalidation procedure
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
	path: clear []
	append parents space								;-- space's generation has to be verified as well 
	foreach obj next parents [
		if obj/cached/-2 < gen [return none]			;-- space generation is older than the host: orphaned (unused) subtree
		if obj/cached/-1 = 'cached [break]				;-- don't check generation numbers inside cached subtree
	]
	#assert [not find parents none]
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
