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
VERSION="0.5.0"
# 0.5.0 - Initial version, for EE/Dev only
# 0.6.0 -
# 0.7.0 -
# 0.9.0 -
# 1.0.0 -
##########################################################################

# Author:  Alex Wang (alex.wang2@emc.com)

SCRIPTNAME="$(basename $0)"
# SCRIPTDIR="$(dirname "$(realpath -e "$0")")"
SCRIPTDIR="$(dirname "$(readlink -f "$0")")"
echo "${SCRIPTNAME} version ${VERSION}"

######################################################## Utility ###############################################################
#################################### Logs Utility ##################################

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

#################################### Logs Utility END ##############################

#################################### Output Utility ################################

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

#################################### Output Utility END ############################

#################################### Common Utility ################################

PUBLIC_IP=''
MGMT_IP=''
REPL_IP=''
DATA_IP=''

MACHINES=''
ECS_VERSION=''
ECS_VERSION_NAME=''
ECS_VERSION_SHORT=''
ECS_VERSION_ID='00000'

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
declare -A VDCNAME_SSHABLEIP_MAP=()

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
    ECS_VERSION=$(sudo -i docker exec object-main rpm -qa | awk -F '-' '/storageos-fabric-datasvcs/ {print $4}' | strings)
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
        ["3.0.0.0.86889.0a0ee19"]="ECS-3.0-HF2-GA"
        ["3.1.0.0.95266.ab2753a"]="ECS-3.1-GA"
    )

    ECS_VERSION_NAME=${ecs_versions[${ECS_VERSION}]}
    ECS_VERSION="${ECS_VERSION} ${ecs_versions[${ECS_VERSION}]}"
    ECS_VERSION_SHORT=${ECS_VERSION:0:3}
    ECS_VERSION_ID=${ECS_VERSION:8:5}

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

    local f_MACHINES=${WORK_DIR_PARENT}/MACHINES.generated_by_script
    for vdc_name in ${VDCID_VDCNAME_MAP[@]}
        do
        awk '{print $4}' ${WORK_DIR}/common_info.vdc_info.${vdc_name} > ${f_MACHINES}.repl_ip.${vdc_name}
        if [[ ${vdc_name} == ${VDC_NAME} ]] ; then
            awk '{print $1}' ${WORK_DIR}/common_info.vdc_info.${vdc_name} > ${f_MACHINES}
        fi
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function get_machines_from_fabric
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    MACHINES=${WORK_DIR_PARENT}/MACHINES
    #get all the nodes on this VDC
    sudo -i getclusterinfo -a ${MACHINES} > /dev/null 2>&1
    # sudo -i getrackinfo -c ${MACHINES} > /dev/null 2>&1
    if [[ $? -ne 0 ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get MACHINES using getclusterinfo/getrackinfo"
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
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get secret, please specify correct mgmt user and password"
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

    #################################### get a node sshable_ip of all vdcs
    for vdc_name in ${!VDCNAME_REPLIP_MAP[@]}
        do
        VDCNAME_SSHABLEIP_MAP[${vdc_name}]=''
        for ip in $(echo "${VDCNAME_REPLIP_MAP[${vdc_name}]} ${VDCNAME_MGMTIP_MAP[${vdc_name}]} ${VDCNAME_DATAIP_MAP[${vdc_name}]}" | tr ',' ' ')
            do
            if [[ ! -z ${VDCNAME_SSHABLEIP_MAP[${vdc_name}]} ]] ; then
                break
            fi
            is_ip_sshable ${ip}
            if [[ $? -ne 0 ]] ; then
                print_error "line:${LINENO} ${FUNCNAME[0]} - ${ip} is not sshable, skip"
                continue
            fi
            VDCNAME_SSHABLEIP_MAP[${vdc_name}]=${ip}
        done
    done

    #################################### get all nodes ips of all vdcs
    for vdc_name in ${!VDCNAME_REPLIP_MAP[@]}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - get IPs for vdc ${vdc_name}"
        local f_vdc_ip_this=${WORK_DIR}/common_info.vdc_info.${vdc_name}
        echo -n "" > ${f_vdc_ip_this}
        for node in $(echo ${VDCNAME_REPLIP_MAP[${vdc_name}]} | tr ',' ' ')
            do
            #####
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - get IPs of vdc ${vdc_name} on node ${node}"
            is_ip_sshable ${node}
            if [[ $? -ne 0 ]] ; then
                print_error "line:${LINENO} ${FUNCNAME[0]} - ${node} is not sshable, skip"
                continue
            fi
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
        WORK_DIR=/home/admin/get_vdc_info/
        mkdir ${WORK_DIR} 2>/dev/null
    fi

    get_local_ips
    [[ $? -ne 0 ]] && exit_program

    get_ecs_version
    [[ $? -ne 0 ]] && exit_program
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Local ECS Object Version: ${ECS_VERSION}"

    [[ -z ${MACHINES} ]] && MACHINES=~/MACHINES
    if [[ ! -f ${MACHINES} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - machine file ${MACHINES} doesn't exist, please specify one using '-machines' option"
        exit_program
    fi

    cp ${MACHINES} ${WORK_DIR_PARENT}/MACHINES 2>/dev/null
    MACHINES=${WORK_DIR_PARENT}/MACHINES
    purify_machines_file

    get_vdc_info_from_dt
    [[ $? -ne 0 ]] && exit_program

    if [[ ${CHECK_TOPOLOGY} -eq 1 ]] ; then
        get_vdc_info_from_mgmt_api
        [[ $? -ne 0 ]] && exit_program

        get_machines_by_replip

        [[ ${PRINT_TOPOLOGY} -eq 1 ]] && print_topology
    fi

    ########################################################################
    echo
    print_info "line:${LINENO} ${FUNCNAME[0]} - ->Local VDC: ${ZONE_ID} ${VDC_NAME}"
    print_info "line:${LINENO} ${FUNCNAME[0]} - ->Local COS: ${COS} ${SP_NAME}"
    print_info "line:${LINENO} ${FUNCNAME[0]} - ->Local RGs:"
    for rg in ${REPLICATION_GROUPS}
        do
        print_info "line:${LINENO} ${FUNCNAME[0]} -              ${rg} ${RGID_RGNAME_MAP[${rg}]}"
    done

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function is_ip_sshable()
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local ip="$1"

    local ret_val=0
    if ! which nc >/dev/null 2>&1 ; then
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - nc binary does not exist"
    else
        nc -zv -w 2 ${ip} 22 > /dev/null 2>&1
        ret_val=$?
        if [[ ${ret_val} -eq 0 ]] ; then
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${ip} is sshable"
        else
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${ip} is NOT sshable"
        fi
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
    return ${ret_val}
}

function usage
{
    echo ""
    echo "Usage: $SCRIPTNAME"
    echo ""
    echo "Options:"
    echo "       -repo                          Check all items of repo GC"
    echo "         -repo_cleanupjob             Check repo GC cleanup jobs"
    echo "         -common_obcc                 Check OB CC Markers"
    echo "         -repo_mns                    Check repo GC min not sealed"
    echo "         -repo_verification           Check repo GC verification"
    echo "       -btree                         Check all items of btree GC"
    echo "         -common_obcc                 Check OB CC Markers"
    echo "         -btree_mns                   Check btree GC min not sealed"
    echo "         -btree_markers               Check btree GC markers"
    echo "       -topology                      Get and print VDCs and RGs configuration"
    echo "       -machines <file path>          Specify machines file path, default '~/MACHINES'"
    echo "       -mgmt_user <user name>         Mgmt user name to login ECS portal"
    echo "       -mgmt_password <password>      Password of the mgmt user to login ECS portal"
    echo "       -dt_query_max_retry <num>      Specify max retry for dt query, 3 times by default"
    echo "       -dt_query_retry_interval <sec> Specify pause time for dt query before next retry, 60 seconds by default"
    echo "       -dt_query_timeout <sec>        Specify timeout value for dt query, 1200 seconds by default"
    echo "       -help                          Help screen"
    echo ""
    exit 1
}

MGMT_USER='emcservice'
MGMT_PWD='ChangeMe'

CHECK_REPO_GC=0
CHECK_REPO_CLEANUP=0
CHECK_REPO_MNS=0
CHECK_REPO_VERIFICATION=0

CHECK_BTREE_GC=0
CHECK_BTREE_MNS=0
CHECK_BTREE_MARKER=0

CHECK_COMMON_OBCCMARKER=0

DT_QUERY_MAX_RETRY=3 ## how many times
DT_QUERY_RETRY_INTERVAL=60 ## in second
DT_QUERY_MAX_TIME=1200 ## in second
CHECK_RESTARTS=0
CHECK_CONFIG=0
CHECK_DTINIT=0
CHECK_CAPACITY=0
CHECK_TOPOLOGY=0
PRINT_TOPOLOGY=0
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
                CHECK_REPO_CLEANUP=1
                CHECK_COMMON_OBCCMARKER=1
                CHECK_REPO_MNS=1
                CHECK_REPO_VERIFICATION=1
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
                CHECK_COMMON_OBCCMARKER=1
                CHECK_BTREE_MNS=1
                CHECK_BTREE_MARKER=1
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
            "-dt_query_max_retry" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                DT_QUERY_MAX_RETRY=$2
                shift 2
                ;;
            "-dt_query_retry_interval" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                DT_QUERY_RETRY_INTERVAL=$2
                shift 2
                ;;
            "-dt_query_timeout" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                DT_QUERY_MAX_TIME=$2
                shift 2
                ;;
            "-topology" )
                CHECK_TOPOLOGY=1
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
        && ${PRINT_TOPOLOGY} -ne 1 && ${CHECK_COMMON_OBCCMARKER} -ne 1 ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - No required argument specified"
        usage
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function clean_up_work_dir
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ ! -z ${WORK_DIR} && -d ${WORK_DIR} ]] ; then
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up working diretory ${WORK_DIR}"
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
    local timeout=$3

    local ret_val=-10

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - query_str:[ ${query_str} ] f_output: [ ${f_output} ], timeout [ ${timeout} ]"

    if [[ ! -z ${timeout} ]] ; then
        if [[ ${DT_QUERY_MAX_TIME} -ne 0 && ${timeout} -gt ${DT_QUERY_MAX_TIME} ]] ; then
            DT_QUERY_MAX_TIME=${timeout} ## use the bigger one
        fi
    fi

    local curl_verbose=${WORK_DIR}/curl_verbose/$(date -d "$(date)" +%s).$RANDOM
    for retry in $(seq 1 ${DT_QUERY_MAX_RETRY})
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - doing query [ ${query_str} ]"

        echo "${query_str}" > ${curl_verbose}
        local query_result=''
        if [[ ! -z ${f_output} ]] ; then
            curl --max-time ${DT_QUERY_MAX_TIME} -v -f -L -s "${query_str}" > ${f_output} 2>>${curl_verbose}
        else
            query_result=$(curl --max-time ${DT_QUERY_MAX_TIME} -v -f -L -s "${query_str}" 2>>${curl_verbose})
        fi

        ret_val=$?

        if [[ ${ret_val} -ne 0 ]] || ! grep -q '200 OK' ${curl_verbose} 2>/dev/null ; then
            ## timed out, won't retry, other wise pause and retry
            if [[ ${ret_val} -eq 28 ]] ; then
                print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to dt_query [${query_str}], timed out in ${DT_QUERY_MAX_TIME} seconds, won't retry"
                print_error "line:${LINENO} ${FUNCNAME[0]} - verbose: $(cat ${curl_verbose})"
                # break
                exit_program
            else
                ## in some cases, returns 0 even with 500 error, so reset return code to an unusual value here
                [[ ${ret_val} -eq 0 ]] && ret_val=99

                ##
                if [[ ${retry} -eq ${DT_QUERY_MAX_RETRY} && ${ret_val} -ne 0 ]] ; then
                    print_error "line:${LINENO} ${FUNCNAME[0]} - Tried out ${retry} times and always failed, return code ${ret_val}, please check if dtquey service had been dead for long time or try in another node"
                    print_error "line:${LINENO} ${FUNCNAME[0]} - verbose: $(cat ${curl_verbose})"
                    # break
                    exit_program
                else
                    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Failed to dt_query [${query_str}] for ${retry} time, return code ${ret_val}, wait ${DT_QUERY_RETRY_INTERVAL} seconds and retry"
                    sleep ${DT_QUERY_RETRY_INTERVAL}
                fi
            fi
        else
            # rm -f ${curl_verbose}
            break ## successful
        fi
    done

    if [[ ! -z ${f_output} ]] ; then
        sed -i 's/\r//g' ${f_output} 2>/dev/null
    else
        echo "${query_result}" | sed -e 's/\r//g' 2>/dev/null
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
    return ${ret_val}
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
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get at least ${missing_dt} ${dt_type} level ${level} DTs, please check if DTs are initialized"
        exit_program
    fi

    echo "${dt_ids}"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function dump_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ ! -r ${WORK_DIR}/stats_aggregate ]] ; then
        curl --max-time 300 -s -f -k -L https://${MGMT_IP}:4443/stat/aggregate | sed -e 's/\r//g' > ${WORK_DIR}/stats_aggregate
        if [[ $? -ne 0 ]] || ! grep -q '^{' <<< "$(head -n1 ${WORK_DIR}/stats_aggregate)" 2>/dev/null ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get stats_aggregate, please check dtquery and stat serivices or run in another node"
            exit_program
            # exit 1
        fi
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function dump_stats_history
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ ! -r ${WORK_DIR}/stats_aggregate_history ]] ; then
        curl --max-time 300 -s -f -k -L https://${MGMT_IP}:4443/stat/aggregate_history | sed -e 's/\r//g' > ${WORK_DIR}/stats_aggregate_history
        if [[ $? -ne 0 ]] || ! grep -q '^{' <<< "$(head -n1 ${WORK_DIR}/stats_aggregate_history)" 2>/dev/null ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get stats_aggregate_history, please check dtquery and stat serivices or run in another node"
            exit_program
            # exit 1
        fi
    fi

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
        files=''
        files=$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name ${log_file}* -mtime -${within_days} -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null " 2>/dev/null)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"

        [[ -z ${files} ]] && continue

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - grepping log from node ${node} ..."
        # cm-chunk-reclaim.log.20170701-013511.gz:2017-06-30T20:06:23,163 [TaskScheduler-ChunkManager-DEFAULT_BACKGROUND_OPERATION-ScheduledExecutor-234]  INFO  RepoReclaimer.java (line 649) successfully recycled repo 3a0a0535-5d00-47d5-a293-96cfb93a0c59
        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep '${key_words}' ${files} 2>/dev/null \" 2>/dev/null" > ${out_put_file}${node} 2>/dev/null &
    done < ${MACHINES}
    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function search_logs_full_days_or_hrs
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local log_file=$1
    local within_days=$2
    local within_hours=$3
    local key_words="$4"
    local out_put_file=$5
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log_file:${log_file} within_days:${within_days} key_words:'${key_words}' out_put_file:${out_put_file}"

    local within_days_to_search=0
    local timestamp_begin=0
    if [[ ${within_hours} -eq -1 ]] ; then
        ## check full days
        within_days_to_search=$((${within_days}+1))
        # local date_end=$(date '+%Y-%m-%d')
        # local date_begin=$(date -d@$(($(date +%s)-${within_days}*86400)) '+%Y-%m-%d')
        local timestamp_start_of_today=$(date -d "$(date '+%Y-%m-%d 00:00:00')" '+%s')
        timestamp_begin=$(echo "scale=0; ${timestamp_start_of_today} - ${within_days}*86400" | bc)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - check full hours within_days_to_search:${within_days_to_search} timestamp_start_of_today:${timestamp_start_of_today} timestamp_begin:${timestamp_begin}"
    else
        ## check full hours
        within_days=$(echo "scale=0; ${within_days} + ${within_hours}/24" | bc)
        within_hours=$(echo "scale=0; ${within_hours}%24" | bc)
        within_days_to_search=${within_days}
        [[ ${within_hours} -gt 0 ]] && within_days_to_search=$((${within_days}+1))
        local timestamp_start_of_current_hour=$(date -d "$(date '+%Y-%m-%d %H:00:00')" '+%s')
        timestamp_begin=$(echo "scale=0; ${timestamp_start_of_current_hour} - ${within_days}*86400 - ${within_hours}*3600" | bc)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - check full hours within_days_to_search:${within_days_to_search} timestamp_start_of_current_hour:${timestamp_start_of_current_hour} timestamp_begin:${timestamp_begin}"
    fi

    local files=''
    while read node
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Collecting log from node ${node} ..."
        files=''
        files=$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name ${log_file}* -mtime -${within_days_to_search} -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null " 2>/dev/null)
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"

        [[ -z ${files} ]] && touch ${out_put_file}${node} && continue

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - grepping log from node ${node} ..."

        # cm-chunk-reclaim.log.20170701-013511.gz:2017-06-30T20:06:23,163 [TaskScheduler-ChunkManager-DEFAULT_BACKGROUND_OPERATION-ScheduledExecutor-234]  INFO  RepoReclaimer.java (line 649) successfully recycled repo 3a0a0535-5d00-47d5-a293-96cfb93a0c59
        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep -E '${key_words}' ${files} 2>/dev/null \" 2>/dev/null" 2>/dev/null | awk -F 'gz:|log:' -v v_timestamp_begin=${timestamp_begin} '{
            time_readable=substr($2, 0, 19)
            gsub(/-|:|T| /," ",time_readable)
            this_timestamp = mktime(time_readable)
            if (this_timestamp >= v_timestamp_begin) {
                print $2
            }
        }' > ${out_put_file}${node} 2>/dev/null &
    done < ${MACHINES}
    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

