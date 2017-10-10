#!/bin/bash

# Copyright 2017 EMC Corporation
# Original author - Manny Caldeira

VERSION=0.0.7

# History

# 2017-04-10: 0.0.6 - Initial version.
# 2017-04-21: 0.0.7 - Added CM Task checks.


## The script makes an attempt to check the health of ECS disks.
## One must supply the MACHINES file which represents all the nodes in the VDC.
## ./DiskHealth.sh /root/MACHINES or maybe ./DiskHealth.sh /root/MACHINES.VDC
## One can also do export MAC=/root/MACHINES and then ./DiskHealth.sh


SetMeUp()
{
	echo; echo "   Disk health check script version ${VERSION}"

	if [ -z ${MAC} ] && [ -z ${ARG} ]
	then
		echo; echo "   Please specify the MACHINES file by argument or setting MAC environment variable."; exit 7
	fi

	if [ "x${MAC}" != "x"  ]
	then
		if [ ! -f ${MAC} ]; then echo; echo "   The file ${MAC} does not exist."; exit 6; fi
		XFIL=${MAC}
	elif [ "x${ARG}" != "x"  ]
	then
		if [ ! -f ${ARG} ]; then echo; echo "   The file ${ARG} does not exist."; exit 5; fi
		XFIL=${ARG}
	fi
}

Hal_Fabric()
{
	echo; echo; echo "   Checking the number of disks seen by cs_hal"; echo
	for X in $(grep -v "^#" ${XFIL})
	do
		N=$(ssh -q ${X} 'cs_hal list disks | grep "^total" | cut -d\  -f2')
		printf "%-38s %s\n" "   Output from ${X}:" "${N}"
	done > ${TD}/DC.hal

	cat ${TD}/DC.hal; echo
	TH=$(awk '{ sum += $NF } END { print sum }' ${TD}/DC.hal)
	printf "%-38s %s\n" "   Total disks as seen by HAL in this VDC:" "${TH}"

	echo; echo; echo "   Checking the Fabric Agent's view of the disks"

	## First, check to see if the agent is affected by Jira Fabric-3303
	for X in $(grep -v "^#" ${XFIL})
	do
		ssh -q ${X} '/opt/emc/caspian/fabric/cli/bin/fcli agent disk.disks' > ${TD}/Fabric.Test 2>&1
		grep "Failed to fill buffer" ${TD}/Fabric.Test > /dev/null 2>&1
		if [ $? -eq 0 ]
		then
			echo; echo "   A restart of the fabric agent needed on ${X}. Please go to this node and run systemctl restart fabric-agent."
		fi
	done

	for X in $(grep -v "^#" ${XFIL})
	do
		echo; echo "   Looking at ${X}"
		ssh -q ${X} '/opt/emc/caspian/fabric/cli/bin/fcli agent disk.disks 2>/dev/null| grep -e "health" -e "operational_status" -e "mount_status" | sort | uniq -c'
	done > ${TD}/DC.fcli
	TO=$(grep OPERATIVE ${TD}/DC.fcli | awk '{ sum += $1 } END { print sum }')
	cat ${TD}/DC.fcli; echo; printf "%-38s %s\n" "   Total disks as seen as OPERATIVE by the fabric agent in  this VDC:" "${TO}"
}

FCLI()
{
	echo; echo; echo "   Printing the FCLI view of the world."
	/opt/emc/caspian/fabric/cli/bin/fcli disks list | sed -e 's/^/      /'
}

SSM_Partitions()
{
	L=$1
	echo; echo; echo "   Checking Level ${L} SSM Partitions."
	echo; echo "   Dumping L${L} data (9101/diagnostic/SS/${L}/DumpAllKeys/SSTABLE_KEY?type=PARTITION) to ${TD}/L${L}.raw"
	curl -s "http://${IP}:9101/diagnostic/SS/${L}/DumpAllKeys/SSTABLE_KEY?type=PARTITION" | tr -d '\r' | sed '1s/http/\n\nhttp/' > ${TD}/L${L}.raw
	echo; echo "   Searching raw output for the next URL's and saving output to ${TD}/L${L}.http"
	grep -B1 schemaType ${TD}/L${L}.raw| grep "^http" | tr -d '\r' | sort > /${TD}/L${L}.http

	for X in $(cat ${TD}/L${L}.http)
	do
		Y=$(echo ${X} | awk -F"[/:]" '{print $4}')
		Z=$(echo ${X} | awk -F\: '{print $5 ":" $6}')
		echo; echo "   Looking at $Y $Z"
		curl -s "${X}&showvalue=gpb" | grep state | sort | uniq -c

		curl -s "${X}&showvalue=gpb" | sed '1s/schemaType/\n\nschemaType/' > ${TD}/SS.detail 2>&1
		TYN=$(grep "state" ${TD}/SS.detail | grep -v PARTITION_UP | wc -l | awk '{print $1}')
		if [ ${TYN} -gt 0 ]
		then
			tput setaf 3; tput bold; echo; echo "   Something wrong with one or more partitions for URL: ${X}&showvalue=gpb"; echo
			for TYP in $(grep "^state" ${TD}/SS.detail | sort -u | grep -v PARTITION_UP | awk '{print $2}')
			do
				grep ${TYP} ${TD}/SS.detail -B1 -A6 | sed -e 's/^/   /'
			done
			tput sgr0
		fi
	done > /${TD}/L${L}.detail

	cat /${TD}/L${L}.detail; echo
	grep state ${TD}/L${L}.detail | awk '{print $NF}' | sort -u > /tmp/L${L}.types

	for T in $(cat ${TD}/L${L}.types)
	do
		TT=$(grep ${T} ${TD}/L${L}.detail | awk '{ sum += $1 } END { print sum }')
		printf "%-38s %s\n" "   Total ${T}:" "${TT}"
	done
}

CM()
{
echo; echo; echo "   Checking on CM Tasks."

for XX in $(echo $CMT)
do
	XXC=$(curl -s "${IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=${XX}" | grep schemaType -c)
	printf "       %-21s %s  ${XXC}\n" "${XX}"
done
}

#  M A I N

ARG=$1

. /home/admin/DiskHealth.conf
SetMeUp
Hal_Fabric
FCLI
SSM_Partitions 1
SSM_Partitions 2
CM
echo; echo
