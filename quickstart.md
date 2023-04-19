---
gitea: none
include_toc: true
---

# Red Spaces Quick Start Tutorial

Will guide you through the basics required to use Spaces in your code.

## What's this

[Red language](http://red-lang.org/) comes with a set of OS-native widgets - [Faces](https://github.com/red/docs/blob/master/en/view.adoc#face-types).\
They're great: familiar look-n-feel, respect for user settings, speed, etc.\
But they're limited: simplistic, not customizable, portability goes down with the number of features, Red support for them varies between platforms, and is often packed with bugs due to complexity of OS APIs.

To provide for the need, this project introduces **[Draw](https://github.com/red/docs/blob/master/en/draw.adoc)-based widgets into Red.**\
These widgets are **called Spaces**. Name comes from the fact that each widget is a separate *coordinate space* that knows how to draw itself.

Spaces provide infrastructure and model using which **you can**:
- leverage fully portable advanced widgets (like `grid-view` with infinite data)
- build custom web-like UI with only a fraction of effort
- scale, rotate or distort the UI, yet still process pointer events properly
- animate the UI or create 2D games

## Setup

Prerequisites: [Red](http://www.red-lang.org/p/download.html) (only automated builds!!), [Git](https://git-scm.com/downloads)

Spaces depend on the helpful functions & macros from [the mezz warehouse](https://codeberg.org/hiiamboris/red-common). So, in your favorite directory, run:
```
git clone https://codeberg.org/hiiamboris/red-common common --depth=1
git clone https://codeberg.org/hiiamboris/red-spaces spaces --depth=1
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

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/example-hello.png)

A few notes:

- `host` is a face on which all spaces are drawn. Like [`panel`](https://github.com/red/docs/blob/master/en/vid.adoc#panel) but for Spaces.
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

		make-space 'text [				;) each make-space creates and returns a new space object
			text: "Hello, space!"		;) like `make prototype [spec..]`, make-space allows to define facets
		]
		make-space 'button [
			data: "OK"					;) data for button can be any Red type
			limits: 80 .. 80			;) limit with min=max fixes the button's size (`..` creates a range!)
			command: [unview]			;) code that is evaluated when button is released
		]
	]
]

host: make-face 'host					;) host face we need to draw spaces on
host/space:  list						;) host must have exactly one space attached to it - here it's `list`
host/draw:   render host				;) `render` returns a list of draw commands, but also sets the /size facet of spaces
host/size:   list/size					;) now we know how big host face we need from previously set list/size
host/offset: 10x10						;) apply default VID margin

window: make-face 'window				;) create window to put host into
window/pane: reduce [host]				;) add host to it
window/size: host/size + 20x20			;) add default VID margins to host/size to infer window/size
window/offset: system/view/screens/1/size - window/size / 2		;) center the window

show window								;) finally, we display the layout
focus-space host/space/content/2		;) focus the button
do-events								;) enter View event loop
```

</details>


### Anything more complex?

I'm planning to create a set of explained templates for common layouts when the time permits.\
For now, the only thing to reverse-engineer is [tests](tests/).


## Layout DSL

The fastest way to write your own layout is to copy and study examples from [VID/S manual](vids.md)! **Seriously!!!**

For simple tasks it will be enough.

More in-depth usage is covered in [Tinkerer's manual](manual.md).

There's also a bunch of [test scripts](tests/README.md) that can serve as a study material and as templates.


## Tips

### Debug mode

Spaces can operate in *debug* or *release* mode.

Debug mode is used during development: it will do many extra checks to ensure early error detection, at the cost of some performance (in some cases it can halve FPS).

Release mode is used for end products. It has all those checks disabled.

If you open [everything.red](everything.red), you'll see roughly the following:
```
#include %../common/debug.red						;-- need #debug macro so it can be process rest of this file
#debug off										;-- turn off type checking and general (unspecialized) debug logs
; #debug set draw									;-- turn on to see what space produces draw errors
; #debug set profile								;-- turn on to see rendering and other times
; #debug set changes								;-- turn on to see value changes and invalidation
; #debug set cache 									;-- turn on to see what gets cached (can be a lot of output)
; #debug set sizing 								;-- turn on to see how spaces adapt to their canvas sizes
; #debug set focus									;-- turn on to see focus changes and errors
; #debug set events									;-- turn on to see what events get dispatched by hosts
; #debug set timer									;-- turn on to see timer events
; #debug set styles									;-- turn on to see which styles get applied
; #debug set grid-view
; #debug set list-view

#include %../common/assert.red
#assert off
```
Debugging and assertions are turned off by default to make demos faster (ships in release mode).

If you plan using Spaces in development, you should comment `#debug off` and `#assert off` lines until your program is ready. This will switch it into debug mode.

### Compilation

Due to numerous issues in include system, compilation is currently rather tricky. It should not be required until you come to release your product in executable form, since Spaces do not use any R/S code. When you do, the following steps should help you:
1. Ensure you're not trying to compile your script from within `spaces/` directory. Bug [#4249](https://github.com/red/red/issues/4249) won't let you. Put your script outside `spaces/`.
2. Download the [inline tool](https://gitlab.com/hiiamboris/red-cli/-/tree/master/mockups/inline) binary, put it into `PATH` or where your script is located.
3. Run `inline -e <your-script.red> <output.red>` command from the command line. This will inline every included file, preprocess it and save as `output.red`. Result is a standalone script!
4. Compile the `output.red` as you usually would (`redc -c output.red` or `redc -r output.red`). You can use `-o` option to control output binary name.

If you cross compile, you'll need to provide the same `-t <platform>` option to both `inline` and `redc`!
