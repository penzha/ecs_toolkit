#!/bin/bash
# Copyright (c) 2017 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.
##########################################################################

##########################################################################
# 0.5.0 - Initial version
# 0.6.0 - 
# 0.7.0 - Enhanced with checking reclaimed garbage since VDC was in 3.0
#         code base
# 0.9.0 - Change name to gc_check.sh from gc_whole.${VERSION}.sh
#         Running multi checking in parralel
#         Change usage
#         Fixed bugs
# 1.0.0 - 
##########################################################################


VERSION="0.9.2"
SCRIPTNAME="$(basename $0)"

DEBUG_MODE=0
TRACE_MODE=0
CHECK_REPO_GC=1
CHECK_BTREE_GC=1

PARTIAL_GC_ENABLED=0 # TBD

ECS_VERSION=''

ZONE_ID=''
VDC_NAME=''
COS=''
SP_NAME=''
REPLICATION_GROUP=''
MGMT_IP=''
REPL_IP=''
DATA_IP=''


function usage()
{
    echo ""
    echo "Usage: $SCRIPTNAME -a|-r|-b"
    echo ""
    echo "Options:"
    echo "       -h: Help           - print Help screen"
    echo "       -a: All            - check both Repo and Btree GC"
    echo "       -r: Repo GC        - only check Repo GC"
    echo "       -b: Btree GC       - only check Btree GC"
}

[[ $# -eq 0 ]] && usage

while getopts "arbDh" arg
    do
    case ${arg} in
        a)
            CHECK_REPO_GC=1
            CHECK_BTREE_GC=1
            ;;
        r)
            CHECK_REPO_GC=1
            CHECK_BTREE_GC=0
            ;;
        b)
            CHECK_REPO_GC=0
            CHECK_BTREE_GC=1
            ;;
        h)
            usage
            ;;
        ?)
            usage
            ;;
    esac
done



WORK_DIR=/var/tmp/gc_check/$(date '+%Y%m%dT%H%M%S')
mkdir -p ${WORK_DIR}
MACHINES_FILE=${WORK_DIR}/MACHINES
RG_ZONE_COS_MAP=${WORK_DIR}/rg_zone_cos
STAT_AGGREGATE=${WORK_DIR}/stats_aggregate
STAT_AGGREGATE_HISTORY=${WORK_DIR}/stats_aggregate_history
echo -n '' > ${RG_ZONE_COS_MAP}

#################################### Logs Utils ###################################

function log_to_file()
{
    if [[ -d ${WORK_DIR} ]] ; then
        echo -e "$*" >> ${WORK_DIR}/log
    fi
}

function LOG_INFO()
{
    echo -e "$*"
    log_to_file "[LOG] $(date '+%Y-%m-%dT%H:%M:%S') [INFO ] $* "
}

function LOG_DEBUG()
{
    [[ ${DEBUG_MODE} -eq 1 ]] && echo -e "\e[1;34m[DEBUG] $* \e[0m"
    log_to_file "[LOG] $(date '+%Y-%m-%dT%H:%M:%S') [DEBUG] $*"
}

function LOG_TRACE()
{
    [[ ${TRACE_MODE} -eq 1 ]] && echo -e "\e[1;34m[TRACE] $* \e[0m"
    log_to_file "\e[1;34m[LOG] $(date '+%Y-%m-%dT%H:%M:%S') [TRACE] $* \e[0m"
}

function LOG_ERROR()
{
    echo -e "\e[41;33;1m[ERROR] $* \e[0m"
    log_to_file "\e[41;33;1m[LOG] $(date '+%Y-%m-%dT%H:%M:%S') [ERROR] $* \e[0m"
}

function LOG_HIGHLIGHT()
{
    echo -e "\e[42;33;1m$*\e[0m"
    log_to_file "\e[42;33;1m[LOG] $(date '+%Y-%m-%dT%H:%M:%S') [INFO+] $* \e[0m"
}

################################# Output Utils ###################################

function print_info()
{
    echo -e "$*"
}

function print_error()
{
    echo -e "\e[41;33;1m$* \e[0m"
}

function print_highlight()
{
    echo -e "\e[42;33;1m$*\e[0m"
}

