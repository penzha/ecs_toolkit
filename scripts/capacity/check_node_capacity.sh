#!/bin/bash

echo
test $(id -u) -eq 0 || { echo "Use sudo to run this script."; echo; exit; }

node_ip=$(netstat -ln | grep ':9101' | grep LISTEN | awk '{print $4}' | cut -d':' -f1 | head -1)
test -d /opt/storageos/logs && cm_log_dir="/opt/storageos/logs" || cm_log_dir="/opt/emc/caspian/fabric/agent/services/object/main/log"
cm_logfile="${cm_log_dir}/cm.log"
GREP="/usr/bin/grep"
test ! -f $cm_logfile && { echo "'$cm_logfile' does not exist, cannot continue."; echo; exit; }

echo -e "\e[1m==== Capacity Utilization - VDC ====\e[0m"
curl -s ${node_ip}:9101/stats/ssm/varraycapacity | egrep 'TotalCapacity|UsedCapacity' | tr '<>' ' ' | awk '{print $1,"\t - ",$2; A[NR-1] =$2}END{print "Free Space","\t - ",A[0]-A[1]}' | sed 's/Capacity/ Space/; s/$/ GB/'
echo

echo -e "\e[1m====================== Capacity Utilization - Individual Nodes =======================\e[0m"
node_count=$(grep SsSelector.java $cm_logfile | grep 'new SS hierarchy' | tail -1 | awk -F'ss map:' '{print $2}' | tr ',' '\n' | wc -l)
if test "$node_count" -eq 0; then
        cm_logfile="${cm_log_dir}/cm.log.$(date +%Y%m%d-%H)*"
        GREP="/usr/bin/zgrep"
        node_count=$($GREP SsSelector.java $cm_logfile | grep 'new SS hierarchy' | tail -1 | awk -F'ss map:' '{print $2}' | tr ',' '\n' | wc -l)
        if test "$node_count" -eq 0; then
                echo "Unable to get the space usage data, '${cm_log_dir}/cm.log' does not contain the required details. Try after some time."
                exit
        fi
fi
awk 'BEGIN{printf "%-15s %14s    %15s    %13s    %16s\n", "ECS Node IP", "Total Space", "Used Space" ,"Free Space", "Used Percent"; print gensub(/ /, "-", "g", sprintf("%*s",86, ""))}'
$GREP SsSelector-000 $cm_logfile | grep -B1 "Supported allocation types after adjustment are.*level" | grep -o "device .* usage [0-9]*" | tr -d , | tail -${node_count} | awk '{print $2,$5,$8,$10}' | sort -n | awk '{a1+=$3; a2+=($3-$2); a3+=$2; a4+=$4; printf "%-15s %12.2f GB %15.2f GB %13.2f GB %8.0f%\n", $1, $3/1073741824, ($3-$2)/1073741824, $2/1073741824, $4}END{print gensub(/ /, "-", "g", sprintf("%*s",86, "")); printf "%-15s %12.2f GB %15.2f GB %13.2f GB %8.0f%\n","Total VDC usage", a1/1073741824, a2/1073741824, a3/1073741824, a4/node_total}' node_total=$node_count
echo

echo
echo
echo -e "\e[1m=========================== Capacity Utilization - Level 2 ===========================\e[0m"
awk 'BEGIN{printf "%-15s %14s    %15s    %13s    %16s\n", "ECS Node IP", "Total Space", "Used Space" ,"Free Space", "Used Percent"; print gensub(/ /, "-", "g", sprintf("%*s",86, ""))}'
$GREP SsSelector-000 $cm_logfile | grep -B1 "Supported allocation types are.*level 2" | grep -o "device .* usage [0-9]*" | tr -d , | tail -${node_count} | awk '{print $2,$5,$8,$10}' | sort -n | awk '{printf "%-15s %12.2f GB %15.2f GB %13.2f GB %8.0f%\n", $1, $3/1073741824, ($3-$2)/1073741824, $2/1073741824, $4}'


echo
echo
echo -e "\e[1m=========================== Capacity Utilization - Level 1 ===========================\e[0m"
awk 'BEGIN{printf "%-15s %14s    %15s    %13s    %16s\n", "ECS Node IP", "Total Space", "Used Space" ,"Free Space", "Used Percent"; print gensub(/ /, "-", "g", sprintf("%*s",86, ""))}'
$GREP SsSelector-000 $cm_logfile | grep -B1 "Supported allocation types are.*level 1" | grep -o "device .* usage [0-9]*" | tr -d , | tail -${node_count} | awk '{print $2,$5,$8,$10}' | sort -n | awk '{printf "%-15s %12.2f GB %15.2f GB %13.2f GB %8.0f%\n", $1, $3/1073741824, ($3-$2)/1073741824, $2/1073741824, $4}'
echo