

function usage {
	echo "Usage:"
	echo "$0 -i <interface> -c"
    echo "$0 -i <interface> -d"
}


function create()
{
    sudo brctl addbr br0
    sudo ip addr flush dev $PHY_INTERFACE
    sudo brctl addif br0 $PHY_INTERFACE
    sudo tunctl -t tap0 -u `whoami`
    sudo ifconfig $PHY_INTERFACE up
    sudo ifconfig br0 up
    sudo ifconfig tap0 up
    sudo dhclient -v br0
    sudo brctl addif br0 tap0
}

function delete()
{
    sudo brctl delif br0 tap0
    sudo tunctl -d tap0
    sudo brctl delif br0 $PHY_INTERFACE
    sudo ifconfig br0 down
    sudo brctl delbr br0
    sudo ifconfig $PHY_INTERFACE up
    sudo dhclient -v $PHY_INTERFACE
}

if [ $# -lt 3 ]
then
    usage
    exit 1
fi

while getopts :i:cd opt
do
	case $opt in
		i)
			PHY_INTERFACE="$OPTARG"
			;;
        c)
            create
            ;;
        d)
            delete
            ;;
		?)
			echo -e "\n[ERROR]$0: invaild option $OPTARG\n" >&2
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))
