# Demos for testing

During development, I've created a number of test scripts, which help me debug things when my changes break something, and help see how my model performs.

These scripts are not meant to be templates you can just grab and extend, but until I make templates it will be the closest thing.

Screenshots show the expected behavior.

To try out any of the tests:
1. clone the repository:
```
git clone https://gitlab.com/hiiamboris/red-mezz-warehouse common
git clone https://gitlab.com/hiiamboris/red-spaces
```
2. run any test:
```
cd red-spaces/tests
red <test-name.red>
```

## Common tests

---

[**web-test.red**](web-test.red)

<img width=400 src=https://s3.gifyu.com/images/GIF-03-May-21-19-05-28.gif></img>

Simplest infinite canvas test, with a spider web. 

---

## Text tests

[**spiral-test.red**](spiral-test.red)

<img width=400 src=https://i.gyazo.com/74d4e22f7480bda9f5c2df8e11c6bfb5.gif></img>

Stress test. Huge editable field curled spirally. Very slow, because renders each glyph separately :)

## Grid tests

[**grid-test1.red**](grid-test1.red)

<img width=400 src=https://i.gyazo.com/69ce7643af977dd4d4a376b1e336f008.png></img>

Simplest fixed `grid` with 2 buttons. Clickable and tabbing should work.

---

[**grid-test2.red**](grid-test2.red)

<img width=400 src=https://i.gyazo.com/46fc42ad3116f89063eb18fdc6b35a6c.png></img>

Simple enough `grid` that I use to test if cell span works. Has fixed limits and uneven row height.

---

[**grid-test3.red**](grid-test3.red)

<img width=400 src=https://i.gyazo.com/f6844992a49e3bbf9f7c997ebe5b4a67.gif></img>

Minimalistic `grid-view`. Size defined by data. Data is limited.

---

[**grid-test4.red**](grid-test4.red)

<img width=400 src=https://s3.gifyu.com/images/GIF-03-May-21-17-20-45.gif></img>

Big `grid-view` with unlimited data, pinned columns & rows, cell span. Should not be lagging too much.

---

[**grid-test5.red**](grid-test5.red)

<img width=400 src=https://i.gyazo.com/582a0e5e72bbf10e86a401052a0641da.png></img>

Stress test. A `grid-view` that contains itself in each cell, truncated at some depth. Very slow. At depth=6 it has to render 4^6 = 4096 cells. Depth=7 contains 16384 cells, and 8192 scrollers, and takes about a minute to render.

---

[**grid-test6.red**](grid-test6.red)

<img width=400 src=https://i.gyazo.com/781656f9bf1cbb3936a7df133519ffb0.gif></img>

Stress test. An infinitely zooming animation for `grid-view` that contains itself in each cell. Uses smarter rendering code that helps speed it up, but still has to be truncated at 625 cells to be responsive.

---

[**grid-test7.red**](grid-test7.red)

<img width=400 src=https://i.gyazo.com/288716f3afecef834a9b1b0b75e47b5d.gif></img>

Stress test. An infinitely zooming animation for `grid-view` that contains itself only in the central cell, which allows to render it quite deeply.


