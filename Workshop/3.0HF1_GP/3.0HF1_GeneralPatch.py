#!/usr/bin/python

##### Keywords #####
# 
####################

# https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets

import sys
import commands
import re
import os

import datetime
import socket
import getopt
import time

import subprocess
import threading
import linecache
import hashlib

from svc_base import Common
import pdb

ignore_15711 = False
ip_addr = ""

start_time = time.time()
common = Common("3.0HF1_GeneralPatch")
local_ip = common._get_local_private_ip()


# improve in svc_base.python
# 1. put retry mechanism into run_cmd and do not implement retry everywhere. need to consider final error handling(?)
#
# TODOs:
# 1. think more about retry ?? need to bypass following logic if we already has some commands failed?
# 2. why run_cmd() may exit(1) ?? check run_cmd() return value is 1 and retry? seems only happened when use "".format() ???

def get_dockerId():
    cmd = 'sudo docker ps | grep emcvipr/object | awk \'{print $1}\''
    result = common.run_cmd(cmd)
    dockerId = result['stdout'].strip('\n')
    
    return dockerId
    
# test 1: set disable BTREE GC failed and need retry ?
def disable_BTREE_GC():
    print "Disable BTREE GC Before Patch ..."
    
    timeout = 60
    retry_delay = 10
    complete_flag = True
        
    print "Setting cmfuser to emcservice"
    cmfuser = "emcservice"
        
    print "Setting cmfpassword to ChangeMe"
    cmfpassword = "ChangeMe"
    
    starttime = int(time.time())
    dockerId = get_dockerId()
    
    while int(time.time()) < (starttime + timeout):  # Retry (need to encapsulate into run_cmd())
        result = setKey("com.emc.ecs.chunk.gc.btree.enabled", "false", dockerId, cmfuser, cmfpassword, "pre-patch for 3.0 HF1 General Patch")
        if not result:
            complete_flag = False
        if complete_flag:
            break # exit
        sleep(retry_delay)
    
    if not complete_flag:
        common.print_failed()
        common.err_output("ERROR:  Could not disable BTREE GC successfully\n")
        exit(1)
        
    print "===========================\n"

def setKey(key, value, dockerId, cmfuser, cmfpassword, reason):
    #cmd = 'sudo docker exec -it %s /opt/storageos/tools/cf_client --set --name %s  --user %s --password %s --value %s --reason %s' % (dockerId, key, cmfuser, cmfpassword, value, reason)
    cmd = 'sudo docker exec -it {} /opt/storageos/tools/cf_client --set --name {}  --user {} --password {} --value {} --reason {}'.format(dockerId, key, cmfuser, cmfpassword, value, reason)
    common.run_cmd(cmd)
    
    # Verify if set successful
    #cmd = 'sudo docker exec -it %s /opt/storageos/tools/cf_client --list --name %s  --user %s --password %s | grep -s "\\"configured_value\\": \\"%s\\"" ' % (dockerId, key, cmfuser, cmfpassword, value)
    cmd = 'sudo docker exec -it {} /opt/storageos/tools/cf_client --list --name {}  --user {} --password {} | grep -s "\\"configured_value\\": \\"{}\\""'.format(dockerId, key, cmfuser, cmfpassword, value)
    result = common.run_cmd(cmd)
    if value in result['stdout']:
        if value == "true":
            print "# CMF key {} enabled successfully".format(key)
        elif value == "false":
            print "# CMF key {} disabled successfully".format(key)
        return True
    else:
        print "# CMF key {} set failure, please manually enable it".format(key)
        print "# For more information, please refer to https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets"
        return False
    
