#!/usr/bin/python

# Check if compliance mode is enabled and save the info

# Exit codes:


import sys
import os
import getopt

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)

sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
from svc_upgrade_common import *


CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
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

	result=parse_global_args(argv)

	if result is "usage":
		usage()


# Main logic

parse_args(sys.argv[1:])


# Check if compliance is enabled in configuration:

cmd="grep 'security|compliance' /opt/emc/caspian/fabric/agent/conf/agent_customize.conf"
output=run_cmd(cmd, noErrorHandling=True)
if "compliance_enabled = true" in output['stdout']:
	# Compliance enabled in config, check if nodes are running:

	cmd="/opt/emc/caspian/fabric/cli/bin/fcli lifecycle cluster.compliance | grep compliance"
	newoutput=run_multi_cmd(cmd)

	for NODE, details in newoutput.viewitems():
		if "NON_COMPLIANT" in details['stdout']:
			err_output("Compliance is configured, but node "+NODE+" does not have compliance enabled.")
			exit(100)
if output['stderr'] is not "":
	err_output("ERROR: "+output['stderr'])
	exit(102)

# Check passed
print "OK"
exit(0)




