#!/usr/bin/env bash

set +x
set -e

# main start
export GERRIT_ID=$(echo ${GERRIT_ID} | sed 's/ //g' | sed 's/，/,/g' | sort -n)
echo ${GERRIT_ID}

# add patch set ids:
for id in $(echo ${GERRIT_ID} | sed 's/,/ /g')
do
    PATCH_ID_HTML="${PATCH_ID_HTML} <a href='https://gerrit.aixin-chip.com/${id}'>${id}</a>"
done
echo "start download"
# set job start by who
BUILD_CAUSE_JSON=$(curl -u jenkins:G}4J6F{ObP --silent ${BUILD_URL}/api/json | tr "{}" "\n" | grep "Started by")
BUILD_USER_ID=$(echo $BUILD_CAUSE_JSON | tr "," "\n" | grep "userId" | awk -F\" '{print $4}')
BUILD_USER_NAME=$(echo $BUILD_CAUSE_JSON | tr "," "\n" | grep "userName" | awk -F\" '{print $4}')

curl -s -u "${SW_JENKINS_USER}":"${SW_JENKINS_TOKEN}" --data-urlencode "description=Gerrit Ids: ${PATCH_ID_HTML}<br>Started by: ${BUILD_USER_NAME}" --data-urlencode "Submit=Submit" "${BUILD_URL}/submitDescription"
#repo forall -c git lfs pull
python -u /data/home/qac/Public/wangwen/download.py --xml .repo/manifests/default.xml
set +e
repo manifest -r -o manifest.xml
cp manifest.xml "${WORKSPACE}"/build/manifest.xml
echo "end download"
# cherry-pick change ids
if [ "${GERRIT_ID}x" = "x" ]; then
    echo "Gerrit Change ID is empty, exit task!"
    #exit 1
fi

function get_change_patchset_revision {
    change_revision=$(gerrit -i "${1}" -m get_change_patchset_revision)
    if [ -n "${change_revision}" ]; then
        echo "${1}":"${change_revision}" >> "${WORKSPACE}"/change_revision
    fi
}
function lfs_change_cherry_pick() {
    # must git fetch first, otherwise git show "${change_revision}" failed
    git fetch ssh://jenkins@gerrit.aixin-chip.com:29418/"${gerrit_id_project}" "${gerrit_id_refId}" && git cherry-pick FETCH_HEAD
    change_revision=$(echo "${change_revision}" | sed 's/\"//g')
    lfs_exist=$(git show "${change_revision}" | grep "https://git-lfs.github.com")
    if [ -n "${lfs_exist}" ]; then
        remote_name=$(git remote -v | awk '{print $1}' | head -n1)
        git_branch=$(git branch -a | grep "\->" | awk -F "/" '{print $NF}')
        if [ -n "${remote_name}" ] && [ -n "${git_branch}" ]; then
            git remote remove "${remote_name}"
            git remote add "${remote_name}" ssh://jenkins@gerrit.aixin-chip.com:29418/"${gerrit_id_project}"
            git reset --hard HEAD
            git lfs pull "${remote_name}"
        fi
    fi
}

for gerrit_id in $(echo ${GERRIT_ID} | sed 's/,/ /g')
do
    echo -e "\nCherry-pick gerrit change id: ${gerrit_id}"
    gerrit_id_project=$(gerrit -m get_change -i ${gerrit_id} | jq -r .project)
    gerrit_id_refId=$(gerrit -m get_change_detail -i ${gerrit_id} | jq -r .revisions[].ref)

    if [ -z "${gerrit_id_project}" ];
    then
        echo "*** ERROR *** Query patch information fail, please make sure your patch is correct then contact system admin!"
        #exit 1
    fi
    echo "gerrit id project: ${gerrit_id_project} ++++++ gerrit_id_refId: ${gerrit_id_refId}"
    # Adapt middleware library
    if [ ${gerrit_id_project} = "app_image_engine" ];then
        gitlab_project="app/image_node"
    elif [ ${gerrit_id_project} = "app_infer_engine" ];then
        gitlab_project="app/infer_node"
    elif [ ${gerrit_id_project} = "app_postprocess_engine" ];then
        gitlab_project="app/postprocess_node"
    elif [ ${gerrit_id_project} = "dep" ];then
        gitlab_project="app/dep"
    elif [ ${gerrit_id_project} = "app_demo" ];then
        gitlab_project="app/demo"
    else
        gitlab_project=${gerrit_id_project}
    fi
    while read LINE
    do
        if [[ $LINE =~ "name=\"${gitlab_project}\"" ]]; then
            if [[ $LINE =~ "path=\"" ]]; then
                echo "--->${LINE}"
                for item in ${LINE}
                do
                    if [[ ${item} =~ "path=\"" ]]; then
                        #echo ${item}
                        repo_path=$(echo ${item#*=} | sed "s/\"//g")
                        break
                    fi
                done
                echo "*******************  ${repo_path}"
                echo "check pick repo: ${gerrit_id_project} +++  ${gerrit_id_refId} +++ ${WORKSPACE}/${repo_path}"
                cd "${WORKSPACE}"/"${repo_path}"

                # To prevent the cherry pick from getting stuck, npu and tools repo pull a complete repository
                gerrit_id_project=$(echo ${gerrit_id_project} | sed 's/ //g')
                if [[ "${gerrit_id_project}" =~ "npu" ]] || [ X"${gerrit_id_project}" == X"tools" ]; then
                    git fetch --unshallow
                fi
                git log -1

                get_change_patchset_revision "${gerrit_id}"
                lfs_change_cherry_pick "${gerrit_id_project}"
                echo "cherry-pick command: git fetch ssh://jenkins@gerrit.aixin-chip.com:29418/${gerrit_id_project} ${gerrit_id_refId} && git cherry-pick FETCH_HEAD"
                git fetch ssh://jenkins@gerrit.aixin-chip.com:29418/"${gerrit_id_project}" "${gerrit_id_refId}" && git cherry-pick -n FETCH_HEAD && break
                if [ $? -ne 0 ]; then
                    echo "*** ERROR *** cherry-pick change id: ${gerrit_id} fail! exit build processing."
                    exit 1
                fi
            else
                echo "+++>${LINE}"
                cd "${WORKSPACE}"/"${gerrit_id_project}"

                # To prevent the cherry pick from getting stuck, npu and tools repo pull a complete repository
                gerrit_id_project=$(echo ${gerrit_id_project} | sed 's/ //g')
                if [[ "${gerrit_id_project}" =~ "npu" ]] || [ X"${gerrit_id_project}" == X"tools" ]; then
                    git fetch --unshallow
                fi
                git log -1

                get_change_patchset_revision "${gerrit_id}"
                lfs_change_cherry_pick "${gerrit_id_project}"
                echo "cherry-pick command: git fetch ssh://jenkins@gerrit.aixin-chip.com:29418/${gerrit_id_project} ${gerrit_id_refId} && git cherry-pick FETCH_HEAD"
                git fetch ssh://jenkins@gerrit.aixin-chip.com:29418/"${gerrit_id_project}" "${gerrit_id_refId}" && git cherry-pick -n FETCH_HEAD && break
                if [ $? -ne 0 ]; then
                    echo "*** ERROR *** cherry-pick change id: ${gerrit_id} fail! exit build processing."
                    exit 1
                fi
            fi
            echo -e "\n\n"
        fi
    done < "${WORKSPACE}"/.repo/manifests/default.xml
done

if [ "${AXERA_FPGA}" = "true" ]
then
    BUILD_TARGET="${BUILD_TARGET} fpga"
fi

if [ "${AXERA_DEMO_NOR_NAND}" = "true" ]
then
    BUILD_TARGET="${BUILD_TARGET} demo_nor_nand"
fi

if [ "${AXERA_EVB}" = "true" ]
then
    BUILD_TARGET="${BUILD_TARGET} evb"
fi

if [ "${QEMU_VIRT}" = "true" ]
then
    BUILD_TARGET="${BUILD_TARGET} qemu_virt"
fi

if [ "${AXERA_ZEBU}" = "true" ]
then
    BUILD_TARGET="${BUILD_TARGET} zebu"
fi

export BUILD_TARGET
export WORKSPACE

BUILD_TARGET=$(echo "$BUILD_TARGET" | grep -o "[^ ]\+\( \+[^ ]\+\)*")
if [ -z "${BUILD_TARGET}" ]
then
    echo "build target is empty"
    exit 1
fi
set -e
echo "======================== Begin verifying ========================"
cd ${WORKSPACE}/build
for TARGET in ${BUILD_TARGET}
do
    if "${Fusa}" = "true" 
    then
        echo "Fusa is true" 
        make PLAT=${TARGET} fusa
    fi


    python -u ${WORKSPACE}/build/scripts/build.py --plat ${TARGET}
done
if [ $? == 0 ]
then
    echo ""
    echo "======================== Building $TARGET Successfully! ========================"
    echo ""
else
    exit 1
fi

if [ "${ISP_UT_VERIFY}" = "true" ] && [ -e "${WORKSPACE}/build/scripts/jenkins_isp_verify.sh" ]
then
    echo "======================== Begin ISP UT & ISP_SIM_X86 verifying ========================"
    # Lock device
    python3 /opt/.shell/ci-cd-scripts/database/use_ut_equipment_status_alias.py -p Haps9 -u start -j "${BUILD_URL}" -g Haps -cj "${BUILD_URL}"
    #haps verify
    pushd ${WORKSPACE}/ut/verify
    #sh ${WORKSPACE}/ut/verify/jenkins_entry_ut_verify.sh -s 10.122.86.74:8010 -b ${BUILD_NUMBER} -t os04a10
    sh ${WORKSPACE}/ut/verify/jenkins_entry_ut_verify.sh -s 10.122.86.74:8011 -j ${JOB_NAME} -b ${BUILD_NUMBER} -t os04a10 -l
    UT_VERIFY_STATUS=$?
    popd
    # Release device
    python3 /opt/.shell/ci-cd-scripts/database/use_ut_equipment_status.py -b Haps9 -u stop
    if [ "${UT_VERIFY_STATUS}" -ne 0 ]
    then
        exit ${UT_VERIFY_STATUS}
    fi

    sh ${WORKSPACE}/build/scripts/jenkins_isp_verify.sh
fi