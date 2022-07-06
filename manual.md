---
gitea: none
include_toc: true
---

# Red Spaces Tinkerer's Manual

Will help you understand Spaces on deeper level to be able to alter how things work.

## Organization

**Key takeaways**:
- Spaces are organized as **a tree**: each parent has links to it's children in it's `/map` facet (e.g. `map: [child [offset 10x10 size 50x30]]`).
- There are **no** `/parent` or `/pane` facets to provide a link back.
- A **path** is used to specify the hierarchical relation of each space (e.g. `host/list/button/text`).
- Styles and event handlers look up specific sequence in the path to find a **match** (e.g. `list/button` will match the above path).

Path has 2 formats:
1. **Block** of **words**, each word is a name of the space and refers to it's object. Used by all **non-pointer** events: keyboard, timer, focus, etc.
   - thus, `space = get path/1` is the space object for which the event handler was defined
   - `get path/-1` is the parent object
   - `get path/2` is a child object (possible e.g. if child space is *focusable* but did not process the key)
   - `get path/3` is an inner child object, etc.
   - since it's a block, one can write something like: `set [parent: space: child: sub-child:] reduce back path`
2. **Block** of **word + pair tuples**. Used by **pointer events**: `over wheel up mid-up alt-up aux-up down mid-down alt-down aux-down click dbl-click`
   - `space = get path/1` is still true
   - `path/2` is the pointer coordinate inside this space's coordinate system
   - `get path/-2` is the parent object
   - `path/-1` is the pointer coordinate inside parent's coordinate system
   - `get path/3` is the child object, `path/4` - pointer coordinate...
   - example: `[list-view 210x392 hscroll 210x8 thumb 196x8]`

Format 1 describes the hierarchy, and is often written in this document using path (not block) **notation**, i.e. separated by slashes.

Tree paths can be discovered for any given layout face using the `dump-host-tree` function.

```
>> view/no-wait [
		face: host [
    		vlist [
    			text "Hello, space!"
    			button "OK" [quit]
    		]
    	]
    ]
>> dump-host-tree face
87x72      host
87x72      host/list
67x16      host/list/text
47x26      host/list/button
16x16      host/list/button/text
```




## Styling

By default, spaces styles are minimalistic and adhere to the theme of user's OS. However if you're making software for yourself only, or if you're certain users won't curse you for enforcing your taste on them, you can fully customize the look of any space.

Spaces are designed in such a way that their core **logic is separated from UI/UX**.

**Two** styling mechanisms are used:
- [VID/S styles](vids.md#style-definition) allow for some quick customization of features on per-widget basis.
- *template styles* (explained below) allow one to define a style for whole templates, globally. Such style is capable to fully redefine the look.


### Style definition

**Warning:** I'm not happy with this design, so it's likely to change in the future. 

Default styles are loaded from the [`styles.red`](styles.red) file.

New styles are currently created by `set-style` function:
```
>> ? set-style
USAGE:
     SET-STYLE name style

DESCRIPTION: 
     Define a named style. 
     SET-STYLE is a function! value.

ARGUMENTS:
     name         [word! path!] 
     style        [block! function!] 
```

For style to have effect, `name` argument should be either:
- a `word!` which should coincide with the space's name (which usually equals it's template name)
- a `path!` of such valid space names that will be matched against the tree path

Examples:
```
set-style 'paragraph ..style-descriptor..
set-style 'list/item ..style-descriptor..
```

When looking up a style for each particular space, full hierarchical path in the space tree is scanned for this word or path. When found, style applies. E.g. `list/item` only styles `item`s that have `list` as their parent space, and has bigger priority than just `item` style.

After the scope, a block with style descriptor should follow, which can be:
- a `compose`-able `block!` with Draw commands
- a function value that receives the space object as argument and returns the Draw block


<details>
	<summary>
		How style lookup works...
	</summary>

<br>

Lookup order is "specific-to-generic". E.g. for path = `host/list-view/list/item/paragraph` the order will be:
```
host/list-view/list/item/paragraph
     list-view/list/item/paragraph
               list/item/paragraph
                    item/paragraph
                         paragraph
```
I.e. if you define both `list/item/paragraph` and `paragraph` then the former (more specific) takes precedence over latter (generic).

