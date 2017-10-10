#!/bin/bash

ns="$1"
bucket="$2"
ip="$3"
to_be_removed_list="$4"

CURL='./s3curl.pl'

test -f $CURL || {
  echo "please cd to s3curl directory, or edit the script, see CURL= const"
  exit 1
}

test $# -ge 3 || {
  echo "Usage: $0 <namespace> <bucket> <ip_of_patched_dtquery_in_bucket_owner_zone> <key_file_to_removed_list>"
  exit 1
}

num=`cat ${to_be_removed_list} | wc -l`
echo "filename: ${to_be_removed_list}, number of keys to be removed: ${num}"
count=0

batch_count=1000

cat ${to_be_removed_list}| while read line; do
    ./s3curl.pl --head --id=ecsee -- http://"$ip:9020/${bucket}/$line" 2> /dev/null | grep "HTTP/1.1 404 Not Found" > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "valid key found! $line"
    else
        echo "removing $ns.$bucket/$line"
        curl -X DELETE http://$ip:9101/removelsentry/$ns.$bucket/$line &
    fi
    count=$((count+1))
    if [ $((count%batch_count)) -eq 0 ];then
        echo "waiting for $batch_count total_count=$count"
        wait
    fi
        if [ $count -eq $num ];then
            break
        fi
done
