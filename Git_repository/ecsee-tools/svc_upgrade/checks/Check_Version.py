#!/usr/bin/python

# Check whether the current version is high enough to run a fabric-only upgrade to 2.2.1 HF1.
# Nodes must already be running either 2.2.1 GA or 2.2.1 HF1; check will fail otherwise.

# XXX - rewrite into a generic version check script that takes an argument, so more portable between versions?

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

# For now, assume 3.0



# Get lists of expected (allowed) versions for this upgrade version and type
ExpectedVersions=common.UpgVersions[common.TargetVersion][common.upgradeType]

# Get current OS version
cmd="rpm -qv ecs-os-base"
output=run_multi_cmd(cmd)


Versions=dict()
for MACHINE, details in output.viewitems():
	Versions[MACHINE]=details['stdout'].strip()

	#print "\t"+MACHINE+": "+Versions[MACHINE]

msg_output("Command run:  '"+cmd+"'", indent=1, req_loglevel=1)
msg_output("OS Version(s) expected: ", indent=1, req_loglevel=1)

for ExpectedOSVersion in ExpectedVersions['ExpectedOS']:
	msg_output(ExpectedOSVersion, indent=2, req_loglevel=1)

msg_output("OS Versions installed:", indent=1, req_loglevel=1)
for MACHINE, version in Versions.viewitems():
	msg_output(MACHINE+": "+version, indent=2, req_loglevel=1)


for MACHINE, version in Versions.viewitems():
	version=version.strip()
	if not version.startswith("ecs-os-base"):
		# Expect outputs like "ecs-os-base-2.2.0.0-1196.f7d8051.578.noarch" or
		# "ecs-os-base-2.2.1.0-1281.e8416b8.68.noarch", otherwise we didn't get
		# a valid string.


		sys.stderr.write("FATAL: While executing "+CurScriptName+"\n\n")

		sys.stderr.write("Could not determine current OS version.  Output was:\n")
		sys.stderr.write("'"+version+"'\n")

		exit(100)

	badversion=True
	for ExpectedOSVersion in ExpectedVersions['ExpectedOS']:
		if version.startswith("ecs-os-base-"+ExpectedOSVersion):
			# OS version is the version expected (3.0 GA)

			badversion=False

	if badversion:
		sys.stderr.write("FATAL: While executing "+CurScriptName+"\n\n")

		sys.stderr.write("Current OS version is incorrect.  Allowed version(s) are:\n")
		for ExpectedOSVersion in ExpectedVersions['ExpectedOS']:
			sys.stderr.write("  'ecs-os-base-"+ExpectedOSVersion+".noarch' \n")
		sys.stderr.write("Current version is '"+version+"'\n")

		exit (100)


# What about checking fabric version??  See page 31

# Version check passed
print "OK"

exit (0)




