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
# 0.7.0 - Enhanced with checking reclaimed garbage since VDC was in 3.0 code base.
# 0.9.0 - Change name to gc_check.sh.
#         Running multi checking in parralel.
#         Change usage.
#         Fix bug
# 0.9.2 - Fix bug
# 0.9.3 - Release Date : 2017-07-18
#         Check if/when GC is enabled, related option is in help screen.
#         Check services restarts to help analysis, related option is in help screen.
#         Check VDCs and RGs configuration/topology to help to estimate GC load/pressure,
#             especially help to analyze GC slowness, related option is in help screen.
#         Check DT init status, related option is in help screen.
#         Simple capacity reports based on stats, same with GUI->Monitor->ChunkSummary, related option is in help screen.
#         Capacity info from SSM and OS level, these data is restricted to ECS CS and ECS Engineering.
#         Check cleanup job and reports separately based on threshold.
#         Check obccmarker and reports separately based on threshold.
#         Check verification details and reports separately based on threshold.
#         Introduce DT query wrapper to tolerate dtquery service restarts during running dt query.
#         Many other details improvement to make output more friendly.
# 0.9.4 - Release Date : 2017-07-25
#         Changed get machine logic to avoid 'getclusterinfo' hang in dev lab,
#             if '-machines' option is not specified ~/MACHINES will be used instead of
#             generating using getclusterinfo, so please make sure ~/MACHINES is correct,
#             otherwise 'Reclaim History' section will report less chunk and size.
# 0.9.5 - Release Date : 2017-07-27
#         Check GC switches of remote VDCs,
#             this will fail if repl and mgmt IPs of VDC are not sshable.
#             repl and mgmt IPs of remote VDCs are the only IPs that can be gotten from local VDC.
# 0.9.6 - Release Date : 2017-08-09
#         Check WSCritical log of GC and GEO,
#             introduce gc_blocking_issue_repository file to record gc blocking issues, lay on same directory of script,
#             each line is used to describe one issue, which contains multiple fields, please see that file for detail.
#         Introduced '-ecs_engineering' option for ecs engineering to present more information.
# 0.9.7 - Release Date : 2017-08-15
#         Check Partial garbage.
#         Improve logic of search log in check know issue function to not depend on error logs recorded in repository file.
# 0.9.8 - Release Date : 2017-08-21
#         Handle cases that work directory cannot be cleaned up, capture pipe signal, and allow single instance running
#             in a node.
#         Handle cases that dt query cannot return for long time when DT is large,
#             1. set default timeout to 20 minutes for each dt query except 'btreeUsage', adjustable using related options.
#             also set timeout to 300 seconds for stats dump.
#             2. don't get cleanup jobs or verification tasks from DT when it is already a large value in stats.
#         Refined stats show.
# 0.9.9 - Release Date : 2017-08-22
#         Refined cleanupjobs and verification related functions.
# 1.0.0 - Release Date : 2017-08-29
#         Introduced daily injection checking, using '-injection <# of days>' option,
#             currently can only correctly count S3 PUT request as per ECS 3.0 S3 API, CAS/Swift/Atmos requests cannot be 
#             fully/correctly counted, if end users uses mixed APIs to write into a VDC, e.g. use (both S3 and Swift) or 
#             (both S3 and Atmos), there will be bias in result.
VERSION=1.0.1
# 1.0.1 - Release Date : 2017-09-01
#         Removed test option '-repo_partial'.
#         Introduced more new stats of 3.1 into capacity check.
#         Fixed a bug in injection checking which miss the data of 00:00:00 in start boundary day.
##########################################################################

# Author:  Alex Wang (alex.wang2@emc.com)

SCRIPTNAME="$(basename $0)"
# SCRIPTDIR="$(dirname "$(realpath -e "$0")")"
SCRIPTDIR="$(dirname "$(readlink -f "$0")")"
echo "${SCRIPTNAME} version ${VERSION}"
# LC_ALL=C

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
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Local ECS Version: ${ECS_VERSION}"

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
    echo "       -repo                          Check repo GC"
    echo "       -btree                         Check btree GC"
    echo "       -force                         Force check cleanup jobs and verification tasks from DT even they are very large size, please use with '-dt_query_timeout' option to set a proper timeout"
    echo "       -restarts                      Check services restart"
    echo "       -configuration                 Check GC configuration"
    echo "       -dt                            Check DT init status"
    echo "       -injection <# of days>         Check how many data wrote into VDC in given days, there will be bias in result if CAS/Swift/Atmos API used"
    echo "       -capacity                      Check capacity from stats, along with '-ecs_engineering' option"
    echo "       -ecs_engineering               Check and print more items and few diagnosis info, for only EE and Dev, some other options relies on this one"
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
CHECK_REPO_GC_FORCE_CHECK_CLEANUP_JOBS_FROM_DT=0
CHECK_REPO_GC_FORCE_CHECK_VERIFICATION_TASKS_FROM_DT=0
CHECK_BTREE_GC=0
DT_QUERY_MAX_RETRY=3 ## how many times
DT_QUERY_RETRY_INTERVAL=60 ## in second
DT_QUERY_MAX_TIME=1200 ## in second
CHECK_BLOCKING_ISSUE=0
CHECK_OBCCMARKER=0
CHECK_TASKS=0
CHECK_RRREBUILD=0
CHECK_RESTARTS=0
CHECK_CONFIG=0
CHECK_DTINIT=0
CHECK_INJECTION_DAYS=0
CHECK_CAPACITY=0
CHECK_CAPACITY_MORE=0
CHECK_TOPOLOGY=0
PRINT_TOPOLOGY=0
IS_ECS_ENGINEERING_OPERATING=0

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
                shift 1
                ;;
            "-btree" )
                CHECK_BTREE_GC=1
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
            "-force" )
                CHECK_REPO_GC_FORCE_CHECK_CLEANUP_JOBS_FROM_DT=1
                CHECK_REPO_GC_FORCE_CHECK_VERIFICATION_TASKS_FROM_DT=1
                shift 1
                ;;
            "-restarts" )
                CHECK_RESTARTS=1
                shift 1
                ;;
            "-configuration" )
                CHECK_TOPOLOGY=1
                CHECK_CONFIG=1
                shift 1
                ;;
            "-dt" )
                CHECK_DTINIT=1
                shift 1
                ;;
            "-injection" )
                [[ -z $2 ]] && print_error "line:${LINENO} ${FUNCNAME[0]} - Requires a value after this option." && usage
                CHECK_INJECTION_DAYS=$2
                shift 2
                ;;
            "-capacity" )
                CHECK_CAPACITY=1
                shift 1
                ;;
            "-capacity_more" )
                CHECK_CAPACITY_MORE=1
                shift 1
                ;;
            "-ecs_engineering" )
                IS_ECS_ENGINEERING_OPERATING=1
                shift 1
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
        &&  ${CHECK_RESTARTS} -ne 1 &&  ${CHECK_CONFIG} -ne 1 \
        &&  ${CHECK_CAPACITY} -ne 1 &&  ${PRINT_TOPOLOGY} -ne 1 \
        && ${CHECK_DTINIT} -ne 1 && ${CHECK_INJECTION_DAYS} -eq 0 ]] ; then
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
    rm -f ${LOCK_FILE} 2>/dev/null

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function clean_up_process
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    ## clean up remote host process
    # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - clean up remote host process of '${SCRIPTNAME}' ..."
    # local local_ips=$(ip addr)
    # while read node
        # do
        # if grep -q "inet ${node}" <<< "${local_ips}" 2>/dev/null ; then
            # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - skip local host"
            # continue
        # fi

        # local pgids=$(ssh -n ${node} "ps -e -o pgid,cmd | grep 'zgrep .* /var/log/cm-chunk-reclaim.log' | grep -v '[0-9] grep' | grep -v '[0-9] bash'" | awk  '{print $1}' | sort | uniq)
        # [[ -z ${pgids} ]] && continue

        # for pgid in ${pgids}
            # do
            # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - on ${node} cleaning up sub process group ${pgid} of '${SCRIPTNAME}'"
            # ssh -n ${node} "sudo kill -9 -${pgid}"
        # done
    # done < ${MACHINES}

    ## clean up local host process
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - clean up local host process of '${SCRIPTNAME}' ..."
    local pgids=$(ps -e -o pgid,cmd | grep "zgrep .* /var/log/cm-chunk-reclaim.log" | grep -v '[0-9] grep' | awk '{print $1}' | sort | uniq)
    local main_pgids=$(ps -e -o pgid,cmd | grep "${SCRIPTNAME}" | grep -v '[0-9] grep' | awk '{print $1}' | sort | uniq)
    local sub_pgids=$(grep -v "${main_pgids}" <<< "${pgids}")
    for pgid in ${sub_pgids}
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up sub process group ${pgid} of '${SCRIPTNAME}' ..."
        sudo kill -9 -${pgid}
    done

    # clean_up_work_dir

    if [[ ! -z ${SCRIPTNAME} ]] ;then
        for pgid in ${main_pgids}
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleaning up main process group ${pgid} of '${SCRIPTNAME}' ..."
            sudo kill -9 -${pgid}
        done
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function clean_up
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    cp ${WORK_DIR}/log ${WORK_DIR_PARENT}/log.${WORK_DIR_SUB}.interrupted
    clean_up_work_dir
    clean_up_process

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function exit_program
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    cp ${WORK_DIR}/log ${WORK_DIR_PARENT}/log.${WORK_DIR_SUB}.exit
    clean_up_work_dir
    clean_up_process

    exit 3

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

