#!/usr/bin/python

# Perform OS quickfit upgrade (if needed)

# Exit codes:
#   100 - installer
#   101 - required file not found
#   102 - Quickfit run, no output generated
#   103 - Upgrade failed, reported wrong version
#   104 - Upgrade failed - other error
#   105 - could not determine current OS version
#   106 - Unsupported OS version on node
#   107 - Unknown upgrade mode option (should be "online" or "offline"
#   108 - Refit did not complete on node
#   109 - Unknown mode argument

#   200 - Exited indicating that next node to be upgraded is the first node.
#   201 - Upgrade of first node completed.

import multiprocessing
import subprocess
import sys
import os
import getopt
import glob
from time import sleep,time,strftime

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib")

import svc_upgrade_common as common
from svc_upgrade_common import *

indent=0

UpgMACHINES=list(get_machines()) # List of machines to upgrade; can be modified by the user



def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help        Show this help message and exit"
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
	print "-P, --provision <file>  Provisioning file name and location"
	print "                  (default is: <installer dir>/conf/provisioning.txt)"
	print "-S, --sku <sku>   System SKU (e.g. U300)"
	print "                  (default is auto-detect)"
	print "-m, --mode <online|offline>    Perform online or offline upgrade"
	print "                   (required)"
	if common.upgradeType == "OS":
		print "-n, --node <#>       Perform OS install and reboot on one node only"

	exit (1)

def parse_args(argv):

	global UpgMACHINES,NodesSpecified

	NodesSpecified=False

	result=parse_global_args(argv, req_version=True, req_upgradeType=True)

	if result is "usage":
		usage()

	# Additional script-specific option parsing

	try:
		opts, args = getopt.getopt(argv,common.allowedArgs['short'],common.allowedArgs['long'])
	except getopt.GetoptError:
		usage()

	# Check that topology was provided (or should we just read this from the state file)?

	for opt, arg in opts:
		if opt in ("-n", "--node"):
			NodesSpecified=True
			common.upgradeMode="online"

			# Accept either node # or private interface IP string
			if "192.168.219." in str(arg):
				for MACHINE in MACHINES:
					if str(arg).strip() in MACHINES:
						TEMPMACHINE=str(arg).strip()
			elif int(arg) > 0 and int(arg) < 24: # look for node 1-24
				TEMPMACHINE="192.168.219."+str(arg)
			else:
				err_output("Node provided is invalid; either not a valid node on this")
				err_output("  system, node is offline, or invalid input.  Value is either")
				err_output("  private IP address or node number.")
				exit(18)

			UpgMACHINES=[TEMPMACHINE]





