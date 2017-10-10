#!/usr/bin/python

# Copyright (c) 2016 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.

import subprocess
import sys
import os
import os.path
import re
import json
import glob
from subprocess import Popen, PIPE
from time import sleep,time,strftime
from collections import OrderedDict

import getopt

UpgradeRootPath=os.path.dirname(os.path.abspath(__file__+"/../"))

Version="0.9.9"
curdate=strftime("%Y-%m-%d")
#upgradeDesc="For upgrades to: ECS 3.0 Fabric/Object"
logfile="/opt/emc/caspian/upgrade/log/upgrade-"+curdate+".log"
BundleSourceDir=os.getenv("HOME") # Default dir containing the Installer package


# Upgrade state file - used to persist data across multiple upgrade attempts
# or multiple "steps" of the upgrade run during consecutive executions
upgrade_state_file="/tmp/_svc_upgrade.state"


# Initialize certain variables:
allowedArgs=dict()
state=dict()

verbose=0
Global_LogMessage=False
screen=True
upgradeType=None # Application or OS
upgradeMode=None # online or offline
TargetVersion=None
topologyfile=None
provisionfile="conf/provisioning.txt"
extendfile=None
appfile=None
lastCompletedTask=None
screen_session=None
OSCompletedNodes=None
OSInProgressNode=None
OSCompletedStep=None

argString=""
sku=None
skiplist=()
MACHINES=None

def changestate():
	state['upgradeType']="test2"


CurPathName=os.path.dirname(__file__)




# Initialize which tasks we're running and in which order, default to False
UpgradeTasks=OrderedDict()
'''UpgradeTasks['all']={
	'Enabled':False
}'''
UpgradeTasks['prechecks']={
	'Enabled':False,
	'FileName':'tasks/prechecks.py',
	'Description':'Prechecks'
}
UpgradeTasks['deploy']={
	'Enabled':False,
	'FileName':'tasks/deploy.py',
	'Description':'Deploy installer files'
}
UpgradeTasks['osupgrade']={
	'Enabled':False,
	'FileName':'tasks/osupgrade.py',
	'Description':'OS upgrade',
	'ErrorText':'OS Upgrade on one or more nodes has failed.  See error text above.\n\
\n\
After correcting the problem, OS upgrade can be retried by running:\n\
\n\
Rerun OS upgrade (refit) on all nodes:\n\
  svc_upgrade --OS --os --mode <online|offline> --version <version> [any other options]\n\
\n\
Rerun OS upgrade on individual nodes:\n\
  svc_upgrade --OS --os --node X --version <version> [any other options]'
}
UpgradeTasks['halupgrade']={
	'Enabled':False,
	'FileName':'tasks/halupgrade.py',
	'Description':'HAL upgrade'
}
UpgradeTasks['fabricupgrade']={
	'Enabled':False,
	'FileName':'tasks/fabricupgrade.py',
	'Description':'Fabric/Object upgrade'
}
UpgradeTasks['postchecks']={
	'Enabled':False,
	'FileName':'tasks/postchecks.py',
	'Description':'Postchecks'
}

UpgVersions=dict()
UpgVersions['2.2.1HF1']=dict()
UpgVersions['3.0']=dict()
UpgVersions['3.0HF1']=dict()

# ExpectedOS - OS versions allowed when starting the upgrade
# TargetOS - OS version after upgrade
# ExpectedInstaller - Installer package name expected to be installed when starting
#                     upgrade
# TargetInstaller - Installer version after upgrade
# TargetHAL/Object/Fabric - HAL/Object/Version version after upgrade
# InstallerFile - Name of the installer upgrade package file


UpgVersions['2.2.1HF1']['OS']={ # From/to versions for 2.2.1 HF1 upgrade
	'ExpectedOS':["2.2.0.0-1196.f7d8051.578", # 2.2.0 HF3
	              "2.2.1.0-1281.e8416b8.68", # 2.2.1 GA
	              "2.2.1.0-1309.3719890.88"], # 2.2.1 HF1
	'TargetOS':"2.2.1.0-1309.3719890.88",
	'ExpectedInstallers':["installer-1.2.0.1-2583.a52f534.x86_64", # 2.2.0 HF3
	                     "installer...", # 2.2.1 GA
	                     "installer-1.2.1.0-2668.6bfe00c.x86_64"], # 2.2.1 HF1
	'TargetInstaller':"installer-1.2.1.0-2668.6bfe00c.x86_64",
	'TargetHAL':"viprhal-1.2.1.0-1600.859252f.SLES.x86_64",
	'TargetObject':"2.2.1.0-77706.493e577",
	'TargetFabric':"1.2.1.0-2668.6bfe00c",
	'InstallerFile':"ecs-os-update-2.2.1.0-1309.3719890.88.zip"
}
UpgVersions['2.2.1HF1']['Application']={ # From/to versions for 2.2.1 HF1 upgrade
	'ExpectedOS':["2.2.1.0-1281.e8416b8.68", # 2.2.1 GA
	              "2.2.1.0-1309.3719890.88"], # 2.2.1 HF1
	'TargetOS':"2.2.1.0-1309.3719890.88",
	'ExpectedInstallers':["installer-1.2.0.1-2583.a52f534.x86_64", # 2.2.0 HF3
	                     "installer...", # 2.2.1 GA
	                     "installer-1.2.1.0-2668.6bfe00c.x86_64"], # 2.2.1 HF1
	'TargetInstaller':"installer-1.2.1.0-2668.6bfe00c.x86_64",
	'TargetHAL':"viprhal-1.2.1.0-1600.859252f.SLES.x86_64",
	'TargetObject':"2.2.1.0-77706.493e577",
	'TargetFabric':"1.2.1.0-2668.6bfe00c",
	'InstallerFile':"ecs-2.2.1.0-1682.d7baf9f.291-production*.tgz",
	'QuickFit':True
}
UpgVersions['3.0']['Application']={ # From/to versions for 3.0 upgrade
	'ExpectedOS':["3.0.0.0-1422.d46985b.663"], # 3.0 GA
	'TargetOS':"3.0.0.0-1422.d46985b.663",
	'ExpectedInstallers':["installer-1.3.0.0-3011.3d88791"], # 3.0 GA
	'TargetInstaller':"installer-1.3.0.0-3011.3d88791",
	'TargetHAL':"viprhal-1.5.0.0-1671.3e75053.SLES.x86_64",
	'TargetObject':"3.0.0.0-85770.a0edee9",
	'TargetFabric':"1.3.0.0-3009.6b1bd5b",
	'InstallerFile':"ecs-3.0.0.0-2398.9f9f451.582-production*.tgz",
	'QuickFit':False
}
UpgVersions['3.0']['OS']={ # From/to versions for 3.0 upgrade
	'ExpectedOS':["2.2.0...", # 2.2 HF3
				  "2.2.1.0-1281.e8416b8.68", # 2.2.1 GA
	              "2.2.1.0-1309.3719890.88", # 2.2.1 HF1
				  "3.0.0.0-1422.d46985b.663"], # 3.0 GA
	'TargetOS':"3.0.0.0-1422.d46985b.663",
	'ExpectedInstallers':"installer-1.3.0.0-3011.3d88791", # 3.0 GA
	'TargetInstaller':"installer-1.3.0.0-3011.3d88791",
	'TargetHAL':"viprhal-1.5.0.0-1671.3e75053",
	'TargetObject':"3.0.0.0-85770.a0edee9",
	'TargetFabric':"1.3.0.0-3009.6b1bd5b",
	'InstallerFile':"ecs-os-update-3.0.0.0-1422.d46985b.663.zip"
}
UpgVersions['3.0HF1']['OS']=UpgVersions['3.0']['OS'] # There's no different upgrade for 3.0 HF1.  Technically they are upgrading OS to 3.0.  But allow the user to supply the 3.0 HF1 keyword.

