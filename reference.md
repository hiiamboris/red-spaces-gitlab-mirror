---
gitea: none
include_toc: true
---

# Red Spaces Widget Reference

Explains how each Space template works.

A few terms for less confusion:
- *style*, *template style*, *styling* - refers to what happens in [`styles.red`](styles.red), i.e. change of visual appearance of a space
- *VID/S style* - refers to `style` keyword in VID/S and `spaces/VID/styles` map
- *template* - refers to a named block used to instantiate a space, held in `spaces/templates` map (main topic of this document)

## Space creation

### `anonymize`

A core concept in spaces is that each space object must be named. Name is what makes it possible to look up styles and choose proper event handlers, because there is no other connection between styles/events and the space object.

However all these names (words) have to belong to different contexts as they share spelling while referring to different `space!` objects.

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

Words created by this function appear in a lot of facets: `map`, `content`, `item-list`, `cell-map`, etc.

### `make-space` & `make-template`

Are the functions that should be used to create new space instances, and define new space templates.

```
>> ? make-space
USAGE:
     MAKE-SPACE type spec

DESCRIPTION: 
     Create a space from a template TYPE. 
     MAKE-SPACE is a function! value.

ARGUMENTS:
     type         [word!] "Looked up in templates."
     spec         [block!] "Extension code."

REFINEMENTS:
     /block       => Do not instantiate the object.
     /name        => Return a word referring to the space, rather than space object.

>> ?? make-template
make-template: func [
    "Declare a space template" 
    base [word!] "Type it will be based on" 
    spec [block!] "Extension code"
][
    make-space/block base spec
]
```
Similar to the native `make`, `spec` of `make-space` can add new facets to the spaces it creates.

### Usage scenarios examples

#### 1. Defining a new template (block) that could later be used to create new space objects