def exit_containers(MACHINE, printOutput=True, mode="online"):
	# If pre-2.2.1, stopping object-main used a different command.  ExitContainers
	# script requires arguments "2.2" or "2.2.1" to choose which to run.
	# Determine which to run

	cmd="rpm -qv ecs-os-base | awk -F- '\\''{ print $4 }'\\''"

	result=run_cmd(cmd, printText="Re-checking OS version on "+MACHINE+"...", printComplete=False, MACHINE=MACHINE, indent=indent)

	curversion=result['stdout'].strip()

	# curversion="2.1.0.0" # - for testing

	curversionArray=()

	if curversion != "":
		curversionArray=curversion.split('.')
	if len(curversionArray) != 4 or curversion=="":
		errstring="Could not determine OS version on "+MACHINE+"\n"
		errstring+="Expected a string in format x.x.x.x\n"
		errstring+="Received '"+curversion+"'\n"
		post_cmd_output(result, Failed=True, errortext=errstring)
		exit (105)

	OfflineScriptVerString=None

	if int(curversionArray[0]) > 2:
		OfflineScriptVerString="2.2.1"
	else:
		if curversionArray[0]=="2" and curversionArray[1]=="2":
			if curversionArray[2]=="1":
				OfflineScriptVerString="2.2.1"
			elif curversionArray[2]=="0":
				OfflineScriptVerString="2.2"

	if OfflineScriptVerString is None:
		errstring="OS version on "+MACHINE+" is invalid or unsupported\n"
		errstring+="Expected either '2.2.0.x' or '2.2.1.x', or 3.x and above\n"
		errstring+="Received '"+curversion+"'\n"
		post_cmd_output(result, Failed=True, errortext=errstring)
		exit (106)

	#print "OfflineScriptVerString: "+OfflineScriptVerString

	post_cmd_output(result, indent=indent)


	# Push Exit script to node

	ExitScriptName="OSUpgradeExitContainers_online.py"

	if mode=="online":
		copy_to_nodes(UpgradeRootPath+"/tools/"+ExitScriptName, "/var/tmp/", MACHINE=MACHINE)
		run_cmd("chmod 755 /var/tmp/"+ExitScriptName, MACHINE=MACHINE, no_LogMessage=True)

		msg_output("Exiting containers on "+MACHINE+"...", do_newline=False)
		cmd="ssh "+MACHINE+" \"/var/tmp/"+ExitScriptName+" --ECSBuild="+OfflineScriptVerString+" 2>&1\""
		output=run_cmd(cmd, timeout=1200, noErrorHandling=True)
		if output['retval'] != 0:
			err_output("ERROR: Containers did not fully exit.  Exit script failed or timed out.")
			err_output("Output was:")
			err_output(output['stdout'])
			err_output(output['stderr'])
			exit(110)

		# Exit containers script should have caught it, but check that docker really is shut down
		#   on the node.  If not, exit.

		dockeroutput=run_cmd("sudo docker ps -a", MACHINE=MACHINE, timeout=180, noErrorHandling=True)
		if "Up" in dockeroutput['stdout']:
			err_output("ERROR: Containers did not fully exit.  After running exit script.")
			err_output("Output of exit script was:")
			err_output(output['stdout'])
			err_output(output['stderr'])
			err_output("")
			err_output("Output of 'docker ps' command was:")
			err_output(dockeroutput['stdout'])
			err_output(dockeroutput['stderr'])
			err_output("")
			exit(111)



		printDone()
	elif mode=="offline":
		copy_to_nodes(UpgradeRootPath+"/tools/"+ExitScriptName, "/var/tmp/")
		run_multi_cmd("chmod 755 /var/tmp/"+ExitScriptName, no_LogMessage=True)

		msg_output("Exiting containers on nodes...", do_newline=False)
		cmd='viprexec -X "/var/tmp/'+ExitScriptName+' --ECSBuild='+OfflineScriptVerString+' 2>&1"'
		run_cmd(cmd, timeout=1200, noErrorHandling=True)

		printDone()
	else:
		printFailed()
		err_output("ERROR: exit_containers(): Unknown mode '"+mode+"'")
		exit(109)



