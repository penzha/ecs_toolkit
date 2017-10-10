#!/usr/bin/python


import sys
import os
import getopt


CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
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

	result=parse_global_args(argv)


	if result is "usage":
		usage()



# Main logic

parse_args(sys.argv[1:])



# Query fabric agent health property on each node.
# Expects output that looks like:
#     "health": "GOOD",

cmd='cd /opt/emc/caspian/fabric/cli;bin/fcli agent agent.health /v1/agent/health | grep health | grep -v {'

#print "Running command:"
#print "\t"+cmd
output=run_multi_cmd(cmd)

HealthStatuses=dict()
for MACHINE, details in output.viewitems():
	HealthStatuses[MACHINE]=details['stdout'].strip()


for MACHINE, HealthStatus in HealthStatuses.viewitems():
	if not HealthStatus.startswith('"health": "'):
		sys.stderr.write("FATAL: While executing "+CurScriptName+"\n\n")

		sys.stderr.write("Could not determine current fabric agent health status.  Output was:\n")
		sys.stderr.write("'"+HealthStatus+"'\n")

		exit (100)
	elif not HealthStatus.startswith('"health": "GOOD"'):
		sys.stderr.write("FATAL: While executing "+CurScriptName+"\n\n")

		sys.stderr.write("Fabric Health on node "+MACHINE+" was not GOOD.  Output was:\n")
		sys.stderr.write("'"+HealthStatus+"'\n")

		exit (101)
	else:
		if verbose >=1:
			print "\t Node "+MACHINE+" fabric agent status: GOOD"



