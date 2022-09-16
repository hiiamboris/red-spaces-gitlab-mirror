# Design card: Algorithms for automatic grid column width estimation

This is something we are all accustomed to and every table widget should support.

All modern browsers implement such automatic estimation (on this gif - Pale Moon browser):
<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-browser-autofit.gif></img>

The task is: knowing cells content (which can be arbitrary and can follow unknown scaling algorithms) and total width to fill, adjust all column widths so that the table would look pleasant to the human eye and these widths would sum to total width. And do that with as little rendering attempts as possible.

Obviously there is no ultimate solution to this, only approximations. In Spaces, following assumptions are made:
1. Most pleasant look is seen as height minimization problem: the lesser the height, the better.
2. A solution can be found by measuring and processing individual column sizes: the core primitive is a function that given column index and width returns it's full rendered height.
3. Each spanned cell affects evenly all columns it spans: it's rendered height is simply divided by the number of columns.
4. Column height is a monotonically decreasing function of it's width.

A total of four fitting algorithms is implemented (each with it's own strengths).

A key idea is to treat each cell as an aquarium: it's amount of liquid (area) doesn't change and if we stretch aquarium's width, it's waterline (height) comes down proportionally. Thus we get a hyperbola `W×H = const`. As such, it works best for flow layouts of small items (small individual letters of `text`, small images in a `row`).

## `width-difference`

**Idea:** distribute free table width proportional to *difference* between min and max total *widths* of individual columns. 

This is the simplest algorithm, which also seems employed by browsers:
1. Minimum (<code>W₁<sub>i</sub></code>) and maximum (<code>W₂<sub>i</sub></code>) column widths are measured.
2. Minimum widths are summed to obtain minimum total width: <code>TW₁ = ΣW₁<sub>i</sub></code>.
3. Max/min width differences <code>W₂<sub>i</sub> - W₁<sub>i</sub></code> are taken as `weights`.
4. Difference between total requested width and minimum total width <code>TW - TW₁</code> is distributed across all columns proportional to `weights`, on top of <code>W₁<sub>i</sub></code>.

The whole algorithm is just two lines:
```
weights: W2 - W1
W: weights / (sum weights) * space-left + W1
```
It's power is simplicity, relatively good performance (as proven by browsing experience) and good tolerance to edge cases.

It is based on the following assumptions:
1. Maximum widths <code>W₂<sub>i</sub></code> all correspond to the same column height. 
2. Product of column width by it's height `W×H` is constant, so <code>ΣW<sub>i</sub>×H = H×ΣW<sub>i</sub> = H×Σ(W₁<sub>i</sub>+ΔW<sub>i</sub>) = TW₁<sub>i</sub> + H×ΣΔW<sub>i</sub> = TW₁<sub>i</sub> + H×(TW-TW₁)</code>, where <code>ΔW<sub>i</sub></code> is column's width extension

Best case scenario:
- all cells contain text of the same length (in pixels)
- all text is using font of the same size
- words are small enough or do not vary in size greatly

Bad edge cases:
- font size varies across columns, or some other objects of bigger-than-letter size are present
- some columns contain big words or objects, while others don't


## `width-total`

**Idea:** distribute total table width proportional to max *total widths* of individual columns.

Key difference from `width-difference` is that weights equal `W₂`, not `W₂ - W₁`, which makes more sense but complicates the algorithm a bit, because now they cannot be easily proporionally distributed: some column widths may happen to fall below <code>W₁<sub>i</sub></code> and require adjustment. 

The algorithm:
1. Minimum (<code>W₁<sub>i</sub></code>) and maximum (<code>W₂<sub>i</sub></code>) column widths are measured.
2. Minimum widths are summed to obtain minimum total width: <code>TW₁ = ΣW₁<sub>i</sub></code>.
3. Maximum widths <code>W₂<sub>i</sub></code> are taken as `weights`.
4. Total width `TW` is distributed across all columns proportional to `weights`, correcting the result so it doesn't go below <code>W₁<sub>i</sub></code> (this requires sorting columns by their weight-to-min-width ratio and distributing `TW` in ratio ascending order).

Best case scenario:
- all cells contain text of the same length (in pixels)
- all text is using font of the same size

Bad edge cases:
- font size varies across columns, or some other objects of bigger-than-letter size are present


## `area-total`

**Idea:** distribute total table width proportional to max *total area* of individual columns.

Key difference from `width-total` is that weights equal `W₂×H₂`, not `W₂`, so it accounts for varying font size or other objects.

This becomes trickier as whatever width estimates are obtained, they have to be contained within `[W₁..W₂]` range. I had a strict solution but dropped it in favor of simple binary search, which should be no slower, and eventually faster as vectors support in Red improves.

The algorithm is explained in `area-difference`, with the only distinction is that constants <code>C<sub>i</sub></code> are zeroes for this case.

Best case scenario:
- all cells contain text of the same area (e.g. font height multiplied by text length) or objects of the same size

Bad edge cases: none.

## `area-difference`

**Idea:** fit hyperbolae `(W+C)×H` upon two points `(W₁,H₁)` and `(W₂,H₂)` for each column by introducing offset vector `C`, then find such height where sum of column widths equals total table width. 

Key difference from `area-total` is in offset `C`, which allows hyperbola to cross not only point `(W₂,H₂)` but also `(W₁,H₁)`.

The algorithm:
1. Minimum (<code>W₁<sub>i</sub></code>) and maximum (<code>W₂<sub>i</sub></code>) column widths are measured.
2. <code>C<sub>i</sub></code> constants are found from the `(W₁+C)×H₁ = (W₂+C)×H₂` vector equation.
3. Minimum (`H₋`) and maximum (`H₊`) table heights are obtained as the search segment boundaries.
4. [Binary search](https://en.wikipedia.org/wiki/Binary_search_algorithm) is performed on `[H₋..H₊]` segment to obtain a table height estimate <code>H<sub>e</sub></code> where column widths sum is closest to total table width `TW`.
5. Column widths are found from the <code>(W+C)×H<sub>e</sub> = (W₂+C)×H₂</code> vector equation.

Best case scenario:
- all cells contain text of the same area (e.g. font height multiplied by text length) or objects of the same size

Bad edge cases: when some cells can become very thin and tall, while others are comparatively wide and low (see the gif example below).

## Performance and edge cases

All four algorithms on text-only grids:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-text-all-methods.gif)

`width-difference` vs `width-total` where some cells have bigger height than others:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-pics-width-only.gif)

`width-total` vs `area-total` where some cells have bigger height than others:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-pics-total-only.gif)

`area-total` vs `area-difference` where some cells have bigger height than others:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-pics-area-only.gif)

`width-difference` vs `width-total` on a mixed content:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-mixed-width-only.gif)

`width-total` vs `area-total` on a mixed content:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-mixed-total-only.gif)

`area-total` vs `area-difference` on a mixed content:
![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-mixed-area-only.gif)

Based on this data, `area-total` is chosen as default algorithm for it's resilience.

