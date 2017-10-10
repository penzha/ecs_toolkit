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


msg_output("Disabling BTree and REPO GC...", do_newline=False)

cmd=GCScript+" -d -n"
output=run_cmd(cmd)

stdout=output['stdout']

# Should produce an output like:

# Setting 'enabled' to false for all params
# Vals after change:
# Value of 'com.emc.ecs.chunk.gc.repo.enabled': "false",
# Value of 'com.emc.ecs.chunk.gc.repo.verification.enabled': "false",
# Value of 'com.emc.ecs.chunk.gc.btree.scanner.verification.enabled': "false",
# Value of 'com.emc.ecs.chunk.gc.btree.scanner.copy.enabled': "false",
# Value of 'com.emc.ecs.chunk.gc.btree.enabled': "false",

# If we don't see 5 "false"s, fail.
# If we see a "true", fail.

if stdout.count("false") != 6 or "true" in stdout:
	printFailed()
	err_output("Unable to disable BTree and Repo GC.  Expected output showing")
	err_output("  6 params with 'false' status.  Did not see 6 'false' strings or")
	err_output("  saw 'true' string in output")
	err_output("")
	err_output("Command run:  '"+cmd+"'")
	err_output("Output was:")
	err_output(output['stdout'])
	err_output(output['stderr'])

	exit (100)


printDone()











