# Demos for testing

During development, I've created a number of test scripts, which help me debug things when my changes break something, and help see how my model performs.

These scripts are not meant to be templates you can just grab and extend, but until I make templates it will be the closest thing.

Screenshots show the expected behavior.

To try out any of the tests:
1. clone the repositories:
```
git clone https://codeberg.org/hiiamboris/red-common common
git clone https://codeberg.org/hiiamboris/red-spaces
```
2. run any test:
```
cd red-spaces/tests
red <test-name.red>
```

## Common tests

[**web-test.red**](web-test.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-web-test.gif></img>

Simplest infinite canvas test, with a spider web. I use it to check if `inf-scrollable` works at all.

---

[**scrollbars-test.red**](scrollbars-test.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-scrollbars-test.gif></img>

Tests of how scrollbars adapt their look to various sizes.\
Not interactive yet, as scrollbars events are undefined outside of `scrollable` space's use.

---

[**tube-test1.red**](tube-test1.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-tube-test1.gif></img>

Tests all axes/align combinations of `tube` layout.

---

[**tube-test2.red**](tube-test2.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-tube-test2.png></img>

Tests some resizing cases of `tube` layout.

---

[**popups-test.red**](popups-test.red)

<img width=300 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-popups-test.gif></img>

Tests `label` template and popups: hints and right-click menus.

---

[**resize-test.red**](resize-test.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-resize-test.gif></img>

Tests resizing of a relatively complex layout.

---

[**hover-test.red**](hover-test.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-hover-test.gif)

Tests whether space receives `over` events:
- when mouse pointer stays in place but the space itself moves
- when pointer leaves it (the 'away' event)


## Text tests

[**field-test.red**](field-test.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-field-test.gif></img>

Tests `field` operation. It's logic is quite tricky to get right.

---

[**spiral-test.red**](spiral-test.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-spiral-field-small.gif></img>

Stress test. Huge editable field curled spirally. Very slow, because renders each glyph separately :)




## List tests

[**list-test1.red**](list-test1.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-list-test1.png)

Simplest `list` of 3 `button` spaces.

---

[**list-test2.red**](list-test2.red)

<img width=300 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-list-test2.gif></img>

`list-view` test: a scrollable window moving over a big but finite content.

---

[**list-test3.red**](list-test3.red)

<img width=300 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-list-test3.gif></img>

`list-view` test: a scrollable window moving over *infinite* content. No matter how far scrolled down, it should be responsive.

---

[**list-test4.red**](list-test4.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-list-test4.gif)

`list-view` test: each list-view item is a `label` which is a horizontal list. It shouldn't be "jumping" which is the case if each label filled the whole viewport of list-view vertically, and then `roll` function would always detect a jump condition.

---

[**list-test5.red**](list-test5.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-list-test5.gif)

`list-view` and `scrollable` test: each list-view item is a `label` put into a scrollable (with different `content-flow` value). A very complex layout under the hood with many possible failure points:
- window (in list-view) may not size itself properly if not given finite canvas (result may be empty)
- inner scrollables may not adapt their size properly, or be given a wrong canvas (they should not exceed outer scrollable's viewport and should not try to fill it vertically, and they should not be empty)
- unwanted invalidation in scrollable's drawing code may make this test slow (it should be realtime, with no noticeable delays)
- weird glitches can be seen if inner scrollables trigger `roll` by their filling attempts


## Grid tests

[**grid-test1.red**](grid-test1.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test1.png></img>

Simplest fixed `grid` with 2 buttons. Clickable and tabbing should work.

---

[**grid-test2.red**](grid-test2.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test2.png></img>

Simple enough `grid` that I use to test if cell span works. Has fixed limits and uneven row height.

---

[**grid-test3.red**](grid-test3.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test3.gif></img>

Minimalistic `grid-view`. Size defined by data. Data is limited.

---

[**grid-test4.red**](grid-test4.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test4.gif></img>

Big `grid-view` with unlimited data, pinned columns & rows, cell span. Should not be lagging too much.

---

[**grid-test5.red**](grid-test5.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test5.png></img>

Stress test. A `grid-view` that contains itself in each cell, truncated at some depth. Very slow. At depth=6 it has to render 4^6 = 4096 cells. Depth=7 contains 16384 cells, and 8192 scrollers, and takes about a minute to render.

---

[**grid-test6.red**](grid-test6.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test6.gif></img>

Stress test. An infinitely zooming animation for `grid-view` that contains itself in each cell. Uses smarter rendering code that helps speed it up, but still has to be truncated at 625 cells to be responsive.

---

[**grid-test7.red**](grid-test7.red)

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-grid-test7.gif></img>

Stress test. An infinitely zooming animation for `grid-view` that contains itself only in the central cell, which allows to render it quite deeply.

---

[**grid-test8.red**](grid-test8.red)

<img width=600 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-autofit-text-all-methods.gif></img>

Test for column [autofit algorithms](../design-cards/grid-autofit.md). Contains grids with edge cases of text and (commented) images content.


## Rich content tests

[**rich-test1.red**](rich-test1.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-rich-test1.png)

A simplest rich content test which I'm using to debug whitespace handling, hittesting and caret location.

---

[**rich-test2.red**](rich-test2.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-rich-test2.gif)

A more realistic rich content test which shows if alignment works as desired. Initial capital `L` is an image.


## Cache checks

[**sync-test1.red**](sync-test1.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-sync-test1.png)

Simplest scenario that tests deep cache fetching after a render on another canvas. Also may show bind-related glitches in styles written in block form.

---

[**sync-test2.red**](sync-test2.red)

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-sync-test2.png)

More complex scenario with multiple nested tubes, for the same purpose. "T" letter should be seen *by hittest* in the center.


