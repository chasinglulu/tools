#!/usr/bin/env bash

# 参数格式化
TOPIC_NAME=$(echo $TOPIC_NAME | sed 's/，/,/g' | sed 's/,//')

ASSIGN_TOPIC=$(echo $ASSIGN_TOPIC | sed 's/，/,/g' | sed 's/,//')
if [ -n "$ASSIGN_TOPIC" ]
then
	TIMESTAMPS=$(date '+%M%S')
	NEW_TOPIC=${ASSIGN_TOPIC}_${TIMESTAMPS}
fi

if [ "$PATCH_MODE" = "Topic" ]
then
	# Get all the gerrit IDs from the same topic
	GERRIT_ID=$(ssh -p 29418 gerrit.aixin-chip.com gerrit query --patch-sets topic:${TOPIC_NAME} < /dev/null | grep '^  number:' | awk '{print $2}' | sort | xargs )
	echo "GERRIT_ID: $GERRIT_ID"
elif [ "$PATCH_MODE" = "GerritID" ]
then
	GERRIT_ID=$(echo ${GERRIT_ID} | sed 's/ //g' | sed 's/，/,/g' | sed 's/,/ /g' )
	echo "GERRIT_ID: $GERRIT_ID"
else
	echo "没有合适的patch格式"
fi

# add patch set ids:
for id in ${GERRIT_ID}
do
	PATCH_ID_HTML="${PATCH_ID_HTML} <a href='https://gerrit.aixin-chip.com/${id}'>${id}</a>"
done

# set job start by who
BUILD_CAUSE_JSON=$(curl -u jenkins:G}4J6F{ObP --silent ${BUILD_URL}/api/json | tr "{}" "\n" | grep "Started by")
BUILD_USER_ID=$(echo $BUILD_CAUSE_JSON | tr "," "\n" | grep "userId" | awk -F\" '{print $4}')
BUILD_USER_NAME=$(echo $BUILD_CAUSE_JSON | tr "," "\n" | grep "userName" | awk -F\" '{print $4}')
curl -s -u "${SW_JENKINS_USER}":"${SW_JENKINS_TOKEN}" --data-urlencode "description=Gerrit Ids: ${PATCH_ID_HTML}<br>Started by: ${BUILD_USER_NAME}" --data-urlencode "Submit=Submit" "${BUILD_URL}/submitDescription"
cd "${WORKSPACE}"
manifest_file="${WORKSPACE}"/.repo/manifests/"${MANIFEST_XML}"

repo forall -c git lfs pull
set +e
repo forall -c git lfs pull
repo manifest -r -o manifest.xml
cp manifest.xml "${WORKSPACE}"/build/manifest.xml

# cherry-pick change ids
if [ -z "${GERRIT_ID}" ]
then
	echo "*** ERROR *** Gerrit change ID is empty, exit task!"
	exit 1
fi

function get_change_patchset_revision {
	change_revision=$(gerrit -i "${1}" -m get_change_patchset_revision)
	if [ -n "${change_revision}" ]
	then
		echo "${1}":"${change_revision}" >> "${WORKSPACE}"/change_revision
	fi
}

function lfs_change_cherry_pick() {
	# must git fetch first, otherwise git show "${change_revision}" failed
	git fetch ssh://jenkins@gerrit.aixin-chip.com:29418/"${gerrit_id_project}" "${gerrit_id_refId}" && git cherry-pick FETCH_HEAD
	change_revision=$(echo "${change_revision}" | sed 's/\"//g')
	lfs_exist=$(git show "${change_revision}" | grep "https://git-lfs.github.com")
	if [ -n "${lfs_exist}" ]
	then
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
    gerrit_id_project=$(ssh -p 29418 gerrit.aixin-chip.com gerrit query ${gerrit_id} < /dev/null | grep '^  project:' | sed 's/.*project:\s*\(\S*\).*/\1/g' | sed 's/^acos\///')
    gerrit_id_refId=$(ssh -p 29418 gerrit.aixin-chip.com gerrit query --current-patch-set ${gerrit_id} < /dev/null | grep ' ref:' | awk '{print $2}')

    if [ -z "${gerrit_id_project}" ];
    then
        echo "*** ERROR *** Query patch information fail, please make sure your patch is correct then contact system admin!"
        #exit 1
    fi
    echo "gerrit id project: ${gerrit_id_project} ++++++ gerrit_id_refId: ${gerrit_id_refId}"
    while read LINE
    do
        if [[ $LINE =~ "name=\"${gerrit_id_project}\"" ]]; then
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
    done < "${WORKSPACE}"/build/manifest.xml
done

function check_topic_exist
{
	# gerrit id个数小于2个时，直接退出；
	# 检查所有的gerrit id是否都存在topic，如有一个存在，退出检查；
	if [ $# -gt 1 ];then
		for i in $@
		do
			# api_get_topic=$(curl -s -X GET https://gerrit.aixin-chip.com/a/changes/$i/topic --user 'jenkins:G}4J6F{ObP')
			api_get_topic=$(gerrit -m get_topic -i $i)
			topic_filter=$(echo $api_get_topic | cut -d '"' -f 2)
			if [ -n "${topic_filter}" ];then
				# topic已有值，则退出
				flag=110 && break
			fi
		done
		flag=119
	else
		flag=120
	fi
}

function set_topic
{
	if [ -n "${ASSIGN_TOPIC}" ]
	then
		echo "start update topic"
		check_topic_exist ${GERRIT_ID}
		if [ $flag -eq 110 ];then
			echo "gerri_id:$i has topic: $topic_filter, skip push topic"
		elif [ $flag -eq 120 ];then
			echo "单个gerrit无需提交topic"
		elif [ $flag -eq 119 ];then
			for i in ${GERRIT_ID}
			do
				echo $i
				curl -X PUT -H "Content-Type: application/json" -d "{"topic": "$new_topic"}" https://gerrit.aixin-chip.com/a/changes/$i/topic --user 'jenkins:G}4J6F{ObP'
			done
		fi
	else
		echo "Don't need to set topic."
	fi
}

if [ "${AXERA_FPGA}" = "true" ]
then
BUILD_TARGET="${BUILD_TARGET} fpga"
fi

if [ "${QEMU_VIRT}" = "true" ]
then
BUILD_TARGET="${BUILD_TARGET} qemu_virt"
fi

echo "============================ $BUILD_TARGET ======================="

export BUILD_TARGET
export WORKSPACE

BUILD_TARGET=$(echo "$BUILD_TARGET" | grep -o "[^ ]\+\( \+[^ ]\+\)*")
if [ -z "${BUILD_TARGET}" ]
then
	echo "build target is empty"
	exit 1
fi

echo "======================== Begin verifying ========================"
sh ${WORKSPACE}/build/scripts/jenkins_verify.sh

if [ "$PATCH_MODE" = "GerritID" ]
then
	set_topic
fi
