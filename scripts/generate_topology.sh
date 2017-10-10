#!/bin/bash


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

function cleanup()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"

    rm -f ${F_RG_ZONESTORE_MAPPING} ${F_RG_ZONE_COS_MAPPING}

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - END"
}


function target_reachable()
{
    local ip=$1
    ping ${ip} -c1 > /dev/null
    if [[ $? -ne 0 ]] ; then
        echo "no"
        return 1
    fi

    echo "yes"
    return 0
}


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


function get_all_data_ips()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"

    local data_ip=$1
    #local ecs_version_head=$2

    curl -s http://${data_ip}:9101/paxos/namespaces | awk '/reading/ {vdc=$4; ip=$6; vdc_ip[vdc]=ip} END{for (item in vdc_ip) {print item,vdc_ip[item]}}' > ${F_ZONE_REPLICATIONIP_MAPPING}

    cat ${F_ZONE_REPLICATIONIP_MAPPING} | while read zone_id node_repl_ip
        do

        if [[ -r ${F_HOST_FILE} ]] ; then
            # Query configuration file to get all node data IPs, which is a better way.

            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Query configuration file to get all node data IPs from zone ${zone_id}"
            ssh ${node_repl_ip} -n "cat ${F_HOST_FILE}" | sed -rne "s/^.*\"data_ip\"\s*:\s*\"([a-z0-9\.\-]+)\".*$/\1/p" > ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.${zone_id}

        else
            # Query PR DT to get all node data IPs.

            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Query PR table to get all node data IPs from zone ${zone_id}"
            local node_data_ip=$(ssh ${node_repl_ip} -n "netstat -an | grep ':9020'" | awk '/LISTEN/{print $4}' | awk -F : '{print $1}')
            if [[ -z ${node_data_ip} ]] ; then
                sleep 8
                node_data_ip=$(ssh ${node_repl_ip} -n "netstat -an | grep ':9101'" | awk '/LISTEN/{print $4}' | awk -F : '{print $1}')     
            fi

            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - node_repl_ip:${node_repl_ip} node_data_ip:${node_data_ip}"
            ssh -n ${node_repl_ip} "curl -s http://${node_data_ip}:9101/diagnostic/PR/2/" | xmllint --format - | sed -nre 's$^.*<owner_ipaddress>([a-z0-9\.\-]+)</owner_ipaddress>$\1$p' | sort | uniq > ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.${zone_id}
        fi

    done

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_rg_zone_cos_mapping()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"

    local data_ip=$1

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
            echo "${rg_id} ${zone_info_store}" >> ${F_RG_ZONESTORE_MAPPING}
            i=0
            continue
        fi
        i=$((${i}+1))
    done


    cat ${F_RG_ZONESTORE_MAPPING}  | while read rg_id zone_store
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


function get_zone_cos_dataip_mapping()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo -n "" > ${F_ZONE_COS_DATAIP_MAPPING}
    cat ${F_RG_ZONE_COS_MAPPING} | awk '{print $2,$3}' | sort | uniq | while read zone_id cos_id
        do
        local a_node_data_ip=$(head -n1 ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.${zone_id})
        echo ${zone_id} ${cos_id} ${a_node_data_ip} >> ${F_ZONE_COS_DATAIP_MAPPING}
    done
 
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - END"
}


function report()
{
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    echo "-------------------------------------- Replication Groups Details --------------------------------------"
    echo "Replication Group(s):"
    for rg_id in $(awk '{print $1}' ${F_RG_ZONE_COS_MAPPING} | sort | uniq)
        do
        local zone_cnt_in_rg=$(grep ${rg_id} ${F_RG_ZONE_COS_MAPPING} -c)
        echo -e "|---- ${rg_id} contains ${zone_cnt_in_rg} StoragePool(s):"
        grep ${rg_id} ${F_RG_ZONE_COS_MAPPING} | while read rg_id zone_id cos_id
            do
            echo -e "|---------- ${zone_id} - ${cos_id}"
        done
        echo "|"
    done

    echo
    echo "--------------------------------------------- VDCs Details ---------------------------------------------"
    echo "VDC(s):"
    for zone_id in $(ls ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.* | awk -F '.' '{print $NF}' | sort | uniq )
        do
        local node_cnt_in_vdc=$(wc -l ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.${zone_id} | awk '{print $1}')
        echo -e "|---- ${zone_id} contains ${node_cnt_in_vdc} Nodes (sorted by data IP):"
        local i=0
        change_line_num=$(cat ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.${zone_id} | wc -l | awk '{print $1}')
        [[ ${change_line_num} -gt 8 ]] && change_line_num=8
        for ip in $(cat ${F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX}.${zone_id})
            do
            [[ ${i} -eq 0 ]] && echo -en "|---------- "
            i=$((${i}+1))
            echo -n "${ip}  "
            [[ ${i} -eq ${change_line_num} ]] && i=0 && echo
        done
        echo "|"
    done
    echo

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - END"
}


#################################################
################# main logic ####################

#set -e

echo "[LIMITAION]: Only support the VDCs that contain only 1 Storage Pool, otherwise script might output wrong result or abort with corruption, please go to ECS Portal of every VDCs to get correct topology."


DEBUG_MODE=$1

current_user=$(whoami)
[[ ${current_user} != "admin" ]] &&  LOG_ERROR "line:${LINENO} ${FUNCNAME[0]} - Must run with admin role outside container." && exit 0

#WORK_DIR=/var/tmp
#OUTPUT_FILE_PREFIX=${WORK_DIR}/topology
OUTPUT_FILE_PREFIX=~/topology
F_ZONE_REPLICATIONIP_MAPPING=${OUTPUT_FILE_PREFIX}.zone_replicationip_mapping
F_ALL_NODE_DATA_IP_OF_ZONE_PREFIX=${OUTPUT_FILE_PREFIX}.MACHINES.public_data_IPs_VDC #.${zone_id}
F_ZONE_COS_DATAIP_MAPPING=${OUTPUT_FILE_PREFIX}.zone_cos_dataip_mapping  ## as input of verifyFailedChunk.py 
F_RG_ZONESTORE_MAPPING=${OUTPUT_FILE_PREFIX}.rg_zongstore_mapping
F_RG_ZONE_COS_MAPPING=${OUTPUT_FILE_PREFIX}.rg_zone_cos_mapping
F_HOST_FILE=/opt/emc/caspian/fabric/agent/services/object/main/host/files/config_cluster_network.json

ecs_version=$(sudo -i docker exec object-main sh -c 'rpm -qa |grep storageos-fabric-datasvcs')
[[ -z $ecs_version ]] && LOG_ERROR "line:${LINENO} ${FUNCNAME[0]} - Failed to get ECS version."
echo
echo "ecs_version is ${ecs_version}"

#ecs_version_head=$((${ecs_version:15:1}+0))
#LOG_DEBUG "ecs_version_head is ${ecs_version_head}"

data_ip=$(get_one_data_ip_from_local_zone)
[[ -z ${data_ip} ]] && LOG_ERROR "line:${LINENO} ${FUNCNAME[0]} - Failed to get a node data IP." && exit 0
LOG_DEBUG "data_ip is ${data_ip}"

get_all_data_ips ${data_ip}

get_rg_zone_cos_mapping ${data_ip}

get_zone_cos_dataip_mapping

report

cleanup

trap cleanup SIGINT

### END
