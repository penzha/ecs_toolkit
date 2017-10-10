#!/bin/bash   
####################################################################

OUTPUT_FILE_PREFIX=/var/tmp/gc
F_RG_ZONE_COS_MAPPING=${OUTPUT_FILE_PREFIX}.rg_zone_cos_mapping
F_ZONE_REPLIP_DATAIP_MAPPING=${OUTPUT_FILE_PREFIX}.zone_replip_dataip_mapping
F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING=${OUTPUT_FILE_PREFIX}.rg_zone_cos_replip_dataip_mapping

F_HOST_FILE=/opt/emc/caspian/fabric/agent/services/object/main/host/files/config_cluster_network.json

PARTIAL_GC_ENABLED=0 # TBD

MGMT_IP=$(hostname -i)
STAT_AGGREGATE="$(curl -sk https://${MGMT_IP}:4443/stat/aggregate)"

###################################################################
########################## logging ################################

function LOGGER()
{
    if [[ -d ${WORK_DIR} ]] ; then
        echo -e "[LOG] $(date '+%Y-%m-%d %H:%M:%S') $* " >> ${WORK_DIR}/log
    fi
    echo -e "[LOG] $(date '+%Y-%m-%d %H:%M:%S') $* "
}

function LOG_DEBUG()
{
    [[ ${DEBUG_MODE} -eq 1 ]] && LOGGER "\e[1;34m[DEBUG] - $* \e[0m"
}

function LOG_INFO()
{
    LOGGER "[INFO ] - $* "
}

function LOG_ERROR()
{
    LOGGER "\e[41;33;1m[ERROR] - $* \e[0m"
}

function LOG_HIGHLIGHT()
{
    LOGGER "\e[42;33;1m[INFOP] - $* \e[0m"
}

########################## logging end ############################
###################################################################

function get_one_data_ip_from_local_zone()
{
    local data_ip=''

    if [[ -r ${F_HOST_FILE} ]] ; then
        data_ip=$(cat ${F_HOST_FILE} 2> /dev/null | sed -rne "s/^.*\"data_ip\"\s*:\s*\"([a-z0-9\.\-]+)\".*$/\1/p" | head -n1)

    else
        data_ip=$(netstat -an | awk '/:9020.*LISTEN/{print $4}' | awk -F : '{print $1}')
        if [[ -z ${data_ip} ]] ; then
            sleep 8
            data_ip=$(netstat -an | awk '/:9101.*LISTEN/{print $4}' | awk -F : '{print $1}')     
        fi
    fi

    echo "${data_ip}"
}


