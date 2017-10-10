#!/usr/bin/python

import os
import sys,re
import subprocess
import getopt
from time import sleep


def ExecuteCommand(command, log=1):
        if log:
           print("Executing command %s" % command)
        output=subprocess.check_output("%s" % command, shell=True)
        return output

def ExitContainers(Build):
	# Get currently available containers


	containers=ExecuteCommand("sudo docker ps -a")
	output=ExecuteCommand("sudo /opt/emc/caspian/fabric/cli/bin/fcli maintenance list")
	print output
	if "LOCKDOWN" in output:
	   assert 0,  "Nodes are in LOCK DOWN state %s"% output
	if "Entering ACTIVE" in output:
	   assert 0,  "Nodes are in Entering ACTIVE state %s"% output

	output=ExecuteCommand("sudo systemctl stop fabric-agent")
	print output
	print("Waiting for fabric-agent to exit")

	t=20
	while t > 0:
		output=ExecuteCommand("sudo systemctl status fabric-agent | grep Active")
		print output
		if not "Active: active (running)" in output:
			break

		t=t-1
		sleep(1)

	print output
	if "Active: active (running)" in output:
	  assert 0, "Fabric Agent still running :%s"% output
	if Build == "2.2":
	  output=ExecuteCommand("sudo docker stop --time 30 object-main")
	  print output
	else:
	  output=ExecuteCommand("cd /opt/emc/caspian/fabric/agent && timeout 900 sudo conf/configure-object-main.sh --stop 2>&1")
	  print output
	  output=ExecuteCommand("sudo docker stop --time 50 object-main 2>&1;exit 0")
	  print output

	if "lifecycle" in containers:
		output=ExecuteCommand("sudo docker stop fabric-lifecycle 2>&1;exit 0")
		print output
	if "fabric-zookeeper" in containers:
		output=ExecuteCommand("sudo docker stop fabric-zookeeper 2>&1;exit 0")
		print output
	if "fabric-registry" in containers:
		output=ExecuteCommand("sudo docker stop fabric-registry 2>&1;exit 0")
		print output
	sleep(10)
	StillUp=True
	loopcount=0
	while loopcount < 5:
		output=ExecuteCommand("sudo docker ps -a")
		if not "Up" in output:
			StillUp=False
			break
		loopcount+=1
	if StillUp:
		assert("Containers still up after running docker stop.  'docker ps' output was:\n"+output)


	output=ExecuteCommand("sudo systemctl stop docker")
	print output
	output=ExecuteCommand("sudo systemctl status docker | grep Active")
	print output
	if "active (running)" in output:
	  assert 0, "Nodes are in running state %s"% output


def main(args):
    #ExecuteCommand("ls asdf;exit 0")
    #exit(0)
    try:
      opts, args = getopt.getopt(args, '', ["help","ECSBuild="])
    except getopt.GetoptError, e:
      print 'usage:python OnlineoSUpgradeExitContainers.py --ECSBuild=<ECS Build>\n'
      print 'Ex:python OnlineoSUpgradeExitContainers.py --ECSBuild=2.2.1'
    ECSBuild=""
    for opt, arg in opts:
         if opt in ("-help", "--help"):
          print 'usage:python OnlineoSUpgradeExitContainers.py --ECSBuild=<ECS Build>\n'
          print 'Ex:python OnlineoSUpgradeExitContainers.py --ECSBuild=2.2.1'
          sys.exit()
         elif opt in ("-ECSBuild", "--ECSBuild"):
            ECSBuild = arg
    if ECSBuild == "2.2" or ECSBuild == "2.2.1":
       ExitContainers(ECSBuild)
    else:
       print 'usage:python OnlineoSUpgradeExitContainers.py --ECSBuild=<ECS Build>\n'
       print 'ECSBuild should be 2.2 or 2.2.1'
       print 'Ex:python OnlineoSUpgradeExitContainers.py --ECSBuild=2.2.1'
    

if __name__ == "__main__":
   main(sys.argv[1:])
