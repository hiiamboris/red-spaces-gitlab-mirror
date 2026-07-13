# Redefining The Future of GUI: Spaces v2 Design Scope

> Spaces v1 is a high-level vector-based GUI system for Red programming language, nearly reaching parity with web experience but without all of web's bloat (in a <1MB binary!). It includes such hardcore features as infinite lists and grids and a fully-featured document processor.

> Spaces v2 will address all of v1 design shortcomings, making it higher level and much more flexible than the web stack, but also turning it into a software revolution.

**What it is**: client-server transport-agnostic and language-agnostic GUI architecture for low-to-high latency connections.

Key **principles**:
- **accessibility and reach**: use advanced modern GUI from any programming language, in desktop and mobile apps and on the web
- **flexibility**: asynchronously communicate between the GUI and the program using any transport protocol, fully bridge the gap between desktop and web apps
- up to the **modern networking** challenges: separate GUI from the server to be able to comfortably work with remote machines even over high latency links
- **green**: keep resource consumption at less than 1MB disk size and less than 50MB RAM footprint, with a fully portable single binary or even lighter web page

Think for a moment about the **massive scale** of this project: nearly every human interacts with devices using GUI. **Every**. Even TUI is just a GUI with very small resolution.

This design will solve whole classes of problems we have today in software world.

## The problems

### There are no great GUIs

Most of the **GUIs suck** extremely badly in all aspects. The only polished examples I can name are:
- modern mobile GUIs (like Material Design, SwiftUI and their smaller replicas): top of the art, with high level widgets, smooth animations and thought out UX
- modern web GUIs: nearly on the same level, lagging behind due to web stack's complexity and instability

Most **programming languages either do not have a GUI** or have some useless trash. E.g. for so popular Golang one has to use full web frontend (Wails), as the rest is too low level to be of any practical use. Haskell, Rust, C - the issue is widespread. Some like Ocaml have nothing at all. In Redbol family of languages, only Red has Spaces while others abandon the whole idea of having a GUI and unconditionally surrender to web, losing all their languages benefits.

Desktop **operating systems** have practically barebones **ancient** low level UIs, unsuitable for any real world tasks, lacking even such common components like rich grids and charts. Inconsistent with each other in looks and features. Mixing together GUIs of different generations, buggy all through and never finished.

For these two reasons we see **everyone abandoning desktop GUIs** and jumping on Electron, which is a full web browser, and is absurdly resource hungry. Some JS runtimes try to be smaller at the cost of having small feature set, but they do not even try address the root issue.

### Existing GUI stacks are a dead end

Web stack is tainted by **decades of mindless bloat-accumulation**. It doesn't stand the slightest technical critique, yet no one dares to question or improve its design. Bloat becomes **a weapon of corporations** because they become the only agents capable of managing it, effectively locking humanity in their walled garden. **Complexity -> control -> money**.

Like **shifting sands, web stack** keeps constantly changing, breaking everything built upon it, draining **billions of man-hours** of useless effort every year. Megacorps in their browser wars are trying to break as much as they can if that helps them push competitor browser out of the market. A promise of unified cross-platform runtime desecrated by the laws of capitalism: it becomes very hard to find a website that works in all of the browsers, and even finding a website that 100% works at all becomes harder every day.

WebAssembly kind of reaches out into the compatibility gap, but unable to interact with the DOM it falls short of really closing it.

**Mobile stack** fares not too much better, with every new OS version breaking unmaintained software, removing useful features in the name of increased control over consumer devices, ignoring critical bugs and vulnerabilities for years. Accessibility, customizeability and convenience don't pay enough and get abandoned. Simplicity, transparency, observability and privacy become anti-values for the capital: megacorps prefer to operate in the shadows they created, where no one can compete, and the cost doesn't matter as long they will be the only players.

### Remote system administration is PITA

**SSH+bash** classics were there since 1995 and these **dinosaurs** are still the go-to method! Typing cryptic fragile unstandardized commands into this ridiculous command line with syntax deserving to be in esoteric languages league!

SSH **connection is ephemeral**. In current world where wireless connections are ubiquitous, it is constantly prone to connection **drops**. Using VPNs like Wireguard helps mitigate that sometimes but once you close the laptop lid, that's a goodbye anyway. **Latency** >100ms also makes working with such tunnel a huge pain, with >500ms being almost intolerable.

**Mosh** tries to monkey-patch these issues by maintaining a UDP connection and predictive typewriting, but in doing so it introduces more issues than it solves, breaking extremely fragile terminal compatibility and making a mess of key combos support. Its predictive capability itself is limited to shell input: try using a simple text editor over 500ms+ connection!

**FAR2L** tries to help with some of the SSH+bash hurdles by automating file listing and output capture, remembering commands and adding session persistence and multiplexing, but it's still dragging the corpse of 'Norton Commander' around habitually, instead of looking at the problems and finding a truly optimal solution.

