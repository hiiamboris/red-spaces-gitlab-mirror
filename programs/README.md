# Programs written with Spaces

## [Red Inspector](red-inspector.red)

A GUI tool to browse current interpreter's state.

Binaries: [Windows](red-inspector.exe), [Linux](red-inspector), [Mac 32-bit](red-inspector-mac). 

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-red-inspector.gif)

Red inspector accepts command line arguments:
```
Red Data Inspector 3-Aug-2022 Use `inspect` function in your scripts by hiiamboris

Syntax: red-inspector [options] [script]

Options:
      --version                   Display program version and exit
  -h, --help                      Display this help text and exit
```

Usage:

1. As a standalone system browser

   When run without arguments, it will open itself at `system` object.

2. As an interactive debug tool

   When run with a script pathname, it will evaluate the script and exit.
   
   Script has access to `inspect` function which will bring up Red Inspector window and you will be able to inspect current evaluation state (including local words of currently evaluated functions). Once window is closed, the script will resume evaluation. 

```
>> ? inspect

USAGE:
     INSPECT 'target

DESCRIPTION:
     Open Red Inspector window on the TARGET.
     INSPECT is a function! value.

ARGUMENTS:
     'target      [path! word! unset!] "Path or word to inspect."
```
[`example.red`](example.red) is a demo script that uses `inspect` function to inspect it's state.

If you'd rather run Inspector from sources, you'll need the [`cli` library](https://gitlab.com/hiiamboris/red-cli/) along with `spaces` & `common` usual setup. Otherwise use provided binaries.

## [VID/S Polygon](vids-polygon.red)

A livecoding tool to experiment with various VID/S layouts.

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/vids-polygon.gif)


## [Red Mark](redmark.red)

World's smallest markdown viewer.

Binaries: [Windows](redmark.exe), [Linux](redmark), [Mac 32-bit](redmark-mac). 

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-redmark.gif)

This tool's main purpose *for now* is to showcase and test rich content, so:
- it contains only a [*toy* 250-LOC markdown-to-VID/S converter](toy-markdown.red)
- I didn't bother making a UI for it
- on startup it downloads images from the web *painfully slowly* (it should be done anynchronously as in browsers)
- Red is still crash happy esp. on [`reference.md`](../reference.md) 🤷

I have no plan on extending RedMark right now. But my plan *for the future*: 

1. Real markdown parser.

   GitHub-flavored markdown has a [specification](https://github.github.com/gfm) which will be tedious to implement but eventually it's worth it. There's [another](https://spec-md.com/) (likely incompatible) spec, but a better organized one.
   
   I'd like to either have a full GFM-compliant parser, or at least a parser for the most compatible subset of markdown features (so one can write documents more strictly to ensure it works everywhere). Or both parsers, with mode switch.
   
   In addition it should be able to decode HTML tags supported by GFM (spoilers, tables, etc.)
   
   If you'd like to implement this or enhance, PRs are welcome. @rebolek has [some parser](https://gitlab.com/rebolek/castr/-/blob/5fca70c37ac1bdcfc45028b038f65f7ccc372342/mm.red) but it looks unfinished and abandoned. Might be a good starting point for serious parser anyway :)
   
2. Make it a GUI tool.

   I want it to be detect changes in the file and automatically update the view, navigating to the place of last change.

   So I could edit markdown file in my text editor and in split-screen see the output rendered. I hate having to push file to the repository only to see if I fixed some typos, and I'd rather use a desktop tool (but all the existing ones are either bloated or have no spoiler or even tables support, and totally no HTML). I don't want to turn RedMark into an editor of it's own.
   
   Line diffing could be added to make it more responsive: it should be able to reconstruct only changed widgets.
   
3. Markdown template as an optional module for Spaces.

   This will be handy for in-program documentation browsing, and RedMark will become even smaller ;)

4. Animated GIFs.

   Red has no animated GIF support as of now. Animations can be distracting and hypnotic, and it's likely not a good idea to animate GIFs by default, but I'd like it to be a controllable option.

