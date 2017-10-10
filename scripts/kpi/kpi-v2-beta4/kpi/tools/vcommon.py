#!/usr/bin/python
# __CR__
# Copyright (c) 2008-2014 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.
# __CR__


#

#
# author: Peter Vacca
# date:   10/01/2014
#

"""
common utility, for remote scp and ssh
"""
import commands
import fcntl
import os
import socket
import struct

DEFAULT = "MACHINES"
HOME_DEFAULT = os.path.join(os.environ['HOME'], DEFAULT)
VM_DEFAULT = "/opt/storageos/conf/data_nodes"
CONTAINER_NAME = ""
PRINT_RET_VAL = False
SERIAL = False
TIMEOUT = 15
RETRY_COUNT = 2
#OPT = "-q"
OPT = ""

def get_interface_ip(ifname):
    """ Determine the IP based on interface name
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    return socket.inet_ntoa(fcntl.ioctl(sock.fileno(), 0x8915, \
           struct.pack('256s', ifname[:15]))[20:24])

def which(program):
    """ Helper function to determine if program is on the system
    """
    status, _ = commands.getstatusoutput("which %s"%program)
    return status == 0

def read_hosts_file(fname):
    """ Create a list of host_names or ip's from the file
        The file should have one and only one hostname or ip per line
    """

    hosts_lst = []
    try:
        file_p = open(fname, 'r')
    except (IOError, os.error), msg:
        print msg
    else:
        for line in file_p:
            line = line.strip()
            if line.startswith("#") or line == "":
                continue
            else:
                hosts_lst.append(line)

    return hosts_lst

def remove_me(hosts):
    """ Filters out by private/public IP and hostname
    """
    filter_list = [socket.gethostname()]
    filter_list.append(get_interface_ip("private"))
    filter_list.append(get_interface_ip("public"))
    return [item for item in hosts if item not in filter_list]


def create_machines_file():
    """ Creates a MACHINE file in current working directory
    """
    cur_file = os.path.join(os.environ['HOME'], DEFAULT)
    if not os.path.isfile(cur_file):
        cmd = "/usr/sbin/getrackinfo -c %s" % cur_file
        status, _ = commands.getstatusoutput(cmd)
        if status == 0:
            print "Did not find a %s file so I made one with createrackinfo" \
                   % DEFAULT
            print "Created the file: %s" % cur_file
            print commands.getoutput("cat %s" % cur_file)

def is_vm():
    """ Determines if we are a VM
    """
    cmd = "dmidecode | grep -q 'VMware Virtual Platform'"
    status, _ = commands.getstatusoutput(cmd)
    return status == 0

def build_host_list(options):
    """ Function to generate the list of hosts to operate on
    """
    hosts = []
    def_file = HOME_DEFAULT

    if options.filename:
        hosts = read_hosts_file(options.filename)
    elif options.hosts:
        hosts = options.hosts.split(',')
    elif os.path.isfile(DEFAULT):
        hosts = read_hosts_file(DEFAULT)
    elif os.path.isfile(def_file):
        hosts = read_hosts_file(def_file)

    if not hosts:
        create_machines_file()
        return []

    if options.notme:
        hosts = remove_me(hosts)

    return hosts