New templates should be placed into the `templates` map:
```
spaces/templates/bold-text: make-template 'text [	;) `text` is the prototype template, `bold-text` is a new one
	flags: [bold]									;) we define default `flags` in the spec
]
```
Now it can be used:
```
view [host [
	vlist [
		text "normal text"
		bold-text text="bold text"
	]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-new-template.png)

Note that there's no VID/S style or template style defined for it yet, so VID/S won't be able to use [auto-facets](vids.md#auto-facets), and font and color won't work (because their application for `bold-text` template must defined by `bold-text` style akin to what `text` style does).


#### 2. Creating a new named `space!` object inside another template

Let's consider a simple template consisting of two others. For simplicity, all sizes are fixed:
```
spaces/templates/boxed-image: make-template 'space [
	;) these two are objects:
	cell:  make-space 'cell  [limits: 70x60 .. 70x60]
	image: make-space 'image [limits: 60x50 .. 60x50]
	size:  70x60
	
	draw:  does [
		compose/only [
			(render 'cell) translate 5x5 (render 'image)
		]
	]
]
```
Let's test it:
```
view [host [
	boxed-image with [image/data: system/words/draw 60x50 [
		pen blue  triangle 5x10  35x10 20x40
		pen brick triangle 55x40 25x40 40x10
	]]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-new-space-object.png)

#### 3. Creating a new named `space!` object and getting it's name (as word) at the same time

This is an alias to `anonymize 'name make-space 'name [...]`, often used when reference to space object itself is not needed:
```
view [host [
	cell 100x50 content= make-space/name 'text [text: "abc"]	;) content facet expects a word! 
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-new-named-space.png)

### Testing

All examples of code in this reference (except those above, which are more explicit) can be tested using 3 methods:
1. In a standalone script:
   ```
   Red [needs: view]
   #include %spaces/everything.red
   view [host [
       ...code from the example...
   ]]
   ```
2. Input into Spaces console (started by `run.bat` or equivalent `red console.red` shell command) as:
   ```
   >> view [host [...code from the example...]]
   ```
3. Or just pasted into running [VID/S Polygon](programs/vids-polygon.red)


## Common facets

In contrast to REBOL & Red's `face!` object that always includes every possible facet, `space` is minimalistic and includes only those facets that each widget requires. And those usually vary, but some have **reserved** meaning (cannot be used for anything else):

| Facet | Type | Description |
|-|-|-|
| `size` | `pair!` `none!` | Size of this space in it's own coordinate system.<br> Usually updated during every `draw` call (as such, it is the *size of the last rendered frame* in a sequential chain of redraws), but sometimes fixed.<br> Used by container spaces (e.g. list) to arrange their items. <br> Can be `none` if space is infinite, or if it was never drawn yet. |
| `draw` | `func [] -> block!` | Should return a block of commands to render this space on the current frame.<br> Should also fill `map` with included spaces if they are interactive.<br> May support `/only xy1 xy2` refinement - to draw only a selected region, and `/on canvas` to auto-adjust it's size. |
| `rate` | `time!` `integer!` `float!` `none!` | Specifies rate of the `on-time` event. `time!` sets period, numbers set rate (1 / period).<br> Not usually present in most spaces by default, but can be added using `make-space` or `with [rate: ..]` keyword in VID/S.<br> If `none` or absent, no `on-time` event is generated. |
| `map` | `block!` | Only for container spaces: describes inner spaces geometry in this space's coordinate system.<br> Has format: `[name [offset: pair! size: pair!] name ...]`.<br> `name` is the name (word) of inner space that should refer to it's object.<br> Used for hittesting and tree iteration. |
| `into` | `func [xy [pair!]] -> [name xy']` | Only for container spaces: more general variant of `map`: takes a point in this space's coordinate system and returns name (word) of an inner space it maps to, and the point in inner space's coordinate system.<br> May return `none` if point does not land on any inner space.<br> Used in hittesting only, takes precedence over `map`.<br> If space supports dragging, then `into` should accept `/force name [word! none!]` refinement that takes full path to an inner space into which translation should happen even if `xy` point does not land on it. |
| `limits` | `none!` `range!` | Object with /min and /max size this space can span. See [VID/S manual](vids.md#constraining-the-size) on details. |
| `weight` | `none!` `integer!` `float!` | Used for relative scaling of items in containers like `tube`. `none` or `0` = never extend, positive values determine relative size extension (`1` is the default). Preferably should be set from styles. |
| `cache?` | `logic!` | Turns off caching of some space (for debugging or if look constantly changes). |
| `on-change*` | `func [word old new]` | Used internally to help enforce consistency, reset cache, etc. |

Some facets are not reserved or prescribed but are **recommended** as a guideline for consistency:

| Facet | Type | Description |
|-|-|-|
| `content` | `word!` `block! of words` `map! of words` | Used by container spaces to hold references to children. |
| `source`  | `block!` `map!` | Used by some container spaces as default data source. |
| `text`    | `string!` | Usually specifies text string for textual spaces. |
| `data`    | varies  | Specifies which data should be displayed if it's not always textual (e.g. button can accept multiple data types). |
| `origin`  | `pair!` | Point at which content should be placed in this space's coordinate system. |
| `margin`  | `pair!` | Adds space between space bounds and it's content. Preferably should be set from styles. |
| `spacing` | `pair!` | In containers with multiple items, adds space between adjacent ones. Preferably should be set from styles. |
| `align`   | `pair!` `block!` | In containers determines how items are aligned. Preferably should be set from styles. |
| `axis` or `axes` | `word!` `block!` | In containers determines primary/secondary axes of extension. |
| `color`   | `tuple!` | Used by VID/S to tell styles what pen color they should use. Styles decide how and if they use it. |
| `command` | `block!` | Used by clickable items to define on-click action. Event handlers decide how and if they use it. |
| `font`    | `object!` | An instance of `font!` object. Preferably should be set from styles. |

<details>
	<summary>Note on <code>map</code> vs <code>into</code></summary>

<br>

- hittesting is done with any of them, `into` takes precedence (they both make it possible to pass pointer events to inner spaces)
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
	draw:   []
	size:   0x0
	limits: none
]
```
Serves no other function: has zero size and draws nothing.\
Useful as a placeholder that should later be overridden.

Since all composite spaces consist of other smaller spaces, this minimalism plays a role in the resource usage. There can be tens to hundreds of thousands spaces present in the tree of a moderately complex layout.

## Timer

Template used to create timers:
```
spaces/templates/timer: make-template 'space [rate: none]
```
Timer is not required for `on-time` event handler to receive events. Any space that has a `rate` facet set will receive these. In fact `make-space 'space [rate: 1]` produces a space identical to `make-space 'timer [rate: 1]`.\
However `timer` makes the intent of code a tiny bit clearer. So it is advised to base timers on this space.

Note: for timers to work, they have to be `render`ed by their owner's `draw` function. This requirement is imposed by the necessity of having tree paths for each timer to be readily available, otherwise they consume too much resources.


## Stretch

Just an elastic spacer between other UI items (see [example in VID/S](vids.md#constraining-the-size)). Another (more readable) name is `<->`, i.e. a double arrow.

Has weight of `1`, which makes it stretch. See [VID/S manual](vids.md#weight-effect) on how weight works.


## Rectangle

Draws a simple box across it's `size`. To be used in other spaces (as interactive region). Currently used only to draw scrollbar's thumb.


| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-rectangle.png) | `rectangle with [margin: 5 size: 80x60]` |
|-|-|

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `margin` | integer! or pair! | horizontal and vertical space between the bounding box [0x0 size] and the drawn box outline (at the stroke center) |


## Triangle

Draws an [isosceles triangle](https://en.wikipedia.org/wiki/Isosceles_triangle). To be used in other spaces. Currently used only to draw scrollbar's arrows.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-triangle-n.png) | `triangle with [margin: 5 size: 80x60 dir: 'n]` |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-triangle-e.png) | **`triangle with [margin: 5 size: 80x60 dir: 'e]`** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-triangle-s.png) | **`triangle with [margin: 5 size: 80x60 dir: 's]`** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-triangle-w.png) | **`triangle with [margin: 5 size: 80x60 dir: 'w]`** |

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `margin` | integer! or pair! | horizontal and vertical space between the bounding box [0x0 size] and to the triangle's points (at the stroke center) |
| `dir` | word! | where it points to: `n`/`e`/`s`/`w` for north, east, south, west |



## Image

Basic image renderer. To be used in more complex templates or standalone. Canvas and limits are used to scale the image up/down when necessary.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-image.png) | <pre>image with [<br>    p: [translate 50x50 pen red line-width 2 spline -40x-28 0x-46]<br>    loop 20 [append p -1x1 * (reverse last p) * 0.9]<br>    data: system/words/draw 100x100 p<br>    margin: 5<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `data` | image! or none! | image to draw |
| `margin` | integer! or pair! | horizontal and vertical space between the bounding box and image itself; should be set in styles |
| `limits` | range! or none! | can be used to control image size; image aims at 100% scale when possible |


## Text

Basic single-line text renderer.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-text.png) | <pre>text with [<br>    text: "Single line text"<br>    margin: 10<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `text` | string! | obvious |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and text itself; should be set in styles |
| `font` | object! | an instance of `font!` object; should be set in styles |
| `color` | tuple! none! | if set, affects text color |
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`); should be set in styles; `wrap` flag would make it behave like `paragraph` |

## Paragraph

Basic multi-line text renderer. Wrap margin is controlled by canvas size, which is in turn constrained by /limits facet.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-paragraph.png) | <pre>paragraph with [<br>    margin: 20x10<br>    text: "You cannot hold back a good laugh any more than you can the tide. Both are forces of nature."<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `text` | string! | obvious |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and text itself; should be set in styles |
| `font` | object! | an instance of `font!` object; should be set in styles |
| `color` | tuple! none! | if set, affects text color |
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`); `flags: [wrap]` is the default, without it would behave like `text` |

## Link

Basic URL renderer, based on `paragraph`. Useful for embedding clickable references into the layout. 

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-link.png) | <pre>link with [<br>    text: https://codeberg.org/hiiamboris/red-spaces/src/branch/master/reference.md<br>]</pre> |
|-|-|

Inherits all of `paragraph` facets:

| facet  | type  | description |
|-|-|-|
| `text` | string! | obvious |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and text itself; should be set in styles |
| `font` | object! | an instance of `font!` object; should be set in styles |
| `color` | tuple! none! | if set, affects text color; defaults to light blue |
| `flags` | block! | a list of rich-text flags, defaults to `flags: [wrap underline]` |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `command` | block! | code to evaluate when link gets clicked; by default opens `text` in the browser |


## Box

Basic alignment box: aligns a single child space on the canvas.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box--1x-1.png) | <pre>box align= -1x-1 [text "aligned^/content"]</pre> |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box-0x-1.png) | **<pre>box align=  0x-1 [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box-1x-1.png) | **<pre>box align=  1x-1 [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box--1x0.png) | **<pre>box align= -1x0  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box-0x0.png)  | **<pre>box align=  0x0  [text "aligned^/content"]</pre> (default)** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box-1x0.png)  | **<pre>box align=  1x0  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box--1x1.png) | **<pre>box align= -1x1  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box-0x1.png)  | **<pre>box align=  0x1  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-box-1x1.png)  | **<pre>box align=  1x1  [text "aligned^/content"]</pre>** |

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to 0x0 (center) |
| `margin` | pair! integer! | horizontal and vertical space from the inner space to the bounding box of the canvas; should be set in styles |
| `content` | word! | name of the inner space; defaults to an empty space |

## Cell

`box` with a visible frame around (drawn by style).

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell--1x-1.png) | <pre>cell align= -1x-1 [text "aligned^/content"]</pre> |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell-0x-1.png) | **<pre>cell align=  0x-1 [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell-1x-1.png) | **<pre>cell align=  1x-1 [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell--1x0.png) | **<pre>cell align= -1x0  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell-0x0.png)  | **<pre>cell align=  0x0  [text "aligned^/content"]</pre> (default)** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell-1x0.png)  | **<pre>cell align=  1x0  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell--1x1.png) | **<pre>cell align= -1x1  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell-0x1.png)  | **<pre>cell align=  0x1  [text "aligned^/content"]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-cell-1x1.png)  | **<pre>cell align=  1x1  [text "aligned^/content"]</pre>** |

Inherits all facets from `box`:

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to 0x0 (center); should be set in styles |
| `margin` | pair! integer! | defaults to 1x1; should be set in styles |
| `content` | word! | name of the inner space; defaults to an empty space |


## Data-view

`box` variant that automatically turns data given to it into visual representation using [`VID/wrap-value`](vids.red) function:
- given `string!` uses [`text`](#text) or [`paragraph`](#paragraph) depending on `wrap?` value
- given `url!` uses [`link`](#link)
- given `image!` uses [`image`](#image)
- given `logic!` uses [`logic`](#logic)
- given `block!` uses [`row`](#row) with every value of it also wrapped by `VID/wrap-value`
- otherwise molds the data and uses `text` on it

Used in `button`, `list-view`, `grid-view` - in every space that displays *data*.

Inherits all facets from `box`:

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to -1x-1; should be set in styles |
| `margin` | pair! integer! | defaults to 1x1; should be set in styles |
| `content` | word! | name of the inner space; defaults to an empty space |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `data` | any-type! | data value to be shown (see the list above) |
| `spacing` | pair! integer! | when data is a block, sets spacing of it's items; should be set in styles |
| `font` | object! | when data is rendered using text or paragraph templates, affects font; should be set in styles |
| `wrap?` | logic! | when true, displays textual data using `paragraph` instead of `text`; should be set in styles |


## Clickable

Basic undecorated clickable area, extends [`data-view`](#data-view).

Inherits all of `data-view` facets:

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to -1x-1; should be set in styles |
| `margin` | pair! integer! | defaults to 1x1; should be set in styles |
| `spacing` | pair! integer! | when data is a block, sets spacing of it's items; should be set in styles |
| `content` | word! | name of the inner space; defaults to an empty space |
| `data` | any-type! | data value to be shown (see the list above) |
| `font` | object! | when data is rendered using text or paragraph templates, affects font; should be set in styles |
| `wrap?` | logic! | when true, displays textual data using `paragraph` instead of `text`; should be set in styles |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `command` | block! | code to evaluate when button gets pushed and then released |
| `pushed?` | logic! | reflects it's pushed state, change from `true` to `false` automatically triggers `command` evaluation |



## Button

Clickable button, extends [`clickable`](#clickable).


| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-button-1.png) | `button "OK"` |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-button-2.png) | **<pre>button with [<br>    data: system/words/draw 40x40 [<br>        pen red triangle 20x5 5x35 35x35<br>    ]<br>]</pre>** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-button-3.png) | **<pre>button with [<br>    data: reduce [<br>        system/words/draw 40x40 [<br>            pen red triangle 20x5 5x35 35x35<br>            text 19x15 "!"<br>        ]<br>        "ACHTUNG^/TEXT"<br>    ]<br>]</pre>** |

Tip: `system/words/draw` is used instead of `draw` when inside spaces context (`with`), as `draw` refers to it's rendering function.

Inherits all of `clickable` facets:

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to -1x-1; should be set in styles |
| `margin` | pair! integer! | defaults to 1x1; should be set in styles |
| `spacing` | pair! integer! | when data is a block, sets spacing of it's items; should be set in styles |
| `content` | word! | name of the inner space; defaults to an empty space |
| `data` | any-type! | data value to be shown (see the list above) |
| `font` | object! | when data is rendered using text or paragraph templates, affects font; should be set in styles |
| `wrap?` | logic! | when true, displays textual data using `paragraph` instead of `text`; should be set in styles |
| `command` | block! | code to evaluate when button gets pushed and then released |
| `pushed?` | logic! | reflects it's pushed state, change from `true` to `false` automatically triggers `command` evaluation |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `rounding` | integer! | button outline rounding radius in pixels (use `0` to draw square corners); should be set in styles |


## Field

Basic editable single-line text field, based on [`text`](#text).

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-field.png) | `field with [text: "edit me"]` |
|-|-|

Inherits all of `text` facets:

| facet  | type  | description |
|-|-|-|
| `text` | string! | current text content |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and text itself; should be set in styles |
| `font` | object! | an instance of `font!` object; should be set in styles |
| `color` | tuple! none! | if set, affects text color |
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`); should be set in styles; `wrap` flag would make it behave like `paragraph` |