UpgVersions['3.0HF1']['Application']={ # From/to versions for 3.0 HF1 upgrade
    'ExpectedOS':["3.0.0.0-1422.d46985b.663"], # 3.0 GA
    'TargetOS':"3.0.0.0-1422.d46985b.663",
    'ExpectedInstallers':["installer-1.3.0.0-3024.09f2704"], # 3.0 HF1
    'TargetInstaller':"installer-1.3.0.0-3024.09f2704",
    'TargetHAL':"viprhal-1.5.0.0-1671.3e75053.SLES.x86_64",
    'TargetObject':"3.0.0.0-85770.a0edee9",
    'TargetFabric':"1.3.0.0-3024.09f2704",
    'InstallerFile':"ecs-3.0.0.0-2454.7cd04c8.635-production*.tgz",
    'QuickFit':False
}

# ANSI colors for colorizing text
# XXX - can I check that the terminal is capable first?  Is there a better way (curses, etc)?
class bcolors:
    HEADER = '\033[95m'
    OK = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


# XXX - Test_authentication global function (prompt for username/password if authentication fails)



def parse_global_args(argv, req_version=False, req_upgradeType=False, req_topology=False, req_upgradeMode=False):

	# Basic, global argument parsing generic to many scripts in the upgrade
	# suite.

	# If req_version or req_upgradeType are True, then require that the user
	# (or calling script) supply a version and/or upgradeType, presumably because
	# the script has different logic used depending on target version, or
	# type (OS or Application upgrade)

	# Returns a string indicating if argument check failed and the script's local
	# usage() should be displayed.

	global allowedArgs,UpgradeTasks,TargetVersion,UpgVersions,verbose,subargs,topologyfile,provisionfile,extendfile,appfile,screen,upgradeType,Global_LogMessage,argString,skiplist,upgradeMode,sku # Yes, I know this is a lot of globals

	allowedArgs['short']="hAOx:vVem:n:rtdolftaNls:T:P:E:Z:S:"
	allowedArgs['long']=["help","application","OS","os","version=","verbose","veryverbose","resume","mode=",
		"node=","precheck","postcheck","deploy","osupgrade","hal","fabric","all",
		"noscreen","log","skipcheck=","topology=","provision=","extend=","appfile=","sku=" ]

	try:
		opts, args = getopt.getopt(argv,allowedArgs['short'],allowedArgs['long'])
	except getopt.GetoptError:
		print ("Unknown option supplied")
		return("usage")

	# Check upgrade type (OS or Application)
	for opt, arg in opts:

		argString=argString+" "+opt
		if arg is not None and arg != "":
			argString=argString+" '"+arg+"'"

		if opt in ("-A", "--application"):
			upgradeType="Application"
		elif opt in ("-O", "--OS"):
			upgradeType="OS"

	if upgradeType is None and req_upgradeType==True:
		print "ERROR: Upgrade type must be specified"
		return("usage")



	# Other options

	for opt, arg in opts:
		if opt in ("-h", "--help"):
			return("usage")
		elif opt in ("-x", "--version"):
			TargetVersion=arg
		elif opt in ("-v", "--verbose"):
			verbose=1
		elif opt in ("-V", "--veryverbose"):
			verbose=2
		elif opt in ("-r", "--precheck"):
			UpgradeTasks['prechecks']['Enabled']=True
		elif opt in ("-d", "--deploy"):
			UpgradeTasks['deploy']['Enabled']=True
		elif opt in ("-o", "--os"):
			UpgradeTasks['osupgrade']['Enabled']=True
		elif opt in ("-l", "--hal"):
			UpgradeTasks['halupgrade']['Enabled']=True
		elif opt in ("-f", "--fabric"):
			UpgradeTasks['fabricupgrade']['Enabled']=True
		elif opt in ("-t", "--postcheck"):
			UpgradeTasks['postchecks']['Enabled']=True
		elif opt in ("-a", "--all"):
			if upgradeType is "OS":
				#UpgradeTasks['all']['Enabled']=True
				UpgradeTasks['prechecks']['Enabled']=True
				UpgradeTasks['deploy']['Enabled']=True
				UpgradeTasks['osupgrade']['Enabled']=True
				UpgradeTasks['postchecks']['Enabled']=True
			if upgradeType is "Application":
				#UpgradeTasks['all']['Enabled']=True
				UpgradeTasks['prechecks']['Enabled']=True
				UpgradeTasks['deploy']['Enabled']=True
				UpgradeTasks['osupgrade']['Enabled']=True
				UpgradeTasks['halupgrade']['Enabled']=True
				UpgradeTasks['fabricupgrade']['Enabled']=True
				UpgradeTasks['postchecks']['Enabled']=True
		elif opt in ("-m", "--mode"):
			if arg=="offline" or arg=="online":
				print "Setting upgradeMode to "+arg
				upgradeMode=arg
			else:
				return("usage")
		elif opt in ("-N", "--noscreen"):
			# Do not spawn inside a screen session
			screen=False
		elif opt in ("-s", "--skipcheck"):
			if len(skiplist) > 0:  # User has specified multiple skipcheck options
				skiplist=skiplist+arg.split(',')
			else:
				skiplist=arg.split(',')
		elif opt in ("-T", "--topology"):
			topologyfile=arg
		elif opt in ("-P", "--provision"):
			provisionfile=arg
		elif opt in ("-E", "--extend"):
			extendfile=arg
		elif opt in ("-Z", "--appfile"):
			appfile=arg
		elif opt in ("-S", "--sku"):
			sku=arg
		elif opt in ("-l", "--log"):
			Global_LogMessage=True
		elif opt in ("-A", "--application") or opt in ("-O", "--OS") or opt in ("-n", "--node") or opt in ("-e", "--resume"):
			continue
		else:
			return("usage")

	# Validate options

	if UpgradeTasks['halupgrade']['Enabled'] or UpgradeTasks['fabricupgrade']['Enabled'] or (upgradeType=="Application" and UpgradeTasks['prechecks']['Enabled']):
		if topologyfile is None:
			err_output("ERROR:  Must supply a topology file when performing Application upgrade")
			return("usage")
	if UpgradeTasks['halupgrade']['Enabled'] or UpgradeTasks['fabricupgrade']['Enabled'] or UpgradeTasks['osupgrade']['Enabled']:
		if upgradeMode is None:
			err_output("ERROR:  Must supply an upgrade mode (online or offline)")
			return("usage")
		if (not upgradeMode == "online" and not upgradeMode == "offline"):
			err_output("ERROR:  Specified upgrade mode '"+upgradeMode+"' is invalid.  Supported options are 'online' or 'offline'")
			return("usage")

	# Check to see that the user has specified a supported version
	foundVers=False
	SupportedVersString=""
	for loopVers in UpgVersions:  # i.e. "3.0", "3.0 HF1", etc
		SupportedVersString=SupportedVersString+"  "+loopVers+"\n"
		if loopVers == TargetVersion:
			foundVers=True

	if foundVers == False:
		if TargetVersion is None:
			print "ERROR:  No target version was specified (--version option)."
		else:
			print "ERROR:  Specified target version ("+TargetVersion+") is not supported by this utility."
		print "Supported versions are:"
		print SupportedVersString
		print
		return("usage")


	# For now assume all upgrades are for 3.0 HF1 and don't require the arg:

	#TargetVersion="3.0 HF1"


