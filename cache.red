Red [
	title:   "Cache for Draw-based widgets"
	author:  @hiiamboris
	license: BSD-3
]

exports: [invalidate invalidate-tree get-full-path]


cache: context [
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
		set 'current-generation gen
		trap/all/catch code [error: thrown]
		set 'current-generation old
		if error [do error]
	]
	
	update-generation: function [
		"Update generation data of SPACE if it's an in-tree render"
		space [object!] (space? space)
		state [word!] "One of [cached drawn]" (find [cached drawn] state)
	][
		if current-generation [
			change change head space/cached current-generation state
		]
	]
	
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
		"If SPACE's draw caching is enabled and valid, return it's cached slot for given canvas"
		space  [object!] (space? space)
		canvas [pair! none!]	;@@ get rid of none
	][
		#debug profile [prof/manual/start 'cache]
		result: all [
			space/cache
			slot: find/same/skip space/cached canvas 2 + length? space/cache
			reduce [space/cache slot]
		]
		;@@ get rid of `none` canvas! it's just polluting the cache, should only be infxinf
		#debug cache [
			name: space/type
			if cache: space/cache [period: 2 + length? space/cache]
			either slot [
				n: (length? cached) / period
				#print "Found cache for (name):(space/size) on canvas=(canvas) out of (n): (mold/flat/only/part slot 40)"
			][
				reason: case [
					cache [rejoin ["cache=" mold extract cache period]]
					not space/parent ["never drawn"]
					not space/cache ["cache disabled"]
					empty? space/cached ["invalidated"]
					'else ["unknown reason"]
				]
				#print "Not found cache for (name):(space/size) on canvas=(canvas), reason: (reason)"
			]
		]
		#debug profile [prof/manual/end 'cache]
		result
	]
	
	commit: function [
		"Save SPACE's Draw block and cached facets on given CANVAS in the cache"
		space  [object!] (space? space)
		canvas [pair! none!]	;@@ get rid of none
		drawn  [block!]
	][
		unless space/cache [exit]						;-- do nothing if caching is disabled
		#debug profile [prof/manual/start 'cache]
		#assert [pair? space/size]						;@@ should I enable caching of infinite spaces? see no point so far
		period: 2 + length? space/cache					;-- custom words + (canvas + drawn)
		slot:   any [find/same/skip space/cached canvas period  tail space/cached]
		words:  compose [canvas drawn (space/cache)]	;-- [canvas drawn size map ...] all bound names
		#assert [period = length? words]
		rechange slot words
		#debug cache [
			#print "Saved cache for (space/type):(space/size) on canvas=(canvas): (mold/flat/only/part drawn 40)"
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
	unless space/cached/-1 [exit]						;-- space was never rendered; early exit (for faster tree construction)
	#debug profile [prof/manual/start 'invalidation]
	default scope: 'size
	either function? custom: select space 'on-invalidate [
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
;; timers.red relies on this to remove no longer valid timers from it's list
get-full-path: function [
	"Get host-relative path for SPACE on the last rendered frame, or none if it's not there"
	space  [object!] (space? space)
	; return: [path! none!]
][
	#assert [space/parent]
	unless all [										;-- fails on self-containing grid
		host: first parents: reverse cache/list-parents space
		host? host
	] [return none]
	
	gen:  host/generation
	path: clear []
	foreach obj next parents [
		frame: head obj/cached
		if frame/1 < gen [return none]					;-- space generation is older than the host: orphaned (unused) subtree
		if frame/2 = 'cached [break]					;-- don't check generation numbers inside cached subtree
	]
	#assert [not find parents none]
	to path! append parents space
]


#if true = get/any 'disable-space-cache? [
	clear body-of :invalidate
	clear body-of :cache/invalidate
	append clear body-of :cache/fetch none
	clear body-of :cache/commit
]


export exports