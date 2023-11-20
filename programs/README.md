---
gitea: none
include_toc: true
---


# Programs written with Spaces

## [Red Inspector](red-inspector.red)

A GUI tool to browse current interpreter's state.

Binaries: [Windows](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/red-inspector.exe), [Linux](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/red-inspector), [Mac 32-bit](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/red-inspector-mac). 

<img width=1000 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-red-inspector.gif />

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

<img width=600 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-vids-polygon.gif />


## [Red Mark](redmark.red)

World's smallest markdown viewer.

Binaries: [Windows](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/redmark.exe), [Linux](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/redmark), [Mac 32-bit](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/redmark-mac). 

<img width=700 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-redmark.gif />

This tool's main purpose *for now* is to showcase and test rich content, so:
- it contains only a [*toy* 250-LOC markdown-to-VID/S converter](toy-markdown.red) (I may call it a toy, but some webchat implementations do away with worse for years...)
- I didn't bother making a UI for it
- on startup it downloads images from the web *painfully slowly* (it should be done anynchronously as in browsers, but for now it will at least cache them in `%appdata%\Red\cache`)
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


## [SVG Browser](svg-browser.red)

Mainly a testing GUI for the SVG decoder.

Binaries: [Windows](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/svg-browser.exe)

<img width=900 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-svg-browser.gif />

Requires [SVG branch of Red](https://github.com/hiiamboris/red/tree/svg2). And a lot of compiler workarounds to make a binary ☺

## [ParSEE - Parsing flow visual analysis tool](parsee-tool.red)

Debug your `parse` code with ease!

ParSEE allows you to get an almost immediate **answer** for the questions:
- **How far** did the parsing reach?
- What rule **deadlocks**?
- Which rules succeeded, which **failed and why**?
- Sometimes it also can show double (**suboptimal**) matching

**Real world case studies**:
- [Failed rule discovery on XML codec's example](parsee-case-xml.md)
- [Double matching detection on CSV codec's example](parsee-case-csv.md)
- [Overall decoder evaluation on XML codec's example](parsee-case-eval.md)
- TBD: deadlock case (need realistic code for an example; try `parsee "1" [while [opt skip]]` for now)

A few **examples** of block dialects (clickable):

| Function spec dialect | Rich-text dialect | @toomasv's graph dialect | Red (old) lexer |
|-|-|-|-|
| [ <img width=400 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-fspec.gif /> ](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-fspec.gif) | [ <img width=400 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-rtd.gif /> ](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-rtd.gif) | [ <img width=400 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-graph.gif /> ](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-graph.gif) | [ <img width=400 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-lexer-small.gif /> ](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-lexer.gif) | 

### Setup

ParSEE UI is Spaces-based, but it would be unwise to require Spaces to be included into every small rule we may wish to debug. For this reason the project is split into **two parts**:
1. [`common/parsee.red`](https://codeberg.org/hiiamboris/red-common/src/branch/master/parsee.red) **backend** that collects info during a Parse run
2. [`spaces/parsee.red`](parsee.red) Spaces-based **frontend** that displays and helps analyze it

So to set things up you'll **need**:
1. As **backend** either [`parsee.red`](https://codeberg.org/hiiamboris/red-common/src/branch/master/parsee.red) with all of its dependencies, or [`parsee-standalone.red`](https://codeberg.org/hiiamboris/red-common/src/branch/master/parsee-standalone.red) (**recommended**) that has all dependencies included already. Latter option is a result of [*inlining*](https://codeberg.org/hiiamboris/red-cli/src/branch/master/mockups/inline) the former, and is provided because I know how annoying the #include bugs can be.

   This script, which you'll want to include, contains:
   - `parse-dump` function that gathers parsing progress and saves it into a temporary dump file
   - `inspect-dump` function that `call`s the frontend to inspect the dump
   - `parsee` function that does both steps at once
   
2. Compiled **frontend binary** for your platform: [Windows](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/parsee.exe), [Linux](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/parsee), [MacOS 32-bit](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/parsee-mac)

   This is the UI that reads the saved dump file. Make this binary available from `PATH` as `parsee` or let the frontend ask you where it is located.

### Usage

After everything's set up, **#include the backend** and you should be able play with it in console e.g.:
```
>> char: charset [#"a" - #"z"]
>> word: [some char]
>> parsee "lorem ipsum dolor sit amet" [some [word opt space]]
```
You'll see the UI popping up:

<img width=400 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-simple.gif />

UI lists all detected Parse rules in depth-increasing order, with their profiles (Y = input advancement, X = time in events), and rules text.

Use `Left`/`Right` keys to change time by single event.

<details><summary><b>Overview</b> of the backend...</summary>

---

**`parsee` is a high level replacement for `parse`**:
```
>> ? parsee
USAGE:
     PARSEE input rules

DESCRIPTION: 
     Process a series using dialected grammar rules, visualizing progress afterwards. 
     PARSEE is a function! value.

ARGUMENTS:
     input        [any-block! any-string!] 
     rules        [block!] 

REFINEMENTS:
     /case        => Uses case-sensitive comparison.
     /part        => Limit to a length or position.
        length       [number! series!] 
     /timeout     => Force failure after certain parsing time is exceeded.
        maxtime      [time! integer! float!] "Time or number of seconds (defaults to 1 second)."
     /keep        => Do not remove the temporary dump file.
     /auto        => Only visualize failed parse runs.
```
It parses input, collects data and calls the frontend for analysis. Optionally /auto flag can be used to skip successful parse runs, and only visualize failures.

---

**`parse-dump` is a lower level `parse` wrapper**:
```
>> ? parse-dump
USAGE:
     PARSE-DUMP input rules

DESCRIPTION: 
     Process a series using dialected grammar rules, dumping the progress into a file. 
     PARSE-DUMP is a function! value.

ARGUMENTS:
     input        [any-block! any-string!] 
     rules        [block!] 

REFINEMENTS:
     /case        => Uses case-sensitive comparison.
     /part        => Limit to a length or position.
        length       [number! series!] 
     /timeout     => Specify deadlock detection timeout.
        maxtime      [time! integer! float!] "Time or number of seconds (defaults to 1 second)."
     /into        => 
        filename     [file!] "Override automatic filename generation."
```
It only does the collection of data. By default it is saved with a unique filename in current working directory. When something goes wrong on either side, it becomes useful to dump the data for manual inspection.

---

**`inspect-dump` is a frontend launcher:**
```
>> ? inspect-dump
USAGE:
     INSPECT-DUMP filename

DESCRIPTION: 
     Inspect a parse dump file with PARSEE tool. 
     INSPECT-DUMP is a function! value.

ARGUMENTS:
     filename     [file!]
```
It can be used to analyze a set of previously saved dumps right from the console.

</details>
