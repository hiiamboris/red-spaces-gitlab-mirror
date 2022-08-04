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

Default styles are loaded from the [`styles.red`](styles.red) file.

New styles are currently created by `set-style` function which accepts single style value:
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
Or with `define-styles` which is a simple dialect for stylesheet definition:
```
>> ? define-styles
USAGE:
     DEFINE-STYLES styles

DESCRIPTION: 
     Define one or multiple styles using Styling dialect. 
     DEFINE-STYLES is a function! value.

ARGUMENTS:
     styles       [block!] "Stylesheet."

REFINEMENTS:
     /unique      => Warn about duplicates.
```

For style to have effect, style *name* should be either:
- a `word!` which should coincide with the space's name (which usually equals it's template name)
- a `path!` of such valid space names that will be matched against the tree path

Examples:
```
set-style 'paragraph ..style-descriptor..
set-style 'list/item ..style-descriptor..
define-styles [
	paragraph: ..style-descriptor..
	list/item: menu/item: ..style-descriptor..
]
```

When looking up a style for each particular space, full hierarchical path in the space tree is scanned for this word or path. When found, style applies. E.g. `list/item` only styles `item`s that have `list` as their parent space, and has bigger priority than just `item` style.



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

Style descriptor carries the style body. It can be either a block or a function.

#### Simple (block) syntax

Is just a block bound to space and evaluated. It minimizes the amount of boilerplate code and makes styles more readable.