function get_rg_zone_cos_mapping()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"

    local data_ip=$1
    local tmp=/var/tmp/rg_zongstore_mapping
    
    echo -n "" > ${tmp}
    echo -n "" > ${F_RG_ZONE_COS_MAPPING}

    local i=0
    curl -s http://${data_ip}:9101/diagnostic/RT/0/DumpAllKeys/REP_GROUP_KEY?showvalue=gpb | grep -B1 'schemaType REP_GROUP_KEY rgId urn:storageos:ReplicationGroupInfo:' | sed 's/\r//g' | while read line
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - +++++++++++++${i} line: ${line}"
        [[ "${line:0:1}" == "-" ]] && continue
        if [[ ${i} -eq 0 ]] ; then
            local zone_info_store=$(echo ${line} | awk -F '"' '/urn:storageos:OwnershipInfo:[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/')
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${i} zone_info_store: ${zone_info_store}"
            [[ -z ${zone_info_store} ]] && LOG_ERROR "[ERROR] line:${LINENO} ${FUNCNAME[0]} - unexpected zone_info_store format !" && break
        elif [[ ${i} -eq 1 ]] ; then
            local rg_id=$(echo ${line} | awk '/^schemaType REP_GROUP_KEY rgId urn:storageos:ReplicationGroupInfo:[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/ {print $4}')
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${i} rg_id: ${rg_id}"
            [[ -z ${rg_id} ]] && LOG_ERROR "[ERROR] line:${LINENO} ${FUNCNAME[0]} - unexpected rg_id format !" && break
            echo "${rg_id} ${zone_info_store}" >> ${tmp}
            i=0
            continue
        fi
        i=$((${i}+1))
    done


    cat ${tmp} | while read rg_id zone_store
        do
        local i=0
        curl -s "${zone_store}" | sed 's/^<.*<pre>//' | grep VirtualArray -B1 | while read line
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - +++++++++++++${i} line: ${line}"
            [[ "${line:0:1}" == "-" ]] && continue
            if [[ ${i} -eq 0 ]] ; then
                zone_id=$(echo ${line} | awk -F '"' '/urn:storageos:VirtualDataCenterData:[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/ {print $2}' | awk -F 'urn' '{print "urn"$2}')
                LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${i} zone_id: ${zone_id}"
                [[ -z ${zone_id} ]] && LOG_ERROR "[ERROR] line:${LINENO} ${FUNCNAME[0]} - unexpected zone_id format !" && break
            elif [[ ${i} -eq 1 ]] ; then
                cos_id=$(echo ${line} | awk -F '"' '/urn:storageos:VirtualArray:[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/ {print $2}' | awk -F 'urn' '{print "urn"$2}')
                LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${i} cos_id: ${cos_id}"
                [[ -z ${cos_id} ]] && LOG_ERROR "[ERROR] line:${LINENO} ${FUNCNAME[0]} - unexpected cos_id format !" && break
                echo "${rg_id} ${zone_id} ${cos_id}" >> ${F_RG_ZONE_COS_MAPPING}
                i=0
                continue
            fi
            i=$((${i}+1))
        done
    done

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_zone_cos_replip_mapping()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"
    
    local data_ip=$1 
    local node_data_ip=''
    
    echo -n "" > ${F_ZONE_REPLIP_DATAIP_MAPPING}
    local tmp=/var/tmp/zone_replip_mapping

    curl -s http://${data_ip}:9101/paxos/namespaces | awk '/reading/ {vdc=$4; ip=$6; vdc_ip[vdc]=ip} END{for (item in vdc_ip) {print item,vdc_ip[item]}}' | sed -e 's/\r//g' > ${tmp}

    cat ${tmp} | while read zone_id node_repl_ip
        do

        if [[ -r ${F_HOST_FILE} ]] ; then
            # Query configuration file to get all node data IPs, which is a better way.

            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Query configuration file to get all node data IPs from zone ${zone_id}"
            node_data_ip=$(ssh ${node_repl_ip} -n "cat ${F_HOST_FILE}" | sed -rne "s/^.*\"data_ip\"\s*:\s*\"([a-z0-9\.\-]+)\".*$/\1/p" | head -n1 | sed -e 's/\r//g')

        else
            # Query PR DT to get all node data IPs.

            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Query PR table to get all node data IPs from zone ${zone_id}"
            node_data_ip=$(ssh ${node_repl_ip} -n "netstat -an | grep ':9020'" | awk '/LISTEN/{print $4}' | awk -F : '{print $1}')

        fi

        if [[ -z ${node_data_ip} ]] ; then
            sleep 8
            node_data_ip=$(ssh ${node_repl_ip} -n "netstat -an | grep ':9101'" | awk '/LISTEN/{print $4}' | awk -F : '{print $1}')     
        fi

        echo "${zone_id} ${node_repl_ip} ${node_data_ip}" >> ${F_ZONE_REPLIP_DATAIP_MAPPING}

    done
 
    
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_rg_zone_cos_replip_dataip_mapping
{

    echo -n "" > ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING}

    cat ${F_RG_ZONE_COS_MAPPING} | while read rg_id zone_id cos_id
        do

        grep "${zone_id}" ${F_ZONE_REPLIP_DATAIP_MAPPING} | while read zone_id repl_ip data_ip
            do
            echo "${rg_id} ${zone_id} ${cos_id} ${repl_ip} ${data_ip}" >> ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING}
        done
    done


}

function get_multi_info
{
    local data_ip=$1

    get_rg_zone_cos_mapping ${data_ip} 
    get_zone_cos_replip_mapping ${data_ip} 
    get_rg_zone_cos_replip_dataip_mapping
}