function print_format()
{
    printf "%-15s %15s %15s %15s %15s %15s %15s\n" "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}


################################# Output Utils ###################################

function format_print
{
    local key="$1"
    local value="$2"
    local size="$3"
    local time="$4"
    local highlight="$5" ## 0 or 1

    local line='-----------------------------------------------------------------------------------------------------------------'

    if  [[ ${key} == "SPLIT" ]] ; then
        echo ${line}

    else

        if [[ ${highlight} -eq 0 ]] ; then
            printf "| %50s | %15s | %15s | %20s |\n" "${key}" "${value}" "${size}" "${time}"
        else
            printf "\033[1;32;40m| %50s | %15s | %15s | %20s |\033[0m\n" "${key}" "${value}" "${size}" "${time}"
        fi
        echo ${line}
    fi
}

function print_title
{
    local key="$1"
    local value="$2"

    local line='-----------------------------------------------------------------------------------------------------------------'

    echo
    echo ${line}
    printf "\033[1;32;40m| %60s %48s |\033[0m\n" "${key}" "${value}"
    echo ${line}
}


################################ Utilitys #####################################

function get_version
{
    local version=$(sudo -i dockobj rpm -qa | awk -F '-' '/storageos-fabric-datasvcs/ {print $4}')
    #local version=$(sudo -i xdoctor --ecsversion |awk '/Object Version:/ {print $3}')
    echo ${version}
}


function get_local_vdc_info
{
    echo "Initializing, retrieving local VDC information ..."

    ECS_VERSION=$(get_version)

    REPL_IP=$(netstat -an | awk '/:9095.*LISTEN/{print $4}' | awk -F : '{print $1}')
    DATA_IP=$(netstat -an | awk '/:9020.*LISTEN/{print $4}' | awk -F : '{print $1}')
    MGMT_IP=$(netstat -an | awk '/:443.*LISTEN/{print $4}' | awk -F : '{print $1}')

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - REPL_IP: ${REPL_IP} DATA_IP: ${DATA_IP} MGMT_IP: ${MGMT_IP}"

    if [[ -z ${REPL_IP} || -z ${DATA_IP} || -z ${MGMT_IP} ]] ; then
        echo "Failed to get IPs"
        exit 0
    fi
    
    local SDS_TOKEN=$(curl -i -s -L --location-trusted -k https://${MGMT_IP}:4443/login -u emcmonitor:ChangeMe | grep X-SDS-AUTH-TOKEN)

    if [[ -z ${SDS_TOKEN} ]] ; then
        echo "Failed to get secret"
        exit 0
    fi

    local local_storage_pool_info=${WORK_DIR}/local_storage_pool_info
    curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/vdc/data-services/varrays" | xmllint --format - > ${local_storage_pool_info}
    COS=$(awk -F"[<|>|?]" '/id/ {print $3}' ${local_storage_pool_info})
    SP_NAME=$(awk -F"[<|>|?]" '/name/ {print $3}' ${local_storage_pool_info})

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - COS: ${COS} SP_NAME: ${SP_NAME}"

    if [[ -z ${COS} || -z ${SP_NAME} ]] ; then
        echo "Failed to get local_storage_pool_info"
        exit 0
    fi

    local local_vdc_info=${WORK_DIR}/local_vdc_info
    curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/object/vdcs/vdc/local"  | xmllint --format - > ${local_vdc_info}
    ZONE_ID=$(awk -F"[<|>|?]" '/vdcId/ {print $3}' ${local_vdc_info})
    VDC_NAME=$(awk -F"[<|>|?]" '/vdcName/ {print $3}' ${local_vdc_info})
    # REPL_IP=$(awk -F"[<|>|?]" '/interVdcCmdEndPoints/ {print $3}' ${local_vdc_info} | awk -F "," '{print $1}')
    # MGMT_IP=$(awk -F"[<|>|?]" '/managementEndPoints/ {print $3}' ${local_vdc_info} | awk -F "," '{print $1}')

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ZONE_ID: ${ZONE_ID} VDC_NAME: ${VDC_NAME}"

    if [[ -z ${ZONE_ID} || -z ${VDC_NAME} ]] ; then
        echo "Failed to get local_vdc_info"
        exit 0
    fi

    local replication_group_info=${WORK_DIR}/replication_group_info
    curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/vdc/data-service/vpools"  | xmllint --format - > ${replication_group_info}
    local rgs=$(awk -F"[<|>|?]" '/<id>/ {print $3}' ${replication_group_info})
    
    for rg in $(echo ${rgs})
        do
        curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/vdc/data-service/vpools/${rg}" | xmllint --format - > ${replication_group_info}.${rg}
        for zone in $(awk -F"[<|>|?]" '/<name>urn/ {print $3}' ${replication_group_info}.${rg})
            do
            if [[ ${zone} == ${ZONE_ID} ]] ; then
                REPLICATION_GROUP="${rg} ${REPLICATION_GROUP}"
                break
            fi
        done
    done

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - REPLICATION_GROUP->: ${REPLICATION_GROUP}"

    if [[ -z ${REPLICATION_GROUP} ]] ; then
        echo "Failed to get replication_group_info"
        exit 0
    fi

    #get all the nodes on this VDC
    # sudo -i getclusterinfo -a /tmp/machineall > /dev/null 2>&1

    sudo -i getrackinfo -c ${MACHINES_FILE}_tmp > /dev/null 2>&1
    if [[ $? -ne 0 ]] ; then
        echo "Failed to get machines"
        exit 0
    fi
    cat ${MACHINES_FILE}_tmp | grep -v '^#' | strings > ${MACHINES_FILE}
}


function query_counter
{
    local key="$1"

    local counter=$(cat ${STAT_AGGREGATE} | grep -i "\"id\"\ :\ \"${key}\"" -A5 | awk '/counter/ {print $3}' | sort | uniq | head -n1)
    #local counter=$(cat ${STAT_AGGREGATE} | grep "${key}" -A5 | awk '/counter/ {print $3}' | sort | uniq | head -n1)

    if [[ -z ${counter} ]] ; then
        echo "failed to get counter"
    fi

    echo ${counter}
}


function query_timestamp
{
    local key="$1"

    local counter=$(cat ${STAT_AGGREGATE} | grep -i "\"id\"\ :\ \"${key}\"" -A3 | awk '/timestamp/ {print $3}' | sort | uniq | head -n1)
    #local timestamp=$(cat ${STAT_AGGREGATE} | grep "${key}" -A3 | awk '/timestamp/ {print $3}' | sort | uniq | head -n1)

    if [[ -z ${timestamp} ]] ; then
        echo "failed to get timestamp"
    fi

    echo "${timestamp}"
}

function query_time
{
    local key="$1"

    local timestamp=$(query_timestamp "${key}")
    local time=$(date -d @${timestamp:0:10} '+%Y-%m-%d %H:%M:%S')

    echo "${time}"
}


####################################################################
####################################################################
####################################################################

function init_stats
{
    if [[ ! -r ${STAT_AGGREGATE} ]] ; then
        curl -sk https://${MGMT_IP}:4443/stat/aggregate > ${STAT_AGGREGATE} 
    fi

    local head=$(head -n1 ${STAT_AGGREGATE})
    if [[ "{" != ${head:0:1} ]] ; then
        echo "fail"
    else
        echo "success"
    fi
}


function init_stats_history
{
    echo -n "Getting aggregate_history ... "
    if [[ ! -r ${STAT_AGGREGATE_HISTORY} ]] ; then
        curl -ks https://${MGMT_IP}:4443/stat/aggregate_history > ${STAT_AGGREGATE_HISTORY}
    fi

    local head=$(head -n1 ${STAT_AGGREGATE_HISTORY})
    if [[ "{" != ${head:0:1} ]] ; then
        echo "fail"
    else
        echo "success"
    fi
}


function get_repo_gc_ongoing
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local gc_scan_task=${WORK_DIR}/CHUNK_GC_SCAN_STATUS_TASK.${ZONE_ID}.REPO
    curl -s "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${ZONE_ID}&type=REPO&time=0" | sed -e 's/\r//g' -e 's/^<.*<pre>//g' > ${gc_scan_task}
    local repo_gc_ongoing=$(grep -c schemaType ${gc_scan_task})

    # local delete_job=${WORK_DIR}/DELETE_JOB_TABLE_KEY.CLEANUP_JOB
    # curl -s "http://${DATA_IP}:9101/diagnostic/OB/0/DumpAllKeys/DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=xxx" | sed -e 's/\r//g' -e 's/^<.*<pre>//g' > ${delete_job}

    local head=$(head -n1 ${gc_scan_task})
    if [[ ${head:0:4} != "http" ]] ; then
        echo "Getting repo gc tasks ... Failed"
        return
    fi

    echo "On-going tasks: ${repo_gc_ongoing}"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_btree_gc_ongoing
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local gc_scan_task=${WORK_DIR}/CHUNK_GC_SCAN_STATUS_TASK.${ZONE_ID}.BTREE

    curl -s "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${ZONE_ID}&type=BTREE&time=0" | sed -e 's/\r//g' -e 's/^<.*<pre>//g' > ${gc_scan_task}

    local head=$(head -n1 ${gc_scan_task})
    if [[ ${head:0:4} != "http" ]] ; then
        echo "Getting btree gc tasks ... Failed"
        return
    fi

    local btree_gc_ongoing=$(grep -c schemaType ${gc_scan_task})

    echo "On-going tasks: ${btree_gc_ongoing}"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_repo_gc_history_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO"
}


function get_btree_gc_history_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO"
}


