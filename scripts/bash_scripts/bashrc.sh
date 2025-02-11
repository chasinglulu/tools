
export TERM=xterm-256color
export CROSS_COMPILE=aarch64-none-linux-gnu-
export ARCH=arm64
export PATH=/home/charleye/.toolchains/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin:$PATH


function scp130()
{
	if [ $# -lt 2 ]
	then
		echo "Too few arguments"
		return 1
	fi
	input=$(echo "$*" | awk '{$NF="";print $0}')
	count=$(echo "$input" | awk '{print NF}')
	output=$(echo "$*" | awk '{print $NF}')
	if ssh wangxinlu@10.126.12.130 test -d $output
	then
		scp -r $input wangxinlu@10.126.12.130:$output
	else
		if [ $count -gt 1 ]
		then
			echo "multi-file for one remote file"
			return 1
		fi
		scp -r $input wangxinlu@10.126.12.130:~/$output
	fi
}

function scp30()
{
	if [ $# -lt 2 ]
	then
		echo "Too few arguments"
		return 1
	fi
	input=$(echo "$*" | awk '{$NF="";print $0}')
	count=$(echo "$input" | awk '{print NF}')
	output=$(echo "$*" | awk '{print $NF}')
	if ssh wangxinlu@10.30.62.30 test -d $output
	then
		scp -r $input wangxinlu@10.30.62.30:$output
	else
		if [ $count -gt 1 ]
		then
			echo "multi-file for one remote file"
			return 1
		fi
		scp -r $input wangxinlu@10.30.62.30:~/$output
	fi
}

alias ssh130="ssh wangxinlu@10.126.12.130"
alias ssh30="ssh wangxinlu@10.30.62.30"

export NODE_PATH=/usr/lib/nodejs:/usr/share/nodejs

function setproxy()
{
    export http_proxy='http://10.0.2.2:7890'
    export https_proxy='https://110.0.2.2:7890'
}

function unsetproxy() {
    export http_proxy=
    export https_proxy=
}