#################################### Common Lib END ################################
######################################################## Utility END ###########################################################

#################################### GC Common #####################################

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

############################### btree_gc checks ###############################

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
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_mns_dump_marker_simple}"
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
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_mns_parser_marker_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_parser_markers}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_mns_parser_tree_simple}"
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
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_marker_simple}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details of all DTs: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_markers}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_mns_gepreplayer_consistency_tree_simple}"
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

function repo_gc_check_cleanup_jobs
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # dt_ids=$(dt_query "http://${DATA_IP}:9101/diagnostic/${dt_type}/${level}/" | xmllint --format - | awk -F '<|>|?' '/<table_detail_link>/{print $3}')
    # dt_ids=$(dt_query "http://${DATA_IP}:9101/diagnostic/${dt_type}/${level}/" | xmllint --format - | awk -F '<|>|?' '/<id>/{print $3}')

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** Cleanup Jobs *********************************************************"

    local f_cleanup_jobs_raw=${WORK_DIR}/repo_gc.cleanup_jobs.raw
    local f_cleanup_jobs=${WORK_DIR}/repo_gc.cleanup_jobs

    local dt_ids=$(validate_dt "OB" 0 "url")

    echo "#### http://${DATA_IP}:9101/diagnostic/OB/0/DumpAllKeys/DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aaa&useStyle=raw" > ${f_cleanup_jobs_raw}

    print_msg "line:${LINENO} ${FUNCNAME[0]} - Highlight 1st Cleanup Job if it delay >= ${CLEANUP_JOB_DAY_DELAY_THRESHOLD} days:"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Highlight 1st and 2nd Cleanup Jobs if their time gap >= ${CLEANUP_JOB_TIME_GAP_THRESHOLD} seconds:"
    printf "%-51s | %-30s | %s\n" " " "1st Cleanup Job" "2nd Cleanup Job"
    printf "%-51s | %7s %-13s %8s | %7s %-13s %8s\n" "DT_ID" "JRmajor" "Timestamp" "DayDelay" "JRmajor" "Timestamp" "DayDelay"
    echo "---------------------------------------------------------------------------------------------------------------------"

    for ob_url in ${dt_ids}
        do
        local ob_id=$(echo ${ob_url} | awk -F '/' '{print $(NF-1)}')
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Querying Cleanup Jobs of ${ob_id}"

        # dt_query "${ob_url}DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aaa&useStyle=raw" ${f_cleanup_jobs_raw}.tmp
        # local cleanup_job_cnt=$(grep schemaType -c  ${f_cleanup_jobs_raw}.tmp)

        local query_str="${ob_url}DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aaa&maxkeys=2&showvalue=gpb&useStyle=raw"
        echo "## ${query_str}" >> ${f_cleanup_jobs_raw}
        dt_query "${query_str}" | tee -a ${f_cleanup_jobs_raw} | awk -v v_ob_id=${ob_id:65:999} -v v_cleaup_job_day_delay_threshold=${CLEANUP_JOB_DAY_DELAY_THRESHOLD} -v v_cleanupjob_time_gap_threshold=${CLEANUP_JOB_TIME_GAP_THRESHOLD} 'BEGIN{
            current_st=systime()
            cleanup_job_first["timestamp"] = "-"
            cleanup_job_first["day_delay"] = "-"
            cleanup_job_first["jr_major"] = "-"
            cleanup_job_second["timestamp"] = "-"
            cleanup_job_second["day_delay"] = "-"
            cleanup_job_second["jr_major"] = "-"
        }{
            if ($1=="schemaType") {
                timestamp=$4
                if (cleanup_job_first["timestamp"] == "-") {
                    cleanup_job_first["timestamp"] = timestamp
                } else {
                    cleanup_job_second["timestamp"] = timestamp
                }

                day_delay=(current_st-substr(timestamp,0,10))/(60*60*24)
                if (cleanup_job_first["day_delay"] == "-") {
                    cleanup_job_first["day_delay"] = day_delay
                }else {
                    cleanup_job_second["day_delay"] = day_delay
                }
            } else if ($1=="subKey:") {
                jr_major=strtonum("0x"substr($2,8,16))
                if (cleanup_job_first["jr_major"] == "-") {
                    cleanup_job_first["jr_major"] = jr_major
                }else {
                    cleanup_job_second["jr_major"] = jr_major
                }
            }
        } END{
            # cleanupjob_time_gap = cleanup_job_second["timestamp"]-cleanup_job_first["timestamp"]
            # if (cleanup_job_first["day_delay"] >= v_cleaup_job_day_delay_threshold) { 
                # if ( cleanupjob_time_gap > v_cleanupjob_time_gap_threshold) {
                    # printf("%-51s | %7x %-13s \033[1;31m%8.2f\033[0m | %7x %-13s \033[1;31m%8.2f\033[0m\n", v_ob_id,cleanup_job_first["jr_major"],cleanup_job_first["timestamp"],cleanup_job_first["day_delay"],cleanup_job_second["jr_major"],cleanup_job_second["timestamp"],cleanup_job_second["day_delay"])
                # } else {
                    # printf("%-51s | %7x %-13s \033[1;31m%8.2f\033[0m | %7x %-13s %8.2f\n", v_ob_id,cleanup_job_first["jr_major"],cleanup_job_first["timestamp"],cleanup_job_first["day_delay"],cleanup_job_second["jr_major"],cleanup_job_second["timestamp"],cleanup_job_second["day_delay"])
                # }
            # } else {
                # printf("%-51s | %7x %-13s %8.2f | %7x %-13s %8.2f\n", v_ob_id,cleanup_job_first["jr_major"],cleanup_job_first["timestamp"],cleanup_job_first["day_delay"],cleanup_job_second["jr_major"],cleanup_job_second["timestamp"],cleanup_job_second["day_delay"])
            # }
            
            cleanupjob_time_gap = cleanup_job_second["timestamp"]-cleanup_job_first["timestamp"]
            if (cleanup_job_first["day_delay"] >= v_cleaup_job_day_delay_threshold) {
                if ( cleanupjob_time_gap > v_cleanupjob_time_gap_threshold) {
                    day_delay_1 = sprintf("\033[1;31m%8.2f\033[0m", cleanup_job_first["day_delay"])
                    day_delay_2 = sprintf("\033[1;31m%8.2f\033[0m", cleanup_job_second["day_delay"])
                } else {
                    day_delay_1 = sprintf("\033[1;31m%8.2f\033[0m", cleanup_job_first["day_delay"])
                    day_delay_2 = sprintf("%8.2f", cleanup_job_second["day_delay"])
                }
            } else {
                day_delay_1 = sprintf("%8.2f", cleanup_job_first["day_delay"])
                day_delay_2 = sprintf("%8.2f", cleanup_job_second["day_delay"])
            }
            printf("%-51s | %7x %-13s %8s | %7x %-13s %8s\n", v_ob_id,cleanup_job_first["jr_major"],cleanup_job_first["timestamp"],day_delay_1,cleanup_job_second["jr_major"],cleanup_job_second["timestamp"],day_delay_2)
        }'
    done | tee ${f_cleanup_jobs}
    echo "--------------------------- END ------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_cleanup_jobs_raw}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_common_check_obccmarker
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_highlight "line:${LINENO} ${FUNCNAME[0]} - ****************************************** OB CC Marker *********************************************************"

    local f_ob_cc_markers_raw=${WORK_DIR}/gc_common.ob_cc_markers.raw
    local f_ob_cc_markers=${WORK_DIR}/gc_common.ob_cc_markers

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
        printf("%-51s ", "")
        for (zone_name in zone_name_id_map) {
            if (zone_name == "local_zone_id") {
                printf("| %-13s ", zone_name)
            } else {
                printf("| %-30s ", zone_name)
            }
        }
        print ""
        printf("%-51s ", "")
        for (zone_name in zone_name_id_map) {
            if (zone_name == "local_zone_id") {
                printf("| %s ", "     JR ")
            } else {
                printf("| %s ", "  MaxJR      JR JRGap  Raito% ")
            }
        }
        print ""
        print "-------------------------------------------------------------------------------------------------------------------"
    }'

    for ob_id in ${dt_ids}
        do

        local query_str="http://${DATA_IP}:9101/gc/obCcMarker/${ob_id}"
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"

        local ob_cc_marker=$(dt_query "${query_str}" | xmllint --format - 2>/dev/null | tee -a ${f_ob_cc_markers_raw})
        echo "${ob_cc_marker}" | grep -q 'HTTP ERROR'
        if [[ $? -eq 0 || -z ${ob_cc_marker} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get obCcMarker [ curl -L -s '${query_str}' ]"
            continue
        fi

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking ob_cc_marker for OB: ${ob_id}"
        echo "${ob_cc_marker}" | awk -v v_ob_id=${ob_id} -v v_ratio_threshold=${OB_CC_MARKER_RATIO_THRESHOLD} -v v_gap_threshold=${OB_CC_MARKER_GAP_THRESHOLD} -F '<|>' '{
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
            printf("%-51s ", substr(v_ob_id,66,51))
            for (zone_name in zone_name_id_map) {
                m_jr=zone_name_maxjr_map[zone_name]
                jr=zone_name_jr_map[zone_name]
                if (m_jr == "") {
                    printf("| %7s %7s %5s %7s  ", "-", "-", "-", "-")
                } else {
                    ratio=100*jr/m_jr
                    jr_gap=m_jr-jr
                    if (jr == "") {
                        full_str=sprintf("| %7x ", m_jr)
                        printf("%-13s ", full_str)
                    } else {
                        if (ratio < v_ratio_threshold || jr_gap >= v_gap_threshold){
                            full_str=sprintf("\033[1;31m| %7x %7x %5lu %7.2f \033[0m", m_jr, jr, jr_gap, ratio)
                            printf("%35s ", full_str)
                        } else {
                            full_str=sprintf("| %7x %7x %5lu %7.2f ", m_jr, jr, jr_gap, ratio)
                            printf("%24s ", full_str)
                        }
                    }
                }
            }
            print ""
        }'
    done | tee ${f_ob_cc_markers}
    echo "------------------- END -------------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_ob_cc_markers_raw}"
    echo
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_compare_cleanupjobs_obccmarker
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local f_ob_cc_markers=${WORK_DIR}/gc_common.ob_cc_markers
    local f_cleanup_jobs=${WORK_DIR}/repo_gc.cleanup_jobs
    sed -i -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" ${f_ob_cc_markers}
    sed -i -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" ${f_cleanup_jobs}

    local dt_ids=$(validate_dt "OB" 0)

    print_highlight "line:${LINENO} ${FUNCNAME[0]} - **************************** Is Cleanup Job blocked by OB CC Marker *********************************************"
    printf "%-51s | %7s | %15s | %15s\n" " " "OBCCMkr" "1st CleanupJob" "2nd CleanupJob"
    printf "%-51s | %7s | %7s %7s | %7s %7s\n" "OB_ID" "VDC_JR" "JR" "Blocked" "JR" "Blocked"
    echo "---------------------------------------------------------------------------------------------"
    # for ob_id in ${dt_ids}
        # do
        # local ob_id_short=${ob_id:65:999}
        # local jr_cleanup_job_1=$(awk -v v_ob_id=${ob_id_short} '{ gsub(/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]/, "", $0) ; if ($1 == v_ob_id) {print strtonum("0x"$3)} }' ${f_cleanup_jobs})
        # local jr_cleanup_job_2=$(awk -v v_ob_id=${ob_id_short} '{ gsub(/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]/, "", $0) ; if ($1 == v_ob_id) {print strtonum("0x"$7)} }' ${f_cleanup_jobs})
        # local jr_ob_cc_marker=$( awk -v v_ob_id=${ob_id_short} '{ gsub(/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]/, "", $0) ; if ($1 == v_ob_id) {print strtonum("0x"$4)} }' ${f_ob_cc_markers})
        # if [[ ${jr_cleanup_job_1} -gt ${jr_ob_cc_marker} ]] ; then
            # if [[ ${jr_cleanup_job_2} -gt ${jr_ob_cc_marker} ]] ; then
                # printf "%-51s %7x | %7x \e[1;31m%7s\e[0m | %7x \e[1;31m%7s\e[0m\n" "${ob_id_short}" "${jr_ob_cc_marker}" "${jr_cleanup_job_1}" "Yes" "${jr_cleanup_job_2}" "Yes"
            # else
                # printf "%-51s %7x | %7x \e[1;31m%7s\e[0m | %7x %7s\n" "${ob_id_short}" "${jr_ob_cc_marker}" "${jr_cleanup_job_1}" "Yes" "${jr_cleanup_job_2}" "No"
            # fi
        # else
            # printf "%-51s %7x | %7x %7s | %7x %7s\n" "${ob_id_short}" "${jr_ob_cc_marker}" "${jr_cleanup_job_1}" "No" "${jr_cleanup_job_2}" "No"
        # fi
    # done

    while read line
        do
        local dt_id=$(echo $line | awk '{print $1}')
        local clp_jr_1=$(echo $line | awk '{print $3}')
        local clp_jr_2=$(echo $line | awk '{print $7}')
        awk -v v_dt_id=${dt_id} -v v_clp_jr_1=${clp_jr_1} -v v_clp_jr_2=${clp_jr_2} '$1 == v_dt_id {
            unit_length = 5
            extra_length = 3
            num_remote = (NF-extra_length)/unit_length
            for (i=0; i<num_remote; i++) {
                obcc_jr = strtonum("0x"$(extra_length-1 + i*5 + 2))
                clp_jr_1 = strtonum("0x"v_clp_jr_1)
                clp_jr_2 = strtonum("0x"v_clp_jr_2)
                blocked_1 = "no"
                blocked_2 = "no"
                if (clp_jr_1 > obcc_jr) {
                    blocked_1 = sprintf("\033[1;31m%7s\033[0m", "yes")
                }
                if (clp_jr_2 > obcc_jr) {
                    blocked_2 = sprintf("\033[1;31m%7s\033[0m", "yes")
                }
                printf("%-51s | %7x | %7x %7s | %7x %7s # remote_vdc_%d\n", v_dt_id, obcc_jr, clp_jr_1, blocked_1, clp_jr_2, blocked_2, i+1)
            }
        }' ${f_ob_cc_markers}
    done < ${f_cleanup_jobs}
    echo "------------- END ---------------------------------------------------------------------------"

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
    local f_min_not_sealeds_chunk_sequence=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealeds.chunk_sequence

    local ct_dt_ids=$(validate_dt "CT" 1)
    local dt_cnt=$(echo "${ct_dt_ids}" | wc -l)

    local query_str="http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_SEQUENCE/?showvalue=gpb&useStyle=raw"
    dt_query "${query_str}" ${f_min_not_sealeds_chunk_sequence}
    local query_urls=$(grep schemaType ${f_min_not_sealeds_chunk_sequence} -B1 | grep '^http')
    if [[ -z ${query_urls} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ ${query_str} ]"
        return
    fi

    local query_urls_cnt=$(echo "${query_urls}" | wc -l)
    local missing_dt=$(echo "scale=0; ${dt_cnt}-${query_urls_cnt}" | bc)
    if [[ ${missing_dt} -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ${missing_dt} DTs have no CHUNK_SEQUENCE"
    fi

    echo -n '' > ${f_min_not_sealeds_chunk_sequence}
    for query_url in ${query_urls}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Querying [ '${query_url}' ]"

        dt_query "${query_url}" | awk -v v_ct_id=$(echo ${query_url} | awk -F '/' '{print $4}') '{
            if($1=="schemaType"){
                key=$0
            }else if ($1=="value:") {
                value=$0
                print v_ct_id,key,value
                key="-"
                value="-"
            }
        }' | sed 's/rgId  dataType/rgId None dataType/g' >> ${f_min_not_sealeds_chunk_sequence}
    done
    awk '/schemaType/{print $5,$7}' ${f_min_not_sealeds_chunk_sequence} | sort | uniq -c

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_min_not_sealeds_chunk_sequence}"
    echo
    echo

    ###### step 2, GC_REF_COLLECTION
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 2, Checking ${check_type} GC_REF_COLLECTION for each CT-DT pair ..."

    local f_min_not_sealeds_gc_ref=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealeds.gc_ref

    local dt_ids=$(validate_dt "PR" 1)
    local dt_cnt=$(echo "${dt_ids}" | wc -l)

    query_str="http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/GC_REF_COLLECTION/?type=${check_type}&showvalue=gpb&useStyle=raw"
    query_urls=$(dt_query "${query_str}" | grep schemaType -B1 | grep '^http')
    if [[ -z ${query_urls} ]] ; then
        print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get [ ${query_str} ]"
        return
    fi

    query_urls_cnt=$(echo "${query_urls}" | wc -l)
    missing_dt=$(echo "scale=0; ${dt_cnt}-${query_urls_cnt}" | bc)
    if [[ ${missing_dt} -ne 0 ]] ; then
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ${missing_dt} DTs have no GC_REF_COLLECTION"
    fi

    for query_url in ${query_urls}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Querying [ '${query_url}' ]"

        local ct_owner=$(echo ${query_url} | awk -F ':|/' '{print $4}')
        local ct_id=$(echo ${query_url} | awk -F '/' '{print $4}')
        echo "# ${query_url}" >> ${f_min_not_sealeds_gc_ref}
        # dt_query "${query_url}" >> ${f_min_not_sealeds_gc_ref}
        dt_query "${query_url}" | while read line
            do
            echo "${line}" >> ${f_min_not_sealeds_gc_ref}
            # if [[ ${line:0:7} == "chunkId" ]] ; then
                # echo "minNotSealedValue: N/A" >> ${f_min_not_sealeds_gc_ref}
                # # local mns_value=$(get_chunk_info "$(echo ${line} | awk -F '"' '{print $2}')" | awk '$1 == "minNotSealedSequenceNumber:" {print $2}')
                # # echo "minNotSealedValue: ${mns_value}" >> ${f_min_not_sealeds_gc_ref}
            # else
                # echo "${line}" >> ${f_min_not_sealeds_gc_ref}
            # fi
        done
    done
    awk '/^schemaType/{print $4,$10}' ${f_min_not_sealeds_gc_ref} | sort | uniq -c

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_min_not_sealeds_gc_ref}"
    echo
    echo

    ###### step 3, Combine
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ##### Step 3, Checking results ..."

    local f_min_not_sealeds=${WORK_DIR}/${check_type_lowercase}_gc_check.min_not_sealeds

    print_msg "line:${LINENO} ${FUNCNAME[0]} - Highlight min-not-sealed ratio>=${MNS_RATIO_THRESHOLD}, # Ratio=(Sequence-MNSminor)/MNSminor"
    printf "%-51s %-78s %19s %9s %6s\n" "DTID" "Replication Group" "MNS(major/minor)" "Sequence" "Ratio" | tee ${f_min_not_sealeds}
    echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------------" | tee -a ${f_min_not_sealeds}

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
            }' ${f_min_not_sealeds_chunk_sequence})
            [[ -z ${sequence} ]] && sequence="-"
            printf "%9s\n" ${sequence}
        done
    done | awk -v v_mns_ratio_threshold=${MNS_RATIO_THRESHOLD} '{
        ratio=($5-$4)/($4+1)
        if (ratio >= v_mns_ratio_threshold) {
            printf("\033[1;31m%s %6.2f\033[0m\n", substr($0,29,999), ratio)
        } else {
            printf("%s %6.2f\n", substr($0,29,999), ratio)
        }
    }' | tee -a ${f_min_not_sealeds}
    echo "--------------------------- END ---------------------------------------------------------------------------------------------------------------------------------------"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_min_not_sealeds}"
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
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_min_not_sealed_simple}"
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

    dt_query "http://${DATA_IP}:9101/triggerGcVerification/queryCacheStatus" ${f_verifications}
    grep -q 'HTTP ERROR' ${f_verifications}
    if [[ $? -eq 0 ]]; then
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Failed to get [curl -L -s http://${DATA_IP}:9101/triggerGcVerification/queryCacheStatus ], will retry after 10 seconds"
        # repo_gc_check_verification_old_fashion
        return
    fi

    print_msg "line:${LINENO} ${FUNCNAME[0]} - Highlight with RED on timestamp<=refreshListTime and delay>=${VERIFICATION_DAY_DELAY_THRESHOLD} days:"
    awk -v v_day_delay=${VERIFICATION_DAY_DELAY_THRESHOLD} 'BEGIN{
        host_node="-"
        refresh_list_time="-"
        cos_local="-"
        dt_level="-"
        replication_group="-"
        gc_type="-"
        ob_id="-"
        ob_ts="-"
        node_loop_done=0
        printf("%-15s %-115s %-13s %-13s %8s\n","HOST","OB_ID","refreshTime","TimeStamp","DayDelay")
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
            day_delay=(systime()-substr(ob_ts,0,10))/(60*60*24)
            if (day_delay >= v_day_delay || ob_ts<refresh_list_time) {
                printf("\033[1;31m%-15s %-115s %-13s %-13s %8.2f\033[0m\n",host_node,ob_id,refresh_list_time,ob_ts,day_delay)
            } else {
                printf("%-15s %-115s %-13s %-13s %8.2f\n",host_node,ob_id,refresh_list_time,ob_ts,day_delay)
            }
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
    }' ${f_verifications}

    ## list OB that are not listed in ${f_verifications}
    print_msg "line:${LINENO} ${FUNCNAME[0]} - OBs that are not in verification:"
    local dt_ids=$(validate_dt "OB" 0)
    local dt_cnt=$(echo "${dt_ids}" | wc -l)
    local ob_verification_cnt=$(grep -c 'urn:storageos:OwnershipInfo:' ${f_verifications})
    local missing_ob_cnt=$(echo "scale=0; ${dt_cnt}-${ob_verification_cnt}" | bc)
    if [[ ${missing_ob_cnt} -ne 0 ]] ; then
        echo "    ${missing_ob_cnt}" | tee -a ${f_verifications}
        echo
        for ob_id in $(echo "${dt_ids}")
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking CHUNK_REFERENCE_SCAN_PROGRESS for OB: ${ob_url}"
            grep -q "${ob_id}" ${f_verifications}
            if [[ $? -ne 0 ]] ; then
                echo "    ${ob_id}" | tee -a ${f_verifications}
            fi
        done
    else
        echo "    NOPE"
    fi

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_verifications}"
    echo
    echo

    # repo_gc_check_verification_task
    repo_gc_check_verification_speed

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_verification_task
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local f_repo_gc_verification_tasks=${WORK_DIR}/repo_gc.verification_tasks
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> On-going verification tasks"
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${ZONE_ID}&type=REPO&time=0&useStyle=raw" ${f_repo_gc_verification_tasks}

    local verification_task_cnt=$(grep -c schemaType ${f_repo_gc_verification_tasks})
    print_info "line:${LINENO} ${FUNCNAME[0]} -     ${verification_task_cnt}"
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function repo_gc_check_verification_speed
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> Verification Speed"

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

    local f_verification_speed=${WORK_DIR}/repo_gc.verification_speed
    if [[ $(echo "${ECS_VERSION_SHORT} < 3.1" | bc) -ne 0  ]] ; then
        # 2017-09-10T06:12:10,944 [TaskScheduler-BlobService-REPO_SCAN-ScheduledExecutor-003]  INFO  RepoChunkReferenceScanner.java (line 217) This round GC verification of scanner:REPO:urn:storageos:OwnershipInfo:5323a427-7032-4c9e-9006-e1edd7391b71_38e4959d-7aad-4def-b7e2-3db8b15fd44b_OB_12_128_0: last: 116163986 milliseconds for objectScanCount 6799847
        search_logs_full_days_or_hrs "blobsvc-chunk-reclaim.log" 2 0 "This round GC verification" ${f_verification_speed}-
        awk '{printf("%-115s %5.1f %12lu\n",substr($12,14,999),$14/(1000*60*60),$18) }' ${f_verification_speed}-* > ${f_verification_speed}
    else
        # 2017-09-01T01:07:26,391 [TaskScheduler-BlobService-REPO_SCAN-ScheduledExecutor-007]  INFO  RepoChunkReferenceScanner.java (line 223) REPO_GC_VERIFICATION_TASK_END: This round Repo_GC verification of scanner:REPO:urn:storageos:OwnershipInfo:fda85274-7f81-4dde-8f14-6cb692afdf72_30f44190-d0ba-4ac1-b69d-6ef782d9881c_OB_70_128_0: last for : 373647 milliseconds objectScanCount: 28060 start time for index stores: createTime: 1504227672744 startTime: 1504227827065 finishTime: 1504228046391 candidateCount: 0, failedCandidateCount: 0, lastTaskTime: 1504219685100
        search_logs_full_days_or_hrs "blobsvc-chunk-reclaim.log" 2 0 "This round Repo_GC verification" ${f_verification_speed}-
        awk '{printf("%-115s %5.1f %12lu\n",substr($13,14,999),$17/(1000*60*60),$20) }' ${f_verification_speed}-* > ${f_verification_speed}
    fi
    rm -f ${f_verification_speed}-* 2>/dev/null

    if [[ ! -f ${f_verification_speed} || ! -s ${f_verification_speed} ]] ; then
        print_info "line:${LINENO} ${FUNCNAME[0]} -   There's no verification done a round within given days in all nodes"
        return
    fi

    ############################## get OwnershipInfo for effactive OB distritution
    local f_dt_ownershipinfo=${WORK_DIR}/gc_common.dt_ownershipinfo
    dt_query "http://${DATA_IP}:9101/diagnostic/DumpOwnershipInfo" ${f_dt_ownershipinfo}

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
        # urn:storageos:ReplicationGroupInfo:38e4959d-7aad-4def-b7e2-3db8b15fd44b:global
        # urn:storageos:OwnershipInfo:5323a427-7032-4c9e-9006-e1edd7391b71_38e4959d-7aad-4def-b7e2-3db8b15fd44b_OB_118_128_0:
        awk -v v_rg_id=${rg_id} -v v_verification_thread_cnt=${verification_thread_cnt} -v v_ob_cnt_max=${ob_cnt_max} 'BEGIN{
            max_hr=-1
            max_ob="-"
            hr_cnt=0
            obj_cnt=0
            ob_cnt=0
        } {
            if (substr($1,66,36) == substr(v_rg_id, 36, 36)){
                if ($2 > max_hr) {
                    max_hr=$2
                    max_ob=$1
                    max_obj_cnt=$3
                }
                obj_cnt+=$3
                hr_cnt+=$2
                ob_cnt++
            }
        } END{
            if (ob_cnt > 0 && hr_cnt > 0 && v_verification_thread_cnt > 0) {
                avg_time=hr_cnt/ob_cnt

                printf("    - Average: %.2f hours, scanned %lu objects, %.2f objects/second\n", avg_time, obj_cnt/ob_cnt, obj_cnt/(hr_cnt*60*60))
                printf("    - Slowest: %.2f hours, scanned %lu objects, on OB %s\n", max_hr, max_obj_cnt, max_ob)
                round_cnt=sprintf("%.0f\n", v_ob_cnt_max/v_verification_thread_cnt+0.49)

                printf("    - This VDC need %.2f to %.2f hours to finish one full round of GC verification for all OB DTs of this RG.\n", round_cnt*avg_time, round_cnt*max_hr)
            } else {
                print "    - There seems no OB DT verified or there are not many objects in OBs of this RG"
            }
        }' ${f_verification_speed}
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
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Details: ${PUBLIC_IP}:${f_verification_simple}"
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

    [[ ${CHECK_BTREE_MNS} -eq 1 ]] && btree_gc_check_mns
    [[ ${CHECK_BTREE_MARKER} -eq 1 ]] && btree_gc_check_btree_markers

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"
    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Checking REPO GC ..."

    [[ ${CHECK_REPO_CLEANUP} -eq 1 ]] && repo_gc_check_cleanup_jobs
    [[ ${CHECK_REPO_MNS} -eq 1 ]] && repo_gc_check_mns
    [[ ${CHECK_REPO_VERIFICATION} -eq 1 ]] && repo_gc_check_verification

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

