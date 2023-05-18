#!/bin/sh
#
# Measure latency per RT priority and plot histogram
#

EXEC="/userdata/cyclictest"
DIR="/userdata/latency"
DURATION="1m"
HIST=1000
MIN_PRIO=1
MAX_PRIO=99

function latency()
{
	for i in $(seq $MIN_PRIO $MAX_PRIO)
	do
		killall cyclictest
		echo "priority of measurement thread $i"
		load=$(uptime)
		echo "$i $load" >>$DIR/system-load.txt
		$EXEC -q -m -a 1-7 -t 8 -p $i -i 200 -D $DURATION -h $HIST >output &
		sleep 1
		pid=$(pidof cyclictest)
		taskset -pc 0 $pid
		sleep 5
		taskset -a -pc $pid

		while true
		do
			exist=$(ps | grep "cyclictest" | grep -v "grep" | wc -l)
			if [ "$exist" -eq 0 ]
			then
				break
			fi
		done

		# 2. Get maximum latency
		max=$(grep "Max Latencies" output | tr " " "\n" | sort -n | tail -1 | sed s/^0*//)
		min=$(grep "Min Latencies" output | tr " " "\n" | sort -n | sed '1,3d' | head -n 1 | sed s/^0*//)
		avg=$(grep "Avg Latencies" output | tr " " "\n" | sort -n | tail -1 | sed s/^0*//)

		# 3. Grep data lines, remove empty lines and create a common field separator
		grep -v -e "^#" -e "^$" output | tr " " "\t" >histogram

		# 4. Set the number of cores, for example
		cores=8

		# 5. Create two-column data sets with latency classes and frequency values for each core, for example
		for y in $(seq 1 $cores)
		do
			column=$(expr $y + 1)
			cut -f1,$column histogram >$DIR/histogram-prio$i-cpu$y
		done

		# 6. Create plot command header
		echo -n -e "set title \"per-CPU Latency plot\"\n\
		set terminal png\n\
		set xlabel \"Latency (us), prio $i, max $max us\"\n\
		set logscale y\n\
		set xrange [0:$HIST]\n\
		set yrange [0.8:*]\n\
		set ylabel \"Number of latency samples\"\n\
		set output \"plot-prio$i.png\"\n\
		plot " >$DIR/plotcmd-prio$i

		# 7. Append plot command data references
		for z in $(seq 1 $cores)
		do
			if test $z != 1
			then
				echo -n ", " >>$DIR/plotcmd-prio$i
			fi
			cpuno=$(expr $z - 1)
			if test $cpuno -lt 10
			then
				title=" CPU$cpuno"
			else
				title="CPU$cpuno"
			fi
			echo -n "\"histogram-prio$i-cpu$z\" using 1:2 title \"$title\" with histeps" >>$DIR/plotcmd-prio$i
		done

		echo "$i $max" >>$DIR/max-latency-prio
		echo "$i $min" >>$DIR/min-latency-prio
		echo "$i $avg" >>$DIR/avg-latency-prio
	done
	rm -rf output histogram
}

function prio_latency()
{
	max=$(cat $DIR/max-latency-prio | awk '{print $2}' | sort -n | tail -1)
	min=$(cat $DIR/min-latency-prio | awk '{print $2}' | sort -n | tail -1)
	avg=$(cat $DIR/avg-latency-prio | awk '{print $2}' | sort -n | tail -1)
	# create plot command header
	echo -n -e "set title \"Latency plot\"\n\
	set terminal png\n\
	set xlabel \"Priority, Max $max us, Avg $avg us, Min $min us\"\n\
	set xrange [1:99]\n\
	set yrange [0:*]\n\
	set ylabel \"Latency (us)\"\n\
	set output \"plot-prio-latency.png\"\n\
	plot " >$DIR/plotcmd-prio-latency
	for i in max avg min
	do
		if test $i != "max"
		then
			echo -n ", " >>$DIR/plotcmd-prio-latency
		fi
		title=$(echo "$i" | awk '{for(i=1;i<=NF;i++){gsub(/^\w/,toupper(substr($i,1,1)),$i)};print}')
		echo -n "\"$i-latency-prio\" using 1:2 title \"$title\" with linespoints lw 2 smooth csplines" >>$DIR/plotcmd-prio-latency
	done
}

function usage()
{
	echo "Usage:"
	echo "$1 [-d TIME]"
	echo -e "-d\t specify a length for the test run."
	echo -e "  \t Append 'm', 'h', or 'd' to specify minutes, hours or days."
	echo -e "-H\t The max latency time to be tracked in microseconds"
}

while getopts d:H:h opt
do
	case $opt in
		d)
			DURATION=$OPTARG
			;;
		H)
			HIST=$OPTARG
			;;
		h)
			usage $0
			exit 0
			;;
	esac
done
shift $((OPTIND - 1))

if [ ! -d "$DIR" ]
then
	mkdir -p $DIR
fi
latency
prio_latency