def pre_15711():
    timeout = 60 * 5
    retry_delay = 30
    complete_flag = True
    starttime = int(time.time())
    
    print "Pre patch step for STORAGE-15711 ..."
    
    print "Setting cmfuser to emcservice"
    cmfuser = "emcservice"
        
    print "Setting cmfpassword to ChangeMe"
    cmfpassword = "ChangeMe"
        
    dockerId = get_dockerId()
    #print "dockerId: ", dockerId
    
    # Disable CMF Key
    while int(time.time()) < (starttime + timeout):  # Retry (need to encapsulate into run_cmd())
        print "################################################"
        print "####    Disable REPO GC                     ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.repo.enabled", "false", dockerId, cmfuser, cmfpassword, "Disable before patch 15711")
        if not result:
            complete_flag = False
        
        print "################################################"
        print "####    Disable REPO GC Verification        ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.repo.verification.enabled", "false", dockerId, cmfuser, cmfpassword, "Disable before patch 15711")
        if not result:
            complete_flag = False
            
        print "################################################"
        print "####    Disable BTREE GC                    ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.btree.enabled", "false", dockerId, cmfuser, cmfpassword, "Disable before patch 15711")
        if not result:
            complete_flag = False
            
        print "################################################"
        print "####    Disable BTREE GC Verification       ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.btree.scanner.verification.enabled", "false", dockerId, cmfuser, cmfpassword, "Disable before patch 15711")
        if not result:
            complete_flag = False
            
        print "################################################"
        print "####    Disable BTREE Partial GC            ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.btree.scanner.copy.enabled", "false", dockerId, cmfuser, cmfpassword, "Disable before patch 15711")
        if not result:
            complete_flag = False
            
        if complete_flag:
            print "################################################"
            print "####                Done                    ####"
            print "################################################\n"
            break # exit
        
        time.sleep(retry_delay)
    
    if not complete_flag:
        common.print_failed()
        common.err_output("ERROR:  Could not disable all REPO/BTREE GC/GC verification successfully\n")
        exit(2)

def clear_cmf_cache():
    print "Clearing cmf cache before apply the patch to the system ..."
    cmd = "mv /data/dynamicconfig/* /tmp/"
    result = common.run_multi_cmd(cmd, Container=True)
    
    ip_list = common.machines
    for ip in ip_list:
        if result[ip]['stderr']:
            print "clear cmf cache error on Node: ", ip
            exit(3)
        
    print "Clear cmf cache complete\n"

def generate_machines_file():
    ip_list = common.machines
    file_path = "/home/admin/MACHINES"
    
    for ip in ip_list:
        with open(file_path, "w") as f:
            f.write(ip)
        
    
def install_patch():
    machines_path = "/home/admin/MACHINES"
    if not os.path.exists(machines_path):
        generate_machines_file()
        
    cmd = "./svc_patch /home/admin/MACHINES -installed"
    return_value = subprocess.call(cmd, shell=True)
    if return_value != 0:
        print "Install patch not success"
        exit(4)
    
    print "=========\n"
    
# need test this again (have add NoExit=True to bypass the exit 1 problem)
def checkKey1(key, value, dockerId, cmfuser, cmfpassword):
    #cmd = "sudo docker exec -it %s /opt/storageos/tools/cf_client --list --name %s --user %s --password %s | grep -s configured_value" %(dockerId, key, cmfuser, cmfpassword)
    cmd = "sudo docker exec -it {} /opt/storageos/tools/cf_client --list --name {} --user {} --password {} | grep -s configured_value".format(dockerId, key, cmfuser, cmfpassword)
    result = common.run_cmd(cmd, noErrorHandling=True)
    if result['retval'] > 0:
        config_value = NULL
    else:
        config_value = result['stdout']
    
    #cmd = "sudo docker exec -it %s /opt/storageos/tools/cf_client --list --name %s --user %s --password %s | grep -s default_value" %(dockerId, key, cmfuser, cmfpassword)
    cmd = "sudo docker exec -it {} /opt/storageos/tools/cf_client --list --name {} --user {} --password {} | grep -s default_value".format(dockerId, key, cmfuser, cmfpassword)
    result = common.run_cmd(cmd, noErrorHandling=True)
    default_value = result['stdout']
    
    if len(config_value) > 0:
        if value in config_value:
            print "# CMF key {} is set to {} as expected".format(key, value)
            return True
        else:
            print "# CMF key {} is not set to {}, no need to do cleanup with LV2 btree GC enabled".format(key, value)
            return False
    else:
        # There are no configured value, check default value
        if len(default_value) > 0:
            if value in default_value:
                print "# CMF key {} has been updated as expected".format(key)
                return True
            else:
                print "# CMF key {} not exist or default value not to be false, can not cleanup with this key disabled.".format(key)
                print "# Check if CMF cache has been cleaned up and vnest has been restarted after applied patch"
                return False

