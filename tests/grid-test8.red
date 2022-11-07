Red [
	title:   "Table test script"
	author:  @hiiamboris
	license: BSD-3
	needs:   view
]

; #do [disable-space-cache?: yes]
#include %../everything.red

declare-template 'zoomer/box [
	zoom: [x: 1.0 y: 1.0]
	;; replaces host/size to exclude face resizing from workflow, which allows for better responsiveness
	canvas: 0x0		#type =? :spaces/ctx/invalidates  
	; draw: function [/on canvas [pair! none!]] [
	draw: function [] [
		canvas': as-pair
			clip (negate infxinf/x) infxinf/x canvas/x / zoom/x
			clip (negate infxinf/y) infxinf/y canvas/y / zoom/y
		drawn: render/on content canvas'
		size:  content/size
		maybe self/size: as-pair
			size/x * zoom/x
			size/y * zoom/y
		compose/deep/only [
			matrix [(zoom/x) 0 0 (zoom/y) 0 0]
			(drawn)
		]
	]
]

pic: draw 50x50 [box 1x1 49x49 rotate -40 25x25 text 7x14 "picture"]
pics: reduce [pic pic pic pic pic pic pic]
	
data-source: compose/deep/only [
	[
		1
		; Lorem ipsum"
		"Loremipsum loremipsum"
		"Nam nec convallis purus"
		"C u r a b i t u r   u r n a   m a u r i s ,   f a c i l i s i s   u t   s c e l e r i s q u e   v i v e r r a ,   f a c i l i s i s   n e c   n u n c"
		; (pics)
		; (reduce [pic "C u r a b i t u r   u r n a   m a u r i s ,   f a c i l i s i s   u t   s c e l e r i s q u e   v i v e r r a ,   f a c i l i s i s   n e c   n u n c"])
	]
	[
		2
		; "Nulla"
		"Nulla nulla nulla"
		; "Sedvehiculasapienetconsecteturvulputateturpis ipsum Sedvehiculasapienetconsecteturvulputateturpis ipsum Sedvehiculasapienetconsecteturvulputateturpis ipsum Sedvehiculasapienetconsecteturvulputateturpis ipsum Sedvehiculasapienetconsecteturvulputateturpis ipsum"
		"Sed vehicula, sapien et consectetur vulputate, turpis ipsum viverra sem, in efficitur quam erat sit amet ligula"
		; "Sed vehicula, sapien et consectetur vulputate, turpis ipsum viverra sem, in efficitur quam erat sit amet ligula Sed vehicula, sapien et consectetur vulputate, turpis ipsum viverra sem, in efficitur quam erat sit amet ligula"
		; "Sedvehiculasapienetconsecteturvulputateturpis ipsum"
		; "Sedvehiculasapienetconsecteturvulputateturpis I n   p o s u e r e   p l a c e r a t   m a x i m u s"
		; "S e d   v e h i c u l a   s a p i e n e t   c o n s e c t e t u r   v u l p u t a t e   t u r p i s .   I n   p o s u e r e   p l a c e r a t   m a x i m u s"
		"S e d   v e h i c u l a   s a p i e n e t   c o n s e c t e t u r   v u l p u t a t e   t u r p i s .   I n   p o s u e r e   p l a c e r a t   m a x i m u s .   S e d   v e h i c u l a   s a p i e n e t   c o n s e c t e t u r   v u l p u t a t e   t u r p i s .   I n   p o s u e r e   p l a c e r a t   m a x i m u s"
		; "Sed vehicula sapienet consectetur vulputate turpis I n   p o s u e r e   p l a c e r a t   m a x i m u s Sed vehicula sapienet consectetur vulputate turpis I n   p o s u e r e   p l a c e r a t   m a x i m u s"
		; (pics)
		; (reduce [pic "Sed vehicula sapienet consectetur vulputate turpis I n   p o s u e r e   p l a c e r a t   m a x i m u s Sed vehicula sapienet consectetur vulputate turpis I n   p o s u e r e   p l a c e r a t   m a x i m u s"])
	]
	[
		3
		"Cras et"
		"Duis ac ex quis nisi tristique placerat quis eu magna"
		"V e s t i b u l u m   a u c t o r   u r n a   f a c i l i s i s   e n i m   s a g i t t i s ,   v e l   u l l a m c o r p e r   e n i m   v e n e n a t i s"
		; (pics)
		; (reduce [pic "V e s t i b u l u m   a u c t o r   u r n a   f a c i l i s i s   e n i m   s a g i t t i s ,   v e l   u l l a m c o r p e r   e n i m   v e n e n a t i s"])
	]
]

compare: [width-difference width-total area-total area-difference]
; compare: [width-difference width-total]
; compare: [width-total area-total]
; compare: [area-total area-difference]

system/view/auto-sync?: off
view/no-wait/options/flags reshape [
	origin 20x20
	below
	host: host with [size: system/view/screens/1/size - 54x120] [
		zoo: zoomer with [zoom: [x 0.5 y 0.5] canvas: host/size - 40] [
			column [
				row !(
					map-each method compare [
						compose/deep [box [text (form method) with [font: make font! [size: 20]]]]
					]
				)
				row weight= 1 /use (
					map-each method compare [
						compose/deep [
							grid-view content-flow= 'vertical source= data-source
							with [grid/autofit: quote (method)]
						]
					]
				)
			]
		]
	]
	block: base brick 20x20 loose react later [
		zoo/canvas: face/offset - host/offset
		;; render immediately, not waiting for the timer - to reduce the visible lag:
		host/draw: render host
		if host/parent [show host/parent]
	]
	do [block/offset: host/size + 20]
][
	offset: 0x0
] 'resize

; spaces/ctx/grid-ctx/autofit gv/grid 200
; b/dirty?: yes
			
; dump-tree
either system/build/config/gui-console? [print "---"][do-events]
prof/show

