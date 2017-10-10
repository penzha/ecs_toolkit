#!/usr/bin/python


# Check to ensure the process is being run on the installer node


import subprocess
import sys
import os
import getopt

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common
from svc_upgrade_common import *


verbose=0


def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help       Show this help message and exit"
	print "-v, --verbose     Enable verbose output"
	print "-V, --veryverbose Enable very verbose output"
	print "-l, --log         Log output to upgrade log"

	exit (1)

def parse_args(argv):

	result=parse_global_args(argv, req_version=True, req_upgradeType=True)


	if result is "usage":
		usage()



# Main logic

parse_args(sys.argv[1:])


# Perform 3 different checks to validate that the current node is the installer node:

# - Should be the first node.  Private rack IP should be 192.168.219.1
# - Installer RPM should be installed
# - Checks that the appropriate fabric services are running





# Check for the installer RPM on this node.
# Expects output that looks like:

# admin@sc-ecs-u300-prd-001:~>rpm -qv "installer"
# installer-1.2.1.0-2666.cd44731.x86_64
# 192.168.219.3:  package installer is not installed
# 192.168.219.4:  package installer is not installed

msg_output("Checking for installer service on this node", req_loglevel=1, indent=1)

cmd="rpm -qv installer"
output=run_cmd(cmd)

installer_package=output['stdout']


if not installer_package.startswith("installer-"):
	err_output("ERROR: Installer package not installed")
	err_output("")
	err_output("Either this isn't the installer node, installer package is incorrectly")
	err_output("  installed, or unable to list installed packages properly.")
	err_output("EXITING...")

	exit (100)




### XXX - need to decide how we're going to determine interface addresses.
# For IP check need a function to tell me what the private interface IP is


# Query fabric agent health property on each node.
# Expects output that looks like:

# Output from host : 192.168.219.1
#      "role": "zookeeper"
#      "role": "main"
#      "role": "lifecycle"
#      "role": "registry"
#
# Output from host : 192.168.219.2
#      "role": "zookeeper"
#      "role": "main"
#      "role": "lifecycle"
#
# Output from host : 192.168.219.3
#      "role": "zookeeper"
#      "role": "main"
#      "role": "lifecycle"
#
# Output from host : 192.168.219.4
#      "role": "main"

msg_output("Checking for fabric services on current node", req_loglevel=1, indent=1)

cmd="sudo /opt/emc/caspian/fabric/cli/bin/fcli agent service.list | grep role | awk '{ print $2 }'"

output=run_cmd(cmd)

running_fabric_services=output['stdout']

if not running_fabric_services:
	err_output("ERROR: Could not determine list of fabric service(s)\n\n")
	err_output("")
	err_output("Either no fabric services are running, or an unexpected error\n")
	err_output("  occurred while listing them.")
	err_output("EXITING...\n")

	exit (101)


for service in ["zookeeper", "main", "lifecycle", "registry"]:
	msg_output("Checking for running service: '"+service+"'", req_loglevel=1, indent=1)
	if running_fabric_services.find(service) is -1:  # service string not found in output
		err_output("ERROR: Installer node service(s) not running")
		err_output("")
		err_output("The service '"+service+"' does not appear to be running.")
		err_output("Either this is not the installer node, or all services are")
		err_output("not running.")
		err_output("EXITING...")

		exit (102)


print "OK"