def checkKey(key, value, dockerId, cmfuser, cmfpassword):
    cmd = "sudo docker exec -it {} /opt/storageos/tools/cf_client --list --name {} --user {} --password {}".format(dockerId, key, cmfuser, cmfpassword)
    result = common.run_cmd(cmd)

    cmd_output = result['stdout']
    
    configured_value_match = re.search(r'"configured_value": "(\w+)"', cmd_output)
    default_value_match = re.search(r'"default_value": "(\w+)"', cmd_output)
    
    if configured_value_match:
        config_value = configured_value_match.group(1)
    else:
        config_value = ''
        
    if default_value_match:
        default_value = default_value_match.group(1)
    else:
        default_value = ''
        
    if len(config_value) > 0:
        if value in config_value:
            print "# CMF key {} is set to {} as expected".format(key, value)
            return True
        else:
            print "# CMF key {} is not set to {}, no need to do cleanup with LV2 btree GC enabled".format(key, value)
            return False
    else:
        # There are no configured value, check default value
        if len(default_value) > 0:
            if value in default_value:
                print "# CMF key {} has been updated as expected".format(key)
                return True
            else:
                print "# CMF key {} not exist or default value not to be false, can not cleanup with this key disabled.".format(key)
                print "# Check if CMF cache has been cleaned up and vnest has been restarted after applied patch"
                return False
    
def cleanup_LV1_GC_verification_checkpoint():
    print "\n#################################################################"
    print "####   Cleanup LV1 GC verification checkpoint for OB table   ####"
    print "#################################################################"

    # Delete btree gc verification checkpoints of all OB tables:
    cmd = 'curl -s -f -X DELETE "http://{}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/OB/0"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "# Unable to complete BTREE GC verification checkpoint cleanup for OB tables, will try this script again"
        return False
    
    cmd = 'curl -s -f -X DELETE "http://{}:9101/triggerGcVerification/deleteAllCheckpoint/REPO/OB/0"'.format(ip_addr)
    result= common.run_cmd(cmd)
    if result['retval'] > 0:
        print "# Unable to complete REPO GC verification checkpoint cleanup for OB tables, will try this script again"
        return False
        
    # Verify delete result
    cmd = 'curl -f -s -L "http://{}:9101/diagnostic/PR/1/DumpAllKeys/CHUNK_REFERENCE_SCAN_PROGRESS?type=BTREE&dt="'.format(ip_addr)
    btree_result = common.run_cmd(cmd)
    if btree_result['retval'] > 0:
        print "# Unable to validate LV1 BTREE GC verification checkpoint cleanup, will try this script again"
        return False
    
    cmd = 'curl -f -s -L "http://{}:9101/diagnostic/PR/1/DumpAllKeys/CHUNK_REFERENCE_SCAN_PROGRESS?type=REPO&dt="'.format(ip_addr)
    repo_result = common.run_cmd(cmd)
    if repo_result['retval'] > 0:
        print "# Unable to validate LV1 REPO GC verification checkpoint cleanup, will try this script again"
        return False
        
    btree_match = re.search(r'schemaType.+_OB_.+', btree_result['stdout'])
    repo_match = re.search(r'schemaType.+_OB_.+', repo_result['stdout'])
    if btree_match or repo_match:
        print "# Cleanup LV1 BTREE GC verification checkpoints failed, will continue since this step is optional."
        return False
    else:
        print "# Cleanup LV1 BTREE GC verification checkpoints successfully\n"
        return True

