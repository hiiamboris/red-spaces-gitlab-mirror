# ParSEE case study: CSV decoder processes the same part of input twice

| NOTE | ParSEE wasn't designed for this use case, and at the moment won't help identify O(n^2) rules, e.g. `[any [not to target skip]]` |
|-|-|

| NOTE | At the moment this feature doesn't work on GTK backend due a to platform [discrepancy](https://github.com/red/red/issues/5410) in RTD |
|-|-|

Double processing incurs additional time cost and should be avoided in codecs. Some cases of such double processing are directly visible in the UI of ParSEE, and can help to improve the code.

Here's an example from CSV codec:

<img width=700 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-case-csv.gif />

As can be seen, `single-value` rule matches the last value in every line, then its parent rule fails as it doesn't see a delimiter (comma) ahead, and `line-rule` lets `single-value` match again, which is likely not by design.
   
	