| facet  | type  | description |
|-|-|-|
| `origin` | integer! | current offset of the text in the field in pixels (non-positive) |
| `selected` | pair! none! | currently selected part of text: `BEGINxEND`, where `begin` should not be bigger than `end` |
| `selection` | rectangle space object! | can be styled as `field/selection` |
| `caret` | rectangle space object! | can be styled as `field/caret` |
| `caret/width` | integer! | `caret` space width in pixels |
| `caret/offset` | integer! | current caret offset in chars |
| `caret/visible?` | logic! | whether caret is currently visible or not (focus indicator) |
| `history` | block! | internally used for undo/redo |

Note: `caret/offset` and `selected` facets use *offsets from head* as coordinates:
- `0` = no offset from the head, i.e. before the 1st char
- `1` = offset = 1, i.e. after 1st char
- `length? text` = offset from the head = text length, i.e. after last char

Field supports it's own *macro dialect*, invoked on it by it's `edit` function. Thanks to it, it's possible to control field behavior on a higher level, ensuring certain consistency level.

The dialect supports following commands:

| Command & Arguments | Description |
|-|-|
| `undo` | Undoes the last change |
| `redo` | Redoes the last undone change |
| `copy selected` | Copy current selection into clipboard (no effect if no selection) |
| `copy <pair!>` | Copy slice from pair/1 to pair/2 offsets into clipboard |
| `select none` | Deselects everything |
| `select all` | Selects everything |
| `select head` | Selects everything from caret to the head |
| `select tail` | Selects everything from caret to the tail |
| `select prev-word` | Selects everything from caret back until the start of the word |
| `select next-word` | Selects everything from caret forth until the end of the word |
| `select <pair!>` | Selects from pair/1 to pair/2 offsets |
| `select by <integer!>` | Selects from caret to caret+`integer` offset (can be negative) |
| `select to <integer!>` | Selects from caret to `integer` offset |
| `move head` | Move caret to the head |
| `move tail` | Move caret to the tail |
| `move prev-word` | Move caret back until the start of the word |
| `move next-word` | Move caret forth until the end of the word |
| `move sel-bgn` | Move caret to the start of the selection (no effect if no selection) |
| `move sel-end` | Move caret to the end of the selection (no effect if no selection) |
| `move by <integer!>` | Move caret by `integer` number of chars (can be negative) |
| `move to <integer!>` | Move caret to `integer` offset |
| `remove prev-word` | Delete text from caret back until the start of the word |
| `remove next-word` | Delete text from caret forth until the end of the word |
| `remove selected` | Delete currently selected text |
| `remove <integer!>` | Delete from caret to caret+integer (can be negative) |
| `insert <string!>` | Insert (trimmed) string at caret, shifting it to the end of insertion |