#################################### Common Utility END ############################

#################################### Common Lib ####################################

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
        curl --max-time 300 -s -f -k -L https://${MGMT_IP}:4443/stat/aggregate > ${WORK_DIR}/stats_aggregate
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
        curl --max-time 300 -s -f -k -L https://${MGMT_IP}:4443/stat/aggregate_history > ${WORK_DIR}/stats_aggregate_history
        if [[ $? -ne 0 ]] || ! grep -q '^{' <<< "$(head -n1 ${WORK_DIR}/stats_aggregate_history)" 2>/dev/null ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get stats_aggregate_history, please check dtquery and stat serivices or run in another node"
            exit_program
            # exit 1
        fi
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
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
        if (key_found!="yes") {
            key_counter=""
        }
        print key_counter
    }' ${WORK_DIR}/stats_aggregate)

    if [[ -z ${counter} || "${counter}" == "-" ]] ; then
        LOG_ERROR "line:${LINENO} ${FUNCNAME[0]} - Didn't find ${key} counter [${counter}] from stats"
        counter=0
    fi

    if ! grep -q '^[[:digit:]]*$' <<< "${counter}" 2>/dev/null ; then
        LOG_ERROR "line:${LINENO} ${FUNCNAME[0]} - Failed to get counter of [${key}] from stats because the counter [${counter}] is not a valid digit, thus set it to 0"
        counter=0
    fi

    echo ${counter}
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

function capacity_usage_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    ##  https://asdwiki.isus.emc.com:8443/display/ECS/Dashboard+Stats+to+API+to+UI+Mapping

    ## metadata
    local data_jr_1=$(query_counter "data_level_1_journal.TOTAL")
    local data_jr_0=$(query_counter "data_level_0_journal.TOTAL")
    local data_btree_1=$(query_counter "data_level_1_btree.TOTAL")
    local data_btree_0=$(query_counter "data_level_0_btree.TOTAL")
    ## user data
    local data_repo=$(query_counter "data_repo.TOTAL")
    ## geo data
    local data_copy=$(query_counter "data_copy.TOTAL")
    local data_parity=$(query_counter "data_xor.TOTAL") # parity chunk
    local data_cached=0  # geo cache
    if [[ $(echo "${ECS_VERSION_SHORT} < 3.1" | bc) -ne 0 ]] ; then
        local chunk_cached=$(query_counter "Number of Chunks.TOTAL")
        data_cached=$(echo "scale=0; ${chunk_cached}*134217600" | bc)
    else
        data_cached=$(query_counter "Capacity of Cache.TOTAL")
    fi
    # "Capacity of Cache.TOTAL" ("Total cache size for chunks in the cache") <-- 3.1
    # "Number of Chunks.TOTAL" ("Number of chunks in the cache")  <-- 3.0 HF2
    # "Chunks Retrieved Locally.TOTAL" ("Number of remote chunks served from the cache.")
    # "Bootstrap Bytes Pending.TOTAL" ("Amount of data yet to be replicated to this secondary zone.")

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
        p_data_cached=100*data_cached/cnt
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
        printf("%21s | %-16s %7.2f(%5.2f%) | %-16s %7.2f(%5.2f%) |\n", " ", "level-1 Btree:",   btree_1/1099511627776,p_btree_1, "Geo Cache:", data_cached/1099511627776,p_data_cached)
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

function check_injection
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    # 2017-08-24T02:10:16,447 [292]  INFO  RequestLog.java (line 83) 10.129.6.65 GET //10.249.228.28:9020/ecsbkt/b7841af2-1474-4831-8c69-fd9722fec10e HTTP/1.1 200 89 - 37902
    # 2017-08-24T02:09:58,738 [292]  INFO  RequestLog.java (line 83) 10.129.6.65 PUT //10.249.228.28:9020/ecsbkt/d4b5254c-527c-45f9-8873-933c3756ec14 HTTP/1.1 200 89 84280 -
    # 2017-08-30T00:05:33,764 [292]  INFO  RequestLog.java (line 83) 10.129.6.65 POST //10.249.228.28:9020/ecsbkt/44d63e2d-e568-48c5-8ef8-9e971e0bb55f?uploads HTTP/1.1 200 89 - 319  #init MPU
    # 2017-08-30T00:05:56,063 [292]  INFO  RequestLog.java (line 83) 10.129.6.65 POST //10.249.228.28:9020/ecsbkt/44d63e2d-e568-48c5-8ef8-9e971e0bb55f?uploadId=3aadd HTTP/1.1 200 89 223 440 #complete MPU
    # 2017-08-24T02:10:19,717 [292]  INFO  RequestLog.java (line 83) 10.129.6.65 DELETE //10.249.228.28:9020/ecsbkt/9b58eb50-815c-42cb-8100-d514b7b4ca65 HTTP/1.1 204 89 - -
    # search_logs_full_days_or_hrs "dataheadsvc.log" ${CHECK_INJECTION_DAYS} -1 "RequestLog.java .* PUT|RequestLog.java .* POST" ${WORK_DIR}/RequestLog-
    search_logs_full_days_or_hrs "dataheadsvc.log" ${CHECK_INJECTION_DAYS} -1 "RequestLog.java .* PUT " ${WORK_DIR}/RequestLog-

    awk -v v_check_days=${CHECK_INJECTION_DAYS} 'BEGIN{
        current_time = strftime("%Y-%m-%dT%T", systime())
    }{
        # if (substr($11, 0, 1) == "2") {
            # if ($8 == "PUT") {
                # date_injection_map[substr($1, 0, 10)] += $13
            # } else if ($8 == "POST") {
                # date_injection_map[substr($1, 0, 10)] += $14
            # }
        # }
        # if ( ($8 == "PUT" || $8 == "POST") && substr($11, 0, 1) == "2" && $13 != "-") {
        if ($8 == "PUT" && substr($11, 0, 1) == "2" && $13 != "-") {
            date_injection_map[substr($1, 0, 10)] += $13
        }
    }END{
        print ""
        printf("\033[1;34m%s %s\033[0m\n", "====> Injection # Checked by UTC",current_time)
        if(length(date_injection_map) == 0) {
            printf("  - No injection in %d days\n" , v_check_days)
        } else {
            asorti(date_injection_map, date_injection_map_key_sorted)
            for (idx in date_injection_map_key_sorted) {
                date_key = date_injection_map_key_sorted[idx]
                printf("  - In %s injected %10.2f GB %7.2f TB\n" , date_key, date_injection_map[date_key]/1073741824, date_injection_map[date_key]/1099511627776)
            }
        }
    }' ${WORK_DIR}/RequestLog-*

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

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

