#!/bin/bash

# Modifications (MOD) / Fixes by Jason Klein:

# Modified for Multi-Rack (MR)
# Modified to use Master IP for data node on optional post check.  Currently commented out
# Modified viprexec commands to include necessary escape characters.  Also removed -c as its not needed
# --> To make this work, it required a lot of code.  It is not pretty, but was required
# Modified viprexec commands to accuratly collect and use Public IP of the very node where command is being run on
# --> Previously, hostname -i would always use the same IP where the script was run from
# ----> In other words, if you ran the script on node 1, it would use IP from node one on all nodes.  In turn it was not possible to correct phantom issue
# Modified prompt statement
# Added min output option
# Added usage
# Added check for hwState. If not found, it's created.  Done with perl, get between DISK ID and first bracket " } ]".  Check if hwState exists.  If not, add dict after line with ""groups" : [ ],"
# Added 2nd check to L1 and L2 PD Removed API calls.  If they are still found not changed, json file is updated.  This happens in same loop as hwstate
# --> Done with awk and perl.  First find all between DISK ID and first bracket " } ]", and get line number of PD Permanent Down.  Then replace line number with perl
# Fixed --help option in usage
# Addressed cosmetics
# 5.2.3  Addressed where primitive hwState is placed.  This is now placed in the empty groups key.  Also updated search for hwState.
# 5.2.6  Enhanced to handle scenario where hwState is found but has value other than "REMOVED"
#        Addressed issue where check for monitor service running, picked up on additional PID.
#        Added loop to perl replace commands for PD REMOVED update and hwState value update.  This was needed as more than 1 instance in the same file for same disk could be found.
#        --> However, even with new loop, additional instance sometimes does not get updated.  Workaround is to run it multiple times until it does.

# Check for sudo:

if (( $EUID != 0 )); then
    echo "Please run with sudo. Now exiting"
    exit
fi

display_usage() {
        echo "
Tool \"setDiskstate\" performs the following:

Version 5.2.6

1) Corrects Phantom Disks."
        echo
        echo "Usage:"
        echo
        echo "bash $0 <disk>"
        echo
        echo "or for minimal output:"
        echo
        echo "bash $0 <disk> min_output
