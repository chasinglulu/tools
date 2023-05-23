#!/bin/bash

USER_NAME=$(compgen -u)

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
		if [ "$val" = "xinlu.wang" ]
		then
			continue
		fi
		echo "$val $ID"
		sudo systemctl set-property user-$ID.slice MemoryLimit=5000M BlockIOWeight=512 CPUQuota=40%
	fi
done
sudo systemctl daemon-reload
