#!/usr/bin/env bash

QAC_PATH=/opt/Perforce/Helix-QAC-2024.1/common/bin
QACLI=qacli
COMMAND=$QAC_PATH/$QACLI
CCT=GNU_GCC-aarch64-none-linux-gnu-gcc_9.2.1-aarch64-none-linux-gnu-C-c90.cct
RCF=axera-qac-misrac-2012-V2.rcf
ACF=default.acf
PRJ_DIR=$1
PRJ_NAME=$2
PROJECT=$PRJ_DIR/$PRJ_NAME
WORKSPACE=$3
PLAT=$4

#check license
$COMMAND config license-server --list
$COMMAND config license-server --check

echo "$PRJ_DIR"
mkdir -p $PROJECT

$COMMAND project create -P $PROJECT --cct $WORKSPACE/build/QAC/configs/$CCT --rcf $WORKSPACE/build/QAC/configs/$RCF --acf $WORKSPACE/build/QAC/configs/$ACF
$COMMAND admin -P $PROJECT --set-source-code-root $WORKSPACE/boot/uboot

cd $WORKSPACE/boot/uboot;make PLAT=$PLAT clean
$COMMAND sync -P $PROJECT -t MONITOR "cd $WORKSPACE/boot/uboot/;make PLAT=$PLAT all"

$COMMAND pprops --list-components -P $PROJECT
$COMMAND pprops -c qac-11.5.0 -P $PROJECT -o -forceinclude --set $WORKSPACE/boot/uboot/u-boot-2022.10/include/linux/kconfig.h
$COMMAND pprops -c qac-11.5.0 --view-values -P $PROJECT

DIR=$WORKSPACE/boot/uboot/u-boot-2022.10/tools
for dir in $(find $DIR -type d | xargs echo)
do
	$COMMAND project files -P $PROJECT --remove --folder -- $dir
done

DIR=$WORKSPACE/boot/uboot/u-boot-2022.10/scripts
for dir in $(find $DIR -type d | xargs echo)
do
	$COMMAND project files -P $PROJECT --remove --folder -- $dir
done

DIR=$WORKSPACE/boot/uboot/u-boot-2022.10/cmd
for dir in $(find $DIR -type d | xargs echo)
do
	$COMMAND project files -P $PROJECT --remove --folder -- $dir
done

DIR=$WORKSPACE/build/out/$PLAT/objs/boot/uboot/u-boot-2022.10/tools
for dir in $(find $DIR -type d | xargs echo)
do
	$COMMAND project files -P $PROJECT --remove --folder -- $dir
done

DIR=$WORKSPACE/build/out/$PLAT/objs/boot/uboot/u-boot-2022.10/scripts
for dir in $(find $DIR -type d | xargs echo)
do
	$COMMAND project files -P $PROJECT --remove --folder -- $dir
done

$COMMAND analyze -P $PROJECT -c
$COMMAND analyze -P $PROJECT -f

REPORTS="CRR HMR MCR MDR RCR SCR SUR"
REP_DIR=/var/www/html/qac-m57h/uboot/${PLAT}_${PRJ_NAME}
mkdir -p $REP_DIR
for type in $REPORTS
do
	$COMMAND report -P $PROJECT --type $type -j 10 -o $REP_DIR
done

$COMMAND upload --dashboard --username admin --password admin -P $PROJECT --url http://10.30.62.30:8090 --upload-project ${PLAT}_${PRJ_NAME} --snapshot-name 1.0 --upload-source ALL -a ABSOLUTE -j 10