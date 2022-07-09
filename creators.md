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

Minimal space:
```
object [
	size: none! or pair!
	draw: func [] -> block!
]
```
Nothing else! `draw` tells how to render this space. `size` tells outside observers how big the render was.

To make spaces more lightweight, optimal **definition model** looks like this:
```
my-space-context: context [							;) context for functions shared by all spaces of this type
	~: self											;) shortcut for the wrapping context
	my-fun: function [space [object!] ...] [		;) functions should accept space instance
		...lots of code...
	]

	spaces/templates/my-space: make-template 'space [
		my-fun: function [...] [
			~/my-fun self ...						;) in-space function should delegate it's task to the shared function
		]
	]
]
```
This way, every instance of `my-space` carries only short dispatching code rather than copying all the big functions from it's template.

Building a space on top of another is done like this:
```
new-space-context: context [
	~: self											;) another shortcut - only affects new functions
	my-fun: function [space [object!] ...] [		;) another big task solver
		...lots of code...
	]

	spaces/templates/new-space:
		make-template 'my-space [					;) extends previously defined 'my-space' type
			my-space-my-fun: :my-fun				;) old `my-fun` can be saved by prefixing it with a prototype name `my-space-`
			my-fun: function [...] [
				~/myfun self ...
				my-space-my-fun ...					;) new `my-fun` now can call the old one when it needs to
			]
		]
]
```

`my-space-context` and `new-space-context` names are not necessary: contexts can be anonymous. But functions from named contexts can be used by respective event handlers or when debugging.

