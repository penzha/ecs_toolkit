#!/usr/bin/python

# Deploy and prepare object/fabric software

import subprocess
import sys
import os
import getopt
import glob

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib")

import svc_upgrade_common as common
from svc_upgrade_common import *

InstallerDir="/opt/emc/caspian/installer"

sku=get_sku()

def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help         Show this help message and exit"
	print "-v, --verbose      Enable verbose output"
	print "-V, --veryverbose  Enable very verbose output"
	print "-l, --log          Log output to upgrade log"
	print ""
	print "-T, --topology <file>  Topology file name and location"
	print "                   (required)"
	print "-E, --extend <file>  Extension file name and location"
	print "                   (optional)"
	print "-P, --provision <file>  Provisioning file name and location"
	print "                   (default is: <installer dir>/conf/provisioning.txt)"
	print "-Z, --appfile <file> application.conf file name and location"
	print "                   (optional)"
	print "-S, --sku <sku>    System SKU (e.g. U300)"
	print "                   (default is auto-detect)"
	print ""
	print "-m, --mode <online|offline>    Perform online or offline upgrade"
	print "                   (required)"


	exit (1)

def parse_args(argv):

	result=parse_global_args(argv, req_version=True, req_upgradeType=True, req_topology=True, req_upgradeMode=True)


	if result is "usage":
		usage()



# Main logic

parse_args(sys.argv[1:])

UpgDetails=common.UpgVersions[common.TargetVersion][common.upgradeType]

#UpgradeDir=UpgDetails[TargetOS] # Should be like "2.2.1.0-1309.3719890.88"
#tempdir="/var/tmp/upgrade"
#UpgradeFullPath=tempdir+"/"+UpgradeDir



msg_output("")
msg_output("Installing fabric/object update:")
msg_output("")



if common.upgradeMode=="offline":
	cmd="cd '"+InstallerDir+"'; sudo bin/installer -operation UPGRADE --sku "+sku
elif common.upgradeMode=="online":
	cmd="cd '"+InstallerDir+"'; sudo bin/installer -operation MANUAL_UPGRADE --sku "+sku
else:
	err_output("ERROR: Unexpected upgrade mode: '"+str(common.upgradeMode)+"'")
	exit (103)


if common.topologyfile:
	cmd=cmd+" --topology '"+common.topologyfile+"'"
if common.provisionfile:
	cmd=cmd+" --provision '"+common.provisionfile+"'"
if common.extendfile:
	cmd=cmd+" --extend '"+common.extendfile+"'"
if common.appfile:
	cmd=cmd+" --application '"+common.appfile+"'"


msg_output("Running fabric/object upgrade (can take over an hour)...", indent=1)

output=run_cmd(cmd, noErrorHandling=True,realtime=True)
err_output(output['stderr'])

if output['retval']==0:
	printDone()
	exit(0)
else:
	exit (output['retval'])
