def check_provision_file():

	if provisionfile == None or provisionfile=="":
		err_output("ERROR:  No provision file defined, cannot read.")
		exit(20)

	print "checking prov file "+provisionfile

	if os.path.isfile("/opt/emc/caspian/installer/"+provisionfile):
		prov_abs_path="/opt/emc/caspian/installer/"+provisionfile
	elif os.path.isfile(provisionfile):
		prov_abs_path=provisionfile
	else:
		err_output("ERROR:  Provision file does not exist or is not a file.")
		err_output("  Please specify a valid file with the --provision option")
		exit(21)

	return prov_abs_path



def get_sku():
	global CurPathName,sku

	# Call svc_sku script, handle results gracefully
	#print "This is a sku test!"

	if (sku==None): # sku hasn't already been specified, typically by the user
		output=run_cmd(UpgradeRootPath+"/tools/svc_sku", noErrorHandling=True)

		if output['retval'] != 0:
			err_output("ERROR:  Unable to auto-detect sku.")
			err_output("Output from svc_sku was:")
			err_output("")
			err_output(output['stdout'])
			err_output("")
			err_output("Check that this is running from the installer node and that,")
			err_output("installer logs exist.  Otherwise, manually specify a sku")
			err_output("with the --sku option")

			exit(19)

		# Error handling

		sku=output['stdout'].strip()

	# SKU should be defined in the current provision file - if not, then it's undefined and
	# invalid.

	# SKU could be in the format "U400", "U2000x2", "R730xd_8n", etc.

	# Not current validating that the SKU matches the current config, but at least validate it
	# looks like a valid SKU and not nonsense.

	ValidSKU=True

	# Get the various SKU names from the provision file.  Should return output like:
	# [U3000]
	# [U3000x2]
	# [U3000x3]
	# [U3000x4]
	# ...
	# [D6200x2]
	# [R730xd_8n]
	# [DSS7000_8n]
	# [SL4540_8n]
	# [DL380_8n]

	abs_prov_file=check_provision_file()
	cmd='cat "'+abs_prov_file+'" | awk \'{ print $1 }\' | grep -e ^\\\['

	# XXX - this assumes that the SKU name will always be enclosed in brackets at the start of
	# the line (although white space is stripped here) - will there be other cases?

	output=run_cmd(cmd)

	if not "["+sku+"]" in output['stdout']:
		ValidSKU=False


	if not ValidSKU:
		err_output("ERROR: get_sku():  SKU does not appear valid.  Value is '"+sku+"'.")
		err_output("  Could not find matching sku definition in '"+abs_prov_file+"'")
		exit(20)


	# XXX - do additional checking.  Does the SKU match what we see as the
	#   current config?

	return sku


def get_machines(force=False, ignoreChecks=False):
	# Get the current MACHINES list.
	#
	# This may have been provided by the user (or in a file provided by the user),
	# or automatically retrieved and cached.
	#
	# If the MACHINES list is not cached, or if "force" flag is set (forcing lookup),
	# perform an automatic "lookup" by running getrackinfo -c and parsing the result.
	#
	# Return as a List with one entry per machine

	global MACHINES

	if MACHINES is None or force==True:

		# Query the list of MACHINES in the current rack from the system.

		# First, create the machines file

		# XXX - is there any way to avoid doing a disk write?  Do we need to check to make sure that we can create a file?

		output=run_cmd("sudo getrackinfo -c /tmp/MACHINES")

		# XXX - how can we be sure the file was created successfully?  Is getrackinfo reliable enough to error out?

		MACHINES=list(open("/tmp/MACHINES"))
		with open("/tmp/MACHINES",	'rb') as f:
			MACHINES=f.readlines()

		if MACHINES[0].startswith("# List of private network IPs"):
			del MACHINES[0]

		# Clean whitespace and things from the entries
		MACHINES = [re.sub('\n','',line) for line in MACHINES]


		# Sanity checks.  Skip checks if user has specified to ignore them.

		# MACHINES list may be returned incorrectly if, say, a node is offline, or
		# for other reasons.

		# Currently assume that a "healthy" system has 4-8 nodes.  This may change
		# with future systems, will need to determine a better way to ensure we have
		# the list of every configured node.

		# XXX - need to be able to get the list of all configured nodes in the VDC

		if not ignoreChecks:
			checksPassed=True
			errortext=""

			# Ensure that the list has either 4 or 8 nodes (currently supported configs in
			# a single rack )

			if not (len(MACHINES)==4 or len(MACHINES)==8):
				checksPassed=False
				errortext+="ERROR: MACHINES list size is incorrect.  Expected 4 or 8,\n"
				errortext+="  list contains '"+str(len(MACHINES))+"' entries\n"
			for MACHINE in MACHINES:
				if not "192.168.219." in MACHINE:
					checksPassed=False
					errortext+="ERROR: Entry in MACHINE list is invalid.  Only private\n"
					errortext+="  network IPs are supported.  Expected '192.168.219.x',\n"
					errortext+="  got "+MACHINE+"\n"

			if not checksPassed:
				errortext+="\n"
				errortext+="This may indicate that getrackinfo -c produced an incorrect list,\n"
				errortext+="  that nodes are offline or unreachable, that a filesystem is full,\n"
				errortext+="  or the current configuration is unsupported by the script.\n"
				errortext+="If you believe this is safe to continue, run this script again\n"
				errortext+="  with the --ignoreMachineChecks flag set.\n"
				err_output(errortext)
				exit(18)

		else:
			msg_output("Skipping MACHINES sanity check", req_loglevel=1)

		# End sanity checks

		# XXX - reminder that once we expand to letting the user provide a custom
		#       MACHINES file, do serious sanity checking; we don't want to use a MACHINES
		#       list that specifies systems outside the current VDC, public IPs, etc

	return MACHINES