function gc_common_check_services_restarts
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> Local VDC Services Restarts"

    local files=''
    local log_searched=${WORK_DIR}/gc_common.service_restarts_log
    while read node
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Collecting log from node ${node} ..."

        files="$(ssh -n ${node} "sudo docker exec object-main sh -c \"find /var/log -name localmessages* -mtime -7 -exec echo -n \\\"{} \\\" \\\; \" 2>/dev/null " 2>/dev/null)" 2>/dev/null
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - log files: [ ${node} ] [ ${files} ]"

        [[ -z ${files} ]] && continue

        ssh -n ${node} "sudo docker exec object-main sh -c \"zgrep restarting ${files} | awk -F 'gz:|localmessages' '{if (substr(\\\$1,0,9)==\\\"/var/log/\\\") {print \\\$NF} else {print \\\$0} }' \" " 2>/dev/null | awk -F 'T| |/' '{print $1,$10}' | sort | grep '-' | uniq -c > ${log_searched}.${node} &
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

    for vdc_name in ${!VDCNAME_SSHABLEIP_MAP[@]}
        do
        echo
        print_info "line:${LINENO} ${FUNCNAME[0]} - ========> VDC: ${vdc_name}"
        if [[ -z ${VDCNAME_SSHABLEIP_MAP[${vdc_name}]} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - sshable IP for vdc ${vdc_name} is not avaliable, got to ${vdc_name} and make a local check"
            continue
        fi

        printf "%-60s %-5s %-12s %-15s %-19s %-s\n" "ConfigurationName" "InCMF" "Default" "Configured" "Mtime" "Audit"
        echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------"
        for switch in ${switches}
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking: [${switch}]"

            ssh -n ${VDCNAME_SSHABLEIP_MAP[${vdc_name}]} "sudo -i docker exec object-main /opt/storageos/tools/cf_client --user ${MGMT_USER} --password ${MGMT_PWD} --list --name ${switch}" 2>/dev/null | awk -F '"' -v v_switch=${switch} 'BEGIN{
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
    done
    echo

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_common_check_tasks
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    validate_dt "CT" 1 > /dev/null
    validate_dt "PR" 1 > /dev/null
    validate_dt "SS" 1 > /dev/null

    local query_str="http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK/?type=GEO_DATA_SEND_TRACKER&useStyle=raw"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"
    local f_cm_geo_send_tracker_tasks=${WORK_DIR}/gc_common.cm_geo_send_tracker_tasks
    dt_query "${query_str}" ${f_cm_geo_send_tracker_tasks}
    local cm_geo_send_tracker_tasks_cnt=$(grep -c schemaType ${f_cm_geo_send_tracker_tasks})

    query_str="http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=GEO_DELETE&useStyle=raw"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"
    local f_cm_geo_delete_tasks=${WORK_DIR}/gc_common.cm_geo_delete_tasks
    dt_query "${query_str}" ${f_cm_geo_delete_tasks}
    local cm_geo_delete_tasks_cnt=$(grep -c schemaType ${f_cm_geo_delete_tasks})

    query_str="http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=FREE_BLOCKS&useStyle=raw"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"
    local f_cm_free_block_tasks=${WORK_DIR}/gc_common.cm_free_block_tasks
    dt_query "${query_str}" ${f_cm_free_block_tasks}
    local cm_free_block_tasks_cnt=$(grep -c schemaType ${f_cm_free_block_tasks})

    query_str="http://${DATA_IP}:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_TASK_KEY?type=BLOCK_FREE_TASK&useStyle=raw"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"
    local f_ss_block_free_tasks=${WORK_DIR}/gc_common.ss_free_block_tasks
    dt_query "${query_str}" ${f_ss_block_free_tasks}
    local ss_block_free_tasks_cnt=$(grep -c schemaType ${f_ss_block_free_tasks})

    query_str="http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK/?type=REPAIR&useStyle=raw"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"
    local f_cm_repair_tasks=${WORK_DIR}/gc_common.cm_repair_tasks
    dt_query "${query_str}" ${f_cm_repair_tasks}
    local cm_repair_tasks_cnt=$(grep -c schemaType ${f_cm_repair_tasks})

    query_str="http://${DATA_IP}:9101/diagnostic/PR/1/DumpAllKeys/DTBOOTSTRAP_TASK/?useStyle=raw"
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying [ ${query_str} ]"
    local f_pr_bootstrap_tasks=${WORK_DIR}/gc_common.pr_bootstrap_tasks
    dt_query "${query_str}" ${f_pr_bootstrap_tasks}
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

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_common_check_blocking_issue
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local f_blocking_issue_report=${WORK_DIR}/gc_common.blocking_issue
    echo > ${f_blocking_issue_report}
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> GC Blocking Issues" >> ${f_blocking_issue_report}

    local f_issue_repository=${SCRIPTDIR}/gc_blocking_issue_repository
    ## search log file or 'WSCritical:' of GEO or GC
    local log_files=$(sudo viprexec -f ${MACHINES} -c -i 'find /var/log/ -type f -name *-error.log' 2>&1 | awk -F '/' '/log$/{print $NF}' | sort | uniq)
    [[ -f ${f_issue_repository} && -r ${f_issue_repository} ]] && log_files=$(echo "${log_files}";awk -F ';' '{if ($0 != "" && substr($1,0,1) != "#") {print $6}}' ${f_issue_repository} 2>&1 | tr ' ' '\n' | strings | sort | uniq)

    # for log_file_name in $(awk -F ';' '{if ($0 != "" && substr($1,0,1) != "#") {print $6}}' ${f_issue_repository} 2>&1 | tr ' ' '\n' | strings | sort | uniq)
    # for log_file_name in $(sudo viprexec -f ${MACHINES} -c -i 'find /var/log/ -type f -name *-error.log' 2>&1 | awk -F '/' '/log$/{print $NF}' | sort | uniq)
    for log_file_name in $(echo "${log_files}" | sort | uniq)
        do
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Searching in ${log_file_name} for 'WSCritical:' of GEO or GC'"
        search_logs_full_days_or_hrs ${log_file_name} ${SEARCH_LOG_FOR_ISSUE_DAYS} ${SEARCH_LOG_FOR_ISSUE_HOURS} "WSCritical: \[GEO\]|WSCritical: \[GC\]|WSCritical: GC|WSCritical: GEO" ${WORK_DIR}/WSCritical.${log_file_name}-
    done

    # cat ${WORK_DIR}/WSCritical.${log_file_name}-* | sort -r > ${WORK_DIR}/WSCritical.log

    # ## check blocking issues
    # while read line
        # do
        # # LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking log [${line}]"
        # # echo "Checking log [${line}]"
        # local matching_result=$(awk -F ";" -v v_line="${line}" 'BEGIN{
            # matched=0
            # matched_line="-"
        # }{
            # print $0
            # if (substr($1, 0, 1) == "#" || substr($1, 0, 1) == "" || substr($1, 0, 1) == " ") {
                # print "skip line"
                # next
            # }
            # issue_id=$1
            # storage_jira=$2
            # ee_jiras=$3
            # description=$4
            # keywords=$5
            # # print keywords
            # # gsub(/\[|\]/, ".*", keywords)
            # # gsub(/\[/, "\\[", keywords)
            # # gsub(/\]/, "\\]", keywords)
            # # print keywords"+++++++++++++"
            # log_file_name=$6
            # severity=$7
            # category=$8
            # workaround=$9
            # solution=$10
            # action_plan=$11
            # extra_info=$12

            # if (match(v_line, keywords)) {
                # matched = 1
                # exit
            # }
        # } END{
            # print matched";"$0
        # }' ${f_issue_repository})

        # if grep -q '^1;' <<< "${matching_result}" 2>/dev/null ; then

        # else

        # fi
    # done < test.log # ${WORK_DIR}/WSCritical.log

    local f_final_log=${WORK_DIR}/WSCritical.log
    # awk -F 'gz:|log:' '{print $NF}' ${WORK_DIR}/WSCritical.*.log-* 2>/dev/null | sort > ${f_final_log}
    cat ${WORK_DIR}/WSCritical.*.log-* 2>/dev/null | sort > ${f_final_log}

    if [[ ! -f ${f_final_log} || ! -s ${f_final_log} ]] ; then
        print_info "line:${LINENO} ${FUNCNAME[0]} -   Didn't find GC blocking issue in latest ${SEARCH_LOG_FOR_ISSUE_DAYS} days and ${SEARCH_LOG_FOR_ISSUE_HOURS} hours" >> ${f_blocking_issue_report}
        cat ${f_blocking_issue_report}
        return 0
    fi

    local f_blocking_issue_log_copy=${WORK_DIR_PARENT}/WSCritical.log.${WORK_DIR_SUB}
    cp ${f_final_log} ${f_blocking_issue_log_copy}
    ## load known issue file
    if [[ ! -f ${f_issue_repository} || ! -r ${f_issue_repository} ]] ; then
        print_info "line:${LINENO} ${FUNCNAME[0]} -   There's no repository file ${f_issue_repository}, thus not able to list issue detail" >> ${f_blocking_issue_report}
    else
        ## check blocking issues
        while read line
            do
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking line [${line}]"
            # echo "Checking line [${line}]"
            if grep -q -e '^#' -e '^[[:blank:]]*$' <<< "${line}" 2>/dev/null ; then
                ## skip commentted lines
                continue
            fi

            # 1.issue id; 2.storage JIRA; 3.known ee JIRAs; 4.issue description; 5.keywords in log; 6.log file name; 7.severity; 8.category(BtreeGC/RepoGC/Geo); 9.workaround; 10.solution; 11.action plan for CS; 12.extra info;
            awk -v v_line="${line}" 'BEGIN{
                split(v_line, sl, ";")
                issue_id=sl[1]
                storage_jira=sl[2]
                ee_jiras=sl[3]
                description=sl[4]
                keywords=sl[5]
                # gsub(/\[|\]/, ".*", keywords)
                gsub(/\[/, "\\[", keywords)
                gsub(/\]/, "\\]", keywords)
                # print keywords"+++++++++++++"
                log_file_name=sl[6]
                severity=sl[7]
                category=sl[8]
                workaround=sl[9]
                solution=sl[10]
                action_plan=sl[11]
                extra_info=sl[12]

                match_cnt=0
                latest_match=""
            }{
                if (match($0, keywords)) {
                    match_cnt++
                    latest_match=$0
                }
            } END{
                if (match_cnt > 0) {
                    print "------------------------------------"
                    printf("%-14s | %s\n", "Issue ID:",issue_id)
                    printf("%-14s | %s\n", "Descirption:",description)
                    printf("%-14s | %s\n", "Related JIRA:",storage_jira)
                    printf("%-14s | %s\n", "EE JIRAs:",ee_jiras)
                    printf("%-14s | %s\n", "Severity:",severity)
                    printf("%-14s | %s\n", "Category:",category)
                    printf("%-14s | %s\n", "Frequency:",match_cnt)
                    printf("%-14s | %s\n", "Latest:",latest_match)
                    printf("%-14s | %s\n", "Workaround:",workaround)
                    printf("%-14s | %s\n", "Solution:",solution)
                    printf("%-14s | %s\n", "Action Plan:",action_plan)
                    printf("%-14s | %s\n", "Extra Info:",extra_info)
                    print "------------------------------------"
                }
            }' ${f_final_log} >> ${f_blocking_issue_report}
        done < ${f_issue_repository}
    fi
    cat ${f_blocking_issue_report}
    print_error "line:${LINENO} ${FUNCNAME[0]} - Found GC blocking issue in ${f_blocking_issue_log_copy}, please escalate to EE to further investigate"
    print_info "line:${LINENO} ${FUNCNAME[0]} -   * If any issue listed, it doesn't mean this VDC have exact issue of 'Related JIRA', please have Engineering to confirm"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

############################### btree and repo gc checks ###########################

function btree_gc_check_configuration
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> Btree GC Configurations"

    get_cmf_configuration "com.emc.ecs.chunk.gc.btree.enabled com.emc.ecs.chunk.gc.btree.scanner.verification.enabled com.emc.ecs.chunk.gc.btree.scanner.copy.enabled"

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_configuration
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> REPO GC Configurations"

    if [[ $(echo "${ECS_VERSION_SHORT} < 3.1" | bc) -ne 0 ]] ; then
        get_cmf_configuration "com.emc.ecs.chunk.gc.repo.enabled com.emc.ecs.chunk.gc.repo.verification.enabled com.emc.ecs.chunk.gc.repo.reclaimer.no_recycle_window"
    else
        get_cmf_configuration "com.emc.ecs.chunk.gc.repo.enabled com.emc.ecs.chunk.gc.repo.verification.enabled com.emc.ecs.chunk.gc.repo.reclaimer.no_recycle_window com.emc.ecs.chunk.gc.repo.partial.enabled com.emc.ecs.chunk.gc.repo.partial.garbage_cache_enabled"
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function gc_common_check_obccmarker
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local f_ob_cc_markers=${WORK_DIR}/gc_common.ob_cc_markers

    local dt_ids=$(validate_dt "OB" 0)

    for ob_id in ${dt_ids}
        do

        local query_str="http://${DATA_IP}:9101/gc/obCcMarker/${ob_id}"
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - querying ['${query_str}' ]"
        local ob_cc_marker=$(dt_query "${query_str}" | xmllint --format - 2>/dev/null)
        echo "${ob_cc_marker}" | grep -q 'HTTP ERROR'
        if [[ $? -eq 0 || -z ${ob_cc_marker} ]] ; then
            print_error "line:${LINENO} ${FUNCNAME[0]} - Failed to get obCcMarker '${query_str}'"
            continue
        fi

        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Checking ob_cc_marker for OB: ${ob_id}"
        echo "${ob_cc_marker}" | awk -v v_ob_id=${ob_id} -F '<|>' '{
            if ($2=="local_zone_id" || substr($2,0,14)=="remote_zone_id") {
                zone_name=$2
                zone_name_id_map[zone_name]=$3
            } else if ($2=="journal_entry") {
                split($3,sl," ")
                zone_name_jr_map[zone_name]=sl[8]
            } else if ($2=="max_journal_entry") {
                split($3,sl," ")
                zone_name_maxjr_map[zone_name]=sl[8]
            }
        } END{
            for (zone_name in zone_name_id_map) {
                m_jr=zone_name_maxjr_map[zone_name]
                if (m_jr == ""){
                    m_jr="-"
                }
                jr=zone_name_jr_map[zone_name]
                if (jr == ""){
                    jr="-"
                    ratio=100
                }
                if (jr == "-" || m_jr == "-") {
                    jr_gap=0
                } else {
                    jr_d = strtonum("0x"jr)
                    m_jr_d = strtonum("0x"m_jr)
                    ratio = 100*jr_d/m_jr_d
                    jr_gap = m_jr_d - jr_d
                }
                printf("%-116s %16s %16s %6.2f %4lu %s\n", v_ob_id, m_jr, jr, ratio, jr_gap, zone_name)
            }
        }' >> ${f_ob_cc_markers}
    done

    awk -v v_ratio_threshold=${OB_CC_MARKER_RATIO_THRESHOLD} -v v_gap_threshold=${OB_CC_MARKER_GAP_THRESHOLD} 'BEGIN{
        smallest_ratio=100
        smallest_ratio_dt="-"
        jr_ratio_small=0
        jr_ratio_big=0
        bigest_gap=0
        bigest_gap_dt="-"
        jr_gap_small=0
        jr_gap_big=0
    }{
        dt_id=$1
        ratio=$4
        jr_gap=$5

        if (ratio < v_ratio_threshold) {
            jr_ratio_small++
        } else {
            jr_ratio_big++
        }
        if (ratio < smallest_ratio) {
            smallest_ratio=ratio
            smallest_ratio_dt=dt_id
        }
        if (jr_gap >= v_gap_threshold) {
            jr_gap_big++
        } else {
            jr_gap_small++
        }
        if (jr_gap > bigest_gap) {
            bigest_gap=jr_gap
            bigest_gap_dt=dt_id
        }
    } END{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> OBCCMarker Status")
        print "---------------------------------"
        printf("%-12s %2d%-7s | %8lu\n", "JRs Ratio >=", v_ratio_threshold, "%", jr_ratio_big)
        print "---------------------------------"
        printf("%-11s %2d%-8s | %8lu\n", "JRs Ratio <", v_ratio_threshold, "%", jr_ratio_small)
        print "---------------------------------"
        printf("%-22s | %7.2f%s %s\n", "Smallest Ratio and DT", smallest_ratio, "%", smallest_ratio_dt)
        print "---------------------------------"
        printf("%-10s %-11lu | %8lu\n", "JRs Gap >=", v_gap_threshold, jr_gap_big)
        print "---------------------------------"
        printf("%-9s %-12lu | %8lu\n", "JRs Gap <", v_gap_threshold, jr_gap_small)
        print "---------------------------------"
        printf("%-22s | %8lu %s\n", "Biggest Gap and DT", bigest_gap, bigest_gap_dt)
        print "---------------------------------"
    }' ${f_ob_cc_markers}

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_rr_rebuild
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    ## https://asdwiki.isus.emc.com:8443/display/ECS/REPO+GC+Trouble+Shooting+-+RR+Rebuild
    ## "/service/rrrebuild/status" is deprecated
    ## local rr_rebuild_tasks=$(dt_query http://${DATA_IP}:9101/service/rrrebuild/status | grep "^urn" | sed -e 's/\r//g' -e 's/^<.*<pre>//g' | grep "$rg" | awk '{print $NF}')

    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Getting REFTABLE_REBUILD_TASK"

    local f_rr_rebuilds=${WORK_DIR}/repo_gc.rr_rebuilds

    echo "curl -s 'http://${DATA_IP}:9101/diagnostic/OB/0/DumpAllKeys/REFTABLE_REBUILD_TASK/?showvalue=gpb&useStyle=raw'" > ${f_rr_rebuilds}
    printf "%-17s %-115s %-s\n" "Status" "OB_ID" "JOURNAL_REGION|Checkpoint" >> ${f_rr_rebuilds}
    echo "-----------------------------------------------------------------------------------------------------------------------" >> ${f_rr_rebuilds}
    local dt_ids=$(validate_dt "OB" 0 "url")
    for ob_url in ${dt_ids}
        do
        local query_str="${ob_url}REFTABLE_REBUILD_TASK/?showvalue=gpb&useStyle=raw"
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - Querying '${query_str}'"

        dt_query "${query_str}" ${WORK_DIR}/tmp
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
        }' ${WORK_DIR}/tmp >> ${f_rr_rebuilds}
    done

    awk '{
        if ($1 == "Status" || $1 == "curl" || $1 == "" || substr($1, 0, 3) == "---") {
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
    }' ${f_rr_rebuilds} | tee -a ${f_rr_rebuilds}

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check_verification
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ $(echo "${ECS_VERSION_SHORT} >= 3.0" | bc) -ne 0 && ${DONT_CHECK_VERIFICATION_TASKS_FROM_DT} -eq 1 && ${CHECK_REPO_GC_FORCE_CHECK_VERIFICATION_TASKS_FROM_DT} -ne 1 ]] ; then
        echo
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> Verification Status"
        print_info "line:${LINENO} ${FUNCNAME[0]} -   Full reclaimable repo chunk in stats is a too big value, it's not necessary to get verification tasks from DT"
        return 0
    fi

    local f_repo_gc_scan_task=${WORK_DIR}/repo_gc.cm_verification_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${ZONE_ID}&type=REPO&time=0&useStyle=raw" ${f_repo_gc_scan_task}

    if [[ ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] ; then
        awk -v v_task_cnt_threshold=${VERIFICATION_TASK_CNT_THRESHOLD} -v v_task_delay_day_threshold=${VERIFICATION_TASK_DELAY_DAY_THRESHOLD} 'BEGIN{
            delay_day_threshold_time_stamp = systime() - 60*60*24*v_task_delay_day_threshold
            tasks_before = 0
            tasks_after = 0
        }{
            if (substr($1,0,4) == "http") {
                split($1,sl,"/")
                dt_id = sl[4]
                task_cnt_map[dt_id] = 0
            } else if ($1 == "schemaType") {
                task_cnt_map[dt_id]++
                if (substr($8,0,10) > delay_day_threshold_time_stamp) {
                    tasks_after++
                } else {
                    tasks_before++
                }
            }
        } END{
            num_dt_exceed_task_cnt_threshold = 0
            dt_has_max_task="-"
            max_task=0
            for (dt_id in task_cnt_map) {
                if (task_cnt_map[dt_id] > v_task_cnt_threshold) {
                    num_dt_exceed_task_cnt_threshold++
                }
                if (task_cnt_map[dt_id] > max_task) {
                    dt_has_max_task = dt_id
                    max_task = task_cnt_map[dt_id]
                }
            }

            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Verification Status")
            print "---------------------------------"
            printf("%-17s | %13lu\n", "Total Tasks", tasks_after+tasks_before)
            print "---------------------------------"
            printf("%-8s %2d %-5s | %13lu\n", "Tasks in", v_task_delay_day_threshold, "Days", tasks_after)
            print "---------------------------------"
            printf("%-5s %2d %-8s | %13lu\n", "Tasks", v_task_delay_day_threshold, "Days Ago", tasks_before)
            print "---------------------------------"
            printf("%-11s %-5lu | %13lu\n", "DTs Tasks >", v_task_cnt_threshold, num_dt_exceed_task_cnt_threshold)
            print "---------------------------------"
            printf("%-17s | %13lu %s\n", "Max Tasks and DT", max_task, dt_has_max_task)
            print "---------------------------------"
        }' ${f_repo_gc_scan_task}
    else
        grep -c schemaType ${f_repo_gc_scan_task} | awk '{
            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Verification Status")
            print "---------------------------------"
            printf("%-17s | %13lu\n", "Total Tasks", $1)
            print "---------------------------------"
        }'
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_check_verification
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local f_btree_gc_scan_task=${WORK_DIR}/btree_gc.cm_verification_tasks
    dt_query "http://${DATA_IP}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK?zone=${ZONE_ID}&type=BTREE&time=0&useStyle=raw" ${f_btree_gc_scan_task}

    if [[ ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] ; then
        awk -v v_task_cnt_threshold=${VERIFICATION_TASK_CNT_THRESHOLD} -v v_task_delay_day_threshold=${VERIFICATION_TASK_DELAY_DAY_THRESHOLD} 'BEGIN{
            delay_day_threshold_time_stamp = systime() - 60*60*24*v_task_delay_day_threshold
            tasks_before = 0
            tasks_after = 0
        }{
            if (substr($1,0,4) == "http") {
                split($1,sl,"/")
                dt_id = sl[4]
                task_cnt_map[dt_id] = 0
            } else if ($1 == "schemaType") {
                task_cnt_map[dt_id]++
                if (substr($8,0,10) > delay_day_threshold_time_stamp) {
                    tasks_after++
                } else {
                    tasks_before++
                }
            }
        } END{
            num_dt_exceed_task_cnt_threshold = 0
            dt_has_max_task="-"
            max_task=0
            for (dt_id in task_cnt_map) {
                if (task_cnt_map[dt_id] > v_task_cnt_threshold) {
                    num_dt_exceed_task_cnt_threshold++
                }
                if (task_cnt_map[dt_id] > max_task) {
                    dt_has_max_task = dt_id
                    max_task = task_cnt_map[dt_id]
                }
            }

            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Verification Status")
            print "---------------------------------"
            printf("%-17s | %13lu\n", "Total Tasks", tasks_after+tasks_before)
            print "---------------------------------"
            printf("%-8s %2d %-5s | %13lu\n", "Tasks in", v_task_delay_day_threshold, "Days", tasks_after)
            print "---------------------------------"
            printf("%-5s %2d %-8s | %13lu\n", "Tasks", v_task_delay_day_threshold, "Days Ago", tasks_before)
            print "---------------------------------"
            printf("%-11s %-5lu | %13lu\n", "DTs Tasks >", v_task_cnt_threshold, num_dt_exceed_task_cnt_threshold)
            print "---------------------------------"
            printf("%-17s | %13lu %s\n", "Max Tasks and DT", max_task, dt_has_max_task)
            print "---------------------------------"
        }' ${f_btree_gc_scan_task}
    else
        grep -c schemaType ${f_btree_gc_scan_task} | awk '{
            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Verification Status")
            print "---------------------------------"
            printf("%-17s | %13lu\n", "Total Tasks", $1)
            print "---------------------------------"
        }'
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_get_history_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO"
}

