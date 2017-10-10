#!/bin/bash

YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m'

function collectAllServiceRestarts {
    viprexec -c -i 'grep -i restarting /var/log/localmessages' > /tmp/srestarts.$timestamp
    lines=($(grep -n "Output" /tmp/srestarts.$timestamp | awk -F ":" '{print $1}'))
    nodes=($(grep "Output" /tmp/srestarts.$timestamp | awk -F ":" '{print $NF}'))
}

function extractNodeWiseServiceRestarts {
    for i in $(seq 0 $((${#lines[@]}-1)))
    do
        count=$((i+1))
        len=$((${#lines[@]}-1))
        startLine=$((${lines[$i]}+1))
        if [ "$i" != "$len" ]
        then
            endLine=$((${lines[$((i+1))]}-2))
        else
            endLine=$(cat /tmp/srestarts.$timestamp | wc -l)
        fi
        awk "NR>=$startLine && NR<=$endLine {print}" /tmp/srestarts.$timestamp > /tmp/file.$timestamp.$count
    done
}

function restartsFor {
    #duration_1h="-1 hour"
	duration_1h="-10 days"
	#duration_1d="-1 day"
	duration_1d="-20 days"
	#duration_7d="-7 days"
	duration_7d="-30 days"
	
    d1h_start=$(date --date="$duration_1h" "+%s")
    d1h_end=$(date "+%s")
	d1d_start=$(date --date="$duration_1d" "+%s")
	d1d_end=$d1h_start
	d7d_start=$(date --date="$duration_7d" "+%s")
	d7d_end=$d1d_start
	
	printf "d1h_start: $d1h_start \n"
	printf "d1h_end: $d1h_end \n"
	printf "d1d_start: $d1d_start \n"
	printf "d1d_end: $d1d_end \n"
	printf "d7d_start: $d7d_start \n"
	printf "d7d_end: $d7d_end \n"
	
    for i in $(seq 0 $((${#lines[@]}-1)))
    do
        count=$((i+1))
        processes=()
        while read line; do
            lineDate=$(echo $line | awk -F " " '{print $1}')
            if [ ${#lineDate} -lt "4" ]
            then
                lineDate=$(echo $line | awk -F " " '{print $1 " " $2 " " $3}')
            fi
            epochTime=$(date --date="$lineDate" "+%s")
			
            [[ $epochTime > $d1h_start && $epochTime < $d1h_end || $epochTime =~ $d1h_end ]] && echo $line >> /tmp/fl.$count.1H.$timestamp
			[[ $epochTime > $d1d_start && $epochTime < $d1d_end || $epochTime =~ $d1d_end ]] && echo $line >> /tmp/fl.$count.1D.$timestamp
			[[ $epochTime > $d7d_start && $epochTime < $d7d_end || $epochTime =~ $d7d_end ]] && echo $line >> /tmp/fl.$count.7D.$timestamp

        done < /tmp/file.$timestamp.$count
        printf "${LIGHT_GREEN}Node: ${NC}${YELLOW}${nodes[$i]}${NC}\n"
		
		printf "${LIGHT_PURPLE}Service Restarts in last 1 hour:${NC}\n"
        printf "${LIGHT_BLUE}================================${NC}\n\n"   
        if [ -f "/tmp/fl.$count.1H.$timestamp" ]
        then
		   processes=($(awk -F "/" '{print $5}' "/tmp/fl.$count.1H.$timestamp" | awk -F " " '{print $1}' | sort | uniq))
           for p in ${processes[@]}
           do
			   r_count=$(grep $p /tmp/fl.$count.1H.$timestamp | wc -l)
			   printf "$p  : $r_count\n"
			   r_count=0
           done
        else
           printf "No restarts.\n"
        fi
		printf "\n"

        printf "${LIGHT_PURPLE}Service Restarts in last 1 day (except last 1 hour):${NC}\n"
        printf "${LIGHT_BLUE}===============================${NC}\n\n" 
		if [ -f "/tmp/fl.$count.1D.$timestamp" ]
        then
		   processes=($(awk -F "/" '{print $5}' "/tmp/fl.$count.1D.$timestamp" | awk -F " " '{print $1}' | sort | uniq))
           for p in ${processes[@]}
           do
			   r_count=$(grep $p /tmp/fl.$count.1D.$timestamp | wc -l)
			   printf "$p  : $r_count\n"
			   r_count=0
           done
        else
           printf "No restarts.\n"
        fi
        printf "\n"

        printf "${LIGHT_PURPLE}Service Restarts in last 7 day (except last 1 day):${NC}\n"
        printf "${LIGHT_BLUE}===============================${NC}\n\n" 		
		if [ -f "/tmp/fl.$count.7D.$timestamp" ]
        then
		   processes=($(awk -F "/" '{print $5}' "/tmp/fl.$count.7D.$timestamp" | awk -F " " '{print $1}' | sort | uniq))
           for p in ${processes[@]}
           do
			   r_count=$(grep $p /tmp/fl.$count.7D.$timestamp | wc -l)
			   printf "$p  : $r_count\n"
			   r_count=0
           done
        else
           printf "No restarts.\n"
        fi
        printf "\n"		
    done
}

function clearDurationWiseFiles {
    rm -f /tmp/fl.*.$timestamp
}

function clearFiles {
    rm -f /tmp/file.$timestamp.*
    rm -f /tmp/srestarts.$timestamp
}

function main {
    collectAllServiceRestarts
    extractNodeWiseServiceRestarts
    restartsFor
    clearDurationWiseFiles
    clearFiles
}

timestamp=$(date +"%Y%m%d-%H%M%S")
main