def remove_btree_gc_verification_tasks():
    print "\n###############################################"
    print "####   Cleanup LV1 GC verification tasks   ####"
    print "###############################################"
    
    # Remove all btree gc verification tasks which are rg-cos scope.
    # Clean up LV1 BTREE GC task status
    #cmd = 'curl -s -L "http://%s:9101/diagnostic/CT/1" | xmllint --format - | grep "<id>" | awk -F \'<|>\' \'{print $3}\'' % (ip_addr)
    cmd = 'curl -s -L "http://{}:9101/diagnostic/CT/1" | xmllint --format - | grep "<id>"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "Dump CT failed"
        return False
        
    ct_list = result['stdout'].split('\n')
    #print "ct_list: ", ct_list
    for item in ct_list:
        match = re.search(r'<.+>(.+)<.+>', item)
        if match:
            ctId = match.group(1)
            
        if ctId:
            print "Cleanup LV1 BTREE GC task for table ", ctId
            cmd = 'curl -f -s -X DELETE -L "http://{}:9101/triggerGcVerification/clearTasksOfCT/BTREE/{}/true"'.format(ip_addr, ctId)
            result = common.run_cmd(cmd)
            if result['retval'] > 0:
                print "Unable to delete LV1 BTREE GC task for CT ", ctId
                return False
            
            cmd = 'curl -f -s -X DELETE -L "http://{}:9101/triggerGcVerification/clearTasksOfCT/BTREE/{}/false"'.format(ip_addr, ctId)
            result = common.run_cmd(cmd)
            if result['retval'] > 0:
                print "Unable to delete LV1 BTREE GC task for CT ", ctId
                return False
                
    for item in ct_list:
        match = re.search(r'<.+>(.+)<.+>', item)
        if match:
            ctId = match.group(1)
            
        if ctId:
            print "Cleanup LV1 REPO GC task for table ", ctId
            cmd = 'curl -f -s -X DELETE -L "http://{}:9101/triggerGcVerification/clearTasksOfCT/REPO/{}/true"'.format(ip_addr, ctId)
            result = common.run_cmd(cmd)
            if result['retval'] > 0:
                print "Unable to delete LV1 REPO GC task for CT ", ctId
                return False
                
            cmd = 'curl -f -s -X DELETE -L "http://{}:9101/triggerGcVerification/clearTasksOfCT/REPO/{}/false"'.format(ip_addr, ctId)
            result = common.run_cmd(cmd)
            if result['retval'] > 0:
                print "Unable to delete LV1 REPO GC task for CT ", ctId
                return False

    cmd = 'curl -f -s -L "http://{}:9101/diagnostic/CT/1/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "# Unable to validate LV1 GC verification checkpoint cleanup, will try the script again"
        return False
        
    if "schema" in result['stdout']:
        print "# Cleanup LV1 CHUNK_GC_SCAN_STATUS_TASK failed, will try this script again"
        return False
    else:
        print "# Cleanup LV1 CHUNK_GC_SCAN_STATUS_TASK successfully\n"
        return True

def post_15711():
    timeout = 60 * 20
    retry_delay = 30
    complete_flag = True
    starttime = int(time.time())
    
    print "Post patch step for STORAGE-15711 ..."
    
    print "Setting cmfuser to emcservice"
    cmfuser = "emcservice"
        
    print "Setting cmfpassword to ChangeMe"
    cmfpassword = "ChangeMe"
    
    dockerId = get_dockerId()
    
    print "######################################################"
    print "####         Checking GC disabled                 ####"
    print "######################################################\n"
    checkKey("com.emc.ecs.chunk.gc.repo.enabled", "false", dockerId, cmfuser, cmfpassword)
    checkKey("com.emc.ecs.chunk.gc.repo.verification.enabled", "false", dockerId, cmfuser, cmfpassword)
    checkKey("com.emc.ecs.chunk.gc.btree.enabled", "false", dockerId, cmfuser, cmfpassword)
    checkKey("com.emc.ecs.chunk.gc.btree.scanner.verification.enabled", "false", dockerId, cmfuser, cmfpassword)
    checkKey("com.emc.ecs.chunk.gc.btree.scanner.copy.enabled", "false", dockerId, cmfuser, cmfpassword)
    
    while int(time.time()) < (starttime + timeout):  # Retry (need to encapsulate into run_cmd())     
        result = cleanup_LV1_GC_verification_checkpoint()
        if not result:
            complete_flag = False
            
        result = remove_btree_gc_verification_tasks()
        if not result:
            complete_flag = False
            
        print "##################################"
        print "####   Enable REPO GC         ####"
        print "##################################"
        result = setKey("com.emc.ecs.chunk.gc.repo.enabled", "true", dockerId, cmfuser, cmfpassword, "Enable after patch 15711")
        if not result:
            complete_flag = False
        
        print "###############################################"
        print "####   Enable REPO GC Verification         ####"
        print "###############################################"
        result = setKey("com.emc.ecs.chunk.gc.repo.verification.enabled", "true", dockerId, cmfuser, cmfpassword, "Enable after patch 15711")
        if not result:
            complete_flag = False
        
        print "################################################"
        print "####    Enable LV1  BTREE GC Verification   ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.btree.scanner.verification.enabled", "true", dockerId, cmfuser, cmfpassword, "Enable after patch 15711")
        if not result:
            complete_flag = False
        
        print "################################################"
        print "####    Enable LV1 BTREE partial GC         ####"
        print "################################################"
        result = setKey("com.emc.ecs.chunk.gc.btree.scanner.copy.enabled", "true", dockerId, cmfuser, cmfpassword, "Enable after patch 15711")
        if not result:
            complete_flag = False
            
        if complete_flag:
            print "################################################"
            print "####                Done                    ####"
            print "################################################\n"
            break # exit
        
        time.sleep(retry_delay)
        
    if not complete_flag:
        common.print_failed()
        common.err_output("ERROR:  post-15711 steps failed.\n")
        exit(6)

