---
gitea: none
include_toc: true
---

# How to create your own widget template

Adding new templates is not quite as easy as using them.
This step by step guide explains template design on a `drop-box` ([combo box](https://en.wikipedia.org/wiki/Combo_box)) example and shows typical little problems and their solutions.

This guide is meant as a more practical addition to the [Creators Guide](../creators.md) and assumes you've got the gist of it.

Despite its simple appearance, combo box is rather hard to design correctly, and it's quite likely that this design will be enhanced in the future.

It is highly recommended to actually follow all the steps yourself rather than just read the guide. This way your brain will wire the instructions with your own understanding of the code at each step, and with questions that may otherwise not be raised.

## Introduction

### Naming 

I don't quite like names `drop-list` and `drop-down` used in VID, as I can't tell them apart. They both "drop down" a "list" of selectable options.

Instead, I want widget names to tell what unique features it provides. After some thinking I decided to have:
- `drop-box`: a read-only box with an item from a drop-down list *(box + drop-down)*
- `drop-field`: an editable field that can be reset to an item from a drop-down list *(field + drop-down)* 

But these names (or similar) will be available out of the box in more recent versions, so to ensure existing features do not interfere with this guide, I will name them the first one `drop-box*` and the second one is out of scope of this guide.

### Features

Roughly what features should a `drop-box*` have?
- some read-only text
- a button on the right
- when clicked, a popup list should appear

### Template

We do not have to start building our template from scratch. As long as one of the standard templates can serve as a basis, it's wise to leverage it.

**TIP: when not to leverage existing template?**
- for performance reasons: specific case can always be optimized more than a general one
- if all templates expose facets that are meaningless for the derived one

We want text and button to be arranged in a *row*, with button being of fixed size and text stretching horizontally. `row` VID/S style that is just a wrapper around [`tube`](../reference.md#tube) (actual underlying template name) seems like the best fit to satisfy these requirements (unlike `hlist` that will compress the items horizontally). So we'll base our new template on `tube`.

### Prototype

It's always best to start playing with the ideas as soon as possible, so let's make a simplest mockup of the new template right away.

Create this file, name it `drop-box-guide.red` and place it into `/widgets` subdirectory of Spaces:
```
Red [needs: view]

#include %../everything.red

declare-template 'drop-box*/tube [
	axes: [e s]											;) east then south - most common flow direction
	content: reduce [									;) let's just put two hardcoded spaces into tube for now
		make-space 'text [text: "chosen item"]
		make-space 'button [data: "v"]
	]
]

view [host [drop-box*]]
```
Run this file with Red, and here's how the result looks:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-1.png)

OK, a bit messy, now we know we're on the right track!

### Providing defaults

Let's tweak it a little...

Looks like tube aligns its items to the top left by default, and we can check that in the `templates.red` file by looking up `'tube/` text:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/tube-source.png)

Indeed, this is the case. But we don't want to depend on default alignment anyway, so let's realign it, adding `align` line after `axes` in our template. 

**`;<<<` marker from now on will identify the changed lines to help you follow:**
```
declare-template 'drop-box*/tube [
	axes: [e s]											;) east then south - most common flow direction
	align: -1x0											;) to the left, but centered vertically						;<<<
	content: reduce [									;) let's just put two hardcoded spaces into tube for now
		make-space 'text [text: "chosen item"]
		make-space 'button [data: "v"]
	]
]
```
Better now:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-2.png)
   
Default button is not what we want to see. In fact we don't even need a button there, just some triangle there without border. Let's rewrite the `button` line into: 

```
	make-space 'triangle [dir: 's]						;) arrow facing south
```
Now look at it:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-3.png)

### Structure

We'd like to be able to address spaces used in the drop-box by some meaningful names rather than numbered `drop-box/content/1` and so. Let's name them.
```
declare-template 'drop-box*/tube [
	axes: [e s]											;) east then south - most common flow direction
	align: -1x0											;) to the left, but centered vertically
	spaces: object [																					;<<<
		box:    make-space 'text [text: "chosen item"]													;<<<
		button: make-space 'triangle [dir: 's]			;) arrow facing south							;<<<
	]
	content: reduce [spaces/box spaces/button]															;<<<
]
```
Now we'll be able to access them as `drop-box/spaces/box` and `drop-box/spaces/button`. 

Why put them into `spaces` internal object? In bigger templates with a lot of children this reduces clutter, and ensures no naming collisions. Generally if space is *meant* to be interacted with (like `/list` in list-view), it's better to put it into template directly, but if it's more of an *implementation detail* and only meant to be used by the template code, it's better to isolate it into `/spaces`.