def get_first_node(MACHINES=None):

	NODES=get_nodenums(MACHINES)

	firstnode=24

	for NODE in NODES:
		if int(NODE) < firstnode:
			firstnode=int(NODE)

	return firstnode


def get_nodenums(MACHINES=None):

	if MACHINES is None:
		MACHINES=get_machines()

	# If the MACHINE addresses are internal IPs, assume the node numbers are
	# the last octet in the IP (i.e. 192.168.219.5 is node 5

	NODES=[]
	for MACHINE in MACHINES:
		if "192.168.219." in MACHINE:
			octets=MACHINE.split(".")
			NODES.append(octets[3])

	return NODES

def get_nodenum(MACHINE):

	if "192.168.219." in MACHINE:
		octets=MACHINE.split(".")
		nodenum=octets[3]

		return nodenum

	else:
		err_output("ERROR: get_nodenum():  Invalid MACHINE provided: '"+MACHINE+"'")
		exit(8)

def get_local_private_IP():

	result=run_cmd("sudo ifconfig private | grep 'inet addr' | awk -F: '{ print $2 }' | awk '{ print $1 }' | head -1")
	local_private_IP=result['stdout'].strip()

	if not "192.168.219." in local_private_IP: # Sanity check that the string we got looks valid.  XXX - won't work with private networks that have been changed from default - is a problem?

		err_output("ERROR:  Could not determine local private IP address.")
		err_output("Expected value in format '192.168.219.x', received '"+local_private_IP+"'")
		err_output("Exiting...")
		exit(7)

	return local_private_IP

def get_IPMI_IP(MACHINE):

	if "192.168.219." in MACHINE:
		# Hack until confirm a better way to determine IPMI address:
		MACHINE=MACHINE.replace('192.168.219.','192.168.219.10')

		return MACHINE
	else:
		err_output("ERROR: get_IPMI_IP():  Invalid MACHINE provided: '"+MACHINE+"'")
		exit(9)

def encapsulate_shell_cmd(cmd):
	return(cmd.replace("'", "'\\''"))


"""
def do_rest_cmd
  # Call svc_rest_cmd script, pass auth info etc, handle results gracefully

def do_json_cmd
  # Call svc_json_cmd script, pass auth info etc, handle results gracefully
"""



def run_cmd(command, printText="", printComplete=False, noErrorHandling=False, showWarnings=True, indent=0, realtime=False, do_LogMessage=False, no_LogMessage=False, print_Verbose=True, MACHINE=None, timeout=None, Container=False, do_sudo=False):
  # Run commands and return the results.

  # By default, if a run command encounters an error, we will attempt to process it (call
  # handle_cmd_error()), which typically leads to the script immediately exiting with
  # an error (potentially causing calling scripts to do the same).
  # Some callers may prefer to do their own error handling, so this can be disabled.

  # Will pass through "showWarnings" and "indent" options to handle_cmd_error() and
  # msg/err_output(), respectively.

  # By default, we will execute the command synchronously - we will stop, wait for it to
  # exit, and resume processing when it does.
  # Caller can specify "realtime" execution - we will print stdout and stderr in "real time"
  # (or close to it).  This is usually used when a calling script wants to see and/or display
  # the output of a child script immediately.  For example, when svc_upgrade calls task scripts
  # (precheck script, osupgrade script, etc).  Or when user is viewing verbose output of fabric
  # upgrade (Can print the output of refit as it runs, otherwise we would appear to just hang
  # for an hour and a half.
  # Currently there's a limitation with "realtime mode" where it may not print stderr output
  # in the order it was generated - we may print stdout lines before we print stderr lines generated
  # by the called command.

  # Returns a Dict with a number of attributes, including:
  # ['stdout'] and ['stderr'] - stores complete output of, well, stdout and stderr returned
  # ['retval'] - return value of executed command
  # ['command'] - Full command executed (potentially useful if this package gets passed
  #   between functions
  # ['realtime'] - whether or not the command was executed in "realtime" mode, so output was
  #   already printed to stdout/stderr

  # XXX - Use subprocess.run() timeout value.  Should caller be able to specify the timeout or should we just use a global failsafe default?  Probably both.

  # XXX - Well, that'd be nice, except of course that didn't show up until python 3, and we're on 2.7.9.
  # Another option for handling indefinitely running commands??  And how do we define the timeout?


	global Global_LogMessage
	global verbose
	global UpgradeRootPath

	cmdFailed=False
	verboseval=""
	veryverboseval=""
	errorval=""

	sudoicmd=get_sudoicmd()

	if MACHINE is not None: # We're executing against a remote node
		ContainerOption=""
		if Container: # Run inside the container
			ContainerOption="-c "
		command=UpgradeRootPath+'/tools/viprexec-upgrade '+ContainerOption+'-n '+MACHINE+' \''+command+'\''

	if timeout is not None: # We want to time out the command after a given amount of time
		command=" timeout --kill-after=10 "+str(timeout)+" sh -c '"+encapsulate_shell_cmd(command)+"'"

	if do_sudo:
		command=sudoicmd+" "+command

	if printText != "":
		# When running the command, we're going to print an output like
		#   "Checking for version of Node..."
		# which will be followed later by "DONE" or "FAILED".
		msg_output(printText, no_LogMessage=no_LogMessage, do_newline=False)

		if printComplete:
			# We're going to be printing a colorized "DONE" or "FAILED" once the
			# command completes, followed by error and verbose text (if any)
			temp=1

		else:
			# We're being asked not to print/log completion info or error/verbose info
			# at this time.  This will be printed later after parsing the output.
			no_LogMessage=True
			print_Verbose=False
			noErrorHandling=True

		verboseval+=msg_output("\nCommand run: "+command, indent=indent, no_LogMessage=True, print_Text=False)
	else:
		msg_output("\nCommand run: "+command, indent=indent, req_loglevel=1, no_LogMessage=no_LogMessage, print_Text=print_Verbose)




	if realtime:
		print_Verbose=False


	p = Popen(command, shell=True, stdout=PIPE, stderr=PIPE, bufsize=1)
	#print p.communicate()
	#
	stdout=""
	stderr=""

	if realtime:
		while True:
			out = p.stdout.read(1)
			if out == '' and p.poll() != None: # p.poll checks if process has terminated
				break
			if out != '':
				stdout=stdout+out
				msg_output(out, do_newline=False, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, indent=indent)
		# means stderr will always be included after stdout...hmmm
		while True:
			err = p.stderr.read(1)
			if err == '' and p.poll() != None:
				break
			if err != '':
				stderr=stderr+err

		# Printing full message to work around an issue with ANSI colorizing sequences.
		# Process has already terminated by this point so we don't need to print as we
		# read, loop will read the complete buffer before termminating
		err_output(stderr, do_newline=False, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, indent=indent)


		retval=p.poll()

	else:
		stdout, stderr = p.communicate()
		retval = p.returncode

	if MACHINE is not None:
		stdout=stdout.replace("\nOutput from host : "+MACHINE+" \n",'')

	# Very verbose messages:

	veryverboseval+=msg_output("=================== Verbose output =====================", indent=indent, no_LogMessage=True, print_Text=False)
	veryverboseval+=msg_output("Return value: "+str(retval), indent=indent, no_LogMessage=True, print_Text=False)
	veryverboseval+=msg_output("Command output:", indent=indent, no_LogMessage=True, print_Text=False)
	veryverboseval+=msg_output(stdout, indent=indent+1, no_LogMessage=True, print_Text=False, do_newline=False)

	# If errors were returned - stderr was non-zero and there was output text:
	if isinstance(stderr, basestring) and stderr != "":
		cmdFailed=True
		errorval+=msg_output("stderr:", indent=indent, no_LogMessage=True, print_Text=False)
		errorval+=msg_output(stderr, indent=indent+1, no_LogMessage=True, print_Text=False, do_newline=False)


	# create return Dictionary
	cmd_output = {'command':command,
				 'stdout':stdout,
	             'stderr':stderr,
				 'retval':retval,
				 'realtime':realtime,
				 'verbose_out':verboseval,
				 'veryverbose_out':veryverboseval,
				 'error_out':errorval,}

	# print "DONE" or "FAILED", if applicable:
	if printText != "" and printComplete:
		if not cmdFailed:
			msg_output(bcolors.OK+"DONE"+bcolors.ENDC)
		else:
			msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)

	# Print verbose and error outputs to screen and log, unless surpressed

	if verboseval.strip() != "" or veryverboseval != "":
		#msg_output("=================== Verbose output =====================", do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, print_Text=print_Verbose, req_loglevel=1)
		msg_output(verboseval, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, print_Text=print_Verbose, req_loglevel=1, do_newline=False)
		msg_output(veryverboseval, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, print_Text=print_Verbose, req_loglevel=2, do_newline=False)
	if cmdFailed:
		if noErrorHandling:
			msg_output(errorval, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, print_Text=print_Verbose, req_loglevel=2)
		else:
			msg_output(errorval, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, print_Text=print_Verbose, req_loglevel=2)


	if noErrorHandling==False:
		handle_cmd_error(cmd_output, showWarnings=showWarnings)

	return cmd_output


