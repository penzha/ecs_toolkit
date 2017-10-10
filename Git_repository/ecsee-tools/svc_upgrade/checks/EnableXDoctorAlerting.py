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


msg_output("Enabling XDoctor connect home", req_loglevel=1)


# Expects output with either a line like:
#   2016-08-09 01:51:34,696: xDoctor_4.4-18 - INFO: Successfully re-enabled ConnectHome ...
# or:
#   2016-08-09 01:52:01,476: xDoctor_4.4-18 - INFO: ConnectHome NOT in Maintenance, no need to re-enable it.


sudoicmd=get_sudoicmd()

cmd="ssh master.rack '"+sudoicmd+" xdoctor --tool --exec=connecthome_maintenance --method=enable'"

output=run_cmd(cmd)

returnstring=output['stdout']+output['stderr'] # For some reason XDoctor prints regular functional output to stderr

if not ("Successfully re-enabled ConnectHome ..." in returnstring or "ConnectHome NOT in Maintenance, no need to re-enable it." in returnstring):
	err_output("ERROR: Unexpected result when attempting to disable XDoctor ConnectHome.\n")

	err_output("Expected either 'Successfully re-enabled ConnectHome' or 'ConnectHome NOT in Maintenance'.")
	err_output("Output was:\n")
	err_output(returnstring+"\n")

	err_output("EXITING...")

	exit (100)

print "OK"
