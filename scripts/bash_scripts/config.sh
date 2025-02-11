#!/usr/bin/env bash

set -x

IS_IN_SUDO=""
HOME_DIR="/home"

function create_user()
{
	echo "$1" # arguments are accessible through $1, $2,...
	USER_NAME=$1
	sudo useradd -m -d $HOME_DIR/${USER_NAME} -s /bin/bash ${USER_NAME}
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
   path = $HOME_DIR/$username/
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
	line=$(grep "\[$username\]" /etc/samba/smb.conf -n | cut -d : -f 1)
	if [ -n "$line" ]
	then
		sudo chmod 666 /etc/samba/smb.conf
		end=$(($line + 11))
		sudo sed -i "$line,${end}d" /etc/samba/smb.conf
		sudo chmod 644 /etc/samba/smb.conf
		sudo systemctl restart smbd.service
	fi
}

function nfs_setup () {
	echo "$1" # arguments are accessible through $1, $2,...
	username=$1
	echo "$HOME_DIR/$username/ *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
	sudo systemctl restart nfs-server.service
	sudo showmount -e localhost | grep $username
}

function remove_nfs_config () {
	echo "$1" # arguments are accessible through $1, $2,...
	username=$1
	pattern=$(echo "$HOME_DIR" | sed 's:/:\\/:g')
	line=$(grep "$pattern\/$username" /etc/exports -n | cut -d : -f 1)
	if [ -n "$line" ]
	then
		sudo sed -i "${line}d" /etc/exports
		sudo systemctl restart nfs-server.service
	fi
}

function usage()
{
	set +x
	echo "Usage:"
	echo "$0 [-srh] [-p prefix] USER_NAME"
	echo -e "\t -s         add user into sudo group"
	echo -e "\t -r         remove user and config"
	echo -e "\t -p prefix  prefix home directory"
	echo -e "\t -h         help"
}

if [ $# -lt 1 ]
then
	usage
	exit 0
fi

while getopts :srhp: opt
do
	case $opt in
		s)
			IS_IN_SUDO="Yes"
			;;
		r)
			DELETE_USER="Yes"
			;;
		p)
			PREFIX="$OPTARG"
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

if [ -n "$PREFIX" ]
then
	PREFIX=$(cd $PREFIX && pwd)
	if [ -d "$PREFIX" ]
	then
		HOME_DIR="${PREFIX}${HOME_DIR}"
	fi
fi

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