function repo_gc_get_history_from_log
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    ## cm-chunk-reclaim.log.20170701-013511.gz:2017-06-30T20:06:23,163 [TaskScheduler-ChunkManager-DEFAULT_BACKGROUND_OPERATION-ScheduledExecutor-234]  INFO  RepoReclaimer.java (line 649) successfully recycled repo 3a0a0535-5d00-47d5-a293-96cfb93a0c59
    search_logs cm-chunk-reclaim.log 1 "RepoReclaimer.* successfully recycled repo" ${WORK_DIR}/repo_gc.reclaimed_history_log-

    local repo_history=${WORK_DIR}/repo_gc.reclaimed_history
    awk -F':' '{ print $2 }' ${WORK_DIR}/repo_gc.reclaimed_history_log-* | sed -e 's/ /T/g' | sort | uniq -c > ${repo_history}

    if [[ ! -s ${repo_history} ]] ; then
        echo
        print_info "line:${LINENO} ${FUNCNAME[0]} - ====> Reclaim History"
        print_info "line:${LINENO} ${FUNCNAME[0]} -   There's no garbage reclaimed in past 24 hrs"
        return
    fi

    awk 'BEGIN{
        current_timestamp = mktime(strftime("%Y %m %d %H 00 00", systime()))
    }{
        chunk_num = $1
        time_readable = $2
        gsub(/-/," ",time_readable)
        gsub(/T/," ",time_readable)
        hr_chunk_map[int((current_timestamp - mktime(time_readable" 00 00"))/(60*60))] = chunk_num
    } END{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Reclaim History")
        chunk_cnt=0
        for (hr_delta in hr_chunk_map) {
            chunk_cnt += hr_chunk_map[hr_delta]
            printf("  - In past %2s hrs, reclaimed %6d chunks, %8.2f GB;  %5d chunks, %7.2f GB/hr\n", hr_delta, chunk_cnt, 134217600*chunk_cnt/(1024*1024*1024), hr_chunk_map[hr_delta], 134217600*hr_chunk_map[hr_delta]/(1024*1024*1024))
        }
        print "  * Size is estimated with maximum chunk size, actual reclaimed size could be smaller"
    }' ${repo_history}

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}