function get_repo_gc_history_from_log
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local files=''
    while read MACHINE; do
        #echo "Executing against MACHINE: $MACHINE"
        files="$(ssh -n $MACHINE "sudo docker exec object-main sh -c \"find /var/log -name cm-chunk-reclaim.log* -mtime -1 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null ")" 2>/dev/null
        # files="$(ssh -n $MACHINE "sudo docker exec object-main sh -c \"find /var/log -name cm-chunk-reclaim.log* -mtime -1 -exec echo -n \\\"{} \\\" \\\; \"")" 2>/dev/null
        ssh -n $MACHINE "sudo docker exec object-main sh -c \"zgrep RepoReclaimer.*successfully\ recycled\ repo ${files} | awk -F':' '{ print \\\$2 }'\"" > ${WORK_DIR}/history_reclaimed_repo-${MACHINE}.out 2>/dev/null &
    done < ${MACHINES_FILE}

    wait

    local repo_history=${WORK_DIR}/history_reclaimed_repo
    cat ${WORK_DIR}/history_reclaimed_repo-*.out | sed -e 's/ /T/g' | sort | uniq -c > ${repo_history}

    local line_cnt=$(wc -l ${repo_history} | awk '{print $1}')
    if [[ $line_cnt -eq 0 ]] ; then
        echo "There's no garbage reclaimed in past 24 hrs..."
        return
    else
        echo "GC history:"
    fi

    local now_date=$(date '+%Y-%m-%dT%H')

    for i in $(seq 1 ${line_cnt}); do
        local this_date=$(tail -n $i ${repo_history} | head -n1 | awk '{print $NF}')
        local range="$(date_minus ${now_date} ${this_date})"
        
        tail -n $i ${repo_history} | awk -v hr="$range" '{cnt+=$1} END{size=134217600*cnt/(1024*1024*1024); printf("  - In past %2s hrs, reclaimed %5d chunks, %7.2f GB\n", hr, cnt, size)}' 
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_btree_gc_history_from_log
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local files=''
    while read MACHINE; do
        #echo "Executing against MACHINE: $MACHINE"
        files="$(ssh -n $MACHINE "sudo docker exec object-main sh -c \"find /var/log -name cm-chunk-reclaim.log* -mtime -1 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null ")" 2>/dev/null
        # files="$(ssh -n $MACHINE "sudo docker exec object-main sh -c \"find /var/log -name cm-chunk-reclaim.log* -mtime -1 -exec echo -n \\\"{} \\\" \\\; \"")" 2>/dev/null
        ssh -n $MACHINE "sudo docker exec object-main sh -c \"zgrep Chunk.*reclaimed ${files} | grep ReclaimState | awk -F':' '{ print \\\$2 }'\"" > ${WORK_DIR}/history_reclaimed_btree-${MACHINE}.out 2>/dev/null &
    done < ${MACHINES_FILE}

    wait

    local btree_history=${WORK_DIR}/history_reclaimed_btree
    cat ${WORK_DIR}/history_reclaimed_btree-*.out | sed -e 's/ /T/g' | sort | uniq -c > ${btree_history}

    local line_cnt=$(wc -l ${btree_history} | awk '{print $1}')
    if [[ $line_cnt -eq 0 ]] ; then
        echo "There's no garbage reclaimed in past 24 hrs..."
        return
    else
        echo "GC history:"
    fi

    local now_date=$(date '+%Y-%m-%dT%H')

    for i in $(seq 1 ${line_cnt}); do
        local this_date=$(tail -n $i ${btree_history} | head -n1 | awk '{print $NF}')
        local range="$(date_minus ${now_date} ${this_date})"

        tail -n $i ${btree_history} | awk -v hr="$range" '{cnt+=$1} END{size=134217600*cnt/(1024*1024*1024); printf("  - In past %2s hrs, reclaimed %5d chunks, %7.2f GB\n", hr, cnt, size)}' 
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function date_minus
{
    # return date_a - date_b
    local date_a="$1"  # 2017-03-14T06:03:33.143002
    local date_b="$2"  # 2017-03-12T06:01:22.121

    local date_a_y=$(echo ${date_a:0:4})
    local date_a_m=$(echo ${date_a:5:2})
    local date_a_d=$(echo ${date_a:8:2})
    local date_a_h=$(echo ${date_a:11:2})

    local date_b_y=$(echo ${date_b:0:4})
    local date_b_m=$(echo ${date_b:5:2})
    local date_b_d=$(echo ${date_b:8:2})
    local date_b_h=$(echo ${date_b:11:2})
    
    local days_gap=`python -c "import datetime; date_a=datetime.datetime(year=int(\"${date_a_y}\"), month=int(\"${date_a_m}\"), day=int(\"${date_a_d}\"), hour=int(\"${date_a_h}\")); date_b=datetime.datetime(year=int(\"${date_b_y}\"), month=int(\"${date_b_m}\"), day=int(\"${date_b_d}\"), hour=int(\"${date_b_h}\")); print date_a-date_b"`

    echo "${days_gap}" | awk -F':' '{print $1}'
}