Names `box` and `button` are only a matter of convenience and are giving meaning to path access: even if they're not really based on `box` or `button` templates, they still act like a box where we will place the selected item and a button to click on. We could have named `box` a `chosen-item` instead, but this will do until we find a name that's *clearly* better.

## Styling

It's time to put some lipstick on our pig now. 

### Frame

First, let's add a frame around it (stick this code after template declaration):
```
define-styles [
	drop-box*: [
		below: [fill-pen off  box 0x0 (size)]
	]
]
```
Note the `(size)` in paren - after being composed internally it will evaluate to the `size` facet of our `drop-box*` space. Composition is done after `draw` sets the `size` and returns. This is important, otherwise `size` would be lagging by one frame behind.

New look:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-4.png)

### Styles affect children

Triangle seems too thick, so let's modify our style:
```
below: [fill-pen off  line-width 1  box 0x0 (size)]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-5.png)

As long as `tringle` style doesn't define its own `line-width`, it inherits the value we define for its parent `drop-box*`.

Now the frame is too thin, how come? This happens because given `0x0` and `size` coordinates, half of the outline gets inside the box, half outside (and this half gets clipped by the host face). Since we can't draw our line from `0.5x0.5` coordinate, we have to halve the scale for lines of odd widths:
```
below: [
	fill-pen off  line-width 1					;) line-width for children
	push [																				;<<<
		scale 0.5 0.5  line-width 2				;) line-width for the frame				;<<<
		box 1x1 (size * 2 - 1)															;<<<
	]																					;<<<
]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-6.png)

OK we've got the frame correct now. 

### Proportions

It all seems too tight, so let's add some margins:
```
define-styles [
	drop-box*: [
		margin: spacing: 5																;<<<
		below: [
			fill-pen off  line-width 1					;) line-width for children
			push [
				scale 0.5 0.5  line-width 2				;) line-width for the frame
				box 1x1 (size * 2 - 1)
			]
		]
	]
]
```
Note that `below` and `above` are keywords in the styling dialect, but the rest (`margin`, `spacing`) changes values of space facets. 

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-7.png)

Perhaps the arrow is a bit too wide, let's make it narrower: 
```
define-styles [
	drop-box*: [
		margin: spacing: 5
		below: [
			fill-pen off  line-width 1					;) line-width for children
			push [
				scale 0.5 0.5  line-width 2				;) line-width for the frame
				box 1x1 (size * 2 - 1)
			]
		]
	]
	drop-box*/triangle: [size/x: 14]													;<<<
]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-8.png)

Since `triangle` is an immediate child of the `drop-box*`, we list it as a substyle, to avoid affecting all other triangles (e.g. those in scrollbars).

### Defaults should be part of the template

It would be better however to move these constants into the template itself, because they seem to be reasonable defaults. Styles should only modify them when they don't want defaults. 
```
declare-template 'drop-box*/tube [
	axes:   [e s]										;) east then south - most common flow direction
   	align:  -1x0										;) to the left, but centered vertically
	margin: spacing: 5																					;<<<
	spaces: object [
		box:    make-space 'text     [text: "chosen item"]
		button: make-space 'triangle [dir: 's size/x: 14]		;) arrow facing south					;<<<
	]
	content: reduce [spaces/box spaces/button]
]

define-styles [
	drop-box*: [
		below: [
			fill-pen off  line-width 1					;) line-width for the children
			push [
				scale 0.5 0.5  line-width 2				;) line-width for the frame
				box 1x1 (size * 2 - 1)
			]
		]
	]
]
```

## Events

### Dummy event handler

Next step would be to add interactivity. We want clicks on `drop-box*` to drop down a list of choices. `on-down` seems like the right event handler to use here. So let's add this after style definition:
```
define-handlers [
	drop-box*: [
		on-down [space path event] [
			?? path
		]
	]
]
```
It will do nothing useful, just show us that it works:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-9.gif)

### Showing a popup

Now we want it to show a list. We could make this list static and put into the template itself, or we could create it on demand when clicked. What to choose? Suppose we have a hundred of drop-boxes on our page. If we put list into the template, we'll have a hundred lists wasting RAM *all the time*, but if we create it on demand, we only sacrifice a bit of CPU time on every click to create the list anew. No one will notice this, so let's go with on demand.

To show popups we have a `popups/show` function:
```
>> ? spaces/ctx/popups/show
USAGE:
     SPACES/CTX/POPUPS/SHOW space offset

DESCRIPTION: 
     Show a popup at given offset, hiding the previous one(s). 
     SPACES/CTX/POPUPS/SHOW is a function! value.

ARGUMENTS:
     space        [object!] "Space or face object to show."
     offset       [pair!] "Offset on the window."

