---
gitea: none
include_toc: true
---

# Red Spaces Widget Creators Guide

Will explain the architecture of Spaces and how to extend them.

In essence, what is a UI?\
A dialogue.\
Program communicates info to the human by drawing things on display.\
Human traditionally answers (interacts) via keyboard or any pointing device (voice recognition left alone for simplicity). That's why UI is interactive.

Spaces design provides for 3 basic needs:
- Spaces themselves (how to display things)
- Hittesting via `into` and `map` (how to interpret clicks, gestures, etc)
- Focus model (how to interpret keyboard input)

Everything else is an implementation detail, with the aim of making programmer's and user's lives easier.

## Space

Draw-based widgets are called *spaces* because they are (separate) coordinate spaces that know how to draw themselves.

Minimal space includes only a few facets:
```
spaces/templates/space: declare-class 'space [
	;) type is used for styling and event handler lookup, may differ from template name!
	type:	'space	#type [word!] =
	
	;) draw tells how to render this space
	draw:   []   	#type [block! function!]
	
	;) size tells outside observers how big the render was
	size:   0x0		#type [pair! (0x0 +<= size)] =?
	
	;) parent is used to invalidate upper spaces when important facet changes
	parent: none	#type [object! none!]
	
	;) limits specify sizing constraints
	limits: none	#type [object! (range? limits)  none!] =? :invalidates
	
	;) cache lists words that internal cache should memorize and restore along with rendered look
	cache:  [size]	#type [block! none!]
	
	;) cached holds internal cache data (explained in the relevant chapter)
	cached: tail copy [0.0 #[none]]	#type [block!]
]
```
As you can see, all facets have type, validity check, and equality type used to detect a change. `limits` also triggers invalidation when changed. More about class system you can read in [classy-object.red](https://codeberg.org/hiiamboris/red-common/src/branch/master/classy-object.red).

To make spaces more lightweight, optimal **definition model** looks like this:
```
my-space-context: context [							;) context for functions shared by all spaces of this type
	~: self											;) shortcut for the wrapping context
	
	my-fun: function [space [object!] ...] [		;) functions should accept space instance
		...lots of code...
	]

	declare-template 'my-space/space [
		my-fun: function [...] [
			~/my-fun self ...						;) in-space function should delegate it's task to the shared function
		]
	]
]
```
This way, every instance of `my-space` carries only short dispatching code rather than copying all the big functions from it's template. `my-space-context` name is not necessary: contexts can be anonymous. But functions from named contexts can be used by respective event handlers or when debugging.

`my-space` is built upon the most basic `space` template, inheriting all of it's facets, constraints and on-change handlers. After that you can use `my-space` as a base for new templates.

Instantiation of space template is done using [`make-space` function](reference.md#make-space).

Spaces can be created and rendered freely, but to properly use them and apply styles one needs a `host` face. It is based on the [`base` View widget](https://github.com/red/docs/blob/master/en/view.adoc#base), and provides event dispatching, styling and visual updates.

How to use `host` face is explained in [`quickstart`](quickstart.md). 

### Rendering

Is done by calling `render` function: `draw-commands: render 'some-space`.

`render` accepts either a space! or face! object. It uses /type facet to find a proper style for it.

`render` internally calls:
- space's style function if style is a function, not a block (style function should call `draw` then)
- space's `draw` function otherwise 

Space's `draw` function (as well as it's style function) must:
- return a block of draw commands to visualize that space
- set space's /size facet to a `pair!` value, unless space is infinite
- set space's /map facet if space contains other spaces ([map syntax described below](#map)); for that it must `render` those spaces, resulting in a tree of `render` calls

Host face is rendered as `host/draw: render host` if out of order update is required, otherwise it takes care of redrawing itself on *next timer event* of the host.

`draw` may support the following refinements (if it does, it's style function must also support these and pass through):
- `/window xy1 [pair! none!] xy2 [pair! none!]` if it makes sense to draw only an area (xy1..xy2) of it. E.g. spaces that are likely to occur inside a `scrollable` (list, grid) support it. Infinite spaces *must* support it, because one cannot draw an infinite space wholly.
- `/on canvas [pair!] fill-x [logic!] fill-y [logic!]` if space adapts it's size to given canvas (most spaces do). This is the basis of automated sizing. Explained [below](#canvas).

Space's redraw is the most expensive operation, so it is only done when necessary. Host checks if it's assigned space was invalidated to decide if it should render it. Render will fetch from cache anything that was not invalidated.

Another very expensive operation is the drawing itself, that is setting host's /draw facet, even if it's value didn't change. So if you have a complex layout that is cached, but some tiny thing that is updated often, you'll pay with big CPU load. [`grid-test4`](tests/grid-test4.red) is an example of that: it only updates the FPS text, but Draw has to redraw everything anew. In such cases it will be preferable to have FPS on a separate host face.

### Size

Some spaces have a fixed size (e.g. `rectangle`'s size is controlled by the owner).\
Most other spaces however set their own size, adapting it to the given `canvas` size within range allowed by `limits` facet.

`size` can be `0x0` before the first call to `draw`, and `none` for infinite spaces.

Since `size` is set by `draw`, it is quite volatile and represents *space's size on the last rendered frame in a given canvas*. New frame - new size. Moreover, often to render a single frame, a series of canvas sizes is given to the `draw` before the optimal final size is found. Layout can be moving, resizing, rotating, distorting, but between two frames (two `render` calls) size is a constant.

### Canvas

Is an argument to spaces' `draw` function and to their style function, which is passed if these functions support `/on canvas [pair!] fill-x [logic!] fill-y [logic!]` refinement. To properly handle resizing one must understand how to interpret it.

`canvas` is best understood as the *amount of free space inside the parent*. Colored `box` space can be used to visualize it, as it tries to fill all of it's canvas.

`fill-x` and `fill-y` flags request that space fills the canvas along one or both of its axes (if possible). `render` guarantees that infinite canvas dimensions received by `draw` are always accompanied by `false` fill flag, however if `draw` is called manually, one must ensure this consistency (e.g. if container infinitely extends along some axis it should also set corresponding fill flag to false before calling child's `draw` func).

<details>
<summary>Internally canvas has an encoded form, which is mostly used by the cache...</summary>

While decoded canvas is three values: pair and 2 logic flags, encoded canvas is a single pair with flags affecting the sign:
- negative sign for `fill = true`
- positive sign for `fill = false` and infinite dimensions

</details>  

Notes:
- `infxinf` is a special `pair!` value exported by Spaces and is used to represent virtual infinity. Equals `2e9 by 2e9`
- `/draw` doesn't have to support `/on canvas fill-x fill-y`, and it doesn't have to be passed to it: in this case the default is `infxinf false false`

To simplify working with canvas, following *functions* exist in `spaces/ctx` context:
- `subtract-canvas canvas [pair!] value [pair!]` is used to subtract margins mostly. It's like normal subtraction, but:
  - infinite amounts stay infinite (equal to `infxinf/x`)
  - does not make canvas less than `0x0`
- `finite-canvas canvas [pair!]` returns canvas modulo `infxinf`, that is it turns infinite sizes into zero, which is useful to obtain the size that should be filled

<details>
<summary>See typical canvas handling code example...</summary>

```
context [
	~: self												;-- way for space to refer to this context
	
	;; shared draw function for all spaces in the template
	draw: function [space [object!] canvas: infxinf [pair! none!] fill-x: no [logic! none!] fill-y: no [logic! none!]] [ 
		... draws the space ...
	]
	
	declare-template 'my-template [
		draw: function [/on canvas [pair!] fill-x [logic!] fill-y [logic!]] [
			~/draw self canvas fill-x fill-y			;-- dispatches call into a shared function
		]
	]
]
```
Note that space's `/draw` may have all arguments as `none` which it passes to a shared `/draw`, which assumes the defaults (`infxinf`, `no`, `no`) for this case.

</details>  


## Umbrella namespace

To minimize the risk of clashing with the user words, an umbrella namespace is used to access common features:
```
>> ? spaces
SPACES is an object! with the following words and values:
     ctx        object!       [exports dump-event dump-tree dorc add-indent mold pr...
     events     object!       [cache on-time previewers finalizers handlers registe...
     templates  map!          [space timer stretch <-> rectangle triangle image box...
     styles     hash!         length: 58  make hash! [base [below: [fill-pen 255.25...
     layouts    object!       [list tube ring]
     keyboard   object!       [focusable focus history valid-path? last-valid-focus...
     VID        object!       [styles host? host-on-change init-spaces-tree wrap-va...
```
`spaces/ctx` contains every function and context defined, and it is the context under which all spaces code operates internally. By binding your code to it you get access to all the features:
```
do with spaces/ctx [...code...] 
```

For convenience, a few names are duplicated from `spaces/ctx` into `spaces` map: `events`, `templates`, etc.

Also some functions are exported into global namespace, e.g. `make-space`, `space?`, `focused?`, etc.


## Hierarchy

Just painting inner spaces is not enough. Need interactivity (e.g. for [hittesting](https://en.wikipedia.org/wiki/Hit-testing), and keyboard input):
- to recognize spaces within other spaces
- to support coordinate transformation (esp. for hittesting)
- to know the order of inner spaces (esp. for tabbing)

Composite space (that "contains" other spaces) should be extended with any or both of:
```
into: func [xy [pair!] /force child [object! none!]] -> [object! pair!] or none

map: [
	object! [offset pair! size pair!]		;) e.g.: inner-space [offset 10x10 size 100x100]
	object! [offset pair! size pair!]
	...
]
```
`/map` facet can be static (unlikely case), but most of the time it is filled by space's `/draw` function. If space can support caching, it should list `map` in it's `/cached` facet, e.g. `cached: [size map]`.

`/parent` facet is set by `render` automatically depending on what parent space called it. Only single parent is allowed (you can read a [design card](design-cards/single-vs-multiple-parents.md) for more details on that).

These facets are used to construct tree paths:
- `map` is used by traversal functions (like `list-spaces` or `foreach-*ace`), and by hittest (descending order)
  Traversal functions are in turn used by tabbing mechanics to switch keyboard focus
- `into` is used (and preferred over `map`) by hittest (also descending order), and `into` often uses `map` itself
- `parent` is used by cache invalidation and by timers (ascending order)

Tree paths are used to look up:
- styles in style sheets
- event handlers among defined events


### `into`

Function that is used in hittesting only.

- takes a point in it's space's coordinate system
- determines which *inner* space this point lands to
- returns the inner space and a point in inner space's coordinate system, or `none` if it lands outside
- when `child` argument is not `none`, it should translate coordinates into the given child (only required if this space wants to support dragging) even it point lands outside; `/force` value should be ignored\
  if child is no longer present in the space, it should return 0x0 coordinate for it (happens when testing paths that were valid on one frame, but became invalid on another)

This allows for rotation, compression, reflection, anything. Can we make a "mirror" space that reflects another space along some axis? Easily.

`into` is not required for hittesting, it just makes it possible to use all these transformations on events. If all inner spaces are just boxes, `map` should be defined instead. `into` is also often used for translation in spaces that support `origin` (containers of all kind).

<details>
	<summary>
<code>into</code> does not provide tree iteration capability (e.g. for tabbing). If iteration is needed (e.g. inner spaces are focusable), then <code>map</code> should also be provided.
</summary>

<br>

Geometries in such `map` are ignored and can be absent or contain invalid/dummy/empty values, e.g.:
- `[inner-space [] ...]` (no offset or size)
- `[inner-space [offset 0x0 size 0x0] ...]` (dummy geometry)
- `[inner1 inner2 ...]` (no geometry)

</details>

### `map`

Is a block that tells which inner space occupies which region (offset & size) of this space on the last frame.\
Order: first items get precedence in case of overlap. So `map` can be thought of a reverse Z-order: topmost child appears first in the map.\
Format described above.

Map is only good for rectangular geometry (which is the majority of use cases anyway). In this case `into` is not needed and `map` is used for hittesting.

`map` should be filled by each `draw` call (or if `draw` is a static block - `map` must be defined at space creation). Before the 1st `draw` call: what isn't drawn does not exist.

`map/child/size <> child/size` in general case: `map` defines it's geometry in parent's coordinates, while `child/size` is it's size in it's own coordinates. E.g. parent may scale it's child.


### Caching

Is controlled by the `/cache` facet, which is a block listing what other facets to cache. Most spaces are cached by default, which can be turned off by setting `cache: none`.

What caching system does is for each given canvas it remembers the outcome: result of `/draw`, as well as any other facets listed in the `/cache` block (usually it's `[size map]`). Then if the same canvas value is provided, it fetches and sets the cached facets and returns the recalled `/draw` result.

Most facets use the [class system](https://codeberg.org/hiiamboris/red-common/src/branch/master/classy-object.red) to define equality type and a function that gets called when facet change is detected by equality test. One way or another, this function eventually calls `invalidate` on the space in question. `invalidate` bubbles up the tree to clear this space's cache and cache of all of it's parents. So important facet change eventually leads to a redraw.

Equality type considerations:
- `=?` is the fastest operator and should be used e.g. for integer or pair facets
- `=` is good for word facets, as we don't usually care about their case
- `==` is good for (short) string facets, as we do care about their case; for long string facets it's inefficient and it's better to invalidate it than to lose time in comparison (e.g. in a big text some character changes during an edit)
- no criterion: invalidation always happens on facet assignment, even if the value is the same; good for bigger facets, internal ones and those not supposed to be changed (like functions)


Meet:
```
>> ? invalidate
USAGE:
     INVALIDATE [space]

DESCRIPTION: 
     Invalidate SPACE cache, to force it's next redraw. 
     INVALIDATE is a function! value.

ARGUMENTS:
     space        [object!] {If present, space/on-invalidate is called instead of cache/invalidate.}

REFINEMENTS:
     /only        => Do not invalidate parents (e.g. if they are invalid already).
     /info        => Provide info about invalidation.
        cause        [object! none!] "Invalidated child object or none."
        scope        [word! none!] "Invalidation scope: 'size or 'look."
```
You can have your own caching mechanism if you define `on-invalidate` facet of the following form:
```
on-invalidate: function [
    space [object!]
    cause [none! object!]
    scope [none! word!]
] [...]
```
It will be called by `invalidate` instead of clearing the `cached` facet.

On parameters:
- `cause` starts with `none`, but as invalidation bubbles up, it gets set to the child that caused invalidation of the parent receiving the call. It is used e.g. by `grid` to find out the coordinate of invalidated cell and contain invalidation to given row and column, while maintaining cache on the other rows and columns.
- `scope` can be:
  - `'size` or `none` for full invalidation
  - `'look` for a hint that only color or other cosmetic change was detected, that doesn't affect the size
    `'look` can be used as an optimization, e.g. in some big list an item changes it's look and list doesn't have to re-render all other items as it knows it's overall size did not change: it only needs to re-render the item in question.

<details><summary>Cache is held within the <code>/cached</code> facet...</summary>

<br>
It has the following form:
```
[
	<last-canvas> <last-generation-number> <last-state>		;) block's head is located after these 3 values
	<canvas> <slot-generation-number> <children-list> <draw-commands> <size> <map> <any other cached facets...>
	<canvas> <slot-generation-number> <children-list> <draw-commands> <size> <map> <any other cached facets...>
	...
]
```
Generation number gets updated from the host's `/generation` facet which is increased on every render call. Last state can be either `'cached` (fetched from cache during last render) or `'drawn` (an actual call to `/draw` happened during last render). This data is used by timers to track spaces that are still live (on the tree), so timers for orphaned subtrees can be disabled to save resources. Slot generation numbers are used by cache to keep itself from creep.

</summary>


## Styles

Spaces should include facets that affect their appearance, e.g. `margin` or `font`, and provide reasonable defaults. Those defaults may then be overridden in styles. It's not a necessity, but practicality: it's easy to modify space's facets, but if margin and font were hardcoded in the styling function, modifying it would require it's replacement.

Visual features that are not meant to be changed between different instances of a space template, should be hardcoded into the template style. See [the manual](manual.md#styling) on style definition.

Template styles should not include any logic unrelated to visual appearance, as they should be easy to replace.

For simpler usage in VID/S, a VID/S style should be defined as well. It's done by extending the `spaces/VID/styles` map:
```
extend spaces/VID/styles [
	my-style-name [										;) VID/S style name
		template: template-name							;) name of the template used to create space with
		spec:     [.. default init code ..]				;) spec is used as in: `make-space 'template-name spec`
		facets: [
			some-datatype!  some-facet-name				;) data of this type will be auto-assigned to this facet
			other-datatype! some-function-value			;) data of this type will be passed as argument to given function
			flag-name       [.. code to evaluate ..]	;) code will be evaluated if flag is met in VID/S
		]
		layout:   name-of-the-custom-layout-function	;) use this only if you want to extend layout syntax beyond the default
	]
]
```
Comments above basically summarize the whole syntax of it. A few remarks:
- `facets` block is what makes it more user friendly, so use it
- to put function values into this block, use `compose/deep` or [`reshape`](https://codeberg.org/hiiamboris/red-common/src/branch/master/reshape.md)
- `spec` is good to alter hardcoded defaults
- `layout` should usually be omitted
  - if provided, it's spec should be `func [block [block!] /styles sheet [map! none!]]`
  - it should process the block and return a block of *code* to be used to build it's `content` pane
  - code will be bound to the space and evaluated after it's construction
  - `sheet` carries currently accumulated VID/S styles and should be passed to `lay-out-vids` to create panes of inner spaces


## Events

Events handlers provide interactivity to a space template. See [the manual](manual.md#defining-behavior) about how to write event handlers. Space should include all necessary levers inside, and event handlers used only to operate these levers and be kept short and clean.

Key takeaways:
- same event and handler names [as in View](https://github.com/red/docs/blob/master/en/view.adoc#events)
- `function` constructor is used to prevent set-words leakage
- handlers are function lists, not single functions
- receive path on the tree
- path is relative to the space for which the handler is defined
- previewers and finalizers for fine event flow control
- two-dimensional event handler lookup order (see [the manual](manual.md#handler-lookup-and-event-propagation))
- event handlers (for the whole template) are not actors (that belong to an individual space), handlers are written by widget designer, actors - by widget user



### Function lists

Unlike faces, where all the magic of how widget works is done in R/S or by the OS, handlers have to implement the magic manually.\
If this magic was overridden, widget would become rather useless.\
So in Spaces, *handlers are function lists*: each handler entry given to `define-handler` function adds a new function to the list.

List *is associated with a path*, e.g. `menu/list/clickable` or just `button`.

List handlers are evaluated from the *oldest to the newest* (or default handler -> extension handler -> user handler).

Individual handlers in this list cannot be blocked by `stop` command, only the whole list at once. So if original event handler receives an event, then all of it's extensions do too.



### Previewers and finalizers

[Manual](manual.md#previewers-and-finalizers) explains the basics and how to write one.

Key concepts:
- use masks to select events to respond to
- cannot be blocked via `stop` command
- can generate new events (see [event generation](#event-generation))
- evaluated in order from the first defined to the last defined
- same as normal handlers, these are called hierarchically, e.g. for path `menu/list/clickable` there will be 3 global handler calls: `menu/list/clickable`, `list/clickable` and `clickable` (if they are defined)
  - handler may use `head? path` test if it doesn't need to be evaluated for child spaces (e.g. right-click on a menu-enabled space only wants to find the innermost `menu` facet, and should not show multiple menus if there's more than one) 



### Event generation

`spaces/events/dispatch` is the function that receives View events and decides how to handle them.

`spaces/events/process-event` is the function that can be called to pass emulated events into event handlers.

```
>> ? spaces/events/process-event
USAGE:
     PROCESS-EVENT path event args focused?

DESCRIPTION: 
     Process the EVENT calling all respective event handlers. 
     PROCESS-EVENT is a function! value.

ARGUMENTS:
     path         [block!] "Path on the space tree to lookup handlers in."
     event        [event! object!] "View event or simulated."
     args         [block!] "Extra arguments to the event handler."
     focused?     [logic!] {Skip parents and go right into the innermost space.}
```
- `path` you usually get in the previewer/finalizer; just pass it further
- `event` you get from View, in the same previewer/finalizer
- `args` are only used right now to pass `delay` to timers, and should be an empty block everywhere else
- `focused?` is true for keyboard and focus/unfocus events: only focused spaces should receive these, not their parents


## Focus & Tabbing

Focus allows to direct keyboard events (`key key-down key-up enter`) into a particular "focused" space. Tabbing cycles focus between spaces when Tab key is pressed.

`spaces/keyboard/focus` holds the currently focused space's path. Focused space can be changed via:
- calling `focus-space` function directly (it accepts a space or it's tree path)
- clicking (`down mid-down alt-down aux-down dbl-click`) on a point that intersects with a *focusable* space
- [tabbing (module)](tabbing.red)

Focused space is saved as a tree path. So for tabbing (and focus in general) to work properly, items in that path should not be discarded. If object in that path is no longer in it's parent's map, focus becomes invalid (which is equivalent to no focus) and attempt to focus next or previous space will start from last valid focused path.

Focusable space types are listed in `spaces/keyboard/focusable` block (new types can be added there at will, simply as words).

Only *rendered* spaces can be focused by tabbing or `focus-space`, and clicking can only focus *visible* ones. Spaces must be present in the `map`s of their parents. Map may or may not include spaces outside the scrollable's viewport, it's implementation-dependent. If tabbing into a space outside of the viewport is desired, spaces near the edge of it should be put into the `map`.

<details>
	<summary>
<i>Tabbing order</i> is the order of the tree, i.e. defined by <code>map</code> order (in turn may be defined by <code>content</code> order in case of <code>list</code> space, etc.). <code>list-spaces</code> and <code>dump-tree</code> functions can be used to visualize it.
	</summary>

<br>

Space tree has 2 dimensions: outer/inner (depth-wise) and previous/next (sibling nodes).\
Forward order (Tab key) is defined as *outer->inner and previous->next*, e.g.:
```
list
list/item1
list/item2
other-space
```
Because Shift-Tab should be a full reverse of Tab, same for any iteration, reverse order is defined as *inner->outer and next->previous* (even though inner->outer part may cause some confusion):
```
other-space
list/item2
list/item1
list
```

</details>

Example code with a new *focusable* space:
```
#include %spaces/everything.red

declare-template 'my-space/space [
	size: 50x50
	draw: [box 1x1 49x49]
]
append spaces/keyboard/focusable 'my-space

set-style 'my-space [
	above: when focused? (compose [text 7x17 "FOCUS"])
]

define-handlers [
	my-space: [on-key [space path event] [print event/key]]
]

view [host focus [my-space]]
```
Press Tab or click on the box space to focus it (should be indicated by "FOCUS" word). Then it will print every key pressed.

## Debugging

### Assertions 

Usually the first thing to do when something unexplicable happens is to ensure assertions are turned on. In [`everything.red`](everything.red) after inclusion of `assert.red` the `off` line should be commented out:
```
#include %../common/assert.red
; #assert off
```
Assertions may slow down Spaces operation some, but are useful to contain the error.

Then:
- divert the output of your program to a file, e.g. `red myscript.red |tee log` or `red myscript.red >log`
- run the script until the error occurs
- inspect the `log` file: usually the *first* failed assertion is the cause of misbehavior

Assertions are assumptions about how code works. Failed assumptions do not necessarily mean bugs. Sometimes it's the assumption that's wrong, which helps you build a correct mental model at earlier stages of development. But sometimes I'm using them in places where proper errors must be thrown but I have no time to bother with proper error detection and reporting (yet).

### Debug output

Is very helpful in nailing down the issue. E.g. Red tells you that `none` is unexpected in a Draw block. How do you know which one it is? You turn `draw` debugging and it will tell you in the log. 

In [`everything.red`](everything.red) there's a whole bunch of commented out debug directives:
```
#include %../common/debug.red						;-- need #debug macro so it can be process rest of this file
; #debug off										;-- turn off type checking and general (unspecialized) debug logs
; #debug set draw									;-- turn on to see what space produces draw errors
; #debug set profile								;-- turn on to see rendering and other times
; #debug set changes								;-- turn on to see value changes and invalidation
; #debug set cache 									;-- turn on to see what gets cached (can be a lot of output)
; #debug set sizing 								;-- turn on to see how spaces adapt to their canvas sizes
; #debug set focus									;-- turn on to see focus changes and errors
; #debug set events									;-- turn on to see what events get dispatched by hosts
; #debug set timer									;-- turn on to see timer events
; #debug set styles									;-- turn on to see which styles get applied
```
Uncomment relevant item, run your script and see if there's a clue in the log.

I strongy recommend `#debug off` be always commented out during development as it affects type and range checks of all space facets and helps you detect errors earlier.

For `profile` output to work, add `prof/show` before exit or at the point where you want the output. `prof/reset` can be used to reset stats. E.g. load during initialization can be different from load during usage, so it makes sense to call `prof/show prof/reset` after the `view/no-wait` call to see initialization phase, then `prof/show` after `do-events` loop quits to see the usage phase. It also makes sense sometimes to do `prof/show prof/reset` every one or few seconds in `on-time` actor, to have smaller profiling slices.

`debug-draw` command can be used to bring up GUI where you can inspect the spaces tree and look of each space in the tree.

### Inspecting your data

Spaces are powered by custom `mold` implementation, which is aimed at producing readable output for programmers. It affects `?`, `??`, `probe` and `save` output.

Most notably, it shortens by default space objects inside other data to `type:size`, so don't take that for an url!:
```
>> render list: first lay-out-vids [hlist [text text text]]
>> ?? list/map
list/map: [
	text:0x16 [offset 10x10 size 0x16]
	text:0x16 [offset 20x10 size 0x16]
	text:0x16 [offset 30x10 size 0x16]
]
```
Also `save/all` output (and `mold/all`) now produces a fully loadable format, supported by [`load-anything` macro](https://codeberg.org/hiiamboris/red-common/src/branch/master/load-anything.red).
 
Do use spaces console (that is run by `run.bat` or `red console.red`) or put a `halt` in your script where you can inspect values interactively.

`??` function is also extended:
- it accepts words and paths as the native function did
- it also accepts blocks of words and paths to dump multiple values in a line, e.g. `?? [x y size]`
- it also accepts any value, e.g. `?? (compute something)`, in which case it works as `probe`

`dorc` (short for `do read-clipboard`) command can be used to evaluate code from the clipboard without messing up console's history. I use it a lot.

### Test your widgets in [VID/S Polygon](programs/vids-polygon.red)

Put them into containers, e.g. into a `row` inside a `column`, and see how they work with automatic sizing. Try resizing the window.