## Area

Not implemented yet.


## Logic

Concise display of `logic!` values.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-logic.png) | <pre>hlist [<br>	logic state= on<br>	logic state= off<br>]</pre> |
|-|-|

Supported facets:

| facet  | type  | description |
|-|-|-|
| `state` | logic! | Displayed state, true or false |

## Switch

Interactive binary switch. To be used as a base for labeled switches.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-switch.png) | <pre>hlist [<br>	switch state= on<br>	switch state= off<br>]</pre> |
|-|-|

Supported facets:

| facet  | type  | description |
|-|-|-|
| `state` | logic! | Displayed state, true or false |

## Label

High level text label, supporting up to 3 lines of text (label text and commentary) and a sigil (image or character).

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-label.png) | `label #"🚘" "Take a ride?^/waiting time ~2min"` |
|-|-|


Supported facets:

| facet  | type  | description |
|-|-|-|
| `margin` | integer! pair! | horizontal and vertical space between label and it's bounding box |
| `spacing` | integer! pair! | space between sigil and text |
| `image` | image! char! string! | sigil to display on the left of the text; can be empty `""` to display nothing but reserve the space for alignment |
| `text` | string! | label and commentary text, split on new-line chars |
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`, `wrap`); should be set in styles |


## Scrollbar

Obvious. To be used in other spaces, as by itself it's not interactive. Used in `scrollable` template. Uses `rectangle` and `triangle`.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-scrollbar-1.png) | `scrollbar with [size: 100x20 offset: 0.6 amount: 0.3 axis: 'x]` |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-scrollbar-2.png) | **`scrollbar with [size: 20x100 offset: 0.6 amount: 0.3 axis: 'y]`** |

| facet  | type  | description |
|-|-|-|
| `size` | pair! | size is fixed and should be defined |
| `axis` | word! | `x` or `y` - scrollbar orientation |
| `offset` | float! percent! | 0 to 1 (100%) - area before the thumb |
| `amount` | float! percent! | 0 to 1 (100%) - thumb area  |

Scrollbar will try it's best to adapt it's appearance to remain useable (visible, clickable) even with extreme values of it's facets.


## Scrollable

Wrapper for bigger (but finite) spaces. Automatically shows/hides scrollbars and provides event handlers to scroll it's content interactively.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-scrollable.png) | <pre>scrollable 100x100 [<br>	space size= 200x300<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `origin` | pair! | point in scrollable's coordinate system at which to place `content`: <0 to left above, >0 to right below |
| `content` | word! | name of the space it wraps, should refer to a space object |
| `hscroll` | scroller space object! | horizontal scrollbar; can be styled as `scrollable/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scroller space object! | vertical scrollbar; can be styled as `scrollable/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | scroller space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |


## Window

Used internally by `inf-scrollable` to wrap infinite spaces. Window has a size, while it's content may not have it. Window guarantees that `content/draw` of the infinite space is called with an `/only` refinement that limits the rendering area.

| facet  | type  | description |
|-|-|-|
| `size` | pair! none! | set by `draw` automatically, read-only for other code; it extends up to the smallest of `origin + content/size` (if defined) and `max-size` |
| `max-size` | pair! | fixed and should be defined - determines maximum size the window adapts |
| `content` | word! | name of the space it wraps, should refer to a space object |
| `origin` | pair! | point in window's coordinate system at which to place `content`: <0 to left above, >0 to right below |
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
- infer the answer from `content/size` if it's defined (e.g. content is finite but way too big to be rendered wholly)

`window/available?` should not normally be replaced, but instead a similar one should be defined by the `content` space.


## Inf-scrollable

Wrapper for infinite spaces: `scrollable` with it's `content` set to `window`. Automatically moves the window across content when it comes near the borders, provides relevant event handlers.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-inf-scrollable.png) | <pre>inf-scrollable with [<br>	size: 100x100<br>	window/content: make-space/name 'space [<br>		available?: func [axis dir from req] [req]<br>	]<br>]</pre> |
|-|-|

Inherits all of `scrollable` facets:

| facet  | type  | description |
|-|-|-|
| `origin` | pair! | point in inf-scrollable's coordinate system at which `window` is placed: <0 to left above, >0 to right below; combined with `window/origin` can be used to translate coordinates into `content`'s coordinate system |
| `content` | word! = `'window` | inherited from `scrollable` and should not be changed, set to `'window` |
| `hscroll` | scroller space object! | horizontal scrollbar; can be styled as `scrollable/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scroller space object! | vertical scrollbar; can be styled as `scrollable/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | scroller space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `pages` | integer! pair! | used to automatically adjust `window/max-size` as `self/size * pages` (e.g. if inf-scrollable is resized) |
| `window` | window space object! | used to limit visible (rendered) area to finite (and sane) size |
| `window/content` | word! | space to wrap, possibly infinite or half-infinite along any of X/Y axes, or just huge |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |
| `roll-timer` | timer space object! | controls jumping of the window e.g. if user drags the thumb or holds a PageDown key, or clicks and holds the pointer in scroller's paging area |
| `roll-timer/rate` | integer! float! time! | rate at which it checks for a jump |
| `roll` | function! | can be called to manually check for a jump |


## Container

Basic template for various layouts. Arranges multiple spaces in a predefined way.

| facet  | type  | description |
|-|-|-|
| `content` | block! of word!s | contains names of spaces to arrange and render |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector |

`items` is a picker interface that abstracts the data source:
- called as `items/size` it should return the number of items
- called as `items/pick i` it should return i-th item (i = 1,2,...,size)

Default `items` just acts as a wrapper around `content`. But can be redefined to use any other source. In this case `content` will be unused (though VID/S only supports `content` when it creates a pane, and such style would require a custom layout function for use in VID/S).

Container's `draw` function is extended with a `/layout type [word!] settings [block!]` refinement, that must be used by the space that uses this template. `type` is the name of one of layout arrangement functions, `settings` is a block of words, each referring to this layout's setting value. See below.

### Layouts

Are defined in [`layouts.red`](layouts.red) file. They are functions used to arrange a collection of spaces geometrically.

Layouts are defined in `spaces/layouts` context (it can be extended with more layouts). Each layout is an object that must define a `create` function with the following arguments:

| argument  | types  | description |
|-|-|-|
| spaces | block! or function! | list of spaces or a picker function |
| settings | block! | settings for layout |

Result of all layouts is a block: `[size [pair!] map [block!]]`, but map geometries also may contain `drawn` block (in addition to `offset` and `size`), which should be used to avoid extra `render` call.
		
There's no other strict requirement as long as layout function accepts arguments given to it by the `draw` function of the template that is built upon `container`.

`make-layout` is the primary interface for layout creation:
```
USAGE:
     MAKE-LAYOUT type spaces settings

