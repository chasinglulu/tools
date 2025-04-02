#!/usr/bin/env bash

QAC_PATH=/opt/Perforce/Helix-QAC-2024.1/common/bin
QACLI=qacli
COMMAND=$QAC_PATH/$QACLI
CCT=GNU_GCC-arm-linux-gnueabi-gcc_7.5.0-arm-linux-gnueabi-C-c11.cct
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
$COMMAND admin -P $PROJECT --set-source-code-root $WORKSPACE/SafetyIsland

cd $WORKSPACE/SafetyIsland/;make PLAT=$PLAT clean
$COMMAND sync -P $PROJECT -t MONITOR "cd $WORKSPACE/SafetyIsland/;make PLAT=$PLAT all"

$COMMAND pprops --list-components -P $PROJECT

$COMMAND analyze -P $PROJECT -c
$COMMAND analyze -P $PROJECT -f

REPORTS="CRR HMR MCR MDR RCR SCR SUR"
REP_DIR=/var/www/html/qac-m57h/SafetyIsland/${PLAT}_${PRJ_NAME}
mkdir -p $REP_DIR
for type in $REPORTS
do
	$COMMAND report -P $PROJECT --type $type -j 10 -o $REP_DIR
done

$COMMAND upload --dashboard --username admin --password admin -P $PROJECT --url http://10.30.62.30:8090 --upload-project ${PLAT}_${PRJ_NAME} --snapshot-name 1.0 --upload-source ALL -a ABSOLUTE -j 10