def handle_cmd_error(cmd_output, showWarnings=True, NoExit=False):

	command=cmd_output['command']
	retval=cmd_output['retval']
	stdout=cmd_output['stdout']
	stderr=cmd_output['stderr']

	if retval != 0: # Non-zero return code, command was not successful

		# XXX - use err_output?

		err_output("ERROR: While executing command '"+command+"'\n")

		if retval==124:
			err_output("Error 124: Command timed out\n")
		else:
			err_output("Return code was: "+str(retval)+"\n")

		if isinstance(stdout, basestring) and stdout != "":
			err_output("Command output:\n")
			err_output(stdout+"\n")
		else:
			err_output("No output returned.\n")

		if isinstance(stderr, basestring) and stderr != "":
			err_output("Error text returned:\n")
			err_output(stderr+"\n")
		else:
			err_output("No error text returned.\n")

		if NoExit==False:
			# At this point, exit due to an unrecoverable error - user will need to correct something before
			# continuing
			err_output ("EXITING...\n")

			exit (1)     # XXX - Should it be an error related to the calling command's return code?
	elif isinstance(stderr, basestring) and stderr != "" and showWarnings: # Command completed but error output was returned
		# XXX - Should I assume it's a warning?  Or look for the "WARNING" keyword in output?  Or...
		err_output("Warning:  While executing command '"+command+"'\n")
		err_output("Output generated: \n"+stderr+"\n")

		# XXX - Should we pause to ask if they want to continue at this point?





def run_multi_cmd(command, MACHINES=None, Container=False, do_LogMessage=False, no_LogMessage=False, print_Verbose=True, noErrorHandling=False):
	# Run a command against every node using viprexec.

	# If no MACHINES list is passed, will attempt to generate one.

	# Optionally can specify whether or not to run commands inside the object container.

	# To make it easy to parse results into an organized Dict, runs viprexec one at a time.
	# This is slower than running in parallel, potentially a lot - future enhancement
	# may be to deal with running commands in parallel

	# Returns a Dict of run_cmd results, with the MACHINE name (IP address) as a key for each
	# entry.

	OutputList=dict()

	if MACHINES is None:
		MACHINES=get_machines()

	for MACHINE in MACHINES:

		output=run_cmd(command, MACHINE=MACHINE, Container=Container, do_LogMessage=do_LogMessage, no_LogMessage=no_LogMessage, print_Verbose=print_Verbose, noErrorHandling=noErrorHandling)
		'''ContainerOption=""
		if Container:
			ContainerOption="-c "
		viprcmd='viprexec '+ContainerOption+'-n '+MACHINE+' \''+command+'\''

		output=run_cmd(viprcmd, do_LogMessage=False, no_LogMessage=False, print_Verbose=print_Verbose)

		output['stdout']=output['stdout'].replace("\nOutput from host : "+MACHINE+" \n",'')
		#output['stdout']=output['stdout'].replace("Output from host",'')'''


		OutputList[MACHINE]=output


	return OutputList