Thus styles apply widely by default (like `paragraph`), but can be specialized (like `paragraph` within `item` within `list`). As opposed to assigning a style to each object separately by default and then making effort to cover more.

`host` is the root style that allows one to define style common for all spaces. E.g. line-width, fill-pen, font. The other words are the names of the spaces.


</details>


Styles are defined using **two syntaxes**: block and function.

#### Simple (block) syntax

In this form, style description is a block of [Draw commands](https://w.red-lang.org/en/draw/#draw-commands)
```
set-style 'list/item [pen cyan]

set-style 'paragraph [
	(font: serif-12 ())			;) modifies /font facet of the space
	pen blue
]
```
Unfortunately compose expressions become ugly, and I will most likely revise this syntax.

<details>
	<summary>
		How block styles are applied...
	</summary>
	
<br>

There are 3 **steps**:

1. Block is bound to the space object and *composed*.

   This allows one to set various space facets before drawing it. Like the above `/font` facet is set before space is drawn.\
   Draw is quite limited: e.g. you can't "ask" what current pen color is, to modify it, and you can't set font for rich-text using "font" command, and so on. Composition is aimed to empower styles while still keeping them short.\
   Don't forget to add `()` at the end of composition paren if you don't want it's output to be inserted into the draw block.

2. Space's `/draw` function is called to get a list of commands to render it. That is, `/draw` is called after style sets the facets.

3. Composed block (1) is inserted *before* the `/draw` result (2).

</details>

<details>
	<summary>
		Animated style example: drunken scrollbars used in some of <a href=tests/README.md>the tests</a>
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


#### Free (function) syntax

Some goals cannot be achieved using simple insertion of styles into the draw block.\ 
Consider a simple example - a button (or any surface that's autosized and has text content):
1. Style sets font, font affects the final size
2. Final size is used to draw background frame for the text
3. Background should be drawn before the text or text will become invisible

These constraints cannot be satisfied by insertion, unless space is rendered twice - first time to obtain the size, second time to insert background. But rendering is the most expensive operation performed, and I didn't want to slow things down.

Function syntax gives full control. Example with the aforementioned button:
```
set-style 'button function [btn] [
	btn/font: fonts/button									;) set the font - affects the size
	drawn: btn/draw											;) draw is called to render the button
	bgnd: either btn/pushed? [svmc/text + 0.0.0.120]['off]	;) background color depends on button state
	if focused? [
		focus: compose/deep [								;) optionally add focus indicator, which depends on button size
			line-width 1
			fill-pen off
			pen pattern 4x4 [scale 0.5 0.5 pen off fill-pen (svmc/text) box 0x0  8x8  fill-pen (svmc/panel) box 1x0 5x1 box 1x5 5x8  box 0x1 1x5 box 5x1  8x5]
			box 4x4 (btn/size - 4) (max 0 btn/rounding - 2)
		]
	]
	compose/only [											;) finally, assemble things in right order
		fill-pen (bgnd)
		push (drawn)
		(any [focus ()])
	]														;) returns the draw block!
]
```
Such function is called with a space object as it's mandatory argument and it should return the block of draw commands.

Function style should use the `/draw` facet of space to render it properly (like `btn/draw` above). It *should not* call the `render` function on it's own space, because the main difference between `/draw` and `render` is that `render` looks up and applies styles (and will deadlock if style calls it back).  

This function's output is used unmodified to draw the space.

Note that `draw` function of each space usually sets it's `/size` and `/map` facets by convention.

For spaces that adapt their size automatically, their styling function should accept `/on canvas [none! pair!]` refinement and pass it on to it's `draw` function. Value of `on` should not be accounted for, only `canvas` value matters.

When it makes sense to draw only a portion of a space (e.g. it's big or infinite), styling function should accept `/only xy1 [none! pair!] xy2 [none! pair!]` refinement and pass it on to it's `draw` function. Value of `only` should not be accounted for, only values of `xy1` and `xy2` matter. `none` means "unspecified" and implies rendering of the whole space area.

#### Flags

- `focused?` is a function that returns `true` inside a style that has focus. As in the example above, it can be used to indicate focused state.\
  `focused?/above n` checks for focus of n-th level parent instead
- spaces may have their own flags, e.g. `/pushed?` flag of a button


## Defining behavior

This chapter describes general event handlers that are applied to whole templates. [VID/S actors](vids.md#actor-definition) can be used to tune each single space separately.

Why write an event handler:
- non-standard or extended behavior for standard templates
- behavior of custom templates

Core logic of each space is (and should be) implemented in it's source code. Standard templates are currently presented in the [`templates.red` file](templates.red).

However the behavior is defined in the [`standard-handlers.red` file](standard-handlers.red). Event handlers are meant to be easy to tune manually.

**Example** behavior definition using *event handler description DSL*:
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
Note that the above example defines events both for `inf-scrollable` template and `inf-scrollable/roll-timer` specialized timer.

Event handler description **DSL quick reference**:

| Example | Syntax | Description |
| - | - | - |
| `template-name: [...]` | `set-word! block!` or `set-word! 'extends lit-word! block!` | Defines events for spaces with the given name, optional `extends` modifier inherits handlers from another space. Can define handlers for spaces belonging to other spaces (like `roll-timer:` above) |
| `on-event [space path event] [...]` | `word! block! block!` | Defines handler for a specific event. Internally uses `function` constructor, so inner set-words are collected |

### Event handler spec

Handler spec almost always takes 3 arguments: `space path event`. Only `on-time` event accepts an additional `delay` argument.\ 
It's possible to provide typesets: `space [object!] path [block!] event [event! none!] delay [percent!]`

| usual name | accepted types | description |
|-|-|-|
| `space` | `object!` | Space object that receives the event. Convenience shortcut that equals `get path/1` |
| `path`  | `block!` | Path in the tree of faces, `at` the index of current space. Can be of 2 formats described [above](#organization). |
| `event` | `event!` or `none!` | View event that triggered the handler. Can be `none` for `focus`/`unfocus` events, because they do not come from View, but are generated internally (and it's impossible to create an event object from Red). |
| `delay` | `percent!` | `0%` is the ideal value. But timers do not get called at a precise time. They can be called early (`delay < 0%`), but usually they are late (`delay > 0%`). `delay = 100%` means *it's late by one timer period*. This value can be used to produce smoother animations. |

Access to full tree path gives handlers ability to access their parent objects, like the `roll-timer` above calls a function `roll` from it's parent to affect it.

Path received by the handler is relative to the space that defined it. E.g. for `screen/window/base/list-view/thumb`, if `list-view` receives the event then `path` is `skip [screen window base list-view thumb] 3`

<details>
	<summary>
	
	Parent handler can also know that interaction is made with one of it's children. E.g. `scrollable` space's handlers know if interaction is made with a scroller's thumb or one of the arrows...
	
	</summary>

<br>

Snippet from `scrollable` that uses `item` and `subitem` to refer to it's children targeted by the pointer:
```
scrollable: [
	on-down [space path event] [
		set [_: _: item: _: subitem:] path					;) offsets (even parts) are not used
		case [
			find [hscroll vscroll] item [					;) move or start dragging
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

### Timers

Spaces that define `/rate` facet (to a positive integer, float or time value), and `on-time:` handler can receive timer events.

Timer event handlers have an extra argument: `delay [percent!]`, meaning *delay from the expected time* `[-100% .. can be big]`. It can be used to make animations more smooth.

E.g. if animation moves a sprite by 50px every 50ms:
- `delay = 100%` means it should move by 50+50=100px, because timer skipped an event and coming late
- `delay = -30%` means is should move by 50-15=35px, because timer fired too early

Timer handlers should be prepared to handle huge delays, possible when device lagged or just woke from sleep (e.g. by ignoring them).

Delay bias is accumulated internally and event system automatically makes delayed timers fire more often until bias is zeroed (possible up to 50-55 fps, after which Windows' native timers can't keep up anymore). This is done to best achieve a desired framerate, regardless of whether handler handles the `delay` in any way.


### Previewers and finalizers

Event handlers are divided into 3 stacks (called in this order obviously):
- previewers (e.g. to focus a space on clicks, and still process the click)
- normal handlers (described above)
- finalizers (e.g. to catch Tab key if it wasn't processed and move focus)

Previewers and finalizers help modularize the event system. E.g. [tabbing](tabbing.red), [hovering](hovering.red), [single click event emulation](single-click.red) are separate files that are added on top of the core event system and are not required for it's operation.

<details>
	<summary>`register-previewer` and `register-finalizer` functions add global handlers...</summary>

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

>> ? delist-previewer
USAGE:
     DELIST-PREVIEWER handler

DESCRIPTION: 
     Unregister a previewer from the event chain. 
     DELIST-PREVIEWER is a function! value.

ARGUMENTS:
     handler      [function!] "Previously registered."
     
>> ? delist-finalizer
USAGE:
     DELIST-FINALIZER handler

DESCRIPTION: 
     Unregister a previewer from the event chain. 
     DELIST-FINALIZER is a function! value.

ARGUMENTS:
     handler      [function!] "Previously registered."

```

Spec of global handlers follows that of normal event handlers.

For examples see [`tabbing.red`](tabbing.red), [`single-click.red`](single-click.red), [`hovering.red`](hovering.red), [`focus.red`](focus.red)

</details>


### Commands

A set of commands is available to each event handler, implementing the idea of [REP 80](https://github.com/red/REP/issues/80). Compared to View actors, there's no risk of accidentally returning something we didn't want to and wreaking havoc upon the whole program and then making it freeze.

| command | returned value | description |
|-|-|-|
| update  | N/A    | schedules redraw of the host face (in case handler changes smth that affects visual appearance) |
| update? | logic! | true if host was marked for redraw while processing the current event (maybe by previously called handlers), false by default |
| pass    | N/A    | tells that event should be propagated to the next handler (in case current handler does not want to process this event) |
| stop    | N/A    | tells the opposite: event is processed and should not be passed to other handlers |
| stop?   | logic! | true if event was not processed yet |

<details>
	<summary>
		`stop?` pipeline deserves special mention
	</summary>

<br>

- `stop?: false` is set before calling previewers. Previewers can use `stop` command to stop the event from reaching normal event handlers
- `stop?: true` is set before entering *every* normal event handler, which may call `pass` to pass it further. If it does not, event won't be passed to other normal handlers
- finalizers may inspect `stop?` state to only react to events (e.g. keys - tabbing module only reacts to Tab presses not processed in other handlers)
- previewers and finalizers are all called regardless of this flag's state (cannot be blocked)

</details>

#### Handler lookup and event propagation

<details>
	<summary>
		Order is two-dimensional: <i>outer before inner</i>, then <i>specific before generic...</i>
	</summary>

<br>

E.g. if hittest returns `[list-view 210x392 hscroll 210x8 thumb 196x8]`, and we reduce that to `list-view/hscroll/thumb` then the order would be:
```
list-view
list-view/hscroll
          hscroll
list-view/hscroll/thumb
          hscroll/thumb
                  thumb
```
I.e. `list-view` (outermost) gets an upper hand and it can stop the event from reaching it's children. Then `hscroll` then finally `thumb` (innermost). But event handlers written for `list-view/hscroll/thumb` (specific) get precedence over `thumb` (generic) when present.

In this example, if `list-view/hscroll` handler calls `pass` command, the event gets into `hscroll` handler. Thus specific handlers may extend generic handlers and only care about their own aspects, passing evaluation further.

</details>

Path along the spaces tree comes:
- for pointer events from `hittest` function (called internally by `host`)
- for keyboard events and focus/unfocus - from `spaces/keyboard/focus` value (but only space types listed in `spaces/keyboard/focusable` can receive keyboard events)
- for timer events - from the internal tree built up by `render`

<details>
	<summary>
		Define events *for paths* to ensure hierarchy.
	</summary>

<br>

E.g. if event is defined for `list-view/hscroll/thumb`, `thumb` space that receives it will be able to access `hscroll` as `path/-1` and `list-view` as `path/-2` and never worry that it might have been used inside another space. Another way to do that is define events for `list-view` and inspect if `path/2 = 'hscroll` and `path/3 = 'thumb`. The choice is a matter of convenience.

</details>

Timer events handlers cannot block each other with `stop`: they always get triggered (because hierarchy doesn't make sense for timers).
Previewers however can use the `stop` command to stop the event from reaching all normal timer event handlers.

### Dragging

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

An event handler is supposed to call `start-drag` to focus subsequent pointer events on that same space, until this or another handler calls `stop-drag`. An optional parameter can be passed with `/with`, while `drag-offset` is computed automatically.



