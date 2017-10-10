#!/usr/bin/python

import sys
import os

subargs=""

CurPathName=os.path.dirname(__file__)

for arg in sys.argv[1:]:
	subargs=subargs+" "+arg


cmd=CurPathName+"/prechecks.py --postcheck"+subargs

#print "Postcheck:  Calling "+cmd
os.system(cmd)