def msg_output(text="", req_loglevel=0, indent=0, do_newline=True, do_LogMessage=False, no_LogMessage=False, print_Text=True):

	global verbose
	global Global_LogMessage

	# Output runtime text to various locations (screen and logfile)

	# - Whether output is displayed to screen depends on the passed req_loglevel
	#   and the current verbosity level (global "verbose" var)
	# - Caller can specify whether the message will be added to the running logfile.
	#   This can be specified with a global (which defaults to true), or overridden
	#   (defaults to false)
	# XXX - need a better way to have a global logmessage setting, but be able to override
	#   it either positively or negatively on a per-message basis
	#
	# - All verbose output always goes to debug logfile, if enabled

	# - Output can include an optional "indent" argument that can indent text
	#   by a certain amount

	# - Allow optional argument, "do_newline" to define whether the string should
	#   have a newline appended.  Default is True

	# - Optionally return verbose output as part of the return array instead of printing it to
	#   the screen/log


	padding = indent * '    ' # 4 spaces per indent

	text=padding + ('\n'+padding).join(text.split('\n'))  # add indentation to incoming string

	if do_newline:
		text+="\n"

	# XXX - this isn't confusing...
	if (do_LogMessage or Global_LogMessage and not no_LogMessage):
		log_message(text)

	if print_Text: # Print text to the screen
		if req_loglevel <= verbose:  # loglevel of this message is low enough to print to the screen

			sys.stdout.write(text)
			sys.stdout.flush() # Otherwise output may not be sent immediately

	return text



def err_output(text="", req_loglevel=0, indent=0, do_newline=True, do_LogMessage=False, no_LogMessage=False, return_Text=False):

	# XXX - collapse this together with msg_output and make err output an argument?

	global verbose
	global Global_LogMessage

	padding = indent * '    ' # 4 spaces per indent

	text=padding + ('\n'+padding).join(text.split('\n'))  # add indentation to incoming string

	if do_newline:
		text+="\n"

	if (do_LogMessage or Global_LogMessage) and not no_LogMessage:
		log_message(text)

	if not return_Text:
		if req_loglevel <= verbose:  # loglevel of this message is low enough to print to the screen

			sys.stderr.write(bcolors.FAIL+text+bcolors.ENDC)
			#sys.stderr.write(text)
			sys.stderr.flush() # Otherwise output may not be sent immediately
	else: # return instead of printing
		return text


def printDone():
	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

def printFailed():
	msg_output(bcolors.FAIL+"FAILED"+bcolors.ENDC)


def post_cmd_output(output, Failed=False, errortext=None, indent=0, delay=0):
	# When we run various tasks, we want to display to the screen/log in format:
	#   "Running some operation...DONE"
	#   "  <verbose text, if applicable>"
	# or
	#   "Running some operation...FAILED"
	#   "  <verbose text, if applicable>"
	#   "  <error text>"
	#
	# We frequently won't know whether the operation has completed or failed until after
	# we've run the command and processed the results.
	#
	# In these cases, we need to postpone printing out any verbose info or error output
	# until after printing "DONE" or "FAILED" - so can't do it inside run_cmd().
	#
	# This function takes the output of run_cmd, and depending on "Failed" flag,
	# prints out a colorized "DONE" or "FAILED", followed by any error text
	# and verbose info.

	# Remember string potentially already comes in indented

	if not Failed:
		printDone()
	else:
		printFailed()
		sleep(delay) # If specified, delay between printing "failed" and printing the
		             # (potentially very verbose) error message.  Usability thing to
					 # give the user a chance to register that an error happened before
					 # flooding the screen with output

	#msg_output("=================== Verbose output =====================", req_loglevel=1, indent=indent)
	if str(output['verbose_out'].strip()) != "":
		msg_output(output['verbose_out'], req_loglevel=1, indent=indent)
	if str(output['veryverbose_out'].strip()) != "":
		msg_output(output['veryverbose_out'], req_loglevel=2, indent=indent)

	if Failed:
		err_output("=================== Fatal Error =====================", indent=indent)
		err_output("Return value: "+str(output['retval']), indent=indent)
		err_output(output['error_out'], indent=indent)
		err_output("==========================================\n", indent=indent)
		err_output(errortext, indent=indent)




def log_message(msg):

	# Logs messages to, well, the global logfile.

	global logfile

	if not os.path.isfile(logfile):
		if os.path.exists(logfile):
			err_output("ERROR: Log file at \""+logfile+"\" exists but is not a file.", no_LogMessage=True)
			err_output("Exiting...", LogMessage=False)
			exit(200)

		# Log file doesn't exist and needs created.  Check if parent directory exists, if not
		# try to create

		logparent=os.path.dirname(logfile)

		if not os.path.exists(logparent):
			# Attempt to create the log directory and any intermediate directories.
			# Since we'll likely need to be root to do this, use shell and sudo command

			cmd="sudo mkdir -m 755 -p '"+logparent+"'"

			result=run_cmd(cmd, no_LogMessage=True)


		# Check/change permissions of log dir if needed
		dirstats=os.stat(logparent)

		cmd="sudo chmod 777 '"+logparent+"'"

		result=run_cmd(cmd, no_LogMessage=True)


	# Create message

	#   Get current timestamp
	Cur_Timestamp=strftime("%Y-%m-%d %H:%M:%S  ")

	#   Prepend timestamp to each line of the incoming string
	#   XXX - may need to revisit for realtime commands
	msg=('\n'+Cur_Timestamp).join(msg.split('\n'))
	#msg=('\n'+Cur_Timestamp).join(msg.split('\n'))

	# Write to logfile!
	f = open(logfile,'a+')
	f.write(msg)
	f.close()

	# Check/change permissions of log file if needed

	cmd="sudo chmod 777 '"+logfile+"'"


def copy_to_nodes(file, targetdir, tmpdir="/var/tmp", MACHINE=None, skipcurrent=False, container=False):

	# Copy file to one or all nodes.

	# If a MACHINE IP has been specified, copy only to that node.  Otherwise,
	# copy to all nodes.
	# If copying to all nodes, optionally skip the current node.

	# Optionally, copy the file to the object-main container on that node(s).
	# If copying to object-container, optionally specify the tempoary directory on
	#   the node to use while copying the file (default is /var/tmp).
	# That is, if container=True and tmpdir="/var/tmp", and targetdir=/opt/storageos/bin,
	# then the file will first be copied to MACHINE:/var/tmp/file.  Then moved
	# from MACHINE:/var/tmp/file to MACHINE:Object-main:/opt/storageos/bin/file


	if MACHINE is None:
		MACHINES=get_machines()
	else:
		MACHINES=[MACHINE]

	basefile=os.path.basename(file)


	# Check if source file exists

	if not os.path.isfile(file):
		err_output("ERROR:  copy_to_nodes():  Source file '"+file+"' not found or is not a file.")
		exit (6)

	# get md5sum of file


	for CURMACHINE in MACHINES:

		# Check if destination dir exists on each node before copying to any

		result=run_cmd('[[ -d '+targetdir+' ]] && echo dir found', MACHINE=CURMACHINE, Container=container)

		if not result['stdout'].strip() == "dir found":
			err_output("ERROR:  copy_to_nodes():  Target directory '"+targetdir+"' not found or is not")
			err_output("  a directory.")
			if container == True:
				err_output("Target:  '"+MACHINE+":object-main:"+targetdir+"'")
			else:
				err_output("Target:  '"+MACHINE+":"+targetdir+"'")

			exit (7)

	if container:

		for CURMACHINE in MACHINES:
			# Check if tmpdir exists

			result=run_cmd('[[ -d '+tmpdir+' ]] && echo dir found', MACHINE=CURMACHINE, Container=False)
			if not result['stdout'].strip() == "dir found":
				err_output("ERROR:  copy_to_nodes():  Temporary directory '"+tmpdir+"' not found or is not")
				err_output("  a directory.")

	for CURMACHINE in MACHINES:
		# Copy the file to nodes

		if not container:
			DestDir=targetdir
		else:
			DestDir=tmpdir

		result=run_cmd("viprscp -n "+CURMACHINE+" "+file+" "+DestDir+"/"+basefile)

		# Check md5sum

		if container:
			# Move to final destination

			run_cmd("docker cp "+DestDir+"/"+basefile+" object-main:"+targetdir+"/"+basefile, MACHINE=CURMACHINE)

			# Check md5sum

			# Remove original

			run_cmd("rm -f "+DestDir+"/"+basefile, MACHINE=CURMACHINE, no_LogMessage=True)



