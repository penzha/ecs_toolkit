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

GCScript=UpgradeRootPath+"/tools/setGCState"


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


msg_output("Enabling Repo GC...", do_newline=False)

cmd=GCScript+" -e -r -n"
output=run_cmd(cmd)

stdout=output['stdout']

# Should produce an output like:

# Setting 'enabled' to true for params
# Vals after change:
# Value of 'com.emc.ecs.chunk.gc.repo.enabled': "true",
# Value of 'com.emc.ecs.chunk.gc.repo.verification.enabled': "true",


hasError=None
if stdout.count("repo") != 2:
	hasError=100


lines=stdout.splitlines()
if hasError==None:
	for line in lines:
		if "repo" in line and (not "true" in line or "false" in line):
			hasError=101


if hasError != None:
	printFailed()
	if hasError==100:
		err_output("Unexpected output trying to enable Repo GC.  Expected output showing")
		err_output(" 2 params with 'true' status.  Did not see exactly 2 params, which is")
		err_output(" unexpected.  Aborting")
	if hasError==101:
		err_output("Unable to enable Repo GC.  Expected output showing 2 params with")
		err_output("  'true' status.  One or more lines did not have 'true' strings or")
		err_output("  saw 'false' string in output")

	err_output("")
	err_output("Command run:  '"+cmd+"'")
	err_output("Output was:")
	err_output(output['stdout'])
	err_output(output['stderr'])

	exit (hasError)


printDone()











