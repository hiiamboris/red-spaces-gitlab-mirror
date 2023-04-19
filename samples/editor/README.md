## [Document editor](document-editor.red)

While builtin [`editor`](../../reference.md#editor) widget provides basic document editing functionality (like typing, selection, undo/redo), it lacks higher level tools that together make a rich text editor (e.g. chaging text formatting, alignment, inserting widgets).

Editor sample includes such higher level tooling and also allows me to test how editor widget behaves in advanced usage scenarios.

It implements all features needed to build your own **word processor**, but can also be handy in many other **applications**:
- as a Draw-based `area` widget (main goal of the implementation)
- to type rich text in *chat clients*
- to compose *emails and forum messages*
- for *note-taking apps*
- to edit *wiki pages or math sheets*
- to write *documentation* for your own program

Structurally, [editor](../../reference.md#editor) is a scrollable wrapper around [document](../../reference.md#document) which itself is a vertical [list](../../reference#list) of [rich-content](../../reference.md#rich-content) spaces that each represent a paragraph.

A paragraph can *include any other space*, though only those spaces that define the /clone facet can be copied and pasted (a very limited set currently).

Paragraph supports all basic text formatting attributes, colors, font face and font size, alignment, indentation,
but its *real magic* lies in the **ability to wrap** any included space that defines the /sections facet, and its **ability to stretch** any such space when *fill alignment* is used.

<img width=600 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/example-rich-content-fill-alignment.gif></img>

Document provides some basic automation, like handling of keys and attribute inherence for new chars. Yet the trickiest feature of it is **undo/redo** history that gracefully handles rich text with spaces! Even trickier: document may contain other documents (e.g. each cell of an inserted table is a separate editor), and they are all linked by the same edit history, so pressing Ctrl+Z in a cell may undo an edit in the main document and vice versa.

<img width=600 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/sample-document-editor.gif></img>