"
        }

        if [ $# -gt 2 ]
        then
                display_usage
                exit 1
        elif [[ $1 == "--help" ]] ||  [[ $1 == "-h" ]]
        then
                display_usage
                exit 0
        elif [[ $# -eq 2 ]]
        then
                export DISK=$1
                LIMIT_OUT=$2
        elif [[ $# -eq 1 ]]
        then
                export DISK=$1
                LIMIT_OUT=
        fi

# Note, couldnt create variable for arg 2.  Needed more time to determine escape characters

# Check if min_output arg is found:

DISPLAY=false

if [[ "$LIMIT_OUT" = min_output ]]
then
        DISPLAY=true
fi

# Get private IP's from all racks (MOD):

getclusterinfo -i | awk '{print $1}' | awk '/Node/,/Status/' | egrep -v 'Node|Ip|===============|Status' > /home/admin/hosts

# get a dump of the values between the Parition and the SSTable Entry
RESP=$(curl -ks https://`hostname -i`:4443/stat/aggregate | tac | sed -n -e '/'"$DISK"'/,/SSTable/ p' | tac | grep -e "SSTable-" -e "SS-" -e "PD-" -e "REMOVED" -e "UNKOWN" | dos2unix)

# Build the values we need to set the correct HWState value for for the L1 owner
L1_SS_ID="$(echo  $RESP | grep -oP 'SSTable-urn\S+_1:')"
L1_PART_IP="$(echo $RESP | grep -oP '(?<=_1:", "id" : ")SS-\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')"

# Data Node IP L1 (MOD):
MASTER_L1_PART_IP=$(echo $L1_PART_IP | awk -F '[-]' '{print "ssh admin@"$2 " ssh master hostname -i"}' | bash | tail -n1)

# Echo L1 values for visual validation
echo
echo "L1 Partition IP: ${L1_PART_IP}"
echo "L1 SSTable URN: ${L1_SS_ID}"

# Build the values we need to set the correct HWState value for for the L1 owner
L2_SS_ID="$(echo  $RESP | grep -oP 'SSTable-urn\S+_2:')"
L2_PART_IP="$(echo $RESP | grep -oP '(?<=_2:", "id" : ")SS-\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')"

# Data Node IP L2 (MOD):
MASTER_L2_PART_IP=$(echo $L2_PART_IP | awk -F '[-]' '{print "ssh admin@"$2 " ssh master hostname -i"}' | bash | tail -n1)

# Echo L2 values for visual validation
echo
echo "L2 Partition IP: ${L2_PART_IP}"
echo "L2 SSTable URN: ${L2_SS_ID}"

# Modified prompt statement when checking if user wants to continue (MOD):
echo
read -p "[`date +%m-%d-%Y_%T`]:If there are valid values for each item above, Enter \"Continue\" to proceed.  Otherwise enter any key to abort:
" RESP_1

if [[ "$RESP_1" = Continue ]] || [[ "$RESP_1" = continue ]]
then
        echo "Will now continue."
else
        exit 1
fi

echo
echo "Setting L1 to PD Removed"

# viprexec command L1.  Includes collection and use of actual public ip where viprexec runs the command (MOD):

if [[ "$DISPLAY" = false ]]
then
        viprexec -i -f /home/admin/hosts "echo -n curl -ks https:// | awk ''{printf\ $\0\;system\(\\\"echo\ hostname\ -i\ \|\ bash\\\"\)\;print\ \\\":4443/stat/update?path=ssm/sstable/${L1_SS_ID}/${L1_PART_IP}/partitions/${DISK}/state\\\\\\\\\&value=\\\\\\\"PD%20Removed\\\\\\\"\\\"}'' | awk ''BEGIN{RS=\\\"\\\"}\{print\ RS\ $\1\,$\2\,$\3$\4}'' | bash"
else
        viprexec -i -f /home/admin/hosts "echo -n curl -ks https:// | awk ''{printf\ $\0\;system\(\\\"echo\ hostname\ -i\ \|\ bash\\\"\)\;print\ \\\":4443/stat/update?path=ssm/sstable/${L1_SS_ID}/${L1_PART_IP}/partitions/${DISK}/state\\\\\\\\\&value=\\\\\\\"PD%20Removed\\\\\\\"\\\"}'' | awk ''BEGIN{RS=\\\"\\\"}\{print\ RS\ $\1\,$\2\,$\3$\4}'' | bash" | egrep -B8 '</error>|"value" : "PD Removed'
fi

echo
echo "Setting L2 to PD Removed"

# viprexec command L2.  Includes collection and use of actual public ip where viprexec runs the command (MOD):

if [[ "$DISPLAY" = false ]]
then
        viprexec -i -f /home/admin/hosts "echo -n curl -ks https:// | awk ''{printf\ $\0\;system\(\\\"echo\ hostname\ -i\ \|\ bash\\\"\)\;print\ \\\":4443/stat/update?path=ssm/sstable/${L2_SS_ID}/${L2_PART_IP}/partitions/${DISK}/state\\\\\\\\\&value=\\\\\\\"PD%20Removed\\\\\\\"\\\"}'' | awk ''BEGIN{RS=\\\"\\\"}\{print\ RS\ $\1\,$\2\,$\3$\4}'' | bash"
else
        viprexec -i -f /home/admin/hosts "echo -n curl -ks https:// | awk ''{printf\ $\0\;system\(\\\"echo\ hostname\ -i\ \|\ bash\\\"\)\;print\ \\\":4443/stat/update?path=ssm/sstable/${L2_SS_ID}/${L2_PART_IP}/partitions/${DISK}/state\\\\\\\\\&value=\\\\\\\"PD%20Removed\\\\\\\"\\\"}'' | awk ''BEGIN{RS=\\\"\\\"}\{print\ RS\ $\1\,$\2\,$\3$\4}'' | bash" | egrep -B8 '</error>|"value" : "PD Removed'
fi

# Check if hwState is missing.  Report if PD exists in statistics.json.  If so report if hw state is missing.  If so, add it (MOD for EVERYTHING below this line):

export DATE=$(date +%s)

echo; echo "Checking for missing hwState, correct value for hwState, and if Current State still does not reflect PD Removed..."; echo

# viprexec cmd to check all nodes.  Add nodes with mssing hwState to list:

CUR_STATE_DOWN_NODES=$(viprexec -i -f /home/admin/hosts "if sed -n ''/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/^\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:/p'' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json | head -n -2 | grep ''PD\ Permanent\ Down'' >/dev/null; then echo PD Permanent Down FOUND; else echo PD Permanent Down NOT FOUND; fi" | grep -B1 'PD Permanent Down FOUND' | grep Output | awk '{print $5}')

HWSTATE_MISSING_NODES=$(viprexec -i -f /home/admin/hosts "if awk ''/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/\ \ \ \ \ \ \ \ \ \ \ \ \},\ \{/'' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json  | grep ${DISK} >/dev/null; then echo DISK FOUND; else echo DISK NOT FOUND; fi; if awk ''/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/\ \ \ \ \ \ \ \ \ \ \ \ \},\ \{/'' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json | grep ''\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ :\ \\\\\\\"hwState\\\\\\\",'' >/dev/null; then echo hwState FOUND; else echo hwState NOT FOUND; fi" | grep -B2 'hwState NOT FOUND' | grep -B1 -A1 'DISK FOUND' | grep Output | awk '{print $5}')

HWSTATE_WRONG_NODES=$(viprexec -i -f /home/admin/hosts "if awk ''/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/\ \ \ \ \ \ \ \ \ \ \ \ \},\ \{/{print\ NR\\\":\\\"$\0}'' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json | awk ''/.*\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ :\ \\\\\\\"hwState\\\\\\\"\,/,/.*:\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \},\ \{/'' | grep value | grep -v REMOVED >/dev/null; then echo hwState_WRONG; fi" | grep -B2 hwState_WRONG | grep Output | awk '{print $5}')

# If list has nodes, run below loop to add hwState for PD in statistics.json, for that specific node.

if [[ $HWSTATE_MISSING_NODES != "" ]] || [[ $CUR_STATE_DOWN_NODES != "" ]] || [[ $HWSTATE_WRONG_NODES != "" ]]
then

	if [[ $HWSTATE_MISSING_NODES != "" ]]
	then
		echo "The following nodes have a missing hwState for Disk ${DISK}:"
		for line in $HWSTATE_MISSING_NODES; do echo $line; done
		echo
	else
		echo "HwState is not missing."; echo
	fi

	if [[ $HWSTATE_WRONG_NODES != "" ]]
	then
		echo "The following nodes have hwState, but have an incorrect value for Disk ${DISK}:"
		for line in $HWSTATE_WRONG_NODES; do echo $line; done
		echo
	else
		echo "hwState has correct value."; echo
	fi

	if [[ $CUR_STATE_DOWN_NODES != "" ]]
	then
		echo "The following nodes still do not have current state set to PD Removed for Disk ${DISK}:"
		for line in $CUR_STATE_DOWN_NODES; do echo $line; done
		echo
	else
		echo "Current State was initially changed correctly with API."; echo
	fi

	if [[ $HWSTATE_MISSING_NODES != "" && $CUR_STATE_DOWN_NODES != "" ]] || [[ $HWSTATE_WRONG_NODES != "" && $CUR_STATE_DOWN_NODES != "" ]]
	then
		echo "Combinding both lists.  Will check for both current state, missing hwState, and incorrect value for hwState. If needed, will fix all at same time."
	fi

	COMBO=$(echo $CUR_STATE_DOWN_NODES; echo $HWSTATE_MISSING_NODES; echo $HWSTATE_WRONG_NODES)

	for line in $COMBO
	do
		echo
		echo "Starting repair on node $line"

		echo "Stopping Monitoring Service on node"

		echo "CMD to restart monitor service on node $line (ONLY use if svc does not come back up):"
		echo "ssh $line ps -ef 2>&1 | grep stat | grep monitor | sed 's/\/opt\/storageos\/bin\/monitor/\n\/opt\/storageos\/bin\/monitor/g' | grep opt | awk '{print \"ssh $line sudo dockobj \"\$0}'" | bash

		MON_RESTART_CMD=$(echo "ssh $line ps -ef 2>&1 | grep stat | grep monitor | sed 's/\/opt\/storageos\/bin\/monitor/\n\/opt\/storageos\/bin\/monitor/g' | grep opt | awk '{print \"ssh $line sudo dockobj \"\$0}'" | bash)

		# Stop Monitor Service:

		echo "ssh $line ps -ef 2>&1 | grep stat | grep monitor | awk '{print \"sudo ssh $line kill \"\$2}'" | bash | bash

		# Sleep 5 seconds and check if monitor service is stopped.  If not, check back every 5 seconds, up tp 60 times.  Otherwise, exit.

		MON_STAT=$(ssh $line ps -ef 2>&1 | grep stat | grep monitor | egrep -v 'grep|poll|SCREEN' | wc -l)

		COUNT=0
		until [[ $COUNT -gt 60 ]] || [[ $MON_STAT -lt 1 ]]
		do
			echo "Waiting for monitor service to stop.  Will check back in 5 seconds."
			sleep 5
			let COUNT=COUNT+1
			MON_STAT=$(ssh $line ps -ef 2>&1 | grep stat | grep monitor | egrep -v 'grep|poll|SCREEN' | wc -l)
		done

		if [[ $MON_STAT -gt 0 ]]
		then
			echo "Monitor service could not be stopped.  Now exiting."
			exit 1
		fi

		ssh $line cp /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json_`date +%m-%d-%Y_%H-%M-%S`_${line}_BAK > /dev/null

		echo "Backup file created on node $line `ssh $line ls -lrth /opt/emc/caspian/fabric/agent/services/object/main/log/ 2>&1 | grep statistics.json_ | tail -n1 | awk '{print "/opt/emc/caspian/fabric/agent/services/object/main/log/"$NF}'`"

		echo "Editing original file..."

##############

		# Check for value PD Permanent Down in current state. Get line number if found:

		# OLD = CS_LINE_NUM=$(echo "sudo ssh $line awk '/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \}\ \]/{print\ NR\\\":\\\"$\0}'' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json 2>&1 | grep ''PD\ Permanent\ Down'' | awk -F ''[:]'' ''{print\ $\1}'" | bash)

		# v2 = CS_LINE_NUM=$(echo "sudo ssh $line awk '/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \}\ \]/{print\ NR\\\":\\\"$\0}' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json 2>&1 | grep 'PD\ Permanent\ Down' | awk -F '[:]' '{print \$1}'" | bash)

		CS_LINE_NUM=$(echo "sudo ssh $line sed -n '/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/^\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:/{=\;p\;}' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json |sed '{N;s/\n/ /}' | head -n -2 | grep 'PD\ Permanent\ Down' | awk '{print \$1}'" | bash)

		# Check if line number was reported. If found replace PD Permanent Down with PD Removed:

		if [[ $CS_LINE_NUM != "" ]]
		then
			for x in $CS_LINE_NUM
			do
				sleep 5
				echo "sudo ssh $line perl -i -pe 's/PD\ Permanent\ Down/PD\ Removed/g\ if\ $.\ ==\ ${x}' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json" | bash
			done
			fi

##############

		# Check hwState value for value other than "REMOVED". Get line number if found:

		HWSV_LINE_NUM=$(echo "sudo ssh $line awk '/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ \:\ \\\\\\\"${DISK}\\\\\\\"\,/,/\ \ \ \ \ \ \ \ \ \ \ \ \},\ \{/{print\ NR\\\":\\\"$\0}' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json 2>&1 | awk '/.*                  \"id\" : \"hwState\"\,/,/.*                \}, \{/' | grep value | grep -v REMOVED | awk -F '[:]' '{print \$1}'" | bash)

		# Check if line number was reported. If found replace line with correction:

		if [[ $HWSV_LINE_NUM != "" ]]
		then
			for x in $HWSV_LINE_NUM
			do
				sleep 5
				echo "sudo ssh $line perl -i -pe 's/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\"value\\\"\ :\ \\\".*/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\"value\\\"\ :\ \\\"REMOVED\\\"/g\ if\ $.\ ==\ ${x}' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json" | bash
			done
		fi

#############

		# This perl command only edits file in place, ONLY if hwState isn't in it's results. Not pretty, but needed:
		sleep 2
		echo "sudo ssh $line perl -i -0pe 's/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ :\ \\\\\\\"${DISK}\\\\\\\",\\\n.*\\\n.*\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"groups\\\\\\\"\ :\ \\\[\ ],/\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ :\ \\\\\\\"${DISK}\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"description\\\\\\\"\ :\ \\\\\\\"\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"timestamp\\\\\\\"\ :\ 1488564738871,\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"groups\\\\\\\"\ :\ \[\ {\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"type\\\\\\\"\ :\ \\\\\\\"group\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ :\ \\\\\\\"status\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"description\\\\\\\"\ :\ \\\\\\\"\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"tag\\\\\\\"\ :\ \\\\\\\"dashboard\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"timestamp\\\\\\\"\ :\ ${DATE}668,\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"groups\\\\\\\"\ :\ \[\ \],\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"primitives\\\\\\\"\ :\ \[\ {\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"type\\\\\\\"\ :\ \\\\\\\"string\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"id\\\\\\\"\ :\ \\\\\\\"hwState\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"description\\\\\\\"\ :\ \\\\\\\"Disk\ hw\ state\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"tag\\\\\\\"\ :\ \\\\\\\"\\\\\\\",\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"timestamp\\\\\\\"\ :\ ${DATE}668,\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"aggregationTypes\\\\\\\"\ :\ \[\ \\\\\\\"LATEST\\\\\\\"\ \],\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \\\\\\\"value\\\\\\\"\ :\ \\\\\\\"REMOVED\\\\\\\"\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \}\ \]\\\n\ \ \ \ \ \ \ \ \ \ \ \ \ \ \}\ \],/g' /opt/emc/caspian/fabric/agent/services/object/main/log/statistics.json" | bash

		echo "Restarting Monitoring Service in 10 seconds."

		sleep 10

		$MON_RESTART_CMD
		
		echo "Finished repair on node $line.  Please wait 5 minutes for correction to reflect in UI".

	done

else
	echo "hwState is not missing, hwState has correct value, and PD Removed is set."
fi

echo
exit 0