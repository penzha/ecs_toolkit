#!/usr/bin/python


import sys
import os

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
from svc_upgrade_common import *



verbose=0
topologyfile=None
extendfile=None

def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help       Show this help message and exit"
	print "-v, --verbose     Enable verbose output"
	print "-V, --veryverbose Enable very verbose output"
	print "-T, --topology <file>  Topology file name and location"
	print "-E, --extend <file>  Extension file name and location"
	print "-l, --log         Log output to upgrade log"

	exit (1)

def parse_args(argv):

	result=parse_global_args(argv, req_version=True, req_upgradeType=True)


	if result is "usage":
		usage()



# Main logic

parse_args(sys.argv[1:])

if common.topologyfile is None and common.extendfile is None:   # Nothing to check
	msg_output("No topology or extend file specified - nothing to check")
	exit(0)

# Check that the file specified exists and is readable


for filename, Description in ({common.topologyfile, "Topology"}, {common.extendfile, "Extend"}):

	# File cannot currently be in /var/tmp/upgrade, since that area will be renamed when we
	# do deploy

	if filename is not None and "/var/tmp/upgrade" in filename:
		err_output("ERROR: Topology and extend files cannot be located in /var/tmp/upgrade")
		exit(103)



	if filename is not None and filename != "":

		msg_output("Checking that "+Description+" file exists and is readable...", indent=1, do_newline=False)
		if not os.path.isfile(filename):
			printFailed()
			err_output("ERROR: "+Description+" file '"+filename+"' does not exist or is not a file.")
			err_output("Check that the file exists and be sure to use the complete path to the file.")
			exit(100)

	try:
		p = open(common.topologyfile, 'r')
	except IOError as e:
		msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)
		err_output("ERROR: Unable to open file '"+common.topologyfile+"' for reading.")
		exit(101)

	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

	msg_output("Checking that file appears to be a topology file...", indent=1, do_newline=False)
	# Basic sanity check that it looks right.

	# Expect that files will be in format like:
	# # Some commented line
	# # Another commented line
	# r1n1,provo-shamrock.ecs.lab.emc.com,169.254.173.1,228SouthStreet,rack1,APM00151000602,shelf1
	# r1n2,sandy-shamrock.ecs.lab.emc.com,169.254.173.2,228SouthStreet,rack1,APM00151000602,shelf1
	# r1n3,orem-shamrock.ecs.lab.emc.com,169.254.173.3,228SouthStreet,rack1,APM00151000602,shelf1
	# r1n4,ogden-shamrock.ecs.lab.emc.com,169.254.173.4,228SouthStreet,rack1,APM00151000602,shelf1

	for line in p:
		if not line.startswith("#") and not line.startswith("r") and not line.strip() is "":
			msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)
			err_output("ERROR: File does not apear to be a topology file or has invalid characters.")
			err_output("  Lines are expected to start with either '#' or 'r'")
			exit(102)

	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)


# XXX - Do additional sanity checks of the topology+extend files, that they match the
#     current system state/config, etc



