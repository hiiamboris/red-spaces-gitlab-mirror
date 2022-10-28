Red []

either empty? system/options/args [
	do %everything.red
][
	do to-red-file system/options/args/1
]

print "--== Spaces Console ==--^/"
system/console/run/no-banner quit
	