# schemaType DIRECTORYTABLE_RECORD type BPLUSTREE_BOOTSTRAP_MARKER dtId urn:storageos:OwnershipInfo:6f512276-d493-49a4-8b75-53b3ae7df2e2_5ac5abc2-c74a-4967-a5b6-81004de196fb_LS_37_128_0: zone urn:storageos:VirtualDataCenterData:eb8945d7-3c1c-474b-99f1-36e4f9ffca88 dstZone urn:storageos:VirtualDataCenterData:f72e5bf0-63d0-4d68-a2df-d363ddcb970c        
def cleanup_marker():
    notDoneTasks = 0
    doneTasks = 0
    
    cmd = 'curl -f -s -L http://{}:9101/diagnostic/PR/1/DumpAllKeys/DTBOOTSTRAP_TASK'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "could not get bootstrap tasks list"
        return False
        
    boot_task_output = result['stdout'].split('\r\n')
    boot_task_keys = []
    boot_task_done_keys = []
    
    for line in boot_task_output:
        if 'schema' in line:
            boot_task_keys.append(line)
    
    for key in boot_task_keys:
        if 'type Done' in key:
            boot_task_done_keys.append(key)
    
    doneTasks = len(boot_task_done_keys)
    nonDoneTasks = len(boot_task_keys) - doneTasks
    if nonDoneTasks > 0:
        print "bootstrap is in progress with {} - skipping this step".format(nonDoneTasks)
        return True
    else:
        print "no bootstrap is in progress"
    
    if doneTasks == 0:
        print "no bootstrap tasks"
        return True
        
    print "checking for any possible lingering markers"
    print "......"
    get_bootstrap_marker = []
    for key in boot_task_done_keys:
        contents = key.split()
        dtId = contents[11]
        zone = contents[13]
        dstZone = contents[9]
        
        cmd = 'curl -s -L "http://{}:9101/diagnostic/PR/1/DumpAllKeys/DIRECTORYTABLE_RECORD?type=BPLUSTREE_BOOTSTRAP_MARKER&dtId={}&zone={}&dstZone={}"'.format(ip_addr, dtId, zone, dstZone)
        get_bootstrap_marker.append(cmd)
        
    # run each command in get_bootstrap_marker
    invalid_marker_list = []
    for cmd in get_bootstrap_marker:
        result = common.run_cmd(cmd)
        markers = re.findall(r'schema.+\S', result['stdout'], re.IGNORECASE)
        for marker in markers:
            invalid_marker_list.append(marker)
            
    lingeringMarkers = len(invalid_marker_list)
    if lingeringMarkers == 0:
        print "# No lingering bootstrap markers"
    else:
        print "found {} possible lingering bootstrap markers".format(lingeringMarkers)
        removedMarkers = 0
        marker_contents = []
        for marker in invalid_marker_list:
            marker_contents = marker.split()
            if len(marker_contents) != 10:
                print "cannot parse marker ", marker
            else:
                dtId = marker_contents[5]
                match = re.search(r'(.+?)_(.+)', dtId)
                cosBase = match.group(1)
                rgName = match.group(2)
                cosBase_items = cosBase.split(':')
                
                cos = "{}:{}:VirtualArray:{}".format(cosBase_items[0], cosBase_items[1], cosBase_items[3])
                rg = "{}:{}:ReplicationGroupInfo:{}:global".format(cosBase_items[0], cosBase_items[1], rgName)
                
                cmd = 'curl -f -X PUT -H x-emc-rg:{} -H x-emc-vpool:{} -H x-emc-directory-id:{} -H x-emc-remote-zone:{} http://{}:9101/bootstrap/remove_bootstrap_marker'.format(rg, cos, dtId, marker_contents[9], ip_addr)
                #print "remove cmd: ", cmd
                result = common.run_cmd(cmd)
                if result['retval'] > 0:
                    print "remove lingering bootstrap marker {} failed".format(marker)
                else:
                    removedMarkers += 1
                    
        print "# Removed {} of {} possible lingering markers".format(removedMarkers, lingeringMarkers)
        if removedMarkers < lingeringMarkers:
            print "# Not Removing all lingering markers"
            return False
    
    return True
    
