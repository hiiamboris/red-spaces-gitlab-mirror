# Alternate stylesheets

If default flat look based on OS colors doesn't work for you, and you're not up for writing your own stylesheet, use one of the available ones here, or use it as a basis to build from.

Be aware that whatever look you like, majority of the users will not. Always provide a choice.

## [Glossy](glossy.red)

So far the only implemented alternate stylesheet, used mainly to push the limits of current styling design and to show what's possible.

Keep in mind that it's far from efficient (need effects support in Draw) and is a bit hacky (because not everything it does styles were designed for). 

By-design look (on [`glossy-test.red`](../tests/glossy-test.red)):

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-glossy-test.gif)

And here's Red Inspector with it included (though Inspector declares it's own styles which replace those from the stylesheet so it's *not fully* styled, and has a glitch with `hscroll`):

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-red-inspector-glossy-styled.gif)

Of course for full effect you will need to remove the OS frame and draw it yourself on a borderless window.

To use it, include it after `everything.red`:
```
#include %spaces/everything.red

#process off											;@@ hack to avoid #include bugs
do/expand [#include %spaces/stylesheets/glossy.red]
#process on
```