function get_version
{
    local version=$(sudo -i dockobj rpm -qa | awk -F '-' '/storageos-fabric-datasvcs/ {print $4}')
    #local version=$(sudo -i xdoctor --ecsversion |awk '/Object Version:/ {print $3}')
    echo ${version}
}

ECS_VERSION=$(get_version)

function query_counter
{
    local key="$1"

    local counter=$(echo "${STAT_AGGREGATE}" | grep "${key}" -A5 | awk '/counter/ {print $3}' | sort | uniq | head -n1)

    if [[ -z ${counter} ]] ; then
        echo "failed to get counter"
    fi

    echo ${counter}
}


function query_timestamp
{
    local key="$1"

    local timestamp=$(echo "${STAT_AGGREGATE}" | grep "${key}" -A3 | awk '/timestamp/ {print $3}' | sort | uniq | head -n1)

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

function query_size
{
    local value="$1"
    local devide_sixty=$2 # 0 or 1
    
    local size_B=0

    if [[ ${devide_sixty} -eq 0 ]] ; then
        size_B=$(( ${value}*(128*1024*1024-128) ))

    elif [[ ${devide_sixty} -eq 1 ]] ; then
        size_B=$(( ${value}*(128*1024*1024-128)/60 ))

    else
        echo "[ERROR] Wrong option, exit!"
        exit 0
    fi
    
    local size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    
    echo "${size_TB}"
}

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
        return
    else
        echo ${line}
        if [[ ${highlight} -eq 0 ]] ; then
            printf "| %50s | %15s | %15s | %20s |\n" "${key}" "${value}" "${size}" "${time}"
        else
            printf "\033[1;32;40m| %50s | %15s | %15s | %20s |\033[0m\n" "${key}" "${value}" "${size}" "${time}"
        fi

    fi
}

####################################################################