DESCRIPTION: 
     Create a layout (arrangement of spaces on a plane). 
     MAKE-LAYOUT is a function! value.

ARGUMENTS:
     type         [word!] "Layout name (list, tube, ring)."
     spaces       [block! function!] "List of space names or a picker function."
     settings     [block!] "Block of words referring to setting values."
```

By default, three layouts are available out of the box: `list` (used in vlist/hlist), `tube` (used in row/column) and `ring` (used in ring menu popups).

#### Settings for list layout

| setting | types | constraints | description |
|-|-|-|-|
| axis | word! | `x` or `y` | primary axis of list's extension |
| margin |  integer! pair! | >= 0x0 | space between list's content and it's border |
| spacing | integer! pair! | >= 0x0 | space between adjacent list's items (only primary axis of the pair is used) |
| canvas | pair! none! | > 0x0 | area size on which list will be rendered |
| limits | range! none! | /min <= /max | constraints on the size |
| origin | pair! | unrestricted | point at which list's coordinate system origin is located |

#### Settings for tube layout

| setting | types | constraints | description |
|-|-|-|-|
| axes | block! of 2 words | any of `[n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s]` (unicode arrows `←→↓↑` are also supported) | primary (first) and secondary (second) axes of tube extension (run [`tube-test`](tests/tube-test.red) to figure it out) |
| align | block! none! | -1x-1 to 1x1 (9 variants) | alignment vector |
| margin |  integer! pair! | >= 0x0 | space between tubr's content and it's border |
| spacing | integer! pair! | >= 0x0 | space between adjacent tube's items (only primary axis of the pair is used) |
| canvas | pair! none! | > 0x0 | area size on which tube will be rendered |
| limits | range! none! | /min <= /max | constraints on the size |

#### Settings for ring layout

| setting | types | constraints | description |
|-|-|-|-|
| angle | integer! float! | unrestricted | clockwise angle from X axis to the first item |
| radius | integer! float! | >= 0 | distance from the center to closest points of items |
| round? | logic! | | false (default) - consider items rectangular, true - consider items round |



## List

A `container` that arranges spaces using `list` layout. VID/S defines styles `vlist` and `hlist` for convenience, based on this template.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-list.png) | <pre>vlist [<br>	button "button 1"<br>	button "button 2"<br>	button "button 3"<br>]</pre> |
|-|-|

Inherits all of `container` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of word!s | contains names of spaces to arrange and render (see [container](#container)) |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector (see [container](#container)) |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `margin` | integer! pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | integer! pair! | space between adjacent items, only chosen axis is used |
| `axis` | word! | `x` or `y` - list's primary axis of extension |

Note that list:
- contains spaces, not data
- is finite
- adjusts it's size to fit the given spaces


## List-view

An inf-scrollable that is used to display finite or infinite amount of data using list layout.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-list-view.png) | <pre>list-view data= func [/pick i /size] [if pick [i]]</pre> |
|-|-|

Note: above list is infinite because `data/size` returns `none`. `data/pick i` returns item number `i` itself, that's why it's populated with just numbers.

A lot of facets are inherited from [`inf-scrollable`](#inf-scrollable) and [`list`](#list):

| facet  | type  | description |
|-|-|-|
| `origin` | pair! | point in inf-scrollable's coordinate system at which `window` is placed: <0 to left above, >0 to right below; combined with `window/origin` can be used to translate coordinates into `content`'s coordinate system |
| `hscroll` | scroller space object! | horizontal scrollbar; can be styled as `list-view/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scroller space object! | vertical scrollbar; can be styled as `list-view/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | scroller space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |
| `pages` | integer! pair! | used to automatically adjust `window/max-size` as `self/size * pages` (e.g. if inf-scrollable is resized) |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |
| `roll-timer` | timer space object! | controls jumping of the window e.g. if user drags the thumb or holds a PageDown key, or clicks and holds the pointer in scroller's paging area |
| `roll-timer/rate` | integer! float! time! | rate at which it checks for a jump |
| `roll` | function! | can be called to manually check for a jump |
| `content` | word! = `'window` | points to `window`, should not be changed |
| `window` | window space object! | used to limit visible (rendered) area to finite (and sane) size |
| `window/content` | word! = `'list` | points to inner `list`, should not be changed |
| `list` | list space object! | inner (finite) list used to display currently visible page |
| `list/axis` | word! | list's primary axis of extension; defaults to `y` but can be changed when needed |
| `list/margin` | integer! pair! | horizontal and vertical space between the items and the bounding box; should be set in styles |
| `list/spacing` | integer! pair! | space between adjacent items, only chosen axis is used; should be set in styles |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `source` | block! | data to render in the list (items of any type - see [`data-view`](#data-view)) |
| `data` | `func [/pick i [integer!] /size]` | picker function (see below) |
| `wrap-data` | `func [item-data [any-type!]] -> space object!` | function that converts any `data` item into a `data-view` space; can be overridden for more control |

`data`'s interface:
- called as `data/size` it should return the number of items to render, or `none` if data is infinite
- called as `data/pick i` it should return i-th item (i > 0)

Default `data` just acts as a wrapper around `source`, picking from it and returning it's length. But can be redefined to use any other source. In this case `source` will be unused.

Note that list-view:
- contains data (not spaces), which it converts into spaces automatically using [`data-view`](#data-view) space. By overriding `list/items` it's possible to make an infinite list of spaces (though why?)
- can be infinite along it's axis (indexes from 1 to infinity)


## Tube

A `container` that arranges spaces using `tube` layout (aka flow layout). VID/S defines styles `row` and `column` for convenience, based on this template.

Supports configuration of direction and alignment.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-row.png) | <pre>row 150 [<br>	button "button 1"<br>	button "..2.."<br>	button "3"<br>	button "button 4"<br>]</pre> |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-column.png) | **<pre>column 0x0 .. (infxinf/x by 150) [<br>	button "button 1"<br>	button "..2.."<br>	button "3"<br>	button "button 4"<br>]</pre>** |


Here's a quick glance at how `list` is different from `tube`:

| | list | tube |
|-|-|-|
| example code | <pre>style box: cell 50x50 .. none sky<br>hlist [box box box box box]</pre> | <pre>style box: cell 50x50 .. none pink<br>row [box box box box box]</pre> |
| behavior | ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-list-resize.gif) | ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-row-resize.gif) |
| summary | <ul><li>always continues along the chosen axis<li>never stretches it's items along the chosen axis<li>expands itself over the canvas when it's too small<li>should be used with scrollers for clipped content to be accessible</ul> | <ul><li>attempts to fill the canvas by stretching it's items<li>tries not to extend over canvas when possible<li>when items don't fit in, starts another row or column</ul> |
| area of use | scrollable lists, or where layout should be guaranteed | flexible lists, that should fit the canvas, smart enough to split when they can't fit |


