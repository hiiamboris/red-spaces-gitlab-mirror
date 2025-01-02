Red [
	title:    "Support for key combos to use in VID/S and editable spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.keys
	depends:  [map-each]
] 

named-keys: #[
	;; note on all named keys: they cannot include a '+' in their name, as it's a modifier-adding delimiter 

	;; named platform-agnostic actions - constitute multiple options - cannot have modifiers
	;@@ should make this a platform-aware switch, e.g. Mac should use Command key or how it's represented in Red
	;@@ ideally also OS language-aware (requires L10N), or keyboard layout-aware (too complicated)
	;; useful source: http://web.archive.org/web/20240729092911/https://doc.qt.io/qt-5/qkeysequence.html#keyboard-layout-issues
	;; typical hotkeys: http://web.archive.org/web/20240729092911/https://doc.qt.io/qt-5/qkeysequence.html#standard-shortcuts
	@Copy		[@Ctrl+C @Ctrl+Insert]
	@Cut		[@Ctrl+X @Shift+Delete]
	@Paste		[@Ctrl+V @Shift+Insert]
	@Undo		[@Ctrl+Z]
	@Redo		[@Ctrl+Y @Ctrl+Shift+Z]
	@SelectAll	[@Ctrl+A]
	@Print		[@Ctrl+P]
	@Find		[@Ctrl+F]
	@FindNext	[@Ctrl+G @F3]
	@Replace	[@Ctrl+H]
	@Bold		[@Ctrl+B]
	@Italic		[@Ctrl+I]
	@Underline	[@Ctrl+U]
	@New		[@Ctrl+N]
	@Open		[@Ctrl+O]
	@Save		[@Ctrl+S]
	@Close		[@Ctrl+W]
	@Quit		[@Ctrl+Q]
	@ZoomIn		[@Ctrl+Plus]
	@ZoomOut	[@Ctrl+Minus]
	;@@ add Ctrl+Home/Ctrl+End here? any other keys? no expert in shortcuts :/

	;; modifiers; can be combined with all of the below keys
	@Alt		alt										;@@ does Mac Red map Command to 'alt'?
	@Control	control
	@Ctrl		control
	@Shift		shift
	; "Win"		command									;@@ not supported by Red as modifier, besides mostly intercepted by the OS
	
	;; named keys - no letter code
	@Left		left
	@Right		right
	@Up			up
	@Down		down
	@Home		home
	@End		end
	@PageUp		page-up
	@PgUp		page-up
	@PageDown	page-down
	@PgDn		page-down
	@Insert		insert
	@Ins		insert
	@Delete		delete
	@Del		delete
	@Pause		pause
	@Menu		menu
	@F1			F1
	@F2			F2
	@F3			F3
	@F4			F4
	@F5			F5
	@F6			F6
	@F7			F7
	@F8			F8
	@F9			F9
	@F10		F10
	@F11		F11
	@F12		F12
	@F13		F13
	@F14		F14
	@F15		F15
	@F16		F16
	@F17		F17
	@F18		F18
	@F19		F19
	@F20		F20
	@F21		F21
	@F22		F22
	@F23		F23
	@F24		F24
	
	;; named keys - esoteric letter code
	@Esc		#"^["
	@Enter		#"^M"
	@Tab		#"^-"
	@Space		#" "
	@Backspace	#"^H"									;@@ add a 'BS' alias?
	; "Center"	#"^L"									;@@ buggy - see #5525; need Red to name it first, then Spaces will inherit the name
	
	;; named keys - single letters (some may be typed as is, but have named aliases for readability)
	@Plus			#"+"								;-- used as a delimiter, so much better to name it
	@Minus			#"-"								;-- to be on par with +
	@Asterisk		#"*"
	@Equals			#"="								;-- not supported by ref! lexing
	@Slash			#"/"
	@Backslash		#"\"								;-- not supported by ref! lexing
	@Comma			#","								;-- not supported by ref! lexing
	@Quote			#"'"								;-- not supported by ref! lexing
	@DoubleQuote	#"^""								;-- not supported by ref! lexing
	@Semicolon		#";"								;-- not supported by ref! lexing
	@Colon			#":"
	@Period			#"."
	@Lesser			#"<"								;-- not supported by ref! lexing
	@Greater		#">"								;-- not supported by ref! lexing
	@LeftBracket	#"["								;-- not supported by ref! lexing
	@RightBracket	#"]"								;-- not supported by ref! lexing
	@LeftParen		#"["								;-- not supported by ref! lexing
	@RightParen		#"]"								;-- not supported by ref! lexing
	@LeftBrace		#"{"								;-- not supported by ref! lexing
	@RightBrace		#"}"								;-- not supported by ref! lexing
	
	;; unnamed keys are distinguished by being a single letter: A-Z, 1-9 and other symbols
]


;; input to 'decode-key-combo' is user-friendly ref from the above map
;; output is either block of words (single combo) or block of blocks of words (multiple combos)
decode-key-combo: function [
	"Decode VID/S key shortcut into Red-compatible key combo blocks"
	combo   [ref!] "E.g. @Ctrl+Alt+Del"
	return: [block!] {E.g. [[control alt delete]] or [[control #"c"] [shift insert]]}
	/local key
][
	either block? list: named-keys/:combo [						;-- a list of alternatives?
		map-each ref list [decode-key-combo ref]
	][
		=fail=: [(ERROR "Unsupported key '(key)' in key combo @(combo)")]
		=key=:  [keep copy key [skip any [not #"+" skip]]]
		keys: parse combo [collect [=key= any ["+" =key=]] [end | =fail=]]
		keys: map-each key keys [
			any [
				named-keys/:key
				if single? key [lowercase first key]			;@@ doesn't support path access `key/1`, hence 'first'
				do =fail=
			]
		]
		reduce [keys]
	]
]

;@@ should '+' be added between keys?
#assert [
	[[control alt delete]] == decode-key-combo @Ctrl+Alt+Del
	[[control alt delete]] == decode-key-combo @Control+Alt+Del
	[[alt shift #"+"	]] == decode-key-combo @Alt+Shift++
	[[alt shift #"+"	]] == decode-key-combo @Alt+Shift+Plus
	[[shift #"^["		]] == decode-key-combo @Shift+Esc
	[[alt #"x"			]] == decode-key-combo @Alt+X
	[[#"x"				]] == decode-key-combo @X
	[[#"+"				]] == decode-key-combo @+
	error?				try  [decode-key-combo @++]
	error?				try  [decode-key-combo @Ctrl+]
	[[control #"c"] [control insert]] = decode-key-combo @Copy	;-- resolves to multiple alternatives
]
