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
    output=ExecuteCommand("viprexec '/opt/emc/caspian/fabric/cli/bin/fcli maintenance list'")
    print output
    if "LOCKDOWN" in output:
       assert 0,  "Nodes are in LOCK DOWN state %s"% output
    if "Entering ACTIVE" in output:
       assert 0,  "Nodes are in Entering ACTIVE state %s"% output
    output=ExecuteCommand("viprexec 'systemctl stop fabric-agent'")
    print output
    print("wait for 20 sec")
    sleep(20)
    output=ExecuteCommand("viprexec 'systemctl status fabric-agent'")
    print output
    if "Active: active (running)" in output:
      assert 0, "Fabric Agent still running :%s"% output
    if Build == "2.2":
      output=ExecuteCommand("viprexec 'docker stop --time 30 object-main'")
      print output
    else:
      output=ExecuteCommand("viprexec 'cd /opt/emc/caspian/fabric/agent; conf/configure-object-main.sh --stop'")
      print output
      output=ExecuteCommand("viprexec 'docker stop --time 30 object-main'")
      print output
    output=ExecuteCommand("viprexec 'docker stop fabric-lifecycle'")
    print output
    output=ExecuteCommand("viprexec 'docker stop fabric-zookeeper'")
    print output
    output=ExecuteCommand("viprexec 'docker stop fabric-registry'")
    print output
    output=ExecuteCommand("viprexec 'sudo docker ps -a'")
    print output
    if "UP" in output:
      assert 0, "Conatiners are still UP even after docker stop commands.%s" % output
    output=ExecuteCommand("viprexec systemctl stop docker")
    print output
    output=ExecuteCommand("viprexec 'systemctl status docker | grep Active'")
    print output
    if "active (running)" in output:
      assert 0, "Nodes are in running state %s"% output


def main(args):
    try:
      opts, args = getopt.getopt(args, '', ["help","ECSBuild="])
    except getopt.GetoptError, e:
      print 'usage:python OSUpgradeExitContainers.py --ECSBuild==<ECS Build>\n'
      print 'Ex:python OSUpgradeExitContainers.py --ECSBuild==2.2.1'
    ECSBuild=""
    for opt, arg in opts:
         if opt in ("-help", "--help"):
          print 'usage:python OSUpgradeExitContainers.py --ECSBuild==<ECS Build>\n'
          print 'Ex:python OSUpgradeExitContainers.py --ECSBuild==2.2.1'
          sys.exit()
         elif opt in ("-ECSBuild", "--ECSBuild"):
            ECSBuild = arg
    if ECSBuild == "2.2" or ECSBuild == "2.2.1":
       ExitContainers(ECSBuild)
    else:
       print 'usage:python OSUpgradeExitContainers.py --ECSBuild==<ECS Build>\n'
       print 'ECSBuild should be 2.2 or 2.2.1'
       print 'Ex:python OSUpgradeExitContainers.py --ECSBuild==2.2.1'
    

if __name__ == "__main__":
   main(sys.argv[1:])
