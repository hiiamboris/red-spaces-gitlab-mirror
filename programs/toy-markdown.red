Red [
	title:       "Toy markdown-to-VID/S converter"
	description: "All I could bother to implement for now"
	author:      @hiiamboris
	license:     BSD-3
]

#include %../../common/tabs.red

context [
	join: function [lines [block!]] [
		to string! next map-each/eval line lines [[#"^/" line]] 
	]
	
	space!: charset " ^-"
	white!: charset " ^-^/^M"
	alpha!: charset [#"a" - #"z" #"A" - #"Z"]
	digit!: charset [#"0" - #"9"]
	non-space!:   negate space!
	non-white!:   negate white!
	non-bracket!: negate charset "\]" 
	non-brace!:   negate charset "\)" 
	non-pipe!:    negate charset "\|" 
	
	;; I chose to negate the scaling for images, else they are too big
	dpi: any [attempt [system/view/metrics/dpi] 96]		;@@ dpi not available on linux - #4740
	scaling: dpi / 96 
	
	;@@ need full list of entities, but it's huge and who's using that junk anyway
	;@@ need also an :emoji: decoder - https://gist.github.com/rxaviers/7360908 
	decode-entity: function [name [string!]] [
		dict: #(
			"lt"    "<"
			"gt"    ">"
			"amp"   "&"
			"nbsp"  " "
			"quot"  {"}
			"apos"  "'"
			"copy"  "©"
			"reg"   "®"
			"deg"   "°"
			"laquo" "«"
			"raquo" "»"
		)
		any [
			select dict name
			rejoin ["&" name ";"]
		]
	]
	
	no-image: draw 70x70 [text 8x20 "image not^/ available"]
	
	;@@ this should support many more inlined html tags
	;@@ inline code should be word-wrapped, so should be part of the text in rich-content
	decode-text: function [text [string!] /local image name link code] [
		list:  make [] 8
		=flush=: [(unless bgn =? end [append list copy/part bgn end]) bgn:]
		parse bgn: text [any [end:
			remove "\" skip
		|	"**"        =flush= (append list either bold:   not bold   ['bold][/bold])
		|	["*" | "_"] =flush= (append list either italic: not italic ['italic][/italic])
		|	[
				["`" copy code to "`" skip]
			|	[<code> copy code to </code> </code>]
			] =flush= (
				append list make-space 'code [text: code]
			)
		|	change ["&" copy name some alpha! ";"] (decode-entity name)	;@@ entity can be numeric too
		|	change <br> "^/"
		|	[
				[
					set image opt "!"
					"[" copy name any [non-bracket! | "\" opt skip] ["]" | end] any space!
					"(" copy link any [non-brace!   | "\" opt skip] [")" | end]
					(width: none)
				]
			|	[
					set image "<img" some space! 1 2 [
						"width=" copy width some digit! any space! (width: to integer! width)
					|	"src=" copy link to [space! | ">"] any space!
					] thru ">" copy name to </img> </img>
				]
			]
			=flush= (
				trim name  trim link
				codec: select #(%.gif gif %.png png %.jpg jpeg %.jpeg jpeg) suffix? link
				either image [
					link: as either find/match link "http" [url!][file!] link
					image: any [
						attempt [
							either url? link [
								load-thru/as link codec			;-- cached ;@@ suffers from #3457
							][
								load/as link codec				;-- no need to cache local files
							]
						]
						no-image
					]
					size: either width [image/size * width / image/size/x][image/size]
					size': min 500x500 size / scaling	;@@ hardcoded size limit is bad
					append list make-space 'image [
						data: image
						limits: 0x0 .. size'
					]
				][
					source: compose [
						color: 50.80.255				;@@ color should be taken from the OS theme, or from link style
						underline
						(decode-text name)
					]
					append list make-space 'clickable compose/deep/only [
						content: make-space 'rich-content [decode (source)]
						command: [browse (as url! link)]
					]
				]
			)
		|	skip
		] end =flush=]
		list
	]
	
	glue-lines: function ["Glue together lines ending with a backslash" lines [block!]] [
		forall lines [
			if #"\" = last lines/1 [
				until [take/last lines/1  #"\" <> last lines/1]
				insert lines: next lines ""
			]
		]
	]
	
	decode-table: function [lines [block!]] [
		aligns: clear []
		=cell=: [
			copy text any [non-pipe! | "\" opt skip] "|"
			keep pick (compose/only [rich-content (decode-text text)])
		]
		=line=: [0 3 space! "|" some =cell= any space! end keep ('return)]
		=align=: [
			;; :-- --- = left, --: = right, :-: = center
			(n: 1)
			any space! [
				opt [":" (n: n + 1)] some "-" opt [":" (n: n + 2)]
				keep (pick [-1x0 -1x0 1x0 0x0] n)
			]
			any space! "|"
		]
		=aligns=: [0 3 space! "|" collect after aligns [some =align=] any space! end]
		content: parse lines [collect [into =line= into =aligns= any [into =line=]] end (ok: yes)]
		compose/deep/only pick [
			;; wrap grid into a scrollable in case it is too wide, to prevent the rest of the text from stretching
			[scrollable [grid pinned= 0x1 alignment= (copy aligns) (content)]]
			[rich-content (decode-text join lines)]		;-- fall back to text if table parsing fails
		] ok = yes
	]
	
	;@@ need to make html table and list decoder
	; decode-block-html: function [text [string!]] [
	; ]
	
	set 'decode-markdown function [
		"Decode markdown lines into VID/S code"
		lines [block!]
		/local line
	][
		or-more: 999
		buffer: clear []
		
		into: func [new] [
			=scope=: get select [
				blank   =blank=
				pre     =pre=
				quote   =quote=
				html    =html=
				grid    =grid=
				break   =break=
				heading =heading=
				numbers =numbers=
				bullets =bullets=
				text    =text=
			] scope: new 
		]
		
		;; this part emits VID/S expressions from parsed data buffer and current scope
		=flush=: [(
			append vid only switch scope [
				pre [compose/deep/only [scrollable [pre (detab/size join buffer 4)]]]
				text numbers [
					compose/only [rich-content (decode-text join buffer)]
				]
				bullets [
					indent: 5
					parse buffer/1 [any [remove 1 3 space! (indent: indent + 15)]]
					compose/deep/only [
						row tight [
							; <-> (indent by 0)			;@@ stupid compiler compiles <-> as something other than word
							stretch (indent by 0)
							rich-content (decode-text join buffer)
						]
					]
				]
				quote [
					compose/deep/only [
						row tight spacing= 5 [
							box 5 (opaque 'text 50%)
							rich-content (decode-text join buffer)
						]
					]
				]
				heading [compose/only [
					rich-content (append copy styling/flags/headings/:level decode-text join buffer)
					font= pick styling/fonts/text (1 + level)
				]]
				break [[thematic-break]]
				grid [decode-table buffer]
				; html [decode-block-html join buffer]
			]
			clear buffer
		)]
		
		=keep=:         [(append buffer line)]
		=blank-line=:   [any space! end =flush= (into 'blank)]
		=pre-line=:     [0 3 #" " "```" =flush= (into either scope = 'pre ['text]['pre])]
		=html-line=:    [0 3 #" " "<" thru ">" =keep= (into 'html)]
		=grid-line=:    [0 3 #" " "|" =keep= (into 'grid)]
		=quote-line=:   [0 3 #" " remove [">" some space!] =flush= =keep= (into 'quote)]
		=break-line=:   [0 3 #" " 3 or-more ["-" | "=" | "*"] any space! end =flush= (into 'break)]
		=heading-line=: [0 3 #" " s: 1 6 #"#" not #"#" e: any space! remove s =flush= =keep= (level: offset? s e) (into 'heading)]
		=number-line=:  [0 3 #" " some digit! #"." space! remove any space! =flush= =keep= (into 'numbers)]
		=bullet-line=:  [0 3 #" " change [["-" | "*"] some space!] "• " =flush= =keep= (into 'bullets)]
		=text-line=:    [0 3 #" " opt [if (not find [text blank grid] scope) =flush=] =keep= (into 'text)]
		=blank=:   [
			=blank-line= | =pre-line= | =quote-line= | =grid-line= | =html-line=
			| =break-line= | =heading-line= | =number-line= | =bullet-line= | =text-line=
		]
		=pre=:     [=pre-line= | =keep=]
		=html=:    [=blank-line= | =keep=]
		=quote=:   [=blank-line= | =keep=]
		=grid=:    [=blank-line= | =grid-line= | =text-line=]
		=heading=: [=blank-line= | =pre-line= | =quote-line= | =heading-line= | =text-line=]
		=break=:   [=blank-line= | =pre-line= | =quote-line= | =heading-line= | =number-line= | =bullet-line= | =text-line=]
		=numbers=: [=blank-line= | =pre-line= | =quote-line= | =heading-line= | =number-line= | =bullet-line= | =break-line= | =keep=]
		=bullets=: [=blank-line= | =pre-line= | =quote-line= | =heading-line= | =number-line= | =bullet-line= | =break-line= | =keep=]
		=text=:    [=blank-line= | =pre-line= | =quote-line= | =heading-line= | =number-line= | =bullet-line= | =break-line= | =keep=]
		
		vid: make [] 8
		glue-lines lines
		into 'blank
		parse lines [any [
			ahead set line skip
			into [=scope= to end]
		] end =flush=]
		vid
	]
]
