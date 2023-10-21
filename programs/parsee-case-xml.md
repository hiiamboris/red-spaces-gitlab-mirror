# ParSEE case study: XML decoder fails on a simple SVG file

### Problem

I needed to decode some SVGs, and used the `XML-codec` branch from [this PR](https://github.com/red/red/pull/5026) at commit [f9efb78](https://github.com/red/red/commit/f9efb7852f22c1745aeb770161ddffc056d25d03) (last commit at the moment). There was a couple of similar issues with it, with one presented below.

On a simple `rects.svg` file the decoder failed:
```
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN" "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd"> 
  
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"   id="drawrects-structure-image-BE-06"  viewBox="0 0 450 450" width="450" height="450" >

 <g id="drawRects">  
 	<rect x="225" y="0" width="225" height="225"  style="fill:red" />
 	<rect x="0" y="225" width="225" height="225"  style="fill:yellow" />
 </g>
</svg>
```

### Classic solution

It normally takes about half an hour to figure out what happens in such complicated code. Roughly it goes like this...

1. Figure out what's the 'main' rule, the entry point. Thankfully pretty simple, just look for `parse` call, there's [just one in the decoder](https://github.com/red/red/blob/f9efb7852f22c1745aeb770161ddffc056d25d03/environment/codecs/XML.red#L130C4-L130C9):

   ```
   	result: either trace? [
   		parse-trace data document
   	] [
   		parse data document
   	]
   ```

2. I find the [`document`](https://github.com/red/red/blob/f9efb7852f22c1745aeb770161ddffc056d25d03/environment/codecs/XML.red#L175-L178) rule and insert `p: (? p)` after each sub-rule (`prolog` and `element`)

   ```
   	document: [
   		opt prolog
   		element
   	]
   ```
   
3. Try to decode my data and count the number of `p: ...` printed, to figure out where it's stuck
4. Go on with this boring routine deeply into subrules, printing the trace after every change, until I find the last rule that should have succeeded but instead failed
5. In this case I find culprit to be [`PubidLiteral`](https://github.com/red/red/blob/f9efb7852f22c1745aeb770161ddffc056d25d03/environment/codecs/XML.red#L220-L223)

   ```
   	PubidLiteral: [
   		dq any PubidChar dq
   	|	sq any [not sq PubidChar] sq
   	]
   ```
   
6. By matching input `"-//W3C//DTD SVG 1.0//EN"` with the actual [charset of `PubidChar`](https://github.com/red/red/blob/f9efb7852f22c1745aeb770161ddffc056d25d03/environment/codecs/XML.red#L224-L226) I can notice that digits aren't there:

   ```
   	PubidChar: charset reduce [
   		space cr lf #"a" '- #"z" #"A" '- #"Z" {-'()+,./:=?;!*#@$_%}
   	]
   ```

So that must be the issue.

### ParSEE solution

Only a matter of getting the progress log and then inspecting it:

1. Include ParSEE from the top of `XML.red` codec:

   ```
   #include %parsee.red
   ```

2. Change [`parse`](https://github.com/red/red/blob/f9efb7852f22c1745aeb770161ddffc056d25d03/environment/codecs/XML.red#L130C4-L130C9) call to a `parsee` one (one extra `e`):

   ```
   	result: either trace? [
   		parse-trace data document
   	] [
   		parsee data document
   	]
   ```

3. Try to decode my data, which brings up the progress inspection window where I can see what happened:

   ![](https://link.storjshare.io/raw/jwtiabvp6myahg3zzf3q5zoii7la/gif/spaces/demo-parsee-case-xml.gif)
   
   In just a minute I know that:
   - it didn't succeed past the `<xml>` header
   - it failed in the `ExternalID` string after `"PUBLIC"`
   - it didn't accept the `3` digit with `PubidChar`

So the [solution](https://github.com/hiiamboris/red/commit/4f24fdd272844e77edcc89c46c1a06653486bee2) is easy:
```
	PubidChar: charset reduce [
-		space cr lf #"a" '- #"z" #"A" '- #"Z" {-'()+,./:=?;!*#@$_%}
+		space cr lf #"a" '- #"z" #"A" '- #"Z" #"0" '- #"9" {-'()+,./:=?;!*#@$_%}
	]
```
	