Instantiation of space type is done using [`make-space` function](reference.md#make-space).

Spaces can be created and rendered freely, but to properly use them and apply styles one needs a `host` face. It is based on the [`base` View widget](https://w.red-lang.org/en/view/#base), and provides event dispatching, styling and visual updates.

How to use `host` face is explained in [`quickstart`](quickstart.md). 

### Rendering

Is done by calling `render` function: `draw-commands: render 'some-space`.

`render` accepts either:
- a space name (word!)
- a face object!

`render` internally calls:
- space's style function if style is a function, not a block (style function should call `draw` then)
- space's `draw` function otherwise 

Space's `draw` function must:
- return a block of draw commands to visualize that space
- set space's /size facet to a `pair!` value, unless space is infinite
- set space's /map facet if space contains other spaces ([map syntax described below](#map)); for that it must `render` those spaces, resulting in a tree of `render` calls

Host face is rendered as `host/draw: render host` if out of order update is required, otherwise it takes care of redrawing itself on *next timer event*.

Space's redraw is the most expensive operation, so it is only done when necessary. Necessity is signalled by setting face's `/dirty?` facet to true. Usually it is done either by `update` command available to event handlers, or by `invalidate` function that gets called when an imporant facet of a space is changed.

Internally a cache of rendered blocks is kept for each canvas size. When such (still valid) block is available, `render` grabs and returns it and sets `/size` and `/map` facets to cached values corresponding to that canvas. Consequently, both map and draw block should be created anew by the `draw` call, and cannot be modified in place.

`draw` may support the following refinements (if it does, it's style function must also support these and pass through):
- `/only xy1 [pair! none!] xy2 [pair! none!]` if it makes sense to draw only an area (xy1..xy2) of it. E.g. spaces that are likely to occur inside a `scrollable` (list, grid) support it. Infinite spaces *must* support it, because one cannot draw an infinite space wholly.
- `/on canvas [pair! none!]` if space adapts it's size to given canvas (most spaces do). This is the basis of automated sizing. Canvas model is scheduled for a change though.

### Size

Some spaces have a fixed size (e.g. `rectangle`'s size is controlled by the owner).\
Most other spaces however set their own size, adapting it to the given `canvas` size within range allowed by `limits` facet.


`size` can be `none` before the first call to `draw` or for infinite spaces.

Since `size` is set by `draw`, it is quite volatile and represents *space's size on the last rendered frame in a given canvas*. New frame - new size. Moreover, often to render a single frame, a series of canvas sizes is given to the `draw` before the optimal final size is found. Layout can be moving, resizing, rotating, distorting, but between two frames size is a constant.

### Canvas

Is an argument to `draw` function of spaces and to their style function, which is passed if these functions support `/on canvas [pair! none!]` refinement. To properly handle resizing one must understand how to interpret it.

`canvas` is best understood as the *amount of free space inside the parent*. Colored `box` space can be used to visualize it, as it tries to fill all of it.

It's a bit more complicated though, as required for proper handling of flow layouts (`paragraph`, `tube`). Each axis of the canvas can have the following values:

| Value | Meaning | Example |
|-|-|-|
| < 0 | Size of available area that should be filled if possible | `-300x-200` means area size of `300x200` should be filled |
| = 0 | Intent is to minimize space along given axis | text rendered on `0x200` canvas should put 1 char per line |
| 0 < canvas < infxinf/x | Size of available area should be used to limit the space but should not be filled | text or tube rendered on `200x0` canvas should wrap itself at 200 pixels and start a new line, but should not extend to fill the width `200` |
| = infxinf/x | Size is infinite: space should not wrap itself along this axis, but should otherwise minimize itself, because infinity cannot be filled | text rendered on `infxinf` canvas should always render as a single line |

Notes:
- `infxinf` is a special `pair!` value exported by Spaces and is used to represent virtual infinity. Equals `2e9 by 2e9`
- `canvas` can be `none`, in which case it has the same meaning as `infxinf`

To simplify working with canvas, following *functions* exist in `spaces/ctx` context:
- `decode-canvas canvas [pair!]` returns a block `[abs-canvas [pair!] fill-flags [pair!]]`:
  - `abs-canvas` contains the positive value of area size; it's useful for calculations - min, max, subtraction, etc
  - `fill-flags` is a pair -1x-1 to 1x1, where value of `1` means that axis should be filled, `0` or `-1` mean that it should not
- `encode-canvas abs-canvas [pair!] fill-flags [pair!]` is the reverse: it turns positive area size value into an encoded possibly-infinite canvas size
- `subtract-canvas abs-canvas [pair!] value [pair!]` is used to subtract margins mostly. It's like normal subtraction, but:
  - infinite amounts stay infinite (equal to `infxinf/x`)
  - does not make canvas less than `0x0`
- `finite-canvas canvas [pair!]` returns canvas modulo `infxinf`, that is it turns infinite sizes into zero, which is useful to obtain the size that should be filled
  


## Umbrella namespace

To minimize the risk of clashing with the user names, an umbrella namespace is used to access common features:
```
>> ? spaces
SPACES is a map! with the following words and values:
     ctx        object!       [by abs block-stack when range clip for clo...
     events     object!       [cache on-time previewers finalizers handle...
     templates  map!          [space timer rectangle triangle image scrol...
     styles     block!        length: 8  [host [pen off fill-pen 255.252....
     layouts    object!       [list tube list-layout-ctx tube-layout-ctx]
     keyboard   object!       [focusable focus history valid-path? last-v.
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
into: func [xy [pair!] /force name [word! none!]] -> [word! pair!]
map: [
	word! [offset pair! size pair!]		;) e.g.: inner-name [offset 10x10 size 100x100]
	word! [offset pair! size pair!]
	...
]
```

<details>
	<summary>
There is no <code>parent</code> facet. <i>Same</i> space object can be shared between various parents, or it can even be it's own child.
	</summary>

<br>

A tree nonetheless exists:
- root for spaces is the `host` face
- each space's children are listed in the `map`
- internal cache holds the parent references, for `invalidate` to affect them, and as an optimization for timers

Event handlers receive a path on this tree, so child spaces handlers can access their parents.

A space can only be shared if:
- it's `size` and `map` are fixed and do not depend on the canvas (otherwise a render somewhere else on another canvas invalidates these set by render in a previous place); an example of that would be some avatar icon
- it's non-interactive, has no map, and no one cares if it's size becomes invalid after it's rendered; example: `stretch` space that paints nothing

</details>


### `into`

Function that is used in hittesting only.

- takes a point in it's space's coordinate system
- determines which *inner* space this point lands to
- returns *name* of the inner space and a point in inner space's coordinate system
- when `name` argument is not `none`, it should return provided (by name) inner space even if the point lies outside it (only required if this space wants to support dragging). `/force` value should be ignored.

This allows for rotation, compression, reflection, anything. Can we make a "mirror" space that reflects another space along some axis? Easily.

`into` is not required for hittesting, it just makes it possible to use all these transformations on events. If all inner spaces are just boxes, `map` should be defined instead. Where `into` is also useful is in infinite spaces like `grid-view`.

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

Is a block that tells which inner face occupies which region (offset & size) of this space.\
Order: first items get precedence in case of overlap. So `map` can be thought of a reverse Z-order: topmost child appears first in the map.

Map is only good for rectangular geometry (which is the majority of use cases anyway). In this case `into` is not needed and `map` is used for hittesting.

`map` should be filled by each `draw` call (or if it's constant - defined on space creation). Before the 1st `draw` call: what isn't drawn does not exist.

<details>
	<summary>
Names in the <code>map</code> may repeat (by spelling), but each should refer to a unique object.
	</summary>

<br>

Examples of that are `list` and `grid` styles that can contain hundreds of `item` or `cell` occurrences in their `map`. Each `item`/`cell` is styled using the same style, and shares same event handlers, but objects (`get item`/`get cell`) are not the same.

</details>

`map/child/size <> child/size` in general case: `map` defines it's geometry in parent's coordinates, while `child/size` is it's size in it's own coordinates. E.g. parent may scale it's child.

### Names

Every space has a name (word)! This name refers to a space object which can be obtained using `get`.

Names are used everywhere in place of objects: in `map`, in `items-list` and `cell-map`, `into` returns a name, tree path received by event handlers contains names, etc.

Space can only be rendered by it's name (`render` won't accept a space object), because this name tells it which style to use. Event dispatcher uses names to decide what event handlers to call.

Why a name is needed?
- styles are based on names
- events are dispatched by names
- what is focusable or not depends on it's name
- possible to repurpose a generic (e.g. `rectangle`) space by giving it a name (e.g. `thumb` of a `hscroll` or `vscroll`) - such space will behave and be styled differently (e.g. `rectangle` doesn't need events, but `thumb` may react)

<details>
	<summary>
Why <code>(get name) = object</code> rather than <code>object [name: ..]</code>?
</summary>

<br>

- dumping particular spaces tree: if you've ever tried `?? my-face` you know it is a bad idea that will force you to kill the console; spaces however are always fully inspectable
- it makes style and event paths also inspectable, which is very helpful when debugging
- simpler listing of the tree of spaces (otherwise all those words would have to be created anew every time a tree is listed)
- to test and evaluate an approach different to the one taken in View

Drawbacks:
- have to call `get` an extra round sometimes. But other way would have to `select .. 'name`, so no big deal.
- to fetch a deep subspace for inspection (e.g. `probe host/space/list/item`), such path has to be preprocessed (done automatically by Spaces Console - `red console.red`).

I'm not totally against the alternative though, if more benefits will be discovered.

</details>


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
- same event and handler names [as in View](https://w.red-lang.org/en/view/#events)
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
- calling `focus-space` function directly (it accepts a tree path)
- clicking (`down mid-down alt-down aux-down dbl-click`) on a point that intersects with a *focusable* space
- [tabbing (module)](tabbing.red)

[comment]: # (TODO: a more user-friendly focusing way is needed since path isn't always available, sometimes only the space object)  

Focused space is a tree path. So for tabbing (and focus in general) to work properly, items in that path should not be discarded. If object in that path is no longer in it's parent's map, focus becomes invalid (which is equivalent to no focus) and attempt to focus next or previous space will start from last valid focused path.

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

spaces/templates/my-space: make-template 'space [
	size: 50x50
	draw: [box 1x1 49x49]
]
append spaces/keyboard/focusable 'my-space

define-handlers [
	my-space: [on-key [space path event] [print event/key]]
]

view [host focus [my-space]]
```
Press Tab or click on the box space to focus it. Then it will print every key pressed.

## Debugging

### Assertions 

Usually the first thing to do when something unexplicable happens is to ensure assertions are turned on. In [`everything.red`](everything.red) after inclusion of `assert.red` the `off` line should be commented out:
```
#include %../common/assert.red
; #assert off
```
Assertions may slow down Spaces operation by up to 30%, but are useful to contain the error.

Then:
- divert the output of your program to a file, e.g. `red myscript.red |tee log` or `red myscript.red >log`
- run the script until the error occurs
- inspect the `log` file: usually the *first* failed assertion is the cause of misbehavior

Assertions are assumptions about how my code works. They can often fail if something is misused though. E.g. you assign a string to `/draw` facet, or an object to `/content` facet, or trying to measure the size of an infinite grid. In time, when design solidifies, most of that should become error messages, but we're not there yet.

### Debug output

Is very helpful in nailing down the issue. E.g. Red tells you that `none` is unexpected in a Draw block. How do you know which one it is? You turn `draw` debugging and it will tell you in the log. 

In [`everything.red`](everything.red) there's a whole bunch of commented out debug directives:
```
; #debug on											;-- general (unspecialized) debug logs
; #debug set draw									;-- turn on to see what space produces draw errors
; #debug set profile								;-- turn on to see rendering and other times
; #debug set cache 									;-- turn on to see what gets cached (can be a lot of output)
; #debug set sizing 								;-- turn on to see how spaces adapt to their canvas sizes
; #debug set focus									;-- turn on to see focus changes and errors
; #debug set events									;-- turn on to see what events get dispatched by hosts
; #debug set styles									;-- turn on to see which styles get applied
```
Uncomment relevant item, run your script and see if there's a clue in the log.

For `profile` output, add `prof/show` before exit or at the point where you want the output. `prof/reset` can be used to reset stats. E.g. load during initialization can be different from load during usage, so it makes sense to call `prof/show prof/reset` after the `view/no-wait` call to see initialization phase, then `prof/show` after `do-events` loop quits to see the usage phase. It also makes sense sometimes to do `prof/show prof/reset` every one or few seconds in `on-time` actor, to have smaller profiling slices.

`debug-draw` command can be used to bring up GUI where you can inspect the spaces tree and look of each space in the tree.

### Inspecting your data

Biggest issue with this comes from spaces using words for links to other spaces, not objects. So usual `space-a/space-b/space-c` approach doesn't work.

Spaces console (that is run by `run.bat` or `red console.red`) automatically converts such paths to those understood by Red, so give it a try. But it may create other issues, as it's not a bug-free hack. In normal Red console, after including `everything.red`, same effect can be achieved with `do fix-paths [..code..]`. Also Red [`get` bugs](https://github.com/red/red/issues/4988) may make the experience much worse that it should be.

Inspect data at the point in the code where it's relevant. In event handlers, styles, etc. `??~` is a variant of `??` that does not expand objects, to keep the output small. `probe~` is a variants of `probe` with the same behavior. Data will be auto formatted by `probe~` using `prettify` function, which helps with unformatted/generated block data, but sometimes messes formatted data a bit.

`dorc` (short for `do read-clipboard`) command can be used to evaluate code from the clipboard without messing up console's history. I use it a lot.

### Test your widgets in [VID/S Polygon](programs/vids-polygon.red)

Put them into containers, e.g. into a `row` inside a `column`, and see how they work with automatic sizing. Try resizing the window.
