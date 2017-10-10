#!/usr/bin/python
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
# Script to check Repo Scan speed
# Author: Julius Zhu
#
# 0.1 - Initial version
# 
#
#
##########################################################################



import time
import datetime
import commands

VERSION = "0.1"
CHECK_DAYS = 2
TIMESTAMP_TAIL_COUNT = 3

def get_all_scan_end():
    
    print "Collecting lastest %d repo scan end timestamp in last %d days log..." %(TIMESTAMP_TAIL_COUNT, CHECK_DAYS)
    print ""
    
    log_to_scan = " /var/log/blobsvc-chunk-reclaim.log "

    today = time.strftime("%Y%m%d")

    for i in range(0, CHECK_DAYS):
        delta_time = datetime.datetime.now() + datetime.timedelta(days=-i)
        suffix = delta_time.strftime("%Y%m%d")
        log_to_scan = " /var/log/blobsvc-chunk-reclaim.log." + suffix + "* " + log_to_scan
        
    
    cmd = "viprexec -c \"zgrep REPO.*OB_.*_128.*persisting.*results %s \" | grep \"persisting results\" > /tmp/scan_end.tmp" % log_to_scan

    status, output = commands.getstatusoutput(cmd)


def get_all_obs():
    obs = []
    cmd = "curl -s http://`hostname`:9101/diagnostic/OB/0/ | xmllint --format - | grep table_detail_link | awk -F \"[<|>|?]\" '{print $3}'"
    status, output = commands.getstatusoutput(cmd)
    if status != 0:
        return None

    for link in output.split("\n"):
        obs.append(link.split("/")[3].split(":")[3].split("_", 1)[1])

    return obs
    

def get_scan_last_timestamp(obs):
    for ob in obs:
        result = "%50s " % ob
        cmd = "grep %s /tmp/scan_end.tmp | tail -3 " % ob
        status, output = commands.getstatusoutput(cmd)
        if status == 0:
            for entry in output.split("\n"):
                if len(entry.strip()) == 0:
                    continue
                timestamp = entry.split(":")[1]
                result += " %20s " % timestamp
        print result

def main():

    print ""
    print "checkRepoScanSpeed.py version %s" % VERSION
    print "" 

    obs = get_all_obs()
    get_all_scan_end()
    get_scan_last_timestamp(obs)

if __name__ == "__main__":
    main()
