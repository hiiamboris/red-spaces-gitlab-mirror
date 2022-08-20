# Programs written with Spaces

## Red Inspector

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

To run Inspector from sources, you'll need the [`cli` library](https://gitlab.com/hiiamboris/red-cli/) along with `spaces` & `common` usual setup.

## VID/S Polygon

A livecoding tool to experiment with various VID/S layouts.

![](https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/vids-polygon.gif)