function gc_summary_repo_stats
{
    local key=''
    local size_B=0

    echo "RERO GC status from Statistic Framework:"
    format_print "Items" "Value" "Size in TB" "Timestamp"

    ####### 1. Total reclaimed chunks #########
    ## How many garbage reclaimed so far (after 3.0)

    format_print "SPLIT"

    key="deleted_chunks_repo"
    local deleted_chunks_repo=$(query_counter "${key}")
    local deleted_chunks_repo_time=$(query_time "${key}")
    local deleted_chunks_repo_size_TB=$(query_size "${deleted_chunks_repo}" 0)
    format_print "deleted_chunks_repo" "${deleted_chunks_repo}" "${deleted_chunks_repo_size_TB}" "${deleted_chunks_repo_time}"

    key="ec_freed_slots"
    local ec_freed_slots=$(query_counter "${key}")
    local ec_freed_slots_time=$(query_time "${key}")
    local ec_freed_slots_size_TB=$(query_size "${ec_freed_slots}" 1)
    format_print "ec_freed_slots" "${ec_freed_slots}" "${ec_freed_slots_size_TB}" "${ec_freed_slots_time}"

    local reclaimed_size_TB=0
    size_B=$(( ${deleted_chunks_repo}*(128*1024*1024-128) + ${ec_freed_slots}*(128*1024*1024-128)/60 ))
    reclaimed_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    format_print "Total reclaimed size" "-" "${reclaimed_size_TB}" "-" "1"


    ####### 2. Garbage Pending by EC Re-encode #########
    # No need to check total_ec_free_slots if partial 
    # gc is never enabled

    format_print "SPLIT"

    key="total_ec_free_slots"
    local total_ec_free_slots=$(query_counter "${key}")
    local total_ec_free_slots_time=$(query_time "${key}")
    local size_pending_ec_re_encode_TB=$(query_size "${total_ec_free_slots}" 1)
    format_print "total_ec_free_slots" "${total_ec_free_slots}" "${size_pending_ec_re_encode_TB}" "${total_ec_free_slots_time}"
    format_print "Garbage Pending by EC Re-encode" "-" "${size_pending_ec_re_encode_TB}" "-" "1"


    ####### 3. Garbage Pending by XOR Shipping #########
    # No need to check slots_waiting_shipping if partial
    # gc is never enabled

    format_print "SPLIT"

    key="slots_waiting_shipping"
    local slots_waiting_shipping=$(query_counter "${key}")
    local slots_waiting_shipping_time=$(query_time "${key}")
    local size_pending_XOR_shipping_TB=$(query_size "${slots_waiting_shipping}" 1)
    format_print "slots_waiting_shipping_time" "${slots_waiting_shipping}" "${size_pending_XOR_shipping_TB}" "${slots_waiting_shipping_time}"
    format_print "Garbage Pending by XOR Shipping" "-" "${size_pending_XOR_shipping_TB}" "-" "1"


    ####### 4. Garbage Pending in GC Verification #########

    format_print "SPLIT"

    key="full_reclaimable_repo_chunk"
    local full_reclaimable_repo_chunk=$(query_counter "${key}")
    local full_reclaimable_repo_chunk_time=$(query_time "${key}")
    local full_reclaimable_repo_chunk_size_TB=$(query_size "${full_reclaimable_repo_chunk}" 0)
    format_print "full_reclaimable_repo_chunk" "${full_reclaimable_repo_chunk}" "${full_reclaimable_repo_chunk_size_TB}" "${full_reclaimable_repo_chunk_time}"

    key="slots_waiting_verification"
    local slots_waiting_verification=$(query_counter "${key}")
    local slots_waiting_verification_time=$(query_time "${key}")
    local slots_waiting_verification_size_TB=$(query_size "${slots_waiting_verification}" 1)
    format_print "slots_waiting_verification" "${slots_waiting_verification}" "${slots_waiting_verification_size_TB}" "${slots_waiting_verification_time}"

    key="full_reclaimable_aligned_chunk"
    local full_reclaimable_aligned_chunk=$(query_counter "${key}")
    local full_reclaimable_aligned_chunk_time=$(query_time "${key}")
    local full_reclaimable_aligned_chunk_size_TB=$(query_size "${full_reclaimable_aligned_chunk}" 0)
    format_print "full_reclaimable_aligned_chunk" "${full_reclaimable_aligned_chunk}" "${full_reclaimable_aligned_chunk_size_TB}" "${full_reclaimable_aligned_chunk_time}"

    local pending_gc_verification_size_TB=0
    if [[ ${PARTIAL_GC_ENABLED} -ne 1 ]] ; then

        pending_gc_verification_size_TB=${full_reclaimable_repo_chunk_size_TB}
    else
        if [[ ${ECS_VERSION:0:1} -ge 3 ]] ; then

            pending_gc_verification_size_TB=${slots_waiting_verification_size_TB}
        else
            pending_gc_verification=$(( ${full_reclaimable_repo_chunk} - ${full_reclaimable_aligned_chunk} ))
            pending_gc_verification_size_TB=$(query_size "${pending_gc_verification}" 0)

            #size_B=$(( (${full_reclaimable_repo_chunk} - ${full_reclaimable_aligned_chunk})*(128*1024*1024-128) ))
            #pending_gc_verification_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
        fi
    fi
    format_print "Garbage Pending in GC Verification" "-" "${pending_gc_verification_size_TB}" "-" "1"


    ####### 5. Size of non-reclaimed garbage GC is aware of #########

    format_print "SPLIT"

    key="total_repo_garbage"
    local total_repo_garbage=$(query_counter "${key}")
    local total_repo_garbage_time=$(query_time "${key}")
    #local total_repo_garbage_size_TB=$(query_size "${total_repo_garbage}" 1)
    size_B=${total_repo_garbage}
    local total_repo_garbage_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    format_print "total_repo_garbage" "${total_repo_garbage}" "${total_repo_garbage_size_TB}" "${total_repo_garbage_time}"

    size_B=$(( ${total_repo_garbage} - ${ec_freed_slots}*(128*1024*1024-128)/60 ))
    local aware_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    format_print "Size of non-reclaimed garbage GC is aware of" "-" "${aware_size_TB}" "-" "1"

    ####### 6. Size of non-reclaimed garbage that GC cannot start #########

    size_B=$(( ${total_repo_garbage} - (${ec_freed_slots}+${total_ec_free_slots}+${slots_waiting_shipping}+${slots_waiting_verification})*(128*1024*1024-128)/60 - (${full_reclaimable_repo_chunk}-${full_reclaimable_aligned_chunk})*(128*1024*1024-128) ))
    local cannot_start_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    format_print "Size of non-reclaimed garbage that GC cannot start"  "-" "${cannot_start_size_TB}" "-" "1"

    format_print "SPLIT"
}

