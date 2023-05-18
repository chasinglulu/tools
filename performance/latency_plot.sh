#!/bin/bash

for i in $(seq 1 99)
do
	gnuplot -persist < plotcmd-prio$i
done

gnuplot -persist < plotcmd-prio-latency

