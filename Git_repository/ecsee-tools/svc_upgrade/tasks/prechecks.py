#!/usr/bin/python



import subprocess
import sys
import os
import getopt
from time import sleep,time

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib")

import svc_upgrade_common as common
from svc_upgrade_common import *  # Declare functions/objects in local namespace
from collections import OrderedDict


# Define which checks should run, and in which order.
# Checks are added to a Dictionary named "ChecksList", in the following format:

# ChecksList['CheckID']={   CheckID must be defined and unique, but currently has no other meaning.
#                           Best practice is currently to use the check script's name here.
#	'name':'ScriptName'     This is the name of the check script that will be run, without trailing .py
#   'description':'...'     Displayed to the user as the check description when run.

PreChecksList = OrderedDict() # Need to use OrderedDict to preserve the order of this Dictionary,
							# because Python is weird
PostChecksList = OrderedDict()

for loopVers in common.UpgVersions:  # i.e. "3.0", "3.0HF1", etc
	PreChecksList[loopVers]=OrderedDict()
	PreChecksList[loopVers]['OS']=OrderedDict()
	PreChecksList[loopVers]['Application']=OrderedDict()

	PostChecksList[loopVers]=OrderedDict()
	PostChecksList[loopVers]['OS']=OrderedDict()
	PostChecksList[loopVers]['Application']=OrderedDict()



ChecksDef=OrderedDict()


ChecksDef['Check_Version']={
	'name':'Check_Version',
	'description':'Checking for valid OS versions'
}
ChecksDef['Check_InstallerNode']={
	'name':'Check_InstallerNode',
	'description':'Checking if running on the installer node'
}
ChecksDef['Check_InstallerFiles']={
	'name':'Check_InstallerFiles',
	'description':'Checking that installation bundle file exists'
}
ChecksDef['Check_TopologyFile']={
	'name':'Check_TopologyFile',
	'description':'Validating Topology file (if applicable)'
}
ChecksDef['Check_XDoctorVersion']={
	'name':'Check_XDoctorVersion',
	'description':'Verifying/Upgrading XDoctor Version'
}
ChecksDef['DisableXDoctorAlerting']={
	'name':'DisableXDoctorAlerting',
	'description':'Disabling XDoctor Alerting'
}
ChecksDef['XDoctorHealthCheck']={
	'name':'XDoctorHealthCheck',
	'description':'Running XDoctor Health Check (please wait)'
}
ChecksDef['Check_ContainerHealth']={
	'name':'Check_ContainerHealth',
	'description':'Verifying Docker containers are active and running'
}
ChecksDef['Check_FabricAgent']={
	'name':'Check_FabricAgent',
	'description':'Checking Fabric Agent status'
}
ChecksDef['Check_Compliance']={
	'name':'Check_Compliance',
	'description':'Checking whether compliance is enabled'
}
ChecksDef['DisableGC']={
	'name':'DisableGC',
	'description':'Disabling BTree and REPO GC (workaround for STORAGE-15711)'
}
ChecksDef['DisableBTreeGC']={
	'name':'DisableBTreeGC',
	'description':'Disabling BTree GC (currently not supported in 3.0 HF1 pending patches)'
}
ChecksDef['EnableRepoGC']={
	'name':'EnableRepoGC',
	'description':'Enabling Repo GC (if disabled)'
}
ChecksDef['Check_DiskPartitions']={
	'name':'Check_DiskPartitions',
	'description':'Checking disks and partitions'
}
ChecksDef['EnableDTLB']={
	'name':'EnableDTLB',
	'description':'Enabling DT Load Balancing on all nodes'
}
ChecksDef['EnablePXE']={
	'name':'EnablePXE',
	'description':'Moving PXE files back into place'
}
ChecksDef['EnableXDoctorAlerting']={
	'name':'EnableXDoctorAlerting',
	'description':'Enabling XDoctor Alerting'
}
#ChecksDef['Check_UpgradeCompleteFlag']={
#	'name':'Check_UpgradeCompleteFlag',
#	'description':'Checking that Upgrade Complete flag is set, and setting if necessary'
#}



PreChecksList['3.0']['OS']['Check_Version']=ChecksDef['Check_Version']
PreChecksList['3.0']['OS']['Check_InstallerNode']=ChecksDef['Check_InstallerNode']
PreChecksList['3.0']['OS']['Check_InstallerFiles']=ChecksDef['Check_InstallerFiles']
PreChecksList['3.0']['OS']['Check_XDoctorVersion']=ChecksDef['Check_XDoctorVersion']
PreChecksList['3.0']['OS']['DisableXDoctorAlerting']=ChecksDef['DisableXDoctorAlerting']
PreChecksList['3.0']['OS']['XDoctorHealthCheck']=ChecksDef['XDoctorHealthCheck']
PreChecksList['3.0']['OS']['Check_ContainerHealth']=ChecksDef['Check_ContainerHealth']
PreChecksList['3.0']['OS']['Check_FabricAgent']=ChecksDef['Check_FabricAgent']
PreChecksList['3.0']['OS']['Check_Compliance']=ChecksDef['Check_Compliance']


