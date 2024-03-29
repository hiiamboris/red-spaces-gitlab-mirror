---
gitea: none
include_toc: true
---

# Spaces Console

Spaces Console is an experimental GUI console replacement for use with Spaces and on its own.

Binaries: [Windows](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/spaces-console.exe), [Linux](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/spaces-console), [Mac 32-bit](https://link.storjshare.io/raw/jx4mhyld6tltxxfjekouysbhziwa/bin/spaces-console-mac). 

<img width=500 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-spaces-console.gif />

## Features

- **paragraph-centric** design, with all of console's history being available for re-evaluation (as opposed to line-terminal design with the ability to 'recall' last line)
- editor, output and result are three separate interactive widgets, allowing one to investigate even big output without the need to 'shorten' it or risk of cluttering the console
- automatic re-evaluation of the tail of the log once some prior setting changes, so you don't have to lose time browsing through your commands when you're testing a chain of multiple expressions
- extensible via **plugins**, with some available out of the box
- includes whole **`red-common`, `red-spaces` and `red-cli`** functionality
- a CLI library-based program, can be both used standalone and to run scripts
- extremely crash-happy xD ¯\\\_(ツ)\_/¯ (but saves and restores the log so it's not lost)

#### CLI syntax

```
$ spaces-console --help
Spaces Console 8-Jan-2024 Advanced REPL for Red built on top of Spaces by hiiamboris

Syntax: spaces-console [options] [script]

Options:
      --reset    Run console with no state (use in case it's broken)
      --catch    If script is given, don't close after it finishes
      --version  Display program version and exit
  -h, --help     Display this help text and exit

```

#### Running from sources

If you don't want to use binary release for some reason, you need up to date mirrors of other used repositories (alongside `spaces`):
- [`red-common`](https://codeberg.org/hiiamboris/red-common) as `common`, required for anything Spaces-based
- [`red-cli`](https://codeberg.org/hiiamboris/red-cli) as `cli` - used to read command line

`red spaces-console.red` command from the directory where it's located should start it.

## Available plugins

All currently implemented plugins can be **installed** with this command in the console:
```
system/console/install-plugin %highlighting.red
system/console/install-plugin %tab-completion.red
system/console/install-plugin %smart-paste.red
```
Plugins will be **downloaded** from this repo and will take effect after console is **restarted**. 

### highlighting.red

Provides automatic syntax highlighting using `transcode/trace` functionality. Default color map tries to blend in with the OS theme, as the rest of Spaces.

Color map can only currently be adjusted by manual editing of the state file (usually in `%LOCALAPPDATA%/spaces-console/` or `~/.local/state/spaces-console/`). GUI to edit it will be added sometime later.

### tab-completion.red

Switches Tab key to complete input (words, paths, filenames).

### smart-paste.red

Allows pasting formatted console output directly into the console as commands.

For example if you encounter this text in Matrix:
```
>> name: "Spaces"
== "Spaces"
>> print ['hello name]
hello Spaces
```
You can copy and paste it directly into the console, and it will split commands from the rest and evaluate:

![](https://link.storjshare.io/raw/jxfnjjold7d4xtoupll4mp7ychkq/img/3aapYr6.png)