########################## Main logic ##############################

function main
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${SCRIPTNAME} version ${VERSION}"

    ## Initialize globals
    get_vdc_info

    [[ ${CHECK_REPO_GC} -eq 1 ]] && repo_gc_check

    [[ ${CHECK_BTREE_GC} -eq 1 ]] && btree_gc_check

    [[ ${CHECK_COMMON_OBCCMARKER} -eq 1 ]] && gc_common_check_obccmarker
    [[ ${CHECK_REPO_CLEANUP} -eq 1 && ${CHECK_COMMON_OBCCMARKER} -eq 1 ]] && repo_gc_compare_cleanupjobs_obccmarker

    # clean_up_work_dir

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

[[ $(whoami) != "admin" ]] && print_error "Please run as admin outside container" && exit 1

trap clean_up SIGINT
trap exit_program SIGPIPE

parse_args $*

CLEANUP_JOB_CNT_THRESHOLD=1500
CLEANUP_JOB_TIME_GAP_THRESHOLD=86400 # seconds of one day
CLEANUP_JOB_DAY_DELAY_THRESHOLD=1
OB_CC_MARKER_RATIO_THRESHOLD=85 #%
OB_CC_MARKER_GAP_THRESHOLD=20
MNS_RATIO_THRESHOLD=0.25
MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD=7
MNS_PARSER_MARKER_DAY_DELAY_THRESHOLD=${MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD}
MNS_CC_MARKER_DAY_DELAY_THRESHOLD=${MNS_DUMP_MARKER_DAY_DELAY_THRESHOLD}
VERIFICATION_DAY_DELAY_THRESHOLD=7

# sudo rm -rf /var/tmp/gc_diagnosis

WORK_DIR_PARENT=/home/admin/gc_diagnosis  ## script will never delete this diretory
WORK_DIR_SUB=$(date '+%Y%m%dT%H%M%S')
WORK_DIR=${WORK_DIR_PARENT}/${WORK_DIR_SUB}  ## script clean up this diretory when script finish or run into error or interrupted

LOCK_FILE=${WORK_DIR_PARENT}/running ## allow only one instance
[[ -f ${LOCK_FILE} ]] && echo "Already running" && exit 17

# rm -rf ${WORK_DIR_PARENT}/201*T* 2>/dev/null  ## clean up old diretory

mkdir -p ${WORK_DIR}/curl_verbose 2>/dev/null
[[ $? -ne 0 ]] && echo "Failed to manipulate directory ${WORK_DIR}" && exit 2
# touch ${LOCK_FILE}

main

########################## Main logic END ##############################