#!/usr/bin/python

# Deploy and prepare software for installation
# Prepare nodes for install
#
# For application upgrade, this means unzipping the upgrade package, installing
#   installer RPMs, unzipping quickfit package (if exists), etc.
#
# For OS upgrade, this means unzipping upgrade package, preserving old installer dir(s),
#   disabling PXE and installer services,  disabling DTLB, and other preparation steps.
# Important difference is that for OS upgrade, there are some (minor) system operation changes
#   (like disabling DTLB) once deploy is run.

# Exit codes:
#
# - 100: Source dir for installer file(s) not found.
# - 101:
# - 102:
# - 103:
# - 104:
# - 105: upgradeType was invalid (should be set/caught by parse_global_args)
# - 106: md5sum check of files on installer node failed
# - 107: Could not determine refit package file name from zip file
# - 108: md5sum of file(s) were incorrect after pushing to nodes
# - 109: Deploy failed to one or more nodes
# - 110: IPMI test failed

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

indent=0


def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print ""
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


def run_deploy_cmd(command, description, MACHINES=None, indent=0, req_loglevel=0):

	verbosetext=""

	msg_output(description+"...", indent=indent, do_newline=False)

	if MACHINES==None:
		result=run_cmd(cmd, indent=indent, print_Verbose=False)
		verbosetext=result['verbose_stdout']

	else:
		result=run_multi_cmd(cmd, indent=indent, MACHINES=MACHINES, print_Verbose=False)
		for MACHINE in MACHINES:
			verbosetext=verbosetext+result[MACHINE]['verbose_stdout']

	# XXX - error handling

	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

	msg_output("=================== Verbose output =====================", req_loglevel=1, indent=indent)
	msg_output(verbosetext, req_loglevel=1, indent=indent)

	return result


def distribute_svcupgrade_bundle():
	# If running on the first node, attempt to copy and unzip the svc_upgrade package
	# to the second node.
	#
	# Currently we can't be certain where the user put it and if it still exists.
	# Assume, though, by far the most common location is the parent directory of where
	# we're running svc_upgrade from.

	# Assume the svc_upgrade archive is named svc_upgrade-[Version].zip


	# Check that we're currently running on the first mode.  Get the second node ID

	firstnode=get_first_node(get_machines())
	curIP=get_local_private_IP()
	curnode=int(get_nodenum(curIP))
	MACHINES=get_machines()
	if len(MACHINES) > 1:
		secondnode=MACHINES[1]
	else:
		#XXX - real error handling once I figure out how I'm doing that
		return "no second node"

	if curnode != firstnode:
		#XXX - real error handling once I figure out how I'm doing that
		return "not first node"


	# Get expected upgrade bundle name.

	svcupgrade_bundle_name="svc_upgrade-"+Version+".zip"

	# Get the parent directory of current svc_upgrade (the expected "bundle dir")

	svcupgrade_bundle_dir=os.path.dirname(os.path.abspath(UpgradeRootPath))

	# Look for the upgrade bundle.

	msg_output("Looking for svc_upgrade bundle named '"+svcupgrade_bundle_name+" in "+svcupgrade_bundle_dir, req_loglevel=1)

	if not os.path.isfile(svcupgrade_bundle_dir+"/"+svcupgrade_bundle_name):
		#XXX - real error handling once I figure out how I'm doing that
		return "file not found"

	# If exist, copy to second node in the same directory, unzip svc_upgrade bundle

	output=run_cmd("scp '"+svcupgrade_bundle_dir+"/"+svcupgrade_bundle_name+"' "+secondnode+":"+svcupgrade_bundle_dir+"/", do_sudo=True, noErrorHandling=True, timeout=30)

	if output['retval'] != 0:
		#XXX - real error handling once I figure out how I'm doing that
		return "couldn't scp file"

	output=run_cmd("cd \""+svcupgrade_bundle_dir+"\"; unzip -o "+svcupgrade_bundle_name, MACHINE=secondnode, noErrorHandling=True, timeout=60)
	if output['retval'] != 0:
		#XXX - real error handling once I figure out how I'm doing that
		return "couldn't unzip file"

	# XXX - should check for destination dir, md5sum, etc.  Or modify copy_to_nodes to better fit this usage
	#   since this is an optional task

	return "DONE"




### Main logic

parse_args(sys.argv[1:])


if common.upgradeType != "OS" and common.upgradeType != "Application":
	# Should have been set/caught by parse_args+parse_global_args
	err_output("ERROR:  Upgrade Type '"+common.upgradeType+"' is invalid.  Exiting.")
	exit (105)


# XXX - re-check a few things, like whether we're running on the installer node


UpgDetails=common.UpgVersions[common.TargetVersion][common.upgradeType]


# Common initial deploy steps (both OS and Application upgrades)

# Check if installer file exists, get its name

InstallerFileFull=check_installer_file(common.BundleSourceDir, UpgDetails)


# Type-specific deploy steps

