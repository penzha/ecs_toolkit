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


sku=get_sku()

def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help       Show this help message and exit"
	print "-v, --verbose     Enable verbose output"
	print "-V, --veryverbose Enable very verbose output"
	print "-l, --log         Log output to upgrade log"
	print "-T, --topology <file>  Topology file name and location"
	print "                  (required)"
	print "-E, --extend <file>  Extension file name and location"
	print "                  (optional)"
	print "-P, --provision <file>  Provisioning file name and location"
	print "                  (default is: <installer dir>/conf/provisioning.txt)"
	print "-S, --sku <sku>   System SKU (e.g. U300)"
	print "                  (default is auto-detect)"

	exit (1)

def parse_args(argv):

	result=parse_global_args(argv, req_version=True, req_upgradeType=True)


	if result is "usage":
		usage()

	# Additional script-specific option parsing

	try:
		opts, args = getopt.getopt(argv,common.allowedArgs['short'],common.allowedArgs['long'])
	except getopt.GetoptError:
		return("usage")

	# Check that topology was provided (or should we just read this from the cache file)?




# Main logic

parse_args(sys.argv[1:])

UpgDetails=common.UpgVersions[common.TargetVersion][common.upgradeType]

if common.upgradeType == "OS":
	msg_output("No HAL upgrade is needed for "+common.TargetVersion+" "+common.upgradeType+" upgrades.")
	exit(0)

if common.upgradeType == "Application":

	InstallerDir="/opt/emc/caspian/installer"

	UpgradeDir=UpgDetails['TargetOS'] # should be like "2.2.1.0-1309.3719890.88"
	tempdir="/var/tmp/upgrade"

	UpgradeFullPath=tempdir+"/"+UpgradeDir

	msg_output("")
	msg_output("Installing HAL update (if needed):")
	msg_output("")

	msg_output("Validating topology file(s)...", indent=1, do_newline=False)
	# XXX - validate the topology file (do this even if we do it in prechecks)
	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

	# XXX - Copy topology/extend/prov file to the upgrade dir?

	msg_output("Validating provisioning file(s)...", indent=1, do_newline=False)
	# XXX - validate the provision file (do this even if we do it in prechecks)
	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)


	msg_output("Validating installer tool...", indent=1, do_newline=False)
	# XXX - Check that installer tool exists and is readable (and md5sum?)
	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

	# XXX - add sku handling


	cmd="cd '"+InstallerDir+"'; sudo bin/installer -operation UPGRADE_HAL --sku "+sku

	if common.topologyfile:
		cmd=cmd+" --topology '"+common.topologyfile+"'"
	if common.provisionfile:
		cmd=cmd+" --provision '"+common.provisionfile+"'"
	if common.extendfile:
		cmd=cmd+" --extend '"+common.extendfile+"'"

	msg_output("Running HAL upgrade (please wait)...", indent=1, do_newline=False)

	msg_output ("Command we will run:", indent=1, req_loglevel=1)
	msg_output (cmd, indent=2, req_loglevel=1)
	if common.verbose >= 2:  # Display the output of the script to the terminal in real time
		msg_output("")
		output=run_cmd(cmd, noErrorHandling=True, realtime=True)
	else:
		output=run_cmd(cmd, noErrorHandling=True, indent=1)

		#msg_output(output['stdout'])
		#err_output(output['stderr'])

	# OF COURSE there are cases where installer fails but doesn't print to stderr and doesn't set a retval on error, so need to manually check stdout for certain error types.
	# - No topology file specified:  "topology not used, skip environment setup"


	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

	# Check new HAL version is correct

	msg_output("Verifying HAL install...", indent=1, do_newline=False)

	for MACHINE in get_machines():
		curhalver=run_cmd("rpm -qv 'viprhal'", MACHINE=MACHINE)

		if not curhalver['stdout'].strip() == UpgDetails['TargetHAL']:
			msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)
			err_output("HAL version on target node is different than expected.")
			err_output("Expected: "+UpgDetails['TargetHAL'])
			err_output("Reported val: "+curhalver.strip())
			exit(100)


	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

exit(0)











