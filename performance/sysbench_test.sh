#!/bin/sh

EXE="/userdata/sysbench"

# 4K seq read
info=$($EXE memory --memory-block-size=4k --memory-oper=read --memory-access-mode=seq --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "4K seq read:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 4K seq write
info=$($EXE memory --memory-block-size=4k --memory-oper=write --memory-access-mode=seq --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "4K seq write:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 4K rnd read
info=$($EXE memory --memory-block-size=4k --memory-oper=read --memory-access-mode=rnd --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "4K rnd read:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 4K rnd write
info=$($EXE memory --memory-block-size=4k --memory-oper=write --memory-access-mode=rnd --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "4K rnd write:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 64K seq read
info=$($EXE memory --memory-block-size=64k --memory-oper=read --memory-access-mode=seq --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "64K seq read:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 64K seq write
info=$($EXE memory --memory-block-size=64k --memory-oper=write --memory-access-mode=seq --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "64K seq write:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 64K rnd read
info=$($EXE memory --memory-block-size=64k --memory-oper=read --memory-access-mode=rnd --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "64K rnd read:"
echo "$eps"
echo "$sum"
echo "$time"

sleep 5

# 64K rnd write
info=$($EXE memory --memory-block-size=64k --memory-oper=write --memory-access-mode=rnd --threads=8 run)

eps=$(echo "$info" | grep "events/s (eps)" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
sum=$(echo "$info" | grep "sum" | awk -F: '{print $NF}' | sed 's/[[:space:]]//g')
time=$(echo "$info" | grep "execution time" | awk -F: '{print $NF}' | awk -F / '{print $1}' | sed 's/[[:space:]]//g')

echo "64K rnd write:"
echo "$eps"
echo "$sum"
echo "$time"