function get_repo_gc_remaining_from_dt
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO, there's no way figured out to check remaining REPO garbage in pre ECS 3.0.0"
}


function get_repo_gc_remaining_and_reclaimed_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # https://asdwiki.isus.emc.com:8443/display/ECS/Check+REPO+GC+Stats+in+Statistic+Framework

    local retval=$(init_stats)
    [[ "success" != ${retval} ]] && echo "Failed to get aggregate" && return 1

    local deleted_chunks_repo_count=$(query_counter "deleted_chunks_repo.TOTAL")
    local ec_freed_slots_count=$(query_counter "ec_freed_slots.TOTAL")
    local size_GB=$(echo "scale=3; ( ${deleted_chunks_repo_count}*134217600 + ${ec_freed_slots_count}*134217600/60 )/1073741824" | bc)
    local size_TB=$(echo "scale=6; ( ${deleted_chunks_repo_count}*134217600 + ${ec_freed_slots_count}*134217600/60 )/1099511627776" | bc)
    # echo "Reclaimed ${size_GB} GB ( ${size_TB} TB ) garbage since VDC was in 3.0 code base."
    printf "Reclaimed: %.3f GB (%.6f TB) garbage since VDC was in 3.0 code base.\n" ${size_GB} ${size_TB}

    local total_repo_garbage_size_B=$(query_counter "total_repo_garbage.TOTAL")
    local remaning_garbage_size_GB=$(echo "scale=3; ${total_repo_garbage_size_B}/1073741824" | bc)
    local remaning_garbage_size_TB=$(echo "scale=6; ${total_repo_garbage_size_B}/1099511627776" | bc)
    local full_reclaimable_repo_chunk_count=$(query_counter "full_reclaimable_repo_chunk.TOTAL")
    local remaning_partial_garbage_size_GB=$(echo "scale=3; ( ${total_repo_garbage_size_B} - ${full_reclaimable_repo_chunk_count}*134217600 )/1073741824" | bc)
    local remaning_partial_garbage_size_TB=$(echo "scale=6; ( ${total_repo_garbage_size_B} - ${full_reclaimable_repo_chunk_count}*134217600 )/1099511627776" | bc)

    # echo "Remaining garbage: ${remaning_garbage_size_GB} GB (${remaning_garbage_size_TB} TB), including partial garbage ${remaning_partial_garbage_size_GB} GB (${remaning_partial_garbage_size_TB} TB)"
    printf "Remaining garbage: %.3f GB (%.6f TB), including partial garbage %.3f GB (%.6f TB)\n" ${remaning_garbage_size_GB} ${remaning_garbage_size_TB} ${remaning_partial_garbage_size_GB} ${remaning_partial_garbage_size_TB}
    
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_btree_gc_remaining_from_gc_query
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # https://asdwiki.isus.emc.com:8443/display/ECS/Check+BTREE+GC+Progress#CheckBTREEGCProgress-ChecktotalBTREEGCgarbage

    local tmp=${WORK_DIR}/btreeUsage.${ZONE_ID}
    echo -n "" > ${tmp}

    for level in $(seq 1 2)
        do
        curl -s http://${DATA_IP}:9101/gc/btreeUsage/${COS}/${level} >> ${tmp}
    done

    # awk '!/^</' ${tmp} | awk -F',' 'BEGIN{garbage=0; partial_garbage=0; count=0; partial_count=0} {garbage+=134217600-$3; count++; if($3<6710880) {partial_garbage+=134217600-$3;partial_count++}} END{print "Remaining garbage: "garbage/(1024*1024*1024) "GB (including partial garbage "partial_garbage/(1024*1024*1024)" GB)"}'
    awk '!/^</' ${tmp} | awk -F',' 'BEGIN{garbage=0; partial_garbage=0; count=0; partial_count=0} {garbage+=134217600-$3; count++; if($3<6710880) {partial_garbage+=134217600-$3;partial_count++}} END{print "Remaining garbage: "garbage/(1024*1024*1024) " GB ("garbage/(1024*1024*1024*1024)" TB), including partial garbage "partial_garbage/(1024*1024*1024)" GB ("partial_garbage/(1024*1024*1024*1024)" TB)"}'

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_btree_gc_remaining_from_dt
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO"
}