REFINEMENTS:
     /in          => 
        window       [object! none!] "Specify parent window (defaults to focus/window)."
     /owner       => 
        parent       [object! none!] "Space or face object; owner is not hidden."
```
And to hide them, respectively `popups/hide`:
```
>> ? spaces/ctx/popups/hide
USAGE:
     SPACES/CTX/POPUPS/HIDE level

DESCRIPTION: 
     Hides popups from given level or popup face. 
     SPACES/CTX/POPUPS/HIDE is a function! value.

ARGUMENTS:
     level        [integer! object!] ">= 1 or face."
```

It wants `offset` in the window as argument, but we have only offset in the host face. `face-to-window` should help us out:
```
>> ? face-to-window
USAGE:
     FACE-TO-WINDOW xy face

DESCRIPTION: 
     Translate a point XY in FACE space into window space. 
     FACE-TO-WINDOW is a function! value.

ARGUMENTS:
     xy           [pair!] 
     face         [object!] 
```
And this requires `face` object, but we only have `space`. We can use `host-of space`, or `event/face`, doesn't matter. 

Let's try to put this all together:
```
define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [													;<<<
				list-view 100x100 source= map-each i 10 [i]								;<<<
			]																			;<<<
			offset: face-to-window event/offset event/face 								;<<<
			spaces/ctx/popups/show list offset											;<<<
		]
	]
]
```

I chose [`list-view`](../reference.md#list-view) instead of [`list`](../reference.md#list) because it's alread data-oriented (for `list` I would have to create space objects for every data value), and though unlikely, it's still possible that popup will have *too many* choices, and `list-view` will handle it gracefully.

Well, it clearly shows it, but clipped:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-10.gif)

### Popups are cropped

Cropping by host is an unfortunate limitation for now. Red has no real popups, nor transparency support for windows, making it impossible to show rounded tooltips and ring menus in a separate window. So to display a popup a new face is used, but face cannot stick out of the window.

To see it we just have to make the window bigger (reasonable to assume real window will be big enough anyway):
```
view [host 150x150 [drop-box*]]
```
Visible now:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-11.gif)

## Tweaking

Now that all the basics are set up, let's tweak it until we're happy.

### Identification by type

There's no border around the list popup, we should add it. However we should not modify the general `list-view` style. Let's call our style `drop-menu*`. For that we must also change the `/type` of `list-view` space we create, so it will be identified properly in styles and event handlers.

Note added `type=` and `drop-menu*` style:
```
define-styles [
	drop-box*: [
		below: [
			fill-pen off  line-width 1					;) line-width for the children
			push [
				scale 0.5 0.5  line-width 2				;) line-width for the frame
				box 1x1 (size * 2 - 1)
			]
		]
	]
	drop-menu*: [below: [box 0x0 (size)]]												;<<<
]

define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [
				list-view 100x100 source= map-each i 10 [i] type= 'drop-menu*			;<<<
			]
			offset: face-to-window event/offset event/face 
			spaces/ctx/popups/show list offset
		]
	]
]
```
Note also that since our drop-menu will always fill the whole host face, we can use the default 2px line-width and allow one pixel to be cropped, resulting in 1px frame, so no scaling is needed. 

### Renaming passive spaces is easier

Popup has a frame now, but does not react to scroll events anymore:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-12.gif)

This is because it used `list-view`'s event handlers, and now it tries to find events for `list-box*`, but we haven't defined them. We can just inherit them using `drop-menu*: extends 'list-view []` line in event handlers, but here's a better idea. `list-view` doesn't support margins and looks too tight right now. We should put it into a `cell`. It will both add margins, draw a frame, and leverage default event handlers of `list-view`:
```
define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [
				cell margin= 5 [list-view 100x100 source= map-each i 10 [i]]			;<<<
			]
			offset: face-to-window event/offset event/face 
			spaces/ctx/popups/show list offset
		]
	]
]
```
We don't even need the `drop-menu*: [below: [box 0x0 (size)]]` line anymore!

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-13.gif)

### Coordinate translations

Next, let's relocate the popup below the `drop-box*` and give it proper size. We need to locate the left bottom corner of the `drop-box*` on the host and then on the window.

We know `event/offset` which is the click location in the host, and `path/2` which is the click location in the drop-box, and we have the drop-box size, so `event/offset - path/2 + (space/size * 0x1)` should be our bottom left corner, relative to host:
```
define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [
				cell margin= 5 [list-view 100x100 source= map-each i 10 [i]]
			]
			corner: event/offset - path/2 + (space/size * 0x1)							;<<<
			offset: face-to-window corner event/face 									;<<<
			spaces/ctx/popups/show list offset
		]
	]
]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-14.gif)

It appears where expected, but our drop-box is too big. Of course, since it's the only space on the host and we forced the host size to be big, it's expected. 

### Sizing constraints

We can just put the drop-box into a list and it will not stretch:
```
view [host 150x150 [vlist [drop-box*]]]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-15.gif)

