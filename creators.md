# Red Spaces Widget Creators Guide

Will explain the architecture of Spaces and how to extend them.

[[_TOC_]]


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

Draw-based widget are called *spaces* because they are (separate) coordinate spaces that know how to draw itself.

Minimal space:
```
size: none! or pair!
draw: func [] -> block!
```
Nothing else! `draw` tells how to render this space. `size` tells outside observers how big the render was.

To make spaces more lightweight, optimal **definition model** looks like this:
```
my-space-context [									;) context for functions shared by all spaces of this type
	~: self											;) shortcut for the wrapping context
	my-fun: function [space [object!] ...] [		;) functions should accept space instance
		...lots of code...
	]

	spaces/my-space: make-space/block 'space [
		my-fun: function [...] [
			~/my-fun self ...						;) in-space function should delegate it's task to the shared function
		]
	]
]
```
This way, every instance of `my-space` carries only short dispatching code rather than copying all the big functions from it's template.

Building a space on top of another is done like this:
```
new-space-context [
	~: self											;) another shortcut - only affects new functions
	my-fun: function [space [object!] ...] [		;) another big task solver
		...lots of code...
	]

	spaces/new-space: make-space/block 'my-space [	;) extends previously defined 'my-space' type
		my-space-my-fun: :my-fun					;) old `my-fun` can be saved by prefixing it with a prototype name `my-space-`
		my-fun: function [...] [
			~/myfun self ...
			my-space-my-fun ...						;) new `my-fun` now can call the old one when it needs to
		]
	]
]
```

`my-space-context` and `new-space-context` names are not necessary: contexts can be anonymous. But functions from named contexts can be used by respective event handlers.