def run_refit(MACHINES, indent=0):

	results=dict()

	if len(MACHINES) > 1:
		multimode=True
	else:
		multimode=False


	if not multimode:
		# Running refit on only a single node.  No need to parallelize anything.
		for MACHINE in MACHINES:
			cmd="ssh "+MACHINE+" '/var/tmp/refit doupdate 2>&1 | tee -a /var/tmp/refit.d/doupdate.out'"
			results[MACHINE]=run_cmd(cmd, printText="Running OS Refit (upgrade) on "+MACHINE+" (please wait)...\n",indent=indent, realtime=True, noErrorHandling=True)

	else:  # Multimode, running refit on multiple nodes in parallel
		# XXX - remove doupdate.out since we're using that to determine state, and don't
		#   want to accidentally read a stale one?

		msg_output("Running OS Refit (upgrade) on nodes in parallel (please wait)...\n")
		msg_output("To monitor upgrade progress, check the /var/tmp/refit.d/doupdate.out log")
		msg_output("  on each node")
		# We're going to run refit in parallel on many nodes.  Start these commands on each but run in the background
		for MACHINE in MACHINES:
			# Start refit in background on all nodes except current
			cmd="ssh "+MACHINE+" 'nohup /var/tmp/refit doupdate >/var/tmp/refit.d/doupdate.out 2>&1 < /dev/null &' "
			#cmd="ssh "+MACHINE+" 'nohup sleep 100 1>/var/tmp/refit.d/doupdate.out 2>&1 < /dev/null &'"
			results[MACHINE]=run_cmd(cmd)

		# Run the refit on the current node and monitor output, display to terminal/log

		sleep(60) # Assuming the refit will take at least this long

		AllNodesComplete=False
		while not AllNodesComplete:

			AllNodesComplete=True

			msg_output("Checking if upgrade still running on each node", req_loglevel=1)

			for MACHINE in MACHINES:
				# Wait for upgrade to complete on each node.  We'll reach this point after
				# the first node finishes.  Check to see if others are still running
				# refit (they should be close to being done).  If not, wait for each to
				# complete.

				# Check the status of the "refit" process on each node.

				# Should be a process that looks something like:
				# admin     62223      1  0 23:09 ?        00:00:00 /bin/bash /var/tmp/refit doupdate

				cmd="ssh "+MACHINE+" 'ps -ef | grep \"bash /var/tmp/refit doupdate\" | grep -v \"grep\"'"
				#cmd="ssh "+MACHINE+" 'ps -ef | grep \"sleep\" | grep -v \"grep\"'"
				result=run_cmd(cmd, noErrorHandling=True)

				if result['stdout'].strip() != "" and result['retval'] != 1:
					AllNodesComplete=False
				# XXX do error handling here

			sleep(10)

		# Once each is complete, then get the complete log for each.

		for MACHINE in MACHINES:
			cmd="cat /var/tmp/refit.d/doupdate.out"
			results[MACHINE]=run_cmd(cmd, MACHINE=MACHINE)

		# End Multimode logic


	for MACHINE in MACHINES:

		if not "DONE!" in results[MACHINE]['stdout']:
			errstring="OS Refit on '"+MACHINE+"' did not complete successfully.\n"
			errstring+="Refit should have logged 'DONE!', string not found.\n"
			errstring+="Output was:\n"
			errstring+=results[MACHINE]['stdout']
			post_cmd_output(results[MACHINE], Failed=True, errortext=errstring)
			exit(108)

	printDone

	for MACHINE in MACHINES:
		# XXX - make additional validation checks?

		# post_cmd_output(results[MACHINE])

		# Move the PXE menu (again, after refit)

		run_cmd("mv /srv/tftpboot/pxelinux.cfg/default /srv/tftpboot/pxelinux.cfg/new.file", MACHINE=MACHINE)

		# Verify change