Now on to size of the list. Its width should just equal that of the drop-box. But height? We don't want it too big, partly because it will be cropped, partly because long drop-down lists are bad UI anyway. 

`limits` facet is just the thing for this. But instead of hardcoding a limit in pixels, let's measure it in heights of the drop-box and make it configurable. E.g. we shouldn't expect only text to be there - maybe someone will use a list of images, and whole widget will have a more square-like appearance.

Let's add new facet to our template. Unlike other facets, which were inherited, this one is new, and we should type it to restrict assignable values:
```
list-pages: 5		#type [integer!] (list-pages >= 1)		;) max drop-list height in drop-box's heights
```
And then our handlers will take it into account:
```
define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [
				cell margin= 5 [list-view source= map-each i 10 [i]]
				limits= space/size .. (space/size * (1 by space/list-pages))			;<<<
			]
			corner: event/offset - path/2 + (space/size * 0x1)
			offset: face-to-window corner event/face 
			spaces/ctx/popups/show list offset
		]
	]
]
```
Note that chosen limits fix the horizontal size and restrict vertical size from 1 to `list-pages` heights of the drop-box.

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-16.gif)

### Popups do not scale

Great. *But it's all incorrect!* We assumed in our calculations that drop-box was never scaled, rotated, or skewed. It may be a fine assumption for skew and rotate, but imagine an interactive page with some drop-boxes, and if user could choose the page's zoom. Our drop-menu will appear bigger than the drop-box.

Unfortunately, this limitation is currently unavoidable for popups. It is impossible to 'ask' Draw "what's your transformation matrix?" and apply it to the new popup face. It could be done by parsing the whole `draw` facet of the host until block returned by drop-box's `draw` will be found, but complexity and performance overhead of such solution makes it unacceptable for me. A program that really needs popup scaling could put page's zoom into a facet and use it for drop-downs - for a specific case it's always orders of magnitude easier.

### Mirroring facets

For our next step, let's make clicks on the list actually choose the item. 

First, we'll add a `selected` facet which will hold the item *data*, and replace `text` with [`data-view`](../reference.md#data-view) that is suited for turning data into text for display:
```
declare-template 'drop-box*/tube [
	axes:   [e s]										;) east then south - most common flow direction
   	align:  -1x0										;) to the left, but centered vertically
	margin: spacing: 5
	spaces: object [
		box:    make-space 'data-view []																		;<<<
		button: make-space 'triangle  [dir: 's size/x: 14]		;) arrow facing south
	]
	content: reduce [spaces/box spaces/button]
	
	list-pages: 5		#type [integer!] (list-pages >= 1)		;) max drop-list height in drop-box's heights
	selected:   {}		#push spaces/box/data																	;<<<
]
```
`#push spaces/box/data` directive here is a shortcut to writing an `on-change` function like this:
```
selected: {}
	#on-change [space [object!] word [word!] value] [
		space/spaces/box/data: :value
	]
```
Its purpose is to mirror changes in the parent facet into one of its children. It doesn't need a type check because child's type check will catch the errors. And the child will also trigger parent's invalidation as it invalidates itself.

### Linking spaces together

Second, we should assign `selected` when `drop-menu*` is clicked. However `drop-menu*` has no link to the `drop-box*` that spawned it, so we add a new `owner` facet to drop-menu. To have events on `drop-menu*` we should also add a `type` facet to `cell` (as we did for `list-view` previously):
```
define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [
				cell margin= 5 [list-view source= map-each i 10 [i]]
					limits= space/size .. (space/size * (1 by space/list-pages))
					owner= space														;<<<
					type= 'drop-menu*													;<<<
			]
			corner: event/offset - path/2 + (space/size * 0x1)
			offset: face-to-window corner event/face 
			spaces/ctx/popups/show list offset
		]
	]
	drop-menu*: [
		on-down [space path event] [
			set [item:] locate path [obj - .. /type = 'item]
			space/owner/selected: item/data
		]
	]
]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-17.gif)

### Copying a style

Our item selection works, but we lost the `cell`'s frame, since it's now recognized as `drop-menu*` and we didn't tell how to draw it. We can just copy the `cell`'s style to it, by inserting this somewhere near `define-styles`:
```
set-style 'drop-menu* spaces/ctx/get-style to path! 'cell
```
`get-style` is quite low level func, optimized for path access, so when our style is a single word we have to explicitly make a path out of it with `to path!`. I'll probably add some style copying syntax direcly into the `define-styles` later, but it's not there yet. 

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-18.gif)

This restored the frame. 

### Working in Spaces context

`spaces/ctx` prefix gets annoying. We can get rid of it by wrapping our whole experiment into a `do with spaces/ctx` call. Let's also add `expand-directives` because this is the only reliable way to expand macros right now, and although we haven't used any macros yet, during more complex design work we might want to. E.g. [`quietly`](https://codeberg.org/hiiamboris/red-common/src/commit/f4928e2145ca1c71e27b5e3ed23853c3ea447d6a/setters.red#L58) is a macro I often use in templates.

| TIP | When designing new styles it's always handy to wrap the code in a `do with spaces/ctx expand-directives [...]` call |
|-|-| 

Whole code should look like this now:
```
Red [needs: view]

