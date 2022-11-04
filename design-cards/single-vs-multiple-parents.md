# Design card: Single vs multiple parents tree models

Spaces started with multiple parents support (in fact there were no explicit parents, only paths from the root), as I didn't want to limit the design until I have to. Any space could appear inside any other space, making cyclic (infinitely nested) layouts possible. Fun! =) 

It works well if performance is limitless and we can redraw the whole spaces tree at any time instantaneously. In reality though, scalability of such system was quite limited (dozens of widgets max) and battery drain was high.

I had to introduce caching to stop repeating the same calculation all the time.

But if the same space could look differently in various places in the tree, I couldn't just give cache a space object and receive it's rendered look. I had to give cache both space and it's parent. But that's still a half-measure: what if some grid contains the same cell multiple times (as in the [`grid-test5`](../tests/grid-test5.red) and [`grid-test6`](../tests/grid-test6.red) demos)? Same parent, same space, but look could still vary (e.g. different row heights lead to different cell sizes). Then if you check this cell's /size, it will only tell you the last rendered /size, losing all the intermediate ones. It's only a matter of time before big problems come to light, not to mention complexity of such cache. E.g. space's cache gets filled by it's historical parents, but there's no telling what parents are still valid, and what parents can be removed from it, leading to slowdowns and adhoc kludges to perform at least some cleanup.

Or imagine a simple text cell in a grid. Upon rendering it must know it's coordinate on the grid to decide if it should use the header style or usual cell style. And if it's the same cell that appears in multiple grids in multiple places, what are the chances of getting a correctly looking layout? And what is the cost of getting it correct? 

Then what about focus? Focus model is based on paths, so if I set focus to `host/grid/cell` it means a *particular* cell object. But if it's the *same* cell that appears multiple times in the grid? They all get focused. And what if the same cell belongs to different grids? Now that is a problem, because focus cannot be set on *different* grids at the same time. Models don't fit. Either I make peace with eventual glitches or complicate the focus model beyond any sane level.

Then what about timers? Problem with timers is that they have to be *blazing fast*. Unlike pointer events which follow hittest path, or key events which follow focus path, timers have no path. If I scan the whole space tree 50 times a sec to look for spaces that have a /rate facet, I will get constant 100% CPU load and 99% of that will be useless scanning work. I have to maintain a list of spaces with currently active timers, and give each on-time handler a path with all of it's parents so it knows where it belongs to (e.g. scrollbar parts need to know both about the scrollbar and the scrollable that contains it). If there are multiple such paths, which one should the handler receive? I could pass all of them sequentially, but in practice such tracking considerably slows down timer code.

Then from user's perspective: if /parents is a list, it's just more annoying to access it (which is a common need).

Enter the single parent model, which doesn't have all the aforementioned issues.

The only problems I have with single parent model are:
1. A space cannot legally contain itself anymore, making some very fun demos obsolete :(
2. Some generic spaces like `stretch` (which is just self-adjusting padding), or `empty` (which was just the default contents of containers), or `image` (imagine an avatar icon along hunderds of chat messages) cannot be shared and have to be recreated

Problem 2 turned out to be tiny compared to the performance benefits of single-parent model. Even `image` space can simply share the same `image!` data, and only object gets copied.

Problem 1 is bigger in my view, though I realize these demos have no practical value for UIs, and were just made to show off. In the end I decided to allow overriding the parent (/owner facet) during render of the same tree (`grid-view` first has a `zoomer` owner, then a `cell`), raise no error, but show a warning in debug mode, that this is most likely a bug. For these demos focus and timers won't work for `grid-view` and it's subtree.

So, same space object cannot *legally* appear more than once in the tree anymore. *Technincally* it can, and it still works, but with all the risks explained above accepted.
