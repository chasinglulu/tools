#!/bin/sh

# For Heavy CPU Ratio.
while true; do /bin/dd if=/dev/zero of=bigfile bs=1024000 count=1024; done &
while true
do
	/userdata/hackbench -f 20 -g 10 -l 100 &
	count=$(ps | grep hackbench | wc -l)
	echo "$count"
	if [ "$count" -gt 1000 ]
	then
		sleep 1
	fi
done
