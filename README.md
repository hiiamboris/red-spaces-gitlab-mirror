---
gitea: none
include_toc: true
---

# RED SPACES - DRAW-BASED WIDGET LIBRARY FOR [RED](http://red-lang.org/)

Official URL of this project: [https://codeberg.org/hiiamboris/red-spaces](https://codeberg.org/hiiamboris/red-spaces) (you may be viewing an automatic mirror otherwise)

## Examples (clickable)

| Spiral editable field | Grid-view |
|---|---|
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-spiral-field.gif) | ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-view.gif) |
|  **Infinite list of items *of varying size*** | **Self-containing grid** |
| ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-infinite-list.gif) | ![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-self-containing-grid.gif) |

Spiral Field demo reuses the normal rectangular `field` space (that contains all the keyboard logic and everything) by transforming hittest coordinates in a spiral way. Rendering logic of course had to be rewritten because such complex transformations are far beyond Draw capabilities. That's why it's a bit laggy: it renders each character individually.

Grid-view demo demonstrates how events are handled naturally even on a rotated and distorted layout.

Infinite List's trick is that when items vary in height, it's hard to provide uniform scrolling (naive desings would scroll at item granularity) and at the same time make it respond in real time to user actions.

Self-containing grid shows that there are no limitations: every space can contain any other space, or even itself (but then one has to manually limit the rendering depth or stack will overflow ☻).

| [MORE DEMOS IN /TESTS](tests/) |
| :-: |

## Docs

#### [Quickstart](quickstart.md) - if you just wanna use one in your program
#### [VID/S manual](vids.md) - description of the layout dialect (must read after Quickstart)
#### [Tinkerer's manual](manual.md) - for deeper understanding and how to alter things
#### [Widget Reference](reference.md) - reference of all available space templates and their properties
#### [Creators Guide](creators.md) - description of the architecture that will help you write your own Spaces


## Status

**Alpha stage. Some design changes possible, risk of breaking changes.**

Good enough to write basic apps with. Design enhancements proposals and feature requests are welcome =)

| By component | State |
| --- | --- |
| Widget architecture | Stable |
| Events | Stable |
| Timers | Stable |
| Styling | Syntax may change |
| Focus model | Stable |
| [Tabbing](https://en.wikipedia.org/wiki/Tabbing_navigation) | Stable |
| [Spatial navigation](https://en.wikipedia.org/wiki/Spatial_navigation) | Not implemented |
| Resize model | Mostly stable. Needs some internal work. |
| Layout | Designed and [documented](vids.md), will be extended when required |
| Grid/Table | Requires interactivity: columns dragging, sorting, filtering |
| Reactivity | Waiting for [PR #4529](https://github.com/red/red/pull/4529) (reactivity has to be scalable for Spaces scope). Temporary kludges are inserted by VID/S |
| Quickstart | [Written](quickstart.md) |
| User guide | [Written](manual.md) |
| Widget reference | [Written](reference.md) |
| Creator's guide | [Written](creators.md) |
| Templates | None made so far |
| Alternate stylesheets | None made so far |


## Goals

- make complex widgets portable and accessible
- make it possible to create custom widgets *easily*
- implement a set of complex widgets in their basic form, to serve as templates
- test various UI framework ideas, see how they work and if they could improve View
- make styling of UI an easy and fun undertaking
- provide a basis for dynamic animated UIs (animation dialects and 2D game engines may be based upon this project)


## Help & feedback

If you find it too complex to achieve some task, you can [ask my advice on Gittard](https://gitter.im/hiiamboris).\
When you spot bugs or other issues you can report them also on Gittard or by creating an [issue report or wish request](https://codeberg.org/hiiamboris/red-spaces/issues/new). Improvement ideas are also welcome :)

