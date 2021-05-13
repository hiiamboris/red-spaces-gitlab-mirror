# Red Spaces Quick Start Tutorial

Will guide you through the basics required to use Spaces in your code.

[[_TOC_]]

## What's this

[Red language](http://red-lang.org/) comes with a set of OS-native widgets - [Faces](https://w.red-lang.org/en/view/#face-types).\
They're great: familiar look-n-feel, respect for user settings, speed, etc.\
But they're limited: simplistic, not customizable, portability goes down with the number of features, Red support for them varies between platforms, and is often packed with bugs due to complexity of OS APIs.

To provide for the need, this project introduces [Draw](https://w.red-lang.org/en/draw)-based widgets into Red.\
These widgets are called Spaces. Name comes from the fact that each widget is a separate *coordinate space* that knows how to draw itself.

Spaces provide infrastructure and model using which you can:
- leverage fully portable advanced widgets (like `grid-view` with infinite data)
- build custom web-like UI with only a fraction of effort
- scale, rotate or distort the UI, yet still process pointer events properly
- animate the UI or create 2D games

## Setup

Prerequisites: [Red](http://www.red-lang.org/p/download.html) (only nightly builds!!), [Git](https://git-scm.com/downloads)

Spaces depend on the helpful functions & macros from [mezz warehouse](https://gitlab.com/hiiamboris/red-mezz-warehouse). So, in your favorite directory, run:
```
git clone https://gitlab.com/hiiamboris/red-mezz-warehouse common
git clone https://gitlab.com/hiiamboris/red-spaces
```

<details>
	<summary>
		If you would prefer not to mess with Git, do it your way, just ensure a file structure similar to the following is created:
	</summary>

```
%red-spaces/
%red-spaces/auxi.red 
%red-spaces/comments 
%red-spaces/creators.md 
%red-spaces/debug-helpers.red 
%red-spaces/events.red 
%red-spaces/everything.red 
%red-spaces/focus.red 
%red-spaces/hittest.red 
%red-spaces/pen-test.red 
%red-spaces/quickstart.md 
%red-spaces/README.md 
%red-spaces/reference.md 
%red-spaces/single-click.red 
%red-spaces/spaces.red 
%red-spaces/standard-handlers.red 
%red-spaces/styles.red 
%red-spaces/tabbing.red 
%red-spaces/timers.red 
%red-spaces/traversal.red 

%red-spaces/tests/ 
%red-spaces/tests/grid-test1.red 
%red-spaces/tests/grid-test2.red 
%red-spaces/tests/grid-test3.red 
%red-spaces/tests/grid-test4.red 
%red-spaces/tests/grid-test5.red 
%red-spaces/tests/grid-test6.red 
%red-spaces/tests/grid-test7.red 
%red-spaces/tests/list-test.red 
%red-spaces/tests/README.md 
%red-spaces/tests/scrollbars-test.red 
%red-spaces/tests/spiral-test.red 
%red-spaces/tests/web-test.red

%common/
%common/apply.red 
%common/assert.red 
%common/bind-only.red 
%common/bmatch.red 
%common/catchers.red 
%common/clock-each.red 
%common/clock.red 
%common/collect-set-words.red 
%common/composite.md 
%common/composite.red 
%common/contrast-with.red 
%common/count.red 
%common/debug.red 
%common/do-atomic.red 
%common/do-queued-events.red 
%common/do-unseen.red 
%common/embed-image.red 
%common/error-macro.red 
%common/everything.red 
%common/expect.red 
%common/explore.red 
%common/extremi.red 
%common/for-each.red 
%common/format-number.red 
%common/format-readable.red 
%common/forparse.red 
%common/glob-test.red 
%common/glob.md 
%common/glob.red 
%common/is-face.red 
%common/keep-type.red 
%common/map-each.red 
%common/modulo.red 
%common/prettify.red 
%common/print-macro.red 
%common/profiling.red 
%common/README.md 
%common/relativity.red 
%common/reshape.md 
%common/reshape.red 
%common/scrollpanel-test.red 
%common/scrollpanel.md 
%common/scrollpanel.red 
%common/selective-catch.red 
%common/setters.red 
%common/show-deep-trace.red 
%common/show-trace.red 
%common/smartload.red 
%common/stepwise-func.red 
%common/stepwise-macro.red 
%common/table.md 
%common/table.red 
%common/tabs.red 
%common/timestamp.red 
%common/trace-deep.red 
%common/trace.red 
%common/with.red 
%common/xyloop.red
```

</details>




## Hello world

Create the following `hello-space.red` script:

```
Red [needs: view]						;) we need the View module to be able to show graphics

recycle/off								;) without this - often crashes on heisenbugs :(

#include %red-spaces/everything.red		;) add Spaces to the current program

view [
	host [								;) create a Host face that can contain spaces
		list with [axis: 'y] [			;) draw a vertical list on the Host
			paragraph with [text: "Hello, space!"]
			button with [data: "OK" command: [quit]]
		]
	]
]
```

Now all you need to do is ensure you've written `#include` path to where you've put the actual `red-spaces` directory, and run the script: `red hello-space.red`

![](https://i.gyazo.com/9218e54a2703bae245b87798e9d42c51.png)

A few notes:

- Later this example will become much simpler once layout work is completed. For now it just shows how spaces can be embedded into [VID](https://doc.red-lang.org/en/vid.html). Right after `host [` VID ends and [spaces layout DSL](#layout-dsl) begins.
- In the example above you might have noticed that I never specified `list/size`. Most spaces will automatically adjust their `/size` facet when drawn. `list` adjusts it's size to fit it's whole content.
- *`host` uses it's `rate` and `draw` facets internally, requires `all-over` flag to be set, but the other facets can be repurposed as you see fit.*

<details>
	<summary>
		The same example can also be written on a lower level, without VID, although requires better knowledge of spaces internals
	</summary>

```
Red [needs: view]						;) we need the View module to be able to show graphics

recycle/off								;) without this - often crashes on heisenbugs :(

#include %red-spaces/everything.red		;) add Spaces to the current program

list: make-space 'list [				;) make-space is used to instantiate spaces
	axis: 'y							;) lists can be horizontal(x) or vertical(y)

	item-list: reduce [					;) item-list is a block of NAMES of spaces

		make-space/name 'paragraph [	;) each make-space/name returns a name referring to an object
			text: "Hello, space!"		;) like `make prototype [spec..]`, make-space allows to define facets
		]
		make-space/name 'button [
			data: "OK" command: [quit]
		]
	]
]

host: make-face 'host					;) host face we need to draw spaces on
host/space:  'list						;) host must have exactly one space attached to it - here it's `list`
host/draw:   render host				;) `render` returns a list of draw commands, but also sets the /size facet of spaces
host/size:   list/size					;) now we know how big host face we need from previously set list/size
host/offset: 10x10						;) apply default VID margin

window: make-face 'window				;) create window to put host into
window/pane: reduce [host]				;) add host to it
window/size: host/size + 20x20			;) add default VID margins to host/size to infer window/size

show window								;) finally, we display the layout
set-focus host							;) focus host for it to receive keyboard events
do-events								;) enter View event loop
```

</details>




## Layout DSL

Will be documented once it's finished.\
Right now, just the bare minimum: 
- style name
- (optionally) followed by `with [code to evaluate]`
- (optionally) followed by `[list of inner spaces]` - for containers like `list` (TODO: `grid` too)

See [the example above](#hello-world).




## Styling

By default, spaces styles are minimalistic and adhere to the theme of your OS. However you can fully customize the look of any space.

Spaces are designed in such a way that their logic is separated from UI/UX. Styles are loaded from the [`styles.red`](styles.red) script. Until I decide on a user-facing styling interface, you can just edit `styles.red` directly or copy it under a different name and load after you've loaded `everything.red`.

### Style definition

Examples:
```
paragraph [..style description..]
list/item [..style description..]
```

Style definition starts with a **scope**. Scope is either:
- a word (name of the space you feed to `make-space`)
- or a path (consisting of such names and enforcing a given hierarchy)

In either case, when looking up a style for each particular space, full hierarchical path in the space tree is scanned for this word or path. When found, style applies. E.g. `list/item` only styles `item`s that have `list` as their parent space, and has bigger priority than just `item` style.

After the scope, a block with style description should follow.

<details>
	<summary>
		Hierarchical path usually looks like this: `host/list/item`. You can discover those paths for any given host face using the `probe list-*aces anonymize 'host host-face` command.
	</summary>

```
>> view/no-wait [
[    	host-face: host focus [
[    		list with [axis: 'y] [
[    			paragraph with [text: "Hello, space!"]
[    			button with [data: "OK" command: [quit]]
[    		]
[    	]
[    ]
>> probe list-*aces anonymize 'host host-face
[
    host 
    host/list 
    host/list/paragraph 
    host/list/button 
    host/list/button/paragraph
]
```

`host` is the root style that allows one to define style common for all spaces. E.g. line-width or fill-pen. The other words are the names of the spaces.

</details>

<details>
	<summary>
		How style lookup works
	</summary>

Lookup order is "specific-to-generic". E.g. for path = `host/list-view/list/item/paragraph`:
```
host/list-view/list/item/paragraph
     list-view/list/item/paragraph
               list/item/paragraph
                    item/paragraph
                         paragraph
```
I.e. if we define both `list/item/paragraph` and `paragraph` then the former (more specific) takes precedence over latter (generic). Specific styles override the generic ones (instead of adding them together).

Thus styles apply widely by default, but can be specialized. As opposed to assigning a style to each object separately by default and then making effort to cover more.

</details>


Styles are defined using two syntaxes: simple and free.

#### Simple syntax

In this form, style description is a block of [Draw commands](https://w.red-lang.org/en/draw/#draw-commands)
```
list/item [[pen cyan]]

paragraph [[
	(self/font: serif-12 ())
	pen blue
]]
```
Simple styles are applied in 3 steps:

1. Description is bound to the space object and *composed*.

   This allows one to set various space facets before drawing it. Like above `/font` facet is provided.\
   Draw is quite limited: e.g. you can't "ask" what current pen color is, to modify it, and you can't set font for rich-text using "font" command, and so on. Composition is aimed to empower styles while still keeping them short.\
   Don't forget to add `()` at the end of composition paren if you don't want it's output to be inserted into the draw block.

2. Space's `/draw` function is called to get a list of commands to render it.

3. Composed block (1) is inserted *before* the Draw commands (2).

<details>
	<summary>
	Advanced example: drunken scrollbars used in some of [the tests](tests/README.md)
	</summary>

```
set-style 'back-arrow  [rotate (angle) (size / 2)]
set-style 'forth-arrow [rotate (angle) (size / 2)]
set-style 'thumb [translate (size * 0x1 / 2) skew (angle / -2) translate (size * 0x-1 / 2)]
```
Where `angle` is updated 3 times per sec as:
```
angle: pick [0 -13 -20 -13 0 13 20 13] (counter: counter + 1) % 8 + 1
```
Such power can be held in just 2-3 lines! :D

</details>


#### Free syntax

<details>
	<summary>
	At first I tried a simpler model: `[(style prefix) (space's draw commands) (style suffix)]`. But it turned out to be too limited.
	</summary>

Simple example - a button (or any surface that's autosized and has text content):
1. Style sets font, font affects the final size
2. Final size is used to draw background frame for the text
3. Background should be drawn before the text or text will become invisible

These constraints cannot be satisfied in this model unless space is rendered twice - first time to obtain the size, second time to insert background. But rendering is the most expensive operation performed, and I didn't want to hinder the responsive time.

</details>

In free syntax, style description is a function declaration. Example:
```
button [
	function [btn] [
		drawn: btn/draw
		bgnd: either btn/pushed? [svmc/text + 0.0.0.120]['off]
		if focused? [
			focus: compose/deep [
				line-width 1
				fill-pen off
		        pen pattern 4x4 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0  8x8  fill-pen (svmc/panel) box 1x0 5x1 box 1x5 5x8  box 0x1 1x5 box 5x1  8x5]
				box 4x4 (btn/size - 4) (max 0 btn/rounding - 2)
			]
		]
		compose/only [
			fill-pen (bgnd)
			push (drawn)
			(any [focus ()])
		]
	]
]
```
Such function is called with a space object as it's (only) argument and it should return the block of draw commands. It can (and should) use the `/draw` facet of space to render it properly (like `btn/draw` above), but it is able to combine the output in any way and modify any facets in any order.

This function's output is used unmodified to draw the space.

<details>
	<summary>
When it makes sense to draw only a portion of a space (e.g. it's big), styling function should support the `/only` refinement.
</summary>

Spec: `function [space /only xy1 [pair! none!] xy2 [pair! none!] [...]`

It should not however take `only` value into account. Instead it should check if `xy1` and `xy2` are `none` or not. `none` means "unspecified" and implies rendering of the whole space area.

If such function calls `space/draw`, the call should look like `space/draw/only xy1 xy2`. 

 </details>

#### Flags

- `focused?` is a function that returns `true` inside a style that has focus. As in the example above, it can be used to indicate focused state.
- spaces may have their own flags, e.g. `/pushed?` flag of a button

### Defining behavior

- non-standard or extended behavior for standard styles
- behavior of custom styles

Core logic of each space is (and should be) implemented in it's source code. Standard styles are currently presented in the [`spaces.red` file](spaces.red), although later this file will likely be split into smaller ones.

But how each space reacts to events is a different matter. Event handlers for standard styles are defined in the [`standard-handlers.red` file](standard-handlers.red). Event handlers are meant to be easy to tune manually.

Example behavior definition using event handler description DSL:
```
define-handlers [									;) `define-handlers` is used to define events
	inf-scrollable: extends 'scrollable [			;) `extends` copies event handlers from another space
		on-down [space path event] [				;) event names follow those of View
			if update? [space/roll]					;) `roll` moves the window inside an infinite space
		]
		on-key-down [space path event] [			;) these handlers do not override those of `scrollable`!
			if update? [space/roll]					;) they are called after the inherited ones
		]
		roll-timer: [								;) roll-timer is a timer space owned by each inf-scrollable
			on-time [space path event delay] [		;) it has it's own event handler
				space: get path/-1					;) path/-1 is the outer space (inf-scrollable)
				if space/roll [update]
			]
		]
	]
]
```

Event handler description DSL quick reference:

| Example | Syntax | Description |
| - | - | - |
| `inf-scrollable: [...]` | `set-word! block!` or `set-word! 'extends lit-word! block!` | Defines events for spaces with the given name, optional `extends` modifier inherits handlers from another space. Can define handlers for spaces belonging to other spaces (like `roll-timer:` above) |
| `on-key-down [space path event] [...]` | `word! block! block!` | Defines handler for a specific event. Internally uses `function` constructor, so inner set-words are collected. |

#### Event handler spec

Handler spec almost always takes 3 arguments: `space path event`. Only `on-time` event accepts an additional `delay` argument.\ It's possible to provide typesets: `space [object!] path [block!] event [event! none!] delay [percent!]`

| usual name | accepted types | description |
|-|-|-|
| `space` | `object!` | Space object that receives the event. Convenience shortcut, that equals `get path/1` |
| `path`  | `block!` | Path in the tree of faces, `at` the index of current space. Can be of 2 formats described below. |
| `event` | `event!` or `none!` | View event that triggered the handler. Can be `none` for `focus`/`unfocus` events, because they do not come from View, but are generated internally. |
| `delay` | `percent!` | `0%` is ideal value. But timers do not get called at a precise time. They can be called early (`delay < 0%`), but usually they are late (`delay > 0%`). `delay = 100%` means *it's late by one timer period*. This value can be used to produce smoother animations. |

#### Path in the tree

As there are no `/parent` or `/pane` facets in spaces, *path* is used to orient the event handler inside the space tree.

Path has 2 formats:
1. Block of words, each word is a name of the space and refers to it's object. Used by all non-pointer events: keyboard, timer, focus, etc.
   - thus, `space = get path/1` is the space object for which the event handler was defined
   - `get path/-1` is the parent object
   - `get path/2` is a child object (possible e.g. if child space is *focusable* but did not process the key)
   - `get path/3` is an inner child object, etc.
   - since it's a block, one can write something like: `set [parent: space: child: sub-child:] reduce back path`
2. Block of word + pair tuples. Used by pointer events: `over wheel up mid-up alt-up aux-up down mid-down alt-down aux-down click dbl-click`
   - `space = get path/1` is still true
   - `path/2` is the pointer coordinate inside this space's coordinate system
   - `get path/-2` is the parent object
   - `path/-1` is the pointer coordinate inside parent's coordinate system
   - `get path/3` is the child object, `path/4` - pointer coordinate...
   - example: `[list-view 210x392 hscroll 210x8 thumb 196x8]`

By accessing parent object, child handlers can fetch info or make changes, like the `roll-timer` above calls a function from it's parent to affect it.

Path received by the handler is relative to the space that defined it. E.g. for `screen/window/base/list-view/thumb`, if `list-view` handles the event then `path` is `skip [screen window base list-view thumb] 3`

<details>
	<summary>
	In the same way child spaces in the path tell the parent handler that interaction is made with one of it's children. E.g. `scrollable` space's handlers know if interaction is made with a scroller's thumb or one of the arrows.
	</summary>

Snippet from `scrollable` that uses `item` and `subitem` to refer to it's children targeted by the pointer:
```
scrollable: [
	on-down [space path event] [
		set [_: _: item: _: subitem:] path
		case [
			find [hscroll vscroll] item [					;-- move or start dragging
				move-by: :scrollable-space/move-by
				axis: select get item 'axis
				switch subitem [
					forth-arrow [move-by space 'line 'forth axis  update]
					back-arrow  [move-by space 'line 'back  axis  update]
					forth-page  [move-by space 'page 'forth axis  update]
					back-page   [move-by space 'page 'back  axis  update]
				]
				start-drag/with path space/origin
			]
			item = space/content [
				start-drag/with path space/origin
				pass
			]
		]
	]
]
```

</details>

#### Timers

Spaces that define `/rate` facet and `on-time:` handler can receive timer events.

Timer event handlers have an extra argument: `delay [percent!]`, meaning *delay from the expected time* `[-100% .. can be big]`. It can be used to make animations more smooth.

E.g. if animation moves a sprite by 50px every 50ms:
- `delay = 100%` means it should move by 50+50=100px, because timer skipped an event and coming late
- `delay = -30%` means is should move by 50-15=35px, because timer fired too early

Timer handlers should be prepared to handle huge delays, possible when device lagged or just woke from sleep (e.g. by ignoring them).

Delay bias is accumulated internally and event system automatically makes more delayed timers fire more often until bias is zeroed (possible up to 50-55 fps, after which Windows' native timers can't keep up anymore). This is done to best achieve a desired framerate, regardless of whether handler handles the `delay` in any way.


#### Previewes and finalizers

Event handlers are divided into 3 stacks (called in this order obviously):
- previewers (e.g. to focus a space on clicks, and still process the click)
- normal handlers (described above)
- finalizers (e.g. to catch Tab key if it wasn't processed and move focus)

Previewers and finalizers help modularize the event system. E.g. [tabbing](tabbing.red), [hovering](hovering.red), [single click event emulation](single-click.red) are separate files that are added on top of the core event system and are not required for it's operation.

<details>
	<summary>Definition API</summary>

```
>> ? register-previewer
USAGE:
     REGISTER-PREVIEWER types handler

DESCRIPTION: 
     Register a previewer in the event chain; remove previous instances. 
     REGISTER-PREVIEWER is a function! value.

ARGUMENTS:
     types        [block!] {List of event/type words that this HANDLER supports.}
     handler      [function!] "func [space path event]."

>> ? register-finalizer
USAGE:
     REGISTER-FINALIZER types handler

DESCRIPTION: 
     Register a finalizer in the event chain; remove previous instances. 
     REGISTER-FINALIZER is a function! value.

ARGUMENTS:
     types        [block!] {List of event/type words that this HANDLER supports.}
     handler      [function!] "func [space path event]."
```

Their spec follows that of normal event handlers, the only difference is there is no `delay` argument.

For examples see [`tabbing.red`](tabbing.red), [`single-click.red`](single-click.red), [`hovering.red`](hovering.red), [`focus.red`](focus.red)

</details>


#### Commands

A set of commands is available to each event handler, implementing the idea of [REP 80](https://github.com/red/REP/issues/80) ). Compared to *View actors*, there's no risk of accidentally returning something we didn't want to and wreaking havoc upon the whole program and then making it freeze.

| command | returned value | description |
|-|-|-|
| update  | N/A    | schedules redraw of the host face (in case handler changes smth that affects visual appearance) |
| update? | logic! | true if host is marked for redraw while processing the current event (maybe by previously called handlers), false by default |
| pass    | N/A    | tells that event should be propagated to the next handler (in case current handler does not want to process this event) |
| stop    | N/A    | tells the opposite: event is processed and should not be passed to other handlers |
| stop?   | logic! | true if event can be passed further |

<details>
	<summary>
		`stop?` pipeline deserves special mention
	</summary>

- `stop?: false` is set before calling previewers. Previewers can use `stop` command to stop the event from reaching normal event handlers
- `stop?: true` is set before entering *every* normal event handler, which may call `pass` to pass it further. If it does not, event won't be passed to other normal handlers
- finalizers may inspect `stop?` state to only react to events (e.g. keys - tabbing module only reacts to Tab presses not processed in other handlers)
- previewers and finalizers are all called regardless of this flag's state (cannot be blocked)

</details>

#### Event lookup order

<details>
	<summary>
		Is two-dimensional: *outer before inner*, then *specific before generic*
	</summary>

E.g. if hittest returns `[list-view 210x392 hscroll 210x8 thumb 196x8]`, and we reduce that to `list-view/hscroll/thumb` then the order would be:
```
list-view
list-view/hscroll
          hscroll
list-view/hscroll/thumb
          hscroll/thumb
                  thumb
```
I.e. `list-view` gets an upper hand and it can stop the event from reaching it's children. Then `hscroll` then finally `thumb`. But event handlers written for `list-view/hscroll/thumb` get precedence over generic `thumb` when present.

In this example, if `list-view/hscroll` handler calls `pass` command, the event gets into `hscroll` handler. Thus specific handlers may extend generic handlers and only worry about their own aspects.

</details>

This path comes from:
- for pointer events from `hittest` function (called internally by `host`)
- for keyboard events and focus/unfocus - from `keyboard/focus` value (but only space types listed in `keyboard/focusable` can receive keyboard events)
- for timer events - from tree iteration using `list-spaces`

<details>
	<summary>
		Define events for paths to ensure hierarchy.
	</summary>

E.g. if event is defined for `list-view/hscroll/thumb`, `thumb` space that receives it will be able to access `hscroll` as `path/-1` and `list-view` as `path/-2` and never worry that it might have been used inside another space. Another way to do that is define events for `list-view` and inspect if `path/2 = 'hscroll` and `path/3 = 'thumb`. The choice is the matter of convenience.

</details>

<details>
	<summary>
Normal timer events handlers cannot block each other: they always get triggered.
	</summary>

If a child space sets a timer, parent has nothing to do with it. Timer handler still gets evaluated, whether `stop` command was called or not.

Previewers however can use the `stop` command to stop the event from reaching all normal timer event handlers.

</details>

#### Dragging

<details>
	<summary>
Current API (not yet mature enough) - `start-drag`, `stop-drag`, `dragging?`, `drag-offset`, `drag-parameter`, `drag-path`
</summary>

```
>> ? events/start-drag
USAGE:
     EVENTS/START-DRAG path

DESCRIPTION: 
     Start dragging marking the initial state by PATH. 
     EVENTS/START-DRAG is a function! value.

ARGUMENTS:
     path         [path! block!] 

REFINEMENTS:
     /with        => 
        param        [any-type!] "Attach any data to the dragging state."

>> ? events/stop-drag
USAGE:
     EVENTS/STOP-DRAG 

DESCRIPTION: 
     Stop dragging; return truthy if stopped, none otherwise. 
     EVENTS/STOP-DRAG is a function! value.

>> drag-in drag-offset drag-parameter drag-path dragging?
>> ? events/dragging?
USAGE:
     EVENTS/DRAGGING? 

DESCRIPTION: 
     EVENTS/DRAGGING? is a function! value.

>> ? events/drag-path
USAGE:
     EVENTS/DRAG-PATH 

DESCRIPTION: 
     Return path that started dragging (or none). 
     EVENTS/DRAG-PATH is a function! value.

>> ? events/drag-parameter
USAGE:
     EVENTS/DRAG-PARAMETER 

DESCRIPTION: 
     Fetch the user data attached to the dragging state. 
     EVENTS/DRAG-PARAMETER is a function! value.

>> ? events/drag-offset
USAGE:
     EVENTS/DRAG-OFFSET path

DESCRIPTION: 
     Get current dragging offset (or none if not dragging). 
     EVENTS/DRAG-OFFSET is a function! value.

ARGUMENTS:
     path         [path! block!] {index of PATH controls the space to which offset will be relative to.}

```

`events/` prefix is not needed inside event handlers.

</details>

## Further reading

What you will want to know while working with spaces is which facets each space supports and how to use them. This info is found in the [Widget Reference](reference.md).

There's a bunch of [test scripts](tests/README.md) that can serve as a study material and as templates.

Later proper templates will be provided for the common use cases.

