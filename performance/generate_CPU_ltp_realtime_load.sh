#!/bin/sh

# For Heavy CPU Ratio.
while true; do /bin/dd if=/dev/zero of=bigfile bs=1024000 count=1024; done &
while true; do /usr/bin/killall hackbench; sleep 5; done &
while true; do /userdata/hackbench; done &

cd /userdata/ltp/testcases/realtime; while true; do ./run.sh -t all; done &