function get_btree_gc_remaining_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO, this will be implemented when stats supports Btree GC"
}

#########################################################################
#########################################################################
#########################################################################
#########################################################################


function repo_gc_summary
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo "==== REPO GC Summary ===="

    ## get remaining garbage
    if [[ ${ECS_VERSION:0:1} -ge 3 ]] ; then
        get_repo_gc_remaining_and_reclaimed_from_stats &
    else
        get_repo_gc_remaining_from_dt &
    fi

    ## get ongoing gc tasks
    get_repo_gc_ongoing &

    ## get gc progress/history
    if [[ ${ECS_VERSION:0:1} -ge 3 ]] ; then
        # get_repo_gc_history_from_stats &
        get_repo_gc_history_from_log &
    else
        get_repo_gc_history_from_log &
    fi

    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_summary
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo "==== Btree GC Summary ===="

    ## get remaining garbage
    if [[ ${ECS_VERSION:0:1} -ge 4 ]] ; then
        get_btree_gc_remaining_from_stats &
    else
        if [[ ${ECS_VERSION:0:1} -ge 3 ]] ; then
            get_btree_gc_remaining_from_gc_query &
        else
            # get_btree_gc_remaining_from_dt
            get_btree_gc_remaining_from_gc_query &
        fi
    fi

    ## get ongoing gc tasks
    get_btree_gc_ongoing &

    ## get gc progress/history
    if [[ ${ECS_VERSION:0:1} -ge 4 ]] ; then
        # get_btree_gc_history_from_stats &
        get_btree_gc_history_from_log &
    else
        get_btree_gc_history_from_log &
    fi

    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function clean_up_work_dir
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - start"

    if [[ -d ${WORK_DIR} ]] ; then
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up working diretory"
        rm -rf ${WORK_DIR}
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - end"
}