function btree_gc_get_history_from_log
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    ## cm-chunk-reclaim.log.20170702-152336.gz:2017-07-01T21:42:54,209 [TaskScheduler-ChunkManager-DEFAULT_BACKGROUND_OPERATION-ScheduledExecutor-069]  INFO  ReclaimState.java (line 45) Chunk 482a16a6-e7c6-479c-8e99-65ae794c08ff reclaimed:true
    search_logs cm-chunk-reclaim.log 1 "ReclaimState.* Chunk .* reclaimed:" ${WORK_DIR}/btree_gc.reclaimed_history_log-

    local btree_history=${WORK_DIR}/btree_gc.reclaimed_history
    awk -F':' '{ print $2 }' ${WORK_DIR}/btree_gc.reclaimed_history_log-* | sed -e 's/ /T/g' | sort | uniq -c > ${btree_history}

    if [[ ! -s ${btree_history} ]] ; then
        echo
        print_info "line:${LINENO} ${FUNCNAME[0]} - ====> Reclaim History"
        print_info "line:${LINENO} ${FUNCNAME[0]} -   There's no garbage reclaimed in past 24 hrs"
        return
    fi

    awk 'BEGIN{
        current_timestamp = mktime(strftime("%Y %m %d %H 00 00", systime()))
    }{
        chunk_num = $1
        time_readable = $2
        gsub(/-/," ",time_readable)
        gsub(/T/," ",time_readable)
        hr_chunk_map[int((current_timestamp - mktime(time_readable" 00 00"))/(60*60))] = chunk_num
    } END{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Reclaim History")
        chunk_cnt=0
        for (hr_delta in hr_chunk_map) {
            chunk_cnt += hr_chunk_map[hr_delta]
            printf("  - In past %2s hrs, reclaimed %6d chunks, %8.2f GB;  %5d chunks, %7.2f GB/hr\n", hr_delta, chunk_cnt, 134217600*chunk_cnt/(1024*1024*1024), hr_chunk_map[hr_delta], 134217600*hr_chunk_map[hr_delta]/(1024*1024*1024))
        }
        print "  * Size is estimated with maximum chunk size, actual reclaimed size could be smaller"
    }' ${btree_history}
    
    # awk -v v_check_days=${CHECK_RECLAIM_DAYS} -F ':' 'BEGIN{
        # current_timestamp = mktime(strftime("%Y %m %d %H 00 00", systime()))
        # chunk_cnt = 0
    # }{
        # date_chunk_cnt_map[substr($1, 0, 13)] += 1
    # }END{
        # print ""
        # printf("\033[1;34m%s\033[0m\n", "====> Reclaim History")
        # if(length(date_chunk_cnt_map) == 0) {
            # printf("  - There is no garbage reclaimed in last 24 hrs\n")
        # } else {
            # asorti(date_chunk_cnt_map,date_chunk_cnt_map_key_sorted)
            # for (key in date_chunk_cnt_map_key_sorted) {
                # chunk_cnt += date_chunk_cnt_map[date_chunk_cnt_map_key_sorted[key]]
                # time_readable = date_chunk_cnt_map_key_sorted[key]
                # gsub(/-|T|:/, " ", time_readable)
                # hr_delta = int((current_timestamp - mktime(time_readable" 00 00"))/3600)
                # printf("  - In past %2s hrs, reclaimed %6d chunks, %8.2f GB;  %5d chunks, %7.2f GB/hr\n", hr_delta, chunk_cnt, 134217600*chunk_cnt/(1024*1024*1024), date_chunk_cnt_map[date_chunk_cnt_map_key_sorted[key]], 134217600*date_chunk_cnt_map[date_chunk_cnt_map_key_sorted[key]]/(1024*1024*1024))
            # }
        # }
    # }' ${WORK_DIR}/btree_gc.reclaimed_history_log-*

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_get_remaining_from_dt
{
    print_msg "line:${LINENO} ${FUNCNAME[0]} - TODO, there's no way figured out to check remaining REPO garbage in pre ECS 3.0.0"
}

