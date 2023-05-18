#!/bin/bash

cd /userdata/
while true; do taskset -c 0 tar cvzf test1.tgz  ./linux-stable-rt ; done  &
while true; do taskset -c 1 tar cvzf test2.tgz  ./linux-stable-rt ; done  &
while true; do taskset -c 2 tar cvzf test3.tgz  ./linux-stable-rt ; done  &
while true; do taskset -c 3 tar cvzf test4.tgz  ./linux-stable-rt ; done  &