Instantiation of space type is done using [`make-space` function](reference.md#make-space).

Spaces can be created and rendered freely, but to properly use them and apply styles one needs a `host` face. It is based on the [`base` View widget](https://w.red-lang.org/en/view/#base), and provides event dispatching, styling and visual updates.

How to use `host` face is explained in [`quickstart`](quickstart.md). It should be rendered as `host/draw: render host` if out of order update is required, otherwise it takes care of updating itself on *next timer event* after one of the space event handlers called `update` command.

### Size

2 strategies are used (sometimes by the same space, e.g. [`image`](reference.md#image)):
- `size` is defined (fixed), `draw` adapts space's appearance to `size` (e.g. [`scrollable`](reference.md#scrollable)).
- `size` is determined by content, and `draw` sets it *after each frame*  (e.g. [`list`](reference.md#list)). Before the 1st call to `draw`, `size` can be `none`.

Automatic sizing strategy is not implemented yet, but will only affect the fixed sizes.

<details>
	<summary>
How does hittest work if `size` is volatile and may even depend on time itself?
</summary>

<br>
`size` for the last rendered frame determines the geometry for all pointer events land. New frame - new geometry. Layout can be moving, rotating, distorting, but what one sees is what one interacts with.

</details>


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
There is no `parent` facet. <i>Same</i> space object can be shared between various parents, or it can even be it's own child.
	</summary>

A tree nonetheless exists:
- root for spaces is the `host` face
- each space's children are listed in the `map`

Event handlers receive a path on this tree, so child spaces handlers can access their parents.

</details>


### into

Function that is used in hittesting only.

- takes a point in it's space's coordinate system
- determines which *inner* space this point lands to
- returns *name* of the inner space and a point in inner space's coordinate system
- when `name` argument is not `none`, it should return provided (by name) inner space even if the point lies outside it (only required if this space wants to support dragging). `/force` value should be ignored.

This allows for rotation, compression, reflection, anything. Can we make a "mirror" space that reflects another space along some axis? Easily.

`into` is not required for hittesting, it just makes it possible to use all these transformations on events. If all inner spaces are just boxes, `map` should be defined instead.

<details>
	<summary>
`into` does not provide tree iteration capability (e.g. for tabbing). If iteration is needed (e.g. inner spaces are focusable), then `map` should also be provided.
</summary>

<br>
Geometries in such `map` are ignored and can be absent or contain invalid/dummy/empty values, e.g.:
- `[inner-space [] ...]` (no offset or size)
- `[inner-space [offset 0x0 size 0x0] ...]` (dummy geometry)
- `[inner1 inner2 ...]` (no geometry)

</details>

### map

Is a block that tells which inner face occupies which region (offset & size) of this space.\
Order: first items get precedence in case of overlap. So `map` can be thought of a reverse Z-order: topmost child appears first in the map.

Map is only good for rectangular geometry (which is the majority of use cases anyway). In this case `into` is not needed and `map` is used for hittesting.

`map` should be filled by each `draw` call (or if it's constant - defined on space creation). Before the 1st `draw` call: what isn't drawn does not exist.

<details>
	<summary>
Names in the `map` may repeat (by spelling), but each should refer to a unique object.
	</summary>

<br>
Examples of that are `list` and `grid` styles that can contain hundreds of `item` or `cell` occurrences in their `map`. Each `item`/`cell` is styled using the same style, and shares same event handlers, but objects (`get item`/`get cell`) are not the same.

</details>

`map/child/size <> child/size` in general case: `map` defines it's geometry in parent's coordinates, while `child/size` is it's size in it's own coordinates.

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
Why `(get name) = object` rather than `object [name: ..]`?
</summary>

- listing the tree of spaces
- dumping particular spaces tree: if you've ever tried `?? my-face` you know it is a bad idea that will force you to kill the console; spaces however are always fully inspectable
- it makes inspectable style and event paths, which is helpful when debugging
- to test and evaluate an approach different to the one taken in View

Drawbacks:
- have to call `get` an extra round sometimes. But other way would have to `select .. 'name`, so no big deal.
- to fetch a deep subspace for inspection (e.g. `probe host/space/list/item`), such path has to be preprocessed.

I'm not totally against the alternative though, if more benefits will be discovered.

</details>


## Styles

Styles may influence or replace the Draw code used to render any space. See [`quickstart`](quickstart.md#styling) about how to write styles.

Spaces should include facets that affect their appearance, e.g. `margin` or `font`, and provide reasonable defaults. Those defaults may then be overridden in styles.

Each space must have a `draw` function (or inherit it), that defines it's look as generally as possible.\
A higher level `render` function applies styles and calls `draw`, so `draw` should not concern itself with styles.
```
USAGE:
     RENDER space

DESCRIPTION: 
     Return Draw code to draw a space or host face, after applying styles. 
     RENDER is a function! value.

ARGUMENTS:
     space        [word! object!] "Space name, or host face as object."

REFINEMENTS:
     /only        => Limit rendering area to [XY1,XY2] if space supports it.
        xy1          [pair! none!] 
        xy2          [pair! none!] 
```

Style functions (defined using [free syntax](quickstart.md#free-syntax)) should call `draw` and not `render`, because at that moment style is already applied.

Everywhere else `draw` should not be called directly (if only for debugging), and `render` should be used instead. Even `draw` function of composite spaces should call `render` for it's children, as otherwise child styles won't be applied.

If `draw` supports `/only xy1 xy2` refinement to draw only a selected region, it should not take `only` value into account. Instead it should check if `xy1` and `xy2` are `none` or not. `none` means "unspecified" and implies rendering of the whole space area.


## Events

Events handling makes space interactive. See [`quickstart`](quickstart.md#defining-behavior) about how to write event handlers. Space should include all necessary levers inside, and event handlers used only to operate these levers and be kept short and clean.

Key concepts:
- same event and handler names [as in View](https://w.red-lang.org/en/view/#events)
- `function` constructor is used to prevent set-words leakage
- handlers are function lists, not single functions
- receive path on the tree (see [`quickstart`](quickstart.md#path-in-the-tree))
- path is relative to the space for which the handler is defined
- previewers and finalizers for fine event flow control
- two-dimensional event handler lookup order (see [`quickstart`](quickstart.md#event-lookup-order))



### Function lists

*Faces:* single actor works on top of magic done in R/S or by the OS. It cannot override this magic and render the widget useless.\
*Spaces:* all magic is done by default event handlers, so they should not be overridden.

Every space/event combo is associated with a function list: default handler -> extension handler -> user handler... Handlers of extending spaces do not override handlers of spaces they are based on.

This list is evaluated sequentially from the first defined handler to the last one.

Individual handlers in this list cannot be blocked by `stop` command, only the whole list at once. So if original event handler receives an event, then all of it's extensions do too.



### Previewers and finalizers

[`Quickstart`](quickstart.md#previewes-and-finalizers) explains the basics and how to write one.

Key concepts:
- use masks to select events to respond to
- cannot be blocked via `stop` command
- can generate new events (see [event generation](#event-generation))
- evaluated in order from the first defined to the last defined


### Event generation

`events/dispatch` is the function that receives View events and decides how to handle them.

<details>
	<summary>
`events/process-event` is the function that can be called to pass emulated events into event handlers.
</summary>

```
>> ? events/process-event
USAGE:
     EVENTS/PROCESS-EVENT path event focused?

DESCRIPTION: 
     Process the EVENT calling all respective event handlers. 
     EVENTS/PROCESS-EVENT is a function! value.

ARGUMENTS:
     path         [block!] "Path on the space tree to lookup handlers in."
     event        [event!] "View event."
     focused?     [logic!] {Skip parents and go right into the innermost space.}
```
However this design is still in question (the `focused?` part). On one hand it helps omit the extra check in key event handlers: `unless single? path [pass exit]` would mostly be needed for parent handlers to pass down events meant for it's *focused* child. On another hand, now parents can't stop or inspect the event.

</details>

## Focus & Tabbing

Focus allows to direct keyboard events (`key key-down key-up enter`) into a particular "focused" space.

`keyboard/focus` holds the currently focused space. Focused space can be changed via:
- calling `focus-space` function directly (it accepts a tree path)
- clicking (`down mid-down alt-down aux-down dbl-click`) on a point that intersects with a *focusable* space
- [tabbing (module)](tabbing.red)

Focused space is a tree path. So for tabbing (and focus in general) to work properly, items in that path should not be discarded. If object in that path is no longer in it's parent's map, focus becomes invalid (which is equivalent to no focus).

Focusable space types are listed in `keyboard/focusable` block (new types can be added there at will).

Only *visible* spaces can be focused by tabbing or clicking, i.e. they must be present in the `map`s of their parents. `focus-space` doesn't have this limitation. If tabbing into a space outside of viewport is desired, spaces near the edge of the viewport should be put into the `map`.

<details>
	<summary>
<i>Tabbing order</i> is the order of the tree, i.e. defined by `map` order (in turn may be defined by `items` order in case of `list` space, etc.). `list-spaces` function can be used to visualize it.
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

Example code with a new focusable space:
```
#include %red-spaces/everything.red

spaces/my-space: make-space/block 'space [
	size: 50x50
	draw: [box 1x1 49x49]
]
append keyboard/focusable 'my-space

define-handlers [
	my-space: [on-key [space path event] [print event/key]]
]

view [host focus [my-space]]
```
Press Tab or click on the box space to focus it. Then it will print every key pressed.