function repo_gc_get_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local partial_candidates=0
    local cleanup_jobs_for_repo_garbage=0
    local repo_garbage_in_cleanup_jobs=0
    local merge_way_gc_src_chunks=0
    local merge_way_gc_tasks=0
    local merge_way_gc_processed_chunks=0
    local ec_freed_slots=0

    if [[ $(echo "${ECS_VERSION_SHORT} >= 3.1" | bc) -ne 0 ]]; then
        local f_repo_gc_repo_usage_data=${WORK_DIR}/repo_gc.repo_usage_data
        dt_query "http://${DATA_IP}:9101/diagnostic/RR/0/DumpAllKeys/REPO_USAGE?useStyle=raw" ${f_repo_gc_repo_usage_data}
        partial_candidates=$(awk '/schema/{count+=$4} END{print count}' ${f_repo_gc_repo_usage_data})
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - partial_candidates(fromDT) ${partial_candidates}"

        repo_garbage_in_cleanup_jobs=$(query_counter "repo_garbage_in_cleanup_jobs.TOTAL")
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - repo_garbage_in_cleanup_jobs.TOTAL ${repo_garbage_in_cleanup_jobs}"
        cleanup_jobs_for_repo_garbage=$(query_counter "cleanup_jobs_for_repo_garbage.TOTAL")
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleanup_jobs_for_repo_garbage.TOTAL ${cleanup_jobs_for_repo_garbage}"
        if [[ $(echo "${cleanup_jobs_for_repo_garbage} > ${CLEANUP_JOBS_FOR_REPO_GARBAGE_THRESHOLD}" | bc) -ne 0 ]] ; then
            DONT_CHECK_CLEANUP_JOBS_FROM_DT=1
        fi
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - cleanup_jobs_for_repo_garbage:${cleanup_jobs_for_repo_garbage} THRESHOLD:${CLEANUP_JOBS_FOR_REPO_GARBAGE_THRESHOLD} DONT_CHECK_CLEANUP_JOBS_FROM_DT:${DONT_CHECK_CLEANUP_JOBS_FROM_DT}"

        merge_way_gc_src_chunks=$(query_counter "merge_way_gc_src_chunks.TOTAL")
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - merge_way_gc_src_chunks.TOTAL ${merge_way_gc_src_chunks}"

        merge_way_gc_tasks=$(query_counter "merge_way_gc_tasks.TOTAL")
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - merge_way_gc_tasks.TOTAL ${merge_way_gc_tasks}"

        merge_way_gc_processed_chunks=$(query_counter "merge_way_gc_processed_chunks.TOTAL")
        LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - merge_way_gc_processed_chunks.TOTAL ${merge_way_gc_processed_chunks}"

        if [[ $(echo "${ECS_VERSION_SHORT} >= 4.0" | bc) -ne 0 ]]; then  ### TODO: version is TBD
            ec_freed_slots=$(query_counter "ec_freed_slots.TOTAL")
            LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ec_freed_slots.TOTAL ${ec_freed_slots}"
        fi
    fi

    local deleted_data_repo=$(query_counter "deleted_data_repo.TOTAL")
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - deleted_data_repo.TOTAL ${deleted_data_repo}"

    local total_repo_garbage=$(query_counter "total_repo_garbage.TOTAL")
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - total_repo_garbage.TOTAL ${total_repo_garbage}"

    local full_reclaimable_repo_chunk=$(query_counter "full_reclaimable_repo_chunk.TOTAL")
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - full_reclaimable_repo_chunk.TOTAL ${full_reclaimable_repo_chunk}"
    if [[ $(echo "${full_reclaimable_repo_chunk} > ${FULL_RECLAIMABLE_REPO_CHUNK_THRESHOLD}" | bc) -ne 0 ]] ; then
        DONT_CHECK_VERIFICATION_TASKS_FROM_DT=1
    fi
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - full_reclaimable_repo_chunk:${full_reclaimable_repo_chunk} THRESHOLD:${FULL_RECLAIMABLE_REPO_CHUNK_THRESHOLD} DONT_CHECK_VERIFICATION_TASKS_FROM_DT:${DONT_CHECK_VERIFICATION_TASKS_FROM_DT}"

    echo "${deleted_data_repo} ${total_repo_garbage} ${full_reclaimable_repo_chunk} ${cleanup_jobs_for_repo_garbage} ${repo_garbage_in_cleanup_jobs} ${merge_way_gc_src_chunks} ${merge_way_gc_tasks} ${merge_way_gc_processed_chunks} ${ec_freed_slots} ${partial_candidates}" | awk -v v_ecs_version_short=${ECS_VERSION_SHORT} '{
        deleted_data_repo = $1
        total_repo_garbage = $2
        full_reclaimable_repo_chunk = $3
        cleanup_jobs_for_repo_garbage = $4
        repo_garbage_in_cleanup_jobs = $5
        merge_way_gc_src_chunks=$6
        merge_way_gc_tasks=$7
        merge_way_gc_processed_chunks=$8
        ec_freed_slots = $9
        partial_candidates = $10

        remaining = total_repo_garbage
        reclaimable = full_reclaimable_repo_chunk*134217600
        remaining_partial = (total_repo_garbage - reclaimable)

        partial_xor_way_handled=ec_freed_slots*134217600/60
        partial_merge_way_handled = merge_way_gc_processed_chunks*134217600*2/3
        reclaimed = (deleted_data_repo + partial_xor_way_handled)

        partial_merge_way_handling = (merge_way_gc_src_chunks - merge_way_gc_tasks)*134217600
        partial_eligible = partial_candidates + partial_merge_way_handling

        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Repo GC Statistic")
        print "--------------------------------------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "Reclaimed Garbage", reclaimed/1073741824, reclaimed/1099511627776)
        if ( v_ecs_version_short >= 3.1 ) {
            if ( v_ecs_version_short >= 4.0 ) {  ### TODO: version is TBD
                print "|                            ---------------------------------"
                printf("%-27s | %13.2f GB | %10.2f TB\n", "|- Handled Partial Garbage", (partial_xor_way_handled+partial_merge_way_handled)/1073741824, (partial_xor_way_handled+partial_merge_way_handled)/1099511627776)
            } else {
                print "|                            ---------------------------------"
                printf("%-27s | %13.2f GB | %10.2f TB\n", "|- Handled Partial Garbage", partial_merge_way_handled/1073741824, partial_merge_way_handled/1099511627776)
            }
        }
        print "--------------------------------------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "Remaining Garbage", remaining/1073741824, remaining/1099511627776)
        print "|                            ---------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "|- Full Reclaimable Garbage", reclaimable/1073741824, reclaimable/1099511627776)
        print "|                            ---------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "|- Partial Garbage", remaining_partial/1073741824, remaining_partial/1099511627776)
        if ( v_ecs_version_short >= 3.1 ) {
            print "   |                         ---------------------------------"
            printf("%-27s | %13.2f GB | %10.2f TB\n", "   |- Eligible Partial", partial_eligible/1073741824, partial_eligible/1099511627776)
            print "      |                      ---------------------------------"
            printf("%-27s | %13.2f GB | %10.2f TB\n", "      |- Handling Partial", partial_merge_way_handling/1073741824, partial_merge_way_handling/1099511627776)
        }
        print "--------------------------------------------------------------"
        printf("%-27s | %16lu |\n", "Full Reclaimable Chunks Cnt", full_reclaimable_repo_chunk)
        if ( v_ecs_version_short >= 3.1 ) {
            print "--------------------------------------------------------------"
            printf("%-27s | %16lu |\n", "Cleanup Jobs Cnt", cleanup_jobs_for_repo_garbage)
            print "--------------------------------------------------------------"
            printf("%-27s | %13.2f GB | %10.2f TB\n", "Garbage in Cleanup Jobs", repo_garbage_in_cleanup_jobs/1073741824, repo_garbage_in_cleanup_jobs/1099511627776)
        }
        print "--------------------------------------------------------------"
        print "  * Reclaimed Garbage: reclaimed garbage since VDC was in 3.0 code base"
        print "  * Size of garbage are estimated with maximum chunk size, actual size could be smaller"
    }'

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_get_remaining_from_gc_query
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    local f_btree_gc_remaining_raw=${WORK_DIR}/btree_gc.btreeUsage_raw
    local f_btree_gc_remaining=${WORK_DIR}/btree_gc.btreeUsage

    # for level in $(seq 1 2)
        # do
        # dt_query "http://${DATA_IP}:9101/gc/btreeUsage/${COS}/${level}" ${f_btree_gc_remaining}
    # done

    dt_query "http://${DATA_IP}:9101/gc/btreeUsage/${COS}/1" ${f_btree_gc_remaining_raw} 5400
    sort ${f_btree_gc_remaining_raw} | uniq | grep SEALED > ${f_btree_gc_remaining}

    awk '!/^</' ${f_btree_gc_remaining} | awk -F',' 'BEGIN{
        garbage=0
        count=0
        full_garbage=0
        full_count=0
        reclaimable_partial_garbage=0
        reclaimable_partial_count=0
    } {
        garbage+=134217600-$3
        count++
        if($3 == 0) {
            full_garbage+=134217600
            full_count++
        }
        if($3 < 6710880 && $3 > 0) {
            reclaimable_partial_garbage+=134217600-$3
            partial_count++
        }
    } END{
        print ""
        printf("\033[1;34m%s\033[0m\n", "====> Btree GC Statistic")
        print "--------------------------------------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "Remaining Garbage", garbage/1073741824,garbage/1099511627776)
        print "|                            ---------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "|- Full Reclaimable Garbage", full_garbage/1073741824,full_garbage/1099511627776)
        print "|                            ---------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "|- Partial Garbage", (garbage-full_garbage)/1073741824,(garbage-full_garbage)/1099511627776)
        print "   |                         ---------------------------------"
        printf("%-27s | %13.2f GB | %10.2f TB\n", "   |- Reclaimable Partial", reclaimable_partial_garbage/1073741824,reclaimable_partial_garbage/1099511627776)
        print "--------------------------------------------------------------"
        print "  * Reclaimed Garbage: reclaimed garbage since VDC was in 3.0 code base"
        print "  * Size of garbage are estimated with maximum chunk size, actual size could be smaller"
    }'

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_get_remaining_from_stats
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - TODO, this will be implemented when stats supports Btree GC"
}

