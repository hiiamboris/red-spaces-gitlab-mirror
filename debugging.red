Red [
	title:    "Simple debug helpers for Spaces"
	author:   @hiiamboris
	license:  BSD-3
	provides: spaces.debugging
	depends:  [global map-each]
]


dump-event: function [event [event!]] [							;-- should not be used for map!-type event
	event: object map-each/eval w system/catalog/accessors/event! [
		[to set-word! w 'quote event/:w]
	]
	help event
]

dump-tree: function [
	"List hierarchical tree of currently rendered faces & spaces"
	/from host [object!] "Root face to list from (by default - the screen)" (host? host)
][
	foreach-*ace *ace: any [host system/view/screens/1] [
		probe as path! get-full-path *ace
	]
	exit
]

global dorc: does [do read-clipboard]

color-names: make map! map-each/eval [name value [tuple!]] to [] system/words [[value to word! name]]
color-name: function [color [tuple! none!]] [			;-- used for debug output to easier identify spaces
	any [
		select color-names color 
		color
		'colorless
	]
]

space-id: function [[no-trace] space [object!]] [		;-- used to identify spaces in debug sessions
	#composite "(color-name select space/config 'color) (space/type):(select space/frames/last 'size)"	
]


; add-indent: function [text [string!] size [integer!]] [
	; indent: append/dup clear "" #" " size
	; parse text [any [#"^/" not end insert indent (lf?: yes) | skip]]
	; if lf? [insert text indent]
	; text
; ]


; ;@@ TODO: at least 3 canvases: none (and maybe 0x0), half-infinite, and finite; configurable size
; debug-draw: function ["Show GUI to inspect spaces Draw block"] [
	; context [
		; list: code: free: sized: drawn: path: obj: none
		; rea: reactor [canvas?: no]
		; fixed: make font! [name: system/view/fonts/fixed]
		; ;; can't put paths into list-view/data because of face's aggressive ownership system
		; paths: []
		; update: has [i] [
			; clear paths
			; list/data: collect [
				; i: 0
				; foreach-*ace obj: system/view/screens/1 [
					; append/only paths path: get-screen-path obj
					; keep reduce [mold path i: i + 1]
				; ]
			; ]
		; ]
		; view/no-wait/options [
			; below list: text-list focus 400x400 on-created [update]
			; panel 2 [
				; origin 0x0 space 10x-5
				; text 195 "w/o canvas" text "with canvas"
				; free:  box 195x170 on-up [rea/canvas?: no] 
					; react [face/color: do pick [white silver] not rea/canvas?]
				; sized: box 195x170 on-up [rea/canvas?: yes]
					; react [face/color: do pick [white silver] rea/canvas?]
			; ] return
			; code: area 400x600 font fixed react [
				; face/text: either any [
					; not list/selected
					; not path: pick paths list/selected
				; ][
					; "Select a space in the list"
				; ][
					; either face? obj: last path [
						; sized/draw: none
						; either free/draw: drawn: obj/draw [
							; mold prettify/draw drawn
						; ][
							; "Face has no Draw block!"
						; ]
					; ][
						; drawn: reduce [
							; free/draw:  render    last path
							; sized/draw: render/on last path to point2D! sized/size yes yes
						; ]
						; mold prettify/draw pick drawn not rea/canvas?
					; ]
				; ] 
			; ]
			; at 350x10 button "Update" [update]
		; ][
			; actors: object [
				; on-created: func [face] [
					; face/offset: face/parent/size - face/size * 1x0
					; foreach other face/parent/pane [
						; unless other =? face [
							; other/offset/x: face/offset/x - other/size/x - 5
							; break
						; ]
					; ]
				; ]
			; ]
		; ]
	; ]
; ]
