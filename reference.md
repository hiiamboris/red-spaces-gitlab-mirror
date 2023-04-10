---
gitea: none
include_toc: true
---

# Red Spaces Widget Reference

Explains how each Space template works.

A few terms for less confusion:
- *style*, *template style*, *styling*, *stylesheet* - refers to what happens in [`styles.red`](styles.red), i.e. change of visual appearance of a space
- *VID/S style* - refers to `style` keyword in VID/S and `spaces/VID/styles` map
- *template* - refers to a named block used to instantiate a space, held in `spaces/templates` map (main topic of this document)

## Space creation

### `make-space`

Used to create new space instances from a known template name.

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
```
Similar to the native `make`, `spec` of `make-space` can add new facets to the spaces it creates.

#### `declare-template`

Used to create new templates.
```
>> ? declare-template
USAGE:
     DECLARE-TEMPLATE [name-base spec]

DESCRIPTION: 
     Declare a named class and put into space templates. 
     DECLARE-TEMPLATE is a function! value.

ARGUMENTS:
     name-base    [path!] "template-name/prototype-name."
     spec         [block!] 
```
`name-base` should be a path of two words: template name and prototype name (e.g. `'my-widget/space` or `'my-list/list`). This allows to inherit class info from the prototype - see [classy-object](https://codeberg.org/hiiamboris/red-common/src/branch/master/classy-object.red) for more background.

`spec` may contain any extended class syntax supported by `classy-object`.

### Usage scenarios examples

#### 1. Defining a new template that could later be used to create new space objects

```
declare-template 'bold-text/text [					;) `text` is the prototype template, `bold-text` is a new one
	flags: [bold]									;) we define default `flags` in the spec
]
```
Now it can be used:
```
view [host [
	vlist [
		text "normal text"
		bold-text text="bold text"					;) template name used to instantiate a space
	]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-new-template.png)