def get_sudoicmd():

	# By default when running "sudo -i", warnings are returned to stderr because
	# there's no default value for the LC_ALL and LANG environment variables.

	# Return a string that allows sudo -i to be run with those variables defined,
	# eliminating the warning.

	# XXX - need to make sure we're getting the correct values instead of this hardcode hack

	LC_ALL="en_US.UTF-8"
	LANG="en_US.UTF-8"

	sudoicmd="sudo -i LANG="+LANG+" LC_ALL="+LC_ALL+" "

	return(sudoicmd)

def parse_md5sums(filename):

	# Given an MD5SUMS file, read the file and parse the entries.
	# Returns a List with keys as filename, values as md5sum

	MD5SUMS=dict()
	lines = [line.rstrip('\n') for line in open(filename)] # read lines, strip trailing newline

	msg_output("Parsing md5sum file "+filename, indent=1, req_loglevel=2)

	for line in lines:
		msg_output("Got line '"+line+"'", indent=2, req_loglevel=2)
		words=line.split()

		if words[0] is not None and words[0] != "" and words[1] is not None and words[1] != "":
			#msg_output("MD5SUMS["+words[1]+"]="+words[0])
			MD5SUMS[words[1]]=words[0]
		else:
			err_output("ERROR:  md5sum file '"+filename+"' does not appear valid.  Exiting.")
			exit (5)

	return MD5SUMS


def setLoadBalanceMode(mode, MACHINE=None):

	global UpgradeRootPath

	if mode == "enable":
		ActionString="Enabling"
	elif mode == "disable":
		ActionString="Disabling"
	else:
		err_output("ERROR: setLoadBalanceMode():  Invalid mode '"+mode+"'")
		exit(21)

	lbscript=UpgradeRootPath+"/tools/setLoadBalanceEnabled"

	if MACHINE==None:
		MACHINES=get_machines()
		msg_output(ActionString+" Directory Table Load Balancing on all nodes...", do_newline=False)
	else:
		MACHINES=[MACHINE]
		msg_output(ActionString+" Directory Table Load Balancing on "+MACHINE+"...", do_newline=False)


	for MACHINE in MACHINES:
		# Copy script to /var/tmp in container on all nodes

		copy_to_nodes(lbscript, "/var/tmp/", MACHINE=MACHINE, container=True)

		run_cmd("chmod 755 /var/tmp/setLoadBalanceEnabled", MACHINE=MACHINE, Container=True)

		run_cmd("/var/tmp/setLoadBalanceEnabled "+mode, MACHINE=MACHINE, Container=True)

		# XXX - Validate LB is disabled

	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)


def check_installer_file(sourcedir, UpgDetails):
	# Check whether the installer bundle exists.

	# Different filenames depending on OS type and version.
	# For application there are also two bundle types:  DaRE and non-DaRE.
	# We look for either bundle name (which start with the same string) and
	#   return the name we found.  If multiples exist (should not exist, since
	#   it means we don't know whether we're installing DaRE or non-DaRE, then
	#   we fail.


	InstallerFullPath = sourcedir+"/"+UpgDetails['InstallerFile']

	msg_output("Checking for upgrade bundle file'"+InstallerFullPath+"'...", do_newline=False)

	InstallerFileList=glob.glob(InstallerFullPath)  # Should return a list containing the file name(s)
													# present in the source dir.

	if len(InstallerFileList) is 0:
		err_output("\nERROR: No installer files named '"+InstallerFullPath+"' exists")
		err_output("")
		err_output("Please check that the installer files have been moved to the current user's home")
		err_output("  directory.")
		err_output("EXITING...")
		exit (103)
	elif len(InstallerFileList) > 1:
		err_output("\nERROR: Ambiguous installer file name:  '"+InstallerFullPath+"'.")
		err_output("")
		err_output("  multiple matches exist:")
		err_output("")
		for FileName in InstallerFileList:
			err_output("  "+FileName)

		exit (104)
	else:
		# InstallerFileFull - final full name of the installer package archive
		#   (e.g. "/home/admin/ecs-3.0.0.0-2398.9f9f451.582-production.tgz")
		InstallerFileFull=InstallerFileList[0]

	#XXX - check that we can read from it?

	msg_output(bcolors.OK+"DONE"+bcolors.ENDC)

	return InstallerFileFull

def get_listen_ip(port, servicename=None):
	if servicename==None:
		msg_output("Getting listener IP for port "+str(port), req_loglevel=1, indent=1)
	else:
		msg_output("Getting listener IP for "+servicename+" (port "+str(port)+")", req_loglevel=1, indent=1)


	# test for 2.2 localhost style
	cmd="sudo netstat -an | grep LISTEN | grep ':"+str(port)+"'"
	result=run_cmd(cmd)

	if ":::"+str(port) in result['stdout']:
		return("localhost")


	cmd="sudo netstat -an | grep LISTEN | grep ':"+str(port)+" ' | awk -F: '{ print $1 }' | awk '{ print $4 }' | head -1"
	result=run_cmd(cmd)

	listen_IP=result['stdout'].strip()

	# Validate the value we got looks like an IP address:

	pat = re.compile("^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")
	if not pat.match(listen_IP):
		return None
	else:
		return listen_IP




