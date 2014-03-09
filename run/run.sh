#!/bin/bash

FILES=asms/*.asm

for f in $FILES
do
	echo "---testing ${f} ------"
	cp $f a.asm
    dosbox run.bat -exit >& /dev/null	
	echo ""
done 
