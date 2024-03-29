# Design card: Caching mechanics

Caching is paramount to Spaces design. It determines scalability and resource usage: whether program will hit 100% CPU load with a few widgets or will stay below 5% on very complex layouts. Caching is what in the end enables automatic sizing and lifts this burden from the programmer.

It faces the following **challenges**:
1. Some widgets (like `tube`) may need up to 3 renders of its children to reach the optimum arrangement (first to get min children widths and split into rows, then to get the height of the formed row, then finally to fill the row). If we nest a few of them we get exponential increase in render calls (e.g. for `row [column [row [column]]]` - up to 3⁴ = 81x slowdown, and it's a quite simple layout yet).
2. During window resizing many intermediate canvas sizes get cached, never to be used again, resulting in *cache creep*, which both slows down cache operation considerably and wastes a lot of RAM, eventually resulting in throughput less than with no cache.
3. It's not possible to cache the whole subtree of a container, only the important bits (e.g. size and map). As a result, container fetched from the cache may have its cached parameters out of sync with its children, who do not know about recent cache fetch.
4. Infinite or very big widgets (like `grid`) cannot be cached directly, as they can never finish their rendering in a reasonable amount of time. Yet without any caching they become too slow to be of any use.

Cache usage is explained in [Creators guide](../creators.md#caching), so this card only explains design choices and internals.

After many iterations, I have come to the **model** of the cache described below.

Each space must have:
1. A `/cache` facet lists names of facets that can be cached. Values of these facets are stashed together with the canvas size for which they have been obtained. These facets get overridden when a render on the same canvas is requested, skipping the render. If set to `none`, builtin cache is disabled (but space may still have its own custom caching in place, with custom invalidation function).
2. A `/cached` facet is a table (flat block of fixed /skip) populated during render by the following columns:
   - `canvas [pair!]` - cache key; each canvas holds its own set of values of cached facets\
     Canvas serves as a key in the cache, since sizing system is supposed to produce the same visual outcome for the same canvas size.
   - `generation [number!]` - age of the cached slot (explained below)
   - `children [block!]` - block of `[child child-canvas ...]`: list of all children drawn on this canvas with canvas sizes they were rendered on
   - `drawn [block!]` - block of Draw commands, a primary result of rendering on the given canvas
   - values of words from the `/cache` facet - usually `size [pair!]` (for all spaces) and `map [block!]` (for map-based containers only)\
   It gets cleared on invalidation.
3. `/cached` facet has its index = 4, to avoid extra `skip` on each cache lookup. Three hidden slots are:
   - `last-canvas [pair!]` - encoded canvas on which this space was rendered last time
   - `generation [number!]` - age of the cache itself
   - `state [word! or none!]` - how last render attempt went: `cached` (when fetched from the cache), `drawn` (when not fetched, rendered), or `none` (never rendered, initial state)\
   These values must always be present in order to avoid extra checks in performance-critical cache code.
   
A `render` call tries to fetch cached data and only does rendering on cache misses, or if `/cache` is disabled (set to `none`).
Consequently, if no changes are made to the layout, top-level `render` call returns the cached draw block almost immediately, not visiting any of the child nodes. However, `draw` operation is by itself very expensive for complex layouts, so host does not perform it until its immediate `/space` gets invalidated. 

**Invalidation.**

A set of invalidation rules is determined by space's *template* (see [Creators guide](../creators.md#caching)). Invalidation, that is both triggered by facet changes and manually called where necessary, propagates the info about the change up the tree to inform parents (until `host/space`) that they have to re-render themselves.

Invalidation is fast, and is used a lot. Its hook to `on-change` saves the user from manually calling it on every facet update, which I consider just syntactic noise anyway, and it's easy to forget.

One danger of invalidation is it can by accident happen during a render. As a result, after the render the host face will still be marked as invalid, triggering another render on the next timer event, and so the upper part of the tree never gets cached, wasting the resources. In debug mode a check is performed to detect this issue and warn about it. Most likely cause of it is a facet assignment somewhere in a space's style that is never checked for equality (`maybe` or `maybe/same` may solve it).

**Generations.**

A generation is a number that starts with zero and gets increased with every render of a host face. Each host has its own generation unrelated to the others, which is kept in host's `/generation` facet. Each space's cache is marked with this number, as well as each cached slot in it. It is chosen to be of `float!` type because 64-bit float has 52 mantissa bits guaranteeing that increment `gen: gen + 1` works even at 1000 FPS for 50 millions of years.

Reasons to use generations:

1. We need to keep cache itself from creeping, thus to clean up no longer relevant slots. Generation is parameter that tells us if slot is old or not. 

   Old slot is defined as one that was not updated on the previous frame. That is, if space was not drawn at given canvas on this frame, on next frame this slot may be reused for new data. So more formally, old age is `<= current-generation - 1`, where `current-generation` is the generation of the undergoing (unfinished) render, and one before it is the last finished one. 
   
   Slots with canvases `[0x0 0xINF INFx0 INFxINF]` are never aging, because they are not a result of resizing, are likely being used on every frame, and there are only four of them so no risk of cache creep from them. All other slots (e.g. `-300xINF`) are aging.
   
   Old slot gets replaced on cache commits, but may stay indefinitely long if no cache misses happen. No cleanup effort is made to get rid of unused slots, they are only reused.
   
   Invalidation of a space normally cleans up all of its cached slots (unless custom invalidation function is provided to do otherwise).
   It guarantees that on the next frame all render calls do the actual rendering and fill the cache.
   
   Due to explained above exponential increase in render calls, the number of slots per render is hard to predict. With this architecture, it's possible to use as many slots as needed for a frame, without the need to worry about getting out of free slots, and ensure the used slot count doesn't grow.
   
   This mechanism uses slot generation and current generation.

2. We need to be able to determine for each space object if it's connected to the live tree or orphaned.

   Main reason for this is that timers for fast operation require to keep an up to date list of all spaces with an active timer (`rate > 0`). Orphaned spaces should have their timers disabled, otherwise runtime creation of timed spaces (e.g. popups with scrollables) will bloat the list and slow down timers, basically blocking the program.
   
   Spaces have a `/parent` facet, but both live and orphaned space may have the same `/parent`. Identifying who is the most recent child of `/parent` is not so easy given that both `content` and `map` are not enforced facets and lookups in them will slow the system down.

   `get-host-path` function (used by timers in particular) walks up the tree from a given space along the `/parent` facets, and collects its full path (list of all parent objects) relative to host space. After that it walks from top down, checking if child generation numbers match the host's: if a child's generation is older than the host's then it's in an orphaned subtree and does not belong to a live frame. Then a timer is disabled on such space and only active timers are kept in the timers list.
   
   Subtrees however can be fully cached: if container is fetched from the cache, all of its children do not get their generation updated. That's why I added state (`cached` or `drawn`) to the `/cached` facet. Subtree below a space marked with `cached` state (a cached container) is not checked (only the container's generation is).
   
   Deep updates would require so much effort that would clog up the CPU, so this architecture avoids it, while still being able to tell a live space from an orphaned.

   The mechanism uses `generation` and `state` hidden slots of a `/cached` facet, and `host/generation`.
   
   Spaces with `/cache` set to `none` still need this mechanism to work, and `/cached` to hold the hidden slots. So `/cache` and `/cached` facets cannot be unified without losing convenience of `/cache: none` expression and turning it into some function call. 
   
**Data validity.**

When container facets (map, size) are fetched from the cache and replaced, its children still keep their old facets, relevant to the last canvas they were rendered on, which may not match the fetched state of the container. Wrong map leads to wrong hittest geometry and other issues. To avoid it, container's cache fetch operation has to also deeply fetch facets from all children.

Deep fetch is not a scalable operation and would defy the purpose of caching completely, so it's optimized the following way:
- container's render operation remembers which child was rendered on which canvas and stashes this `children` info in the cache slot
- when fetching container from the cache, each of its children `last-canvas` value is matched against the canvas for this child stashed in the `children` block on this container's canvas cache slot
- when they match, child is skipped - it should be valid already
- when they don't child is also refreshed from the cache, and matching is done for its own children (if any)
- to avoid deep fetching it's possible to call `render` with `/crude` refinement - it can be used if container is certain that this child will be rendered again before container's `render` returns (e.g. `tube` finalizes its first two crude renders with a final one).
