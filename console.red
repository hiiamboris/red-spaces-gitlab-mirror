Red []

;; this exploits the hack in debug-helpers for console prompt to accept space-aware paths
;; unfortunately it cannot be done for the general case,
;; as this file has to be included after every other code finishes


either empty? system/options/args [
	do %everything.red
][
	do to-red-file system/options/args/1
]

system/console: make system/console [
	try-do: func [code /local result path][
		set/any 'result try/all/keep [
			either 'halt-request = set/any 'result catch/name [
				parse code [any [
					change only set path any-path! (
						any [
							to path expand-space-path path
							path
						])
				|	skip
				]]
				do probe code
			] 'console [
				print "(halted)"						;-- return an unset value
			][
				:result
			]
		]
		:result
	]
]

system/console/run/no-banner quit
	