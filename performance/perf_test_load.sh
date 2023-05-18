#!/bin/sh
#

CUR_PATH=$(cd $(dirname $0);pwd)
echo "$CUR_PATH"

function cpu_load()
{
	if [ -x $CUR_PATH/stress-ng ]
	then
		$CUR_PATH/stress-ng -c 7 --cpu-method all -l 80 --vm 1 --timeout 1000s &>/dev/null &
		if [ $? -eq 0 ]
		then
			echo "Increase CPU load successfully."
		else
			echo "Failed to increase CPU load!"
		fi
	fi
}

function check_cpu_load()
{
	local stress=$(ps | grep stress-ng | grep -v "{*}" | grep -v grep | wc -l)
	if [ "$stress" ] && [ $stress -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function bpu_load()
{
	export BMEM_CACHEABLE=true
	export LD_LIBRARY_PATH=/app/libbpu/hbdk3:$LD_LIBRARY_PATH

	local output00="/userdata/model-2k_00/"
	local output01="/userdata/model-2k_01/"
	local output10="/userdata/model-2k_10/"
	local output11="/userdata/model-2k_11/"
	local hbm_file="/app/libbpu/HBDK3_MODEL_2K/gen_I2004_ForTest2k_1x1088x2048x3.hbm"
	local src_file="/app/libbpu/HBDK3_MODEL_2K/input_0_feature_1x1088x2048x3_ddr_native.bin"
	local model_name="I2004_ForTest2k_1x1088x2048x3"

	if [ -d "$output00" ]
	then
		rm -rf $output00
	fi

	if [ -d "$output01" ]
	then
		rm -rf $output01
	fi
	if [ -d "$output10" ]
	then
		rm -rf $output10
	fi
	if [ -d "$output11" ]
	then
		rm -rf $output11
	fi
	mkdir -p $output00
	mkdir -p $output01
	mkdir -p $output10
	mkdir -p $output11

	if [ -x /app/bin/tc_hbdk3 ]
	then
		tc_hbdk3 -f $hbm_file -i $src_file -n $model_name -o $output00,$output01,$output10,$output11 -g 0 -c 1000 &>/dev/null &
		if [ $? -eq 0 ]
		then
			echo "Increase BPU load successfully."
		else
			echo "Failed to increase BPU load!"
		fi
	else
		echo "Failed to find out tc_hbdk3!"
	fi
}

function check_bpu_load()
{
	local bpu=$(ps | grep tc_hbdk3 | grep -v "{*}" | grep -v grep | wc -l)
	if [ "$bpu" ] && [ $bpu -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function network_load()
{
	if [ "$serverip" ]
	then
		iperf3 -c $serverip -b 300M -n 100G &>/dev/null &
		if [ $? -eq 0 ]
		then
			echo "Increase network load successfully."
		else
			echo "Failed to increase network load!"
		fi
	else
		echo "Failed to specify server IP for iperf3!"
	fi
}

function check_network_load()
{
	local network=$(ps | grep iperf3 | grep -v grep | wc -l)
	if [ "$network" ] && [ $network -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function pcie_load()
{
	if [ -x "$CUR_PATH/hbpcie_dma_test" ]
	then
		local pcie=$(ps | grep  hbpcie_dma_test | grep -v grep)
		if [ "$pcie" ]
		then
			killall hbpcie_dma_test
		fi
		$CUR_PATH/hbpcie_dma_test 4 0 -w -t 1 &>/dev/null &
		echo "Increase PCIe load successfully."
	else
		echo "Failed to increase PCIe load!"
	fi
}

function check_pcie_load()
{
	local pcie=$(ps | grep  hbpcie_dma_test | grep -v grep | wc -l)
	if [ "$pcie" ] && [ $pcie -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function can_load()
{
	if [ -x "/app/bin/ip" ] && [ -x "/app/bin/candump" ]
	then
		local state=$(/app/bin/ip link show can0 | grep "state DOWN")
		if [ "$state" ]
		then
			/app/bin/ip link set can0 up type can bitrate 1000000
		fi
		state=$(/app/bin/ip link show can1 | grep "state DOWN")
		if [ "$state" ]
		then
			/app/bin/ip link set can1 up type can bitrate 1000000
		fi
		state=$(/app/bin/ip link show can2 | grep "state DOWN")
		if [ "$state" ]
		then
			/app/bin/ip link set can2 up type can bitrate 1000000
		fi
		state=$(/app/bin/ip link show can3 | grep "state DOWN")
		if [ "$state" ]
		then
			/app/bin/ip link set can3 up type can bitrate 1000000
		fi

		state=$(ps | grep candump | grep "can0" | grep -v grep)
		if [ -z "$state" ]
		then
			/app/bin/candump can0 &>/dev/null &
		fi
		state=$(ps | grep candump | grep "can1" | grep -v grep)
		if [ -z "$state" ]
		then
			/app/bin/candump can1 &>/dev/null &
		fi
		state=$(ps | grep candump | grep "can2" | grep -v grep)
		if [ -z "$state" ]
		then
			/app/bin/candump can2 &>/dev/null &
		fi
	fi
	sh $CUR_PATH/can_send.sh &
	if [ $? -eq 0 ]
	then
		echo "Increase CAN load successfully."
	else
		echo "Failed to increase CAN load!"
	fi
}

function check_can_load()
{
	local can=$(ps | grep can_send.sh | grep -v grep | wc -l)
	if [ "$can" ] && [ $can -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function codec_load()
{
	local OUTPUT_DIR_PREFIX="/userdata/libmm/"
	if [ ! -e "/dev/jpu" ]
	then
		insmod "/app/bin/libmm/hobot_jpu.ko"
	fi

	if [ ! -e "/dev/vpu" ]
	then
		insmod "/app/bin/libmm/hobot_vpu.ko"
	fi

	if [ -d "${OUTPUT_DIR_PREFIX}/output/" ]
	then
		rm -rf "${OUTPUT_DIR_PREFIX}/output/"
	fi
	mkdir -p "${OUTPUT_DIR_PREFIX}/output/"

	if [ -x "$CUR_PATH/multimedia_test" ]
	then
		$CUR_PATH/multimedia_test  --gtest_filter=MediaCodecTest.test_encoding_decoding_case_multiProcess_2\
			--gtest_output=xml:${OUTPUT_DIR_PREFIX}output/multimedia_H265MultiEncDec_test_result.xml \
			--input_dir="/app/bin/libmm/" \
			--output_dir=${OUTPUT_DIR_PREFIX} \
			--test_time=1000 \
			--test-md5=0 &>/dev/null &
		if [ $? -eq 0 ]
		then
			echo "Increase CODEC load successfully."
		else
			echo "Failed to increase CODEC load!"
		fi
	else
		echo "Failed to find out multimedia_test"
	fi
}

function check_codec_load()
{
	local codec=$(ps | grep multimedia_test | grep -v grep | wc -l)
	if [ "$codec" ] && [ $codec -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function gdc_load()
{
	export LD_LIBRARY_PATH=/app/bin/vps/vpm/lib:$LD_LIBRARY_PATH
	export PYM_MODULE_SKIP=1
	export ISP_MODULE_SKIP=1

	gdc_module=$(lsmod | grep hobot_gdc)
	if [ -z "$gdc_module" ] && [ -e "/app/bin/vps/vpm/hobot_gdc.ko" ]
	then
		insmod /app/bin/vps/vpm/hobot_gdc.ko
		echo "insmod hobot_gdc.ko successfully."
	fi

	if [ -x "/app/bin/vps/vpm/vpm_gtest" ]
	then
		/app/bin/vps/vpm/vpm_gtest -v "/app/bin/vps/vpm/cfg/ddr_gdc_1080p/vpm_config.json" \
			-G 0 -l 10000 -w "/app/bin/vps/vpm/res/1080p.yuv" \
			--gtest_filter=VpmGdcTest.gdc_feedback &>/dev/null &
		if [ $? -eq 0 ]
		then
			echo "Increase GDC load successfully."
		else
			echo "Failed to increase GDC load!"
		fi
	else
		echo "Failed to find out vpm_gtest!"
	fi
}

function check_gdc_load()
{
	local gdc=$(ps | grep ddr_gdc_1080p | grep -v "{*}" | grep -v grep | wc -l)
	if [ "$gdc" ] && [ $gdc -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function stitch_load()
{
	if [ -x "/app/bin/videostitch_test/videostitch_test" ]
	then
		/app/bin/videostitch_test/videostitch_test -m 1 -d 0 -id 0 -l 10000 &>/dev/null &
		if [ $? -eq 0 ]
		then
			echo "Increase STITCH load successfully."
		else
			echo "Failed to increase STITCH load!"
		fi
	else
		echo "Failed to find out videostitch_test!"
	fi
}

function check_stitch_load()
{
	local stitch=$(ps | grep videostitch_test | grep -v "{*}" | grep -v grep | wc -l)
	if [ "$stitch" ] && [ $stitch -gt 0 ]
	then
		return 0
	else
		return 1
	fi
	return 0
}

function main()
{
	cpu_load
	bpu_load
	network_load
	can_load
	pcie_load
	codec_load
	gdc_load
	stitch_load
}

function usage()
{
	echo "Usage: $0 [-n <serverip>] [-h]"
}

while getopts :n:h opt
do
	case $opt in
	n)
		serverip=$OPTARG
		;;
	h)
		usage
		;;
	'?')
		echo "$0: invalid option -$OPTARG" >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

export PATH=$PATH:/app/bin/
main

while true
do
	if ! check_cpu_load
	then
		cpu_load
	fi

	if ! check_bpu_load
	then
		bpu_load
	fi

	if ! check_network_load
	then
		network_load
	fi

	if ! check_can_load
	then
		can_load
	fi

	if ! check_pcie_load
	then
		pcie_load
	fi

	if ! check_codec_load
	then
		codec_load
	fi

	if ! check_gdc_load
	then
		gdc_load
	fi

	if ! check_stitch_load
	then
		stitch_load
	fi
	sleep 5
done