**Clipboard**, unreliable on every OS as it is, becomes a rabbit hole: there's now local OS clipboard, remote OS clipboard, and often remote software-level clipboard, all intersecting, requiring separate hotkeys which often conflict with something else, and mental bookkeeping of what was stored where.

Having a GUI with the server requires not only a very fast connection, but also installing up to gigabytes of bloat and even that will be totally bug-ridden anyway.

## The solution

While the aforementioned problems seem to be of unrelated classes at first, they all can be solved with one design: **Spaces v2**.

The remote system administration goal dictates the use of **client/server split architecture**. This in turn means that to access the GUI from other languages we don't rely on binary linking, but on client/server **data exchange**.

So we must define precisely what are **the roles of** the client and the server. There are many logical layers between an intent to display data (server) and that data rendered as pixels on the screen (client). But since we aim for high-latency environments, the only meaningful split is the one already taken by the web devs: **client fully handles the GUI**, only interacting with the server when it is unavoidable (similar to how traditionally one fills the web form and then POSTs it). This achieves realtime performance for everything not involving server-side data and minimizes the traffic and cumulative delay.

Any program written in any language of choice will be able to act as **the server**, requiring no part of Red runtime to keep everything simple. The server's only role is to provide the *data* to display. This will give **every programming language** an access to a top-notch cross-platform modern GUI. Including our neighboring projects: Rebol 3 and Ren-C.

**The client** will be a precompiled Red/Spaces runtime running on the user's machine with real-time feedback, drawing everything and handling events. It will receive UI as Red script(s) in text form, load and evaluate, follow all the UI program logic, communicate with the server as required. Thanks to its dialects, Red is much better suited for UI description than most other languages, and keeping the UI in Red will make it portable across apps, at the cost of people having to either learn some Red to write the UI or to use a GUI-based layout designer (for beginners).

A single client can be universal and connect to any server, or it can be preconfigured with certain connection parameters: being lightweight enables a lot of flexibility in this regard.

The following **data exchange** is expected:
- client->server: files to write, shell commands to execute, web requests to make (from the server), system calls to execute...
- server->client: UI layouts, database data to display, directory listings, shell command and web request results, files read, images and sounds...

**Locally**, when both client and the server run on the same hardware, a simple pair of unencrypted OS pipes is enough. For Red-native programs, data exchange can be squashed into a no-op, removing all the overhead.

**Remote** communication will be transport-agnostic. Likely using protobuf (a lightweight widely supported data encoding scheme) over any of: SSH, gRPC, Websockets, Reticulum. In case of websockets security can only be provided by TLS (heavy, rarely available as requires certificates), Yggdrasil (distributed encrypted network) or any VPN, so an additional software-level encryption layer may be added for cases when none of the transport encryption options are available.

Proper **system administration** suite may classically consist of a shell, directory view, viewer and editor. It's much easier to write than people tend to think, but keeping the UI logic close to user is what will make a world of difference.

As Spaces only require a drawing surface, this makes them **extremely portable**. To conquer the existing web stack will only transpiling Red/System code into a mix of WASM (compute) and some JS (events), so it could reliably and performantly run a subset of Red. From there, nearly every consumer device can be reached install-free. Besides, sites written in Red will be accessible not only from bloated web browsers but also from any thin Red/Spaces client, making **web apps** a breeze and greatly reducing the probability of worldwide browser vendor lock-in.

## Is this still relevant in AI era?

More than ever before.

In a physical sense, energy density in this world is limited. This has led us humans to develop what we call "**attention**" - a way to direct this limited amount of energy in a way that's most meaningful for our survival. AI, being subject to the same physical laws, naturally inherits the same "attention" mechanism: it has limits on how much it can process.

The bloat accumulated by most languages has the **same effect on AI** as it has on human developers: AI gets lost, makes mistakes, struggles to understand the full picture, resolves to cheap monkey-patching like a low-pay-grade clerk, etc. I've seen it so many times in my agentic development explorations.

Compact, declarative, readable and efficient code always benefitted human developers, but only those who knew the languages that have these features. In AI era, we (humans) will mostly interact with the AI, not with code. So we don't need to learn the languages anymore. This means that once AI gets trained on an efficient language with efficient GUI framework, AI will start preferring this language and will get thousands of times more productive, and every AI user will immediately get access to this unleashed productivity. When the framework handles every lower level aspect on its own, all that AI has to do is to declaratively express its needs. This applies to Red language as a whole, but even more so to Red/Spaces GUI. Don't just think cost reduction, think leverage and endless possibilities! **Truly portable and lightweight websites and apps built using only a tiny fraction of the effort and within the grasp of every AI user!**