def reboot_node(MACHINE, printOutput=True):

	shutdowntimeout=60
	powerontimeout=20
	poweroffretries=3
	poweronretries=3
	osstart_timeout=360
	nodeservice_timeout=360
	local_private_IP=get_local_private_IP()
	IPMI_IP=get_IPMI_IP(MACHINE)
	nodenum=get_nodenum(MACHINE)

	# Make sure MACHINE isn't current node - must be run from a remote node


	if MACHINE == local_private_IP:
		return

	# Shut down node with "shutdown"

	cmd="ssh "+MACHINE+" 'sudo shutdown -h now'"
	msg_output("Rebooting "+MACHINE+"...", do_newline=False)
	run_cmd(cmd, noErrorHandling=True, printComplete=True, timeout=60)
	printDone()

	# Wait for machine to shut down. If not powered off within timeout, do hard poweroff

	shutdownstart=int(time())
	shutdowncomplete=False

	msg_output("Waiting for "+MACHINE+" to shut down...", do_newline=False)

	while int(time()) < (shutdownstart + shutdowntimeout):
		result=run_cmd("sudo ipmitool -H "+IPMI_IP+" -U root -P passwd power status", noErrorHandling=True, timeout=30)
		if result['stdout'].strip() == "Chassis Power is off":
			shutdowncomplete=True
			break
		else:
			sleep(1)

	if not shutdowncomplete:  # Shutdown not complete before timeout, do hard power off

		poweroffcomplete=False
		poweroffretry=0
		cmd="sudo ipmitool -H "+IPMI_IP+" -U root -P passwd power off"

		while poweroffretry < poweroffretries:
			result=run_cmd(cmd, noErrorHandling=True, timeout=30)
			sleep(10)

			result=run_cmd("sudo ipmitool -H "+IPMI_IP+" -U root -P passwd power status", noErrorHandling=True, timeout=30)

			if result['stdout'].strip() == "Chassis Power is off":
				poweroffcomplete=True
				break


		if not poweroffcomplete:
			printFailed()
			err_output("ERROR:  reboot_node():  Forced power off did not succeed.")
			err_output("Expected 'Chassis power is off', received '"+result['stdout'].strip()+"'")
			exit(10)

	printDone()

	# Wait a few, power back on

	sleep(3)

	msg_output("Powering "+MACHINE+" back on...", do_newline=False)

	poweronstart=int(time())
	poweroncomplete=False
	poweronretry=0

	while poweronretry < poweronretries:
		# Try turning on power; potentially retry more than once if the command failed or didn't seem to work
		result=run_cmd("sudo ipmitool -H "+IPMI_IP+" -U root -P passwd power on", noErrorHandling=True, timeout=30)

		# Wait for node power status to change to "on"
		while int(time()) < (poweronstart + powerontimeout):
			result=run_cmd("sudo ipmitool -H "+IPMI_IP+" -U root -P passwd power status", noErrorHandling=True, timeout=30)
			if result['stdout'].strip() == "Chassis Power is on":
				poweroncomplete=True
				break
			else:
				sleep(1)
		poweronretry += 1
		if poweroncomplete:
			break

		sleep(1)


	if not poweroncomplete:
		printFailed()
		err_output("ERROR:  reboot_node():  Power on did not succeed after "+str(poweronretries)+" tries.")
		err_output("  of "+str(powerontimeout)+" seconds.")
		err_output("Expected 'Chassis Power is on', received '"+result['stdout'].strip()+"'")
		exit(11)

	printDone()


	# Wait for node to become responsive.  Check ping, then ssh.

	msg_output("Waiting for "+MACHINE+" to reboot completely...", do_newline=False)

	pingsucceed=False
	startupcomplete=False
	startupstart=int(time())

	while int(time()) < (startupstart + osstart_timeout):

		result=run_cmd("ping -c 1 "+MACHINE, noErrorHandling=True, timeout=30)

		if result['retval']==0:   # Ping command succeeded
			pingsucceed=True

		if pingsucceed:
			# Check ssh
			result=run_cmd("ssh "+MACHINE+" 'uptime'", timeout=30)
			if result['retval']==0:
				startupcomplete=True
				break

		sleep(2)

	if not poweroncomplete:
		printFailed()
		err_output("ERROR:  reboot_node():  Node did not fully respond within "+osstart_timeout)
		err_output("  seconds after power on.  Either was not responding to pings or not")
		err_output("  responding to basic ssh commands")
		exit(12)

	printDone()

	# Wait until we see in getrackinfo - node is up and registered

	msg_output("Waiting for "+MACHINE+" node services to start...", do_newline=False)

	nodeservicescomplete=False
	nodeservicesstart=int(time())

	while int(time()) < (nodeservicesstart + nodeservice_timeout):
		# Wait for a getrackinfo output that looks something like:
		# 192.168.219.2     2        SA       00:1e:67:ab:ea:58   10.245.129.42       00:1e:67:6a:1e:fd   10.245.129.32       sandy-shamrock
		# Assume the "Status" field must contain "SA" or "MA".  If the node isn't fully contacted or still offline, this will show as blank or other value

		result=run_cmd("sudo -i getrackinfo -f | grep '"+MACHINE+" ' | awk '{ print $3 }'", noErrorHandling=True, timeout=50)

		if ("SA" in result['stdout'] or "MA" in result['stdout']):
			nodeservicescomplete=True
			break

		sleep(2)

	if not nodeservicescomplete:
		printFailed()
		err_output("ERROR:  reboot_node():  Node services did not fully respond within "+str(nodeservice_timeout))
		err_output("  seconds after OS was booted.  getrackinfo output did not show the node")
		err_output("  as active")
		exit(13)

	printDone()


