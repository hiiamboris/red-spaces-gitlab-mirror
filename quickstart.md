---
gitea: none
include_toc: true
---

# Red Spaces Quick Start Tutorial

Will guide you through the basics required to use Spaces in your code.

## What's this

[Red language](http://red-lang.org/) comes with a set of OS-native widgets - [Faces](https://w.red-lang.org/en/view/#face-types).\
They're great: familiar look-n-feel, respect for user settings, speed, etc.\
But they're limited: simplistic, not customizable, portability goes down with the number of features, Red support for them varies between platforms, and is often packed with bugs due to complexity of OS APIs.

To provide for the need, this project introduces **[Draw](https://w.red-lang.org/en/draw)-based widgets into Red.**\
These widgets are **called Spaces**. Name comes from the fact that each widget is a separate *coordinate space* that knows how to draw itself.

Spaces provide infrastructure and model using which **you can**:
- leverage fully portable advanced widgets (like `grid-view` with infinite data)
- build custom web-like UI with only a fraction of effort
- scale, rotate or distort the UI, yet still process pointer events properly
- animate the UI or create 2D games

## Setup

Prerequisites: [Red](http://www.red-lang.org/p/download.html) (only automated builds!!), [Git](https://git-scm.com/downloads)

Spaces depend on the helpful functions & macros from [mezz warehouse](https://codeberg.org/hiiamboris/red-common). So, in your favorite directory, run:
```
git clone https://codeberg.org/hiiamboris/red-common common
git clone https://codeberg.org/hiiamboris/red-spaces spaces
```

<details>
	<summary>
		If you would prefer not to mess with Git, do it your way, just ensure a file structure similar to the following is created:
	</summary>

```
%spaces/
%spaces/auxi.red 
%spaces/comments 
%spaces/creators.md 
%spaces/debug-helpers.red 
%spaces/events.red 
%spaces/everything.red 
%spaces/focus.red 
%spaces/hittest.red 
%spaces/pen-test.red 
%spaces/quickstart.md 
%spaces/README.md 
%spaces/reference.md 
%spaces/single-click.red 
%spaces/spaces.red 
%spaces/standard-handlers.red 
%spaces/styles.red 
%spaces/tabbing.red 
%spaces/timers.red 
%spaces/traversal.red 

%spaces/tests/ 
%spaces/tests/grid-test1.red 
%spaces/tests/grid-test2.red 
%spaces/tests/grid-test3.red 
%spaces/tests/grid-test4.red 
%spaces/tests/grid-test5.red 
%spaces/tests/grid-test6.red 
%spaces/tests/grid-test7.red 
%spaces/tests/list-test.red 
%spaces/tests/README.md 
%spaces/tests/scrollbars-test.red 
%spaces/tests/spiral-test.red 
%spaces/tests/web-test.red

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

Put it another way, if you download a zip from the repository site, don't forget to rename directories after unzipping, to `spaces` and `common`.



## Hello world

Create the following `hello-space.red` script:

```
Red [needs: view]						;) we need the View module to be able to show graphics

#include %spaces/everything.red			;) add Spaces to the current program

view [
	host [								;) create a Host face that can contain spaces
		vlist [									;) draw a vertical list on the Host
			text "Hello, space!"
			button "OK" 80 focus [unview]		;) unview generates an error - #5124 :)
		]
	]
]
```

Code assumes /spaces and /common reside in this script's directory, if they're not, fix the path. Then run the script: `red hello-space.red`.

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-hello.png)

A few notes:

- `host` is a face on which all spaces are drawn. Like [`panel`](https://w.red-lang.org/en/vid/#panel) but for Spaces.
- `host` uses it's `rate` and `draw` facets internally, requires `all-over` flag to be set, but other facets can be repurposed as you see fit.
- The example is written in a mix of DSLs: standard [VID](https://doc.red-lang.org/en/vid.html) starts after `view [` and is used to describe faces layout. After `host [` VID ends and specialized [VID/S](#layout-dsl) begins.
- In the example above you might have noticed that I never specified `vlist`'s size. Most spaces will automatically adjust their `/size` facet when drawn. `vlist` adjusts it's size to fit it's whole content. See [Constaining the size](Constaining the size) chapter of VID/S manual for details and common usage examples.


<details>
	<summary>
		The same example can also be written on a lower level, without VID or VID/S, but using manual layout construction which is faster but very boring
	</summary>

```
Red [needs: view]						;) we need the View module to be able to show graphics

#include %spaces/everything.red			;) add Spaces to the current program

list: make-space 'list [				;) make-space is used to instantiate spaces
	axis: 'y							;) lists can be horizontal(x) or vertical(y)
	margin: spacing: 10x10				;) list is tight by default, this makes it spacious

	content: reduce [					;) content is a block of NAMES of spaces

		make-space/name 'text [			;) each make-space/name returns a name referring to an object
			text: "Hello, space!"		;) like `make prototype [spec..]`, make-space allows to define facets
		]
		make-space/name 'button [
			data: "OK"					;) data can be any Red type
			limits: 80 .. 80			;) limit with min=max fixes the button's size
			command: [unview]			;) code that is evaluated when button is released
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
window/offset: system/view/screens/1/size - window/size / 2		;) center the window

show window								;) finally, we display the layout
set-focus host							;) focus host for it to receive keyboard events
do-events								;) enter View event loop
```
Note: in the above `..` is an operator that produces a `range!` object.

</details>


### Anything more complex?

I'm planning to create a set of explained templates for common layouts when the time permits.\
For now, the only thing to reverse-engineer is [tests](tests/).


## Layout DSL

The fastest way to write your own layout is to copy and study examples from [VID/S manual](vids.md)! **Seriously!!!**

For simple tasks it will be enough.

More in-depth usage is covered in [Tinkerer's manual](manual.md).

There's also a bunch of [test scripts](tests/README.md) that can serve as a study material and as templates.



