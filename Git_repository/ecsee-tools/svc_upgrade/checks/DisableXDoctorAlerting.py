#!/usr/bin/python



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

	result=parse_global_args(argv)


	if result is "usage":
		usage()


# Main logic

parse_args(sys.argv[1:])


msg_output("Disabling XDoctor connect home, placing in maintenance mode", req_loglevel=1)


# Expects output with either a line like:
#   2016-08-09 01:31:04,346: xDoctor_4.4-18 - INFO: Successfully disabled ConnectHome ...
# or:
#   2016-08-09 01:41:56,553: xDoctor_4.4-18 - INFO: ConnectHome Already in a Maintenance window, no need to disable it.


sudoicmd=get_sudoicmd()

cmd="ssh master.rack '"+sudoicmd+" xdoctor --tool --exec=connecthome_maintenance --method=disable'"

output=run_cmd(cmd)

returnstring=output['stdout']+output['stderr'] # For some reason XDoctor prints regular functional output to stderr

if not ("Successfully disabled ConnectHome ..." in returnstring or "ConnectHome Already in a Maintenance window, no need to disable it." in returnstring):
	err_output("ERROR: Unexpected result when attempting to disable XDoctor ConnectHome.\n")
	err_output("Expected either 'Successfully disabled ConnectHome' or 'ConnectHome Already in a Maintenance window'.")
	err_output("Output was:")
	err_output(returnstring+"\n")

	err_output("EXITING...")

	exit (100)

print "OK"