def check_os_version(MACHINE):
	global UpgDetails

	# Try multiple times in case command fails from recent reboot

	vercorrect=False
	retries=2
	retry=0

	while retry < retries:
		result=run_cmd("rpm -qv ecs-os-base", printText="Validating OS version after upgrade...", printComplete=False, MACHINE=MACHINE)
		if UpgDetails['TargetOS'] in result['stdout']:
			vercorrect=True
			break

		sleep(10)

		retry+=1

	if vercorrect==False:
		errortext="After upgrade and reboot, OS version appears incorrect.\n"
		errortext+="Expected version: '"+UpgDetails['TargetOS']+"'\n"
		errortext+="Reported version: '"+result['stdout'].strip()+"'\n"
		post_cmd_output(result, Failed=True, errortext=errortext)
		exit(13)
	else:
		post_cmd_output(result)


def verify_bonding(MACHINE):

	bondconfigured=False

	linkcmd='ip link show | egrep "slave-|public"'
	msg_output("Verifying bonding mode...", do_newline=False)
	result=run_cmd(linkcmd, MACHINE=MACHINE, noErrorHandling=True)

	msg_output("verify_bonding(): Looking for 'slave-0' and 'slave-1' output in ip link show output", req_loglevel=2)

	if not ("slave-0" in result['stdout'] and "slave-1" in result['stdout']):
		# LAG slave interfaces did not start after upgrade/reboot - restart NAN
		msg_output("\nLAG slave interfaces did not start after upgrade/reboot - restarting NAN", indent=1)
		run_cmd("sudo ifdown public", indent=1, MACHINE=MACHINE)
		run_cmd("sudo rm /etc/sysconfig/network/ifcfg-public", indent=1, MACHINE=MACHINE, noErrorHandling=True)
		run_cmd("sudo systemctl restart nan", indent=1, MACHINE=MACHINE)
		sleep(20)
		run_cmd("sudo ifdown public && sudo ifup public", indent=1, MACHINE=MACHINE)
		sleep(10)
		result=run_cmd(linkcmd, MACHINE=MACHINE, noErrorHandling=True)

	if ("slave-0" in result['stdout'] and "slave-1" in result['stdout']):
		# Slaves configured, move on to check that bond itself (public) is set up properly

		result=run_cmd("grep Mode /proc/net/bonding/public", indent=1, MACHINE=MACHINE, noErrorHandling=True)

		msg_output("verify_bonding(): Looking for 'Bonding Mode: IEEE 802.3ad Dynamic link aggregation' output in /proc/net/bonding/public", req_loglevel=2)

		if "Bonding Mode: IEEE 802.3ad Dynamic link aggregation" in result['stdout']:
			# Everything looks good:

			bondconfigured=True

	if bondconfigured:
		printDone()
	else:
		printFailed()
		err_output("ERROR:  Public network interfaces failed to configure properly after ")
		err_output("  upgrade/reboot on "+MACHINE+".")
		err_output("Either LAG slave interfaces did not start properly, or LAG bonding")
		err_output("  interface (public) did not configure properly.")
		err_output("")
		exit(14)

		# XXX - add boilerplate message displayed if OS upgrade fails.
		# Should this be in svc_upgrade.py ?  Probably, if the script fails unexpectedly, we
		# won't have the chance to display anywhere else.  And we do something similar in
		# prechecks()



def get_postupdate_info():


	temp=1




######################## Main logic ############################

