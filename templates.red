Red [
	title:    "Spaces templates core"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.templates
	depends:  [global classy-object advanced-function]
]


;; an alias used in make-space
space!: copy classy-object!

global space?: function [										;-- faster check used when value is known to be an object
	"Determine if OBJ is a space! object"
	obj [object!]
][
	to logic! templates/(class? obj)
]

global is-space?: function [									;-- shortcut for `all [object? :value space? value]`
	"Determine if VALUE is a space! object"
	value [any-type!]
][
	to logic! all [
		object? :value
		templates/(class? value)
	]
]

;; base for all new templates
template!: object [
	spec:			;-- construction spec for make-space
	tools:			;-- functions that take a space argument
	kit:			;-- functions (or wrappers) auto-bound to the space with 'using'
	config:			;-- each template should have its own shared default config
	style:			;@@ make it possible to directly write the style or call 'define-styles'?
		none
]

templates: make #[] 100

templates/space: make template! [
	;; tools are template functions that take `space` argument
	tools: object [
		;; 'draw' is a mandatory tool for all templates
		draw: function [space [object!] canvas [map!]] [
			copy/deep #[size: (0,0) drawn: []]
		]
	]
	
	;; kit is template functions to be called by `using`, passing `space` argument implicitly
	;; it should always be present in the template, to simplify kit inheritance
	kit: object []												;-- initialized further below
	
	;; config is often shared across single template spaces to save RAM and allow mass modification
	;; to enable sharing while offering the convenience of automatic invalidation when it is changed, it has to track its owners
	config: object [
		owners: make hash! 16									;-- spaces that use the config; shared configs must use hash! here
		on-change*: function [word old new] [
			;@@ verify if it works as expected during a chain of 'make's
			foreach space owners [invalidate space]				;-- each (?) config assignment invalidates all its owners
		]
	]
	
	;; spec is fed to every make-space call to construct a space from the template
	spec: declare-class 'space [
		;; type identifies space's template context; it is patched in place by declare-template
		;; all kit and event and style lookups are using the type
		type:   'space
		
		;; parent makes the space able to trace its location on the tree, making invalidation and liveness checks possible
		parent: none
		
		;; each frame contains not only the set of commands to draw the space, but also info computed during the rendering process
		;; such info is useful for all kinds of frame measurements, be it glyphs, items, caret location, and so on
		;; minimum frame requirements: #[size [planar!] drawn [block!]]
		frames: make map! 4										;@@ literal maps are not copied - #2167
		
		;; config contains settings that affect the behavior of individual or a group of spaces (when config is shared)
		config: templates/:type/config							;-- ideally config is not recreated unless needed
		#on-change [space word new [any-type!] old [any-type!]] [
			if object? :old [remove find/same old/owners space]
			#assert [any [hash? :new/owners (length? new/owners) <= 8]] 
			append new/owners space
		]
	]
]

global make-space: function [
	"Create a new Space object from given template TYPE"
	type [word!] (templates/:type)
	spec [block!]
][
	;@@ should I also copy/deep the spec?
	make space! append copy/deep templates/:type/spec spec		;-- copy/deep to avoid bugs caused by shared series
]

;@@ default config assignment - global or per template (template/type/default-config) ?

global declare-template: function [
	"Declare a new space template with given NAME"
	name   [path! (parse name [2 word!]) word!]
	source [block!] "Must include a /spec field at least"
][
	either path? name+base: name
		[set [name: base:] name]
		[base: 'space]
	templates/:name: ctx: make template! source					;@@ add error capturing scope for make?
	#assert [templates/:name/spec    "Template declaration must include a /spec field!"]
	#assert [templates/:name/config  "Template declaration must include a /config field!"]
	base:  copy/deep templates/:base/spec
	added: declare-class name+base ctx/spec
	change find/tail base [type:] to lit-word! name				;-- replace the previous type
	ctx/spec: compose [(base) (added)]
	ctx
]

extend-config: function [config [object!] spec [block!]] [
	;@@ copy the /owners or not here?
	make config spec
]

;@@ test declare-template and make-space with assertions once stable


;@@ copy or not? ideally I want to avoid the copy, that's why I removed 'do-batch' from the kit, which could cause conflicts
;; must be free of any locals, to not pollute the 'plan' with extra word bindings
global using: function [
	"Evaluate PLAN within SPACE's kit"
	space [object!]
	plan  [block!]
][
	#assert [select select templates space/type 'kit  "no kit provided by the space template"]
	do bind plan templates/(space/type)/kit						;-- expose only kit functions to the plan
]

;; I got rid of 'do-batch' in the kit, as binding 'plan' to various 'do-batch' funcs can mess it up
;; to the point where words' context will be unavailable (on recursive entrance)
global make-kit: function [
	"Create a kit for the template"
	name    [path! (parse name [2 word!]) word!] "'name or 'name/base"
	spec    [block!]  "Functions for the kit"
	return: [object!] "The new kit object"
][
	either path? name [set [name: base:] name][base: 'space]
	#assert [
		select templates base  "base template is undefined"
		select templates name  "target template is undefined"
	]
	;; bind spec to 'using' to make it access the current 'space' (ancestor funcs were already bound):
	templates/:name/kit: make templates/:base/kit with :using spec
]

templates/space/kit: make-kit 'space [
	;; by convention, space's operational timer is held in the /timer facet
	arm-timer:    does [events/arm-timer    space space/timer]
	disarm-timer: does [events/disarm-timer space space/timer]
]

	
