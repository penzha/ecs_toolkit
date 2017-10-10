#!/bin/bash

YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m'

ECHO="/bin/echo -e"
SCRIPTNAME="$(basename $0)"

# search LS table to find all objects with object_owner_history, save it to file OBJECT_OWNER_HISTORY.tmp
function get_objownerhistory_from_ls {
    #curl -s "http://`hostname -i`:9101/diagnostic/LS/0/DumpAllKeys/List_ENTRY?type=OBJECT_OWNER_HISTORY" | grep -B1 schemaType > /tmp/OBJECT_OWNER_HISTORY.$timestamp
    curl -s "http://${ip_addr}:9101/diagnostic/LS/0/DumpAllKeys/LIST_ENTRY?type=OBJECT_OWNER_HISTORY" | grep schemaType > $(pwd)/OBJECT_OWNER_HISTORY.$timestamp
	#object_lines=($(grep "schemaType" $(pwd)/OBJECT_OWNER_HISTORY.$timestamp  | awk -F ":" '{print $1}'))
	
}

# extract one object's update info into different temp files (index by sequence)
function extractUpdateBySequence {

    printf "update info file: $1 \n"
	
	lines=($(grep -n "schemaType" $1 | awk -F ":" '{print $1}'))
	
	printf "lines: ${lines[*]} \n"
	
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
    last_update_isowner=$(grep -A1 'current-zone-is-owner' $(pwd)/update.$oid.$timestamp.$2 | grep -v 'current-zone-is-owner' | awk -F "\"" '{print $2}')
    printf "last_update_isowner: $last_update_isowner \n"

    last_update_dmarker=$(grep -A1 'dmarker' $(pwd)/update.$oid.$timestamp.$2 | grep -v 'dmarker' | awk -F "\"" '{print $2}')
    printf "last_update_dmarker: $last_update_dmarker \n"
	
    last_update_hasownership=$(grep -A1 'has-ownerhistory' $(pwd)/update.$oid.$timestamp.$2 | grep -v 'has-ownerhistory' | awk -F "\"" '{print $2}')
    printf "last_update_hasownership: $last_update_hasownership \n"
	
	previous_last_update_count=$(($2-1))
	printf "previous_last_update_count: $previous_last_update_count \n"
	previous_last_update_hasownership=$(grep -A1 'has-ownerhistory' $(pwd)/update.$oid.$timestamp.$previous_last_update_count | grep -v 'has-ownerhistory' | awk -F "\"" '{print $2}')
	printf "previous_last_update_hasownership: $previous_last_update_hasownership \n"
	
	#if [ $last_update_dmarker = "true" ]
	if [ $last_update_isowner = "true" ]
	then
	    printf "last_update_dmarker is true \n"
		printf "check: ${#last_update_hasownership} \n"
	    if [ $previous_last_update_hasownership = "true" ]
		then
		    printf "previous_last_update_hasownership is true \n"
			if [ -z "$last_update_hasownership" ]
			then
		        printf "Object: $1 detect has-ownerhistory missing issue. \n"
		    fi
		fi
	fi
}