if common.upgradeType=="OS":

	curDate=strftime("%Y-%m-%d_%H.%M.%S")
	tmpDir="/var/tmp"
	refitDir=tmpDir+"/refit.d"
	refitOldDir=refitDir+"_"+curDate

	msg_output("")
	msg_output("Deploying OS install files and preparing system for upgrade")
	msg_output("")


	# If running on the first node, attempt to copy and unzip the svc_upgrade package
	# to the second node.

	msg_output("Distributing upgrade bundle to additional nodes (if needed)...", do_newline=False)

	result=distribute_svcupgrade_bundle()
	if result == "DONE":
		printDone()
	else:
		msg_output(bcolors.WARNING+"NOT DONE"+bcolors.ENDC)
		msg_output("Reason: "+result, indent=1)

	# XXX - Check if correct bundle is already deployed?  If so, exit and require
	# --force or something?  Or just redeploy?  If we redeploy,
	# go ahead and preserve history?  If so, might as well not bother checking.

	# Probably should combine all steps below into a per-node loop


	msg_output("Checking for previous OS upgrade files...", do_newline=False)

	for MACHINE in get_machines():

		# If there is a refit.d file in the /var/tmp directory, rename to refit.d_date

		# Move any of the supporting refit files (refit script, MD5SUMS, etc) into the old refit dir


		result=run_cmd("if [[ -d "+refitDir+" ]]; then echo refit present; fi", MACHINE=MACHINE)

		if result['stdout'].strip()=="refit present":

			msg_output("Previous upgrade dir found at "+refitDir+" on "+MACHINE+".  Renaming to "+refitOldDir, indent=1, req_loglevel=1)
			run_multi_cmd("mv "+tmpDir+"/refit "+refitDir+"/. 2>/dev/null; mv "+tmpDir+"/*update* "+refitDir+"/. 2>/dev/null; mv "+tmpDir+"/MD5SUMS "+refitDir+"/. 2>/dev/null", MACHINES=[MACHINE])

			# Rename the old refit dir with a timestamp
			run_multi_cmd("mv "+refitDir+" "+refitOldDir, MACHINES=[MACHINE]);

	printDone()

	# On installer (current) node, unzip package to /var/tmp and validate md5sum

	cmd="unzip -o "+InstallerFileFull+" -d "+tmpDir
	run_cmd(cmd, printText="Extracting upgrade package on installer node...", printComplete=True)

	# Verify md5sums of update package

	cmd="cd "+tmpDir+"; md5sum -c MD5SUMS"
	result=run_cmd(cmd, printText="Checking md5sums of upgrade package files...", printComplete=False)

	# Expect that the output will look something like:
	#   ecs-os-setup-target.x86_64-3.1422.663.update.tbz: OK
	#   refit: OK
	#
	# Look for two occurrences of ": OK", if not, something has gone wrong

	if result['stdout'].count(": OK") != 2:
		errstring="ERROR:  md5sum check for upgrade package files on installer node failed.  Exiting.\n"
		errstring+="\n"
		errstring+="MD5SUMS file checked: "+tmpDir+"/MD5SUMS\n"
		errstring+="Output was:\n"
		errstring+=result['stdout']
		post_cmd_output(result, Failed=True, errortext=errstring)
		exit (106)

	post_cmd_output(result, indent=indent)

	# Copy refit files to all nodes, verify, and set permissions

	# Get the specific name of the refit archive
	# Procedure has the user copy files using a wildcard which could copy unexpected
	#  files
	#
	# Should be something like: ecs-os-setup-target.x86_64-3.1422.663.update.tbz

	result=run_cmd("unzip -l "+InstallerFileFull+" | grep ecs-os-setup-target | awk '{ print $4 }'")
	if result['stdout'] is None or result['stdout']=="":
		err_output("ERROR:  Could not determine refit archive name.")
		exit (107)
	else:
		RefitArchiveName=result['stdout'].strip()

	# Get the md5sum outputs from the md5sum file for comparison later

	MD5SUMS=parse_md5sums(tmpDir+"/MD5SUMS")

	#run_cmd("viprscp /usr/local/bin/refit "+tmpDir+"/")
	run_cmd("viprscp "+tmpDir+"/refit "+tmpDir+"/")

	cmd="viprscp -X "+tmpDir+"/"+RefitArchiveName+" "+tmpDir
	run_cmd(cmd, printText="Copying refit archive to nodes (please wait)...", printComplete=True)

	for MACHINE in get_machines():

		# Validate files copied successfully

		result=run_cmd("md5sum "+tmpDir+"/refit", printText="Validating files on "+MACHINE+"...",MACHINE=MACHINE,printComplete=False)

		if not MD5SUMS['refit'] in result['stdout']:
			errstring="ERROR: md5sum check of /usr/local/bin/refit on "+MACHINE+" was incorrect.\n"
			errstring+="  Expected: "+MD5SUMS['refit']+"\n"
			errstring+="  Received: "+result['stdout']+"\n"
			post_cmd_output(result, Failed=True, errortext=errstring)

			exit(108)

		result=run_cmd("md5sum "+tmpDir+"/"+RefitArchiveName, MACHINE=MACHINE)

		if not MD5SUMS[RefitArchiveName] in result['stdout']:
			errstring="ERROR: md5sum check of "+tmpDir+"/"+RefitArchiveName+" on "+MACHINE+" was incorrect.\n"
			errstring+="  Expected: "+MD5SUMS[RefitArchiveName]+"\n"
			errstring+="  Received: "+result['stdout']+"\n"
			post_cmd_output(result, Failed=True, errortext=errstring)
			exit(108)

		post_cmd_output(result, indent=indent)


		#run_cmd("chmod 755 /usr/local/bin/refit", MACHINE=MACHINE)
		run_cmd("chmod 755 "+tmpDir+"/refit", MACHINE=MACHINE)


	# Capture RPM info (why are we doing this, and what are we doing it for?  Just for
	#   troubleshooting later, so should go to the log?

	# Run refit deploybundle on all nodes

	cmd="viprexec '"+tmpDir+"/refit deploybundle "+tmpDir+"/"+RefitArchiveName+"'"
	result=run_cmd(cmd, printText="Preparing installer bundle on nodes...", printComplete=True)

	# Verify deployment

	# Each completed deploy should output the message "Bundled deployed to host.
	#   Proceed with update." if successful.  Count the number of occurrences
	#   of this string in output, and compare to the number of nodes.

	if (result['stdout'].count("Bundled deployed to host. Proceed with update.") != len(get_machines())):
		err_output("ERROR:  One or more 'refit deploybundle' operations did not complete.")
		err_output("")
		err_output("Output of all operations was:")
		err_output(result['verbose_out'])
		exit(109)

	# Verify IPMI remote management functionality

	msg_output("Testing IPMI Management Functionality to nodes...", do_newline=False)

	for MACHINE in get_machines():

		IPMI_Addr=get_IPMI_IP(MACHINE)

		cmd='sudo ipmitool -H '+IPMI_Addr+' -U root -P passwd power status'
		result=run_cmd(cmd)

		# Expects that command will return "Chassis power is on" if successful

		if not "Chassis Power is on" in result['stdout']:
			msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)
			err_output("ERROR:  Could not contact ipmi on "+IPMI_Addr+" or output was unexpected")
			err_output("")
			err_output("Command was: "+cmd)
			err_output("Output was:")
			err_output(result['verbose_out'])
			exit(110)

	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)



	# Remove NFS mounts (if any) - should just go under prechecks?




	# End OS upgrade mode deploy

