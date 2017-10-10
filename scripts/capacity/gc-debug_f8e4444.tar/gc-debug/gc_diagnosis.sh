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
# 0.5.0 - Initial version, for EE/Dev only
# 0.6.0 -
# 0.7.0 -
# 0.9.0 -
# 1.0.0 -
##########################################################################

# Author:  Alex Wang (alex.wang2@emc.com)

VERSION="0.5.0"
SCRIPTNAME="$(basename $0)"

######################################################## Utilitys ###############################################################
#################################### Logs Utils ###################################

function log_to_file()
{
    if [[ -d ${WORK_DIR} ]] ; then
        echo -e "$*" >> ${WORK_DIR}/log
    fi
}

TRACE_MODE=0
function LOG_TRACE()
{
    ## print purple
    [[ ${TRACE_MODE} -eq 1 ]] && echo -e "\e[1;35m[TRACE] $* \e[0m"
    log_to_file "\e[1;35m$(date '+%Y-%m-%dT%H:%M:%S') [TRACE] $* \e[0m"
}

DEBUG_MODE=0
function LOG_DEBUG()
{
    ## print blue
    [[ ${DEBUG_MODE} -eq 1 ]] && echo -e "\e[1;34m[DEBUG] $* \e[0m"
    log_to_file "\e[1;34m$(date '+%Y-%m-%dT%H:%M:%S') [DEBUG] $* \e[0m"
}

function LOG_ERROR()
{
    ## print red
    log_to_file "\e[1;31m$(date '+%Y-%m-%dT%H:%M:%S') [ERROR] $* \e[0m"
}

function LOG_HIGHLIGHT()
{
    ## print green
    log_to_file "\e[1;32m$(date '+%Y-%m-%dT%H:%M:%S') [INFO+] $* \e[0m"
}

function LOG_INFO()
{
    ## print no color
    log_to_file "$(date '+%Y-%m-%dT%H:%M:%S') [INFO ] $* "
}

#################################### Logs Utils END ##############################

################################# Output Utils ###################################

function print_error()
{
    ## print red
    LOG_ERROR "$*"
    local short_msg=$(echo "$*" | awk -F ' - ' '{print $NF}')
    echo -e "\e[1;31m${short_msg}\e[0m"
}

function print_highlight()
{
    ## print green
    LOG_HIGHLIGHT "$*"
    local short_msg=$(echo "$*" | awk -F ' - ' '{print $NF}')
    echo -e "\e[1;32m${short_msg}\e[0m"
}

function print_info()
{
    ## print no color
    LOG_INFO "$*"
    local short_msg=$(echo "$*" | awk -F ' - ' '{print $NF}')
    echo "${short_msg}"
}

function print_msg()
{
    ## print blue
    LOG_INFO "$*"
    local short_msg=$(echo "$*" | awk -F ' - ' '{print $NF}')
    echo -e "\e[1;34m${short_msg}\e[0m"
}

################################# Output Utils END ##############################

################################# Common Utils ###################################

PUBLIC_IP=''
MGMT_IP=''
REPL_IP=''
DATA_IP=''

MACHINES=''
ECS_VERSION=''

SDS_TOKEN=''
VDC_NAME=''
ZONE_ID=''
COS=''
SP_NAME=''
REPLICATION_GROUPS=''
REPLICATION_GROUPS_ALL=''
REPLICATION_GROUPS_NAME_ALL=''

declare -A VDCNAME_DATAIP_MAP=()
declare -A VDCID_REPLIP_MAP=()
declare -A VDCNAME_REPLIP_MAP=()
declare -A VDCID_MGMTIP_MAP=()
declare -A VDCNAME_MGMTIP_MAP=()
declare -A VDCID_DATAIP_MAP=()

declare -A VDCID_VDCNAME_MAP=()
declare -A VDCNAME_VDCID_MAP=()

declare -A VDCID_COSID_MAP=()
declare -A COSID_VDCID_MAP=()

declare -A RGID_RGNAME_MAP=()
declare -A RGNAME_RGID_MAP=()

declare -A RGID_VDCIDS_MAP=()
declare -A RGNAME_VDCNAMES_MAP=()

declare -A VDCID_RGIDS_MAP=()
declare -A VDCNAME_RGNAMES_MAP=()