Inherits all of `container` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of word!s | contains names of spaces to arrange and render (see [container](#container)) |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector (see [container](#container)) |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `margin` | pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | pair! | horizontal or vertical space between adjacent items and rows/columns |
| `axes`  | block! = `[word! word!]` | primary and secondary flow directions: each word is one of `n w s e` or `← → ↑ ↓`; default for `tube` and `row` = `[e s]` (extend to the east then split southwise) |
| `align` | pair! or block! = `[word! word!]` | row and item alignment (see below), default = -1x-1 |

Alignment specification is supported in two forms:
- `pair!` -1x-1 to 1x1 - in this case pair/1 is alignment along primary axis (of extension), and pair/2 is alignment along secondary axis (of splitting):
  - `-1` aligns towards the negative side of the axis
  - `0` aligns close to the center along this axis
  - `-1` aligns towards the positive side of the axis
- `block! = [word! word!]` where each word is one of `n w s e` or `← → ↑ ↓` - in this case alignment is specified independently of axes, and is screen-oriented (north always points up, east to the right, etc)
  - there can be less than 2 words in the block: omitted alignments will be centered, e.g. `[n]` will center horizontally, but will align towards the top vertically
  - order of words is irrelevant, but alignments should obviously be orthogonal to each other

<details>
  <summary>
Expand to see all supported axes/align combinations.
  </summary>

<br>

Generated using [`tube-test.red`](tests/tube-test.red):

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/tube-axes-alignments-showcase.png)

</details>

## Ring

A `container` that arranges spaces using `ring` layout. Used by ring menu popup.


| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-ring.png) | <pre>ring [<br>	button "button 1"<br>	button "button 2"<br>	button "button 3"<br>	button "button 4"<br>	button "button 5"<br>]</pre> |
|-|-|

