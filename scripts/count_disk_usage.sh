#!/bin/bash

USER_NAME=$(compgen -u)
FILENAME="/home/xinlu.wang/disk_all_usage.txt"

if [ -e "$FILENAME" ]
then
	rm -rf "$FILENAME"
fi

for val in $USER_NAME
do
	if [ -d "/home/$val" ]
	then
		ID=$(id -u $val)
		if [ "$ID" -lt "1000" ]
		then
			continue
		fi
		echo "$val"
		pushd "/home/$val" >/dev/null
		size=$(sudo du -sh | awk '{print $1}')
		echo "@$val $size" >> $FILENAME
	fi
done