#include %../everything.red

do with spaces/ctx expand-directives [

declare-template 'drop-box*/tube [
	axes:   [e s]										;) east then south - most common flow direction
   	align:  -1x0										;) to the left, but centered vertically
	margin: spacing: 5
	spaces: object [
		box:    make-space 'data-view []
		button: make-space 'triangle  [dir: 's size/x: 14]		;) arrow facing south
	]
	content: reduce [spaces/box spaces/button]
	
	list-pages: 5		#type [integer!] (list-pages >= 1)		;) max drop-list height in drop-box's heights
	selected:   {}		#push spaces/box/data
]

set-style 'drop-menu* get-style to path! 'cell
define-styles [
	drop-box*: [
		below: [
			fill-pen off  line-width 1					;) line-width for the children
			push [
				scale 0.5 0.5  line-width 2				;) line-width for the frame
				box 1x1 (size * 2 - 1)
			]
		]
	]
]

define-handlers [
	drop-box*: [
		on-down [space path event] [
			list: first lay-out-vids [
				cell margin= 5 [list-view source= map-each i 10 [i]]
					limits= space/size .. (space/size * (1 by space/list-pages))
					owner= space
					type= 'drop-menu*
			]
			corner: event/offset - path/2 + (space/size * 0x1)
			offset: face-to-window corner event/face 
			popups/show list offset
		]
	]
	drop-menu*: [
		on-down [space path event] [
			set [item:] locate path [obj - .. /type = 'item]
			space/owner/selected: item/data
		]
	]
]

view [host 150x150 [vlist [drop-box*]]]

];do with spaces/ctx expand-directives [
```

### Hiding a popup

We forgot to hide our drop-menu on click, so about time to add `popups/hide` to its `on-down` handler. It accepts either a popup level (since our popups are not nested, it's just `1`), or a popup host face (which we can obtain as `host-of space` or `event/face`):
```
drop-menu*: [
	on-down [space path event] [
		set [item:] locate path [obj - .. /type = 'item]
		space/owner/selected: item/data
		popups/hide event/face
	]
]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-19.gif)

The list gets hidden now.

### Wrapping data into spaces

Perhaps we should add some highlight to the `drop-menu*` item under the pointer. That means having some logic flag, and best place for it seems the list item. `list-view` generates spaces for its data on the fly using `wrap-data` function, so we find it in `templates.red` (look for `'list-view/` then `wrap-data` in it). Here it is:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/list-view-source.png)

All we need is to copy it over and add a new facet to the item. Let's modify the `on-down` handler of the `drop-box*`:
```
drop-box*: [
	on-down [space path event] [
		list: first lay-out-vids [
			cell margin= 5 [
				list-view source= map-each i 10 [i]												;<<<
					wrap-data= func [item-data [any-type!] /local spc] [						;<<<
						spc: make-space 'data-view [											;<<<
							quietly type:  'item												;<<<
							quietly wrap?:  on													;<<<
							lit?: no				;) we'll set this to true for coloring		;<<<
						]																		;<<<
						set/any 'spc/data :item-data											;<<<
						spc																		;<<<
					]																			;<<<
			]
				limits= space/size .. (space/size * (1 by space/list-pages))
				owner= space
				type= 'drop-menu*
		]
		corner: event/offset - path/2 + (space/size * 0x1)
		offset: face-to-window corner event/face 
		popups/show list offset
	]
]
```

### Adding on-over highlight

Now we can add an `on-over` handler to the item that sets the `lit?` flag ('lit' from 'light', not 'literal'):
```
drop-menu*: [
	on-down [space path event] [
		set [item:] locate path [obj - .. /type = 'item]
		space/owner/selected: item/data
		popups/hide event/face
	]
	list-view: [																		;<<<
		window: [																		;<<<
			list: [																		;<<<
				item: [																	;<<<
					on-over [space path event] [										;<<<
						space/lit?: path/2 inside? space								;<<<
						invalidate space												;<<<
					]																	;<<<
				]																		;<<<
			]																			;<<<
		]																				;<<<
	]																					;<<<
]
```
Note the full path to the handler is `drop-menu*/list-view/window/list/item` (you can always get it by inspecting `?? path` in any event handler), which ensures it affects only our new widget and nothing else. Note also with `invalidate` we signal the space tree to redraw the list item after the change.

