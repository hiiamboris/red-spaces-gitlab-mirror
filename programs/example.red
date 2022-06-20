Red [
	title:   "Demo script for Red Inspector"
	author:  @hiiamboris
	license: 'BSD-3
]

example-func: function [message [string!]] [
	lorem: {Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.}
	image: draw 1000x1000 [
		scale 10 10 fill-pen linear blue green 0x0 100x100 circle 50x50 49
	]
	color-map: make map! map-each/eval/drop [w c [tuple!]] to [] system/words [[w c]]
	obj: object [block: [a b c d e]]
	
	;; suppose this is where error appears
	;; call inspect to observe the system state!
	; inspect lorem
	inspect example-func
]

example-func "Hello from Mr. Inspector"
; inspect system