def post_HF1_general_patch():
    timeout = 60 * 20
    retry_delay = 60
    complete_flag = True
    starttime = int(time.time())
    
    print "Post-patch actions to cleanup lingering bootstrap marker and enable LV1 BTREE GC ..."
    
    print "Setting cmfuser to emcservice"
    cmfuser = "emcservice"
        
    print "Setting cmfpassword to ChangeMe"
    cmfpassword = "ChangeMe"
    
    dockerId = get_dockerId()
    
    print "##############################################"
    print "####   Cleanup lingering bootstrap marker ####"
    print "##############################################"

    while int(time.time()) < (starttime + timeout):  # Retry (need to encapsulate into run_cmd())
        result = cleanup_marker()
        if not result:
            print "# Cleanup lingering markers failed, will run the script again to make sure all lingering markers are removed"
            print "# For more information, please refer to https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets"
            complete_flag = False

        # Enable LV1 BTREE GC
        print "##################################"
        print "####   Enable LV1 BTREE GC    ####"
        print "##################################"
        result = setKey("com.emc.ecs.chunk.gc.btree.enabled", "true", dockerId, cmfuser, cmfpassword, "Enable after patch 3.0 HF1 General Patch")
        if not result:
            complete_flag = False
                
        if complete_flag:
            print "################################################"
            print "####                Done                    ####"
            print "################################################\n"
            break # exit
        
        time.sleep(retry_delay)
        
    if not complete_flag:
        common.print_failed()
        common.err_output("ERROR: post-patch steps failed.\n")
        exit(7)

def cleanup_LV2_GC_verification_checkpoint():
    print "############################################################"
    print "####   Cleanup LV2 BTREE GC verification checkpoints    ####"
    print "############################################################"
    cmd = 'curl -s -f -X DELETE "http://{}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/CT/1"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "cleanup CT BTREE GC verification checkpoints failed"
        return False
    cmd = 'curl -s -f -X DELETE "http://{}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/PR/1"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "cleanup PR BTREE GC verification checkpoints failed"
        return False
    cmd = 'curl -s -f -X DELETE "http://{}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/SS/1"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "cleanup SS BTREE GC verification checkpoints failed"
        return False
    cmd = 'curl -s -f -X DELETE "http://{}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/BR/1"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "cleanup BR BTREE GC verification checkpoints failed"
        return False
        
    # Verify delete result
    cmd = 'curl -f -s -L "http://{}:9101/diagnostic/PR/2/DumpAllKeys/CHUNK_REFERENCE_SCAN_PROGRESS?type=BTREE&dt="'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "# Unable to validate LV2 BTREE GC verification checkpoint cleanup, will continue since this step is optional"
        print "# Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to verify if cleanup is done"
    
    if 'schemaType' in result['stdout']:
        print "# Cleanup LV2 BTREE GC verification checkpoints failed, will continue since this step is optional."
        print "# Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to do cleanup manually if necessary"
    else:
        print "# Cleanup LV2 BTREE GC verification checkpoints successfully"
        
    return True
    
def cleanup_LV2_GC_task():
    print "#####################################################"
    print "####   Cleanup LV2 BTREE GC verification tasks   ####"
    print "#####################################################"
    
    cmd = 'curl -s -L "http://{}:9101/diagnostic/CT/2" | xmllint --format - | grep "<id>"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "Dump CT failed"
        return False

    ct_list = result['stdout'].split('\n')
    for item in ct_list:
        match = re.search(r'<.+>(.+)<.+>', item)
        if match:
            ctId = match.group(1)

        if ctId:
            print "Cleanup LV2 BTREE GC task for table ", ctId
            cmd = 'curl -f -s -X DELETE -L "http://{}:9101/triggerGcVerification/clearTasksOfCT/BTREE/{}/false"'.format(ip_addr, ctId)
            result = common.run_cmd(cmd)
            if result['retval'] > 0:
                print "Unable to delete LV2 BTREE GC task for CT ", ctId
                return False

    cmd = 'curl -f -s -L "http://{}:9101/diagnostic/CT/2/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK"'.format(ip_addr)
    result = common.run_cmd(cmd)
    if result['retval'] > 0:
        print "# Unable to validate LV2 BTREE GC verification checkpoint cleanup, will continue since this step is optional"
        print " Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to verify if cleanup is done"
        
    if "schema" in result['stdout']:
        print "# Cleanup LV2 CHUNK_GC_SCAN_STATUS_TASK failed, will continue since this step is optional"
        print "# Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to do cleanup manually if necessary"
    else:
        print "# Cleanup LV2 CHUNK_GC_SCAN_STATUS_TASK successfully"
        
    return True