Block style may contain special `below:` and `above:` blocks with [Draw commands](https://w.red-lang.org/en/draw/#draw-commands) which will be inserted before and after the Draw block returned by the space's `/draw` function:
- `below` is great for drawing frame and background after `/size` gets set
- `above` is great for drawing focus overlay or tinting the space (like button in it's "pushed" state)

Examples:
```
set-style 'list/item [
	below: [pen cyan]					;) changes pen used by /draw
]

set-style 'paragraph [
	font: serif-12						;) modifies /font facet before /draw call
	below: [pen blue]
]

define-styles [
	tube: list: box: [					;) allows color override for containers
	
		;) `select self 'color` ensures that `color: none` value works same as absence of `color:` facet
		below: when select self 'color [
		
			;) note usage of unqualified `size` here (compose gets called after /draw so it's valid)
			push (make-box size 0 'off color)
		]
	]
	
	hscroll/thumb: vscroll/thumb: [		;) box that indicates focus presence in a scrollable
		above: when focused?/above 2 (		;) test if focus is 2 levels above thumb (scrollable, grid-view, list-view)
			make-box/margin size 1 checkered-pen none 4x3
		)
	]
]
```
Tip: `when` function tests a condition and if true, returns the block after it or evaluates a paren. If false, returns an empty block. It's a very useful helper for `compose`.

<details>
	<summary>
		Animated style example: drunken scrollbars used in some of <a href=tests/README.md>the tests</a>
	</summary>

```
define-styles [
	back-arrow:  [below: [rotate (angle) (size / 2)]]
	forth-arrow: [below: [rotate (angle) (size / 2)]]
	thumb:       [below: [translate (size * 0x1 / 2) skew (angle / -2) translate (size * 0x-1 / 2)]]
]
```
Where `angle` is updated 3 times per sec as:
```
angle: pick [0 -13 -20 -13 0 13 20 13] (counter: counter + 1) % 8 + 1
```
Such power can be held in just a few lines! :D

</details>


<details>
	<summary>
		How block styles are applied...
	</summary>
	
<br>

There are 3 **steps**:

1. Block is bound to the space object and evaluated before the `/draw` call.

   This allows one to set various space facets before drawing it. Like the above `/font` facet is set before space is drawn.\
   Draw is quite limited: e.g. you can't "ask" what current pen color is, to modify it, and you can't set font for rich-text using "font" command, and so on. Evaluation is aimed to empower styles while still keeping them short.\
   Evaluation result is unused except for `below:` and `above:` fields.\
   Other set-words that are not bound to space will leak out, so be careful.

2. Space's `/draw` function is called to get a list of commands to render it.

   `/draw` sets the `/size` and `/map` facets, so they will be valid when accessed from `below`/`above` blocks during their composition.

3. Values of `below:` and `above:` are composed (using `compose/deep`) and inserted around `/draw` result: `[(below) (drawn) (above)]`.

   If any of these values are absent or `none`, they're ignored.

</details>


#### Free (function) syntax

Function syntax gives more control over styling, e.g.:
- it can ignore `/draw` function completely
- it gets access to the `canvas` and `xy1`/`xy2` arguments
- it's faster because it's not being bound to the space at runtime

Sometimes it's more readable. Plus there's little risk of accidentally leaking words.

Style function:
- receives space as it's mandatory argument and should use path syntax to access it's facets
- should call `/draw` manually, passing `/on canvas` and `/window xy1 xy2` arguments to `/draw` if it supports those
- should return a block of Draw commands, which will be used to draw the space without any further modifications
 
Example for `grid/cell` that draws full cell background regardless of how small/big the cell content happens to be:
```
set-style 'grid/cell function [cell /on canvas] [
	#assert [canvas]							;-- grid should provide finite canvas
	drawn: cell/draw/on canvas					;-- passes /canvas argument
	
	;; when cell content is not compressible, cell/size may be bigger than canvas, but we draw up to allowed size only
	canvas: min abs canvas cell/size
	
	color: any [								;-- allow cell color override and highlight pinned cells by default
		select cell 'color
		if grid-ctx/pinned? [mix 'panel opaque 'text 15%]
	]
	
	bgnd: make-box canvas 0 'off color			;-- always fill canvas, even if cell is constrained
	
	reduce ['push bgnd drawn]					;-- compose result of /draw and background
]
```

Example for `switch` that doesn't use `/draw` at all, and sets the `/size` itself:
```
set-style 'switch function [self] [
	cross?: when self/state [line 3x3 13x13 line 13x3 3x13]
	frame:  make-box self/size: 16x16 1 none none
	reduce [frame cross?]
]
```

Note: style function *should not* call the `render` function on it's own space, because the main difference between `/draw` and `render` is that `render` looks up and applies styles (and will deadlock if style calls it back).  

For spaces that adapt their size automatically, their styling function should accept `/on canvas [none! pair!]` refinement and pass it on to it's `draw` function. Value of `on` should not be accounted for, only `canvas` value matters.

When it makes sense to draw only a portion of a space (e.g. it's big or infinite), styling function should accept `/window xy1 [none! pair!] xy2 [none! pair!]` refinement and pass it on to it's `draw` function. Value of `window` should not be accounted for, only values of `xy1` and `xy2` matter. `none` means "unspecified" and implies rendering of the whole space area.

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
	Parent handler can also know that interaction is made with one of it's children. E.g. <code>scrollable</code> space's handlers know if interaction is made with a scroller's thumb or one of the arrows...
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
	<summary><code>register-previewer</code> and <code>register-finalizer</code> functions add global handlers...</summary>

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
		<code>stop?</code> pipeline deserves special mention
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
		Define events <em>for paths</em> to ensure hierarchy.
	</summary>

<br>

E.g. if event is defined for `list-view/hscroll/thumb`, `thumb` space that receives it will be able to access `hscroll` as `path/-1` and `list-view` as `path/-2` and never worry that it might have been used inside another space. Another way to do that is define events for `list-view` and inspect if `path/2 = 'hscroll` and `path/3 = 'thumb`. The choice is a matter of convenience.

</details>

Timer events handlers cannot block each other with `stop`: they always get triggered (because hierarchy doesn't make sense for timers).
Previewers however can use the `stop` command to stop the event from reaching all normal timer event handlers.

### Dragging

<details>
	<summary>
Current API (not yet mature enough) - <code>start-drag</code>, <code>stop-drag</code>, <code>dragging?</code>, <code>drag-offset</code>, <code>drag-parameter</code>, <code>drag-path</code>
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



