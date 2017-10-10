#!/usr/bin/python


# Exit codes:
#   100 - No output returned to "docker ps" command
#   101 - One or more containers in Exited state
#   102 - Unexpected output in "docker ps" command (potentially failed to run)
#   103 - fabric-agent not running
#   104 - fabric-agent health check failed
#   1 - bad syntax or help screen


import sys
import os
import getopt

CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)

sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
from svc_upgrade_common import *

verbose=0


def usage():
	global CurScriptName

	print "Usage: "+CurScriptName+" [options]"
	print
	print "options:"
	print "-h, --help       Show this help message and exit"
	print "-v, --verbose     Enable verbose output"
	print "-V, --veryverbose Enable very verbose output"
	print "-l, --log         Log output to upgrade log"

	exit (1)

def parse_args(argv):

	result=parse_global_args(argv)


	if result is "usage":
		usage()


def do_error(err_string, retval):
	global CurScriptName

	err_output("FATAL: While executing "+CurScriptName+"\n")

	err_output(err_string)
	exit(retval)


# Main logic

parse_args(sys.argv[1:])

msg_output("Checking container run states", req_loglevel=1)

cmd="docker ps -a"
result=run_multi_cmd(cmd)

#result=dict()

# Check that we did get output of some kind

# XXX - need to do this check for every command.  Should run_multi_cmd always check this and die?
if len(result) < 1:
	output="No results were returned when running viprexec "+cmd+", which is\n"
	output+="an unexpected condition."

	do_error(output, 100)

# Loop through each of the results
for MACHINE, psdata in result.viewitems():

	cmd_output=psdata['stdout']+psdata['stderr']
	# Check to make sure the output looks like a valid output

	if not ("CONTAINER ID" in cmd_output and "COMMAND" in cmd_output and "STATUS" in cmd_output):
		output=cmd+" output from node "+MACHINE+" does not look like proper output.  Aborting.\n"
		output+="Expect to see the strings 'CONTAINER ID', 'COMMAND', and 'STATUS'\n"
		output+="Output was:\n"
		output+=str(cmd_output)

		do_error(output, 101)


	# Check that no container is in the "Exited" state.
	# Run command against all nodes.  Expected output per node should look something like:
	# Output from host : 192.168.219.2
	# CONTAINER ID  IMAGE         COMMAND                 CREATED     STATUS     PORTS       NAMES
	# 313e0996a08b  464b97154c24  "/opt/vipr/boot/boot."  5 days ago  Up 5 days  object-main
	# 52aadea83a59  24d9d6008893  "./boot.sh lifecycle"   5 days ago  Up 5 days  fabric-lifecycle
	# 8445595cb349  32cce433c3dc  "./boot.sh 2 1=169.25"  5 days ago  Up 5 days  fabric-zookeeper

	# If status is "Exited", fail

	# Check for "Exited" anywhere in the output.
	# XXX - This logic could be a problem if at some point this output changes so that "Exited" shows up
	# in an unexpected place, but is unlikely and we have a similar problem even if we were trying to
	# locate the "Exited" status more positionally and output changes unexpectedly.
	# Should be safe as worst case this will cause us to fail the check.

	if "Exited" in cmd_output:
		output="One or more containers on node "+MACHINE+" are in Exited status.\n"
		output+="Output was:\n"
		output+=cmd_output

		do_error(output, 102)

# Check that every node is running the "fabric-agent service".

# Output should look something like:
# Output from host : 192.168.219.2
# Loaded: loaded (/usr/lib/systemd/system/fabric-agent.service; enabled)
# Active: active (running) since Wed 2016-06-08 11:54:42 UTC; 5 days ago

msg_output("Checking fabric-agent states", req_loglevel=1)

cmd="systemctl status fabric-agent | grep -A 1 /usr/lib/systemd/system/fabric-agent.service"

result=run_multi_cmd(cmd)

for MACHINE, fabricagent_out in result.viewitems():
	cmd_output=fabricagent_out['stdout']+fabricagent_out['stderr']
	if not ("Loaded: loaded (/usr/lib/systemd/system/fabric-agent.service; enabled)" in cmd_output and "Active: active (running)" in cmd_output):
		output="fabric-agent not running on node "+MACHINE+", or unexpected output.\n"
		output+="Output was:"
		output+=cmd_output

		do_error(output, 103)


# Check fabric-agent health on each node.

# Output from each should look something like:

# Output from host : 192.168.219.9
# {
#   "health": {
#     "health": "GOOD",
#     "startup_seq_no": 56103,
#     "startup_timestamp_ms": 1468898392137
#   },
#   "status": "OK",
#   "etag": 56127
# }

msg_output("Checking fabric-agent health", req_loglevel=1)

cmd="cd /opt/emc/caspian/fabric/cli;bin/fcli agent agent.health /v1/agent/health"

result=run_multi_cmd(cmd)

for MACHINE, fabricagent_health in result.viewitems():
	cmd_output=fabricagent_health['stdout']+fabricagent_health['stderr']
	if not ('"health": "GOOD"' in cmd_output and '"status": "OK"' in cmd_output):
		output="fabric-agent health check failed on node "+MACHINE+", or unexpected output.\n"
		output+='Expected to see strings \'"health": "GOOD"\' and \'"status": "OK"\'.'
		output+="Output was:"
		output+=cmd_output

		do_error(output, 104)


# XXX - need to figure out best way to validate Partition names, p.22+23



# Check disks agent status

# XXX - possibly need to just make most of the below a library function as we're doing it enough.
msg_output("Checking fabric-agent health", req_loglevel=1)

cmd='cd /opt/emc/caspian/fabric/cli;bin/fcli agent disk.disks | grep \"status\"'

result=run_multi_cmd(cmd)

for MACHINE, disksagent_health in result.viewitems():
	cmd_output=disksagent_health['stdout']+disksagent_health['stderr']
	if not '"status": "OK"' in cmd_output:
		output="disks agent health check failed on node "+MACHINE+", or unexpected output.\n"
		output+='Expected to see string \'"status": "OK"\'.\n'
		output+="Output was:\n"
		output+=cmd_output

		do_error(output, 105)




# Success

msg_output("OK")

exit(0)



