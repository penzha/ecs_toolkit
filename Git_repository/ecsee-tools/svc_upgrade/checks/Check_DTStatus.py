#!/usr/bin/python

# Check whether DTs are initialized and ready

# Exit codes:
#   100 - could not determine OS version or version invalid
#   101 - incorrect version
#   1 - bad syntax or help screen

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


def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-O, --os          ECS OS upgrade"
	print "-A, --application ECS Application Software upgrade"
	print
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

check_dt_ready

exit (0)




