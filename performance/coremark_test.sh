#!/bin/sh

run1_param="0x0 0x0 0x66 500000 7 1 2000"
run2_param="0x3415 0x3415 0x66 500000 7 1 2000"
run3_param="0x0 0x0 0x66 500000 7 1 6000"
run4_param="0x3415 0x3415 0x66 500000 7 1 6000"
run5_param="8 8 8 500000 7 1 1200"

EXE="/userdata/coremark"

# 2K performance
info=$($EXE $run1_param)
info=$(echo "$info" | grep "Iterations/Sec" | awk -F: '{print $NF}')
echo "2K performance :$info"
sleep 5

# 2K validation
info=$($EXE $run1_param)
info=$(echo "$info" | grep "Iterations/Sec" | awk -F: '{print $NF}')
echo "2K validation :$info"
sleep 5

# 6k performance
info=$($EXE $run1_param)
info=$(echo "$info" | grep "Iterations/Sec" | awk -F: '{print $NF}')
echo "6k performance :$info"
sleep 5

# 6k validation
info=$($EXE $run1_param)
info=$(echo "$info" | grep "Iterations/Sec" | awk -F: '{print $NF}')
echo "6k validation :$info"
sleep 5

# Profile generation
info=$($EXE $run1_param)
info=$(echo "$info" | grep "Iterations/Sec" | awk -F: '{print $NF}')
echo "Profile generation :$info"