def cleanup_LV2_BTREE_GC():
    timeout = 60 * 20
    retry_delay = 60
    complete_flag = True
    starttime = int(time.time())
    
    print "Cleanup LV2 BTREE GC ..."
    
    print "Setting cmfuser to emcservice"
    cmfuser = "emcservice"
        
    print "Setting cmfpassword to ChangeMe"
    cmfpassword = "ChangeMe"
    
    dockerId = get_dockerId()
    
    while int(time.time()) < (starttime + timeout):  # Retry (need to encapsulate into run_cmd())     
        # Verify if com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled has been updated and set to false
        print "######################################################"
        print "####         Checking LV2 BTREE GC disabled       ####"
        print "######################################################"
        #pdb.set_trace()
        result = checkKey("com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled", "false", dockerId, cmfuser, cmfpassword)
        if not result:
            complete_flag = False
        
        # Verify if com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled has been updated
        print "###################################################################"
        print "####         Checking LV2 BTREE GC verification disabled       ####"
        print "###################################################################"
        result = checkKey("com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled", "false", dockerId, cmfuser, cmfpassword)
        if not result:
            complete_flag = False
            
        # Clean up LV2 BTREE GC verification checkpoints
        result = cleanup_LV2_GC_verification_checkpoint()
        if not result:
            complete_flag = False        

        # Clean up LV2 BTREE GC task status
        result = cleanup_LV2_GC_task()
        if not result:
            complete_flag = False
        
        if complete_flag:
            print "################################################"
            print "####                Done                    ####"
            print "################################################\n"
            break # exit
        
        time.sleep(retry_delay)
        
    if not complete_flag:
        common.print_failed()
        common.err_output("ERROR:  cleanup_LV2_BTREE_GC failed.\n")
        exit(8)


def get_host_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    finally:
        s.close()

    return ip
  
def parse_args():
    options = """
        Usage:  $SCRIPTNAME [-h] [--debug] [--ip ipaddr] [--ignore_15711]
        
        Options:
        \t-h: Help              - This help screen
        \t--debug: Debug        - Produces additional debugging output
        \t--ip:                 - used when customer using network separation to specify data ip
        \t--ignore_15711        - Not do disable/enable REPO/BTREE GC/GC verification before and after patch install
        """
    
    try:
        opts, args = getopt.getopt(sys.argv[1:], "h", ["debug","ip=","threads="])
    except getopt.GetoptError as err:
        # print help information and exit
        print (err)
        print options
        sys.exit(2)
      
    for opt, arg in opts:
        if opt == '-h':
            print options
            sys.exit(0)
        if opt == '--debug':
            global debug
            debug = True
        if opt == '--ip':
            global ip_addr
            ip_addr = arg
        if opt == '--ignore_15711':
            global ignore_15711
            ignore_15711 = True
        
        if not opts or '' in opts:
            print options
            sys.exit(0)
      
def main():
    global ip_addr
    ip_addr = get_host_ip()
    
    parse_args()
    
    print "dtquery ip is: ", ip_addr
    
    print "======= Starting 3.0 HF1 General Patch Steps for BTREE GC tickets =======\n"
    #common.check_dt_ready()
    
    # Pre patch steps
    disable_BTREE_GC()
    
    if not ignore_15711:
        pre_15711()
    else:
        print "Skip pre patch step for STORAGE-15711\n"
        
    clear_cmf_cache()
    
    # Install patch
    #install_patch()
    
    # Post patch steps
    if not ignore_15711:
        post_15711()
    else:
        print "Skip post patch step for STORAGE-15711\n"

    post_HF1_general_patch()
    
    cleanup_LV2_BTREE_GC()
    
    # the end
    print time.time() - start_time, "seconds"

if __name__ == '__main__':
    main()