def check_dt_ready():


	dt_req_timeout=15*60 # Time to wait (in seconds) for a DT request to return.
	                     # Assume if we haven't heard back in this amount of time
						 # that the request is hung, not just slow.
	dt_total_timeout=dt_req_timeout*2 # Time to wait total for DTs to come ready
	                     # Ensure that we make at least 2 DT requests; at least 2 have to
						 # be run before we fail.  If we're getting dtquery responses
						 # and DTs just aren't ready, will make more than 2 passes
						 # 30 minutes, in this case.

	retry_delay=15 # delay until next retry
	dtready=False

	# Get IP that dtquery is listening on (tcp port 9101) on local node

	msg_output("Checking DT initialization status (please wait)...", do_newline=False)


	# Run the dtquery

	msg_output("\nWaiting up to "+str(dt_total_timeout/60)+" minutes for DTs to come ready", req_loglevel=1)

	dtquery_results=dict.fromkeys(["total_dt_num","unready_dt_num","unknown_dt_num"], None)
	dtquery_start=int(time())
	firstpass=True

	dt_listen_IP=None


	while int(time()) < (dtquery_start + dt_total_timeout): # Retry to see if DTs come ready

		# Get the IP we're listening for dtquery info on, if needed
		if dt_listen_IP == None:
			dt_listen_IP=get_listen_ip(9101, servicename="dtquery service")

		if dt_listen_IP == None:
			sleep (retry_delay)
			continue



		if firstpass:
			tempstring="Requesting"
			firstpass=False
		else:
			tempstring="Re-requesting"

		msg_output(tempstring+" dt query status.  Waiting up to "+str(dt_req_timeout)+" seconds for a reply", req_loglevel=1)

		cmd="curl -m "+str(dt_req_timeout)+" -sS http://"+dt_listen_IP+":9101/stats/dt/DTInitStat | xmllint --format - | grep -A4 '<entry>'"
		result=run_cmd(cmd)

		# Should return something like:
		#   <entry>
		#     <total_dt_num>2048</total_dt_num>
		#     <unready_dt_num>0</unready_dt_num>
		#     <unknown_dt_num>0</unknown_dt_num>
		#   </entry>
		#
		# ... although if there are problems, may be a number of sets of these results with details
		# about different DT types; occasionally multiple entries are returned.  We'll look only at
		# the first "unready" and "unknown" results if there are multiples

		# XXX - would it make sense to just use an XML parser?

		# Produce warning messages for certain conditions:

		if "Failed" in result['stdout']:
			msg_output("\nWARNING: Unexpected output from dt query.  Check upgrade log for more details")

		# Parse results

		dtlines=result['stdout'].strip().splitlines()

		for line in dtlines:
			if "<total_dt_num>" in line and "</total_dt_num>" in line:
				dtquery_results['total_dt_num']=line.split("<total_dt_num>")[1].split("</total_dt_num>")[0]
			if "<unready_dt_num>" in line and "</unready_dt_num>" in line:
				dtquery_results['unready_dt_num']=line.split("<unready_dt_num>")[1].split("</unready_dt_num>")[0]
			if "<unknown_dt_num>" in line and "</unknown_dt_num>" in line:
				dtquery_results['unknown_dt_num']=line.split("<unknown_dt_num>")[1].split("</unknown_dt_num>")[0]

		msg_output("  total_dt_num: "+str(dtquery_results['total_dt_num'])+" unready_dt_num: "+str(dtquery_results['unready_dt_num'])+" unknown_dt_num: "+str(dtquery_results['unknown_dt_num']), req_loglevel=2)

		if str(dtquery_results['unready_dt_num']).strip() == "0" and str(dtquery_results['unknown_dt_num']).strip() == "0":
			dtready=True
			break # Things look good, exit loop and don't retry

		sleep(retry_delay)

	if dt_listen_IP==None:
		printFailed()
		err_output("ERROR:  Could not determine IP address listener for dtquery (port 9101).")
		err_output("  Either dtquery is not running on this node, or an unexpected condition")
		err_output("  was encountered.")
		exit(15)


	if not dtready:
		printFailed()
		err_output("ERROR: check_dt_ready(): One or more DTs were unready or unknown, or had")
		err_output("an unexpected value.")
		err_output("  total_dt_num: "+str(dtquery_results['total_dt_num']))
		err_output("  unready_dt_num: "+str(dtquery_results['unready_dt_num']))
		err_output("  unknown_dt_num: "+str(dtquery_results['unknown_dt_num']))
		exit(16)
	else:
		printDone()
		msg_output("  total_dt_num: "+str(dtquery_results['total_dt_num'])+" unready_dt_num: "+str(dtquery_results['unready_dt_num'])+" unknown_dt_num: "+str(dtquery_results['unknown_dt_num']))


def write_state_file():

	global upgrade_state_file

	state=dict()

	# Upgrade Type
	# Upgrade Mode
	# Upgrade
	# topology filename
	# extend filename
	# sku (?)
	# Which step(s) have completed
	# Which node is first node?
	# Which nodes have completed if OS
	# Which part of OS upgrade has finished if OS
	# Compliance state
	# Target Version

	# XXX - really should move all these "globals" to a module
	# called "state", and reference them there, and from
	# all other scripts/modules, then just dump the module/class to/from disk

	state['upgradeType']=upgradeType
	state['upgradeMode']=upgradeMode
	state['topologyfile']=topologyfile
	state['extendfile']=extendfile
	state['provisionfile']=provisionfile
	state['sku']=sku
	state['lastCompletedTask']=lastCompletedTask
	state['OSCompletedNodes']=OSCompletedNodes
	state['OSInProgressNode']=OSInProgressNode
	state['OSCompletedStep']=OSCompletedStep
	state['UpgradeTasks']=UpgradeTasks
	state['argString']=argString

	with open(upgrade_state_file, 'w') as outfile:
		json.dump(state, outfile, indent=4)

	# XXX - do stuff


def read_state_file():

	# Really need to make state its own module, move a lot of the "common" vals there, treat like a class

	global upgrade_state_file,upgradeType,upgradeMode,topologyfile,extendfile,provisionfile,sku,lastCompletedTask,OSCompletedNodes,OSInProgressNode,OSCompletedStep,UpgradeTasks,argString,appfile

	try:
		with open(upgrade_state_file) as data_file:
			state = json.load(data_file)
	except:
		return None

	upgradeType=state['upgradeType']
	upgradeMode=state['upgradeMode']
	topologyfile=state['topologyfile']
	extendfile=state['extendfile']
	provisionfile=state['provisionfile']
	#sku=state['sku']
	lastCompletedTask=state['lastCompletedTask']
	OSCompletedNodes=state['OSCompletedNodes']
	OSInProgressNode=state['OSInProgressNode']
	OSCompletedStep=state['OSCompletedStep']
	UpgradeTasks=state['UpgradeTasks']
	argString=stage['argString']

	return state

# XXX delete stale state file



