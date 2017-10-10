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
    duration=$1
    d1=$(date --date="$duration" "+%s")
    d2=$(date "+%s")
    for i in $(seq 0 $((${#lines[@]}-1)))
    do
        count=$((i+1))
        rm -f /tmp/fl.$timestamp
        processes=()
        while read line; do
            lineDate=$(echo $line | awk -F " " '{print $1}')
            if [ ${#lineDate} -lt "4" ]
            then
                lineDate=$(echo $line | awk -F " " '{print $1 " " $2 " " $3}')
            fi
            epochTime=$(date --date="$lineDate" "+%s")
            [[ $epochTime > $d1 && $epochTime < $d2 || $epochTime =~ $d2 ]] && echo $line >> /tmp/fl.$timestamp
        done < /tmp/file.$timestamp.$count
        printf "${LIGHT_GREEN}Node: ${NC}${YELLOW}${nodes[$i]}${NC}\n"
        if [ -f "/tmp/fl.$timestamp" ]
        then
           processes=($(awk -F "/" '{print $5}' "/tmp/fl.$timestamp" | awk -F " " '{print $1}' | sort | uniq))
           for p in ${processes[@]}
           do
               printf "$p  : $(grep $p /tmp/fl.$timestamp | wc -l)\n"
           done
        else
           printf "No restarts.\n"
        fi
        printf "\n"
    done
}

function clearDurationWiseFiles {
    rm -f /tmp/fl.$timestamp
}

function clearFiles {
    rm -f /tmp/file.$timestamp.*
    rm -f /tmp/srestarts.$timestamp
}

function main {
    collectAllServiceRestarts
    extractNodeWiseServiceRestarts
    printf "${LIGHT_PURPLE}Service Restarts in last 7 days:${NC}\n"
    printf "${LIGHT_BLUE}================================${NC}\n\n"
    restartsFor "-7 days"
    clearDurationWiseFiles
    printf "${LIGHT_PURPLE}Service Restarts in last 1 day:${NC}\n"
    printf "${LIGHT_BLUE}===============================${NC}\n\n"
    restartsFor "-1 day"
    clearDurationWiseFiles
    printf "${LIGHT_PURPLE}Service Restarts in last 1 hour:${NC}\n"
    printf "${LIGHT_BLUE}================================${NC}\n\n"
    restartsFor "-1 hour"
    clearDurationWiseFiles
    clearFiles
}

timestamp=$(date +"%Y%m%d-%H%M%S")
main
