#!/usr/bin/python

# Check if compliance mode is enabled and save the info

# Exit codes:

# 100: RackInstallServer setting could not be disabled or could not be verified
# 101: getrackinfo -i produced unexpected output (presumably is displaying it has
#      a problem
# 102: number of nodes returned in getrackinfo -c does not match MACHINES


import sys
import os
import getopt
import re

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)

sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
from svc_upgrade_common import *

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)

MACHINES=get_machines()


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
	#global verbose,subargs,topologyfile,provisionfile,extendfile,screen,upgradeType

	result=parse_global_args(argv)

	if result == "usage":
		usage()



# Main logic

parse_args(sys.argv[1:])


# Disable PXE

# Check if PXE config is currently enabled on any node - if so, rename config file.

msg_output("Checking PXE configuration", req_loglevel=1, indent=2)

result=run_multi_cmd("ls -l /srv/tftpboot/pxelinux.cfg/default", MACHINES=MACHINES)

for MACHINE, details in result.viewitems():

	if details['stdout'] is not "":   # File exists, PXE config is set
		# Rename configuration

		msg_output("PXE config enabled.  Disabling PXE config on "+MACHINE, req_loglevel=1, indent=2)

		run_multi_cmd("mv /srv/tftpboot/pxelinux.cfg/default /srv/tftpboot/pxelinux.cfg/old.file", MACHINES={ MACHINE })


# Disable RackInfoServer

msg_output("Disabling RackInstallServer setting ", req_loglevel=1, indent=2)

run_cmd("sudo setrackinfo -p RackInstallServer no")

# Check it is disabled

cmd="sudo getrackinfo -p RackInstallServer"
result=run_cmd(cmd)

if result['stdout'].strip() != 'no':
	err_output("ERROR: RackInstallServer setting could not be verified or could not be disabled. ")
	err_output("Output of "+cmd+" should be 'no', instead output was: "+result['stdout'])

	exit (100)


# Set the DHCP ignore list

msg_output("Setting DHCP ignore list", req_loglevel=1, indent=2)

cmd="for mac in $(sudo getrackinfo -v | egrep \"private[ ]+:\"|awk '{print $3}'); do sudo setrackinfo --installer-ignore-mac $mac; done"

#run_cmd(cmd)

# Check that ignore list is set properly.  (XXX - should this be split into a standalone check?)
# Output of getrackinfo -i should look similar to:

# Rack Installer Status
# =====================
# Mac                 Name       Port   Ip                Status
# 00:1e:67:69:7e:3b   provo      1      192.168.219.1     Done!
# 00:1e:67:69:fc:c6   sandy      2      192.168.219.2     Done!
# 00:1e:67:69:f7:d5   orem       3      192.168.219.3     Done!
# 00:1e:67:69:f9:6a   ogden      4      192.168.219.4     Done!
# ... With # of MAC address entries matching the # of MACHINES in the rack and Status of Done!

msg_output("Checking getrackinfo output", req_loglevel=1, indent=2)

result=run_cmd("sudo getrackinfo -i")

# There are cases where getrackinfo -i will return errors indicating that it had a
# problem retrieving info.  If so the getrackinfo output won't start with "Rack Installer
# Status".  We should error out in this case and let the user decide if this needs to
# be addressed

if not result['stdout'].startswith("Rack Installer Status"):
	err_output("ERROR:  getrackinfo -i produced unexpected output while verifying installer")
	err_output("  status.  Exiting.")
	err_output("Full output was:")
	err_output(result['stdout'])
	err_output(result['stderr'])

	exit (101)

# Check # of nodes is correct.  Assume each line with a mac address represents one node,
# and that the # of nodes in the rack should match MACHINES list

nodecount=0
lines=result['stdout'].splitlines()
macregex='([a-fA-F0-9]{2}[:|\-]){5}[a-fA-F0-9]{2}'

for line in lines:
	if re.compile(macregex).search(line):
		nodecount+=1

if nodecount != len(MACHINES):
	err_output("ERROR:  Number of nodes returned in getrackinfo -i output does not match")
	err_output("  the number of nodes in MACHINES.")

	exit (102)

#print "Nodecount: "+str(nodecount)

print "OK"

# XXX - possibly we should be saving the fact that we did or didn't rename the PXE file to the persistence file.  There could be a case where when upgrade started, the file didn't exist so we didn't rename it (assuming it was already disabled by either a previous run or manually), but the "old.file" that exists is from some earlier release and contains stale/bad info.  Two unlikely things, and the format of the file hasn't changed in quite a while.  But is a small possibility.