PreChecksList['3.0']['Application']['Check_Version']=ChecksDef['Check_Version']
PreChecksList['3.0']['Application']['Check_InstallerNode']=ChecksDef['Check_InstallerNode']
PreChecksList['3.0']['Application']['Check_InstallerFiles']=ChecksDef['Check_InstallerFiles']
PreChecksList['3.0']['Application']['Check_TopologyFile']=ChecksDef['Check_TopologyFile']
PreChecksList['3.0']['Application']['Check_XDoctorVersion']=ChecksDef['Check_XDoctorVersion']
PreChecksList['3.0']['Application']['DisableXDoctorAlerting']=ChecksDef['DisableXDoctorAlerting']
PreChecksList['3.0']['Application']['XDoctorHealthCheck']=ChecksDef['XDoctorHealthCheck']
PreChecksList['3.0']['Application']['Check_ContainerHealth']=ChecksDef['Check_ContainerHealth']
PreChecksList['3.0']['Application']['Check_FabricAgent']=ChecksDef['Check_FabricAgent']
PreChecksList['3.0']['Application']['Check_DiskPartitions']=ChecksDef['Check_DiskPartitions']
PreChecksList['3.0']['Application']['DisableGC']=ChecksDef['DisableGC']

PreChecksList['3.0HF1']['OS']=PreChecksList['3.0']['OS']

PreChecksList['3.0HF1']['Application']['Check_Version']=ChecksDef['Check_Version']
PreChecksList['3.0HF1']['Application']['Check_InstallerNode']=ChecksDef['Check_InstallerNode']
PreChecksList['3.0HF1']['Application']['Check_InstallerFiles']=ChecksDef['Check_InstallerFiles']
PreChecksList['3.0HF1']['Application']['Check_TopologyFile']=ChecksDef['Check_TopologyFile']
PreChecksList['3.0HF1']['Application']['Check_XDoctorVersion']=ChecksDef['Check_XDoctorVersion']
PreChecksList['3.0HF1']['Application']['DisableXDoctorAlerting']=ChecksDef['DisableXDoctorAlerting']
PreChecksList['3.0HF1']['Application']['XDoctorHealthCheck']=ChecksDef['XDoctorHealthCheck']
PreChecksList['3.0HF1']['Application']['Check_ContainerHealth']=ChecksDef['Check_ContainerHealth']
PreChecksList['3.0HF1']['Application']['Check_FabricAgent']=ChecksDef['Check_FabricAgent']
PreChecksList['3.0HF1']['Application']['Check_DiskPartitions']=ChecksDef['Check_DiskPartitions']
PreChecksList['3.0HF1']['Application']['DisableBTreeGC']=ChecksDef['DisableBTreeGC']



PostChecksList['3.0']['OS']['Check_ContainerHealth']=ChecksDef['Check_ContainerHealth']
PostChecksList['3.0']['OS']['Check_FabricAgent']=ChecksDef['Check_FabricAgent']
PostChecksList['3.0']['OS']['Check_DiskPartitions']=ChecksDef['Check_DiskPartitions']
PostChecksList['3.0']['OS']['Check_XDoctorVersion']=ChecksDef['Check_XDoctorVersion']
PostChecksList['3.0']['OS']['XDoctorHealthCheck']=ChecksDef['XDoctorHealthCheck']
PostChecksList['3.0']['OS']['EnableDTLB']=ChecksDef['EnableDTLB']
PostChecksList['3.0']['OS']['EnablePXE']=ChecksDef['EnablePXE']
PostChecksList['3.0']['OS']['EnableXDoctorAlerting']=ChecksDef['EnableXDoctorAlerting']

PostChecksList['3.0HF1']['OS']=PostChecksList['3.0']['OS']

PostChecksList['3.0']['Application']['Check_ContainerHealth']=ChecksDef['Check_ContainerHealth']
PostChecksList['3.0']['Application']['Check_FabricAgent']=ChecksDef['Check_FabricAgent']
PostChecksList['3.0']['Application']['Check_DiskPartitions']=ChecksDef['Check_DiskPartitions']
#PostChecksList['3.0']['Application']['Check_UpgradeCompleteFlag']=ChecksDef['Check_UpgradeCompleteFlag']
PostChecksList['3.0']['Application']['Check_XDoctorVersion']=ChecksDef['Check_XDoctorVersion']
PostChecksList['3.0']['Application']['XDoctorHealthCheck']=ChecksDef['XDoctorHealthCheck']
PostChecksList['3.0']['Application']['EnableXDoctorAlerting']=ChecksDef['EnableXDoctorAlerting']

