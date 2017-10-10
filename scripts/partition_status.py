#!/usr/bin/env python
# __CR__
# Copyright (c) 2008-2017 DellEMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of DellEMC Corporation
# or is licensed to DellEMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of DellEMC.
# __CR__

"""
Primary Author: Suraj Prabhu (ECS Escalation Engineering)
Purpose: check disk/partition status in fabric and SSM
Usage: python %prog --help
Version: 1.0
Prerequisite : None
Input/Output restriction: Input is a single node ip or MACHINES file with system node ips
Script compatible with ECS 3.1 code where device is the node id and not the node ip.
Changelog:
    1.0 [Aug 16, 2017] - Initial Version Ready for Release
"""

import StringIO
import argparse
import subprocess
import json
import sys


cmd_get_object_version = '''sudo -i xdoctor -x | grep Object'''
cmd_get_node_id = '''/opt/emc/caspian/fabric/cli/bin/fcli agent node.id | grep id'''
cmd_get_fabric_disks = '''/opt/emc/caspian/fabric/cli/bin/fcli agent disk.disks'''
cmd_list_uuid_from_fabric = '''/opt/emc/caspian/fabric/cli/bin/fcli agent disk.disks | grep uuid | grep -v mount_path'''
cmd_check_partition_from_ss = '''curl "http://{}:9101/diagnostic/SS/{}/DumpAllKeys/SSTABLE_KEY?type=PARTITION&\
device={}&partition={}&showvalue=gpb" -s | grep -B1 schemaType | grep -v schemaType'''
cmd_get_dtquery_ip = '''netstat -ln | grep ':9101' | grep LISTEN | head -1'''


version = "v1.0"


def valid_ip(ip):
    return ip.count('.') == 3 and all(0 <= int(num) < 256 for num in ip.rstrip().split('.'))


def get_object_version(ip):
    pass
    result = runcommand(ip, cmd_get_object_version, "Failed to get object version from "
                                                    "xdoctor")[0].split()[2].split('.')
    obj_version = float(result[0]+"."+result[1])
    return obj_version


def runcommand(ip, command, err_message):
    ssh = subprocess.Popen(["ssh", "%s" % ip, command],
                           shell=False,
                           stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)
    result = ssh.stdout.readlines()
    if not result:
        error = ssh.stderr.readlines()
        if error:
            print >>sys.stderr, "ERROR: %s %s" % (ip, err_message)
            exit(1)
    return result


def get_partition_state_from_ss(ip, level, uuid, node_id=''):
    device_id = ip
    if '' != node_id:
        device_id = node_id
    url = runcommand(ip, cmd_check_partition_from_ss.format(ip, level, device_id, uuid), "Failed to get owner SS for "
                                                                                         "partition")
    if url:
        url_line = url[0].rstrip()
        if "<pre>" in url_line:
            url = url_line.rsplit("<pre>", 1)[1]
        else:
            url = url_line
        cmd_url = "curl -s \"{}\" | grep state".format(url)
        partition_state = runcommand(ip, cmd_url, "Failed to get partition state from SS")
        partition_state = partition_state[0].rstrip().split(' ')[1]
    else:
        partition_state = "NOT_FOUND"
    return partition_state


def get_partition_status(ip, use_node_id):
    result = runcommand(ip, cmd_list_uuid_from_fabric, "Failed to list the uuids from fabric")
    disks_list_length = len([i.split("\"")[3] for i in result])
    result = runcommand(ip, cmd_get_fabric_disks, "Failed to get disk status from fabric")
    f = StringIO.StringIO(''.join(result).rstrip())
    try:
        data = json.load(f)
    except ValueError:
        print "Decoding json has failed"
        exit(1)
    node_id = ''
    if use_node_id:
        node_id = runcommand(ip, cmd_get_node_id, "Failed to get node id")[0].split("\"")[3]
    dtquery_ip = runcommand(ip, cmd_get_dtquery_ip, "Failed to get dtquery ip")[0].split(":")[0].rsplit(' ', 1)[1]
    i = 0
    print ""
    print " {:^40} {:^47} {:^61}".format('-' * 40, '-' * 47, '-' * 61)
    print "|{:^40}|{:^47}|{:^61}|".format("Node : " + dtquery_ip, "Data from Fabric", "Data from SSM")
    print " {:<40} {:^10} {:^15} {:^20} {:^30} {:>30}".format('-' * 40, '-' * 10, '-' * 15, '-' * 20, '-' * 30,
                                                              '-' * 30)
    print "|{:^40}|{:^10}|{:^15}|{:^20}|{:^30}|{:^30}|".format("PARTITION", "Health", "Mount Status",
                                                               "Operational Status", "SS Level1", "SS Level2")
    print " {:<40} {:^10} {:^15} {:^20} {:^30} {:>30}".format('-' * 40, '-' * 10, '-' * 15, '-' * 20, '-' * 30,
                                                              '-' * 30)
    while i < disks_list_length:
        uuid = data["disks"][i]["uuid"]
        health = data["disks"][i]["health"]
        mount_status = data["disks"][i]["mount_status"]
        operational_status = data["disks"][i]["operational_status"]
        l1_state = get_partition_state_from_ss(dtquery_ip, 1, uuid, node_id)
        l2_state = get_partition_state_from_ss(dtquery_ip, 2, uuid, node_id)
        print "|{:^40}|{:^10}|{:^15}|{:^20}|{:^30}|{:^30}|".format(uuid, health, mount_status,
                                                                   operational_status, l1_state, l2_state)
        i = i + 1
    print " {:<40} {:^10} {:^15} {:^20} {:^30} {:>30}".format('-' * 40, '-' * 10, '-' * 15, '-' * 20, '-' * 30,
                                                              '-' * 30)


def print_help_and_exit_if_no_args_provided(parser):
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)


def main(args):
    use_node_id = 0
    if args.ipFile:
        count = 0
        for ip in open(args.ipFile):
            if valid_ip(ip.rstrip()):
                if count == 0 and get_object_version(ip) >= 3.1:
                    use_node_id = 1
                get_partition_status(ip.rstrip(), use_node_id)
            count = count + 1
    elif args.ip:
        if valid_ip(args.ip):
            if get_object_version(args.ip) >= 3.1:
                use_node_id = 1
            get_partition_status(args.ip, use_node_id)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-v", "--version", action='version', version='%(prog)s ' + version)
    parser.add_argument("-i", "--ip", type=str, help="Provide the node ip whose partitions are to be checked")
    parser.add_argument("-f", "--ipFile", type=str, help="Provide the machines file with ips of nodes whose "
                                                         "partitions are to be checked")
    print_help_and_exit_if_no_args_provided(parser)
    return parser.parse_args()


if __name__ == "__main__":
    main(parse_args())