try:
	parse_args(sys.argv[1:])

	#exit(1)

	UpgDetails=common.UpgVersions[common.TargetVersion][common.upgradeType]

	######## OS major upgrade (refit)

	if common.upgradeType == "OS":

		# Make sure we're running on first node (again)
		# Check that refit and refit dir is still there
		# Push refit every time?  Something keeps deleting it.
		# Check that nodes are online and containers up on all nodes
		# Should that be standalone check tool...?
		# Check if refit is already running

		# Determine whether we're running on the first node or not, and
		# sanity check (again) that the first node is an installer node.

		# If we're running from something other than the first node, upgrade
		# to other nodes must be complete.  And user must have specified to
		# upgrade the first node.

		# If we're running from the first node and user hasn't selected to
		# upgrade a specific node, then assume all other nodes will be upgraded.

		# Once nodes other than node 1 are upgraded, copy the installer package to
		# nodes and instruct the user to connect to another node and upgrade node 1.

		firstnode=get_first_node(get_machines())
		curIP=get_local_private_IP()
		curnode=int(get_nodenum(curIP))

		if firstnode == curnode:
			on_firstnode=True
		else:
			on_firstnode=False


		# If we're running on the first node, then remove this node from the MACHINES list
		# that'll be parsed for the majority of tasks

		if curIP in UpgMACHINES:
			msg_output("Not upgrading the current node (node "+str(curnode)+")", indent=1)
			UpgMACHINES.remove(curIP)

		# Disable DT load balancing

		setLoadBalanceMode("disable")

		# Run loop on all except the first node

		# If offline, do all in parallel.  If online, do one at a time

		if common.upgradeMode == "online":
			msg_output("Online OS Upgrade mode.  Upgrading nodes individually.")

			for MACHINE in UpgMACHINES:

				# Prompt user before continuing with node
				msg_output("\n============ Upgrading new node ==============")
				msg_output("About to upgrade node "+get_nodenum(MACHINE)+" ("+MACHINE+").")
				msg_output("Please ensure the node is ready to be taken offline (has been")
				msg_output("removed from load balancer or application configuration, etc)")
				msg_output("and enter the word \"READY\", followed by enter, to continue.")
				msg_output("Quotes are not needed, and string must be in capital letters.")
				msg_output("")

				response=""

				while True:
					#response=raw_input("Type \"READY\" <enter> to continue: ")
					msg_output("Please enter \"READY\" (no quotes, followed by enter) to continue")
					response=raw_input("")
					if response.strip() == "READY":
						break

				# Exit containers

				exit_containers(MACHINE)

				# Run refit doupgrade
				run_refit([MACHINE])

				# Reboot node
				reboot_node(MACHINE, printOutput=True)

				# After restart, verify OS version
				check_os_version(MACHINE)

				# Verify bonding mode
				verify_bonding(MACHINE)

				# Restart containers
				run_cmd("sudo systemctl start docker", MACHINE=MACHINE)
				run_cmd("sudo systemctl start fabric-agent", MACHINE=MACHINE)

				# Disable load balancing (again)
				setLoadBalanceMode("disable", MACHINE=MACHINE)

				# Check for bad disks (again?)

				# Save post-update information

				get_postupdate_info()

				# Compare pre- and post-update information

				# Check that object service initialization is complete
				check_dt_ready()



				# go to the next node

		elif common.upgradeMode == "offline":
			msg_output("Offline OS Upgrade mode.  Upgrading nodes in parallel.")

			exit_containers(UpgMACHINES[0],mode="offline")

			run_refit(UpgMACHINES)

			for MACHINE in UpgMACHINES:
				reboot_node(MACHINE)
				check_os_version(MACHINE)
				verify_bonding(MACHINE)
				setLoadBalanceMode("disable", MACHINE)

			for MACHINE in UpgMACHINES:
				# Restart containers
				run_cmd("sudo systemctl start docker", MACHINE=MACHINE)
				run_cmd("sudo systemctl start fabric-agent", MACHINE=MACHINE)

			# Check for bad disks (again?)
			# Save post-update information
			# Compare pre- and post-update information
			# Check that object service initialization is complete
			check_dt_ready()
			# Verify other versions (hal, object, fabric)


		else:
			err_output("ERROR:  Unknown OS upgrade mode '"+str(common.upgradeMode)+"'.  Exiting.")
			exit (107)


		# Once all nodes are complete except first one, mark it in state file and
		# push to all nodes.

		# XXX - temporary until we have persistent marking/validation for when each node is complete
		if not NodesSpecified:
			msg_output("")
			msg_output(bcolors.OK+"*******"+bcolors.ENDC+" Upgrade of non-installer nodes complete. "+bcolors.OK+"*******"+bcolors.ENDC)
			msg_output("")
			msg_output("The current node still needs to be upgraded.  To perform this, disconnect")
			msg_output("from this node, connect to the second node, and run")
			msg_output("     svc_upgrade --OS --os --node "+str(curnode)+" <other options>")
			msg_output("")
			msg_output("Note:  Do not connect to the other node from this session; it will be")
			msg_output("disconnected")
			msg_output("")
			exit (200)
		else:
			if UpgMACHINES[0] == "192.168.219."+str(firstnode):  # First node just upgraded
				msg_output("")
				msg_output(bcolors.OK+"*******"+bcolors.ENDC+" Upgrade of installer node complete. "+bcolors.OK+"*******"+bcolors.ENDC)
				msg_output("")
				msg_output("To continue, disconnect this session and reconnect to the first node.")
				exit (201)


		# Push svc_upgrade and topology/extend files to all nodes















	######### OS Quickfit for Application Upgrades

	if common.upgradeType == "Application":

		# Only run quickfit upgrade if needed

		if not UpgDetails['QuickFit']:
			msg_output("No OS quickfit is needed for "+common.TargetVersion+" "+common.upgradeType+" upgrades.")
			msg_output("")
			exit (0)

		InstallerDir=UpgDetails['TargetOS'] # should be like "2.2.1.0-1309.3719890.88"
		tempdir="/var/tmp/upgrade"

		InstallerFullPath=tempdir+"/"+InstallerDir


		msg_output("")
		msg_output("Installing OS quickfit (if needed):")
		msg_output("")



		msg_output("Checking for OS upgrade directory '"+InstallerFullPath+"'...", indent=1, do_newline=False)
		if not os.path.isdir(InstallerFullPath):
			printFailed()
			err_output("ERROR: Dir for OS upgrade package, '"+InstallerFullPath+"' is not")
			err_output("a directory or doesn't exist.")
			err_output("")
			err_output("Be sure that the upgrade 'deploy' operation has completed successfully.")
			err_output("")
			err_output("EXITING...")

			exit (100)
		printDone()


		msg_output("Checking for required files...", indent=1, do_newline=False)

		found_error=False
		for file in ["VERSION.hotfix","ecs-os-setup-target.x86_64-2.1309.88.hotfix.tbz","ecs-os-setup-target.x86_64-2.1309.88.install.tar.xz","quickfit"]:
			curfile=InstallerFullPath+"/"+file

			msg_output("Checking for file: ", indent=2, req_loglevel=1)
			msg_output(curfile, indent=3, req_loglevel=1)

			if not os.path.exists(curfile):
				if not found_error:
					printFailed()

				found_error=True
				err_output("ERROR: Required file, '"+curfile+"' is not found.")


		if found_error:
			err_output("")
			err_output("Be sure that the upgrade 'deploy' operation has completed successfully.")
			err_output("")
			err_output("EXITING...")
			exit (101)
		else:
			printDone()

		msg_output("Running quickfit for OS update (please wait)...", indent=1, do_newline=False)

		cmd="cd "+InstallerFullPath+"; ./quickfit update"
		if verbose >= 2:  # Display the output of the script to the terminal in real time
			result=run_cmd(cmd, indent=1, realtime=True)
		else:
			result=run_cmd(cmd, noErrorHandling=True, indent=1)

		# Parse results of the output
		output=result['stdout'].split("\n") # Split into a list by newline, iterate through them

		if output is "":
			err_output("ERROR: OS upgrade failed, no output generated.  Unexpected state\n\n")

			exit (102)


		prevline=""
		for line in output:
			if line.find("ERROR") is not -1: # an error reported
				if line.find("Current versions not suitable for"): # Incorrect version error
					# This is something like:
					# 20160809-061952 ERROR!  Current versions not suitable for 2.2.1 HF1 quickfit

					if prevline.find(common.TargetVersion) is not -1:
						# Look for message on the previous line.  If this matches, it is something like:
						# 20160809-061952 Info    Comparing base 2.2.1.0-1281.e8416b8.68 to node version 2.2.1.0-1309.3719890.88
						# Oh, this just means we've already upgraded.
						prevline=line
						msg_output("Note: Already upgraded OS, no need to upgrade again", req_loglevel=1)
						continue
					else: # truly is the wrong version
						err_output("ERROR: OS upgrade failed, reported wrong version.")
						err_output("")
						err_output("Complete output was:")
						err_output(result['stdout'])

						exit (103)
				else: # unknown error
					err_output("ERROR: OS upgrade failed, unknown error.")
					err_output("")
					err_output("Complete output was:")
					err_output(result['stdout'])

					exit (104)

			prevline=line



		printDone()

except:
	#msg_output("Exiting early")
	raise











