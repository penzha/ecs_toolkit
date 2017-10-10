#!/bin/bash

###########################################################################
# 1.0 - First release version, already runned on several customer's environment
#

YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m'

ECHO="/bin/echo -e"
SCRIPTNAME="$(basename $0)"

DEBUG=0
CHECKONLY=0

MULTI_THREAD=1
WORK_DIR=/tmp/object_check
mkdir -p ${WORK_DIR}

# TODO:
# Is it possible to not use temp files to store update sequences?

# search LS table to find all objects with object_owner_history, save it to file OBJECT_OWNER_HISTORY.$timestamp
function get_objownerhistory_from_ls {
    curl -s "http://${ip_addr}:9101/diagnostic/LS/0/DumpAllKeys/LIST_ENTRY?type=OBJECT_OWNER_HISTORY" | grep schemaType > ${WORK_DIR}/OBJECT_OWNER_HISTORY.$timestamp
	
	object_counts=$(cat ${WORK_DIR}/OBJECT_OWNER_HISTORY.$timestamp | wc -l)
	$ECHO "There are $object_counts objects has OBJECT_OWNER_HISTORY type and need to be scanned \n"
	
	if [ $object_counts -lt $MULTI_THREAD ]
	then
	    MULTI_THREAD=1
	fi
	
	mod=`expr $object_counts / $MULTI_THREAD`
	
	if [ `expr $object_counts % $MULTI_THREAD` == 0 ]
	then
	    split_num=$MULTI_THREAD
    else
	    split_num=`expr $MULTI_THREAD + 1`
	fi
	
	for i in $(seq 0 `expr $split_num - 1`)
	do
	    startLine=`expr $i \* $mod + 1`
		endLine=`expr $startLine + $mod - 1`
		
		if [ $endLine -gt $object_counts ]
		then
		    endLine=$object_counts
		fi
		
		awk "NR>=$startLine && NR<=$endLine {print}" ${WORK_DIR}/OBJECT_OWNER_HISTORY.$timestamp > ${WORK_DIR}/OBJECT_OWNER_HISTORY.$timestamp.$((i+1))
	done;
	
}