function repo_gc_stuck
{
    local f_check_ob_cmd=/var/tmp/cleanup_job_command.sh
    local f_check_ob=/var/tmp/cleanupjob.tmp

    curl -s "http://${DATA_IP}:9101/diagnostic/OB/0/" | xmllint --format - | awk -F"[<|>|?]" '/table_detail_link/ {print "echo \""$3"\"\n""curl -L \""$3"DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aa&maxkeys=1&useStyle=raw\""}' > ${f_check_ob_cmd}
    sh ${f_check_ob_cmd} > ${f_check_ob}

    
    
    
}

function get_partial_gc_from_dt
{
    echo "Partial GC status from DTs:"
    format_print "Items" "Value" "Size in TB" "Timestamp"

    local f_check_rr_cmd=/var/tmp/check_rr_command.sh
    local f_check_rr=/var/tmp/check_rr.tmp

    curl -s "http://${DATA_IP}:9101/diagnostic/RR/0/" | xmllint --format - | awk -F"[<|>|?]" '/table_detail_link/{print "echo \""$3"\"\n""curl -sL \""$3"REPO_REFERENCE_COLLECTOR_KEY?showvalue=gpb\""}' > ${f_check_rr_cmd}
    sh ${f_check_rr_cmd} > ${f_check_rr}

    # Total:
    local total_garbage=$(awk 'BEGIN {sum=0} /repoUsageSize/{if($2<134217600){sum+=(134217600-$2)}} END{print sum}' ${f_check_rr})
    local total_garbage_size_TB=$(echo "scale=6; ${total_garbage}/(1024*1024*1024*1024)" | bc)
    
    # Full reclaimable:
    local reclaimable_garbage=$(grep -A4 "reclaimable: TRUE" ${f_check_rr} | awk 'BEGIN {sum=0} /repoUsageSize/{if($2<134217600){sum+=(134217600-$2)}} END{print sum}')
    local reclaimable_garbage_size_TB=$(echo "scale=6; ${reclaimable_garbage}/(1024*1024*1024*1024)" | bc)

    # Partial:
    local partail_garbage=$(grep -A4 "reclaimable: FALSE" ${f_check_rr} | awk 'BEGIN {sum=0} /repoUsageSize/{if($2<134217600){sum+=(134217600-$2)}} END{print sum}')
    local partail_garbage_size_TB=$(echo "scale=6; ${partail_garbage}/(1024*1024*1024*1024)" | bc)
    
    format_print "SPLIT"
    format_print "total_garbage" "${total_garbage}" "${total_garbage_size_TB}" "-"
    format_print "reclaimable_garbage" "${reclaimable_garbage}" "${reclaimable_garbage_size_TB}" "-"
    format_print "partail_garbage" "${partail_garbage}" "${partail_garbage_size_TB}" "-"

    format_print "SPLIT"
}




