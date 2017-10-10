#!/usr/bin/python



import subprocess
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
	print "Upgrade type (one required):"
	print "-O, --os          ECS OS upgrade"
	print "-A, --application ECS Application Software upgrade"
	print
	print "Other options:"
	print
	print "-h, --help       Show this help message and exit"
	print "-v, --verbose     Enable verbose output"
	print "-V, --veryverbose Enable very verbose output"
	print "-l, --log         Log output to upgrade log"

	exit (1)

def parse_args(argv):

	result=parse_global_args(argv, req_upgradeType=True)


	if result is "usage":
		usage()


# Main logic

parse_args(sys.argv[1:])

UpgDetails=common.UpgVersions[common.TargetVersion][common.upgradeType]


# Check if installer file exists, get its name

InstallerFileFull=check_installer_file(common.BundleSourceDir, UpgDetails)
