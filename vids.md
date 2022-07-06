---
gitea: none
include_toc: true
---

# VID/S - Visual Interface Dialect for Spaces

VID/S is different from [VID](https://w.red-lang.org/en/vid) because it serves a completely different design.

## Quick VID to VID/S and faces to spaces comparison

| Feature | VID, View, Faces | VID/S, Spaces |
| - | - | - |
| Organization | Tree of static doubly linked `face!` objects (children have a /parent facet, parents have /pane). Face can appear in only a single place. | Tree of singly¹ linked `space!` objects (parents have /map facet). Same space can appear in multiple places². |
| Geometry | All faces are boxes sized in (virtual) pixels. | Each space can rotate/scale/bend it's children if it can express that in Draw. For interactivity support, it should provide coordinate transformation. |
| Rendering | Faces are rendered by the OS, triggering redraw when a facet changes | Spaces are rendered using [Draw dialect](https://w.red-lang.org/en/draw), redrawn continuously over time³. |
| Naming | `name:` can prefix a face definition. | `name:` can prefix a space definition. |
| VID styles | `style` keyword allows to define a new style with new defaults. | `style` keyword allows to define a new style with new defaults. |
| Stylesheets | No support. Faces look is mostly cast in stone. | Whole classes of spaces can be styled using a single style block or function. Styling is affected by the hierarchy. Spaces look can be fully customized, animated, effects applied (no limits). |
| Coloring | Faces support both foreground and background colors. | Spaces support only one color, which will be e.g. text color for `text` and fill color for `box`. |
| Font styles | Faces support `font` facet as well as `bold/italic/underline/font-size` shortcuts. | Text spaces support `bold/italic/underline` shortcuts, while font and size can only be set by stylesheet. |
| Actors | Each individual face can have a [set of actors](https://w.red-lang.org/en/view/#actors). | Each individual space can have the same set of actors. |
| Event handlers | Events are handled by the OS. Some little customization can be done using a stack of [event functions](https://w.red-lang.org/en/view/#insert-event-func). | Events are handled by [standard event handlers](standard-handlers.red). Each space can have a stack of event handlers defining different levels of behavior from basic to custom. |
| Facets | Each face has exactly the same set of facets that cannot be extended from VID. Mapping of VID datatypes to facets is hardcoded. | Each space defines it's own set of facets (only a few are shared), which can be extended by user with the `facet=` notation. Mapping of datatypes to facets is defined by [`spaces/styles` map](vid.red) which can be altered at any time. |
| Sizing | Each face has a fixed size that has to be changed manually when required. | Most spaces automatically adjust their sizes, virtually eliminating the need for manual intervention. `limits` facet controls the range in which the size can vary. |
| Positioning | VID allows for quite tricky static layouts with rows, columns, alignment. Every pane is pre-arranged using the same powerful algorithm. | VID/S uses [layout functions](layouts.red) to position spaces (some support alignment). They are more limited⁴ and predictable but able to adapt to size changes. Some spaces can only contain a single child. |
| Reactivity | Faces are deeply reactive. | Spaces are not reactive⁵, but VID/S adds (shallow) reactivity to spaces with a name or reaction defined. |

**Footnotes**:\
¹ Internally there's still a link from child to parent which is used for cache invalidation and fast provision of paths to timer events. It lives from one rendered frame until another.\
² For a space to appear in multiple places it's size and map must not depend on canvas size, because these are parts of the `space!` object and every new render (in a new place) will invalidate the old data.\
³ Draw block and map are cached internally, so space's `draw` function is only called when it's invalid. Invalidation is triggered by a change of it's facet (not a deep change!). A redraw cycle is only triggered when `/dirty?` facet of the `host` is true. Actors must use `update` function to mark it as dirty (when they change the look).\
⁴ It's possible to write a VID-like layout function, but most likely it won't be able to react to resizes in a meaningful way.\
⁵ Making all spaces reactive would immensely slow down their operation as there can easily be tens to hundreds of thousands present at the same time.


## Predefined styles

The following VID/S styles are currently supported for truly high level experience (more to come later):

| Style | Description | Based on template | Datatypes accepted | Flags supported |
|-|-|-|-|-|
| `hlist` | horizontal list of spaces | [list](reference.md#list) | block! as content | tight |
| `vlist` | vertical list of spaces | [list](reference.md#list) | block! as content | tight |
| `row` | horizontal tube of spaces | [tube](reference.md#tube) | block! as content | tight left center right top middle bottom |
| `column` | vertical tube of spaces | [tube](reference.md#tube) | block! as content | tight left center right top middle bottom |
| `list-view` | scrollable vertical list of data | [list-view](reference.md#list-view) | block! as content | tight left center right top middle bottom |
| `box` | borderless aligning box | [box](reference.md#box) | block! as content | left center right top middle bottom |
| `cell` | bordered aligning box | [cell](reference.md#cell) | block! as content | left center right top middle bottom |
| `grid` | grid of spaces | [grid](reference.md#grid) | pair! as bounds,<br>block! as content | tight |
| `text` | single-line text | [text](reference.md#text) | string! as text | bold italic underline |
| `paragraph` | multi-line wrapped text | [paragraph](reference.md#paragraph) | string! as text | bold italic underline |
| `label` | 1- to 3-line unwrapped text with sigil | [label](reference.md#label) | string! as text,<br>char! or image! as image | bold italic underline |
| `field` | single-line editable text | [field](reference.md#field) | string! as text | bold italic underline |
| `link` | multi-line clickable wrapped text | [link](reference.md#link) | string! or url! as text,<br>block! as command | |
| `button` | bordered clickable area | [button](reference.md#button) | string! or image! as data | block! as command | |
| `timer` | invisible zero-sized time events receiver | [timer](reference.md#timer) | integer!, float! or time! as rate,<br>block! as on-time actor body | |
| `<->` aka `stretch` | invisible elastic filler space | [stretch](reference.md#stretch) | | |

All [supported space *templates*](reference.md) can be used in VID/S, but without auto-facet magic, flags, or user-friendly default settings.


[comment]: # (maybe button should support sigil as label does!)
[comment]: # (some of these are not documented in the reference yet!)


## Dialect

VID/S is handled by `lay-out-vids` function which takes a VID/S block and returns a block of space names (each name refers to space object). Example:
```
>> names: lay-out-vids [text "foo" vlist [] button "bar"]
== [text list button]

>> ? :names/1
TEXT is an object! with the following words and values:
     on-change*       function!     [word [any-word!] old [any-type!] new [...
     draw             function!     [/on canvas [pair! none!]]
     size             none!         none
     limits           none!         none
     cache?           logic!        true
     text             string!       "foo"
     margin           pair!         0x0
     font             none!         none
     flags            block!        length: 0  []
     weight           integer!      0
     layouts          map!          []
     layout           none!         none
     invalidate       function!     []
     space-on-change  function!     [word [any-word!] old [any-type!] new [...
```
Upon `host` initialization, this list is rendered into Draw code.

### Syntax

VID/S can contain the following kinds of expressions:
1. [Style instantiation](#style-instantiation)
2. [Style definition](#style-definition)
3. [Do-expression](#do-expression)

#### Style instantiation

This results in a new space created and returned.

Syntax: `<bound-name>: <style-name> <modifiers...>`

- `style-name` can be any of:
  - styles previously defined using [style definition](#style-definition)
  - styles predefined by VID/S (see `? spaces/VID/styles` output)
  - raw template names (see `? spaces/templates` output), but these do not support [auto-facets](#auto-facets)
- `bound-name` is a set-word that will refer to the created space object, and it makes the space reactive
- `modifiers` is an optional *unordered* set of any number of parameters described [below](#supported-modifiers)

Example:
```
view [host [
	label #"☺" "some text" underline teal
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-style-instantiation.png)

| **TIP** | Examples in this document can be run:<ul><li>in a separate script (after including `everything.red`)<li>directly in Spaces console (started by `run.bat` or equivalent `red console.red` shell command)<li>using [VID/S Polygon](programs/vids-polygon.red) - an evolving tool for testing various layouts, minimalistic for now but still quite handy (in this case, omit the `view [host []]` part!) and is a great way to get a feel how sizing works</ul> |
|-|-|

#### Style definition

This creates new *VID/S styles*, that are valid until return of `lay-out-vids`. VID/S style is a collection of facets that will be automatically applied upon it's instantiation, thus helping avoid repetition.

Syntax: `style <new-style-name>: <style-name> <modifiers...>`
- `style-instantiation` is described [above](#style-instantiation)
- `new-style-name` is a set-word that will be used as `style-name` in the subsequent style instantiations
- `modifiers` is an optional set of any number of parameters described [below](#supported-modifiers)

Example:
```
view [host [
	style big-button: button 200
	vlist [big-button "abc" big-button "def"]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-style-definition.png)

| **NOTE** | For a more radical change of look than facets allow, a new *template style* should be defined instead. See [Styling chapter in the manual](manual.md#styling). Template style is more profound and affects every space of built upon that template, globally. |
|-|-|

#### Do expression

This allows one to evaluate arbitrary expression and discard it's result. 

Syntax: `do <red-expression>`
- `red-expression` is a block! of Red code

Examples:
- `do [print "hello in the middle of layout creation!"]`
- `do [some initialization of previously created spaces...]`

## Supported modifiers

### Pane definition

Styles that don't use block value for an auto-facet will get it processed by `lay-out-vids` and assigned to their `content` facet (which contains inner spaces). 

Only some spaces support it:
- `cell` and `box` may only contain a single space
- `hlist`, `vlist` (all `list` derivatives), `row`, `column` (all `tube` derivatives), and `grid` may contain zero or more spaces

Syntax: `<content>`\
where `content` is a block! value

Example:
```
view [host [
	column [
		row [field "a" field "b" field "c" field "d"]
		cell [
			grid 2x2 [
				text "a" text "b" return
				text "c" text "d"
			]
		]
	]
]]
```  
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-pane-definition.png)


### `with`

Serves as a spec for the newly created space object. Similarly to `make object! spec` semantics, it may define new facets. This is the most basic and powerful way of defining facets (and the most verbose for sure ;)

Syntax: `with <spec...>`
- `spec` is a block! of Red code, in which set-words mark space's facets

Example:
```
view [host [
	button with [data: "some text" font: make font! [size: 20] limits: none]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-modifier-with.png)

### `react`

Defines a reactive relation on a space and makes the space [reactive](https://w.red-lang.org/en/reactivity/). Reaction may refer to this space by `self` or by [bound name](#style-instantiation) (if one is given).

Syntax:
- `react <relation>`
- `react later <relation>`\
where:
- `relation` is a block of arbitrary Red code (reactivity framework uses paths and get-paths as reactive sources, so these serve as triggers)
- `later` will delay relation evaluation until next change in it's sources

Example (combining both VID and VID/S reactivity):
```
view/flags [
	;) just `h: host` won't work since it's delayed by VID after reaction definition
	host 100x100 with [set 'h self] [
		cell [text react [text: form h/size]]		;) VID/S react keyword
	] react [h/size: h/parent/size - 20]			;) VID react keyword
] 'resize
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-modifier-react.gif)

### Actor definition

Defines an actor (i.e. a function that gets called when specific event happens in a space).

Syntax:
- `<on-event> <body>`
- `<on-event> function <spec> <body>`
- `<on-event> :<reference>`

Where:
- `on-event` is any word that starts with `on-` (see [list of supported events](https://w.red-lang.org/en/view/#events))
- `body` and `spec` are blocks. In the first case, actor is defined implicitly as `function [space path event] body`, so `body` should use these names
- `reference` is either a get-word or get-path referring to the actor function

In all cases, function body is bound to space object, so `space/` prefix is not required to access it's facets (unless actor is shared across multiple spaces).  

For `on-time` event to fire, space's /rate facet should be a positive integer, float or time value.

### `focus`

Sets keyboard focus to the chosen space (and to host face).

[comment]: # (should this only accept focusable spaces or not? undecided)

Syntax: `focus`

Example: `button "text" focus`

### Facet assignment

Sets space's facet to the value of expression. Non-existing facets are silently added, so check your speling. Facets supported by each space are listed in the [Widget Reference](reference.md).

Syntax: `<name>= <expression>`
- `name` is any word that ends in `=`
- `expression` is an arbitrary Red expression that is evaluated using `do`. Tip: parens can be helpful for readability

Examples:
```
view [host [
	label
		image= "🦖"
		text= rejoin [random "dinosaur was here" "^/in year " random 2000]
		color= green - 20
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-facet-assignment.png)

```
view [host [
	text text= "no conflict between style names and their facets!"
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-facet-assignment-2.png)

### Auto-facets

Some **datatypes** are automatically recognized by certain VID/S styles and are assigned to a corresponding facet.

Syntax: `<value>`
- `value` is a value of one of the recognized datatypes

Each style has it's own set of supported datatypes. Currently these are:

| Style | Datatypes | Target facets |
| -|-|- |
| label | image!<br>char!<br>string! | image<br>image<br>text |
| link | string!<br>url!<br>block! | text<br>text<br>command |
| text | string! | text |
| paragraph | string! | text |
| field | string! | text |
| button | string!<br>block! | data<br>command |
| timer | integer!<br>float!<br>time!<br>block! | rate<br>rate<br>rate<br>actors/on-time |
| grid | pair! | bounds |

Example:
```
view [host [
	vlist [
		label
			#"🌴"											;) char! is auto assigned to /image facet (as sigil)
			"Wild palms"									;) string! is auto assigned to /text facet
		link
			"Open in browser 🌍"							;) string! is auto assigned to /text facet
			[browse https://www.imdb.com/title/tt0106175]	;) block! is auto assigned to /command facet
	]
]]
```  
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-auto-facet.png)


### Flags setting

Flags are **words** that when present, modify the appearance of the space.

Syntax: `<flag>`\
where `flag` is a word

Each style has it's own set of supported flags. Currently these are:
- `left`, `center`, `right` - control horizontal alignment of containers (row, column, box, cell)
- `top`, `middle`, `bottom` - control vertical alignment of containers (row, column, box, cell)
- `tight` - sets container spacing and margin to zero (hlist, vlist, row, column, list-view, grid)
- `bold`, `italic`, `underline` - control font properties of text (text, paragraph, field)
 
[comment]: # (wrap flag should be supported for text? list it here then, area should support font flags)

Example:
```
view [host [
	column 200x200 bottom right [
		cell [text "🌊"]
		paragraph bold "Ocean is more ancient than the mountains, and freighted with the memories and the dreams of Time."
		text italic "-- H. P. Lovecraft"
	]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-flags-setting.png)

### Coloring

Sets `color` facet of the new space. Not all spaces support it: `color` should be used by the stylesheet to have effect.

Syntax: `<color>`\
where `color` can be:
  - a tuple! value
  - a word! referring to a tuple! value
  - an issue! of format accepted by `hex-to-rgb` function

Example:
```
view [host 100x100 [
	box color= sky * 120% [
		vlist [
			text "green" 0.200.0
			text "magenta" magenta
			text "orange" #f80
		]
	]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-coloring.png)

### Constraining the size

Each space supports /limits facet which may define it's minimum and maximum size. It can take one of the following values:
- `none` - no limit defined (0x0 to infinity), equivalent to `none .. none`
- a `range!` object with /min and /max fields, each can be:
  - `none` - no limit defined, equivalent to `0x0` for /min and `infxinf` for /max (`infxinf` is a special `pair!` value defined by spaces)
  - a `pair!` value - defines 2D limit
  - an `integer!` value - defines width limit, height stays unconstrained

Syntax:
- `<limit-value>` or
- `<range-expression>`

Where:
- `limit-value` - an `integer!` or `pair!` value, which sets both low and high limits, fixing the size
- `range-expression` - is a Red expression of the form `<limit1> .. <limit2>` that constructs a new `range!` object:
  - `limit1` can only be a single token (expressions should be wrapped in parentheses), otherwise VID/S cannot reliably detect the range expression
  - `limit2` can be any expression, parenthesized or not, but keep in mind that `..` is an operator, so it will take precedence over possible following operators
  - both limits should evaluate to a value supported by the /limits facet

Examples:
```
view/flags [
	host 200x40 [
		row white [
			text "left" red				;) text does not stretch by default
			<-> 0 .. 200				;) this area will stretch up to 200 px but no more
			text "right" green
		]
	] react [face/size: face/parent/size - 20 face/dirty?: yes]
] 'resize
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-size-constraining.gif)

---
```
view/flags [
	host 200x70 [
		row white [
			cell red    50x50			;) fixed size
			cell yellow 50 .. 100		;) will fill the row height defined by the highest cell
			cell green  none .. none	;) will fill the rest
		]
	] react [face/size: face/parent/size - 20 face/dirty?: yes]
] 'resize
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-size-constraining-2.gif)

### Weight effect

Spaces can define their `weight` facet to determine relative sizing in containers. Some templates set it to `1` (the default). `row` & `column` in particular make great use of it. `0` or `none` values disable extension.

Example:
```
view/flags [
	host 100x100 [
		row [
			cell blue							;) uses default weight = 1
			cell green 40 .. 100 weight= 0.5	;) also has size constraints, receives 1/2 extension 
			cell red             weight= 3		;) receives triple extension
		]
	] react [face/size: face/parent/size - 20 face/dirty?: yes]
] 'resize
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-weight-effect.gif)


### Grid-specific extensions

`grid` style extends it's pane block with more keywords: `at` and `return`.

Normally, each new instantiated space in grid's pane just increments column index by one:\
`grid [text "a" text "b" text "c"]` will place `text`s into cells 1x1, 2x1 and 3x1 respectively, regardless of declared grid bounds.

The following additional syntax allows one to control the cell coordinate:
- `return` moves subsequent space into the first column on the next row
- `at <expression>` evaluates the expression that follows it and uses it's result:  
  - if result is a `pair!`, it moves subsequent space into given cell coordinate
  - if result is a `range!` object, it works as above, but also tells this cell to span the given range

Example:
```
view [host [
	grid 5x5 widths= #(default 50) heights= #(default 50) [
		cell [text "a"] cell [text "b"] return
		text "c" text "d"
		at 4x4 text "e" text "f"
		at 4x5 cell [text "g"] cell [text "h"]
		at 2x3 .. 4x3 cell [text "i"]
	]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-grid-extensions.png)

## Popups

### Hints

[comment]: # (this is completely irrelevant to VID/S but I don't have a better place to put it)

Every space can have a hint (tooltip) shown when it's hovered over.

To have a hint it should set it's `/hint` facet to a string.

Example:
```
view [host [
	row [
		button "OK"     hint= "Destroy all files on my HDD"
		button "Cancel" hint= "I prefer to have my files kept"
	]
]]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-hints.gif)

**Warning:** tablet users won't see it! Mind your audience.

### Menu DSL

*Read this only if you want popup menus.*

Only single-level popup menus are supported currently.

Menus are specified in the `menu` facet (`menu= [...]` in VID/S). Any space can have it. Triggered by right-click (so they require a pointing device to work).

Menu specification is a block: `[opt any flag  any menu-item]`

It starts with optional flags. Currently supported are:
- `radial` - uses [`ring` layout](reference.md#ring) to arrange menu items, instead of the default [`vlist`](reference.md#list)
- `round` - considers menu items round, not rectangular; only has effect together with `radial` flag

**Each menu item** is one or more values to display, followed by a `paren!` with code to evaluate when this item is chosen:\
`data data ... (code)`

Item data can contain: `char!`, `string!`, `logic!` and `image!` values, as well as `word!`s referring to spaces. It is laid out using [`row` layout](reference.md#row). When aligning separator (`stretch` aka `<->`) is missing in the row, one is automatically added after first textual space, so rows like `"Find..." "Ctrl+F"` become `"Find..." <-> "Ctrl+F"` and get aligned properly (name to the left, key to the right).

Example from [`popups-test.red`](tests/popups-test.red):
```
menu: reshape [
	;) note usage of logic values for sigils:
	"Approve the course" #[true] (print "On our way")
	"Alter the course" #[false] (
		rocket/angle: random 360
		invalidate rocket
		print "Adjusting..."
	)
	
	;) note that sigil will be right-aligned because `<->` will be inserted after first string:
	"Beam me up" "🔭" (print "Zweeee..^/- Welcome onboard!")
	
	;) note how `switch` space is created by `reshape` and inserted as word into the item block:
	"Thrusters overload" !(anonymize 'switch r-switch: make-space 'switch [state: on]) (
		r-switch/state: rocket/burn?: not rocket/burn?
		print pick ["Thrusters at maximum" "Keeping quiet"] rocket/burn?
	)
]
```
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-menu.png)