function get_btree_gc_total
{
    local repl_ip=$1
    local data_ip=$2
    local rg_id=$3
    local cos=$4
    local level=$5
  
    echo "Btree GC status from DT for cos ${cos} level ${level}"
    format_print "SPLIT"
    # get_btree_gc_total
    local tmp=/var/tmp/btreeUsage.${cos}.${level}
    
    #echo "ssh ${repl_ip} -n curl -s http://${data_ip}:9101/gc/btreeUsage/${cos}/${level}"

    ssh ${repl_ip} -n curl -s http://${data_ip}:9101/gc/btreeUsage/${cos}/${level} > ${tmp}

    #local get_btree_gc_total=$(grep ${rg_id} ${tmp} | awk -F',' 'BEGIN{garbage=0; partialGarbage=0; count=0; partialCount=0} {garbage+=134217600-$3; count++; if($3<6710880) {partialGarbage+=134217600-$3;partialCount++}} END{print "garbage:"garbage", partialGarbage:"partialGarbage", count:"count", partialCount:"partialCount}')
    
    local get_btree_gc_total=$(cat ${tmp} | awk -F',' 'BEGIN{garbage=0; partialGarbage=0; count=0; partialCount=0} {garbage+=134217600-$3; count++; if($3<6710880) {partialGarbage+=134217600-$3;partialCount++}} END{print "garbage:"garbage", partialGarbage:"partialGarbage", count:"count", partialCount:"partialCount}')

    local btree_garbage_count=$(echo ${get_btree_gc_total} | awk -F ',' '{print $3}' | awk -F ':' '{print $2}')
    local size_B=$(echo ${get_btree_gc_total} | awk -F ',' '{print $1}' | awk -F ':' '{print $2}')
    local btree_garbage_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    format_print "total_btree_garbage" "${btree_garbage_count}" "${btree_garbage_size_TB}" "-"

    local btree_garbage_partial_count=$(echo ${get_btree_gc_total} | awk -F ',' '{print $4}' | awk -F ':' '{print $2}')
    size_B=$(echo ${get_btree_gc_total} | awk -F ',' '{print $2}' | awk -F ':' '{print $2}')
    local btree_garbage_partial_garbage_size_TB=$(echo "scale=6; ${size_B}/(1024*1024*1024*1024)" | bc)
    format_print "total_partial_garbage" "${btree_garbage_partial_count}" "${btree_garbage_partial_garbage_size_TB}" "-"
    
    format_print "SPLIT"
    
}

function get_btree_gc_ongoing
{
    local repl_ip=$1
    local data_ip=$2
    local rg_id=$3

    format_print "SPLIT"
    echo "Btree GC On-going Tasks from DT for RG ${rg_id}"
    # get_btree_gc_ongoing
    local tmp=/var/tmp/CHUNK_GC_SCAN_STATUS_TASK

    #echo "ssh ${repl_ip} -n curl -s http://${data_ip}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${rg_id}&type=BTREE&time=0"

    ssh ${repl_ip} -n curl -s "http://${data_ip}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${rg_id}&type=BTREE&time=0" > ${tmp}
    local btree_gc_ongoing=$(grep -c schemaType ${tmp})
    format_print "btree_gc_ongoing" "${btree_gc_ongoing}" "-" "-"

    format_print "SPLIT"
}

DATA_IP=$(get_one_data_ip_from_local_zone)

gc_summary_repo_stats

[[ -f ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} ]] || get_multi_info ${DATA_IP} 

awk '{print $3}' ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | sort | uniq | while read cos
    do

    repl_ip=$(grep ${cos} ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | awk '{print $4}'| head -n1)
    data_ip=$(grep ${cos} ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | awk '{print $5}'| head -n1)
    rg_id=$(grep ${cos} ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | awk '{print $1}'| head -n1)

    get_btree_gc_total ${repl_ip} ${data_ip} ${rg_id} ${cos} 2
    get_btree_gc_total ${repl_ip} ${data_ip} ${rg_id} ${cos} 1

done


awk '{print $1}' ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | sort | uniq | while read rg_id
    do

    repl_ip=$(grep ${rg_id} ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | awk '{print $4}'| head -n1)
    data_ip=$(grep ${rg_id} ${F_RG_ZONE_COS_REPLIP_DATAIP_MAPPING} | awk '{print $5}'| head -n1)

    get_btree_gc_ongoing ${repl_ip} ${data_ip} ${rg_id}

done


[[ ${PARTIAL_GC_ENABLED} -eq 1 ]] && get_partial_gc_from_dt


# checking if gc is stuck
# RR table to check status , showgpb to check schedule count, if it's to big, then yes stuck