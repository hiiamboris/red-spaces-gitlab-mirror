# PRELIMINARY DOCUMENTATION FOR DRAW-BASED WIDGET LIB FOR [RED](http://red-lang.org/)

## EXAMPLES (clickable)

| Spiral editable field | Table | Infinite list of items *of varying size* |
|---|---|---|
| ![](https://i.gyazo.com/74d4e22f7480bda9f5c2df8e11c6bfb5.gif) | ![](https://i.gyazo.com/5f16371407967a41e16bb6f601201a70.gif) | ![](https://i.gyazo.com/856724cebae6a5967a9eb96142dd35de.gif) |

Layouts currently look like this (needs more design & Parse work to make it on par with View layout):

- Spiral:
```
host [
	rotor [
		list with [axis: 'y] [
			spiral with [field/text: lorem10 size: 300x300]
		]
	]
]
```

- Table:
```
host [
	rotor [
		list with [axis: 'y] [
			field with [text: "field"]
			list-view with [size: 200x100 source: list1d]
			button with [data: "button"]
			table with [size: 200x200 source: list2d]
		]
	]
]
```

- List:
```
host [list-view with [size: 300x400 source: list1d]]
```

Drunken scrollbars are done via [Styling](#styling):
```
set-style 'back-arrow  [rotate (angle) (size / 2)]
set-style 'forth-arrow [rotate (angle) (size / 2)]
set-style 'thumb [translate (size * 0x1 / 2) skew (angle / -2) translate (size * 0x-1 / 2)]
```
Where `angle` is updated 3 times per sec as:
```
angle: pick [0 -13 -20 -13 0 13 20 13] (counter: counter + 1) % 8 + 1
```

Wavy table rows are done similarly:
```
set-style 'table/headers [(t: now/time/precise phase: (to float! t) % 12 * 30 ())]  ;) initial phase (can also be done in timer)
set-style 'row [(phase: phase + 60  margin/x: to 1 5 * sine phase ())]              ;) phase changes with each row
```

Such power can be held in just 2-3 lines! :D

Spiral Field demo reuses the normal rectangular `field` space (that contains all the keyboard logic and everything) by transforming hittest coordinates in a spiral way. Rendering logic of course had to be rewritten because such complex transformations are far beyond Draw capabilities. That's why it's a bit laggy: it renders each character individually.

Table is far from being complete, but also demonstrates how events are handled naturally even on rotated layout.

Infinite List's trick is that when items vary in height, it's hard to provide uniform scrolling (naive desings would scroll at item granularity) and at the same time make it respond in real time to user actions.

## How to try it out?

Setup, in your favorite directory:
```
git clone https://gitlab.com/hiiamboris/red-mezz-warehouse common
git clone https://gitlab.com/hiiamboris/red-spaces
```
To run e.g. `spiral-test` demo:
```
cd red-spaces
red spiral-test.red
```


## Preface

We need portable table widget.<br>
Table is a composite widget: includes scrollbars, scrollable panel, infinite list, row, labels, fields, images, etc.<br>
Making *just* an ad-hoc table = stupid.<br>
Building a set of reusable portable widgets = way to go.<br>
This means a common design underlining all widgets.

# Status

**Preliminary work, PoC. Major design changes possible. High risk of breaking changes. Not very high-level yet.**

| By component | State |
| --- | --- |
| Widget architecture | Still many open design questions, big changes possible | 
| Events | Mostly stable |
| Timers | Stable | 
| Styling | Mostly stable, but looks a bit cryptic, needs simpler interface |
| Focus model | Mostly stable |
| [Tabbing](https://en.wikipedia.org/wiki/Tabbing_navigation) | Breaks from time to time, but working |
| [Spatial navigation](https://en.wikipedia.org/wiki/Spatial_navigation) | Not implemented |
| Resize model | Need a powerful simple design idea, ideally that would apply to faces too |
| Layout | Embedded into View layout seamlessly, but very basic: only accepts space names and `with` |
| Table | Missing advanced features like cells span, columns dragging, sorting, filtering |

# Goals

- make complex widgets portable and accessible
- make it possible to create custom widgets *easily*
- implement a set of complex widgets in their basic form, to serve as templates
- test various UI framework ideas, see how they work and if they could improve View
- make styling of UI an easy and fun undertaking
- provide a basis for dynamic animated UIs (animation dialects and 2D game engines may be based upon this project)

# Architecture

This lists what is mostly cast in stone. Still many design questions need answering (see [comments](comments) file).

In essence, what is a UI? A dialogue.<br>
Program communicates info to the human by drawing things on display.<br>
Human traditionally answers (interacts) via keyboard or any pointing device (voice recognition left alone for simplicity). That's why UI is interactive.

This design provides 3 basic needs:
- Spaces (how to display things)
- Hittesting via `into` and `map` (how to interpret clicks, gestures, etc)
- Focus model (how to interpret keyboard input)

Everything else is an implementation detail, with the aim of making programmer's and user's lives easier.

## Space

Draw-based widget I call SPACE.
Reason: it is basically just a coordinate space that knows how to draw itself.

Minimal space:
```
size: none or pair
draw: func []
```
Nothing else! `draw` tells how to render this space. `size` tells outside observers how big the render was.

**Quirk:** `size` is only available after a call to `draw`.

Some spaces have user-provided fixed size (e.g. `scrollable`), but this may change if I decide on a resizing model.

For other spaces (e.g. `list`) size is determined by it's content (e.g. items in the list).

**Quirk:** `size` is a volatile thing.

`size` may even depend on time so: whenever we read it, it's already outdated.<br>
However for most practical tasks we can think of `size` on the last rendered frame.<br>
When we click on any point, it's the last frame geometry that decides where that click lands to: what user sees (what was rendered) determines the behavior.

To make spaces more lightweight, optimal **definition model** is like this:
```
my-space-ctx: context [
	my-fun: function [space [object!] ...] [
		...lots of code...
	]

	my-space: make-space/block [
		my-fun: function [...] [my-space-ctx/my-fun self ...]		;) a shortcut
	]
]
```
This way, every instance of `my-space` carries only short dispatching code rather than copying all the big functions from it's template.


## Hierarchy

Just painting inner spaces = not enough. Need interactivity (e.g. for [hittesting](https://en.wikipedia.org/wiki/Hit-testing), tabbing):
- need to recognize spaces within other spaces
- need to support coordinate transformation (esp. for hittesting)
- need to know the order of inner spaces (esp. for tabbing)

Composite space (that "contains" other spaces) should be extended with *any* of:
```
into: func [xy [pair!] /force name [word!]] -> [word! pair!]
map: [
	word! [offset pair! size pair!]					;) e.g.: inner-name [offset 10x10 size 100x100]
	word! [offset pair! size pair!]
	...
]
```

**`into`:**
- takes a point in it's space's coordinate system
- determines which *inner* space this point maps to
- returns name of the inner space and a point in inner space's coordinate system
- when /force is true, it should return provided (by name) inner space even if the point is outside it (only required if this space wants to support dragging)

This allows for rotation, compression, reflection, anything. Can we make a "mirror" space that reflects another space along some axis? Easily.

**`map`:**

Is a block that tells which inner face occupies which region (offset & size) of this space.<br>
Order: first items get precedence in case of overlap.

Map is only good for rectangular geometry (in this case `into` is not needed and `map` is used for hittesting). But this is 95%+ of use cases.

`map` should be filled by each `draw` call. Before 1st call: what isn't drawn does not exist.

If `into` is provided, `map` is still required if space wants to support iteration over it's inner spaces (e.g. for tabbing). In this case `map` can contain any geometry or even only names of inner spaces: `[word! word! ...]`

Names in a `map` may repeat, but each should refer to a unique object.

**Quirk:** space always has a name (word)!

Everywhere in my design, if space `A` contains space `B` then `B` will be listed inside `A` as a *word, referring* to the object of `B`: `map` contains `B` word, `into` returns `B` word, etc.

Why need for name?
- styles are based on names
- events are dispatched by names
- what is focusable or not depends on it's name
- possible to repurpose a generic (e.g. `rectangle`) space by giving it a name (e.g. `thumb` of a `hscroll` or `vscroll`) - such space will behave and be styled differently (e.g. `rectangle` doesn't need events, but `thumb` may react)

Why `(get name) = object` rather than `object [name: ..]`?
- it makes easy to apply styles to whole classes of spaces by their names (see [styling](#styling) below)
- it makes easy to visualize (dump) the face/space tree
- if you've ever tried `?? my-face` you know it is a bad idea; with spaces however, output is always fully inspectable exactly because of this choice

Drawback: have to call `get` an extra round sometimes. But other way would have to `select .. 'name`, so no big deal.


## Styling

Style is: name -> block of Draw commands

Styles definitions are separate from the space definitions.

E.g. `paragraph [pen blue]`<br>
E.g. `hscroll/thumb [fill-pen yellow]`

**Quirk:** Style name is a path!

Example: face/space tree listing:
```
screen/window
screen/window/base
screen/window/base/list-view
screen/window/base/list-view/list
screen/window/base/list-view/list/item
screen/window/base/list-view/list/item/paragraph
screen/window/base/list-view/list/item
screen/window/base/list-view/list/item/paragraph
screen/window/base/list-view/list/item
screen/window/base/list-view/list/item/paragraph
screen/window/base/list-view/list/item
screen/window/base/list-view/list/item/paragraph
screen/window/base/list-view/list/item
screen/window/base/list-view/list/item/paragraph
screen/window/base/list-view/hscroll
screen/window/base/list-view/hscroll/back-arrow
screen/window/base/list-view/hscroll/back-page
screen/window/base/list-view/hscroll/thumb
screen/window/base/list-view/hscroll/forth-page
screen/window/base/list-view/hscroll/forth-arrow
screen/window/base/list-view/vscroll
screen/window/base/list-view/vscroll/back-arrow
screen/window/base/list-view/vscroll/back-page
screen/window/base/list-view/vscroll/thumb
screen/window/base/list-view/vscroll/forth-page
screen/window/base/list-view/vscroll/forth-arrow
screen/window/base/list-view/timer
screen/window/text
```
**Quirk:** `list` contains hundreds of `item`s, but `map` contains only visible 5 paragraphs (those we need to hittest against). Relates to [tabbing](#tabbing) as well.

Here, `base` is a face that contains a tree of spaces. Only spaces are styled (not faces).

**Quirk:** Style lookup order is "specific-to-generic". E.g. for path = `screen/window/base/list-view/list/item/paragraph`:
```
screen/window/base/list-view/list/item/paragraph
       window/base/list-view/list/item/paragraph
              base/list-view/list/item/paragraph
                   list-view/list/item/paragraph
                             list/item/paragraph
                                  item/paragraph
                                       paragraph
```
I.e. if we define both `list/item/paragraph` and `paragraph` then `list/item/paragraph` takes precedence over generic `paragraph` style as more specific one.

To have 2 `list-view`s with different sizes we would clone `list-view` style under a different name and give it the same set of event handlers.<br>
Thus styles apply widely by default, but can be specialized. As opposed to assigning a style to each object separately by default and then making effort to cover more.

**Two types of styles:**
- styles - inserted before whatever `draw` returns (to set pen, line-width, change size & font, paint background, etc)
- closures - inserted after (to post-decorate already drawn content, e.g. draw an overlay)

Draw only provides `pen`, `fill-pen`, `line-width` and some less useful primitives in terms of styling. Even `font` command can't be applied to `text` if `text` renders a rich-text layout. We need more than that, so...

**Quirk:** Styles are bound to the space object and composed. 

So it's possible to write `(self/size: new-size ())` or `(self/font: make font! [..] ())` to change space's properties before it's drawn.<br>
`()` is required to exclude the expression result from the final Draw block (or equivalently, `[]`) so we don't get Draw errors. Still looking for a way to make this prettier.

## Events

Defined similarly to styles, e.g.:
```
my-space [
	on-down [space path event] [...]
	on-key [space path event] [...]
]
```

Event handlers are divided into 3 stacks (called in this order obviously):
- previewers (e.g. to focus a space on clicks, and still process the click)
- normal handlers
- finalizers (e.g. to catch Tab key if it wasn't processed and move focus)

Event handlers are bound to a set of **commands** (implementing the idea of [REP 80](https://github.com/red/REP/issues/80) ):
```
update              -- marks parent face (host) to redraw after event is fully processed (we changed smth that affects visual appearance)
update?  -> logic!  -- true if marked for redraw (false by default)
pass                -- tells that event should be propagated to the next space in the chain (we examined it and decided not to process it)
stop                -- tells that we should not
stop?               -- true if we should not propagate it further into normal event handlers
```
- `stop?` is true upon entering any normal event handler, which may call `pass` if event should be propagated further
- `stop` is useful for previewers if they want to stop the event from reaching handlers
- previewers and finalizers are all called regardless of flags state (cannot be blocked)

Compared to *View actors*, there's no risk of accidentally returning something we didn't want to and wreaking havoc upon the whole program and then making it freeze.

**Quirk:** handlers bodies are `function`s, so they leak no words.

**Spec**

Previewers and finalizers have all the same spec:<br>
`function [space [object!] path [block!] event [event! none!]]`
- `space` is the object that this event relies to (analogous to `face` in actors)
- `path` has 2 formats, but anyway it's a chain of space names from the tree root down to it's inner spaces
- `event` is what View provides us with (may be `none` for synthesized events)

**Quirk:** Normal event handlers have varying spec, depending on event type.<br>
Usually: `function [space [object!] path [block!] event [event! none!]]`

**Quirk:** `path` has 2 formats:
- for pointer-related events, path is returned by hittest and it contains the whole history of coordinate system transformations: e.g. `[list-view 210x392 hscroll 210x8 thumb 196x8]` (word pair word pair ...). Each pair is a point in the space listed before it. Such path does not include parent *faces* for we don't hittest against them (would be extra effort to generate this info) but this may change in the future. `over wheel up mid-up alt-up aux-up down mid-down alt-down aux-down click dbl-click`
- for all other events, we have no offsets, so it's words only: `[screen window base list-view]`. Keyboard events (`key key-down key-up enter`) go into the *focused* space (so `path` should be equal to `keyboard/focus` up to index).

`path` is a *block* for convenience, so it can be reduced or decomposed like `set [a: b: c:] path`.

Timer event handlers have the spec:<br>
`function [space [object!] path [block!] event [event! none!] delay [percent!]]`<br>
See [Timers](#timers) on the meaning of delay.

**Quirk:** all `path`s are relative to the space that handles the event.

E.g. for `screen/window/base/list-view/thumb`, if `list-view` handles the event then `path = skip [screen window base list-view thumb] 3`

Thus, `space = get path/1` always holds true, `path/-1` and `path/-2` are possible parents and `path/2` and `path/3` are possible children (take care for pairs though). `space` thus is not strictly needed but it's a nice shortcut that saves a lot of `space: get path/1` lines.

`self` vs `space`: `self` could have been used instead to reduce the number of arguments, but since one event handler can handle events for hundreds of spaces, we would have to `bind` it before every call, which is too slow.

**Quirk:** event handler lookup order is two-dimensional. *Outer before inner*, then *specific before generic*

E.g. if hittest returns `[list-view 210x392 hscroll 210x8 thumb 196x8]`, and we reduce that to `list-view/hscroll/thumb` then the order would be:
```
list-view
list-view/hscroll
          hscroll
list-view/hscroll/thumb
          hscroll/thumb
                  thumb
```
I.e. `list-view` gets an upper hand and can stop the event from reaching it's children. Then `hscroll` then finally `thumb`. But event handlers written for `list-view/hscroll/thumb` get precedence over generic `thumb` when present.

In this example, if `list-view/hscroll` handler calls `pass`, the event gets into `hscroll` handler. Thus specific handlers may extend generic handlers and only worry about their own aspects.

I don't know yet if this O(n^2) will pose a threat, but presumably it'll be too short for that.



## Focus & Tabbing

Tabbing only possible into what's **visible** right now. 

Example: `table` (scrollable) contains 100000 `field`s inside (like mini-spreadsheet). If we press Tab in the last visible `field`:
- should it scroll the table and focus the next field? in this case we never tab out (our patience runs out before that) to reach other spaces
- or should it tab out of the table? in this case to reach the next field we would have to tab until we focus `table`, scroll it with arrows, then tab in until we reach the field we need (so, more work, but doable)

There's no ultimately right choice that I can see. 2nd option is chosen for simplicity and better fit for the current design. But 1st option can still be implemented using a previewer, where it's required.

**Tabbing order** is the order of the tree, i.e. defined by `map` order (in turn may be defined by `items` order in case of `list` space). `list-spaces` function can be used to visualize it (like the big listing in [Styling](#styling)).

Tree has 2 dimensions: outer/inner (depth-wise) and previous/next (sibling nodes).<br>
Forward order (Tab key) is defined as *outer->inner and previous->next*, e.g.:
```
list
list/item1
list/item2
other-space
```
Reverse order is defined as *inner->outer and next->previous*:
```
other-space
list/item2
list/item1
list
```
Because Shift-Tab should be a full reverse of Tab, same for any iteration, even though inner->outer part may cause some confusion.


## Timers

Spaces that define `rate:` facet and `on-time:` handler can receive timer events.

Timer event handlers have an extra argument: `delay [percent!]`. *Delay from the expected time* `[-100% .. can be big]`. It can be used to make animations more smooth.<br>
E.g. if animation moves a sprite by 50px every 50ms:
- `delay = 100%` means it should move by 50+50=100px, because timer skipped an event and coming late
- `delay = -30%` means is should move by 50-15=35px, because timer fired too early

Event handlers should be prepared to handle huge delays, possible when device lagged or just woke from sleep (e.g. by ignoring them).

Delay bias is accumulated internally and event system automatically makes more delayed timers fire more often until bias is zeroed (possible up to 50-55 fps, after which Windows' native timers can't keep up anymore). This is done to best achieve a desired framerate, even when handler does not handle the `delay`.


