#!/usr/bin/python

# Copyright (c) 2016 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.

# Initialize global state variables

Global_LogMessage=False
upgradeType=None # Application or OS
upgradeMode=None # online or offline
topologyfile=None
provisionfile="conf/provisioning.txt"
extendfile=None
appfile=None
lastCompletedTask=None
screen_session=None
OSCompletedNodes=None
OSInProgressNode=None
OSCompletedStep=None

sku=None
skiplist=()
MACHINES=None


def getvars():
	return(globals())