function get_local_ips
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    #################################### get all type IPs of local host
    PUBLIC_IP=$(ip addr | awk '$7=="public" {split($2,sl,"/"); print sl[1]}')
    DATA_IP=$(ip addr | awk '$7=="public.data" {split($2,sl,"/"); print sl[1]}'); [[ -z ${DATA_IP} ]] && DATA_IP=${PUBLIC_IP}
    REPL_IP=$(ip addr | awk '$7=="public.repl" {split($2,sl,"/"); print sl[1]}'); [[ -z ${REPL_IP} ]] && REPL_IP=${PUBLIC_IP}
    MGMT_IP=$(ip addr | awk '$7=="public.mgmt" {split($2,sl,"/"); print sl[1]}'); [[ -z ${MGMT_IP} ]] && MGMT_IP=${PUBLIC_IP}
    # DATA_IP=$(netstat -an | awk '/:9020.*LISTEN/{print $4}' | awk -F : '{print $1}')
    # REPL_IP=$(netstat -an | awk '/:9095.*LISTEN/{print $4}' | awk -F : '{print $1}')
    # MGMT_IP=$(netstat -an | awk '/:443.*LISTEN/{print $4}' | awk -F : '{print $1}')

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - PUBLIC_IP:${PUBLIC_IP} DATA_IP: ${DATA_IP} REPL_IP: ${REPL_IP} MGMT_IP: ${MGMT_IP}"

    if [[ -z ${REPL_IP} || -z ${DATA_IP} || -z ${MGMT_IP} || -z ${PUBLIC_IP} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get IPs"
        return 1
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_ecs_version
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    #################################### get ecs version of local VDC
    ECS_VERSION=$(sudo -i docker exec object-main rpm -qa | awk -F '-' '/storageos-fabric-datasvcs/ {print $4}')
    # ECS_VERSION=$(sudo -i xdoctor --ecsversion |awk '/Object Version:/ {print $3}')

    if [[ -z ${ECS_VERSION} ]] ; then
        print_error "Failed to get ECS_VERSION"
        return 1
    fi

    declare -A ecs_versions=(
        ["2.0.1.0-62267.db4d4a8"]="ECS-2.0.1"
        ["2.0.1.0-62579.2b9366b"]="ECS-2.0.1-HF2"
        ["2.1.0.0-64720.6678e90"]="ECS-2.1-GA"
        ["2.1.0.0-64822.e755d30"]="ECS-2.1-HF1"
        ["2.1.0.0-64965.b4aff56"]="ECS-2.1-HF2"
        ["2.1.0.0-65517.64b7a6e"]="ECS-2.1-HF3"
        ["2.1.0.0-65588.1d00c37"]="ECS-2.1-HF4"
        ["2.2.0.0-73837.e1ca963"]="ECS-2.2-GA"
        ["2.2.0.0-75469.caa0f9a"]="ECS-2.2-HF1"
        ["2.2.0.0-75566.ccea02d"]="ECS-2.2-HF2"
        ["2.2.0.0-75761.8c6090f"]="ECS-2.2-HF3"
        ["2.2.1.0-77331.4f57cc6"]="ECS-2.2.1-GA"
        ["2.2.1.0-77706.493e577"]="ECS-2.2.1-HF1-GA"
        ["3.0.0.0.85807.98632a9"]="ECS-3.0-GA"
        ["3.0.0.0.86239.1c9e5ec"]="ECS-3.0-HF1"
        ["3.0.0.0-86889.0a0ee19"]="ECS-3.0-HF2-GA"
    )

    ECS_VERSION="${ECS_VERSION} ${ecs_versions[${ECS_VERSION}]}"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function purify_machines_file
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ ! -z ${MACHINES} && -r ${MACHINES} ]]; then
        sudo chown admin:users ${MACHINES} 2>/dev/null
        sed -i '/^#.*/d' ${MACHINES}
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - purified"
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_machines_by_replip
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    MACHINES=/var/tmp/MACHINES
    for vdc_name in ${VDCID_VDCNAME_MAP[@]}
        do
        awk '{print $4}' ${WORK_DIR}/common_info.vdc_info.${vdc_name} > /var/tmp/MACHINES.repl_ip.${vdc_name}
        if [[ ${vdc_name} == ${VDC_NAME} ]] ; then
            awk '{print $1}' ${WORK_DIR}/common_info.vdc_info.${vdc_name} > ${MACHINES}
        fi
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_machines_from_fabric
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    ### we don't usually rely on fabric, because in case of a vdc with multiple rack we cannot get private IPs of all racks
    ### because by dedign or bugs

    MACHINES=/var/tmp/MACHINES
    #get all the nodes on this VDC
    # sudo -i getclusterinfo -a /tmp/machineall > /dev/null 2>&1
    sudo -i getrackinfo -c ${MACHINES} > /dev/null 2>&1
    if [[ $? -ne 0 ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get MACHINES"
        return 1
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_vdc_info_from_mgmt_api
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    #################################### get MGMT secret
    SDS_TOKEN=$(curl -i -s -L --location-trusted -k https://${MGMT_IP}:4443/login -u ${MGMT_USER}:${MGMT_PWD} 2>/dev/null | grep X-SDS-AUTH-TOKEN 2>/dev/null)
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - SDS_TOKEN-> [ ${SDS_TOKEN} ]"
    if [[ -z ${SDS_TOKEN} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get secret"
        return 1
    fi

    #################################### get local storage pool(virtual array) info
    local local_storage_pool_info=$(curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/vdc/data-services/varrays" 2>/dev/null | xmllint --format - 2>/dev/null)
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - local_storage_pool_info-> [ ${local_storage_pool_info} ]"
    [[ -z ${COS} ]] && COS=$(echo "${local_storage_pool_info}" | awk -F"<|>" '/id/ {print $3}')
    SP_NAME=$(echo "${local_storage_pool_info}" | awk -F"<|>" '/name/ {print $3}')
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - COS-> ${COS} SP_NAME-> ${SP_NAME}"
    if [[ -z ${COS} || -z ${SP_NAME} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get /vdc/data-services/varrays"
        return 2
    fi

    local local_vdc_info=$(curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/object/vdcs/vdc/local" 2>/dev/null | xmllint --format - 2>/dev/null)
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - local_vdc_info-> [ ${local_vdc_info} ]"
    [[ -z ${ZONE_ID} ]] && ZONE_ID=$(echo "${local_vdc_info}" | awk -F"<|>" '/vdcId/ {print $3}')
    VDC_NAME=$(echo "${local_vdc_info}" | awk -F"<|>" '/vdcName/ {print $3}')
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ZONE_ID-> ${ZONE_ID} VDC_NAME-> ${VDC_NAME}"
    if [[ -z ${ZONE_ID} || -z ${VDC_NAME} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get /object/vdcs/vdc/local"
        return 3
    fi

    ############################################################################################################
    #################################### get zone id name map
    local vdcs_info_out=$(curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/object/vdcs/vdc/list" 2>/dev/null | xmllint --format - 2>/dev/null)
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - vdcs_info_out-> [ ${vdcs_info_out} ]"
    if [[ -z ${vdcs_info_out} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get /object/vdcs/vdc/list"
        return 4
    fi

    local vdcs_info=$(echo "${vdcs_info_out}" | awk -F '<|>' 'BEGIN{
        loop_end=0
        vdc_id="-"
        vdc_name="-"
        data_ips=""
        repl_ips=""
        mgmt_ips=""
    } {
        if ($2=="vdc") {
            loop_end=0
        } else if ($2=="vdcId") {
            vdc_id=$3
        } else if ($2=="vdcName") {
            vdc_name=$3
        } else if ($2=="interVdcCmdEndPoints") {
            gsub(/ /,"",$3)
            repl_ips=$3
        } else if ($2=="managementEndPoints") {
            gsub(/ /,"",$3)
            mgmt_ips=$3
        } else if ($2=="/vdc") {
            loop_end=1
        }
        if (loop_end==1) {
            print vdc_id,vdc_name,"repl_ip",repl_ips
            print vdc_id,vdc_name,"mgmt_ip",mgmt_ips
            vdc_id="-"
            vdc_name="-"
            repl_ips=""
            mgmt_ips=""
            loop_end=0
        }
    }')
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - vdcs_info-> [ ${vdcs_info} ]"

    #################################### get every RGs related to local zone
    local rg_info_out=$(curl -s -L --location-trusted -k -H "${SDS_TOKEN}" "https://${MGMT_IP}:4443/vdc/data-service/vpools" 2>/dev/null | xmllint --format - 2>/dev/null)
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - rg_info_out-> [ ${rg_info_out} ]"
    if [[ -z ${rg_info_out} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get /vdc/data-service/vpools"
        return 5
    fi

    local rg_info=$(echo "${rg_info_out}" | awk -F '<|>' 'BEGIN{
        rg_loop_end=0
        vdc_loop_end=0
        rg_id="-"
        rg_name="-"
        zone_id="-"
        cos_id="-"
        local_rgs=""
    } {
        if ($2=="data_service_vpool") {
            rg_loop_end=0
        } else if ($2=="id") {
            rg_id=$3
        } else if ($2=="name" && substr($3,0,3)!="urn") {
            rg_name=$3
        } else if ($2=="varrayMappings") {
            vdc_loop_end=0
        } else if ($2=="name" && substr($3,0,36)=="urn:storageos:VirtualDataCenterData:") {
            zone_id=$3
        } else if ($2=="value" && substr($3,0,27)=="urn:storageos:VirtualArray:") {
            cos_id=$3
        } else if ($2=="/varrayMappings") {
            vdc_loop_end=1
        } else if ($2=="/data_service_vpool") {
            rg_loop_end=1
        }

        if (vdc_loop_end == 1 && rg_id != "-" && zone_id != "-" && cos_id != "-") {
            zone_cos_map[zone_id] = cos_id
            zone_id="-"
            cos_id="-"
            vdc_loop_end=0
        }

        if (rg_loop_end==1) {
            for(zone_id in zone_cos_map) {
                print rg_id,rg_name,zone_id,zone_cos_map[zone_id]
            }
            delete zone_cos_map
            rg_id="-"
            rg_name="-"
            zone_id="-"
            cos_id="-"
            rg_loop_end=0
        }
    }')
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - rg_info-> [ ${rg_info} ]"

    #################################### generate and print vdc info-mappings

    local length=$(echo "${vdcs_info}" | wc -l)
    for itrt in $(seq 1 ${length})
        do
        local line=$(echo "${vdcs_info}" | head -n${itrt} | tail -n1)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - line->[${line}]"
        local vdc_id=$(echo ${line} | awk '{print $1}')
        local vdc_name=$(echo ${line} | awk '{print $2}')
        VDCID_VDCNAME_MAP[${vdc_id}]=${vdc_name}
        VDCNAME_VDCID_MAP[${vdc_name}]=${vdc_id}

        local ip_type=$(echo ${line} | awk '{print $3}')
        local ips=$(echo ${line} | awk '{print $4}')
        if [[ ${ip_type} == "repl_ip" ]] ; then
            VDCNAME_REPLIP_MAP[${vdc_name}]=${ips}
            VDCID_REPLIP_MAP[${vdc_id}]=${ips}
        elif [[ ${ip_type} == "mgmt_ip" ]] ; then
            VDCNAME_MGMTIP_MAP[${vdc_name}]=${ips}
            VDCID_MGMTIP_MAP[${vdc_id}]=${ips}
        elif [[ ${ip_type} == "data_ip" ]] ; then
            VDCNAME_DATAIP_MAP[${vdc_name}]=${ips}
            VDCID_DATAIP_MAP[${vdc_id}]=${ips}
        fi
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - vdc_id->[${vdc_id}] vdc_name->[${vdc_name}] ip_type->[${ip_type}] ips->[${ips}]"
    done

    #################################### get all nodes sshable_ips of all vdcs
    for vdc_name in ${!VDCNAME_REPLIP_MAP[@]}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - get IPs for vdc ${vdc_name}"
        local f_vdc_ip_this=${WORK_DIR}/common_info.vdc_info.${vdc_name}
        echo -n "" > ${f_vdc_ip_this}
        for node in $(echo ${VDCNAME_REPLIP_MAP[${vdc_name}]} | tr ',' ' ')
            do
            #####
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - get IPs of vdc ${vdc_name} on node ${node}"
            local host_name=$(ssh -n ${node} "hostname" 2>/dev/null)
            ssh -n ${node} "ip addr" 2>/dev/null | awk -v v_hostname=${host_name} '{
                if ($7=="private.4") {
                    split($2,sl,"/")
                    private4_ip=sl[1]
                } else if ($7=="public") {
                    split($2,sl,"/")
                    public_ip=sl[1]
                } else if ($7=="public.data") {
                    split($2,sl,"/")
                    data_ip=sl[1]
                } else if ($7=="public.repl") {
                    split($2,sl,"/")
                    repl_ip=sl[1]
                } else if ($7=="public.mgmt") {
                    split($2,sl,"/")
                    mgmt_ip=sl[1]
                }
            } END{
                if (data_ip=="") {data_ip=public_ip}
                if (repl_ip=="") {repl_ip=public_ip}
                if (mgmt_ip=="") {mgmt_ip=public_ip}
                printf("%-15s %-15s %-15s %-15s %-15s %s\n", private4_ip,public_ip,data_ip,repl_ip,mgmt_ip,v_hostname)
            }' >> ${f_vdc_ip_this}
        done
    done

    #################################### get rg vdc mapping

    local length=$(echo "${rg_info}" | wc -l)
    for itrt in $(seq 1 ${length})
        do
        local line=$(echo "${rg_info}" | head -n${itrt} | tail -n1)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - line->[${line}]"
        local rg_id=$(echo ${line} | awk '{print $1}')
        local rg_name=$(echo ${line} | awk '{print $2}')
        RGID_RGNAME_MAP[${rg_id}]=${rg_name}
        RGNAME_RGID_MAP[${rg_name}]=${rg_id}

        local vdc_id=$(echo ${line} | awk '{print $3}')
        local cos_id=$(echo ${line} | awk '{print $4}')
        VDCID_COSID_MAP[${vdc_id}]=${cos_id}
        COSID_VDCID_MAP[${cos_id}]=${vdc_id}

        local vdc_ids="${vdc_id} ${RGID_VDCIDS_MAP[${rg_id}]}"
        RGID_VDCIDS_MAP[${rg_id}]=${vdc_ids}
        local vdc_names="${VDCID_VDCNAME_MAP[${vdc_id}]} ${RGNAME_VDCNAMES_MAP[${rg_name}]}"
        RGNAME_VDCNAMES_MAP[${rg_name}]=${vdc_names}

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - rg_id:[${rg_id}] rg_name->[${rg_name}] vdc_id->[${vdc_id}] cos_id->[${cos_id}] vdc_ids->[${vdc_ids}] vdc_names->[${vdc_names}]"

        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - RGID_VDCIDS_MAP[${rg_id}]->[${RGID_VDCIDS_MAP[${rg_id}]}]"
        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - RGNAME_VDCNAMES_MAP[${rg_name}]->[${RGNAME_VDCNAMES_MAP[${rg_name}]}]"
    done

    for vdc_id in ${!VDCID_VDCNAME_MAP[@]}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - vdc_id->[${vdc_id}]"
        for rg_id in ${!RGID_RGNAME_MAP[@]}
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - vdc_id->[${vdc_id}] rg_id->[${rg_id}]"

            echo ${RGID_VDCIDS_MAP[${rg_id}]} | grep -q ${vdc_id} >/dev/null 2>&1
            if [[ $? -eq 0 ]] ; then

                echo ${VDCID_RGIDS_MAP[${vdc_id}]} | grep -q ${rg_id} >/dev/null 2>&1
                if [[ $? -ne 0 ]] ; then
                    VDCID_RGIDS_MAP[${vdc_id}]="${rg_id} ${VDCID_RGIDS_MAP[${vdc_id}]}"
                    VDCNAME_RGNAMES_MAP[${VDCID_VDCNAME_MAP[${vdc_id}]}]="${RGID_RGNAME_MAP[${rg_id}]} ${VDCNAME_RGNAMES_MAP[${VDCID_VDCNAME_MAP[${vdc_id}]}]}"
                    # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - VDCID_RGIDS_MAP[${vdc_id}]->[${VDCID_RGIDS_MAP[${vdc_id}]}] VDCNAME_RGNAMES_MAP[${VDCID_VDCNAME_MAP[${vdc_id}]}]->[${VDCNAME_RGNAMES_MAP[${VDCID_VDCNAME_MAP[${vdc_id}]}]}]"
                fi
            fi
        done
    done

    REPLICATION_GROUPS_ALL=${VDCID_RGIDS_MAP[${ZONE_ID}]}
    REPLICATION_GROUPS_NAME_ALL=${VDCNAME_RGNAMES_MAP[${VDC_NAME}]}

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_vdc_info_from_dt
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # need to handle blow format, ...
    # userMd {
      # key: "rgId"
      # textValue: "urn:storageos:ReplicationGroupInfo:00000000-0000-0000-0000-000000000000:global"
    # }
    # userMd {
      # key: "zone-000-urn:storageos:VirtualDataCenterData:1e653708-414b-4874-bd6f-067d60b6f934"
      # binaryValue: "\nHurn:storageos:VirtualDataCenterData:1e653708-414b-4874-bd6f-067d60b6f934\022?urn:storageos:VirtualArray:c6b29495-3a41-420b-8344-822c8f20fb69\030\000"
      # skipDare: false
    # }

    local rg_vdc_cos_mapping=$(dt_query "http://${DATA_IP}:9101/diagnostic/RT/0/DumpAllKeys/REP_GROUP_KEY?showvalue=gpb&useStyle=raw" | grep -B1 'schemaType REP_GROUP_KEY rgId urn:storageos:ReplicationGroupInfo:' | grep '^http' | while read query_url
        do
        dt_query "${query_url}" | awk '{
            if (substr($2,2,4) == "rgId") {
                getline
                gsub(/"/,"",$2)
                rg_id=$2
            } else if (substr($2,2,5) == "zone-") {
                gsub(/"/,"",$2)
                zone_id=substr($2,10,999)
                getline
                gsub(/"/,"",$2)
                # cos_id=$2
                idx=index($2, "urn:storageos:VirtualArray:")
                split(substr($2,idx,999),sl,"\\")
                cos_id=sl[1]
                zone_cos_map[zone_id]=cos_id
            }
        } END{
            for (zone_id in zone_cos_map) {
                if (rg_id != "urn:storageos:ReplicationGroupInfo:00000000-0000-0000-0000-000000000000:global") {
                    print rg_id,zone_id,zone_cos_map[zone_id]
                }
            }
        }'
    done)

    if [[ -z ${rg_vdc_cos_mapping} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get RG info from RT"
        return 1
    fi

    local ob_urls=$(validate_dt "OB" 0 "url")

    local cos_short=$(echo "${ob_urls}" | head -n1 | awk -F ':|_' '{print $6}')
    COS=$(echo "${rg_vdc_cos_mapping}" | awk -v v_cos_short=${cos_short} '{
        if (substr($3,28,36) == v_cos_short) {
            cos_id=$3
            exit
        }
    } END{
        print cos_id
    }')

    ZONE_ID=$(echo "${rg_vdc_cos_mapping}" | awk -v v_cos_short=${cos_short} '{
        if (substr($3,28,36) == v_cos_short) {
            vdc_id=$2
            exit
        }
    } END{
        print vdc_id
    }')

    REPLICATION_GROUPS=$(echo "${rg_vdc_cos_mapping}" | awk -v v_rgs_short="$(echo "${ob_urls}" | awk -F ':|_' '{print $7}' | sort | uniq | tr '\n' ' ')" 'BEGIN{
        split(v_rgs_short,rgs_short," ")
    }{
        for(key in rgs_short) {
            if (substr($1,36,36) == rgs_short[key]) {
                rg_ids[$1]=$1
            }
        }
    } END{
        for(rg_id in rg_ids) {
            printf("%s ",rg_id)
        }
        printf("\n")
    }')

    if [[ -z ${ZONE_ID} || -z ${COS} || -z ${REPLICATION_GROUPS} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get vdc id, cos, or replicaltion groups from RT"
        return 2
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function print_topology
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    echo "-------------------------------------- Replication Groups Details --------------------------------------"
    for rg_id in ${!RGID_RGNAME_MAP[@]}
        do
        echo "|"
        echo "|---- ${rg_id} ${RGID_RGNAME_MAP[${rg_id}]}"
        for vdc_id in ${RGID_VDCIDS_MAP[${rg_id}]}
            do
            echo "|------------ ${vdc_id} ${VDCID_VDCNAME_MAP[${vdc_id}]} ${VDCID_COSID_MAP[${vdc_id}]}"
        done
    done

    echo
    echo "--------------------------------------------- VDCs Details ---------------------------------------------"
    for vdc_id in ${!VDCID_VDCNAME_MAP[@]}
        do
        echo "|"
        echo "|---- ${vdc_id} ${VDCID_VDCNAME_MAP[${vdc_id}]}"
        for rg_id in ${VDCID_RGIDS_MAP[${vdc_id}]}
            do
            echo "|------------ ${rg_id} ${RGID_RGNAME_MAP[${rg_id}]}"
        done
    done

    echo
    echo "------------------------------------------- VDCs IP Details --------------------------------------------"
    for vdc_id in ${!VDCID_VDCNAME_MAP[@]}
        do
        echo "|"
        echo "|---- ${vdc_id} ${VDCID_VDCNAME_MAP[${vdc_id}]}"
        printf "|------------ %-15s %-15s %-15s %-15s %-15s %s\n" "private4_ip" "public_ip" "data_ip" "repl_ip" "mgmt_ip" "hostname"
        while read line
            do
            echo "|------------ ${line}"
        done < ${WORK_DIR}/common_info.vdc_info.${VDCID_VDCNAME_MAP[${vdc_id}]}
    done

    echo
    echo "------------------------------------- Replication Groups From RT ---------------------------------------"
    dt_query "http://${DATA_IP}:9101/diagnostic/RT/0/DumpAllKeys/REP_GROUP_KEY?showvalue=gpb&useStyle=raw" | grep -B1 'schemaType REP_GROUP_KEY rgId urn:storageos:ReplicationGroupInfo:' | grep '^http' | while read query_url
        do
        dt_query "${query_url}" | awk '{
            if (substr($2,2,4) == "rgId") {
                getline
                gsub(/"/,"",$2)
                rg_id=$2
            } else if (substr($2,2,5) == "zone-") {
                gsub(/"/,"",$2)
                zone_id=$2
                getline
                gsub(/"/,"",$2)
                # cos_id=$2
                idx=index($2, "urn:storageos:VirtualArray:")
                split(substr($2,idx,999),sl,"\\")
                cos_id=sl[1]
                zone_cos_map[zone_id]=cos_id
            }
        } END{
            print "|"
            print "|----",rg_id
            for (zone_id in zone_cos_map) {
                print "|----------",zone_id,zone_cos_map[zone_id]
            }
        }'
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_vdc_info
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_msg "Initializing, retrieving local VDC information from node $(hostname -i 2>/dev/null) $(hostname) ..."

    ####################################
    if [[ -z ${WORK_DIR} ]] ; then
        WORK_DIR=/var/tmp/get_vdc_info/
        mkdir ${WORK_DIR} 2>/dev/null
    fi

    get_local_ips
    [[ $? -ne 0 ]] && exit_program

    get_ecs_version
    [[ $? -ne 0 ]] && exit_program
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ECS_VERSION: ${ECS_VERSION}"

    if [[ -z ${MACHINES} ]] ; then
        get_machines_from_fabric
        [[ $? -ne 0 ]] && exit_program
    fi
    purify_machines_file

    get_vdc_info_from_dt
    [[ $? -ne 0 ]] && exit_program

    if [[ ${PRINT_TOPOLOGY} -eq 1 ]] ; then
        get_vdc_info_from_mgmt_api
        [[ $? -ne 0 ]] && exit_program

        get_machines_by_replip
        [[ $? -ne 0 ]] && exit_program

        print_topology
    fi

    ########################################################################
    echo
    print_info "line:${LINENO} ${FUNCNAME[0]} - ->Local VDC: ${ZONE_ID} ${VDC_NAME}"
    print_info "line:${LINENO} ${FUNCNAME[0]} - ->Local COS: ${COS} ${SP_NAME}"
    print_info "line:${LINENO} ${FUNCNAME[0]} - ->Local RGs:"
    for rg in ${REPLICATION_GROUPS}
        do
        echo "             ${rg} ${RGID_RGNAME_MAP[${rg}]}"
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function get_sshable_ip()
{
    local ips="$1"

    local sshable_ips=""

    ## print 1st sshable IP from input IPs
    for ip in ${ips}
        do
        ssh -n ${ip} date > /dev/null 2>&1
        if [[ $? -eq 0 ]] ; then
            sshable_ips="${ip} ${sshable_ips}"
        fi
    done

    echo "${sshable_ips}"
}

################################# Common Utils END ###############################
######################################################## Utilitys END ###########################################################

function usage
{
    echo ""
    echo "Usage: $SCRIPTNAME"
    echo ""
    echo "Options:"
    echo "       -repo                  check all items of repo GC"
    echo "         -repo_conf           check repo GC configuration"
    echo "         -repo_rrr            check repo GC RR rebuild"
    echo "         -repo_cleanupjob     check repo GC cleanup jobs"
    echo "         -common_obcc         check OB CC Markers"
    echo "         -repo_mns            check repo GC min not sealed"
    echo "         -repo_verification   check repo GC verification"
    echo "       -btree                 check all items of btree GC"
    echo "         -btree_conf          check btree GC configuration"
    echo "         -common_obcc         check OB CC Markers"
    echo "         -btree_mns           check btree GC min not sealed"
    echo "         -btree_markers       check btree GC markers"
    echo "       -restarts              check critical services restart"
    echo "       -configuration         check GC configuration"
    echo "       -dt                    check DT init status"
    echo "       -capacity              check capacity"
    echo "       -topology              print VDCs and RGs configuration"
    echo "       -machines              machines file path"
    echo "       -mgmt_user             mgmt user, username to login ECS portal"
    echo "       -mgmt_password         password of the mgmt user to login ECS portal"
    echo "       -help                  help screen"
    echo ""
    exit 0
}

MGMT_USER='emcservice'
MGMT_PWD='ChangeMe'
CHECK_REPO_GC=0
CHECK_REPO_CONF=0
CHECK_REPO_RRREBUILD=0
CHECK_REPO_CLEANUP=0
CHECK_REPO_MNS=0
CHECK_REPO_VERIFICATION=0
CHECK_COMMON_OBCCMARKER=0
CHECK_BTREE_GC=0
CHECK_BTREE_CONF=0
CHECK_BTREE_MNS=0
CHECK_BTREE_MARKER=0
CHECK_RESTARTS=0
CHECK_CONFIG=0
CHECK_DTINIT=0
CHECK_CAPACITY=0
PRINT_TOPOLOGY=0
PARTIAL_GC_ENABLED=0 # TBD
function parse_args
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ $# -lt 1 ]]; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Requires at least one option/argument"
        usage
    fi

    while [ -n "$1" ]
        do
        case $1 in
            "" )
                ;;
            "-repo" )
                CHECK_REPO_GC=1
                CHECK_REPO_CONF=1
                CHECK_REPO_RRREBUILD=1
                CHECK_REPO_CLEANUP=1
                CHECK_COMMON_OBCCMARKER=1
                CHECK_REPO_MNS=1
                CHECK_REPO_VERIFICATION=1
                shift 1
                ;;
            "-repo_conf" )
                CHECK_REPO_GC=1
                CHECK_REPO_CONF=1
                shift 1
                ;;
            "-repo_rrr" )
                CHECK_REPO_GC=1
                CHECK_REPO_RRREBUILD=1
                shift 1
                ;;
            "-repo_cleanupjob" )
                CHECK_REPO_GC=1
                CHECK_REPO_CLEANUP=1
                shift 1
                ;;
            "-repo_mns" )
                CHECK_REPO_GC=1
                CHECK_REPO_MNS=1
                shift 1
                ;;
            "-repo_verification" )
                CHECK_REPO_GC=1
                CHECK_REPO_VERIFICATION=1
                shift 1
                ;;
            "-common_obcc" )
                CHECK_COMMON_OBCCMARKER=1
                shift 1
                ;;
            "-btree" )
                CHECK_BTREE_GC=1
                CHECK_BTREE_CONF=1
                CHECK_COMMON_OBCCMARKER=1
                CHECK_BTREE_MNS=1
                CHECK_BTREE_MARKER=1
                shift 1
                ;;
            "-btree_conf" )
                CHECK_BTREE_GC=1
                CHECK_BTREE_CONF=1
                shift 1
                ;;
            "-btree_mns" )
                CHECK_BTREE_GC=1
                CHECK_BTREE_MNS=1
                shift 1
                ;;
            "-btree_markers" )
                CHECK_BTREE_GC=1
                CHECK_BTREE_MARKER=1
                shift 1
                ;;
            "-restarts" )
                CHECK_RESTARTS=1
                shift 1
                ;;
            "-configuration" )
                CHECK_CONFIG=1
                shift 1
                ;;
            "-dt" )
                CHECK_DTINIT=1
                shift 1
                ;;
            "-capacity" )
                CHECK_CAPACITY=1
                shift 1
                ;;
            "-topology" )
                PRINT_TOPOLOGY=1
                shift 1
                ;;
            "-machines" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                MACHINES=$2
                shift 2
                ;;
            "-mgmt_user" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                MGMT_USER="$2"
                shift 2
                ;;
            "-mgmt_password" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                MGMT_PWD="$2"
                shift 2
                ;;
            "-help" )
                usage
                ;;
            *)
                print_error "line:${LINENO} ${FUNCNAME[0]} - Invalid option '${1}'"
                echo ""
                usage
                ;;
        esac
    done # Loop through parameters

    ### check args
    if [[ ${CHECK_REPO_GC} -ne 1 &&  ${CHECK_BTREE_GC} -ne 1 \
        &&  ${CHECK_RESTARTS} -ne 1 &&  ${CHECK_CONFIG} -ne 1 \
        &&  ${CHECK_CAPACITY} -ne 1 &&  ${PRINT_TOPOLOGY} -ne 1 \
        && ${CHECK_DTINIT} -ne 1 && ${CHECK_COMMON_OBCCMARKER} -ne 1 ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - No required argument specified"
        usage
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function clean_up_work_dir
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ ! -z ${WORK_DIR} && -d ${WORK_DIR} ]] ; then
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up working diretory"
        rm -rf ${WORK_DIR} 2>/dev/null
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function clean_up_process
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # local pgids=$(ps -e -o pgid,cmd | grep "zgrep.*/var/log/cm-chunk-reclaim.log" | grep -v '[0-9] grep' | awk '{print $1}' | sort | uniq)
    # for pgid in ${pgids}
        # do
        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up sub process group ${pgid} of '${SCRIPTNAME}' about cm-chunk-reclaim.log ..."
        # sudo kill -9 -${pgid}
    # done

    # pgids=$(ps -e -o pgid,cmd | grep "zgrep.*/var/log/blobsvc-chunk-reclaim.log" | grep -v '[0-9] grep' | awk '{print $1}' | sort | uniq)
    # for pgid in ${pgids}
        # do
        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up sub process group ${pgid} of '${SCRIPTNAME}' about blobsvc-chunk-reclaim.log ..."
        # sudo kill -9 -${pgid}
    # done

    # pgids=$(ps -e -o pgid,cmd | grep "zgrep.*/var/log/localmessages" | grep -v '[0-9] grep' | awk '{print $1}' | sort | uniq)
    # for pgid in ${pgids}
        # do
        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up sub process group ${pgid} of '${SCRIPTNAME}' about localmessages ..."
        # sudo kill -9 -${pgid}
    # done

    if [[ ! -z ${SCRIPTNAME} ]] ;then
        pgids=$(ps -e -o pgid,cmd | grep "${SCRIPTNAME}" | grep -v grep | awk '{print $1}' | sort | uniq)
        for pgid in ${pgids}
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up process group ${pgid} of '${SCRIPTNAME}' ..."
            sudo kill -9 -${pgid}
        done
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function clean_up
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # clean_up_work_dir
    clean_up_process

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function exit_program
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # clean_up_work_dir
    clean_up_process

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

################################ Utilitys #####################################

function dt_query
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local query_str="$1"
    local f_output="$2"

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - query_str:[ ${query_str} ] f_output: [ ${f_output} ]"

    DT_QUERY_MAX_RETRY=10
    DT_QUERY_RETRY_INTERVAL=30 ## in second

    local curl_verbose=${WORK_DIR}/curl_verbose
    for retry in $(seq 1 ${DT_QUERY_MAX_RETRY})
        do
        echo -n '' > ${curl_verbose}
        if [[ ! -z ${f_output} ]] ; then
            curl -v -f -L -s "${query_str}" 2>/dev/null > ${f_output} 2>${curl_verbose}
            if [[ $? -ne 0 ]] || ! grep -q '200 OK' ${curl_verbose} 2>/dev/null ; then
                LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Failed to dt_query [${query_str}] for ${retry} time, wait ${DT_QUERY_RETRY_INTERVAL} seconds and retry"
                sleep ${DT_QUERY_RETRY_INTERVAL}
            else
                sed -i 's/\r//g' ${f_output}
                break
            fi
        else
            local query_result=$(curl -v -f -L -s "${query_str}" 2>${curl_verbose})
            if [[ $? -ne 0 ]] || ! grep -q '200 OK' ${curl_verbose} 2>/dev/null ; then
                LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Failed to dt_query [${query_str}] for ${retry} time, wait ${DT_QUERY_RETRY_INTERVAL} seconds and retry"
                sleep ${DT_QUERY_RETRY_INTERVAL}
            else
                echo "${query_result}" | sed -e 's/\r//g'
                break
            fi
        fi

        if [[ ${retry} -eq ${DT_QUERY_MAX_RETRY} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Tried out ${retry} times and always failed, please check if dtquey service had been dead for long time or try in another node"
            exit_program
        fi
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function validate_dt
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local dt_type=$1
    local level=$2
    local return_type=$3 ## url or nothing

    local dt_ids=""
    if [[ "${return_type}" == "url" ]] ; then
        dt_ids=$(dt_query "http://${DATA_IP}:9101/diagnostic/${dt_type}/${level}/" | xmllint --format - | awk -F '<|>|?' '/<table_detail_link>/{print $3}')
    else
        dt_ids=$(dt_query "http://${DATA_IP}:9101/diagnostic/${dt_type}/${level}/" | xmllint --format - | awk -F '<|>|?' '/<id>/{print $3}')
    fi
    if [[ -z ${dt_ids} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get all ${dt_type} level ${level} DTs, please check if DTs are initialized"
        exit_program
    fi

    local dt_cnt=$(echo "${dt_ids}" | wc -l)
    local missing_dt=$(echo "${dt_cnt}%128" | bc)
    if [[ ${missing_dt} -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - Failed to get at least ${missing_dt} ${dt_type} level ${level} DTs, please check if DTs are initialized"
        exit_program
    fi

    echo "${dt_ids}"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function init_stats
{
    if [[ ! -r ${WORK_DIR}/stats_aggregate ]] ; then
        curl -s -k -L https://${MGMT_IP}:4443/stat/aggregate > ${WORK_DIR}/stats_aggregate
    fi

    if ! grep -q "^{" <<< $(head -n1 ${WORK_DIR}/stats_aggregate) 2>/dev/null ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get stats_aggregate, please check dtquery and stat serivice"
        exit_program
    fi
}

function init_stats_history
{
    if [[ ! -r ${WORK_DIR}/stats_aggregate_history ]] ; then
        curl -s -k -L https://${MGMT_IP}:4443/stat/aggregate_history > ${WORK_DIR}/stats_aggregate_history
    fi

    if ! grep -q "^{" <<< $(head -n1 ${WORK_DIR}/stats_aggregate_history) 2>/dev/null ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get stats_aggregate_history, please check dtquery and stat serivice"
        exit_program
    fi
}

function query_counter
{
    local key="$1"

    local counter=$(awk -F '"' -v v_key="${key}" 'BEGIN{
        key_found="no"
        key_counter="-"
    } {
        if ($0 ~ "{") {
            key_found="no"
            key_counter="-"
        } else if ($2 == "id" && $4 == v_key) {
            key_found="yes"
        } else if ($2 == "counter") {
            gsub(/ /,"",$3)
            gsub(/:/,"",$3)
            key_counter=$3
        }
        if (key_counter!="-" && key_found=="yes") {
            exit
        }
    } END{
        print key_counter
    }' ${WORK_DIR}/stats_aggregate)

    if [[ -z ${counter} || "${counter}" == "-" ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Didn't find counter of ${key} from stats, please check if there's no 'counter' filed for ${key} in ${WORK_DIR}/stats_aggregate"
        counter=0
    fi

    if ! grep -q '^[[:digit:]]*$' <<< "${counter}" 2>/dev/null ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get counter of ${key} from stats because the counter is not a digit in ${WORK_DIR}/stats_aggregate"
        counter=0
    fi

    echo ${counter}
}

function capacity_usage_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    init_stats

    local data_repo=$(query_counter "data_repo.TOTAL") ## user data chunk
    local data_jr_1=$(query_counter "data_level_1_journal.TOTAL") ## metadata chunk
    local data_jr_0=$(query_counter "data_level_0_journal.TOTAL") ## metadata chunk
    local data_btree_1=$(query_counter "data_level_1_btree.TOTAL") ## metadata chunk
    local data_btree_0=$(query_counter "data_level_0_btree.TOTAL") ## metadata chunk
    local data_copy=$(query_counter "data_copy.TOTAL")  ## geo chunk
    local data_parity=$(query_counter "data_xor.TOTAL")  ## parity chunk
    local chunk_cached=$(query_counter "Number of Chunks.TOTAL")
    local data_cached=$(echo "scale=0; ${chunk_cached}*134217600" | bc)

    echo ${data_repo} ${data_jr_1} ${data_jr_0} ${data_btree_1} ${data_btree_0} ${data_copy} ${data_parity} ${data_cached} | awk '{
        for(i=1; i<=NF; i++){
            cnt+=$i
        }
        if ( cnt == 0 ) {
            print "Theres neither data writen into or DT activity ever happened in this VDC"
            exit
        }

        repo=$1
        p_repo=100*repo/cnt

        jr_1=$2
        p_jr_1=100*jr_1/cnt
        jr_0=$3
        p_jr_0=100*jr_0/cnt
        btree_1=$4
        p_btree_1=100*btree_1/cnt
        btree_0=$5
        p_btree_0=100*btree_0/cnt
        metadata=jr_1+jr_0+btree_1+btree_0
        p_metadata=100*metadata/cnt

        copy=$6
        p_copy=100*copy/cnt
        parity=$7
        p_parity=100*parity/cnt
        data_cached=$8
        p_xor_shipped=100*data_cached/cnt
        geo=copy+parity+data_cached
        p_geo=100*geo/cnt

        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Capacity Status without Overhead")
        print "------------------------------------------------------------------------------------------------------------"
        printf("%21s | %32s | %32s | %s\n","UserData","Metadata","GeoData","TotalUsed (TB)")
        print "------------------------------------------------------------------------------------------------------------"
        printf("%13.2f(%5.2f%) | %24.2f(%5.2f%) | %24.2f(%5.2f%) | %14.2f\n",repo/1099511627776,p_repo, metadata/1099511627776,p_metadata, geo/1099511627776,p_geo, cnt/1099511627776)
        print "------------------------------------------------------------------------------------------------------------"
        printf("%21s | %-16s %7.2f(%5.2f%) | %-16s %7.2f(%5.2f%) |\n", " ", "level-0 Btree:",   btree_0/1099511627776,p_btree_0, "Geo Copy:",         copy/1099511627776,p_copy)
        printf("%21s | %-16s %7.2f(%5.2f%) | %-16s %7.2f(%5.2f%) |\n", " ", "level-0 Journal:",    jr_0/1099511627776,p_jr_0,    "XOR:",            parity/1099511627776,p_parity)
        printf("%21s | %-16s %7.2f(%5.2f%) | %-16s %7.2f(%5.2f%) |\n", " ", "level-1 Btree:",   btree_1/1099511627776,p_btree_1, "Geo Cache:", data_cached/1099511627776,p_xor_shipped)
        printf("%21s | %-16s %7.2f(%5.2f%) |                      \n", " ", "level-1 Journal:",    jr_1/1099511627776,p_jr_1)
        print "------------------------------------------------------------------------------------------------------------"
        print ""

        c_repo=repo*1.33
        c_metadata=metadata*3
        c_geo=geo*1.33
        c_total=c_repo+c_metadata+c_geo

        printf("\033[1;34m%s\033[0m\n", "====> Estimated Used Capacity")
        print "------------------------------------------------------------------------------------------------------------"
        printf("%13.2f(%5.2f%) | %24.2f(%5.2f%) | %24.2f(%5.2f%) | %14.2f\n", c_repo/1099511627776,100*c_repo/c_total, c_metadata/1099511627776,100*c_metadata/c_total, c_geo/1099511627776,100*c_geo/c_total, c_total/1099511627776)
        print "------------------------------------------------------------------------------------------------------------"
    }'

    dt_query "${DATA_IP}:9101/stats/ssm/varraycapacity" | awk -F '<|>' '{
        if ($2 == "TotalCapacity"){
            TotalCapacity=$3
        } else if ($2 == "UsedCapacity") {
            UsedCapacity=$3
        }
    } END{
        if (TotalCapacity != 0){
            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Capacity Usage")
            print "---------------------------------------------------"
            printf("%15s | %15s | %15s\n", "TotalCapacity","UsedCapacity","UsedPercentage")
            print "---------------------------------------------------"
            printf("%15lu | %15lu | %14.2f%\n", TotalCapacity/1024,UsedCapacity/1024,100*UsedCapacity/TotalCapacity)
            print "---------------------------------------------------"
        }
    }'

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function capacity_from_ssm
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - Below capacity data is restricted to ECS CS and ECS Engineering"

    ### check capacity in DT
    dt_query "http://${DATA_IP}:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_KEY?type=PARTITION&showvalue=gpb&useStyle=raw" | grep -B1 schemaType | grep '^http' | while read query_url
        do
        dt_query "${query_url}" | awk '{
            if($1=="schemaType") {
                device=$6
            } else if($1=="freeSpace:") {
                freeSpace=$2
            }  else if($1=="busySpace:") {
                busySpace=$2
                device_capacity[device]+=(freeSpace+busySpace)
            }
        } END{
            for (device in device_capacity) {
                printf("%-15s %32lu\n",device,device_capacity[device])
            }
        }'
    done | sort | awk '{
        device=$1
        capacity=$2
        device_capacity[device]+=capacity
        capacity_vdc+=capacity
    } END{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Local VDC Capacity from SS")
        for (device in device_capacity) {
            printf("%-15s %15.4f GB\n",device,device_capacity[device]/(1024*1024*1024))
        }
        printf("%-15s %15.2f TB (%.2f PB) \n","VDC Total",capacity_vdc/(1024*1024*1024*1024),capacity_vdc/(1024*1024*1024*1024*1024))
    }'

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function capacity_from_blockbin
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - Below capacity data is restricted to ECS CS and ECS Engineering"

    [[ ${PRINT_TOPOLOGY} -ne 1 ]] && PRINT_TOPOLOGY=1 && get_vdc_info_from_mgmt_api

    ################## check All VDC disk capacity
    for vdc_name in ${!VDCNAME_REPLIP_MAP[@]}
        do
        echo
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> Capacity of VDC ${vdc_name}"
        local f_vdc_ip_this=${WORK_DIR}/common_info.vdc_info.${vdc_name}
        echo -n "" > ${f_vdc_ip_this}
        printf "%-15s %8s %10s %13s\n" "node_ip" "disk_cnt" "blockbin" "capacity"
        for node in $(echo ${VDCNAME_REPLIP_MAP[${vdc_name}]} | tr ',' ' ')
            do
            #####
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - get Capacity of VDC ${vdc_name} node ${node}"
            ssh -n ${node} "sudo -i cs_hal list vols 2>/dev/null | awk '/xfs/{print \"/dae/uuid-\"\$3}' | xargs -t -i sudo docker exec object-main ls -lS {}" 2>&1 | awk -v v_node=${node} '{
                if ($1 == "total") {
                    next
                } else if ($1 == "sudo") {
                    disk_cnt+=1
                } else {
                    blockbin_cnt+=1
                    blockbin_size_cnt+=$5
                }
            } END{
                printf("%-15s %8d %10d %13.2f GB\n",v_node,disk_cnt,blockbin_cnt,blockbin_size_cnt/(1024*1024*1024))
            }'
        done | tee ${WORK_DIR}/tmp_file
        awk '{
            disk_cnt+=$2
            capacity_cnt+=$4
        } END{
            printf("%-15s %8d %10s %13.2f GB(%.2f TB %.2f PB)\n","VDC Total",disk_cnt,"-",capacity_cnt,capacity_cnt/1024,capacity_cnt/(1024*1024))
        }' ${WORK_DIR}/tmp_file
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function search_logs
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local log_file=$1
    local within_days=$2
    local key_words="$3"
    local out_put_file=$4

    local files=''
    while read node
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Collecting log from node ${node} ..."
        files=$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name ${log_file}* -mtime -${within_days} -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null " 2>/dev/null)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"

        [[ -z ${files} ]] && continue

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - grepping log from node ${node} ..."
        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep '${key_words}' ${files}\"" > ${out_put_file}${node} 2>/dev/null &
    done < ${MACHINES}
    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

############################### gc_common checks ###############################

function gc_common_dtinit
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    dt_query "http://${DATA_IP}:9101/stats/dt/DTInitStat" | xmllint --format - | awk -F '[<|>]' '{
        if ($2 == "total_dt_num") {
            total_dt_num=$3
        } else if ($2 == "unready_dt_num") {
            unready_dt_num=$3
        } else if ($2 == "unknown_dt_num") {
            unknown_dt_num=$3
        } else if ($2 == "/entry") {
            exit
        }
    } END{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> DT status")
        print "---------------------------------"
        printf("%-17s | %13lu\n", "total_dt_num", total_dt_num)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "unready_dt_num", unready_dt_num)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "unknown_dt_num", unknown_dt_num)
        print "---------------------------------"

        if (unready_dt_num != 0 || unknown_dt_num != 0) {
            print "please run [ /usr/local/xdoctor/tools/ee_scripts/dtquery.sh dt ] to check DT details"
        }
    }'

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_chunk_info
{
    local chunk_id=$1

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Getting chunk info of ${chunk_id}"
    local chunk_query_url=$(dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK?chunkId=${chunk_id}&showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http')
    if [[ -z ${chunk_query_url} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get chunk_query_url for chunk ${chunk_id}"
        return 1
    fi

    dt_query "${chunk_query_url}"
}

############################### gc_common checks ###############################

function gc_common_check_services_restarts
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Local VDC Services Restarts ******************************************"

    local files=''
    local log_searched=${WORK_DIR}/gc_common.service_restarts_log
    while read node
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Collecting log from node ${node} ..."

        files="$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name localmessages* -mtime -7 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null " 2>/dev/null)" 2>/dev/null
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"

        [[ -z ${files} ]] && continue

        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep restarting ${files} | awk -F 'gz:|localmessages' '{if (substr(\\\$1,0,9)==\\\"/var/log/\\\") {print \\\$NF} else {print \\\$0} }' \" " 2>/dev/null | awk -F 'T| |/' '{print $1,$10}'| sort | grep '-' | uniq -c > ${log_searched}.${node} &
    done < ${MACHINES}
    wait

    while read node
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Collecting log from node ${node} ..."

        #print_msg "------------------------------------------------- ${node} -------------------------------------------------"
        printf " ------------------------------------------------ %-15s -----------------------------------------------\n" "${node}"

        if [[ ! -f ${log_searched}.${node} || ! -s ${log_searched}.${node} ]] ; then
            echo "NOPE"
            continue
        fi

        local svcs=$(awk '{print $3}' ${log_searched}.${node} | sort | uniq )
        local dates=$(awk '{print $2}' ${log_searched}.${node} | sort | uniq | tail -n7)

        printf "%-22s " "Services\Date"
        for date in $(echo ${dates})
            do
            printf "%12s " "${date}"
        done
        printf "\n"

        for svc in $(echo ${svcs})
            do
            printf "%-22s " "${svc}"
            for date in $(echo ${dates})
                do
                local cnt=$(awk -v v_date=${date} -v v_svc=${svc} '{if ($2==v_date && $3==v_svc) {print $1}}' ${log_searched}.${node})
                [[ -z ${cnt} ]] && cnt='-'
                printf "%12s " "${cnt}"
            done
            printf "\n"
        done
        printf "\n"
    done < ${MACHINES}

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_cmf_configuration
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local switches="$1"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - switches: [${switches}]"

    printf "%-60s %-5s %-12s %-15s %-19s %-s\n" "ConfigurationName" "InCMF" "DefaultValue" "ConfiguredValue" "ModifyTime" "Reason"
    echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------"
    for switch in ${switches}
        do

        sudo -i docker exec object-main /opt/storageos/tools/cf_client --user ${MGMT_USER} --password ${MGMT_PWD} --list --name "${switch}" | awk -F '"' -v v_switch=${switch} 'BEGIN{
            found="no"
            default_value="-"
            configured_value="-"
            mtime="-"
            reason="-"
            loop_end=0
        } {
            if ($0 ~ "}") {
                loop_end=1
            } else if ($2=="name" && $4==v_switch) {
                found="yes"
            } else if ($2=="default_value") {
                default_value=$4
            } else if ($2=="configured_value"){
                configured_value=$4
            } else if ($2=="modified"){
                mtime=strftime("%Y-%m-%dT%H:%M:%S",substr($4,0,10))
            } else if ($2=="audit"){
                reason=$4
            }

            if (loop_end==1 && found=="yes") {
                exit
            }

            if (loop_end==1) {
                found="no"
                default_value="-"
                configured_value="-"
                mtime="-"
                reason="-"
                loop_end=0
            }
        } END{
            printf("%-60s %-5s %-12s %-15s %-19s %-s\n", v_switch, found, default_value, configured_value, mtime, reason)
            print "-----------------------------------------------------------------------------------------------------------------------------------------------------------------"
        }'
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_common_check_tasks
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    validate_dt "CT" 1 > /dev/null
    validate_dt "PR" 1 > /dev/null
    validate_dt "SS" 1 > /dev/null

    local f_cm_geo_send_tracker_tasks=${WORK_DIR}/gc_common.cm_geo_send_tracker_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK/?type=GEO_DATA_SEND_TRACKER&useStyle=raw" ${f_cm_geo_send_tracker_tasks}
    local cm_geo_send_tracker_tasks_cnt=$(grep -c schemaType ${f_cm_geo_send_tracker_tasks})

    local f_cm_geo_delete_tasks=${WORK_DIR}/gc_common.cm_geo_delete_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=GEO_DELETE&useStyle=raw" ${f_cm_geo_delete_tasks}
    local cm_geo_delete_tasks_cnt=$(grep -c schemaType ${f_cm_geo_delete_tasks})

    local f_cm_free_block_tasks=${WORK_DIR}/gc_common.cm_free_block_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=FREE_BLOCKS&useStyle=raw" ${f_cm_free_block_tasks}
    local cm_free_block_tasks_cnt=$(grep -c schemaType ${f_cm_free_block_tasks})

    local f_ss_block_free_tasks=${WORK_DIR}/gc_common.ss_free_block_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_TASK_KEY?type=BLOCK_FREE_TASK&useStyle=raw" ${f_ss_block_free_tasks}
    local ss_block_free_tasks_cnt=$(grep -c schemaType ${f_ss_block_free_tasks})

    local f_cm_repair_tasks=${WORK_DIR}/gc_common.cm_repair_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK/?type=REPAIR&useStyle=raw" ${f_cm_repair_tasks}
    local cm_repair_tasks_cnt=$(grep -c schemaType ${f_cm_repair_tasks})

    local f_pr_bootstrap_tasks=${WORK_DIR}/gc_common.pr_bootstrap_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/DTBOOTSTRAP_TASK" ${f_pr_bootstrap_tasks}
    local pr_bootstrap_tasks_done=$(grep -c Done ${f_pr_bootstrap_tasks})
    local pr_bootstrap_tasks_btree_scan=$(grep -c BTreeScan ${f_pr_bootstrap_tasks})
    local pr_bootstrap_tasks_replicate_btree=$(grep -c ReplicateBTree ${f_pr_bootstrap_tasks})

    echo "${cm_geo_send_tracker_tasks_cnt} ${cm_geo_delete_tasks_cnt} ${cm_free_block_tasks_cnt} ${ss_block_free_tasks_cnt} ${cm_repair_tasks_cnt} ${pr_bootstrap_tasks_done} ${pr_bootstrap_tasks_btree_scan} ${pr_bootstrap_tasks_replicate_btree}" | awk '{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Relevant Tasks Status")
        print "---------------------------------"
        printf("%-17s | %13lu\n", "Geo Shipping", $1)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "Geo Delete", $2)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "Free Blocks", $3)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "SS Block Free", $4)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "Repair", $5)
        print "---------------------------------"
        printf("%-17s | %13lu\n", "Bootstrap", $8+$6+$7)
        print "|                  --------------"
        printf("%-17s | %13lu\n", "|- Done", $6)
        printf("%-17s | %13lu\n", "|- BTreeScan", $7)
        printf("%-17s | %13lu\n", "|- ReplicateBTree", $8)
        print "---------------------------------"
    }'

    if [[ ${pr_bootstrap_tasks_btree_scan} -gt 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs in BTreeScan:"
        grep BTreeScan ${bootstrap_task} -B1 | grep '^http'
    fi

    if [[ ${pr_bootstrap_tasks_replicate_btree} -gt 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs in ReplicateBTree:"
        grep ReplicateBTree ${bootstrap_task} -B1 | grep '^http'
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

############################### btree_gc checks ###############################

function btree_gc_check_configuration
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Btree GC Configurations **********************************************"

    get_cmf_configuration "com.emc.ecs.chunk.gc.btree.enabled com.emc.ecs.chunk.gc.btree.scanner.verification.enabled com.emc.ecs.chunk.gc.btree.scanner.copy.enabled"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_check_btree_markers
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Btree GC Occupancy Scanner Consistent Tree ***************************"


    ##### step 1
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 1, Get and parse BPLUSTREE_DUMP_MARKER"

    local f_mns_dump_markers=${WORK_DIR}/btree_gc_check.mns.dump_markers
    local f_mns_dump_marker_simple=${WORK_DIR}/btree_gc_check.mns.dump_marker.simple

    print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs whoes BPLUSTREE_DUMP_MARKER delay >= ${MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD} days"
    printf "%-51s %-72s %13s %-19s %9s\n" "DTID" "ZoneID" "DumpMarker" "MarkerReadable" "DayDelay"
    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

    printf "%-115s %-72s %13s %-19s %9s\n" "DTID" "ZoneID" "DumpMarker" "MarkerReadable" "DayDelay" >> ${f_mns_dump_marker_simple}
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" >> ${f_mns_dump_marker_simple}

    for level in $(seq 1 2)
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Get and parse BPLUSTREE_DUMP_MARKER for level ${level}"

        local dt_ids=$(validate_dt "PR" ${level})
        local dt_cnt=$(echo "${dt_ids}" | wc -l)

        local query_urls=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/${level}/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=BPLUSTREE_DUMP_MARKER&showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http')
        if [[ -z ${query_urls} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ curl -L -s 'http://${DATA_IP}:9101/diagnostic/PR/${level}/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=BPLUSTREE_DUMP_MARKER&showvalue=gpb&useStyle=raw' ]"
            continue
        fi

        for query_url in $(echo "${query_urls}")
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${query_url}' ]"

            echo "${query_url}" >> ${f_mns_dump_markers}
            dt_query "${query_url}" | tee -a ${f_mns_dump_markers} | awk 'BEGIN{
                dt_id="-"
                zone_id="-"
                time_stamp="-"
            } {
                if($1=="schemaType"){
                    dt_id=$6
                    zone_id=$8
                }else if ($1=="progress:"){
                    time_stamp=$2
                    printf("%-115s %-72s %13s %-19s %9d\n",dt_id,zone_id,time_stamp,strftime("%Y-%m-%dT%H:%M:%S",substr(time_stamp,0,10)), (systime()-substr(time_stamp,0,10))/(60*60*24) )
                    dt_id="-"
                    zone_id="-"
                    time_stamp="-"
                }
            }' | tee -a ${f_mns_dump_marker_simple} | awk -v v_mns_dump_marker_day_delay=${MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD} '{
                if ($NF>=v_mns_dump_marker_day_delay) {
                    print substr($0,65,999)
                }
            }'
        done
    done
    echo "-------------------------------- END -----------------------------------------------------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs BPLUSTREE_DUMP_MARKER distribution:"
    awk -F' |_' '/schemaType/{print $11,$NF}' ${f_mns_dump_markers} | sort | uniq -c | sort

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_mns_dump_marker_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_dump_markers}"
    echo
    echo

    ##### step 2
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 2, Get and parse BPLUSTREE_PARSER_MARKER"

    local f_mns_parser_markers=${WORK_DIR}/btree_gc_check.mns.parser_markers
    local f_mns_parser_marker_simple=${WORK_DIR}/btree_gc_check.mns.parser_marker.simple
    local f_mns_parser_trees=${WORK_DIR}/btree_gc_check.mns.parser_trees
    local f_mns_parser_tree_simple=${WORK_DIR}/btree_gc_check.mns.parser_tree.simple

    print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs whoes BPLUSTREE_PARSER_MARKER delay >= ${MNS_PARSER_MARKER_DAY_DELAY_THRESHOLD} days"
    printf "%-51s %-72s %-16s %-13s %-19s %-8s\n" "DTID" "ZoneID" "ParserMajor" "ParserMarker" "MarkerReadable" "DayDelay"
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

    printf "%-115s %-72s %-16s %-13s %-19s %-8s\n" "DTID" "ZoneID" "ParserMajor" "ParserMarker" "MarkerReadable" "DayDelay" >> ${f_mns_parser_tree_simple}
    echo "--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" >> ${f_mns_parser_tree_simple}

    for level in $(seq 1 2)
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Get and parse BPLUSTREE_PARSER_MARKER for level ${level}"

        local query_urls=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/${level}/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=BPLUSTREE_PARSER_MARKER&showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http')
        if [[ -z ${query_urls} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ curl -L -s 'http://${DATA_IP}:9101/diagnostic/PR/${level}/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=BPLUSTREE_PARSER_MARKER&showvalue=gpb&useStyle=raw' ]"
            continue
        fi

        for query_url in $(echo "${query_urls}")
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${query_url}' ]"

            echo "${query_url}" >> ${f_mns_parser_markers}
            local sub_qurey_urls=$(dt_query "${query_url}" | tee -a ${f_mns_parser_markers} | awk -v v_pr_qurey_url=${query_url} '/schemaType|bTreeInfoMajor/{
                if($1=="schemaType"){
                    dt_id=$6
                    zone_id=$8
                }else if ($1=="bTreeInfoMajor:"){
                    jr_major=$2
                    gsub(/BPLUSTREE_PARSER_MARKER/, "BPLUSTREE_INFO", v_pr_qurey_url)
                    printf("%s&dtId=%s&zone=%s&major=%016x\n", v_pr_qurey_url, dt_id, zone_id, jr_major-1)
                }
            }')

            ######
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Get and parse BPLUSTREE_INFO"

            for sub_qurey_url in $(echo "${sub_qurey_urls}")
                do
                LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${sub_qurey_url}' ]"

                echo "${sub_qurey_url}" >> ${f_mns_parser_trees}
                dt_query "${sub_qurey_url}" | tee -a ${f_mns_parser_trees} | awk '/schemaType|timestamp/{
                    if($1=="schemaType"){
                        dt_id=$6
                        zone_id=$8
                        jr_major=$10
                    }else if ($1=="timestamp:"){
                        time_stamp=$2
                    }
                } END{
                    if (time_stamp!="-") {
                        time_readable=strftime("%Y-%m-%dT%H:%M:%S",substr(time_stamp,0,10))
                        day_delay=(systime()-substr(time_stamp,0,10))/(60*60*24)
                    }
                    printf("%-115s %-72s %-16s %-13s %-19s %8d\n", dt_id,zone_id,jr_major,time_stamp,time_readable,day_delay)
                }' | tee -a ${f_mns_parser_tree_simple} | awk -v v_mns_parser_marker_day_delay=${MNS_PARSER_MARKER_DAY_DELAY_THRESHOLD} '{
                    if ($NF>=v_mns_parser_marker_day_delay) {
                        print substr($0,65,999)
                    }
                }'
            done
        done
    done
    echo "-------------------------------- END ---------------------------------------------------------------------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs BPLUSTREE_PARSER_MARKER distribution:"
    awk -F' |_' '/schemaType/{print $10,$15}' ${f_mns_parser_trees} | sort | uniq -c | sort

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_mns_parser_marker_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_parser_markers}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_mns_parser_tree_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_parser_trees}"
    echo
    echo


    ##### step 3
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 3, Get and parse GEOREPLAYER_CONSISTENCY_CHECKER_MARKER"

    local f_mns_gepreplayer_consistency_markers=${WORK_DIR}/btree_gc_check.mns.gepreplayer_consistency_markers
    local f_mns_gepreplayer_consistency_marker_simple=${WORK_DIR}/btree_gc_check.mns.gepreplayer_consistency_marker.simple
    local f_mns_gepreplayer_consistency_trees=${WORK_DIR}/btree_gc_check.mns.gepreplayer_consistency_trees
    local f_mns_gepreplayer_consistency_tree_simple=${WORK_DIR}/btree_gc_check.mns.gepreplayer_consistency_tree.simple

    print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs whoes GEOREPLAYER_CONSISTENCY_CHECKER_MARKER delay >= ${MNS_CC_MARKER_DAY_DELAY_THRESHOLD} days"
    printf "%-51s %-72s %-16s %-13s %-19s %8s\n" "DTID" "ZoneID" "CCMajor" "CCMarker" "MarkerReadable" "DayDelay"
    echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    printf "%-115s %-72s %-16s %-13s %-19s %8s\n" "DTID" "ZoneID" "CCMajor" "CCMarker" "MarkerReadable" "DayDelay" >> ${f_mns_gepreplayer_consistency_tree_simple}
    echo "-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" >> ${f_mns_gepreplayer_consistency_tree_simple}

    for level in $(seq 1 2)
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Get and parse GEOREPLAYER_CONSISTENCY_CHECKER_MARKER for level ${level}"

        local dt_urls=$(validate_dt "PR" ${level} "url")

        local query_urls=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/${level}/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=GEOREPLAYER_CONSISTENCY_CHECKER_MARKER&showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http')
        if [[ -z ${query_urls} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ curl -L -s 'http://${DATA_IP}:9101/diagnostic/PR/${level}/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=GEOREPLAYER_CONSISTENCY_CHECKER_MARKER&showvalue=gpb&useStyle=raw' ]"
            continue
        fi

        for query_url in $(echo "${query_urls}")
            do
        # for dt_url in $(echo "${dt_urls}")
            # do
            # local query_url="${dt_url}&type=GEOREPLAYER_CONSISTENCY_CHECKER_MARKER&showvalue=gpb&useStyle=raw"
            # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${query_url}' ]"

            echo "${query_url}" >> ${f_mns_gepreplayer_consistency_markers}
            local sub_qurey_urls=$(dt_query "${query_url}" | tee -a ${f_mns_gepreplayer_consistency_markers} | awk -v v_pr_qurey_url=${query_url} '{
                if($1=="schemaType"){
                    dt_id=$6
                    zone_id=$8
                }else if ($1=="subKey:"){
                    jr_major=substr($2,8,16)
                    jr_minor=substr($2,32,16)
                    gsub(/GEOREPLAYER_CONSISTENCY_CHECKER_MARKER/, "BPLUSTREE_INFO", v_pr_qurey_url)
                    printf("%s&dtId=%s&zone=%s&major=%s\n", v_pr_qurey_url, dt_id, zone_id, jr_major)
                }
            }')

            ######
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Get and parse BPLUSTREE_INFO"
            for sub_qurey_url in $(echo "${sub_qurey_urls}")
                do
                LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${sub_qurey_url}' ]"

                echo "${sub_qurey_url}" >> ${f_mns_gepreplayer_consistency_trees}
                dt_query "${sub_qurey_url}" | tee -a ${f_mns_gepreplayer_consistency_trees} | awk '/schemaType|timestamp/{
                    if($1=="schemaType"){
                        dt_id=$6
                        zone_id=$8
                        jr_major=$10
                    }else if ($1=="timestamp:"){
                        time_stamp=$2
                    }
                } END{
                    if (time_stamp!="-") {
                        time_readable=strftime("%Y-%m-%dT%H:%M:%S",substr(time_stamp,0,10))
                        time_delta=(systime()-substr(time_stamp,0,10))/(60*60*24)
                    }
                    printf("%-115s %-72s %-16s %13s %-19s %8d\n", dt_id,zone_id,jr_major,time_stamp,time_readable,time_delta)
                }' | tee -a ${f_mns_gepreplayer_consistency_tree_simple} | awk -v v_mns_parser_marker_day_delay=${MNS_CC_MARKER_DAY_DELAY_THRESHOLD} '{
                    if ($NF>=v_mns_parser_marker_day_delay) {
                        print substr($0,65,999)
                    }
                }'
            done
        done
    done
    echo "-------------------------------- END ---------------------------------------------------------------------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - DTs GEOREPLAYER_CONSISTENCY_CHECKER_MARKER distribution:"
    awk '/VirtualDataCenterData/{print substr($1,103,2),$2}'  ${f_mns_gepreplayer_consistency_tree_simple} | sort | uniq -c | sort

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_marker_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_markers}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_tree_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_trees}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_check_mns
{
    gc_check_mns "BTREE"
    # gc_check_mns "JOURNAL"
}