To see it working we also need to make the style use this new flag (put this into `define-styles` scope):
```
drop-menu*/list-view/window/list/item: [
	below: when lit? [pen off fill-pen (opaque 'text 10%) box 0x0 (size)]
]
```
Now we get highlight:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-20.gif)

### Handling child events in the parent

I don't quite like the nesting level for `item`'s `on-over` and paths like in styles are not implemented, but there's another way - we can write it for the `drop-menu*` itself:
```
drop-menu*: [
	on-down [space path event] [
		set [item:] locate path [obj - .. /type = 'item]
		space/owner/selected: item/data
		popups/hide event/face
	]
	on-over [space path event] [														;<<<
		set [item: item-xy:] locate path [obj - .. /type = 'item]						;<<<
		item/lit?: item-xy inside? item													;<<<
		invalidate item																	;<<<
	]																					;<<<
]
```
But now we get errors `inside? does not allow none! for its point argument` printed all over the console. Of course, since not every `over` event happens to land on the item. Let's modify the `locate` line: 
```
unless set [item: item-xy:] locate path [obj - .. /type = 'item] [exit]
```
That removes the error:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-21.gif)

Another `path item/data is not valid for none! type` error comes from the `down` event when we try to use the scrollbar. Of course, since we missed the same check. Let's fix the `on-down`'s `locate`:
```
unless set [item:] locate path [obj - .. /type = 'item] [exit]
```

### Passing unhandled events down

No error anymore, but scrollbar doesn't react to events:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-22.gif)

It happens because our `on-down` and `on-over` handlers process the event, so it's not passed further into children. We should use the `pass` call to let it pass thru when we don't handle it:
```
drop-menu*: [
	on-down [space path event] [
		unless set [item:] locate path [obj - .. /type = 'item] [pass exit]				;<<<
		space/owner/selected: item/data
		popups/hide event/face
	]
	on-over [space path event] [
		unless set [item: item-xy:] locate path [obj - .. /type = 'item] [pass exit]	;<<<
		item/lit?: item-xy inside? item
		invalidate item
	]
]
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-23.gif)

Purrfect!

## Review

So now that our widget is mostly working, it's time to review the design.

### Using classes for type checks

Our `lit?` flag is not typed and does not auto invalidate the space. We need to reserve a class for it to make all that work, however we do not want to add a new space template (which is also class-based), since our `item` wouldn't be of any good outside of `drop-menu*`.

Let's convert our `item` init code:
```
spc: make-space 'data-view [
	quietly type:  'item
	quietly wrap?:  on
	lit?: no				;) we'll set this to true for coloring
]
```
into a class:
```
item-template: declare-class 'item-in-drop-menu/data-view [
	type:  'item
	wrap?: on
	lit?:  no		#type = [logic!] :invalidates		;) we'll set this to true for coloring
]
```
We use a lengthy name `item-in-drop-menu` because class names are all global, and we don't want to accidentally claim a good name that can be used for a new widget or something else. Class is based on `data-view`, so it inherits all typechecks from it. Since `lit?` is the only new facet, it's the only one we have to `#type`. 

`quietly` there was just an optimization for really long lists, so we can remove it, as drop-lists are always limited. `type` will keep our item recognized as `item` for styles and events, not as `item-in-drop-menu` (class name is used only when no explicit type is provided). `invalidates` will redraw the item every time `lit?` value changes: `=` equality type is provided to skip assignments that do not change the value.

`wrap-data` can now be rewritten as (also renamed `spc` to `item`):
```
wrap-data= func [item-data [any-type!] /local item] [
	item: make-space 'data-view item-template
	set/any 'item/data :item-data
	item
]
```
It's still based on `data-view` template (because we didn't declare a new template), but it will use typechecks from `item-in-drop-menu` class and evaluate code provided by `item-template` block, initializing three facets.

### VID/S into Red code

