# A [Grid Editor](grid-edit.red) demo

<img width=500 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-grid-editor.gif></img>

Features:
- columns can be resized by dragging area between column headers (very slow :/)
- columns can be reordered by Alt+dragging column headers
- columns can be shown/hidden from the right-click menu on any column header
- table can be sorted by any column in descending or ascending order using arrow buttons in the column header
- multiple columns can be selected by dragging across column headers or clicking and Ctrl-clicking
- multiple rows can be selected by dragging across row headers or clicking and Ctrl-clicking
- whole grid data can be selected by clicking on the header intersection "#" or by Ctrl+A key combo
- limited 2D area can be selected by dragging from between non-header cells
- cursor navigation across grid using arrow keys (also supports jumps with Ctrl)
- keyboard selection of 2D data area using Shift and arrow keys (including Ctrl+Shift)
- whole rows and columns can be selected with Ctrl+Space and Shift+Space keys, and extended with Shift+arrows 
- cells and headers can be edited with F2 or Enter key press (Enter or Esc to commit)
- headers can be renamed with Ctrl+F2 key combo
- selected rows and columns can be removed with Ctrl+- key combo, new ones prepended with Ctrl++
- copying and pasting using Ctrl+C/Ctrl+V/Ctrl+X/Shift+Ins/Shift+Del standard key combos 
- undo and redo capability using Ctrl+Z/Ctrl+Shift+Z standard key combos
  (currently does not affect cell renaming - should it?)
- big cell content is shown in the tooltip above it
- import and export of data in .red, .csv and .redbin formats (to compress it, also add .gz)
- automatic state saving and restoration when editor is closed and reopened