# extract one object's update info into different temp files (index by sequence)
function extractUpdateBySequence {
	lines=($(grep -n "schemaType" $1 | awk -F ":" '{print $1}'))
	 
    for i in $(seq 0 $((${#lines[@]}-1)))
    do
        count=$((i+1))
        len=$((${#lines[@]}-1))
        startLine=$((${lines[$i]}))
        if [ "$i" != "$len" ]
        then
            endLine=$((${lines[$((i+1))]}-2))
        else
            endLine=$(cat $1 | wc -l)
        fi
        awk "NR>=$startLine && NR<=$endLine {print}" $1 > $1.$((i+1))
    done
}

# check the last update, if its key "dmarker" is true then go to next step. If not, skip this object.
# check the previous update of the last one, if its key "has-ownerhistory" is true and the last object does not have key "has-ownerhistory", then report this objects.
function detect_ownerhistory_issue {
    last_update_isowner=$(grep -A1 'current-zone-is-owner' ${WORK_DIR}/update.$3.$1.$timestamp.$2 | grep -v 'current-zone-is-owner' | awk -F "\"" '{print $2}')

    last_update_dmarker=$(grep -A1 'dmarker' ${WORK_DIR}/update.$3.$1.$timestamp.$2 | grep -v 'dmarker' | awk -F "\"" '{print $2}')
	
    last_update_hasownership=$(grep -A1 'has-ownerhistory' ${WORK_DIR}/update.$3.$1.$timestamp.$2 | grep -v 'has-ownerhistory' | awk -F "\"" '{print $2}')
	
	previous_last_update_count=$(($2-1))
	previous_last_update_hasownership=$(grep -A1 'has-ownerhistory' ${WORK_DIR}/update.$3.$1.$timestamp.$previous_last_update_count | grep -v 'has-ownerhistory' | awk -F "\"" '{print $2}')
	
	if [ "$last_update_dmarker" = "true" ]
	then
	    if [ "$previous_last_update_hasownership" = "true" ]
		then
			if [ -z "$last_update_hasownership" ]
			then
		        printf "Object: $1 detect has-ownerhistory missing issue. \n"
				echo "Object: $1 detect has-ownerhistory missing issue." >> ${WORK_DIR}/result.$timestamp
		    fi
		fi
	fi
}

# retrieve oid according to parent/child (save it to file oid_update.tmp during debug mode)
# save each update info to separate files
function get_oid_update {
    item_num=$1
	
    while read line; do
        parent=$(echo $line | awk -F " " '{print $6}')
		child=$(echo $line | tr -d '\r' | awk -F "child " '{print $2}')
		
		printf "Parsing $parent:$child ...... \n"
		debug_message "Parsing $parent:$child ...... \n"
        
		# caculate oid from parent/child instead of query it from LS table. 
		oid=$(echo -n "$parent.$child" | sha256sum | awk -F " " '{print $1}')
		debug_message "$oid"
        
        # get query url for retrieve update
		if [[ $DEBUG -eq 1 ]]; then
		    debug_message "$(curl -s "http://${ip_addr}:9101/diagnostic/OB/0/DumpAllKeys/OBJECT_TABLE_KEY?type=UPDATE&objectId="$oid"" | grep -B1 schemaType)"
		fi
		
        ob_url="$(curl -s "http://${ip_addr}:9101/diagnostic/OB/0/DumpAllKeys/OBJECT_TABLE_KEY?type=UPDATE&objectId="$oid"" | grep -B1 schemaType | grep -v schemaType | tr -d '\r' | sed 's/<.*>//g')"
        
		if [ -z "$ob_url" ]; then
		    printf "could not find ob_url \n"
		    continue
	    fi

		if [[ $DEBUG -eq 1 ]]; then
		    debug_message "$(curl -s ""$ob_url"&useStyle=raw&showvalue=gpb")"
		fi
		
        # get update info
        curl -s ""$ob_url"&useStyle=raw&showvalue=gpb" | grep -A1 'schemaType\|current-zone-is-owner\|omarker\|dmarker\|has-ownerhistory' >> ${WORK_DIR}/update.$item_num.$oid.$timestamp
        
        # save update info into array update[]
        update_count=$(grep 'schemaType' ${WORK_DIR}/update.$item_num.$oid.$timestamp | wc -l)
		
		if [ $update_count -gt 1 ]
		then
		    extractUpdateBySequence ${WORK_DIR}/update.$item_num.$oid.$timestamp
		    detect_ownerhistory_issue $oid $update_count $item_num
		fi
 
        debug_message "============ \n"
        
		#rm -f ${WORK_DIR}/update.$item_num.$oid.$timestamp*
		# use find . -name *** | xargs rm -f to handle the situation where we have huge amount files need to be deleted at one time
		#$ECHO "find ${WORK_DIR} -name \"update.$item_num.$oid.$timestamp*\" | xargs rm -rf \n"
		find ${WORK_DIR} -name "update.$item_num.$oid.$timestamp*" | xargs rm -rf

    done < ${WORK_DIR}/OBJECT_OWNER_HISTORY.$timestamp.$item_num
}

function debug_message {

	local _MESSAGE="$*"
 
	if [[ $DEBUG -eq 1 ]]; then
		sudo bash -c "echo -e '$_MESSAGE' >> '${WORK_DIR}/oid_update.$timestamp'"
	fi
}

function usage
{
  $ECHO "Usage:  $SCRIPTNAME [-h] [-objects] [-debug | -ip ipaddr | -threads thread_num]"
  $ECHO ""
  $ECHO "Options:"
  $ECHO "\t-h: Help         - This help screen"
  $ECHO "\t-debug: Debug    - Produces additional debugging output"
  $ECHO "\t-ip:             - used when customer using network separation to specify data ip"
  $ECHO "\t-threads: num    - simulate multiple threads"
  $ECHO "\t-objects         - only check how many objects need to be scanned"

  exit 1

}

function parse_args
{
	while [ -n "$1" ]
	do
		case $1 in
		"" )
			;;
		"-debug" )
			DEBUG=1
			shift 1
			;;
		"-h" )
			usage
			;;
		"-ip" )
			ip_addr=$2
			shift 2
			;;
		"-threads" )
			MULTI_THREAD=$2
			shift 2
			;;
		"-objects" )
		    CHECKONLY=1
			shift 1
			;;
		*)
			$ECHO "ERROR:  Invalid option '${1}'"
			$ECHO ""
			usage
			;;
		esac
	done # Loop through parameters
}

function clearFiles {
	find ${WORK_DIR} -name "update.*.$timestamp*" | xargs rm -rf
}

######## Main function part #######

timestamp=$(date +"%Y%m%d-%H%M%S")
ip_addr=`hostname -i`

$ECHO "object_ownerhistory_check.sh version 1.0\n"

if [ $# -gt 0 ]
then
    parse_args $*
fi

get_objownerhistory_from_ls

if [ $CHECKONLY -eq 0 ]
then
    $ECHO '' > ${WORK_DIR}/result.$timestamp

    #printf "split_num: $split_num \n"
    for i in $(seq 1 $split_num)
        do {
            get_oid_update $i
	       }&
        done

    wait

    $ECHO "Please find the objects with ownerhistory problem in ${WORK_DIR}/result.$timestamp \n"

    clearFiles
fi