function repo_gc_check_cleanup_job
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    if [[ $(echo "${ECS_VERSION_SHORT} >= 3.1" | bc) -ne 0 && ${DONT_CHECK_CLEANUP_JOBS_FROM_DT} -eq 1 && ${CHECK_REPO_GC_FORCE_CHECK_CLEANUP_JOBS_FROM_DT} -ne 1 ]] ; then
        echo
        print_msg "line:${LINENO} ${FUNCNAME[0]} - ====> Cleanup Job Status"
        print_info "line:${LINENO} ${FUNCNAME[0]} -   Cleanup jobs for repo garbage in stats is a too big value, it's not necessary to get cleanup jobs from DT"
        return 0
    fi

    local f_repo_gc_cleanup_jobs=${WORK_DIR}/repo_gc.ob_cleanup_jobs
    dt_query "http://${DATA_IP}:9101/diagnostic/OB/0/DumpAllKeys/DELETE_JOB_TABLE_KEY?type=CLEANUP_JOB&objectId=aa&useStyle=raw" ${f_repo_gc_cleanup_jobs}

    if [[ ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] ; then
        awk -v v_job_cnt_threshold=${CLEANUP_JOB_CNT_THRESHOLD} -v v_day_delay_threshold=${CLEANUP_JOB_DELAY_DAY_THRESHOLD} 'BEGIN{
            delay_day_threshold_time_stamp = systime() - 60*60*24*v_day_delay_threshold
            job_cnt_before = 0
            job_cnt_after = 0
        }{
            if (substr($1,0,4) == "http") {
                split($1,sl,"/")
                dt_id = sl[4]
                job_cnt_map[dt_id] = 0
            } else if ($1 == "schemaType") {
                job_cnt_map[dt_id]++
                if (substr($4,0,10) > delay_day_threshold_time_stamp) {
                    job_cnt_after++
                } else {
                    job_cnt_before++
                }
            }
        } END{
            num_dt_exceed_job_cnt_threshold = 0
            dt_has_max_job="-"
            max_job=0
            for (dt_id in job_cnt_map) {
                if (job_cnt_map[dt_id] > v_job_cnt_threshold) {
                    num_dt_exceed_job_cnt_threshold++
                }
                if (job_cnt_map[dt_id] > max_job) {
                    dt_has_max_job = dt_id
                    max_job = job_cnt_map[dt_id]
                }
            }

            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Cleanup Job Status")
            print "---------------------------------"
            printf("%-17s | %13lu\n", "Total Jobs", job_cnt_after+job_cnt_before)
            print "---------------------------------"
            printf("%-7s %2d %-6s | %13lu\n", "Jobs in", v_day_delay_threshold, "Days", job_cnt_after)
            print "---------------------------------"
            printf("%-4s %2d %-9s | %13lu\n", "Jobs", v_day_delay_threshold, "Days Ago", job_cnt_before)
            print "---------------------------------"
            printf("%-10s %-6lu | %13lu\n", "DTs Jobs >",v_job_cnt_threshold, num_dt_exceed_job_cnt_threshold)
            print "---------------------------------"
            printf("%-17s | %13lu %s\n", "Max Jobs and DT", max_job, dt_has_max_job)
            print "---------------------------------"
        }' ${f_repo_gc_cleanup_jobs}
    else
        grep -c schemaType ${f_repo_gc_cleanup_jobs} | awk '{
            print ""
            printf("\033[1;34m%s\033[0m\n", "====> Cleanup Job Status")
            print "---------------------------------"
            printf("%-17s | %13lu\n", "Total Jobs", $1)
            print "---------------------------------"
        }'
    fi

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function repo_gc_check
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    echo "==== REPO GC Summary ===="

    if [[ $(echo "${ECS_VERSION_SHORT} >= 3.0" | bc) -ne 0 ]] ; then
        repo_gc_get_stats  ## get golbals DONT_CHECK_CLEANUP_JOBS_FROM_DT and DONT_CHECK_VERIFICATION_TASKS_FROM_DT
    else
        repo_gc_get_remaining_from_dt
    fi

    repo_gc_check_cleanup_job &
    repo_gc_check_verification &

    if [[ $(echo "${ECS_VERSION_SHORT} >= 4.0" | bc) -ne 0 ]] ; then
        repo_gc_get_history_from_stats &
    else
        repo_gc_get_history_from_log &
    fi

    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

