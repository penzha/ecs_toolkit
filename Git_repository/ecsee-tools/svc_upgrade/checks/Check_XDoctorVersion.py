#!/usr/bin/python

# Attempt to check the current XDoctor version and upgrade, if possible.
# If the system has connectivity to ftp.emc.com, will be able to verify
#   whether XDoctor is up to date or not; if not, then we'll upgrade.
# If we can't upgrade, provide an error; the user is expected to confirm
#   that XDoctor is up to date, ensuring that the latest health checks and
#   critical config changes are being made.

# Exit codes:
# - 100:  Could not verify/upgrade XDoctor version

import sys
import os
import getopt
CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
from svc_upgrade_common import *


CurScriptName=os.path.basename(__file__)


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

sudoicmd=get_sudoicmd()

msg_output("Validating XDoctor version and upgrading if necessary", req_loglevel=1)
cmd=" ssh master.rack xdoctor --upgrade --auto"
output=run_cmd(cmd, noErrorHandling=True, timeout=300, do_sudo=True)

if (output['retval'] is not 0 and output['stderr'] is not None):
	# xdoctor will potentially output text to stderr regardless of whether
	#   an error occurred or not, and potentially set retval to 0 even if
	#   an error occurred.  Assume that if an error occurred that output
	#   has been made to stderr and it contains the string "ERROR "

	if ("ERROR " in output['stderr'] ): # actual error found
		err_output("ERROR: Could not upgrade or validate xDoctor version.")
		err_output()
		err_output("If the system cannot reach ftp.emc.com and this is expected, ")
		err_output("please ensure that XDoctor has been manually upgraded to the latest")
		err_output("version before continuing.")
		err_output()
		err_output("Output was:")
		err_output(output['stderr'])

		exit (100)
	elif "INFO: xDoctor is up-to-date" in output['stderr']:
		msg_output("xDoctor is up to date.", req_loglevel=1)






