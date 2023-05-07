# Extra widgets

This directory contains widgets that I don't want to include into the Spaces core.

They should be included after `%everything.red`.

See the [guide](guide.md) if you'd like to create your own widget. 

---

`document.red` is an advanced template that arranges mixed content paragraphs into a (possibly editable) document:

<img width=800 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/sample-document-editor.gif></img>

---

`requesters.red` contains `request` dialog constructor and the following default requesters:
- `request-color` asks for color using `color-picker.red`, that contains the basic `color-picker` widget (palette, lightness)

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/widget-color-picker.png)

---

`drop-down-lists.red` contains `drop-box` (aka [drop-down list](https://en.wikipedia.org/wiki/Drop-down_list)) and `drop-field` (aka [combo box](https://en.wikipedia.org/wiki/Combo_box)) widgets. They are common on desktop and web, but not on mobile, so I don't want to add them into the core.

| **NOTE** | Before using these please read [this article on better alternatives](https://medium.com/re-write/fuck-dropdowns-6-ways-to-eliminate-dropdowns-from-your-design-83efb8773675) (or see [this long video](https://youtu.be/hcYAHix-riY)). IMO drop-down lists have a place in some cases, e.g. in a toolbar above the text area, where space is precious, but they are abused way too much. |
|-|-|

![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-drop-down-test.gif)