function btree_gc_check
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    echo "==== Btree GC Summary ===="

    btree_gc_check_verification &

    if [[ ${ECS_VERSION:0:1} -ge 4 ]] ; then
        btree_gc_get_remaining_from_stats &
    elif [[ ${ECS_VERSION:0:1} -ge 3 ]] ; then
        btree_gc_get_remaining_from_gc_query &
    else
        btree_gc_get_remaining_from_gc_query &
    fi

    if [[ ${ECS_VERSION:0:1} -ge 4 ]] ; then
        btree_gc_get_history_from_stats &
    else
        btree_gc_get_history_from_log &
    fi

    wait

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

########################## Main logic ##############################

function main
{
    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - Start"

    echo
    LOG_DEBUG "line:${LINENO} ${FUNCNAME[0]} - ${SCRIPTNAME} version ${VERSION}"
    print_msg "line:${LINENO} ${FUNCNAME[0]} - Temporarily using ${WORK_DIR_SUB} as work directory"

    ## Initialize globals
    get_vdc_info

    [[ ${CHECK_REPO_GC} -eq 1 || ${CHECK_CAPACITY} -eq 1 ]] && dump_stats

    ## set checking scope
    [[ ${CHECK_REPO_GC}  -eq 1 ]] && CHECK_BLOCKING_ISSUE=1 && CHECK_OBCCMARKER=1 && CHECK_TASKS=1 && CHECK_RRREBUILD=1
    [[ ${CHECK_BTREE_GC} -eq 1 ]] && CHECK_BLOCKING_ISSUE=1 && CHECK_OBCCMARKER=1 && CHECK_TASKS=1

    ## pre condition checkings but standalone
    [[ ${CHECK_CONFIG} -eq 1 ]] && repo_gc_check_configuration && btree_gc_check_configuration
    [[ ${CHECK_RESTARTS} -eq 1 ]] && gc_common_check_services_restarts

    [[ ${CHECK_CAPACITY} -eq 1 && ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] && capacity_usage_from_stats
    [[ ${CHECK_CAPACITY_MORE} -eq 1 && ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] && capacity_from_ssm && capacity_from_blockbin

    [[ ${CHECK_DTINIT} -eq 1 ]] && gc_common_dtinit &
    [[ ${CHECK_INJECTION_DAYS} -ne 0 ]] && check_injection &

    ## gc common checkings
    [[ ${CHECK_BLOCKING_ISSUE} -eq 1 && $(echo "${ECS_VERSION_SHORT} >= 3.1" | bc) -ne 0 ]] && gc_common_check_blocking_issue &
    [[ ${CHECK_OBCCMARKER} -eq 1 && ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] && gc_common_check_obccmarker &
    [[ ${CHECK_TASKS} -eq 1 && ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] && gc_common_check_tasks &
    [[ ${CHECK_RRREBUILD} -eq 1 && ${IS_ECS_ENGINEERING_OPERATING} -eq 1 ]] && repo_gc_check_rr_rebuild &

    wait

    [[ ${CHECK_REPO_GC} -eq 1 ]] && repo_gc_check
    [[ ${CHECK_BTREE_GC} -eq 1 ]] && btree_gc_check

    clean_up_work_dir

    LOG_TRACE "line:${LINENO} ${FUNCNAME[0]} - END"
}

[[ $(whoami) != "admin" ]] && print_error "Please use admin role outside container" && exit 1

trap clean_up SIGINT
trap exit_program SIGPIPE

parse_args $*

CLEANUP_JOB_CNT_THRESHOLD=1500
CLEANUP_JOB_DELAY_DAY_THRESHOLD=1
OB_CC_MARKER_RATIO_THRESHOLD=85 #%
OB_CC_MARKER_GAP_THRESHOLD=20
VERIFICATION_TASK_CNT_THRESHOLD=1000
VERIFICATION_TASK_DELAY_DAY_THRESHOLD=10
CLEANUP_JOBS_FOR_REPO_GARBAGE_THRESHOLD=700000
FULL_RECLAIMABLE_REPO_CHUNK_THRESHOLD=1000000
DONT_CHECK_CLEANUP_JOBS_FROM_DT=0
DONT_CHECK_VERIFICATION_TASKS_FROM_DT=0
SEARCH_LOG_FOR_ISSUE_DAYS=3
SEARCH_LOG_FOR_ISSUE_HOURS=0
CHECK_RECLAIM_DAYS=1

# sudo rm -rf /var/tmp/gc_check

WORK_DIR_PARENT=/home/admin/gc_check  ## script will never delete this diretory
WORK_DIR_SUB=$(date '+%Y%m%dT%H%M%S')
WORK_DIR=${WORK_DIR_PARENT}/${WORK_DIR_SUB}  ## script clean up this diretory when script finish or run into error or interrupted

LOCK_FILE=${WORK_DIR_PARENT}/running ## allow only one instance
[[ -f ${LOCK_FILE} ]] && echo "Already running" && exit 17

rm -rf ${WORK_DIR_PARENT}/201*T* 2>/dev/null  ## clean up old diretory

mkdir -p ${WORK_DIR}/curl_verbose 2>/dev/null
[[ $? -ne 0 ]] && echo "Failed to manipulate directory ${WORK_DIR}" && exit 2
touch ${LOCK_FILE}

print_highlight "Please be patient, it's time-consuming to get reclaim history and especially Btree GC statistic, and verification task/cleanup job if the backlog are large."
print_highlight "Before run script, please firstly get a VDC wide MACHINES file if there are multiple racks, using 'getclusterinfo -a ~/MACHINES' for reference."

GC_HISTORY=${WORK_DIR_PARENT}/gc_check.run_history

echo -e "\n\n######################################## START @ $(date '+%Y-%m-%dT%H:%M:%S')" >> ${GC_HISTORY}
main | tee -a ${GC_HISTORY}
echo -e "++++++++++++++++++++++++++++++++++++++++ END @ $(date '+%Y-%m-%dT%H:%M:%S')  \n\n" >> ${GC_HISTORY}

########################## Main logic END ##############################