Note that there's no VID/S style or template style defined for it yet, so VID/S won't be able to use [auto-facets](vids.md#auto-facets), and font and color won't work (because their application for `bold-text` template must defined by `bold-text` style akin to what `text` style does).


#### 2. Altering existing template

```
declare-template 'cell/cell [						;) new template has the same name as the existing one
	margin: 10x10									;) new default for existing facet
	user-data: "test data"							;) new facet that will exist in all cell spaces created after
]
```

#### 3. Creating a new `space!` object inside another template or as a child

Let's consider a simple template consisting of two others. For simplicity, all sizes are fixed:
```
declare-template 'boxed-image/space [
	;) these two are objects:
	cell:  make-space 'cell  [limits: 70x60 .. 70x60]
	image: make-space 'image [limits: 60x50 .. 60x50]
	size:  70x60
	
	draw:  does [
		compose/only [
			(render cell) translate 5x5 (render image)
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

Child space created manually example:
```
view [host [
	cell 100x50 content= make-space 'text [text: "abc"]
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
3. Or just pasted into running [VID/S Polygon](programs/vids-polygon.red) window


## Common facets

In contrast to REBOL & Red's `face!` object that always includes every possible facet, `space` is minimalistic and includes only those facets that each widget requires. And those usually vary.

`space!` object itself defines a minimal set of facets:

| Facet | Type | Description |
|-|-|-|
| `type` | `word!` | Used for styles and event handler lookups. Usually equals space's template name, but can be renamed freely. |
| `size` | `pair!` `none!` | Size of this space in it's own coordinate system.<br> Usually updated during every `draw` call (as such, it is the *size of the last rendered frame* in a sequential chain of redraws), but sometimes fixed.<br> Used by container spaces (e.g. list) to arrange their items. <br> Can be `none` if space is infinite, or if it was never drawn yet. |
| `draw` | `block!`<br>`func [] -> block!` | Should return a block of commands to render this space on the current frame.<br> Should also fill `map` with included spaces if they are interactive.<br> May support `/window xy1 xy2` refinement - to draw only a selected region, and `/on canvas fill-x fill-y` to auto-adjust its size. |
| `parent` | `none!` `object!` | After space is rendered, contains it's owner object. |
| `limits` | `none!` `range!` | Object with /min and /max size this space can span. See [VID/S manual](vids.md#constraining-the-size) on details. |
| `cache` | `none!` `block!` | List of cached words (usually `[size map]`). Turns off caching if set to `none`. |
| `cached` | `block!` | Used internally to hold cached data. |
| `on-change*` | `func [word old new]` | Used internally by the class system to help enforce consistency, types, reset cache, etc. |

They are chosen to be mandatory because they are either strictly required, or (as is the case for /limits) apply to all spaces and can be assigned at runtime.

---

Some other facets are not mandatory but have a **reserved** meaning (cannot be used for anything else):

| Facet | Type | Description |
|-|-|-|
| `rate` | `time!` `integer!` `float!` `none!` | Specifies rate of the `on-time` event. `time!` sets period, numbers set rate (1 / period).<br> Not usually present in most spaces by default, but can be added using `make-space` or `with [rate: ..]` keyword in VID/S.<br> If `none` or absent, no `on-time` event is generated. |
| `map` | `block!` | Only for container spaces: describes inner spaces geometry in this space's coordinate system.<br> Has format: `[child [offset: pair! size: pair!] child ...]`.<br> Used for hittesting and tree iteration. |
| `into` | `func [xy [pair!]]`<br>`-> [child xy']` | Only for container spaces: more general variant of `map`: takes a point in this space's coordinate system and returns an inner space it maps to, and the point in inner space's coordinate system.<br> May return `none` if point does not land on any inner space.<br> Used in hittesting only, takes precedence over `map`.<br> If space supports dragging, then `into` should accept `/force child [object! none!]` refinement that should enforce coordinate translation into chosen child even if `xy` point does not land on it. |
| `weight` | `number!` | Used for relative scaling of items in containers like `tube`. `0` = never extend, positive values determine relative size extension (`1` is the default). Preferably should be set from styles. |
| `kit` | `object!` | Shared kit object (see [below](#kit)). |
| `on-invalidate` | <pre>func [<br>	space [object!]<br>	cause [object! none!]<br>	scope [word! none!]<br>]</pre> | Custom invalidation function, if cache is managed by the space itself. |

---

Some facets are not reserved or prescribed but have a **recommended** meaning as a guideline for consistency:

| Facet | Type | Description |
|-|-|-|
| `content` | `word!` `block! of spaces` `map! of spaces` | Used by container spaces to hold references to children. |
| `source`  | `block!` `map!` | Used by some container spaces as default data source. |
| `items`   | `function!` | Used by container spaces as an abstraction over `source`. |
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
| `timeline` | `object!` | Timeline of recorded events (see [below](#timelines)). |

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

Spaces do not impose any structural limitations. If a space can hold a box or a piece of text, then it can hold *any* other space, no matter how complex it is. The only requirement is that same space should not normally appear in multiple places on the tree.

### Kit

`kit` facet is present in templates spaces that want provide functions to read, interpret and modify their state. Having a set of functions inside every space object is quite RAM-expensive, so instead spaces of the same template contain a link to a shared kit object that contains all the functions.

Since these functions are shared, they need to know which space they should operate upon. Rather than adding a `space [object!]` argument to all of them (it becomes way too verbose), I made them implicitly receive space object from the kit entry point called `batch`. 

<details>
<summary><code>batch</code> global function is used to access functions in the kit...</summary>

```
>> ? batch
USAGE:
     BATCH space plan

DESCRIPTION: 
     Evaluate plan within space's kit. 
     BATCH is a function! value.

ARGUMENTS:
     space        [object!] 
     plan         [block!] 
```
Example usage (on document `doc`):
```
batch doc [
	select-range none
	move-caret here - 1
	remove-range 0x1 + here
	insert-items "text"
]
```

</details>

`batch` evaluates given `plan` while implicitly passing its `space` argument to all the functions. That's why we don't have to write `move-caret doc (here doc) - 1` but just `move-caret here - 1`. This requires an extra `bind` call on every `plan` evaluation, but is a small price to pay compared to both the verbosity of extra argument and having a per-object copy of all functions.

On top of normal functions that depend on space's state only, kit may have a `frame` object with its own functions subset. This subset contains functions that are only valid after a render (i.e. they read data from the `map` or other facets generated for a single frame). Examples are 2D caret locations, row count and geometry, and so on.


<details>
<summary>If a space has a <code>/kit</code> object, to see a list of functions supported by it you can use <code>help</code>...</summary>

```
>> text: make-space 'text []					;) space we want to inspect 

>> batch text [help self]						;) list of general functions
SELF is an object! with the following words and values:
     clone         function!     []
     format        function!     []
     length        function!     Get text length.
     everything    function!     Get full range of text.
     selected      function!     Get selection range or none.
     select-range  function!     Replace selection.
     frame         object!       [line-count point->caret caret-box item-box item-boxes sections]
     do-batch      function!     (Generated) Evaluate plan for given space.
     
>> batch text [help frame]						;) list of frame functions
FRAME is an object! with the following words and values:
     line-count    function!     Get line count on last frame.
     point->caret  function!     Get caret offset and side near the point XY on last frame.
     caret-box     function!     Get box [xy1 xy2] for the caret at given offset and side on last frame.
     item-box      function!     Get box [xy1 xy2] for the char at given index on last frame.
     item-boxes    function!     Get boxes [xy1 xy2 ...] for all chars in given range on last frame (unifies subsequent boxes).
     sections      function!     Get section widths on last frame as list of integers.
```

A few notes:
- `do-batch` is an internal auto-generated entry point called by `batch`. Without it, the other functions won't work.
- `clone` function is used by clipboard to obtain stateless deep copies of live space objects. Space must have it in the kit to be copyable.
- `format` function is used whenever a space must be converted to plain text, e.g. when sharing it via clipboard with other programs.
- `frame/sections` function is documented in [rich-paragraph](#sectioning).
- Generally, naming of similar functions is kept consistent across templates. E.g. editable text spaces all use [`key->plan`](key-plan.red) to interpret input, which then calls `selected`, `everything`, `undo`, `redo`, `move-caret`, `select-range`, `insert-items`, `remove-range`, `copy-range`, etc.

</details> 

### Timelines

`/timeline` facet can be set to a `timeline!` object (used by `document` mainly) that holds all events that led the space from its initial state to the current one. Used by `undo`/`redo`.

Timeline object can be shared across multiple spaces (of any template), because each event holds a link to the event receiver.

Main functions in the timeline are:
- `undo` - undoes last event
- `redo` - redoes next event
- `put space [object!] left [block!] right [block!]` - adds an event to the timeline with a reference to the receiver (space); `left` is the code to evaluate when undoing this event, `right` - when redoing it

[comment]: # (need to document the rest of timeline once it matures)

### Clipboard

Due to limitations of native `read-clipboard` and `write-clipboard` functions, Spaces use their own `clipboard` implementation.

```
>> ? clipboard/read
USAGE:
     CLIPBOARD/READ 

DESCRIPTION: 
     Get clipboard contents. 
     CLIPBOARD/READ is a function! value.

REFINEMENTS:
     /text        => Return text even if data is non-textual.
     
>> ? clipboard/write
USAGE:
     CLIPBOARD/WRITE content

DESCRIPTION: 
     Write data to clipboard. 
     CLIPBOARD/WRITE is a function! value.

ARGUMENTS:
     content      [object! string!] 
```

It currently supports the following formats:
- `text!` (plain text string)
- `rich-text-span!` (items of hypertext - chars and space objects)
- `rich-text-block!` (whole paragraphs, of `rich-content` template)

[comment]: # (more can be documented, e.g. how to create a new format, how to treat it)


## Space

Minimal space template to build upon:
```
spaces/templates/space: declare-class 'space [
	type:	'space
	size:    0x0
	draw:    []   	
	limits:  none
	parent:  none	
	cache:   [size]	
	cached:  tail copy [0.0 #[none]]
]
```
Serves no other function: has zero size and draws nothing.\
Useful as a placeholder that should later be overridden.

Since all composite spaces consist of other smaller spaces, this minimalism plays a role in the resource usage. There can be tens to hundreds of thousands spaces present in the tree of a moderately complex layout.

## Timer

Template used to create timers:
```
declare-template 'timer/space [rate: none]
```
Timer is not required for `on-time` event handler to receive events. Any space that has a `rate` facet set will receive these. In fact `make-space 'space [rate: 1]` produces a space identical to `make-space 'timer [rate: 1]`.\
However `timer` makes the intent of code a bit clearer. So it is advised to base timers on this space.

Note: for timers to work, they have to be `render`ed by their owner's `draw` function. This requirement is imposed by the necessity of having tree paths for each timer to be readily available, otherwise they consume too much resources.


## Stretch

Just an elastic spacer between other UI items (see [example in VID/S](vids.md#constraining-the-size)). Another (more readable) name is `<->`, i.e. a double arrow (but it may cause problems when compiling - see [#5137](https://github.com/red/red/issues/5137)).

Has weight of `1`, which makes it stretch. See [VID/S manual](vids.md#weight-effect) on how weight works.


## Rectangle

Draws a simple box across it's `size`. To be used in other spaces (as interactive region). Currently used only to draw scrollbar's thumb and caret.


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
| `weight` | integer! or float! >= 0 | this common facet has more meaning in image: if zero, image will only adapt it's size to /limits but not to canvas it's rendered on; if positive, then if canvas fill is requested, it will try to fill the canvas' smaller dimension |


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
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`, `strike`, `ellipsize`); should be set in styles; `wrap` flag would make it behave like `paragraph` |
| `caret` | none! or [`caret` space object!](#caret) | when set, draws a caret on the text |
| `selected` | pair! none! | when set, draws a selection on the text; can be styled as `text/selection` |
| `kit` | object! | shared [kit object](#kit) |

## Paragraph

Basic multi-line text renderer. Wrap margin is controlled by canvas size, which is in turn constrained by /limits facet.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-paragraph.png) | <pre>paragraph with [<br>    margin: 20x10<br>    text: "You cannot hold back a good laugh any more than you can the tide. Both are forces of nature."<br>]</pre> |
|-|-|

Inherits all of `text` facets:

| facet  | type  | description |
|-|-|-|
| `text` | string! | obvious |
| `margin` | pair! integer! | horizontal and vertical space between the bounding box and text itself; should be set in styles |
| `font` | object! | an instance of `font!` object; should be set in styles |
| `color` | tuple! none! | if set, affects text color |
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`, `strike`, `ellipsize`); `flags: [wrap]` is the default, without it would behave like `text` |
| `caret` | none! or [`caret` space object!](#caret) | when set, draws a caret on the text |
| `selected` | pair! none! | when set, draws a selection on the text; can be styled as `paragraph/selection` |
| `kit` | object! | shared [kit object](#kit) |

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
| `flags` | block! | a list of rich-text flags (`underline`, `bold`, `italic`, `strike`, `ellipsize`); defaults to `flags: [wrap underline]` |
| `caret` | none! or [`caret` space object!](#caret) | when set, draws a caret on the text |
| `selected` | pair! none! | when set, draws a selection on the text; can be styled as `link/selection` |
| `kit` | object! | shared [kit object](#kit) |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `command` | block! | code to evaluate when link gets clicked; by default opens `text` in the browser |

## Caret

A `rectangle`-based template that represents the caret within text tempates.

Exposes the following facets:

| facet  | type  | description |
|-|-|-|
| `width` | integer! | caret width in pixels (height is inferred from the font) |
| `offset` | integer! | zero-based integer caret offset within the parent |
| `side` | word! | `left` or `right` - determines displayed caret location at line wraps: `left` means end of the previous row, `right` means start of the next row |

Note that `offset` and `side` do not affect the caret itself, but serve as hint for the parent on where to draw it.


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
| `content` | object! none! | inner space; none if no content |

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
| `content` | object! none! | inner space; none if no content |


## Clickable

Basic undecorated clickable area, extends [`box`](#box).

Inherits all of `box` facets:

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to 0x0 (center); should be set in styles |
| `margin` | pair! integer! | defaults to 1x1; should be set in styles |
| `content` | object! none! | inner space; none if no content |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `command` | block! | code to evaluate when button gets pushed and then released |
| `pushed?` | logic! | reflects it's pushed state, change from `true` to `false` automatically triggers `command` evaluation |


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
| `content` | object! none! | inner space; none if no content |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `data` | any-type! | data value to be shown (see the list above) |
| `spacing` | pair! integer! | when data is a block, sets spacing of it's items; should be set in styles |
| `font` | object! | when data is rendered using text or paragraph templates, affects font; should be set in styles |
| `wrap?` | logic! | when true, displays textual data using `paragraph` instead of `text`; should be set in styles |


## Data-clickable

[comment]: # (not a great name, needs revisiting)

Undecorated clickable area with arbitrary data support, extends [`data-view`](#data-view).

Inherits all of `data-view` facets:

| facet  | type  | description |
|-|-|-|
| `align` | pair! | -1x-1 to 1x1 (9 variants); defaults to -1x-1; should be set in styles |
| `margin` | pair! integer! | defaults to 1x1; should be set in styles |
| `spacing` | pair! integer! | when data is a block, sets spacing of it's items; should be set in styles |
| `content` | object! none! | inner space; none if no content |
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
| `content` | object! none! | inner space; none if no content |
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

Adds new facets:

| facet  | type  | description |
|-|-|-|
| `origin` | integer! | current offset of the text in the field in pixels (non-positive) |
| `selected` | pair! none! | currently selected part of text: `BEGINxEND`, where `begin` should not be bigger than `end` |
| `selection` | rectangle space object! | can be styled as `field/selection` |
| `caret` | none! or [`caret` space object!](#caret) | when set, draws a caret on the text |
| `caret/look-around` | integer! | how close caret can come to field's margins; defaults to 10 pixels |
| `kit` | object! | shared [kit object](#kit) |

Note: `caret/offset` and `selected` facets use *offsets from head* as coordinates:
- `0` = no offset from the head, i.e. before the 1st char
- `1` = offset=1, i.e. after 1st char
- `length? text` = offset from the head = text length, i.e. after last char


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
| `arrow-size` | float! percent! | arrow length in percents of scrollbar's overall thickness (useful for styling, default: 90%) |

Scrollbar will try it's best to adapt it's appearance to remain useable (visible, clickable) even with extreme values of it's facets.


## Scrollable

Wrapper for bigger (but finite) spaces. Automatically shows/hides scrollbars and provides event handlers to scroll it's content interactively.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-scrollable.png) | <pre>scrollable 100x100 [<br>	space size= 200x300<br>]</pre> |
|-|-|

| facet  | type  | description |
|-|-|-|
| `origin` | pair! | point in scrollable's coordinate system at which to place `content`: <0 to left above, >0 to right below |
| `content` | object! none! | inner space; none if no content |
| `content-flow` | word! | lets scrollable know how content is supposed to use canvas; can be one of: `planar` (default), `horizontal` or `vertical` (see below) |
| `hscroll` | scrollbar space object! | horizontal scrollbar; can be styled as `scrollable/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scrollbar space object! | vertical scrollbar; can be styled as `scrollable/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | timer space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |
| `viewport` | `func [] -> pair!` | size of the viewport (region without scrollbars) on the last frame |

<details><summary>How to understand <code>content-flow</code>...</summary>

<br>
Each scrollable faces a challenge: it has to figure out how to best draw it's content, and do it fast.

It could render it's content on 4 canvas sizes:
1. Full canvas
2. Canvas minus horizontal scrollbar
3. Canvas minus vertical scrollbar
4. Canvas minus both scrollbars

For some spaces, like `list`, there will be a difference: `list` fits content across its secondary axis, so if list is vertical, width of the canvas will control overall list's width.

But `scrollable` knows nothing of its content's size adjustment behavior. In what order should it try canvases to render its content on? 1-2-3-4? 1-3-2-4? And how should it evaluate if content fits successfully? 

Performance is a significant consideration here, as in a scenario when a scrollable contains a scrollable that also contains a scrollable, if each one tries 2 canvases instead of 1, the innermost scrollable will be rendered 2^3=8 times instead of 1. This gets out of hand quickly.

`content-flow` is what helps scrollable reason about what canvases it should try while keeping the number of renders to a minimum:
- `planar` only tries the full canvas (1), which works great for spaces that do not adjust to canvas (like `grid`), and so do not suffer the performance hit from multiple renders
- `vertical` tries (1) and then (if height is exceeded) - (2), which works for spaces that adjust their width to canvas (vertical `list`, text `paragraph`)
- `horizontal` tries (1) and then (if width is exceeded) - (3), which works for spaces that adjust their height to canvas (horizontal `list`)
- spaces that adjust both dimensions (`tube`, `box`, etc) are a bad fit for a scrollable: they bring ambiguity into canvas selection and are not meant to be scrolled anyway, so no special mode is supported for these (best would be to use `planar`)

</details>

## Window

Used internally by `inf-scrollable` to wrap infinite spaces. Window has a size, while it's content may not have it. Window guarantees that `content/draw` of the infinite space is called with an `/window` refinement that limits the rendering area.

| facet  | type  | description |
|-|-|-|
| `size` | pair! none! | set by `draw` automatically, read-only for other code; it extends up to the smallest of `origin + content/size` (if defined) and `canvas * pages` |
| `pages` | integer! pair! | used to automatically adjust maximum window size to a multiple of canvas: `canvas * pages` (e.g. on it's parent's resize or auto adjustment) |
| `content` | object! none! | inner space; none if no content |
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

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-inf-scrollable.png) | <pre>inf-scrollable with [<br>	size: 100x100<br>	window/content: make-space 'space [<br>		available?: func [axis dir from req] [req]<br>	]<br>]</pre> |
|-|-|

Inherits all of `scrollable` facets:

| facet  | type  | description |
|-|-|-|
| `origin` | pair! | point in inf-scrollable's coordinate system at which `window` is placed: <0 to left above, >0 to right below; combined with `window/origin` can be used to translate coordinates into `content`'s coordinate system |
| `content` | object! = `window` | inherited from `scrollable` and should not be changed |
| `hscroll` | scroller space object! | horizontal scrollbar; can be styled as `scrollable/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scroller space object! | vertical scrollbar; can be styled as `scrollable/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | scroller space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |
| `viewport` | `func [] -> pair!` | size of the viewport (region without scrollbars) on the last frame |

Introduces new facets:

| facet  | type  | description |
|-|-|-|
| `window` | window space object! | used to limit visible (rendered) area to finite (and sane) size |
| `window/content` | object! none! | space to wrap, possibly infinite or half-infinite along any of X/Y axes, or just huge |
| `window/pages` | integer! pair! | used to automatically adjust maximum window size to a multiple of canvas: `canvas * pages` (e.g. on inf-scrollable's resize or auto adjustment) |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |
| `roll-timer` | timer space object! | controls jumping of the window e.g. if user drags the thumb or holds a PageDown key, or clicks and holds the pointer in scroller's paging area |
| `roll-timer/rate` | integer! float! time! | rate at which it checks for a jump |
| `roll` | function! | can be called to manually check for a jump |

`inf-scrollable` uses two origins (`origin` and `window/origin`) to provide pagination across unlimited (or big) dimensions. `window/origin` determines offset of window's content from window's left top corner. `inf-scrollable/origin` determines offset of window's lert top corner from viewport's left top corner. So both are normally negative pairs. You can jump around `inf-scrollable` by setting these two origins to desired offsets.

## Container

Basic template for various layouts. Arranges multiple spaces in a predefined way.

| facet  | type  | description |
|-|-|-|
| `content` | block! of space object!s | contains spaces to arrange and render |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector |
| `kit` | object! | shared [kit object](#kit) |

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

By default, three layouts are available out of the box: `list` (used in vlist/hlist), `tube` (used in row/column), `ring` (used in ring menu popups), and `paragraph` (used in rich-paragraph and derivatives).

#### Settings for list layout

| setting | types | constraints | description |
|-|-|-|-|
| axis | word! | `x` or `y` | primary axis of list's extension |
| margin |  integer! pair! | >= 0x0 | space between list's content and it's border |
| spacing | integer! pair! | >= 0x0 | space between adjacent list's items (only primary axis of the pair is used) |
| canvas | pair! none! | > 0x0 | area size on which list will be rendered (infinite by default) |
| limits | range! none! | /min <= /max | constraints on the size (unlimited by default) |
| origin | pair! | unrestricted | point at which list's coordinate system origin is located |

#### Settings for tube layout

| setting | types | default | constraints | description |
|-|-|-|-|-|
| axes | block! of 2 words, none! | `[e s]` | any of `[n e] [n w] [s e] [s w] [e n] [e s] [w n] [w s]` (unicode arrows `←→↓↑` are also supported) | primary (first) and secondary (second) axes of tube extension (run [`tube-test`](tests/tube-test.red) to figure it out) |
| align | block! of 0-2 words, pair! none! | -1x-1 | -1x-1 to 1x1 = 9 pair variants, or axes-like block | alignment vector: with pair `x` is 'list within row' and `y` is 'item within list'; with block axes are fixed and missing axis centers along it |
| margin |  integer! pair! | | >= 0x0 | space between tube's content and it's border |
| spacing | integer! pair! | | >= 0x0 | space between adjacent tube's items (primary axis) and rows (secondary axis) |
| canvas | pair! none! | INFxINF | > 0x0 | area size on which tube will be rendered |
| limits | range! none! | none | /min <= /max | constraints on the size |

#### Settings for ring layout

| setting | types | constraints | description |
|-|-|-|-|
| angle | integer! float! none! | unrestricted | clockwise angle from X axis to the first item, defaults to zero |
| radius | integer! float! | >= 0 | distance from the center to closest points of items |
| round? | logic! | | false (default) - consider items rectangular, true - consider items round |

#### Settings for paragraph layout

| setting | types | default | constraints | description |
|-|-|-|-|
| align | word! none! | left | any of `[left center right fill scale upscale]` | horizontal alignment |
| baseline | percent! float! none! | 80% | normally 0%(top) to 100%(bottom) | vertical alignment |
| margin |  integer! pair! | | >= 0x0 | space between paragraph's content and it's border |
| spacing | integer! pair! | | >= 0x0 | space between adjacent items (x) and rows (y) |
| canvas | pair! none! | INFxINF | > 0x0 | area size on which tube will be rendered |
| limits | range! none! | none | /min <= /max | constraints on the size |
| indent | `[first: integer! rest: integer!]` block! or none! | none | >= 0 each | first and other rows indentation in pixels |
| force-wrap? | logic! | false | | prioritize canvas width even if it means wrapping spaces at any pixel (may be slow on 1px canvas!) |

See [rich-paragraph](#rich-paragraph) to better understand how it works.


## List

A `container` that arranges spaces using `list` layout. VID/S defines styles `vlist` and `hlist` for convenience, based on this template.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-list.png) | <pre>vlist [<br>	button "button 1"<br>	button "button 2"<br>	button "button 3"<br>]</pre> |
|-|-|

Inherits all of `container` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of space object!s | contains spaces to arrange and render (see [container](#container)) |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector (see [container](#container)) |
| `kit` | object! | shared [kit object](#kit) |

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
| `viewport` | `func [] -> pair!` | size of the viewport (region without scrollbars) on the last frame |
| `jump-length` | integer! `>= 0` | maximum jump the window makes when it comes near it's borders |
| `look-around` | integer! `>= 0` | determines how near is "near it's borders", in pixels |
| `roll-timer` | timer space object! | controls jumping of the window e.g. if user drags the thumb or holds a PageDown key, or clicks and holds the pointer in scroller's paging area |
| `roll-timer/rate` | integer! float! time! | rate at which it checks for a jump |
| `roll` | function! | can be called to manually check for a jump |
| `content` | object! = `window` | set to `window`, should not be changed |
| `window` | window space object! | used to limit visible (rendered) area to finite (and sane) size |
| `window/content` | object! = `list` | set to inner `list`, should not be changed |
| `window/pages` | integer! pair! | used to automatically adjust maximum window size to a multiple of canvas: `canvas * pages` (e.g. on list-view's resize or auto adjustment) |
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
| `content` | block! of space object!s | contains spaces to arrange and render (see [container](#container)) |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector (see [container](#container)) |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `margin` | pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | pair! | horizontal or vertical space between adjacent items and rows/columns |
| `axes`  | block! = `[word! word!]` | primary and secondary flow directions: each word is one of `n w s e` or `← → ↑ ↓`; default for `tube` and `row` = `[e s]` (extend to the east then split southwise) |
| `align` | pair! or block! of 0 to 2 words | row and item alignment (see below), default = -1x-1 |

Alignment specification is supported in two forms:
- `pair!` -1x-1 to 1x1 - in this case pair/1 is alignment along primary axis (of extension), and pair/2 is alignment along secondary axis (of splitting):
  - `-1` aligns towards the negative side of the axis
  - `0` aligns close to the center along this axis
  - `-1` aligns towards the positive side of the axis
- `block!` of 0 to 2 words, where each word is one of `n w s e` or `← → ↑ ↓` - in this case alignment is specified independently of axes, and is screen-oriented (north always points up, east to the right, etc)
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

Tube is not some generalized equation solver. It's just a fast simple algorithm that does roughly the following:
- render each item to obtain its minimal size
- split this long row into multiple rows so each row's width is no bigger than the given canvas width 
- expand items in each row to fill row's width fully (if any item has weight > 0)
- expand rows to fill the canvas height (if any row has item with weight > 0)
- expand items in each row to fill row's height fully (so they can be aligned)

This works fine with spaces like `box`, which just expand to the given size, and to an extent with other flow-like things. But some more complex spaces may not work well with it or it may be hard to predict the outcome.  


## Ring

A `container` that arranges spaces using `ring` layout. Used by ring menu popup.


| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-ring.png) | <pre>ring [<br>	button "button 1"<br>	button "button 2"<br>	button "button 3"<br>	button "button 4"<br>	button "button 5"<br>]</pre> |
|-|-|

Inherits all of `container` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of space object!s | contains spaces to arrange and render (see [container](#container)) |
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

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-grid.png) | <pre>grid autofit= none [<br>    at 2x1 image data= system/words/draw 40x40 [<br>    	pen red triangle 20x5 5x35 35x35<br>    ]<br>    at 1x2 cell [text "some text"]<br>    at 3x2 field "field"<br>    at 2x3 button "button"<br>]</pre> |
|-|-|

| facet  | type | description |
|-|-|-|
| `margin` | pair! | horizontal and vertical space between cells and the bounding box |
| `spacing` | pair! | horizontal and vertical space between adjacent cells |
| `content` | map! of `pair! (col x row) -> space object!` | used to place spaces at specific row/col positions |
| `cells` | `func [/pick xy [pair!] /size]` | picker function that abstracts `content` |
| `widths` | map! of `integer! (col) -> integer! (width)` | defines specific column widths in pixels; `widths/default` is a fallback value for absent column numbers; `widths/min` is only used by autofitting; columns are numbered from `1`; filled automatically if autofitting is on |
| `autofit` | word! or none! | chooses one of automatic column width fitting methods: [`[width-difference width-total area-difference area-total]`](design-cards/grid-autofit.md); defaults to `area-total`; `none` to disable, always disabled on infinite grids |
| `heights` | map! of `integer! (row) -> integer! or word! = 'auto` | defines specific row heights in pixels; `heights/default` is a fallback value that defaults to `auto`; `heights/min` sets the minimum height for `auto` rows (to prevent rows of zero size); rows are numbered from `1` |
| `bounds` | pair! or block! `[x: lim-x y: lim-y]` | defines grid's number of rows and columns: `none` = infinite, `auto` = use upper bound of `cells`, integer = fixed |
| `wrap-space` | `function! [xy [pair!] name [word!]] -> cell [object!]` | function that wraps spaces returned by `cells` into a `cell` template, for alignment and background drawing; can be overridden |


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

For more info about these functions, create a grid `g: make-space 'grid []` and inspect each function e.g. `? g/get-span`.


## Grid-view

An [`inf-scrollable`](#inf-scrollable) wrapper around [`grid`](#grid), used to display finite or infinite amount of **data**.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-gridview.png) | <pre>grid-view with [<br>	grid/widths:  #(default 40)<br>	grid/heights: #(default 20)<br>	data: func [/pick xy /size] [either size [ [x #[none] y #[none]] ][ xy ]]<br>]</pre><br>Tip: `size/x = size/y = none` means infinite in both directions |
|-|-|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-gridview-autofitted.gif) | <pre>grid-view source= [<br>	[1 "22 22"]<br>	["3 3 3" "4444 4444 4444 4444"]<br>]</pre> |

Inherits all of [`inf-scrollable`](#inf-scrollable) facets:

| facet  | type | description |
|-|-|-|
| `origin` | pair! | offset of unpinned cells, together with `window/origin` can be used to translate coordinates into `grid`'s coordinate system |
| `hscroll` | scroller space object! | horizontal scrollbar; can be styled as `grid-view/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scroller space object! | vertical scrollbar; can be styled as `grid-view/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | scroller space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |
| `viewport` | `func [] -> pair!` | size of the viewport (region without scrollbars) on the last frame |
| `roll-timer` | timer space object! | controls jumping of the window e.g. if user drags the thumb or holds a PageDown key, or clicks and holds the pointer in scroller's paging area |
| `roll-timer/rate` | integer! float! time! | rate at which it checks for a jump |
| `roll` | function! | can be called to manually check for a jump |
| `window` | window space object! | used to limit visible (rendered) area to finite (and sane) size |
| `window/content` | object! = `grid` | set to inner `grid` and should not be changed |
| `window/pages` | integer! pair! | used to automatically adjust maximum window size to a multiple of canvas: `canvas * pages` (e.g. on grid-view's resize or auto adjustment) |
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


Pagination works as explained for [`inf-scrollable`](#inf-scrollable). The only thing to note is that pinned cells are displayed in the viewport regardless of the estimated content offset. 



## Rich-paragraph

A `container` specially designed to display mixed content (text, and other spaces, including images). Arranges spaces using `paragraph` layout. Used by [`rich-content`](#rich-content).

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-rich-paragraph.png) | <pre>rich-paragraph [<br>	text "some text "<br>	image data= draw 40x30 [<br>		triangle 3x25 37x25 20x5<br>		triangle 13x15 27x15 20x25<br>	]<br>	text " with an image"<br>]</pre> |
|-|-|

Like [`tube`](#tube), it is a flow layout, but with the following major differences:

| Feature | `tube` | `rich-paragraph` |
|-|-|-|
| optimized for | UI rows and columns | rich text |
| size fitting | will try to stretch it's content based on weight, which may require up to 3 rendering attempts | renders content once on an infinite canvas |
| orientation | exposes 2 axes that control primary and secondary direction | always lays out left-to-right, arranges in top-down lines |
| alignment | 9 fixed alignments along its two axes | 6 fixed horizontal alignments (left, right, center, fill, scale, upscale) and a continuous vertical alignment controlled by baseline location (0% to 100% of line height) |
| splitting | content items cannot be split | content items can be split at provided sections (see below) |
| intervals | only fixed uniform `spacing` between items | sections may denote any part of item as 'empty', and these are omitted from output at line boundaries |


Inherits all of `container` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of space object!s | contains spaces to arrange and render (see [container](#container)) |
| `items` | `func [/pick i [integer!] /size]` | paragraph does not support filtering, so `items` facet should be used |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `margin` | pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | integer! | vertical space between adjacent rows |
| `align` | word! | horizontal alignment: one of `[left center right fill scale upscale]`; default = left |
| `baseline` | percent! float! | vertical alignment as percentage of line's height: 0% = top, 50% = middle, 100% = bottom; default = 80% (makes text of varying font size look more or less aligned) |
| `indent` | none! block! | first and the other rows indentation from the left, in the form: `[first: integer! rest: integer!]`; both `first` and `rest` values have to be present, e.g. `[first: 15 rest: 30]` |
| `force-wrap?` | logic! | on limited width canvas: when `on`, wraps spaces that are wider than the width; when `off`, canvas width can be extended to accomodate the widest space and indentation |
| `kit` | object! | shared [kit object](#kit) |


**Alignments** look like this (left, fill, then center, right - snapshot from [rich-test2](tests/README.md)):

<img width=600 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-rich-paragraph-alignments.png></img>

`fill` alignment is the slowest one since it has to split paragraphs into multiple fragments that can then be uniformly spaced.\
`upscale` horizontally scales every row until it fills the total width.\
`scale` is similar to `upscale` but can both upscale and downscale the row, choosing scale ratio closest to 1 for each row.\
Both `scale` and `upscale` alignments are not meant for documents, but for fitting text into straight blocks.

Note that `rich-paragraph` can split *any* space that appears in it into a number of rows (provided it supports `sections`). Final look is the result of clipping and scaling. This allows spaces to keep their simple box geometry without any special treatment and complex drawing logic.

### Sectioning

All spaces that have `frame/sections` in their [kit](#kit) can be wrapped by `rich-paragraph`. `frame/sections` must be a nullary function returning:
- `none` denoting that space cannot be split
- `block!` of integers, representing a list of horizontal interval widths for this space on the last frame

Each returned interval width can be:
- a positive integer denotes a mandatory inteval (always made visible), usually a single word of text
- a negative integer denotes an empty interval (whitespace) which can be hidden by the alignment line, or stretched to fill the row
  
Constraints:
- zero is reserved for now and should never appear in the block
- sum of absolute values of inteval widths must equal total space width
- generally margin should be treated as mandatory (this way margins won't be stripped off the space when it comes near the edge), while spacing should be treated as empty

Example: for `text margin= 10x5 "hello world"` sections may return: `[10 26 -4 30 10]` where 26 is the width of `hello`, 4 is the width of whitespace, 30 is the width of `world`.

`frame/sections` is defined for the text-based templates, and containers that usually wrap them. This function can be freely added to the kit of any other spaces that should be wrappable.


## Rich-content

A `rich-paragraph` that adds the ability to edit content and fill it from the source dialect. It is not interactive out of the box (see [`editor`](#editor) for that).

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-rich-content.png) | `rich-content ["normal " bold "bold" italic " italic " /bold size: 15 underline "big" /underline /size " text"]` |
|-|-|

Source dialect summary (not meant to be concise, meant to be easy to parse):

| Feature | Syntax |
|-|-|
| text | string! or char! (concatenated) |
| bold | starts with `bold`, ends with `/bold` |
| italic | starts with `italic`, ends with `/italic` |
| underline | starts with `underline`, ends with `/underline` |
| strikethrough | starts with `strike`, ends with `/strike` |
| font face | starts with `font: "Font name"`, ends with `/font` |
| font size | starts with `size: integer!`, ends with `/size` |
| font color | starts with `color: tuple!` or `color: name` (e.g. `blue`), ends with `/color` |
| background color | starts with `backdrop: tuple!` or `backdrop: name` (e.g. `blue`), ends with `/backdrop` |
| arbitrary spaces | any space! object met in the `source` is passed into `content` |

Note that every space object inserted constitutes a single item (caret cannot enter it), even if it's a text space, because there is no easy way to map integer caret offset to addresses inside other objects and back.
 
Inherits all of `rich-paragraph` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of space object!s | filled by `deserialize` kit function (done automatically in VID/S) or on `data` override, should not be changed directly |
| `items` | `func [/pick i [integer!] /size]` | paragraph does not support filtering, so `items` facet should be used |
| `margin` | pair! | horizontal and vertical space between the items and the bounding box |
| `spacing` | integer! | vertical space between adjacent rows |
| `align` | word! | horizontal alignment: one of `[left center right fill scale upscale]`, default = left |
| `baseline` | percent! float! | vertical alignment as percentage of line's height: 0% = top, 50% = middle, 100% = bottom; default = 80% (makes text of varying font size look more or less aligned) |
| `indent` | none! block! | first and the other rows indentation from the left, in the form: `[first: integer! rest: integer!]`; both `first` and `rest` values have to be present, e.g. `[first: 15 rest: 30]` |
| `force-wrap?` | logic! | on limited width canvas: when `on`, wraps spaces that are wider than the width; when `off`, canvas width can be extended to accomodate the widest space and indentation |
| `kit` | object! | shared [kit object](#kit) |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `font` | object! | an instance of `font!` object; sets default font to use; should be set in styles |
| `color` | tuple! none! | if set, affects default text color |
| `selected` | pair! none! | currently selected part of content: `BEGINxEND` (two zero-based offsets); makes it display boxes of `rich-content/selection` style |
| `caret` | none! or [`caret` space object!](#caret) | when set, draws a caret on the text |
| `data` | block! | internal content representation (see below); updates `content` when set |

`data` facet is a block of `[item attr ...]` pairs, where:
- `item` is either a char! value or a space object!
- `attr` is a set of text attributes (bold, italic, color, etc) for the previous item

`data` can be modified by high level kit functions or manually (in latter case the facet must be `set` after making changes to trigger internal updates).

The easiest ways to fill data are:
- in VID/S add a block after `rich-content` instance (as in the example above)
- after `rich-content` space creation call `batch my-rich-content-object [deserialize [source ...]]`


## Document

A vertical list of `rich-content` spaces. Represents a non-interactive hypertext document. Provides global (cross-paragraph) caret and selection.

Has to be imported separately: [`#include %widgets/document.red`](widgets/document.red). `document.red` file contains both `document` and `editor` templates.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-document.png) | <pre>document 80 [<br>	rich-content [italic "First " /italic "paragraph text"]<br>	rich-content [italic "Second" /italic " paragraph text"]<br>	rich-content [italic "Third" /italic " paragraph text"]<br>]</pre> |
|-|-|


Inherits all of `list` facets:

| facet  | type  | description |
|-|-|-|
| `content` | block! of `rich-content` object!s | paragraphs to display; document only supports `rich-content` spaces, anything else should be put inside `rich-content` |
| `items` | `func [/pick i [integer!] /size]` | more generic item selector (see [container](#container)) |
| `axis` | word! | set to `y` and should not be changed |
| `margin` | integer! pair! | horizontal and vertical space between the paragraphs and the bounding box; should not be less than 1x0, or caret may become invisible at the end of the longest line |
| `spacing` | integer! | space between adjacent paragraphs |
| `kit` | object! | shared [kit object](#kit) |

Adds new facets:

| facet  | type | description |
|-|-|-|
| `length` | integer! | read-only (updated by edits) length of the document in items |
| `caret` | [`caret` space object!](#caret) | controls caret location and width; can be styled as `rich-content/caret` |
| `selected` | pair! none! | currently selected document part: `BEGINxEND` (two zero-based offsets) |
| `paint` | block! | current (for newly inserted chars) set of attributes updated on caret movement; format: `[attr-name attr-value ...]` |


## <a name="area"></a>Editor

A scrollable wrapper around `document`. Represents an interactive editable hypertext document and defines most common event handlers for editing.

Has to be imported separately: [`#include %widgets/document.red`](widgets/document.red). `document.red` file contains both `document` and `editor` templates.

| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-template-editor.gif) | <pre>editor 80x70 [<br>	rich-content [italic "First " /italic "paragraph text"]<br>	rich-content [italic "Second" /italic " paragraph text"]<br>	rich-content [italic "Third" /italic " paragraph text"]<br>]</pre> |
|-|-|

See [Document Editor](samples/editor) sample for advanced usage. 

Inherits all of `scrollable` facets:

| facet  | type  | description |
|-|-|-|
| `origin` | pair! | nonpositive offset of `content` within editor's viewport; on key presses adjusted to keep caret visible |
| `content` | object! none! | set to a `document` space and should not be changed |
| `content-flow` | word! | set to 'vertical and should not be changed |
| `hscroll` | scrollbar space object! | horizontal scrollbar; can be styled as `editor/hscroll` |
| `hscroll/size/y` | integer! | height of the horizontal scrollbar; could be set in styles |
| `vscroll` | scrollbar space object! | vertical scrollbar; can be styled as `editor/vscroll` |
| `vscroll/size/x` | integer! | width of the vertical scrollbar; could be set in styles |
| `scroll-timer` | timer space object! | controls scrolling when user clicks and holds scroller's arrow or paging area between arrow and thumb |
| `scroll-timer/rate` | integer! float! time! | rate at which it scrolls |
| `viewport` | `func [] -> pair!` | size of the viewport (region without scrollbars) on the last frame |

Editor affects its document (`content`) according to received events: modifies data, selection, moves caret. 




[comment]: # (not sure icon template is worth documenting / making available by default, we'll see)

