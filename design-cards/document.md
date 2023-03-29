# Design card: Document model

This card explains at least top-level design decisions applied in the `rich-paragraph`, `document` and `editor` templates.

As [hypertext](https://en.wikipedia.org/wiki/Hypertext) (or rather [hypermedia](https://en.wikipedia.org/wiki/Hypermedia)) became commonplace, the need for its support in software is now obvious.

If UI system does not have hypertext support, as soon as program requires it, the show is over, because realistically not every coder is capable or ready to implement it. I want Spaces to make great UIs accessible to everyone, so that makes hypertext one of the key features to have, and a great stress test for the whole design.

Funny but despite the ages of web browsers development, they don't usually let us *edit* hypertext directly, save for very complex and bloated websites, like Google Docs. In most cases we just edit the *source code* (e.g. markdown), which is then converted into hypertext on demand. That should hint at the complexity involved in the task.

Word processors we all know, I bet no user really understands:
- What will happen on Tab key press?

  <img width=500 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-tab-key.gif />
  
- How will right-aligned numbered paragraph look like with nonzero indentation?

  <img width=500 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-right-aligned.gif />
  
- What if line contains more whitespace that can fit the screen?

  <img width=500 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-long-line.gif />
  
- Is it possible select whole first row of a grid and only a half of second row? Or part of the 1x1 cell and part of the 2x1 cell?

  <img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-table-select.gif />

- If part of the grid is copied, how is it inserted inside and outside the grid?
- 
  <img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-table-insert.gif />

These are just a few examples of implementation edge cases, but any implementation has to consider them.


## Mixing text and spaces

First problem is how to insert spaces (widgets) into text. Red can only display *text* with its Rich Text dialect (RTD), as far as I can tell, because the text API subset is portable. It shouldn't be too hard to interleave text with widgets, or should it?

This task presents a few challenges:

1. Wrapping (at line margin).

   Consider [hyperlink text](#) or `a span of code`. These are space objects. They treat themselves as boxes (certain offset and size), and they must be styled easily as such boxes. To draw an outline we should just write `box 0x0 size rounding` and call it a day.
   
   How can we draw them in multiple lines and preserve the simplicity of the box model? And also abstract the wrapping so the space itself won't even know it's being wrapped, while still receiving pointer events on it as if it was a box?
   
   `paragraph` layout cannot leverage native wrapping of RTD as that would account for characters only. It may need to start text at x=200, wrap it at x=300 and continue from x=0. Only text size metric of RTD is of use here (to ask it "how much text fits into 100 px?" offset-to-caret calculation can be used). So wrapping has to be done manually.

2. Indentation.

   *Left, right, center* alignments are somewhat straightforward: fill a row, measure it and align within total size. But when indentation of 1st and 2nd line differs, what is the condition when we stop adding words to the 1st line and start adding to the 2nd?
   
   Sometimes leading whitespace affects the result:
   
   <img width=150 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-leading-space.gif />
   
3. Stretching.

   The *fill* alignment complicates everything.
   
   Suppose I have "a few words of text" that fit in a row, so I have 4 whitespace regions (between 5 words) that I need to expand uniformly. Simple Draw-level scaling works up to 110% max, then the text becomes too distorted, so that trick doesn't work. Now what if I want this text to become a link? I create a `rich-content`, put it into a `clickable` space, and insert as a single item. How should `clickable` container now tell me where the whitespace is within it?
   
   If a code span (or a focused link) has an outline, and contains whitespace from the fill alignment, how to not interrupt the outline with the inserted whitespace?

4. Uniqueness.

   Spaces tree consists of unique objects only (see [the other card](single-vs-multiple-parents.md) why), they can't appear twice or more. So it's not possible to put the *same* hyperlink space in row 1, then again in row 2 and in all other rows it spans. Even if it was technically possible, iteration (think tabbing) would treat them as different objects and it would be possible to tab around between parts of the link, which would lead the user to believe they're different links.
   
5. Vertical alignment.

   Text glyphs are drawn above a certain baseline. If we don't take it into account, we may end up with something like this:
   
   <img width=100 src=https://camo.githubusercontent.com/7f13cec707d1a633a6c4a10eef3bf7fee794c0d0e0db11f8c7f9661a73c5cae4/68747470733a2f2f692e6779617a6f2e636f6d2f39326362626633356661643734313134646536383338363730363432313437342e706e67 /> 

6. Coordinate mapping.

   We need to be able to map click/over event coordinates in the paragraph into coordinates in individual spaces. Even trickier, click on a whitespace inserted by fill alignment must lead back to a space character, and click on indentation region - point us to the offset where space is split into rows.
   
   Also we need to map integer caret offsets into planar boxes that we can draw.
   
   If a click lands between two spaces, the term "closest" space may be thought of either as linear or planar metric. 
   
7. Selection.

   Single selection can span multiple rows of varying height, across character and space slots, and yet we should be able to style it as just a box.

The model that meets these challenges includes as much as 3 coordinate spaces (isn't it what Spaces project is all about? ;):
- The **1D (original)** space is how each space object sees itself - as a contiguous box. Together all spaces (including text ones) form a single horizontal tight row. Total 1D width equals sum of all widths of spaces within it, and height equals that of tallest space. The `map` facet or `rich-paragraph` is expressed in this CS.
- The **1D' (unrolled 2D)** space is a transition between 1D and 2D - same horizontal row but with all the indentation, inter-row whitespace from row alignment, and inter-word whitespace from the fill alignment. Think of it as all 2D rows concatenated with the first row. Total 1D' width is never less than 1D width, height equals that of 1D height. Some X points in 1D may map to a whole segment of 1D' space (e.g. indentation regions). On this CS it is easy to tell where a click on the indentation ends up - between which space objects.
- The **2D (rolled)** space is how it is all seen on screen: as separate rows, spaced with given `spacing` value. These rows have different height, accomodating the tallest item within the row. Some 1D' X points (those at row edges) map onto totally different 2D points - to the right of the row above and to the left of the row below. This CS is accepted by `into` function and is produced by `caret->box`.

So a paragraph unifies 3 coordinate spaces and translates between 1D (map, children) and 2D (draw, parents, paragraph's own size).

Rendering phase (including splitting at row and word margins) combines clipping (to isolate rows or words) and scaling (of whitespace in fill mode, to avoid interruption of possible outline).

Here's an illustration of how paragraph model performs in practice when containers can pass along section data from their children:

<img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/example-rich-content-fill-alignment.gif />

## Data representation

How should hypertext data internally be organized?

### Tree

At first glance, Spaces already hierarchically form a **tree**, so it would have been easiest to reuse the tree structure. Piece of cake, until we consider:
1. Editability: text and object insertion, caret movement.

   It's easy to insert characters into text spaces. But what do with the text space if it becomes empty?
   
   And where to insert other spaces? Easiest for lists, but not every tree element is a list. Rules of tree transformation can get quite complex.
   
2. Copying/pasting.

   Suppose we can define rules to extract a branch of the tree. But how to insert it? If we insert a paragraph A right before the paragraph B, do we insert it before B or into B? And it gets more complex with bigger tree depth changes at any given caret location.
   
   And what the extracted part looks like? Is it a copy of spaces tree or serialized somehow?
    
3. Undoing/redoing.

   If we directly modify the tree, we need a way to encode any action and its reverse for every space that can appear in the document.
   

I even think that all of this is possible to achieve, but complexity of this solution would be immense.

Maybe we could serialize the tree into a some proper format, work on this format, then deserialize back into a tree?

People invented general markup languages (SGML, HTML, XML) long ago for a similar case. After some consideration of this option I have come to the following conclusions:
- Markup languages make it easy to extract text from the tree: just remove tags, trim, and it's done. This is why every browser allows to select text on the page and then copy it (as plain text) into clipboard.
- They *don't* make it easy to insert text. Copied subtree would include tags, some of which may not be closed or opened inside the copied range. Inserting such structured data at an arbitrary point in the source would lead to a mess and a massive effort to fix it after such insertion.
- This would involve all the complexity of reading and generating such a format. If I learned anything from interacting with web, it's that this should be a last resort solution.

What about using Red native data formats for the tree? VID/S is basically already such tree structure, so can be reused. But even if VID/S was simplified enough for ease of algorithmic modification, I don't see any significant benefits of this over direct space tree modification. All challenges still stand, it just becomes more readable in a serialized form.

So tree representation is a dead end when the aformentioned 3 challenges are considered. No wonder our browsers can do nothing more than copy text from the pages. *Their data format defines their limits.*

### List

But document can also be **flat**. Omitting implementation details, every 'character' can be either a text glyph or a space object, and it can be attached some attributes (like bold, italic, etc). If we look at nested list levels in the document, on paper and screen they are not nested, they only vary by their indentation. Paragraph splits can be denoted by a newline char.

Key difference between flat and tree models can be illustrated using selection with e.g. a grid object:
- In the tree model, selection can start outside of the grid, and end within one of its cells. Ideally such selection should be copied and inserted as a subtree, but I never saw it implemented by anyone. Caret offsets can span whole tree.

  <img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-browser-table-select.gif />
  
- In the flat model, if selection starts outside of the grid, it can only include grid as a whole. And whole grid can be inserted anywhere, including one of grid cells. Caret offset within the cell does not belong to the outside document, but to a separate one.

  <img width=400 src=https://codeberg.org/hiiamboris/media/raw/branch/master/spaces/demo-gdocs-table-select.gif />
  
It's an interesting distinction that can be seen in how selection works in browsers vs how it works in word processors. Former work on the tree, latter use the flat model.

Flat model is trivial to edit, as long as we are able to represent the data in a simple way. Characters do not constitute any problem, but how do we work with space *objects* and text *attributes*?

For *space objects*, if sameness is preserved it can get us across undo/redo cycles, but when we copy something and paste into multiple places, we have to:
- convert spaces (active object) into data (passive object) in the clipboard, so any further modification of the object won't affect the clipboard contents
- convert clipped data back into spaces on insertion, and ensure modification of the inserted spaces does not modify the data on the clipboard
- ensure every newly inserted space objects are never the same, as tree can only support unique objects, and we want to interact with each individually anyway, rather than edit one and see changes appear on all others

I had to reserve `clone` facet in all spaces for the purpose of converting them into 'passive' objects. It produces a space of the same type with all data (e.g. text, margins) deeply copied and state (e.g. caret, selection) discarded. And also to be able to insert the data into other programs, I reserved `format` facet that converts space into formatted plain text. Only spaces that define both facets can be copied and pasted.

*Attributes* representation is also not trivial. We need to attach (possibly quite big) attribute set to each character. Sameness doesn't work, because we want to be able to modify attributes of arbitrary ranges. We could copy them on modification, but multiple modifications then would lead to more and more copies. In the worst case scenario - some macro or script operating on a document - this could eat all available RAM pretty soon.

I've tried to keep attributes separate from text in maps with vectors, binaries, strings, but scratched all these models, as they were unwieldy and led to bugs, esp. when multiple undo operations needed to be grouped.

What I ended with is a global catalog of all attribute combinations that ever appeared in the documents. Normally their number should not exceed a few dozens, but in the worst case it could be equal the number of characters in the text (e.g. some rainbow colored text), which is an unlikely occurrence but still manageable even for a text of 1M chars.

Data then can be represented as simple `[char attr ...]` paired list, where `char` is a character or space object and `attr` is an integer index of the attribute combination for this `char`. Getting the block from integer index is trivial, and to convert a block back to an integer, block is molded and hashed with SHA1. SHA1 data is then also hashed by the `hash!` datatype, allowing O(1) lookups, with the slowest operation being `mold`. This assumes that `mold/all` produces unique output for every sorted attribute set, which holds true if attributes can only carry data (strings, numbers, none value), not code (bound words, objects).

This format is used by `rich-content` template, while `document` just carries a list of `rich-content` paragraphs. I decided against putting all of `rich-content` data into a single array in a `document`, because that would put limit on the speed of every character insertion/removal, esp. at the head of a big document. We'll at least need some tree-based series datatype to make this and a few other aspects of the document scalable to bigger texts, and likely `slice!` datatype to put parts of the document into it's paragraphs as data.

### Clipboard

How this data can be stashed and handed over to other programs?

Red native clipboard implementation can only carry text, images and file lists, and only text is implemented on every platform.

From what I read about Windows clipboard, it was a mess and remained a mess. Every program seems to define its own clipboard format only it is able to read. Somehow I am able to copy formatted text from a native word processor and insert it into Google Docs (I suggest it used RTF clipboard format), but even that is a pathetic failure:

<img width=400 src=demo-clipboard-formatted.gif />

It copied bold and italic flags but totally lost font face and size. Hello from 2023, ancestors 🖐🛸. Sixty years after hypertext invention we're still unable to move it between programs. Let's wait another 60 and see.

For now, until Red can at least hold rich text data in the clipboard, I've implemented it to hold in parallel: rich text inside Red process RAM, plain text inside OS clipboard. If it detects plain text was changed from what it remembers, it discards the rich text part and uses just the text.
Even when Red implements such format, the question will remain how to put space objects into it without losing information, and whether we can carry objects into other Red apps or other incompatible programs.

One more quirk is that `[char attr ...]` format isn't enough: it doesn't carry paragraph alignment, so I had to implement two formats: `rich-text-span!` holds a (flat) slice of hypertext, and `rich-text-block!` holds whole paragraphs with hypertext within them.

## Timelines

Since I'm using flat data model, if I want e.g. to edit cells in a grid, each cell has to become a separate document. But undo/redo keys should work across them all.

For this, Spaces provide a `timeline!` object that holds series of events and position in it. Each event contains a link to the space object associated with it, code to undo it and code to perform it. Such timeline can be shared across multiple documents, and events will know where to evaluate, no matter who triggers them.
 