Inherits all of `container` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of word!s | contains names of spaces to arrange and render (see [container](#container)) |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector (see [container](#container)) |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `angle` | integer! float! | unrestricted | clockwise angle from X axis to the first item |
| `radius` | integer! float! | >= 0 | distance from the center to closest points of items |
| `round?` | logic! | | false (default) - consider items rectangular, true - consider items round |


## Grid

A composite template to arrange **spaces** (not data) in a grid.

Features:
- Grid's columns have fixed width, while rows can be fixed or auto-sized.
- Grid can either have infinite width, or automatically infer row height, but not both (it would be an equation with 2 unknowns).
- Grid can have infinite height.
- Grid cells can span multiple rows and/or columns.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-grid-template.png) | <pre>grid [<br>    at 2x1 image data= system/words/draw 40x40 [<br>    	pen red triangle 20x5 5x35 35x35<br>    ]<br>    at 1x2 cell [text "some text"]<br>    at 3x2 field "field"<br>    at 2x3 button "button"<br>]</pre> |
|-|-|

| facet  | type | description |
|-|-|-|
| `margin` | pair! | horizontal and vertical space between cells and the bounding box |
| `spacing` | pair! | horizontal and vertical space between adjacent cells |
| `content` | map! of `pair! (col x row) -> word! (space name)` | used to place spaces at specific row/col positions |
| `cells` | `func [/pick xy [pair!] /size]` | picker function that abstracts `content` |
| `widths` | map! of `integer! (col) -> integer! (width)` | defines specific column widths in pixels; `widths/default` is a fallback value for absent column numbers; `widths/min` is only used by `autofit` function; columns are numbered from `1` |
| `heights` | map! of `integer! (row) -> integer! or word! = 'auto` | defines specific row heights in pixels; `heights/default` is a fallback value that defaults to `auto`; `heights/min` sets the minimum height for `auto` rows (to prevent rows of zero size); rows are numbered from `1` |
| `bounds` | pair! or block! `[x: lim-x y: lim-y]` | defines grid's number of rows and columns: `none` = infinite, `auto` = use upper bound of `cells`, integer = fixed |
| `wrap-space` | `function! [xy [pair!] name [word!]] -> cell-name [word!]` | function that wraps spaces returned by `cells` into a `cell` template, for alignment and background drawing; can be overridden |


`cells` is a picker interface that abstracts the cell selection:
- called as `cells/size` it should return a pair (number of columns, number of rows)
- called as `cells/pick xy` it should return xy-th item (xy >= 1x1)

Default `cells` just acts as a wrapper around `content`, picking spaces from it or returning it's bounds. In case it's redefined, `content` will be unused.

The following public API is exposed by each `grid` space:

| Function | Description |
|-|-|
| `get-span` | Given cell coordinate (>= 1x1), returns it's span (>= 1x1) | 
| `set-span` | Changes span of a cell | 
| `get-first-cell` | Given cell coordinate (>= 1x1), returns coordinate of a multicell that contains it; for single cells, returns the cell itself |
| `get-offset-from` | Measures pixel offset (pair) between top left corners of two cells |
| `locate-point` | Given coordinate in pixels, returns corresponding cell coordinate and offset within that cell |
| `row-height?` | Measures height of a row (useful when it's not fixed) |
| `col-width?` | Measures width of a column (simple abstraction over `widths` map) |
| `cell-size?` | Measures size of a cell or multicell starting at given cell coordinate |
| `is-cell-pinned?` | True if cell at a given cell coordinate is pinned |
| `infinite?` | True if not all grid dimensions are finite |
| `calc-bounds` | Returns grid's number of columns and rows (useful e.g. if `bounds` facet is set to `auto`) |
| `calc-size` | Measures grid's total width and height (may require rendering of all it's items) |

For more info about these functions, create a grid `g: make-space 'grid []` and inspect each function e.g. `? g/get-span`.


## Grid-view

An [`inf-scrollable`](#inf-scrollable) wrapper around [`grid`](#grid), used to display finite or infinite amount of **data**.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-gridview.png) | <pre>grid-view with [<br>	grid/widths:  #(default 40)<br>	grid/heights: #(default 20)<br>	data: func [/pick xy /size] [any [xy []]]<br>]</pre><br>Tip: `data` returns `[]` as size, so both `size/x` and `size/y` yield `none` (infinite in both directions) |
|-|-|

Inherits all of [`inf-scrollable`](#inf-scrollable) facets:

| facet  | type | description |
|-|-|-|
| `origin` | pair! | offset of unpinned cells (mirrors `grid/origin`), together with `window/origin` can be used to translate coordinates into `grid`'s coordinate system |
| `hscroll` | scroller space object! | horizontal scrollbar; can be styled as `grid-view/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scroller space object! | vertical scrollbar; can be styled as `grid-view/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | scroller space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |
| `roll-timer` | timer space object! | controls jumping of the window e.g. if user drags the thumb or holds a PageDown key, or clicks and holds the pointer in scroller's paging area |
| `roll-timer/rate` | integer! float! time! | rate at which it checks for a jump |
| `roll` | function! | can be called to manually check for a jump |
| `pages` | integer! pair! | used to automatically adjust `window/max-size` as `self/size * pages` (e.g. if grid-view is resized) |
| `window` | window space object! | used to limit visible (rendered) area to finite (and sane) size |
| `window/content` | word! = `'grid` | points to inner `grid` and should not be changed |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |

Adds new facets:

| facet | type | description |
|-|-|-|
| `grid` | grid space object! | can be used to access wrapped [`grid`](#grid) space with all of it's facets |
| `grid/pinned` | pair! (col,row) | defines the headings size - rows and columns that won't be scrolled |
| `source` | map! of `pair! (col,row) -> any-type!` | data to render in the cells (using [`data-view`](#data-view)); `source/size` should be set to a number of columns & rows in the data (pair!) |
| `data` | `func [/pick xy [pair!] /size]` | picker function (see below) |
| `wrap-data` | `func [item-data [any-type!]] -> space object!` | function that wraps values returned by `data` into a `data-view` space; can be overridden for more control |


`data` is a picker interface that abstracts the data selection:
- called as `data/size` it should return the X and Y data limits as either:
  - a `pair!` if data is finite
  - a block `[x: #[none] y: #[none]]` if at least one limit is infinite (the other one can be an integer; also `none`s can be omitted following block selection rules: `[]` is equivalent to `[x: none y: none]`)
- called as `data/pick xy` it should return the data value at (row=y, col=x), xy >= 1x1

Default `data` just acts as a wrapper around `source`, picking from it and returning it's `source/size` value. But can be redefined to use any other source. In this case `source` will be unused.


[comment]: # (not sure icon template is worth documenting / making available by default, we'll see)

