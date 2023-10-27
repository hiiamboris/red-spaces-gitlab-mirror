# ParSEE case study: overall evaluation of a decoder (on XML codec's example)

This example shows How ParSEE can be used:
- by the decoder **author**: to quickly evaluate if it is **performing as expected** 
- by a person **unfamiliar** with the decoder but wanting to extend it: to see what **each rule is doing** 

**Watch** the following GIF closely as I oversee rules one by one. Pay attention to:
- **areas** of input **matched** by each rule
- **color overlapping** of the matches

<img width=1000 src=https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-case-evaluation.gif />

In this short session we have discovered:
- input is **valid**, as evidenced by the top level rule being green in the end and consuming all of it
- input **areas matched** by each rule, e.g. `STag`, `ETag`, `CharData`, `S*`, `S+` and so on: good way to spot unexpected or missed matches
- rules `element` and `content` are **recursive**, with former including the latter plus tags
- `Name`, `Attribute`, `AttValue` rules are performing **duplicate matching** as evidenced by twice repeated patterns in rule profiles
- `EmptyElemTag` inside `element` being the most likely **culprit** of the duplicate matching, as it performs full match and then fails and discards the result at the very end (more general cause usually is the direct translation of EBNF grammer to Parse dialect)
 	