Next issue is that we're using VID/S in `drop-box*`'s `on-down` event to make a new space, but it's not what VID/S was designed for. Let's rewrite it using plain Red:
```
drop-box*: [
	on-down [space path event] [
		list: make-space 'cell [														;<<<
			type:    'drop-menu*														;<<<
			owner:   space																;<<<
			margin:  5																	;<<<
			limits:  space/size .. (space/size * (1 by space/list-pages))				;<<<
			content: make-space 'list-view [											;<<<
				source: map-each i 10 [i]												;<<<
				wrap-data: func [item-data [any-type!] /local item] [					;<<<
					item: make-space 'data-view item-template							;<<<
					set/any 'item/data :item-data										;<<<
					item																;<<<
				]																		;<<<
			]																			;<<<
		]
		corner: event/offset - path/2 + (space/size * 0x1)
		offset: face-to-window corner event/face 
		popups/show list offset
	]
]
```
That's better (and faster, though we won't notice it).

### Configurable list of choices

We also hardcoded list data as an integer range 1 to 10. Instead let's add a `data` facet to the `drop-box*`:
```
data:       []		#type [block! hash!]			;) available options
```
`hash!` type seems reasonable to allow: since we do not expose an integer index of the selected item, in case one wants the index one will have to use `index? find data item`, which scales better on `hash!`.   

And we init list's `source` with `data`:
```
content: make-space 'list-view [
	source: space/data																	;<<<
	wrap-data: func [item-data [any-type!] /local item] [
		item: make-space 'data-view item-template
		set/any 'item/data :item-data
		item
	]
]
```

### Handling changes

Next we should think what happens if `data` is changed? It doesn't affect the `drop-box*` itself and we don't expect to refresh a shown `drop-menu*` in real time as `data` changes. However, we may want to keep `selected` in sync with the `data`, and if `data` is replaced, we should also reset `selected`:
```
data:       []		#type [block! hash!]			;) available options
	#on-change [space [object!] word [word!] list [block! hash!]] [						;<<<
		space/selected: any [:space/data/1  copy {}]									;<<<
	]																					;<<<
```
But to avoid cluttering the template, it's a good practice to move the `#on-change` out:
```
on-data-change: function [space [object!] word [word!] list [block! hash!]] [
	space/selected: any [:space/data/1  copy {}]
]
```
And then redeclaring `data` as:
```
data:       []		#type [block! hash!] :on-data-change	;) available options
```
Now we can move the data into VID/S block:
```
view [host 150x150 [vlist [drop-box* data= map-each i 10 [i]]]]
```
And as we can see `drop-box*` now starts with a properly selected item upon creation:

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-24.png)

### Adding a VID/S style

To ease the use of our template, we should also add a VID/S style. What auto-facets makes sense for a `drop-box*`? Obviously, we could auto-assign block to `data`. We could probably use `[left center right]` for alignments as well.

Styles reside in `spaces/VID/styles`, but since we're working within Spaces context, just `VID/styles` is fine.
Let's put this somewhere in our script before the `view` call, and test it out: 
```
VID/styles/drop-box*: [																						;<<<
	template: drop-box*									;) template used for make-space						;<<<
	facets: [																								;<<<
		block!	data									;) block! will be assigned to /data					;<<<
		left	[spaces/box/align/x: -1]				;) alignment words will evaluate given code			;<<<
		center	[spaces/box/align/x:  0]																	;<<<
		right	[spaces/box/align/x:  1]																	;<<<
	]																										;<<<
]																											;<<<

view [host 150x150 [vlist [drop-box* [a b c d e f] right]]]
```
Note that instead of `align/x` we use `spaces/box/align/x`, because our `tube`-based `drop-box*` fills the whole canvas anyway, and stretches the `box` (because it has nonzero default `weight`), so alignment should happen in the `box` to have a visible effect.

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-25.png)

Cool!

### Exposing inner facets

But in case one uses `align=` in VID/S now it is going to be useless, so let's just propagate `drop-box*` alignment down into the `box`:
```
declare-template 'drop-box*/tube [
	axes:   [e s]									;) east then south - most common flow direction
	margin: spacing: 5
	spaces: object [
		box:    make-space 'data-view []
		button: make-space 'triangle  [dir: 's size/x: 14]		;) arrow facing south
	]
	content: reduce [spaces/box spaces/button]
	
	align:      -1x0	#push spaces/box/align		;) to the left, but centered vertically					;<<<
	list-pages: 5		#type [integer!] (list-pages >= 1)		;) max drop-list height in drop-box's heights
	selected:   {}		#push spaces/box/data
	data:       []		#type [block! hash!] :on-data-change	;) available options
]
```
I moved `align:` below `spaces:` because `#push` path requires `spaces` to be present on first assignment.

