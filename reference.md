---
gitea: none
include_toc: true
---

# Red Spaces Widget Reference

Explains how each Space works.

## Space creation

### Anonymize

A core concept in spaces is that each space object must be named. Name is what makes it possible to look up styles and choose proper event handlers, because there is no other connection between styles/events and the space object.

However all these names (words) have to belong to different contexts as they share spelling.

For this `anonymize` function is used:
```
>> ? anonymize
USAGE:
     ANONYMIZE word value

DESCRIPTION: 
     Return WORD bound in an anonymous context and set to VALUE. 
     ANONYMIZE is a function! value.

ARGUMENTS:
     word         [word!] 
     value        [any-type!] 
```

Words created by this function in a lot of facets: `map`, `content`, `item-list`, `cell-map`, etc.

### Make-space

Is the function that should be used to create new space instances and define new space templates.

```
>> ? make-space
USAGE:
     MAKE-SPACE type spec

DESCRIPTION: 
     Create a space from a template TYPE. 
     MAKE-SPACE is a function! value.

ARGUMENTS:
     type         [word!] "Looked up in spaces."
     spec         [block!] "Extension code."

REFINEMENTS:
     /block       => Do not instantiate the object.
     /name        => Return a word referring to the space, rather than space object.
```

Forms:
- `make-space 'type [...]` - returns instantiated space object. Good when you have a named facet and want it to refer to a space object. Similar to the native `make`, `spec` of `make-space` can add new facets to the spaces it creates.
- `make-space/block 'type [...]` - returns spec block used to create a space object. Good for defining new space types (they're all blocks). To create new templates, they should be placed into the `spaces` map: `spaces/templates/new-type: make-space/block 'template [...]`.
- `make-space/name 'type [...]` - returns word `type` in an anonymous context, referring to an instantiated space object. Good for putting this name into `scrollable/content`, `list/item-list` or `grid/cell-map` facets.


### Testing

All examples of code in this reference can be tested like this:
```
Red [needs: view]

recycle/off                 
#include %red-spaces/everything.red

view [
    host [
        ...code from the example...
    ]
]
```


## Common facets

In contrast to REBOL & Red's `face!` object that always includes every possible facet, `space` is minimalistic and includes only those facets that each widget requires. And those usually vary, but some have **reserved** meaning:

| Facet | Type | Description |
|-|-|-|
| `size` | `pair!` `none!` | Size of this space in it's own coordinate system.<br> Often updated during every `draw` call (as such, it is the *size of the last rendered frame* in a sequential chain of redraws), but sometimes fixed.<br> Used by container spaces (e.g. list) to arrange their items. <br> Can be `none` if space is infinite, or if it was never drawn yet. |
| `draw` | `func [] -> block!` | Should return a block of commands to render this space on the current frame.<br> Should also fill `map` of composite spaces.<br> May support `/only xy1 xy2` refinement - to draw only a selected region. |
| `rate` | `time!` `integer!` `float!` `none!` | Specifies rate of the `on-time` event. `time!` sets period, numbers set rate (1 / period).<br> Not usually present in most spaces by default, but can be added using `make-space` or `with [rate: ..]` keyword in VID.<br> If `none` or absent, no `on-time` event is generated. |
| `map` | `block!` | Only for container spaces: describes the inner spaces geometry in this space's coordinate system.<br> Has format: `[name [offset: pair! size: pair!] name ...]`.<br> `name` is the name (word) of inner space that should refer to it's object.<br> Used for hittesting and tree iteration. |
| `into` | `func [xy [pair!]] -> [name xy']` | Only for container spaces: more general variant of `map`: takes a point in this space's coordinate system and returns name (word) of an inner space it maps to, and the point in inner space's coordinate system.<br> May return `none` if point does not land on any inner space.<br> Used in hittesting only, takes precedence over `map`.<br> If space supports dragging, then `into` should accept `/force name [word! none!]` refinement that determines the inner space. |
| `on-change*` | `func [word old new]` | Used internally to help enforce consistency, reset cache, etc. |

Some facets are not reserved or prescribed but are **recommended** as a guideline for consistency:

| Facet | Type | Description |
|-|-|-|
| `content` | `word!` | Used when space has single user-defined inner space (like `scrollable`) |
| `margin` | `pair!` | Adds space between space bounds and it's content. Preferably should be set from styles. |
| `origin` | `pair!` | Point at which content should be placed in this space's coordinate system. |
| `font`   | `object!` | An instance of `font!` object. Preferably should be set from styles. |

<details>
	<summary>Note on `map` vs `into`</summary>

<br>
- hittesting is done with any of them, `into` takes precedence (this makes it possible to pass pointer events to inner spaces)
- tree iteration (e.g. when tabbing) uses `map` only, but it uses only names from the map (not the geometry)

  So if `into` is supported, then `map` can contain spaces of empty/invalid geometry to simplify the code:
  ```
  map: [inner1 [] inner2 [] ...]
  map: [inner1 inner2 ...]
  ```

</details>

Spaces do not impose any structural limitations. If a space can hold a box or a piece of text, then it can hold *any* other space, no matter how complex it is.



## Space

Minimal space template to build upon:
```
spaces/templates/space: [
	draw: []
	size: 0x0
]
```
Serves no other function: has zero size and draws nothing.\
Useful as a placeholder that should later be overridden.

Since all composite spaces consist of other smaller spaces, this minimalism plays a role in the resource usage.

## Timer

Template used to create timers:
```
spaces/templates/timer: make-space/block 'space [rate: none]
```
Timer is not required for `on-time` event handler to receive events. Any space that has a `rate` facet set will receive these. In fact `make-space 'space [rate: 1]` produces a space identical to `make-space 'timer [rate: 1]`.\
However `timer` makes the intent of code a tiny bit clearer. So it is advised to base timers on this space.


## Rectangle

Draws a simple box across it's `size`. To be used in other spaces. Currently used only to draw scrollbar's thumb.

| ![](https://i.gyazo.com/1cb18bf4f6e539433df65ca2b8b396a7.png) | `rectangle with [margin: 5 size: 80x60]` |
|-|-|

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `margin` | integer! or pair! | horizontal and vertical space between the bounding box [0x0 size] and the drawn box outline (at the stroke center) |


## Triangle

Draws an [isosceles triangle](https://en.wikipedia.org/wiki/Isosceles_triangle). To be used in other spaces. Currently used only to draw scrollbar's arrows.

| ![](https://i.gyazo.com/467883de636221da6e9d2833de9e4c39.png) | `triangle with [margin: 5 size: 80x60 dir: 'n]` |
|-|-|
| ![](https://i.gyazo.com/619a17d97c4c533eeb61dc36a6d8fa41.png) | **`triangle with [margin: 5 size: 80x60 dir: 'e]`** |
| ![](https://i.gyazo.com/f8d583d917e417057832dafcc665bf1b.png) | **`triangle with [margin: 5 size: 80x60 dir: 's]`** |
| ![](https://i.gyazo.com/b3472ef7f5c08e7df22239ff66aaccfc.png) | **`triangle with [margin: 5 size: 80x60 dir: 'w]`** |

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `margin` | integer! or pair! | horizontal and vertical space between the bounding box [0x0 size] and to the triangle's points (at the stroke center) |
| `dir` | word! | where it points to: `n`/`e`/`s`/`w` for north, east, south, west |



## Image

Basic image renderer that has 2 modes: size adjusts to image / image adjusts to size.

| ![](https://i.gyazo.com/95bfc0e8c6ba133f244315d9619fedcd.png) | <pre>image with [<br>    p: [translate 50x50 pen red line-width 2 spline -40x-28 0x-46]<br>    loop 20 [append p -1x1 * (reverse last p) * 0.9]<br>    data: system/words/draw size: 100x100 p<br>    margin: 5<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `autosize?` | logic! | default: `on` = space size adjusts to image; `off` = image gets compressed/expanded to fit the size |
| `size` | pair! | should be set if `autosize? = off`, otherwise set by `draw` automatically |
| `data` | image! | image to draw |
| `margin` | pair! | horizontal and vertical space between the bounding box and image itself; should be set in styles |



## Paragraph

Basic text renderer.

| ![](https://i.gyazo.com/bae37d89c0d89f05136daecf3bcb7cc4.png) | <pre>paragraph with [<br>    margin: 20x10<br>    width: 100<br>    text: "You cannot hold back a good laugh any more than you can the tide. Both are forces of nature."<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `size` | pair! | inferred automatically, set by `draw` |
| `width` | integer! none! | used to wrap the text, `none` = don't wrap, otherwise width in pixels |
| `text` | string! | obvious |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and text itself; should be set in styles |
| `font` | object! | an instance of `font!` object; should be set in styles |



## Data-view

Renderer of arbitrary data:
- given `string!` uses [`paragraph`](#paragraph)
- given `image!` uses [`image`](#image)
- given `block!` uses [`list`](#list)
- otherwise molds the data and uses `paragraph`

Used in `button`, `list`, `grid` - in every space that displays data.

| facet  | type  | description |
|-|-|-|
| `size` | pair! | inferred automatically, set by `draw` |
| `data` | any-type! | renderer is chosen based on type of data (see above) |
| `width` | integer! none! | used to wrap the text, `none` = don't wrap, otherwise width in pixels |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and content; should be set in styles |
| `spacing` | pair! integer! | horizontal and vertical space between adjacent items (only if `data` is a `block!`); should be set in styles |



## Button

Basic clickable button, extends [`data-view`](#data-view).

| ![](https://i.gyazo.com/8f5bfa054728fab1e595b8fc35504d63.png) | `button with [data: "OK" width: 80]` |
|-|-|
| ![](https://i.gyazo.com/0630764821104d331f1a6f0b24db221b.png) | **<pre>button with [<br>    data: system/words/draw 40x40 [<br>        pen red triangle 20x5 5x35 35x35<br>    ]<br>]</pre>** |
| ![](https://i.gyazo.com/04117da4dfc5a790820d4bdb453f4180.png) | **<pre>button with [<br>    data: reduce [<br>        system/words/draw 40x40 [<br>            pen red triangle 20x5 5x35 35x35<br>            text 19x15 "!"<br>        ]<br>        "ACHTUNG^/TEXT"<br>    ]<br>]</pre>** |

Inherits all of `data-view` facets:

| facet  | type  | description |
|-|-|-|
| `size` | pair! | inferred automatically, set by `draw` |
| `data` | any-type! | renderer is chosen based on type of data (see above) |
| `width` | integer! none! | used to wrap the text, `none` = don't wrap, otherwise width in pixels |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and content; should be set in styles |
| `spacing` | pair! integer! | horizontal and vertical space between adjacent items (only if `data` is a `block!`); should be set in styles |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `command` | block! | code to evaluate when button gets pushed and then released |
| `pushed?` | logic! | reflects it's pushed state, change from `true` to `false` automatically triggers `command` evaluation |
| `rounding` | integer! | button outline rounding radius in pixels (use `0` to draw square corners); should be set in styles |

Tip: use `system/words/draw` instead of `draw` when inside spaces context, as `draw` refers to it's rendering function.



## Field

Basic editable text field, based on [`scrollable`](#scrollable). Covers both single and multi-line text input.

Needs more work currently.

| ![](https://i.gyazo.com/62e91ca8ceb9e97f8a6afb03e6588650.png) | `field with [size: 100x30 text: "edit me"]` |
|-|-|

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `text` | string! | text to render inside using [`paragraph`](#paragraph) |
| `wrap?` | logic! | turns on/off automatic wrapping of `text` |
| `caret` | rectangle space object! | can be replaced/styled |
| `caret-index` | integer! | caret position: `0` = before 1st char, `1` = after 1st char, `2` = after 2nd, etc |
| `caret-width` | integer! | `caret` space width in pixels |




## Scrollbar

Obvious. To be used in other spaces, as by itself it's not interactive. Used in `scrollable` style. Uses `rectangle` and `triangle`.

| ![](https://i.gyazo.com/a83446e3a150aeff16c4b289793d60a6.png) | `scrollbar with [size: 100x20 offset: 0.6 amount: 0.3 axis: 'x]` |
|-|-|
| ![](https://i.gyazo.com/fbc37007791a1b25588291e53f53e56d.png) | **`scrollbar with [size: 20x100 offset: 0.6 amount: 0.3 axis: 'y]`** |

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `axis` | word! | `x` or `y` - scrollbar orientation |
| `offset` | float! percent! | 0 to 1 (100%) - area before the thumb |
| `amount` | float! percent! | 0 to 1 (100%) - thumb area |

Scrollbar will try it's best to adapt it's appearance to remain useable (visible, clickable) even with extreme values of it's facets.


## Scrollable

Wrapper for bigger (finite) spaces. Automatically shows/hides scrollbars and provides event handlers to scroll it's content interactively.

| ![](https://i.gyazo.com/6d5ec0cd103e15ae967b4b6b69beb0c8.png) | <pre>scrollable with [size: 100x100] [<br>	space with [size: 200x300]<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `origin` | pair! | point in scrollable's coordinate system at which to place `content`: <0 to left above, >0 to right below |
| `content` | word! | name of the space it wraps, should refer to a space object |

`hscroll`, `vscroll` and `scroll-timer` facets (spaces) also may be customized, though it should not be required normally. Notably `hscroll/size` and `vscroll/size` control scrollers thickness, and `scroll-timer/rate` controls how often scroll events are produced when the user clicks and holds one of the arrows or paging areas.

Controlling code should otherwise not poke into scrollbars, but read/change the `origin` to move content around or retrieve it's location.


## Window

Used internally to wrap infinite spaces. Window has a size, while it's content may not have it. Window guarantees that `content/draw` is called with an `/only` refinement that limits the rendering area.

| facet  | type  | description |
|-|-|-|
| `size` | pair! none! | size is set by `draw` automatically, read-only for other code; it extends up to the smallest of `origin + content/size` (if defined) and `max-size` |
| `max-size` | pair! | fixed and should be defined - determines maximum size the window adapts |
| `content` | word! | name of the space it wraps, should refer to a space object |
| `map/(get content)/offset` | pair! | point in window's coordinate system at which to place `content`: <0 to left above, >0 to right below |
| `available?` | function! (see below) | used by the window to measure nearby content - to move window around and to determine it's `size` |

`available?` function has the following spec:
```
function [
	"Should return number of pixels up to REQUESTED from AXIS=FROM in direction DIR"
	axis      [word!]    "x/y"
	dir       [integer!] "-1/1"
	from      [integer!] "axis coordinate to look ahead from"
	requested [integer!] "max look-ahead required"
]
```
It is used to determine if window can be moved across it's `content`, without knowing it's size (as it may have infinite size).

Example - to ask `content` if it stretches for at most 500 pixels to the right from point `300x200`:
```
available? 'x 1 300 500
```
which should return a number from 0 to 500, depending on how many pixels are available in that direction

By default it is defined to:
- call `content/available?` if that function is defined in `content` (with the same arguments)
- infer the answer from `content/size` if it's defined

This function should not normally be replaced, but instead a similar one should be defined by the `content` space.



## Inf-scrollable

Wrapper for infinite spaces: `scrollable` with it's `content` set to `window`. Automatically moves the window across content when it comes near the borders, provides relevant event handlers.

| ![](https://i.gyazo.com/aaa27a9537a6d18fdd5b5ee87f01ec71.png) | <pre>inf-scrollable with [<br>	size: 100x100<br>	window/content: make-space/name 'space [<br>		available?: func [axis dir from req] [req]<br>	]<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `origin` | pair! | point in inf-scrollable's coordinate system at which `window` is placed: <0 to left above, >0 to right below; combined with `window/map/(get window/content)/offset` can be used to translate coordinates into `content`'s coordinate system |
| `content` | word! = `'window` | inherited from `scrollable` and should not be changed, set to `'window` |
| `window/content` | word! | space to wrap, possibly infinite or half-infinite along any of X/Y axes |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |
| `pages` | pair! | used to automatically adjust window/max-size from `self/size * pages` |
| `roll-timer/rate` | integer! float! time! | how often window can jump e.g. if user drags the thumb or holds a PageDown key |




## Container

Template for various layout styles. Arranges multiple spaces in a predefined way.

| facet  | type  | description |
|-|-|-|
| `item-list` | block! of word!s | contains names of spaces to arrange and render |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector |

`items` is a picker interface that abstracts the data source:
- called as `items/size` it should return the number of items
- called as `items/pick i` it should return i-th item (i > 0)

Default `items` just acts as a wrapper around `item-list`. But can be redefined to use any other source. In this case `item-list` will be unused.

Container's `draw` function is extended with a `/layout lobj [object!]` refinement, that must be used by the space that uses this template.

### Layouts

Are defined in [`layouts.red`](layouts.red) file. They are objects used to arrange a collection of spaces visually.

Layout's interface is defined as follows:

| facet  | type  | description |
|-|-|-|
| `margin` | `pair!` (in) | horizontal and vertical space between the items and the bounding box |
| `place` | `func [item [word!]]` (in) | should be called to place a space on the layout |
| `map` | `block!` or `func [] -> block!` (out) | in the same format as `/map` facet of spaces; is built up by `place` calls and should be called to obtain the final result |
| `size` | `pair!` (out) | full size of the layout with items placed so far |
| `content-size` | `pair!` (out) | size of layout's content with items placed so far (not including margins) |

Tip: every item added into a layout may move the previously placed items, so `map` should only be accessed after all of the items were added.

Implemented layouts so far:

| name | description |
|-|-|
| `spaces/layouts/list` | Simply stacks given items along given axis, adding spacing. Supports same facets as `list` space: `axis`, `origin`, `margin`, `spacing` |
| `spaces/layouts/tube` | Arranges items into rows and fits rows into a tube of fixed width. See [`tube` space](#tube) for details. |



## List

A `container` that arranges spaces using `spaces/layouts/list`.

| ![](https://i.gyazo.com/32f6522fc5f1e8f86446c3bfc3e8fd33.png) | <pre>list with [axis: 'y] [<br>	button with [data: "button 1"]<br>	button with [data: "button 2"]<br>	button with [data: "button 3"]<br>]</pre> |
|-|-|

| facet  | type | description |
|-|-|-|
| `item-list` | block! of word!s | contains names of spaces to arrange and render (see [container](#container)) |
| `items` | function! | more generic item selector (see [container](#container)) |
| `margin` | pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | pair! | horizontal or vertical space between adjacent items, depending on chosen axis |
| `axis` | word! | `x` or `y` - list orientation |

Note that list:
- contains spaces, not data
- is finite
- adjusts it's size to fit the given spaces


## List-view

An inf-scrollable that is used to display finite or infinite amount of data using list layout.

| ![](https://i.gyazo.com/c6d424e529458493e10698ba2804c6ab.png) | <pre>list-view with [<br>	size: 100x100<br>	data: func [/pick i /size] [if pick [i]]<br>]</pre> |
|-|-|

Note: above list is infinite because `data/size` returns `none`. `data/pick i` returns item number `i` itself, that's why it's populated with numbers.

Some facets are inherited from [`inf-scrollable`](#inf-scrollable):

| facet  | type | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `origin` | pair! | point in inf-scrollable's coordinate system at which `window` is placed: <0 to left above, >0 to right below; combined with `window/map/(get window/content)/offset` can be used to translate coordinates into `content`'s coordinate system |
| `jump-length` | integer! >= 0 | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! >= 0 | determines how near is "near it's borders", in pixels |
| `pages` | pair! | used to automatically adjust window/max-size from `self/size * pages` |
| `roll-timer/rate` | integer! float! time! | how often window can jump e.g. if user drags the thumb or holds a PageDown key |

Additionally it supports:

| facet  | type | description |
|-|-|-|
| `list` | space object! | an extended [`list`](#list) instance with all of it's facets; it's `/axis`, `/margin` and `/spacing` facets are up to you to change |
| `source` | block! | data to render in the list (items of any type - see [`data-view`](#data-view)) |
| `data` | `func [/pick i [integer!] /size]` | more generic data selector |
| `wrap-data` | `func [item-data [any-type!]] -> space object!` | function that converts any data item into a `data-view` space; can be overridden for more control |

`data` is a picker interface that abstracts the data source:
- called as `data/size` it should return the number of items to render, or `none` if data is infinite
- called as `data/pick i` it should return i-th item (i > 0)

Default `data` just acts as a wrapper around `source`, picking from it and returning it's length. But can be redefined to use any other source. In this case `source` will be unused.

Note that list-view:
- contains data, which it converts into spaces automatically using [`data-view`](#data-view) space. By overriding `list/items` it's possible to make an infinite list of spaces (though why?)
- can be half-infinite (indexes from 1 to infinity)
- has fixed predefined size



## Grid

A composite style to arrange spaces in a grid.

- Grid's columns have fixed width, while rows can be fixed or auto-sized.
- Grid can either have infinite width, or automatically infer row height, but not both (it would be an equation with 2 unknowns).
- Grid can have infinite height.
- Grid cells can span multiple rows and/or columns.


| ![](https://i.gyazo.com/6a9bf52d297b4eaa4d9c053b723e5c8f.png) | <pre>grid with [<br>    extend cell-map reduce [<br>        1x2 make-space/name 'paragraph [text: "paragraph"]<br>        3x2 make-space/name 'field [text: "field"]<br>        2x1 make-space/name 'image [<br>            data: system/words/draw 40x40 [<br>                pen red triangle 20x5 5x35 35x35]<br>        ]<br>        2x3 make-space/name 'button [data: "button"]<br>    ]<br>    heights/default: 'auto<br>]</pre> |
|-|-|

| facet  | type | description |
|-|-|-|
| `size` | pair! | inferred automatically, set by `draw` |
| `margin` | pair! | horizontal and vertical space between cells and the bounding box |
| `spacing` | pair! | horizontal and vertical space between adjacent cells |
| `cell-map` | map! of pair! (col,row) -> word! (space name) | used to place spaces at specific row/col positions |
| `cells` | `func [/pick xy [pair!] /size]` | more generic cell selector |
| `widths` | map! of integer! (col) -> integer! (width) | defines specific column widths in pixels, `widths/default` is a fallback value |
| `heights` | map! of integer! (row) -> integer! or word! `'auto` (height) | defines specific row heights in pixels, `heights/default` is a fallback value |
| `min-row-height` | integer! (height) | for heights marked as `'auto` defines their minimum height (useful if having empty rows to prevent them from have zero size) |
| `pinned` | pair! (col,row) | defines the headings size - rows and columns that won't be scrolled |
| `limits` | pair! or block! `[x: lim-x y: lim-y]` | defines grid's number of rows and columns: `none` = infinite, `auto` = use upper bound of `cells`, integer = fixed |

`cells` is a picker interface that abstracts the cell selection:
- called as `cells/size` it should return a pair (number of columns, number of rows)
- called as `cells/pick xy` it should return i-th item (i > 0)

Default `cells` just acts as a wrapper around `cell-map`, picking spaces from it or returning it's bounds. But can be redefined. In this case `cell-map` will be unused.


<details>
<summary>
To work with cell span the following API is used: `get-span`, `set-span`, `get-first-cell`
</summary>

```
>> g: make-space 'grid []
>> ? g/set-span
USAGE:
     G/SET-SPAN first span

DESCRIPTION: 
     Set the SPAN of a FIRST cell, breaking it if needed. 
     G/SET-SPAN is a function! value.

ARGUMENTS:
     first        [pair!] {Starting cell of a multicell or normal cell that should become a multicell.}
     span         [pair!] {1x1 for normal cell, more to span multiple rows/columns.}

REFINEMENTS:
     /force       => Also break all multicells that intersect with the given area.

>> ? g/get-span
USAGE:
     G/GET-SPAN xy

DESCRIPTION: 
     Get the span value of a cell at XY. 
     G/GET-SPAN is a function! value.

ARGUMENTS:
     xy           [pair!] "Column (x) and row (y)."

>> ? g/get-first-cell
USAGE:
     G/GET-FIRST-CELL xy

DESCRIPTION: 
     Get the starting row & column of a multicell that occupies cell at XY. 
     G/GET-FIRST-CELL is a function! value.

ARGUMENTS:
     xy           [pair!] {Column (x) and row (y); returns XY unchanged if no such multicell.}

```

</details>

Note that grid contains spaces in it's cells, not data.


## Grid-view

An [`inf-scrollable`](#inf-scrollable) wrapper around [`grid`](#grid), used to display finite or infinite amount of data.

| ![](https://i.gyazo.com/c0aa7e84b9c0bcc8c299b100718c3346.png) | <pre>grid-view with [<br>    size: 100x100<br>    grid/heights/default: 20<br>    grid/widths/default: 40<br>    data: func [/pick xy /size] [<br>        either pick [xy][ [] ]<br>    ]<br>]</pre> |
|-|-|

Grid-view infers it's limits from data: `limits: data/size`. As a consequence, above grid-view is half-infinite in both directions because `data/size` returns `[]` and thus `limits/x` and `limits/y` both are `none`.

Some facets are inherited from [`inf-scrollable`](#inf-scrollable):

| facet  | type | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `origin` | pair! | point in inf-scrollable's coordinate system at which `window` is placed: <0 to left above, >0 to right below; combined with `window/map/(get window/content)/offset` can be used to translate coordinates into `content`'s coordinate system |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |
| `pages` | pair! | used to automatically adjust window/max-size from `self/size * pages` |
| `roll-timer/rate` | integer! float! time! | how often window can jump e.g. if user drags the thumb or holds a PageDown key |

Additionally it supports:

| facet  | type | description |
|-|-|-|
| `source` | map! of pair! (col,row) -> any-type! | data to render in the cells (using [`data-view`](#data-view)); `source/size` should be set to a number of columns & rows in the data (pair!) |
| `data` | `func [/pick xy [pair!] /size]` | more generic data selector |
| `wrap-data` | `func [xy [pair!] item-data [any-type!]] -> space object!` | function that converts any data into a `data-view` space; uses column width of `xy/x`; can be overridden for more control |
| `grid` | grid space object! | can be used to access wrapped [`grid`](#grid) space with all of it's facets |


`data` is a picker interface that abstracts the data source:
- called as `data/size` it should return the X and Y data limits as:
  - a `pair!` if data is finite
  - a block `[x: #[none] y: #[none]]` if at least one limit is infinite (the other one can be an integer; also `none`s can be omitted: `[]`)
- called as `data/pick xy` it should return the item at (row=y, col=x), x > 0, y > 0

Default `data` just acts as a wrapper around `source`, picking from it and returning it's `source/size` value. But can be redefined to use any other source. In this case `source` will be unused.

Note that `grid-view` contains *data*, which it transforms into spaces automatically.


# Tube

Container that places items into rows of fixed width, and stacks rows on top of each other. Unlike grid, has no columns and no support for big number of items. Similar to VID's standard flow layout.

Supports direction and alignment.

| ![](https://i.gyazo.com/ac67631a29d0d84f75f92de372125ff9.png) | <pre>tube with [width: 130] [<br>	button with [data: "button 1"]<br>	button with [data: "..2.."]<br>	button with [data: "3"]<br>	button with [data: "button 4"]<br>]</pre> |
|-|-|


| facet  | type | description |
|-|-|-|
| `item-list` | block! of word!s | contains names of spaces to arrange and render (see [container](#container)) |
| `items` | function! | more generic item selector (see [container](#container)) |
| `margin` | pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | pair! | horizontal or vertical space between adjacent items, depending on chosen axis |
| `axes`  | block! = `[word! word!]` | primary and secondary flow directions: each word is one of `n w s e`; default = `[s e]` |
| `align` | block! = `[integer! integer!]` | row and item alignment: each integer is one of `-1 0 1`; default = `[-1 -1]` |
| `width` | integer! > 0 | max extent along secondary direction (tube width); should be no less than max item size or that item will stick out |

Tube layout has 2 *orthogonal* axes:

<img width=300 src=https://i.gyazo.com/5fd8f0caaaa9312bbfa05baf8b12e9f5.png></img>

Rows are stacked along *primary axis*, it's size is extended to fit all items.\
Items within row are stacked along *secondary axis*, it's size equals `width` and is fixed, items that do not fit go to next row (but no less than 1 item per row).\
Axes are specified as `n` (north = 0x-1), `s` (south = 0x1), `w` (west = -1x0), `e` (east = 1x0).

Finished rows get aligned along secondary axis using `align/1`:
- `-1` to align towards primary axis
- `1` to align outwards from primary axis
- `0` to center in `width`

Items within finished rows get aligned along primary axis using `align/2`:
- `-1` to align towards secondary axis
- `1` to align outwards from secondary axis
- `0` to center in row height

Margin and spacing are expressed in space coordinates and do not rotate with the axes.

<details>
  <summary>
Expand to see all supported axes/align combinations.
  </summary>

<br>
Generated using [`tube-test.red`](tests/tube-test.red):

![](https://i.gyazo.com/d2bb4c569b7b796fe77bc5f572570dde.png)

</details>



