---
gitea: none
include_toc: true
---

# RED SPACES - DRAW-BASED WIDGET LIBRARY FOR [RED](http://red-lang.org/)

## Examples (clickable)

| Spiral editable field | Table |
|---|---|
| ![](https://i.gyazo.com/74d4e22f7480bda9f5c2df8e11c6bfb5.gif) | ![](https://i.gyazo.com/5f16371407967a41e16bb6f601201a70.gif) |
|  **Infinite list of items *of varying size*** | **Self-containing grid** |
| ![](https://i.gyazo.com/856724cebae6a5967a9eb96142dd35de.gif) | ![](https://i.gyazo.com/4a2557024a80ac54e890fbf665e1cf7a.gif) |

\>\> [MORE DEMOS IN /TESTS](tests/) <<

Spiral Field demo reuses the normal rectangular `field` space (that contains all the keyboard logic and everything) by transforming hittest coordinates in a spiral way. Rendering logic of course had to be rewritten because such complex transformations are far beyond Draw capabilities. That's why it's a bit laggy: it renders each character individually.

Table demo demonstrates how events are handled naturally even on a rotated layout.

Infinite List's trick is that when items vary in height, it's hard to provide uniform scrolling (naive desings would scroll at item granularity) and at the same time make it respond in real time to user actions.

Self-containing grid shows that there are no limitations: every space can contain any other space, or even itself (but then one has to manually limit the rendering depth or stack will overflow ☻).

## Docs

- [Quickstart](quickstart.md) - if you just wanna use one in your program
- [Widget Reference](reference.md) - if you're interested in what Spaces are available and how they work
- [Creators Guide](creators.md) - will describe the architecture and help you write your own Spaces


## Status

**Alpha stage. Some design changes possible, risk of breaking changes. Not very high-level yet.**

Good enough to experiment with, and to propose design enhancements and feature requests.

| By component | State |
| --- | --- |
| Widget architecture | Mostly stable | 
| Events | Mostly stable |
| Timers | Stable | 
| Styling | Mostly stable |
| Focus model | Mostly stable |
| [Tabbing](https://en.wikipedia.org/wiki/Tabbing_navigation) | Mostly stable |
| [Spatial navigation](https://en.wikipedia.org/wiki/Spatial_navigation) | Not implemented |
| Resize model | Need a powerful simple design idea, ideally that would apply to faces too |
| Layout | Embedded into View layout seamlessly, but very basic: only accepts space names and `with` |
| Grid/Table | Requires interactivity: columns dragging, sorting, filtering |
| Reactivity | Waiting for https://github.com/red/red/pull/4529 |
| User's guide | Written |
| Widget reference | Written |
| Creator's guide | Written |
| Templates | None made so far |



## Goals

- make complex widgets portable and accessible
- make it possible to create custom widgets *easily*
- implement a set of complex widgets in their basic form, to serve as templates
- test various UI framework ideas, see how they work and if they could improve View
- make styling of UI an easy and fun undertaking
- provide a basis for dynamic animated UIs (animation dialects and 2D game engines may be based upon this project)


## Help & feedback

If you find it too complex to achieve some task, you can [ask my advice on Gittard](https://gitter.im/hiiamboris).\
When you spot bugs or other issues you can report them also on Gittard or by creating an [issue report or wish request](https://gitlab.com/hiiamboris/red-spaces/-/issues/new) in this repository. Improvement ideas are also welcome :)