This simplifies our VID/S style:
```
VID/styles/drop-box*: [
	template: drop-box*								;) template used for make-space
	facets: [
		block!	data								;) block! will be assigned to /data
		left	[align/x: -1]						;) alignment words will evaluate given code				;<<<
		center	[align/x:  0]																				;<<<
		right	[align/x:  1]																				;<<<
	]
]
```
But oops it doesn't work! Turns out we hit the Red bug [#5312](https://github.com/red/red/issues/5312) and reactivity happily skips the `/x:` assignment. We shouldn't panic though, and either rewrite it as `self/align/x: 1` or `align: 1x0`. The former is more general as it allows to combine vertical and horizontal alignments:
```
VID/styles/drop-box*: [
	template: drop-box*								;) template used for make-space
	facets: [
		block!	data								;) block! will be assigned to /data
		left	[self/align/x: -1]					;) alignment words will evaluate given code				;<<<
		center	[self/align/x:  0]					;@@ self/ is a workaround for #5312 - remove me later	;<<<
		right	[self/align/x:  1]																			;<<<
	]
]
```
| TIP | Always leave markers for used workarounds, so they can be easily located and removed when the underlying issue gets fixed |
|-|-|

Perhaps we should also propagate this alignment into the `drop-menu*` too:
```
wrap-data: func [item-data [any-type!] /local item] [
	item: make-space 'data-view item-template
	item/align: space/align																;<<<
	set/any 'item/data :item-data
	item
]
```

### Wrapping up

Last thing that bothers me is global words we have defined. Let's wrap our whole style into a context to avoid words pollution and our final script will look like this:
```
Red [needs: view]

#include %../everything.red

context with spaces/ctx expand-directives [												;<<<

	on-data-change: function [space [object!] word [word!] list [block! hash!]] [
		space/selected: any [:space/data/1  copy {}]
	]
	
	declare-template 'drop-box*/tube [
		axes:   [e s]									;) east then south - most common flow direction
		margin: spacing: 5
		spaces: object [
			box:    make-space 'data-view []
			button: make-space 'triangle  [dir: 's size/x: 14]		;) arrow facing south
		]
		content: reduce [spaces/box spaces/button]
		
	   	align:      -1x0	#push spaces/box/align		;) to the left, but centered vertically
		list-pages: 5		#type [integer!] (list-pages >= 1)		;) max drop-list height in drop-box's heights
		selected:   {}		#push spaces/box/data
		data:       []		#type [block! hash!] :on-data-change	;) available options
	]
	
	set-style 'drop-menu* get-style to path! 'cell
	define-styles [
		drop-box*: [
			below: [
				fill-pen off  line-width 1				;) line-width for the children
				push [
					scale 0.5 0.5  line-width 2			;) line-width for the frame
					box 1x1 (size * 2 - 1)
				]
			]
		]
		drop-menu*/list-view/window/list/item: [
			below: when lit? [pen off fill-pen (opaque 'text 10%) box 0x0 (size)]
		]
	]
	
	item-template: declare-class 'item-in-drop-menu/data-view [
		type:  'item
		wrap?: on
		lit?:  no		#type = [logic!] :invalidates	;) we'll set this to true for coloring
	]
	
	define-handlers [
		drop-box*: [
			on-down [space path event] [
				list: make-space 'cell [
					type:    'drop-menu*
					owner:   space
					margin:  5
					limits:  space/size .. (space/size * (1 by space/list-pages))
					content: make-space 'list-view [
						source: space/data
						wrap-data: func [item-data [any-type!] /local item] [
							item: make-space 'data-view item-template
							item/align: space/align
							set/any 'item/data :item-data
							item
						]
					]
				]
				corner: event/offset - path/2 + (space/size * 0x1)
				offset: face-to-window corner event/face 
				popups/show list offset
			]
		]
		
		drop-menu*: [
			on-down [space path event] [
				unless set [item:] locate path [obj - .. /type = 'item] [pass exit]
				space/owner/selected: item/data
				popups/hide event/face
			]
			on-over [space path event] [
				unless set [item: item-xy:] locate path [obj - .. /type = 'item] [pass exit]
				item/lit?: item-xy inside? item
			]
		]
	]
	
	VID/styles/drop-box*: [
		template: drop-box*								;) template used for make-space
		facets: [
			block!	data								;) block! will be assigned to /data
			left	[self/align/x: -1]					;) alignment words will evaluate given code
			center	[self/align/x:  0]					;@@ self/ is a workaround for #5312 - remove me later
			right	[self/align/x:  1]
		]
	]

];context with spaces/ctx expand-directives [

view [host 150x150 [vlist [drop-box* [a b c d e f] right]]]			;) just test code - to be removed
```
![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/drop-box-guide/drop-box-26.gif)

| TIP | Always start development of a new template in a new context, and within the `spaces/ctx` namespace |
|-|-|

This concludes our guide!

All that's left is to remove the `view` line, `#include` our widget and use it in our program! This is the only way to determine if our design is any good.
