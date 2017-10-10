#!/usr/bin/python



import sys
import os
import getopt
CurScriptName=os.path.basename(__file__)
CurPathName=os.path.dirname(__file__)
sys.path.append(CurPathName+"/../lib/")

import svc_upgrade_common as common
from svc_upgrade_common import *


CurScriptName=os.path.basename(__file__)


# List of XDoctor errors/warnings messages that should be excluded

ExcludeList=["Message  = The following nodes were recently rebooted",
             "Message  = The following containers were recently restarted",
			 "Message  = The /root/MACHINES files are not consistent across the rack.",
			 "Message  = Patch required for STORAGEOS file(s)."
			 ]

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


# Main logic

parse_args(sys.argv[1:])

sudoicmd=get_sudoicmd()

msg_output("Running xdoctor", req_loglevel=1)

cmd="ssh master.rack xdoctor"
output=run_cmd(cmd, noErrorHandling=True, do_sudo=True)



msg_output("Getting latest report", req_loglevel=1)

cmd=sudoicmd+"ssh master.rack xdoctor -r | grep -a1 Latest | tail -1"
output=run_cmd(cmd)

LatestReport=output['stdout'].strip()[4:35]  # Output has unprintable characters, strip out only the ones we need
#LatestReport="xdoctor -r -a 2016-08-04_170002" #clean
#LatestReport="xdoctor -r -a 2016-08-04_175109" #error

if not LatestReport.startswith("xdoctor -r -a"):
	# Expect output that looks like "xdoctor -r -a 2016-08-04_044801", if not then we have
	# an unexpected condition

	err_output("ERROR: Could not determine latest xdoctor report.")
	err_output("Output was:")
	err_output("\t'"+LatestReport+"'")

	exit (100)


cmd=sudoicmd+" ssh master.rack "+LatestReport+" -WEC | grep -v 'Displaying xDoctor Report'"
output=run_cmd(cmd, noErrorHandling=True)

# There are a number of errors or warnings that XDoctor produces that we don't need to fail on, or display the user.

# Break the report down into different events, in a List.  Then filter out events that should be ignored.
# Output will be something like:

#        Timestamp    = 2016-11-10_160606
#            Category = platform
#            Source   = md5sum
#            Severity = ERROR
#            Node     = 169.254.173.1
#            Message  = The /root/MACHINES files are not consistent across the rack.
#            RAP      = RAP040
#            Solution = 489950
#
#        Timestamp    = 2016-11-17_045704
#            Category = Docker
#            Source   = OS
#            Severity = WARNING
#            Node     = 169.254.173.2
#            Message  = The following containers were recently restarted
#            Extra    = {'fabric-lifecycle': '1:23:35', 'fabric-zookeeper': '1:23:35', 'object-main': '1:23:35'}
#
#        Timestamp    = 2016-11-17_045704
#            Category = Docker
#            Source   = OS
#            Severity = WARNING
#            Node     = 169.254.173.6
#            Message  = The following containers were recently restarted
#            Extra    = {'object-main': '4:57:43'}


ReportOutput=output['stdout'].strip()

OrigReportEvents=ReportOutput.split("Timestamp")

ReportEvents=list()
for Event in OrigReportEvents:

	IncludeEvent=True

	if not "Category" in Event:
		IncludeEvent=False
		continue

	for ExcludeItem in ExcludeList:
		if ExcludeItem in Event:
			IncludeEvent=False
			continue
	if IncludeEvent:
		ReportEvents.append(Event)

if len(ReportEvents) > 0:
	# xdoctor detected problems

	err_output("ERROR: XDoctor detected problems.")
	err_output("Output was:")

	for Event in ReportEvents:
		err_output(bcolors.ENDC+"Timestamp"+Event)

	err_output("You can review this report by running")
	err_output("\t'sudo -i "+LatestReport+" -WEC'")

	exit (101)


