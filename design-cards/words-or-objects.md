# Design card: Spaces tree structure: words or objects?

When I started developing Spaces, I already knew from my experience with View how many `mold` problems objects within objects create (like [#4118](https://github.com/red/red/issues/4118)).

At least for a time, I decided to use words where objects would be, and these words contained an implicit reference to the object itself. But this created other problems (explained below).

Even after Spaces core somewhat matured I was unsure if I should continue using words or switch to objects: benefits and drawbacks was hard to predict in such big system. So I had to attempt to make the change to settle this design question once and for all.

This document evaluates the pros and cons of three possible space tree models:
1. Each object reference is a word:
   - in space facets: /content and /owner are a words (or blocks of words), and /items function returns words
   - in maps: /map contains words and /into returns a word
   - in paths: event handlers receive paths consisting of words, and traversal functions generate lists of paths with words in them
2. Only /content and /items become objects, words are used in all other places
3. Objects everywhere, even paths consist of objects: `(parent-object)/(child-object)/(inner-child-object)`

## Model 1. Words everywhere

Is a natural fit for spaces like `scrollbar`:
```
make space! [
	...
	forth-arrow: make space! [...]
	forth-page:  make space! [...]
	thumb:       make space! [...]
	back-page:   make space! [...]
	back-arrow:  make space! [...]
	...
]
```
In such object I *already have* the words, and get path access (e.g. `scrollbar/thumb/size`), and I don't need to create another word.

But spaces like `box` and more complex ones do not contain hardcoded spaces, instead they have to expose a /content facet that links to an arbitrary other space. Content has to be a word, because there's no other place where style name of the child object can be kept. Word acts as a name, and at first glance it looks like a minimalistic model (but turns out it's not).

Such words each need an object to bind it to, e.g. in a list of 100 `item`s, each `item` word needs a separate object, otherwise all `item`s would reference the same value.

Path access to contents of generic containers is also obstructed: I have to write: `value: select get space/content 'facet` instead of just `value: space/content/facet`, and that's a simple case.

Pros:
- moldable out of the box, easy to debug
- no risk to freeze and run out of memory

Cons:
- no path access, which may be annoying to the user
- requires hacking the console, so I can use paths during debugging, and console would translate these invalid paths into valid ones
- extra resource waste: CPU time to create anonymous object for each word, RAM amount to keep it, and then CPU time spent on GC run

Object creation time is not significant enough to consider, but GC at least currently is far from fast. I measured that it adds +60% to the tree rendering time, and had to disable it during render.

RAM waste can be measured more precisely:

| Words in the object | Object's size in bytes | Bytes per word |
|-|-|-|
| 0-4   | 424   | >106 |
| 5-6   | 728   | >121 |
| 7-8   | 1868  | >233 |
| 9-16  | 2428  | >150 |
| 17-33 | 3500  | >106 |

I used words for /content, /owner and /cache, each is 424 bytes, totalling 1272 bytes of pure overhead over the 1868-2428 normal space size, which makes for +50-70%. Quite a lot!

In my opinion these numbers can be halved for `0-4` and `7-8` intervals, but in the end the wasted percentage will be the same, because minimal space has around 7-10 words regardless of how I organize it.

<details><summary>Here's the script I used to measure RAM requirements...</summary>

```
Red []

recycle/off
recalc: does [
	report/text: form try [
		proto: do type/text
		new: load spec/text
		s1: stats
		loop n: 10000 [make proto new]
		to integer! stats - s1 / n
	]
	do-events/no-wait
	recycle
]
view [
	text "Measure the size of a datatype" return
	text "Type:" type: drop-down select 4 focus
		data foreach x sort to [] exclude any-type! immediate! [append [] form x]
		on-change :recalc
		on-key [if event/key = tab [set-focus spec]]
		return
	text "Spec:" spec: field 200 "" on-enter :recalc
		on-key [if event/key = tab [set-focus type]]
		return
	report: text 300x100
]
quit
```

</details>



## Model 2. Only /content and /owner are words

The idea is to make path access `space/content/facet...` possible (for convenience), but to keep paths as lists of words.

Drawback is it requires addition of a `/style` facet to all spaces, because now I don't know the name of the object in /content facet anymore, and I need it to apply both style and dispatch to the relevant event handler. Class name could be used as a style name, but it's sometimes meant to be internal (like `list-in-list-view`), and I don't want to expose that into stylesheet, nor make it styled any differently than just `list`. So I ruled that out.

Pros:
- has path access to child spaces within /content (which is now object of block of objects)

Cons:
- mold has increased risk of big output, e.g. if /content is a block of objects and each object also contains multiple objects, so custom `mold` function is required
- resource waste is even bigger than in model 1: adding 106 bytes per space for /style facet (since paths still have to contain bound words, I still have to create anonymous objects and bind /style word to them, so /style word would back reference it's own object)
- in many places `get` still has to be used to access the object, e.g. in event handlers (which receive paths of words)

## Model 3. Objects everywhere

If I'm not using words to refer to objects, then I don't need anonymous contexts to hold these words in. /style facet is a simple word then.

Pros:
- noticeably lower resource consumption, and especially faster cache operation due to it being more readibly accessible (as it's just a block now)
- ease (and readability) of child object access, not need to bother with `get`
- /style is kept within the object, easy to override, no need to keep it elsewhere (e.g. grid's internal cache can contain just cell objects, not word+object pairs)                  

Cons:
- custom `mold` is a requirement (means also hacking `save` and help system)
- risk of `form`ing the tree\*
- hittesting and listing paths now consist of objects, which is not how we are used to think about paths (on the other hand it makes for easier access to those objects)
- harder to access known items in maps: instead of `map/thumb/size/x` I have to write `pick select find/same map thumb 'size 'x` (fortunately just a few places) 

\* As I show in [REP #134](https://github.com/red/REP/issues/134), the meaning of `form` is most likely to produce single-line messages. It is quite disappointing then to see it freeze for a minute and then throw an out of memory error, or output hundreds of megabytes of text in it's zealous attempt to form the complex tree, as if anyone would ever need that. Even more dissatisfying is that I cannot meaningfully override it, as unlike `mold`, `form` is often called internally, namely by string actions (`insert`, `append`, `change`), by `rejoin` (which is `append`-based), by `print`. Even if I could rewrite `print`, maybe even `rejoin` (though that's costly), rewrite of actions is not possible at Red level.

After making a transition to this model, I see it as an overall win. Resource usage and convenience is well worth the effort I spent on `mold`, and this work also strongly highlighted the issues in our debugging tools, which we'll hopefully be able to improve. Indeed if tools is the main source of problems, we should focus on tools, not find workarounds.