############################### repo_gc checks ###############################

function repo_gc_check_configuration
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** REPO GC Configurations ***********************************************"

    get_cmf_configuration "com.emc.ecs.chunk.gc.repo.enabled com.emc.ecs.chunk.gc.repo.verification.enabled com.emc.ecs.chunk.gc.repo.reclaimer.no_recycle_window"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_rr_rebuild
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** RR Rebuild ***********************************************************"
    ## https://asdwiki.isus.emc.com:8443/display/ECS/REPO+GC+Trouble+Shooting+-+RR+Rebuild
    ## "/service/rrrebuild/status" is deprecated
    ## local rr_rebuild_tasks=$(dt_query http://${DATA_IP}:9101/service/rrrebuild/status | grep "^urn" | sed -e 's/\r//g' -e 's/^<.*<pre>//g' | grep "$rg" | awk '{print $NF}')

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Getting REFTABLE_REBUILD_TASK"

    local f_rr_rebuilds=${WORK_DIR}/repo_gc.rr_rebuilds

    echo "# http://${DATA_IP}:9101/diagnostic/OB/0/DumpAllKeys/REFTABLE_REBUILD_TASK/?showvalue=gpb&useStyle=raw" > ${f_rr_rebuilds}
    printf "#%-16s %-115s %-s\n" "Status" "OB_ID" "JOURNAL_REGION|Checkpoint" | tee -a ${f_rr_rebuilds}
    echo "#----------------------------------------------------------------------------------------------------------------------------------------------------------------" | tee -a ${f_rr_rebuilds}
    local dt_ids=$(validate_dt "OB" 0 "url")
    for ob_url in ${dt_ids}
        do
        local query_str="${ob_url}REFTABLE_REBUILD_TASK/?showvalue=gpb&useStyle=raw"
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Querying [ curl -L -s '${query_str}' ]"
        echo "# ${query_str}" >> ${f_rr_rebuilds}

        dt_query "${query_str}" | tee -a ${f_rr_rebuilds} > ${f_rr_rebuilds}.tmp
        awk 'BEGIN{
            status="-"
            ob_id="-"
            zone_id="-"
            jr_major="-"
            jr_minor="-"
            checkpoint="-"
            task_loop_done=0
        } {
            if ($1=="status:") {
                task_loop_done=0
                status=$2
            } else if ($1=="dtId:") {
                split($2,sl,"\"")
                ob_id=sl[2]
            } else if ($1=="zone:") {
                split($2,sl,"\"")
                zone_id=sl[2]
            } else if ($1=="subKey:") {
                jr_major=substr($2,8,16)
                jr_minor=substr($2,32,16)
                status="WaitingOBCCMarker"
            } else if ($1=="userKey:") {
                checkpoint=substr($2,5,64)
                status="ScaningOB"
            } else if ($1=="isFailed:") {
                task_loop_done=1
            }

            if ( task_loop_done==1 ) {
                if (status == "WaitingOBCCMarker") {
                    printf("%-17s %-115s %-s,%-s\n",status,ob_id,jr_major,jr_minor)
                } else if (status == "ScaningOB") {
                    printf("%-17s %-115s %-s\n",status,ob_id,checkpoint)
                } else {
                    printf("%-17s %-115s %-s\n",status,ob_id,"-")
                }
                status="-"
                ob_id="-"
                zone_id="-"
                jr_major="-"
                jr_minor="-"
                checkpoint="-"
                task_loop_done=0
            }
        }' ${f_rr_rebuilds}.tmp
    done
    echo "----------------------------------- END -------------------------------------------------------------------------------------------------------------------------"

    awk '{
        if ($1 == "" || substr($1,0,1) == "#") {
            next
        } else if ($1 == "DONE") {
            done_cnt++
        }else if ($1 == "ScaningOB") {
            scaning_ob_cnt++
        }else if ($1 == "WaitingOBCCMarker") {
            waiting_obccmarker_cnt++
        }else {
            other_cnt++
        }
        total_cnt++
    } END{
        if (total_cnt == 0) {
            done_ratio=0
            scaning_ob_ratio=0
            waiting_obccmarker_ratio=0
            other_ratio=0
        } else {
            done_ratio=100*done_cnt/total_cnt
            scaning_ob_ratio=100*scaning_ob_cnt/total_cnt
            waiting_obccmarker_ratio=100*waiting_obccmarker_cnt/total_cnt
            other_ratio=100*other_cnt/total_cnt
        }
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> RR Rebuild Status")
        print "-----------------------------------"
        printf("%-17s | %7lu\n", "Total DTs", total_cnt)
        print "-----------------------------------"
        printf("%-17s | %7lu %6.2f%\n", "WaitingOBCCMarker", waiting_obccmarker_cnt, waiting_obccmarker_ratio)
        print "-----------------------------------"
        printf("%-17s | %7lu %6.2f%\n", "ScaningOB", scaning_ob_cnt, scaning_ob_ratio)
        print "-----------------------------------"
        printf("%-17s | %7lu %6.2f%\n", "Done", done_cnt, done_ratio)
        print "-----------------------------------"
        printf("%-17s | %7lu %6.2f%\n", "Other", other_cnt, other_ratio)
        print "-----------------------------------"
    }' ${f_rr_rebuilds}

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_rr_rebuilds}"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_cleanup_jobs
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Cleanup Jobs *********************************************************"

    local f_cleanup_jobs=${WORK_DIR}/repo_gc.cleanup_jobs

    local dt_ids=$(validate_dt "OB" 0 "url")

    echo "# http://${DATA_IP}:9101/diagnostic/OB/0/DumpAllKeys/DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aaa&useStyle=raw" > ${f_cleanup_jobs}

    print_msg "line:${LINENO} ${FUNCNAME[0]} - Highlight with RED on Cleanup Job delay >= ${CLEANUP_JOB_DAY_DELAY_THRESHOLD} Days or Cleanup Job Count >= ${CLEANUP_JOB_CNT_THRESHOLD}:"
    printf "#%-50s %8s %-16s %-13s %8s\n" "DT_ID" "JobCount" "JRmajor" "Timestamp" "DayDelay" | tee -a ${f_cleanup_jobs}
    echo "#---------------------------------------------------------------------------------------------------" | tee -a ${f_cleanup_jobs}

    for ob_url in ${dt_ids}
        do
        local ob_id=$(echo ${ob_url} | awk -F '/' '{print $(NF-1)}')
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Querying Cleanup Jobs of ${ob_id}"

        dt_query "${ob_url}DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aa&useStyle=raw" ${f_cleanup_jobs}
        local cleanup_job_cnt=$(grep schemaType -c ${f_cleanup_jobs})

        dt_query "${ob_url}DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aa&maxkeys=1&showvalue=gpb&useStyle=raw" | awk -v v_cleanup_job_cnt=${cleanup_job_cnt} -v v_ob_id=${ob_id} 'BEGIN{
            if ($1=="schemaType") {
                time_readable=strftime("%Y-%m-%dT%H:%M:%S",substr($4,0,10))
                day_delay=(systime()-substr($4,0,10))/(60*60*24)
            } else if ($1=="subKey:") {
                jr_major=substr($2,8,16)
            }
        } END{
            printf("%-115s %8lu %-16s %-19s %8.2f\n",v_ob_id,v_cleanup_job_cnt,jr_major,time_readable,day_delay)
        }' | tee -a ${f_cleanup_job_simple} | awk -v v_cleaup_job_threshold=${CLEANUP_JOB_CNT_THRESHOLD} -v v_day_delay_threshold=${OB_CC_MARKER_DAY_DELAY_THRESHOLD} '{
            if ($NF>=v_day_delay_threshold || $2 >= v_cleaup_job_threshold) {
                print substr($0,65,999)
            }
        }'
    done
    echo "--------------------------- END --------------------------------------------------------------------------"

    awk '{cnt+=$2} END{
        if (cnt == 0) {
            print "CLEANUP_JOB is 0, maybe because"
            print "\t1. writing into this VDC stopped long time ago or never happened"
            print "\t2. IC has issue"
        }
    }' ${f_cleanup_job_simple}

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_cleanup_job_simple}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_common_check_obccmarker
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** OB CC Marker *********************************************************"

    local f_ob_cc_markers=${WORK_DIR}/gc_common.ob_cc_markers
    local f_ob_cc_marker_simple=${WORK_DIR}/gc_common.ob_cc_marker.simple

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Highlight OBCCMarker's JR Gap(MAX_JR-JR) >= ${OB_CC_MARKER_GAP_THRESHOLD} or JR Ratio(JR/MAX_JR) >= ${OB_CC_MARKER_RATIO_THRESHOLD}%:"
    local dt_ids=$(validate_dt "OB" 0)
    local a_ob=$(head -n1 <<< "${dt_ids}")
    dt_query "http://${DATA_IP}:9101/gc/obCcMarker/${a_ob}" | xmllint --format - 2>/dev/null | awk -F '<|>' '{
        if ( (substr($2,0,14) == "remote_zone_id" || $2 == "local_zone_id") && substr($3,0,36) == "urn:storageos:VirtualDataCenterData:") {
            print $3,$2
            zone_name_id_map[$2]=$3
        }
    } END{
        printf("%-64s ", "")
        for (zone_name in zone_name_id_map) {
            if (zone_name == "local_zone_id") {
                printf("%13s ", zone_name)
            } else {
                printf("%24s ", zone_name)
            }
        }
        print ""
        printf("%-64s %24s\n", "", "MaxJR JR JRGap Raito")
    }' | tee ${f_ob_cc_marker_simple}

    for ob_id in ${dt_ids}
        do

        local query_str="http://${DATA_IP}:9101/gc/obCcMarker/${ob_id}"
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${query_str}' ]"

        local ob_cc_marker=$(dt_query "${query_str}" | xmllint --format - 2>/dev/null)
        echo "${ob_cc_marker}" | grep -q 'HTTP ERROR'
        if [[ $? -eq 0 || -z ${ob_cc_marker} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get obCcMarker [ curl -L -s '${query_str}' ]"
            continue
        fi

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking ob_cc_marker for OB: ${ob_id}"
        echo ${query_str} >> ${f_ob_cc_markers}
        echo "${ob_cc_marker}" | tee -a ${f_ob_cc_markers} | awk -v v_ob_id=${ob_id} -v v_ratio_threshold=${OB_CC_MARKER_RATIO_THRESHOLD} -v v_gap_threshold=${OB_CC_MARKER_GAP_THRESHOLD} -F '<|>' '{
            if ($2=="local_zone_id" || substr($2,0,14)=="remote_zone_id") {
                zone_name=$2
                zone_name_id_map[zone_name]=$3
            } else if ($2=="journal_entry") {
                split($3,sl," ")
                zone_name_jr_map[zone_name]=strtonum("0x"sl[8])
            } else if ($2=="max_journal_entry") {
                split($3,sl," ")
                zone_name_maxjr_map[zone_name]=strtonum("0x"sl[8])
            }
        } END{
            printf("%-64s ", substr(v_ob_id,53,64))
            for (zone_name in zone_name_id_map) {
                m_jr=zone_name_maxjr_map[zone_name]
                jr=zone_name_jr_map[zone_name]
                if (m_jr == "") {
                    printf("%24s ", "N/A")
                } else {
                    ratio=100*jr/m_jr
                    jr_gap=m_jr-jr
                    if (jr == "") {
                        full_str=sprintf("%x", m_jr)
                        printf("%13s ", full_str)
                    } else {
                        if (ratio < v_ratio_threshold || jr_gap >= v_gap_threshold){
                            full_str=sprintf("\033[1;31m%x %x %3lu %5.2f%\033[0m", m_jr, jr, jr_gap, ratio)
                            printf("%35s ", full_str)
                        } else {
                            full_str=sprintf("%x %x %3lu %5.2f%", m_jr, jr, jr_gap, ratio)
                            printf("%24s ", full_str)
                        }
                    }
                }
            }
            print ""
        }' | tee -a ${f_ob_cc_marker_simple}
    done

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_ob_cc_marker_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Detials of all DTs: ${PUBLIC_IP}:${f_ob_cc_markers}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_check_mns
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Min Not Sealed *******************************************************"

    local check_type=$1  ## "REPO" or "BTREE" or "JOURNAL"
    declare -l check_type_lowercase=${check_type}
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Checking Min Not Sealed for ${check_type} GC ..."


    ###### step 1, CHUNK_SEQUENCE
    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 1, Checking CHUNK_SEQUENCE of CT tables ..."

    local ct_dt_ids=$(validate_dt "CT" 1)
    local dt_cnt=$(echo "${ct_dt_ids}" | wc -l)

    local query_urls=$(dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_SEQUENCE/?showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http')
    if [[ -z ${query_urls} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ curl -L -s 'http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_SEQUENCE/?showvalue=gpb&useStyle=raw' ]"
        return
    fi

    local query_urls_cnt=$(echo "${query_urls}" | wc -l)
    local missing_dt=$(echo "scale=0; ${dt_cnt}-${query_urls_cnt}" | bc)
    if [[ ${missing_dt} -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ${missing_dt} DTs have no CHUNK_SEQUENCE"
    fi

    local f_min_not_sealeds_chunk_sequence=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealeds.chunk_sequence
    local f_min_not_sealed_chunk_sequence_simple=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealed.chunk_sequence.simple

    for query_url in $(echo "${query_urls}")
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ruunig [ curl -L -s '${query_url}' ]"

        echo "${query_url}" >> ${f_min_not_sealeds_chunk_sequence}
        dt_query "${query_url}" | tee -a ${f_min_not_sealeds_chunk_sequence} | awk -v v_ct_id=$(echo ${query_url} | awk -F '/' '{print $4}') '{
            if($1=="schemaType"){
                key=$0
            }else if ($1=="value:") {
                value=$0
                print v_ct_id,key,value
                key="-"
                value="-"
            }
        }' | sed 's/rgId  dataType/rgId None dataType/g' >> ${f_min_not_sealed_chunk_sequence_simple}
    done
    awk '/schemaType/{print $5,$7}' ${f_min_not_sealed_chunk_sequence_simple} | sort | uniq -c

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_min_not_sealed_chunk_sequence_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_min_not_sealeds_chunk_sequence}"
    echo
    echo

    ###### step 2, GC_REF_COLLECTION
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 2, Checking ${check_type} GC_REF_COLLECTION for each CT-DT pair ..."

    local dt_ids=$(validate_dt "PR" 1)
    local dt_cnt=$(echo "${dt_ids}" | wc -l)

    query_urls=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/GC_REF_COLLECTION/?type=${check_type}&showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http')
    if [[ -z ${query_urls} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ curl -L -s 'http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/GC_REF_COLLECTION/?type=${check_type}&showvalue=gpb&useStyle=raw' ]"
        return
    fi

    query_urls_cnt=$(echo "${query_urls}" | wc -l)
    missing_dt=$(echo "scale=0; ${dt_cnt}-${query_urls_cnt}" | bc)
    if [[ ${missing_dt} -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ${missing_dt} DTs have no GC_REF_COLLECTION"
    fi

    local f_min_not_sealeds_gc_ref=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealeds.gc_ref
    local f_min_not_sealed_gc_ref_simple=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealed.gc_ref.simple

    for query_url in $(echo "${query_urls}")
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - running [ curl -L -s '${query_url}' ]"

        local ct_owner=$(echo ${query_url} | awk -F ':|/' '{print $4}')
        local ct_id=$(echo ${query_url} | awk -F '/' '{print $4}')
        echo "${query_url}" >> ${f_min_not_sealeds_gc_ref}
        dt_query "${query_url}" >> ${f_min_not_sealeds_gc_ref}
        # dt_query "${query_url}" | while read line
            # do
            # echo "${line}" >> ${f_min_not_sealeds_gc_ref}
            # if [[ ${line:0:7} == "chunkId" ]] ; then
                # local mns_value=$(get_chunk_info "$(echo ${line} | awk -F '"' '{print $2}')" | awk '$1 == "minNotSealedSequenceNumber:" {print $2}')
                # echo "minNotSealedValue: ${mns_value}" >> ${f_min_not_sealeds_gc_ref}
            # fi
        # done
    done
    awk '/^schemaType/{print $4,$10}' ${f_min_not_sealeds_gc_ref} | sort | uniq -c

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_min_not_sealed_gc_ref_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_min_not_sealeds_gc_ref}"
    echo
    echo

    ###### step 3, Combine
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 3, Checking results ..."

    local f_min_not_sealeds=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealeds
    local f_min_not_sealed_simple=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealed.simple

    print_msg "line:${LINENO} ${FUNCNAME[0]} - CT whoes min-not-sealed ratio >= ${MNS_RATIO_THRESHOLD}, Ratio=(Sequence-MNSminor)/MNSminor"
    printf "%-51s %-78s %19s %9s %6s\n" "DTID" "Replication Group" "MNS(major/minor)" "Sequence" "Ratio"
    echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------------"

    printf "%-79s %-78s %19s %9s %5s\n" "DTID" "Replication Group" "MNS(major/minor)" "Sequence" "Ratio" >> ${f_min_not_sealed_simple}
    echo "---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------" >>${f_min_not_sealed_simple}

    for rg in $(awk '/schemaType/{print $10}' ${f_min_not_sealeds_gc_ref} | sort | uniq)
        do

        for ct in $(echo "${ct_dt_ids}")
            do

            printf "%-79s %-78s " "${ct}" "${rg}"
            grep -e schemaType -e minNotSealedValue ${f_min_not_sealeds_gc_ref} | grep -A1 "GC_REF_COLLECTION.*"${ct}".*rgId ${rg}" | grep minNotSealedValue | awk 'BEGIN{
                minor=2^53; major=0
            } {
                if($2<minor) {
                    minor=$2
                } else if ($2>major) {
                    major=$2
                }
            } END{
                printf("%9s %9s ",major,minor)
            }'

            local sequence=$(awk -v v_ct=${ct} -v v_rg=${rg} -v v_type=${check_type} '{
                if ($1~v_ct && $5==v_rg && $7==v_type) {
                    print $NF
                }
            }' ${f_min_not_sealed_chunk_sequence_simple})
            [[ -z ${sequence} ]] && sequence="-"
            printf "%9s\n" ${sequence}
        done
    done | awk '{printf("%s %6.2f\n", $0, ($5-$4)/($4+1))}' | tee -a ${f_min_not_sealed_simple} | awk -v v_mns_ratio_threshold=${MNS_RATIO_THRESHOLD} '{
        if ($NF >= v_mns_ratio_threshold || $NF < 0) {
            print substr($0,29,999)
        }
    }'
    echo "--------------------------- END -------------------------------------------------------------------------------------------------------------------------------------------------------------------" >> ${f_min_not_sealed_simple}
    echo "--------------------------- END ---------------------------------------------------------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_min_not_sealed_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_min_not_sealeds}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_mns
{
    gc_check_mns "REPO"
}

function repo_gc_check_mns_old_fashion
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Min Not Sealed (old fashion) *****************************************"

    ###
    local dt_ids=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/1/" | xmllint --format - |grep table_detail_link)
    if [[ -z ${dt_ids} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get all PRs"
        return
    fi
    local dt_cnt=$(echo "${dt_ids}" | wc -l)
    if [[ $(echo "${dt_cnt}%128" | bc) -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - Failed to get full PRs"
    fi

    local query_urls_cnt=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/DIRECTORYTABLE_RECORD/?type=METERING_JOURNAL_PARSER_MARKER&showvalue=gpb&useStyle=raw" | grep schemaType -c)
    local missing_dt=$(echo "scale=0; ${dt_cnt}-${query_urls_cnt}" | bc)
    if [[ ${missing_dt} -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ${missing_dt} DTs have no DIRECTORYTABLE_RECORD->METERING_JOURNAL_PARSER_MARKER which block(s) JournalParser"
    fi

    ###
    local f_min_not_sealed_log=${WORK_DIR}/repo_gc.min_not_sealed.log.old_fashion
    local f_min_not_sealed_simple=${WORK_DIR}/repo_gc.min_not_sealed.simple.old_fashion
    local f_mns_not_sealeds=${WORK_DIR}/repo_gc.mns_not_sealeds.old_fashion
    local f_mns_not_sealed_chunks=${WORK_DIR}/repo_gc.mns_not_sealed.chunks.old_fashion
    touch ${f_mns_not_sealed_chunks}

    local files=''
    while read node
        do
        files="$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name cm-chunk-reclaim.log* -mtime -1 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null ")" 2>/dev/null
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"
        if [[ -z ${files} ]] ; then
            print_msg "line:${LINENO} ${FUNCNAME[0]} - There's no cm-chunk-reclaim.log within 1 day in node ${node}"
            continue
        fi

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - extracting log for mns progres in node ${node}"
        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep 'does not pass progress check, reclaim skipped' ${files} | awk -F 'gz:|.log:' '{if (substr(\\\$1,0,9)==\\\"/var/log/\\\") {print \\\$NF} else {print \\\$0} }' \" " 2>/dev/null | sort -n -k20 > ${f_min_not_sealed_log}.${node} &
    done < ${MACHINES}
    wait

    cat ${f_min_not_sealed_log}.* | sort -r > ${f_min_not_sealed_log}
    if [[ ! -f ${f_min_not_sealed_log} || ! -s ${f_min_not_sealed_log} ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - There's no min-not-seal logged within 1 day in all nodes"
        return
    fi

    local dt_ids=$(dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/?useStyle=raw" | xmllint --format - 2>/dev/null | awk -F '<|>' '/<id>/{print $3}')
    if [[ -z ${dt_ids} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get all CTs"
        return
    fi
    local dt_cnt=$(echo "${dt_ids}" | wc -l)
    if [[ $(echo "${dt_cnt}%128" | bc) -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - Failed to get full CTs"
    fi

    ### parse log
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking min-not-sealed ..."
    print_msg "line:${LINENO} ${FUNCNAME[0]} - CT whoes min-not-sealed delay ratio >= ${MNS_RATIO_THRESHOLD}"
    printf "%-15s %-80s %-37s %10s %10s %-5s\n" "CT_OWNER" "CT_ID" "Chunk_ID" "Sequence" "Progress" "Ratio" | tee -a ${f_min_not_sealed_simple}
    echo "------------------------------------------------------------------------------------------------------------------------------------------------------------------" | tee -a ${f_min_not_sealed_simple}

    local ct_found=0
    while read line
        do

        ## Find the suspect CT table with issues on min-not-seal progress
        local progress=$(echo "${line}" | awk '{print $20}')
        local sequence_number=$(echo "${line}" | awk -F ' |,' '{print $21}')
        if [[ ${sequence_number} -le 0 ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - sequence_number ${sequence_number} is not expected."
            continue
        fi
        local ratio=$(echo "scale=0; 100*(${sequence_number}-${progress})/${sequence_number}" | bc)

        local chunk_id=$(echo "${line}" | awk '{print $8}')
        if [[ -z ${chunk_id} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get chunk_id from current line of log"
            continue
        fi

        grep -q "${chunk_id}" ${f_mns_not_sealed_chunks}
        if [[ $? -eq 0 ]] ; then
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - bypass ${chunk_id} which already checked"
            continue
        fi

        echo ${chunk_id} >> ${f_mns_not_sealed_chunks}

        local query_url=$(dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK?chunkId=${chunk_id}&maxkeys=1&showvalue=gpb&useStyle=raw" | grep schemaType -B1 | grep '^http' | awk -F '/CHUNK' '{print $1}')
        if [[ -z ${query_url} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get CT owner for chunk ${chunk_id}"
            continue
        fi

        local ct_id=$(echo ${query_url} | awk -F '/' '{print $4}')
        local ct_owner=$(echo ${query_url} | awk -F '/|:' '{print $4}')
        grep -q "${ct_id}" ${f_min_not_sealed_simple}
        if [[ $? -eq 0 ]]; then
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - bypass ${chunk_id} whose CT already checked"
            continue
        fi

        ct_found=$((${ct_found+1}))

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${ct_owner} ${ct_id} ${chunk_id} sequence_number: ${sequence_number} progress : ${progress} ratio: ${ratio}"
        printf "%-15s %-80s %-37s %10s %10s %5s\n" "${ct_owner}" "${ct_id}" "${chunk_id}" "${sequence_number}" "${progress}" "${ratio}" >> ${f_min_not_sealed_simple}

        if [[ ${progress} -le 0 ]] ; then
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${ct_owner} ${ct_id} ${chunk_id} sequence_number: ${sequence_number} progress: ${progress}, RepoReclaimer may fail to get latest min-not-seal progress"
            printf "%-15s %-80s %-37s %10s %10s %s\n" "${ct_owner}" "${ct_id}" "${chunk_id}" "${sequence_number}" "${progress}" "RepoReclaimer may fail to get latest min-not-seal progress"

        elif [[ ${ratio} -gt ${MNS_RATIO_THRESHOLD} ]] ; then
            ## Find the OB table which blocks min-not-seal progress for one CT table
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} -  ${ct_owner} ${ct_id} ${chunk_id} sequence_number: ${sequence_number} progress: ${progress} ratio: ${ratio}, There's issue on min-not-seal progress"
            printf "%-15s %-80s %-37s %10s %10s %5s\n" "${ct_owner}" "${ct_id}" "${chunk_id}" "${sequence_number}" "${progress}" "${ratio}"

            local mns_progress=$(dt_query "http://${DATA_IP}:9101/gc/minNotSealedProgress/${COS}/${ct_id}" | xmllint --format - 2>/dev/null)
            if [[ -z ${mns_progress} ]] ; then
                print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ curl -L -s http://${DATA_IP}:9101/gc/minNotSealedProgress/${COS}/${ct_id} ]"
                continue
            fi

            ####
            echo "" | tee -a ${f_min_not_sealed_simple}
            echo "OB who is blocking min-not-sealed, please check JournalParser for these OB table:" | tee -a ${f_min_not_sealed_simple}
            echo "-------------------------------------------------------------------------------------" | tee -a ${f_min_not_sealed_simple}

            ## TODO, using read line....
            local loop_end=0
            echo "${mns_progress}" | tee ${f_mns_not_sealeds}.${ct_id} | grep -e final_progress -e rgId | while read line
                do

                local key=$(echo ${line} | awk -F '<|>' '{print $2}')
                local value=$(echo ${line} | awk -F '<|>' '{print $3}')
                if [[ "${key}" == "rgId" ]] ; then
                    loop_end=0
                    rg_id=${value}
                elif [[ "${key}" == "final_progress" ]] ; then
                    final_progress=${value}
                    loop_end=1
                fi

                if [[ ${loop_end} -eq 1 ]] ; then
                    loop_end=0
                    local ob_owner=$(echo "${mns_progress}" | grep -B1 "<minNotSealedSequenceNumber>${final_progress}</minNotSealedSequenceNumber>" | awk -F '<|>' '/urn:storageos/{print $3}')
                    echo "${rg_id} final_progress: ${final_progress} ${ob_owner}" | tee -a ${f_min_not_sealed_simple}
                    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - OB who is bloking min-not-seal, please check JournalParser for this OB table: [ ${ob_owner} ]"
                fi
            done
        fi

        if [[ ${ct_found} -eq ${ct_ids_cnt} ]] ; then
            break
        fi

    done < ${f_min_not_sealed_log}

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_min_not_sealed_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_min_not_sealeds_chunk_sequence}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_verification
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** GC Verification ******************************************************"

    local f_verifications=${WORK_DIR}/repo_gc.verifications
    local f_verification_simple=${WORK_DIR}/repo_gc.verification.simple

    dt_query "http://${DATA_IP}:9101/triggerGcVerification/queryCacheStatus" ${f_verifications}
    grep -q 'HTTP ERROR' ${f_verifications}
    if [[ $? -eq 0 || ! -f ${f_verifications} || ! -s ${f_verifications} ]]; then
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Failed to get [curl -L -s http://${DATA_IP}:9101/triggerGcVerification/queryCacheStatus ], will retry after 10 seconds"
        # repo_gc_check_verification_old_fashion
        # return
        sleep 10
    fi

    print_msg "line:${LINENO} ${FUNCNAME[0]} - OB whose timestamp <= refreshListTime and delay >= ${VERIFICATION_DAY_DELAY_THRESHOLD} days:"
    awk 'BEGIN{
        host_node="-"
        refresh_list_time="-"
        cos_local="-"
        dt_level="-"
        replication_group="-"
        gc_type="-"
        ob_id="-"
        ob_ts="-"
        node_loop_done=0
        printf("%-15s %-115s %-13s %-13s %-19s %8s\n","HOST","OB_ID","refreshTime","TimeStamp","TimeStampReable","DayDelay")
        print "----------------------------------------------------------------------------------------------------------------------------"
    } {
        if ($1=="IP:") {
            host_node=$2
        } else if ($1=="refreshListTime:") {
            refresh_list_time=$2
        } else if (substr($1,0,11)=="ScanTaskKey") {
            split($1,sl,"'"'"'")
            cos_local=sl[2]
            split($2,sl,"=")
            split(sl[2],sll,"}")
            dt_level=sll[1]
        } else if (substr($1,0,9)=="RgTypeKey") {
            split($1,sl,"(")
            split(sl[2],sll,")")
            replication_group=sll[1]
            split($2,sl,"=")
            split(sl[2],sll,"}")
            gc_type=sll[1]
        } else if (substr($1,0,28)=="urn:storageos:OwnershipInfo:") {
            split($1,sl,"::")
            ob_id=sl[1]":"
            ob_ts=sl[2]
            refresh_list_time_gap=(substr(ob_ts,0,10)-substr(ob_ts,0,10))/(60*60*24)
            day_delay=(systime()-substr(ob_ts,0,10))/(60*60*24)
            printf("%-15s %-115s %-13s %-13s %-19s %8.2f\n",host_node,ob_id,refresh_list_time,ob_ts,strftime("%Y-%m-%dT%H:%M:%S",substr(ob_ts,0,10)),day_delay)
        } else if ($0=="") {
            node_loop_done=1
        }

        if (node_loop_done==1) {
            print "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            host_node="-"
            refresh_list_time="-"
            cos_local="-"
            dt_level="-"
            replication_group="-"
            gc_type="-"
            ob_id="-"
            ob_ts="-"
            node_loop_done=0
        }
    } END{
        print "-------------------------- END ---------------------------------------------------------------------------------------------"
    }' ${f_verifications} | tee -a ${f_verification_simple} | awk -v v_day_delay=${VERIFICATION_DAY_DELAY_THRESHOLD} '{
        if ($4!="-" && $4<=$3 && $6>=v_day_delay){
             printf("%-15s %-51s %-13s %-13s %-19s %8s\n",$1,substr($2,65,999),$3,$4,$5,$6)
        }
        if (substr($0,3,10) == "----------"){
            print $0
        }
    }'


    ## list OB that are not listed in ${f_verifications}
    print_msg "line:${LINENO} ${FUNCNAME[0]} - OBs that are not in verification:"
    local dt_ids=$(validate_dt "OB" 0)
    local dt_cnt=$(echo "${dt_ids}" | wc -l)
    local ob_verification_cnt=$(grep -c 'urn:storageos:OwnershipInfo:' ${f_verifications})
    local missing_ob_cnt=$(echo "scale=0; ${dt_cnt}-${ob_verification_cnt}" | bc)
    if [[ ${missing_ob_cnt} -ne 0 ]] ; then
        echo "    ${missing_ob_cnt}" | tee -a ${f_verification_simple}
        echo
        for ob_id in $(echo "${dt_ids}")
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking CHUNK_REFERENCE_SCAN_PROGRESS for OB: ${ob_url}"
            grep -q "${ob_id}" ${f_verifications}
            if [[ $? -ne 0 ]] ; then
                echo "    ${ob_id}" | tee -a ${f_verification_simple}
            fi
        done
    else
        echo "    NOPE"
    fi

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_verification_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_verifications}"
    echo
    echo

    repo_gc_check_verification_task
    repo_gc_check_verification_speed

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_verification_task
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # local f_repo_gc_verification_tasks=${WORK_DIR}/repo_gc.verification_tasks
    # print_msg "line:${LINENO} ${FUNCNAME[0]} - On-going verification tasks:"
    # dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${ZONE_ID}&type=REPO&time=0&useStyle=raw" ${f_repo_gc_verification_tasks}

    # local verification_task_cnt=$(grep -c schemaType ${f_repo_gc_verification_tasks})
    # print_info "line:${LINENO} ${FUNCNAME[0]} -     ${verification_task_cnt}"
    # echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function repo_gc_check_verification_speed
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    print_msg "line:${LINENO} ${FUNCNAME[0]} - Checking verification speed ..."

    ############################## get batch number
    local f_verification_repo_thread_conf=${WORK_DIR}/repo_gc.verification.repo_thread_conf
    while read node
        do
        echo -n "    ${node} " >> ${f_verification_repo_thread_conf}
        ssh -n ${node} "sudo docker exec object-main sh -c \"grep repoScanThreadPoolConfig /opt/storageos/conf/shared-threadpool-conf.xml -A2 \" 2>/dev/null" 2>/dev/null | awk -F '"' '/corePoolSize/{print $4}' >> ${f_verification_repo_thread_conf}
    done < ${MACHINES}
    print_msg "line:${LINENO} ${FUNCNAME[0]} -   Thread cnt for verification:"
    cat ${f_verification_repo_thread_conf}
    local verification_thread_cnt=$(sort -k2 -n ${f_verification_repo_thread_conf} | head -n1 | awk '{print $2}') ## get smallest

    ############################## collect log for how long one round of verification took
    local f_verification_round_time=${WORK_DIR}/repo_gc.verification_round_time_from_log
    local files=''
    while read node
        do
        files="$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name blobsvc-chunk-reclaim.log* -mtime -2 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null ")" 2>/dev/null
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"
        if [[ -z ${files} ]] ; then
            print_info "line:${LINENO} ${FUNCNAME[0]} -   There's no blobsvc-chunk-reclaim.log within 2 day in node ${node}"
            continue
        fi

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - extracting log for mns progres in node ${node}"
        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep 'This round GC verification' ${files} \" " 2>/dev/null | awk '{printf("%-115s %5.1f %12lu\n",substr($12,14,999),$14/(1000*60*60),$18) }' > ${f_verification_round_time}.${node} &
    done < ${MACHINES}
    wait

    cat ${f_verification_round_time}.* | sort -n -r -k3 > ${f_verification_round_time}
    if [[ ! -f ${f_verification_round_time} || ! -s ${f_verification_round_time} ]] ; then
        print_info "line:${LINENO} ${FUNCNAME[0]} -   There's no verification done a round within given days in all nodes"
        return
    fi

    ############################## get OwnershipInfo for effactive OB distritution
    local f_dt_ownershipinfo=${WORK_DIR}/gc_common.dt_ownershipinfo
    dt_query "http://${DATA_IP}:9101/diagnostic/DumpOwnershipInfo" ${f_dt_ownershipinfo}

    if [[ ! -f ${f_dt_ownershipinfo} || ! -s ${f_dt_ownershipinfo} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get DumpOwnershipInfo after 3 retry"
        return
    fi

    print_msg "line:${LINENO} ${FUNCNAME[0]} -   OB balance for all RGs:"
    awk -F ':' '/_OB_/{print $8}' ${f_dt_ownershipinfo} | tr -d '[[:blank:]]' | sort | uniq -c

    for rg_id in $(echo "${REPLICATION_GROUPS}")
        do
        print_msg "line:${LINENO} ${FUNCNAME[0]} -   For RG ${rg_id}:"
        ############################## get effactive OB balance
        local balance=$(awk -F ':' -v v_rg_id_short=${rg_id:35:36} '$0 ~ v_rg_id_short"_OB_" {print $8}' ${f_dt_ownershipinfo} | tr -d '[[:blank:]]' | sort | uniq -c)
        if [[ -z ${balance} ]] ; then
            print_info "line:${LINENO} ${FUNCNAME[0]} -     Didn't find OB of this RG, maybe RG was Inactived"
            continue
        else
            print_info "line:${LINENO} ${FUNCNAME[0]} -     OB balance:"
            echo "${balance}"
            echo
        fi

        local ob_cnt_max=$(echo "${balance}" | sort -n | tail -n1 | awk '{print $1}')

        ############################## how long one round of verification took
        awk -v v_rg_id_short=${rg_id:35:36} '$0 ~ v_rg_id_short' ${f_verification_round_time} | awk -v v_verification_thread_cnt=${verification_thread_cnt} -v v_ob_cnt_max=${ob_cnt_max} 'BEGIN{
            max_hr=-1
            max_ob="-"
            hr_cnt=0
            obj_cnt=0
        } {
            if ($2 > max_hr) {
                max_hr=$2
                max_ob=$1
                max_obj_cnt=$3
            }
            obj_cnt+=$3
            hr_cnt+=$2
        } END{
            if (NR > 0 && hr_cnt > 0 && v_verification_thread_cnt > 0) {
                printf("    - Average: %.2f hours, scanned %lu objects, %.2f objects/second\n", hr_cnt/NR, obj_cnt/NR, obj_cnt/(hr_cnt*60*60))
                printf("    - Slowest: %.2f hours, scanned %lu objects, on OB %s\n", max_hr, max_obj_cnt, max_ob)
                round_time=(v_ob_cnt_max/v_verification_thread_cnt)*(hr_cnt/NR)
                if (round_time < max_hr) {round_time=max_hr}
                printf("    - This VDC need ~ %.2f hours to finish one round GC verification.\n", round_time)
            } else {
                print "    - There seems no OB verified or there are not many objects in OBs of this RG"
            }
        }'
        echo
    done
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function repo_gc_check_verification_old_fashion
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Verification (old fashion) *******************************************"

    local dt_ids=$(validate_dt "OB" 0)

    local f_verifications=${WORK_DIR}/repo_gc.verifications.old_fashion
    for ob_id in $(echo "${dt_ids}")
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking CHUNK_REFERENCE_SCAN_PROGRESS for OB: ${ob_id}"

        local progress_out=$(dt_query "http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/CHUNK_REFERENCE_SCAN_PROGRESS?type=REPO&dt=${ob_id}&sequence=0&maxkeys=1&useStyle=raw")

        echo "${progress_out}" | tee -a ${f_verifications} | grep -q schemaType
        if [[ $? -ne 0 ]] ; then
            print_msg "line:${LINENO} ${FUNCNAME[0]} - There's no CHUNK_REFERENCE_SCAN_PROGRESS for OB: ${ob_id}, please check why the scanner cannot load tasks to start a new round"
            continue
        fi

        local task_key=$(echo "${progress_out}" | awk -F '@' '/userKey/ {print $3}' | awk -F '\' '{print $1}')
        if [[ -z ${task_key} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - failed to get userKey"
            continue
        fi

        local task_create_time=$(echo "${progress_out}" | awk '/createTime/ {print $2}')
        if [[ -z ${task_create_time} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - failed to get createTime"
            continue
        fi

        local current_ts=$(date -d "$(date)" +%s)
        local minute_delta=$(echo "scale=0; (${current_ts}-${task_create_time:0:10})/60" | bc)
        if [[ -z ${minute_delta} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - failed to caculate minute_delta"
            continue
        fi

        if [[ ${minute_delta} -gt 5 ]] ; then
            print_msg "line:${LINENO} ${FUNCNAME[0]} - CHUNK_REFERENCE_SCAN_PROGRESS for OB: ${ob_id} userKey ${task_key} createTime ${task_create_time} is not moving forward in 5 minutes"

            ## Check if GC Verification is blocked through logs
            # TODO

            ## Check Error log for GC Verification Scanner
            # TODO
        fi
    done

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Results of all DTs: ${PUBLIC_IP}:${f_verification_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_verifications}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_check
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"
    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Checking BTREE GC ..."

    [[ ${CHECK_BTREE_CONF} -eq 1 ]] && btree_gc_check_configuration
    [[ ${CHECK_BTREE_MNS} -eq 1 ]] && btree_gc_check_mns
    [[ ${CHECK_BTREE_MARKER} -eq 1 ]] && btree_gc_check_btree_markers

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"
    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Checking REPO GC ..."

    [[ ${CHECK_REPO_CONF} -eq 1 ]] && repo_gc_check_configuration
    [[ ${CHECK_REPO_RRREBUILD} -eq 1 ]] && repo_gc_check_rr_rebuild
    [[ ${CHECK_REPO_CLEANUP} -eq 1 ]] && repo_gc_check_cleanup_jobs
    [[ ${CHECK_REPO_MNS} -eq 1 ]] && repo_gc_check_mns
    [[ ${CHECK_REPO_VERIFICATION} -eq 1 ]] && repo_gc_check_verification

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


# function search_log
# {
    # LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # local issue_id="$1"
    # local search_str="$2"
    # local files=''
    # local log_searched=${WORK_DIR}/known_issue.${issue_id}.log
    # while read node
        # do
        # files="$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name cm-chunk-reclaim.log* -mtime -1 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null ")" 2>/dev/null
        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"
        # if [[ -z ${files} ]] ; then
            # print_msg "line:${LINENO} ${FUNCNAME[0]} - There's no cm-chunk-reclaim.log within 1 day in node ${node}"
            # continue
        # fi

        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - extracting log for mns progres in node ${node}"
        # ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep 'does not pass progress check, reclaim skipped' ${files} | awk -F 'gz:|.log:' '{if (substr(\\\$1,0,9)==\\\"/var/log/\\\") {print \\\$NF} else {print \\\$0} }' \" " 2>/dev/null | sort -n -k20 > ${f_min_not_sealed_log}.${node} &
    # done < ${MACHINES}
    # wait

    # while read node
        # do
        # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Collecting log from node ${node} ..."

        # #print_msg "------------------------------------------------- ${node} -------------------------------------------------"
        # printf " ------------------------------------------------ %-15s -----------------------------------------------\n" "${node}"

        # if [[ ! -f ${log_searched}.${node} || ! -s ${log_searched}.${node} ]] ; then
            # echo "NOPE"
            # continue
        # fi

        # local svcs=$(awk '{print $3}' ${log_searched}.${node} | sort | uniq )
        # local dates=$(awk '{print $2}' ${log_searched}.${node} | sort | uniq | tail -n7)

        # printf "%-15s " "Services\Date"
        # for date in $(echo ${dates})
            # do
            # printf "%13s " "${date}"
        # done
        # printf "\n"

        # for svc in $(echo ${svcs})
            # do
            # printf "%-15s " "${svc}"
            # for date in $(echo ${dates})
                # do
                # local cnt=$(awk -v v_date=${date} -v v_svc=${svc} '{if ($2==v_date && $3==v_svc) {print $1}}' ${log_searched}.${node})
                # [[ -z ${cnt} ]] && cnt=0
                # printf "%13s " "${cnt}"
            # done
            # printf "\n"
        # done
        # printf "\n"
    # done < ${MACHINES}

    # LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
# }

function check_known_issue
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    for issue_id in ${!KNOWN_ISSUES[@]}
        do
        search_log "${issue_id}" "${KNOWN_ISSUES[${issue_id}]}"
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

########################## Main logic ##############################

function main
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_info "line:${LINENO} ${FUNCNAME[0]} - ${SCRIPTNAME} version ${VERSION}"

    ## Initialize globals
    get_vdc_info

    [[ ${CHECK_RESTARTS} -eq 1 ]] && gc_common_check_services_restarts

    if [[ ${CHECK_CONFIG} -eq 1 ]] ; then
        repo_gc_check_configuration
        btree_gc_check_configuration
    fi

    if [[ ${CHECK_CAPACITY} -eq 1 ]] ; then
        capacity_usage_from_stats
        capacity_from_ssm
        capacity_from_blockbin
    fi

    [[ ${CHECK_DTINIT} -eq 1 ]] && gc_common_dtinit

    [[ ${CHECK_REPO_GC} -eq 1 ]] && repo_gc_check

    [[ ${CHECK_BTREE_GC} -eq 1 ]] && btree_gc_check

    [[ ${CHECK_COMMON_OBCCMARKER} -eq 1 ]] && gc_common_check_obccmarker

    # clean_up_work_dir

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

[[ $(whoami) != "admin" ]] && print_error "Please run as admin outside container" && exit 0

trap clean_up SIGINT

parse_args $*

CLEANUP_JOB_CNT_THRESHOLD=1500
OB_CC_MARKER_RATIO_THRESHOLD=85 #%
OB_CC_MARKER_GAP_THRESHOLD=20
MNS_RATIO_THRESHOLD=0.25
MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD=7
MNS_PARSER_MARKER_DAY_DELAY_THRESHOLD=${MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD}
MNS_CC_MARKER_DAY_DELAY_THRESHOLD=${MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD}
VERIFICATION_DAY_DELAY_THRESHOLD=7

WORK_DIR_PARENT=/home/admin/gc_diagnosis
WORK_DIR=${WORK_DIR_PARENT}/$(date '+%Y%m%dT%H%M%S')

mkdir -p ${WORK_DIR} 2>/dev/null
[[ $? -ne 0 ]] && echo "Failed to manipulate directory ${WORK_DIR}" && exit 0

main

########################## Main logic END ##############################