# retrieve oid according to parent/child (save it to file oid_update.tmp during debug mode)
# retrieve update info for the oid and save it to file update.$oid.$timestamp, parse file and save each update info into array update[].
# update[index] = 'dmarker;has-ownerhistory' (? need consider the order of dmarker and has-ownerhistory ?)
function get_oid_update {
    while read line; do
        parent=$(echo $line | awk -F " " '{print $6}')
        #printf "parent:  $parent \n"
		child=$(echo $line | tr -d '\r' | awk -F "child " '{print $2}')
        #printf "child:  $child \n"
		printf "Parsing $parent:$child ...... \n"
        
        # get query url for retrieve oid
        # has problem when child contain space? how to make it exact match?
		
        curl -s "http://${ip_addr}:9101/diagnostic/LS/0/DumpAllKeys/LIST_ENTRY?type=KEYPOOL&parent="$parent"&child="$child"&showvalue=gpb" | grep -w -B1 "schemaType LIST_ENTRY type KEYPOOL parent $parent child $child" >> $(pwd)/oid_update.$timestamp
        ls_url_temp="$(curl -s "http://${ip_addr}:9101/diagnostic/LS/0/DumpAllKeys/LIST_ENTRY?type=KEYPOOL&parent="$parent"&child="$child"&showvalue=gpb" | grep -w -B1 "schemaType LIST_ENTRY type KEYPOOL parent $parent child $child" | grep -v schemaType | tr -d '\r' | sed 's/<.*>//g' | awk -F "child" '{print $1}')"
        printf "ls_url_temp: $ls_url_temp \n"
		#child_suffix="$child"
		#printf "child_suffix: $child_suffix \n"
		#ls_url=$ls_url_temp"child=$child_suffix"
		ls_url=\"$ls_url_temp"child=\"$child"\"\"
		echo $ls_url
		printf "ls_url: $ls_url \n"
        
        # get oid
        # same problem as above when child contain space? ls_url we get here is not complete for such situation. 
		#echo \"$ls_url\"
		printf "1111 \n"
		curl -s $ls_url
		echo "curl -s $ls_url"
		printf "2222 \n"
        #curl -s "$ls_url" | grep oid | awk -F "\"" '{print $2}' >> $(pwd)/oid_update.$timestamp
        #oid="$(curl -s "$ls_url" | grep oid | awk -F "\"" '{print $2}')"
        #printf "oid: $oid \n"
        
        # get query url for retrieve update
        #curl -s "http://${ip_addr}:9101/diagnostic/OB/0/DumpAllKeys/OBJECT_TABLE_KEY?type=UPDATE&objectId="$oid"" | grep -B1 schemaType >> $(pwd)/oid_update.$timestamp
        #ob_url="$(curl -s "http://${ip_addr}:9101/diagnostic/OB/0/DumpAllKeys/OBJECT_TABLE_KEY?type=UPDATE&objectId="$oid"" | grep -B1 schemaType | grep -v schemaType | tr -d '\r' | sed 's/<.*>//g')"
        #printf "ob_url: $ob_url \n"
        
        # get update info
        #curl -s ""$ob_url"&useStyle=raw&showvalue=gpb" | grep -A1 'schemaType\|current-zone-is-owner\|omarker\|dmarker\|has-ownerhistory' >> $(pwd)/update.$oid.$timestamp
        
        # save update info into array update[]
        #update_count=$(grep 'schemaType' $(pwd)/update.$oid.$timestamp | wc -l)
		#printf "update_count: $update_count \n"
		
		#if [ $update_count -gt 1 ]
		#then
		#    extractUpdateBySequence $(pwd)/update.$oid.$timestamp
		#    detect_ownerhistory_issue $oid $update_count
		#fi
 
        echo '============' >> $(pwd)/oid_update.$timestamp
		printf "============ \n"
        
    done < $(pwd)/OBJECT_OWNER_HISTORY.$timestamp
}

function usage
{
  $ECHO "Usage:  $SCRIPTNAME"
  $ECHO "           | [-ip ipaddr]"
  $ECHO ""
  $ECHO "Options:"
  $ECHO "\t-h: Help         - This help screen"
  $ECHO
  $ECHO "\t-debug: Debug    - Produces additional debugging output"
  $ECHO "\t-ip:      		- used when customer using network separation to specify data ip"

  exit 1

}

function parse_args
{
#printf "option num: $# \n"
#echo "$1 \n"
#echo "$2 \n"
#echo "options: $@ \n"

	case $1 in
	"" )
		;;
    "-debug" )
        DEBUG=1
        ;;
    "-h" )
        usage
        ;;
    "-ip" )
	    printf "step 2 \n"
        ip_addr=$2
        ;;
    *)
	    printf "step 3 \n"
		print_message "ERROR:  Invalid option '${1}'"
		print_message ""
        usage
        ;;
	esac
}

######## Main function part #######

timestamp=$(date +"%Y%m%d-%H%M%S")
ip_addr=`hostname -i`

if [ $# -gt 0 ]
then
    printf "go into parse_args \n"
    parse_args $*
fi

printf "ip_addr: $ip_addr \n"
get_objownerhistory_from_ls
get_oid_update

