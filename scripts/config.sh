#!/usr/bin/env bash

set -x

IS_IN_SUDO=""

function create_user()
{
	echo "$1" # arguments are accessible through $1, $2,...
	USER_NAME=$1
	sudo useradd -m -d /home/${USER_NAME} -s /bin/bash ${USER_NAME}
	if [ -n "${IS_IN_SUDO}" ]
	then
		sudo usermod -a -G sudo ${USER_NAME}
	fi
	echo "${USER_NAME}:${USER_NAME}" | sudo chpasswd

	sudo usermod -a -G video ${USER_NAME}
	sudo usermod -a -G dialout ${USER_NAME}
}

function delete_user () {
	echo "$1" # arguments are accessible through $1, $2,...
	sudo userdel -r $1
}


function samba_setup () {
	echo "$1" # arguments are accessible through $1, $2,...
	username=$1
	passwd=$1

	echo -e "$passwd\n$passwd" | sudo smbpasswd -a -s $username

	sudo chmod 666 /etc/samba/smb.conf
sudo cat >>/etc/samba/smb.conf<<EOF
[$username]
   comment = $username
   browseable = yes
   path = /home/$username/
   public = no
   valid users = $username
   create mask = 644
   directory mask = 755
   force user = $username
   force group = $username
   available = yes
   writable = yes
EOF
	sudo chmod 644 /etc/samba/smb.conf
	sudo systemctl restart smbd.service
}

function remove_samba_config ()
{
	echo "$1" # arguments are accessible through $1, $2,...
	username=$1
	sudo chmod 666 /etc/samba/smb.conf
	line=$(grep "\[$username\]" /etc/samba/smb.conf -n | cut -d : -f 1)
	end=$(($line + 11))
	sudo sed -i "$line,${end}d" /etc/samba/smb.conf
	sudo chmod 644 /etc/samba/smb.conf
	sudo systemctl restart smbd.service
}

function nfs_setup () {
	echo "$1" # arguments are accessible through $1, $2,...
	username=$1
	echo "/home/$username/ *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
	sudo systemctl restart nfs-server.service
	sudo showmount -e localhost | grep $username
}

function remove_nfs_config () {
	echo "$1" # arguments are accessible through $1, $2,...
	username=$1
	line=$(grep "\/home\/$username\/" /etc/exports -n | cut -d : -f 1)
	sudo sed -i "${line}d" /etc/exports
	sudo systemctl restart nfs-server.service
}

function usage()
{
	echo "Usage:"
	echo "$0 [-rd] USER_NAME"
}

if [ $# -lt 1 ]
then
	usage
	exit 0
fi

while getopts :rhd opt
do
	case $opt in
		r)
			IS_IN_SUDO="Yes"
			;;
		d)
			DELETE_USER="Yes"
			;;
		h)
			usage
			exit 0
			;;
		?)
			echo -e "\n[ERROR]$0: invaild option -$OPTARG\n" >&2
			usage
			exit 0
			;;
	esac
done
shift $((OPTIND - 1))

if [ -n "$1" ]
then
	if [ -n "$DELETE_USER" ]
	then
		if ! id $1
		then
			echo "$1 user not exist"
			exit 0
		fi
		remove_samba_config $1
		remove_nfs_config $1
		delete_user $1
	else
		if id $1
		then
			echo "$1 user exist"
			exit 0
		fi
		create_user $1
		samba_setup $1
		nfs_setup $1
	fi
else
	echo "USER NAME empty"
	usage
fi
