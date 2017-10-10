#!/usr/bin/python



import subprocess
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


# Main logic

parse_args(sys.argv[1:])

run_multi_cmd("mv /srv/tftpboot/pxelinux.cfg/new.file /srv/tftpboot/pxelinux.cfg/default", noErrorHandling=True)

for MACHINE in get_machines():
	result=run_cmd("if [[ -f /srv/tftpboot/pxelinux.cfg/default ]]; then echo 'found'; fi", MACHINE=MACHINE, noErrorHandling=True)
	if result['stdout'].strip() != "found":
		err_output("ERROR: EnablePXE(): /srv/tftpboot/pxelinux.cfg/default was not found on '"+MACHINE+"'")
		exit(100)

print "OK"
