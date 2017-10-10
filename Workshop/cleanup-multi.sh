#!/bin/bash

##### Keywords #####
# Shell - multi-threads
# Shell - nohup
####################


ls_dump="$1"
threads="$2"
ns="$3"
bucket="$4"
ip="$5"

timestamp=$(date +"%Y%m%d-%H%M%S")

if [[ -f "/tmp/ls-cleanup-mag-multi.out" ]]; then
        echo "backup existing /tmp/ls-cleanup-mag-multi.out"
        mv /tmp/ls-cleanup-mag-multi.out /tmp/ls-cleanup-mag-multi.out.$timestamp
fi

# split ls dump
ls_counts=$(cat ${ls_dump} | wc -l)
echo $ls_counts

mod=`expr $ls_counts / $threads`
echo "mod: $mod \n"

if [ `expr $ls_counts % $threads` == 0 ]
	then
	    split_num=$threads
    else
	    split_num=`expr $threads + 1`
	fi
echo "split_num: $split_num \n"

for i in $(seq 0 `expr $split_num - 1`)
do
    startLine=`expr $i \* $mod + 1`
	endLine=`expr $startLine + $mod - 1`
	
	if [ $endLine -gt $ls_counts ]
	then
	    endLine=$ls_counts
	fi
	
	awk "NR>=$startLine && NR<=$endLine {print}" ${ls_dump} > /tmp/ls_dump.$((i+1))
done;

# cleanup in parallel
for i in $(seq 1 $split_num)
    do {
        nohup sh -x /usr/share/s3curl/ls-entry-cleanup_keyfile.sh $ns $bucket $ip /tmp/ls_dump.$i >> /tmp/ls-cleanup-mag-multi.out
	   }&
    done

wait