function clean_up_process
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - start"

    local pgids=$(ps -e -o pgid,cmd | grep "sh -c zgrep.*/var/log/cm-chunk-reclaim.log" | grep -v '[0-9] grep' | awk '{print $1}' | sort | uniq)
    for pgid in ${pgids}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up sub process group ${pgid} of '${SCRIPTNAME}' ..."
        sudo kill -9 -${pgid}
    done

    if [[ ! -z ${SCRIPTNAME} ]] ;then
        pgids=$(ps -e -o pgid,cmd | grep "${SCRIPTNAME}" | grep -v grep | awk '{print $1}' | sort | uniq)
        for pgid in ${pgids}
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up process group ${pgid} of '${SCRIPTNAME}' ..."
            sudo kill -9 -${pgid}
        done
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - end"
}


function clean_up
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - start"

    clean_up_work_dir
    clean_up_process

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - end"
}

########################## Main logic ##############################

trap clean_up SIGINT

echo
echo "${SCRIPTNAME} version ${VERSION}"
echo

## Initialize globals
get_local_vdc_info

echo "Start: $(date '+%Y-%m-%d %H:%M:%S')"
echo

## Start real works
if [[ ${CHECK_REPO_GC} -eq 1 ]] ; then
    repo_gc_summary
    echo
fi

if [[ ${CHECK_BTREE_GC} -eq 1 ]] ; then
    btree_gc_summary
    echo
fi

# [[ ${PARTIAL_GC_ENABLED} -eq 1 ]] && get_partial_gc_from_dt

echo "End:   $(date '+%Y-%m-%d %H:%M:%S')"
echo

clean_up_work_dir


########################## Main logic END ##############################