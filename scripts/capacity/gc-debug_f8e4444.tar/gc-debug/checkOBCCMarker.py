#!/bin/sh
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
# Script to check all OB CC marker in current zone
# Author: Julius Zhu
#
# 0.1 - Initial version
# 0.2 - Better output format
#       Highlight delayed CC marker by defined threshold
# 0.3 - Support querying for single OB
# 0.4 - Support verbose info on OB CC marker
#
##########################################################################

import commands
import xml.etree.ElementTree as ET
import argparse

version = "0.4"

highlight_threshold = 80

remote_zones = []

results = []

def get_all_ob_links(ob):
    cmd = "curl -s http://`hostname`:9101/diagnostic/OB/0/ | xmllint --format - | grep table_detail_link | awk -F \"[<|>|?]\" '{print $3}'"
    if ob != None:
        cmd += " | grep %s " % ob
    status, output = commands.getstatusoutput(cmd)
    if status != 0:
        return None

    ob_link_list = output.split("\n")
    return ob_link_list


def get_ob_cc_marker(ob_link, verbose):
    
    cmd = "curl -s %s | xmllint --format - " % ob_link.replace("urn", "gc/obCcMarker/urn")
    status, output = commands.getstatusoutput(cmd)
    if status != 0:
        return None

    ob = ob_link.split("/")[3].split(":")[3].split("_", 1)[1]

    root = ET.fromstring(output)

    ob_result = {"ob": ob,
                 "local_jr": ""}

    print_head = False
    
    for entry in root:
        is_local = False
        zone = ""
        max_jr = ""
        cc_jr = ""
        cc_bt = ""
        max_bt = ""
        max_bt_jr = ""
        for child in entry:
            if child.tag == "local_zone_id":
                is_local = True
                zone = child.text.split(":")[-1]
            elif child.tag.find("remote_zone_id") != -1:
                zone = child.text.split(":")[-1]
            elif child.tag == "journal_entry":
                cc_jr = child.text.split("major")[1].split("minor")[0].strip().lstrip("0")
            elif child.tag == "max_journal_entry":
                max_jr = child.text.split("major")[1].split("minor")[0].strip().lstrip("0")
            elif child.tag == "btree_info":
                cc_bt = child.text.split("major")[1].split("minor")[0].strip().lstrip("0")
            elif child.tag == "latest_btree_info":
                max_bt = child.text.split("major")[1].split("minor")[0].strip().lstrip("0")
            elif child.tag == "latest_btree_journal_entry":
                max_bt_jr = child.text.split("major")[1].split("minor")[0].strip().lstrip("0")
             
        if is_local:
            ob_result["local_jr"] = max_jr
            ob_result["local_zone"] = zone
        else:
            if zone not in remote_zones:
                remote_zones.append(zone)
                print_head = True
            remote_result = {"CC_JR": cc_jr,
                             "MAX_JR": max_jr,
                             "CC_BT": cc_bt,
                             "MAX_BT": max_bt,
                             "MAX_BT_JR": max_bt_jr}
            ob_result[zone] = remote_result

    #    results.append(ob_result)
    if verbose:
        print_verbose_results(ob_result, print_head)
    else:
        print_results(ob_result, print_head)
         
def print_results(ob_result, print_head):
    
    if print_head:
        head = "%50s %20s" % ("OB", "LOCAL_MAX_JR")

        zone_id = 1
        print "LocalZone: %s" % ob_result["local_zone"]
        for zone in remote_zones:
            head += " %20s " % ("RemoteZone%d" % zone_id)
            print "RemoteZone%d: %s" % (zone_id, zone)
            zone_id += 1

        print
        print head
        print
    
    body = "%50s %20s" % (ob_result["ob"], ob_result["local_jr"])
    for zone in remote_zones:
        try:
            cc_marker_percent = int(ob_result[zone]['CC_JR'], 16) * 100 / int(ob_result["local_jr"], 16)
        except Exception:
            body += " %20s " % "N/A"
            continue
        
        cc_marker = "%s (%d%%)" % (ob_result[zone]['CC_JR'], cc_marker_percent)
        if cc_marker_percent < highlight_threshold:
            body += " \33[31m%20s\33[0m " % cc_marker
        else:
            body += " %20s " % cc_marker

    print body

def print_verbose_results(ob_result, print_head):
    
    if print_head:
        head = "%50s %20s" % ("OB", "LOCAL_MAX_JR")

        zone_id = 1
        print "LocalZone: %s" % ob_result["local_zone"]
        head += " %10s " % " "
        for zone in remote_zones:
            head += " %20s " % ("RemoteZone%d" % zone_id)
            print "RemoteZone%d: %s" % (zone_id, zone)
            zone_id += 1

        print
        print head
        print
    
    body = "%50s %20s" % (ob_result["ob"], ob_result["local_jr"])

    body += " %10s " % "CC_JR"
    for zone in remote_zones:
        try:
            cc_marker_percent = int(ob_result[zone]['CC_JR'], 16) * 100 / int(ob_result["local_jr"], 16)
        except Exception:
            body += " %20s " % "N/A"
            continue
        
        cc_marker = "%s (%d%%)" % (ob_result[zone]['CC_JR'], cc_marker_percent)
        if cc_marker_percent < highlight_threshold:
            body += " \33[31m%20s\33[0m " % cc_marker
        else:
            body += " %20s " % cc_marker
    body += "\n"

    body += "%50s %20s" % (" ", " ")
    body += " %10s " % "MAX_JR"
    for zone in remote_zones:
        max_jr = "%s" % ob_result[zone]['MAX_JR']
        body += " %20s " % max_jr
    body += "\n"

    body += "%50s %20s" % (" ", " ")
    body += " %10s " % "CC_BT"
    for zone in remote_zones:
        cc_bt = "%s" % ob_result[zone]['CC_BT']
        body += " %20s " % cc_bt
    body += "\n"

    body += "%50s %20s" % (" ", " ")
    body += " %10s " % "MAX_BT"
    for zone in remote_zones:
        max_bt = "%s" % ob_result[zone]['MAX_BT']
        body += " %20s " % max_bt
    body += "\n"

    body += "%50s %20s" % (" ", " ")
    body += " %10s " % "MAX_BT_JR"
    for zone in remote_zones:
        max_bt_jr = "%s" % ob_result[zone]['MAX_BT_JR']
        body += " %20s " % max_bt_jr
    body += "\n"

    print body



def main():
    print
    print "checkOBCCMarker  version %s" % version
    print

    parser = argparse.ArgumentParser(description="Check OB CC markers")
    parser.add_argument('--ob', dest='ob', action='store', default=None, help="Specify a single OB to check")
    parser.add_argument('-v', dest='verbose', action='store_true', default=False, help="Verbose info for OB CC Marker")
    args = parser.parse_args()
    
    for ob_link in get_all_ob_links(args.ob):
        get_ob_cc_marker(ob_link, args.verbose)
    # print_results()


if __name__ == "__main__":
    main()
 