PostChecksList['3.0HF1']['Application']['Check_ContainerHealth']=ChecksDef['Check_ContainerHealth']
PostChecksList['3.0HF1']['Application']['Check_FabricAgent']=ChecksDef['Check_FabricAgent']
PostChecksList['3.0HF1']['Application']['Check_DiskPartitions']=ChecksDef['Check_DiskPartitions']
#PostChecksList['3.0']['Application']['Check_UpgradeCompleteFlag']=ChecksDef['Check_UpgradeCompleteFlag']
PostChecksList['3.0HF1']['Application']['Check_XDoctorVersion']=ChecksDef['Check_XDoctorVersion']
PostChecksList['3.0HF1']['Application']['XDoctorHealthCheck']=ChecksDef['XDoctorHealthCheck']
PostChecksList['3.0HF1']['Application']['EnableXDoctorAlerting']=ChecksDef['EnableXDoctorAlerting']
PostChecksList['3.0HF1']['Application']['EnableRepoGC']=ChecksDef['EnableRepoGC']


CurPathName=os.path.dirname(__file__)



# Initialize variables

CheckType=""



def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help       Show this help message and exit"
	print ""
	print "-O, --os          ECS OS upgrade"
	print "-A, --application ECS Application Software upgrade"
	print
	print "-s, --skipcheck   Comma-separated list of pre- or post-upgrade"
	print "                  health checks to skip"
	print "-v, --verbose     Enable verbose output"
	print "-V, --veryverbose Enable very verbose output"
	print "-l, --log         Log output to upgrade log"
	print
	print "-T, --topology <file>  Topology file name and location"
	print "-E, --extend <file>  Extension file name and location"

	exit (1)

def parse_args(argv):

	global CheckType,PreChecksList,PostChecksList,ChecksList

	result=parse_global_args(argv, req_version=True, req_upgradeType=True)


	if result is "usage":
		usage()

	# Additional script-specific option parsing

	try:
		opts, args = getopt.getopt(argv,common.allowedArgs['short'],common.allowedArgs['long'])
	except getopt.GetoptError:
		return("usage")

	for opt, arg in opts:
		if opt in ("--precheck"):
			# Perform checks in the precheck manifest
			CheckType="pre"
		elif opt in ("--postcheck"):
			# Perform checks in the precheck manifest
			CheckType="post"

	if CheckType=="":
		CheckType="pre"

	if CheckType=="post":
		# Assuming 3.0 for now
		ChecksList=PostChecksList[common.TargetVersion][common.upgradeType]
	else:
		ChecksList=PreChecksList[common.TargetVersion][common.upgradeType]



### Main logic

parse_args(sys.argv[1:])

if common.upgradeType=="Application":
	sku=get_sku()


msg_output(CheckType+"-upgrade health check v"+Version)
#msg_output(upgradeType)
msg_output()
msg_output("Initializing environment")
if common.upgradeType=="Application":
	msg_output("SKU: "+sku+"\n")


msg_output("Executing upgrade "+CheckType+"-checks:")
msg_output("")
for checknum, checkvals  in ChecksList.viewitems():
	checkname = checkvals['name']

	msg_output(checkvals['description']+" ("+checkname+")...", indent=1, do_newline=False)


	if checkname in common.skiplist:
		# User has specified this check to be skipped
		msg_output(bcolors.WARNING+"Skipped"+bcolors.ENDC)
		continue

	cmd=common.UpgradeRootPath+"/checks/"+checkname+".py"+common.argString # check commands are each called with the same args as this script received; many will be ignored

	output=run_cmd(cmd, noErrorHandling=True, indent=1, print_Verbose=False)
	sleep(0.3)

	if output['retval']==0:

		post_cmd_output(output)
		#msg_output(bcolors.OK+"OK"+bcolors.ENDC)

		# verbose output

		#msg_output("=================== Verbose output =====================", req_loglevel=1, indent=1)
		#msg_output(output['stdout'], req_loglevel=1, indent=1)
		#msg_output(output['verbose_stdout'], req_loglevel=1, indent=1)
	else:
		# XXX - not handling warning cases
		errstring="Please check this problem and re-run the health check.\n"
		errstring+="\n"
		errstring+="You can run this check manually by executing the 'checks/"+checkname+".py'\n"
		errstring+="script from the upgrade tools directory.\n"
		errstring+="\n"
		errstring+="If you've confirmed that this error and this check are safe to skip,\n"
		errstring+="you can re-run this script with --skipcheck "+checkname+"\n"
		errstring+="\n"
		errstring+="Exiting...\n"
		post_cmd_output(output, Failed=True, errortext=errstring, delay=3)

		exit(output['retval'])

		'''msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)
		err_output("FATAL:  Error while running check '"+checkname+"'")

		handle_cmd_error(output, NoExit=True)
		err_output("==========================================")
		err_output("Please check this problem and re-run the health check.")
		err_output()
		err_output("You can run this check manually by executing the 'checks/"+checkname+".py'")
		err_output("script from the upgrade tools directory.")
		err_output("")
		err_output("If you've confirmed that this error and this check are safe to skip, ")
		err_output("you can re-run this script with --skipcheck "+checkname+"")
		err_output("")
		err_output("Exiting...")
		exit (1)'''