elif common.upgradeType=="Application":



	AppTempDir="/var/tmp/upgrade"
	curDate=strftime("%Y-%m-%d_%H.%M.%S")
	AppOldDir=AppTempDir+"_"+curDate

	msg_output("")
	if UpgDetails['QuickFit']:
		msg_output("Preparing OS quickfit, HAL, and fabric/object upgrade files for install:")
	else:
		msg_output("Preparing HAL, and fabric/object upgrade files for install:")

	msg_output("")


	msg_output("Checking for upgrade temp directory '"+AppTempDir+"'...", indent=0, do_newline=False)

	if not os.path.isdir(AppTempDir):
		if os.path.exists(AppTempDir):
			msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)
			err_output("ERROR: Temporary dir for upgrade package, '"+AppTempDir+"' is not a directory\n")
			err_output("EXITING...")

			exit (101)

	else: # Existing upgrade dir exists, rename
		msg_output("Previous upgrade dir found at "+AppTempDir+".  Renaming to "+AppOldDir, indent=1, req_loglevel=1)

		run_cmd("sudo mv "+AppTempDir+" "+AppOldDir)

	try:
		msg_output("\nAttempting to create upgrade temp dir...", req_loglevel=1,indent=1, do_newline=False)
		os.makedirs(AppTempDir)
	except OSError as exc:
		printFailed()
		err_output("ERROR: Could not create temporary directory, '"+AppTempDir+"'\n")

		err_output("EXITING...")
		exit (102)


	# XXX - check that we can write to it?


	# XXX - Free space check?

	printDone()



	cmd='tar xvz -C '+AppTempDir+' -f '+InstallerFileFull+' --overwrite'
	run_cmd(cmd, printText="Extracting installer archive...", printComplete=True)

	cmd='cd '+AppTempDir+';sudo ./run.sh'
	run_cmd(cmd, printText="Deploying installer RPM package (staging installer)....", indent=1, printComplete=True)

	if UpgDetails['QuickFit']:
		cmd='unzip -o -d /'+AppTempDir+' '+AppTempDir+'/tars/ecs-os-hotfix-*.zip'
		run_cmd(cmd, printText="Extracting hotfix archive...", printComplete=True)

	# End Application upgrade mode deploy












