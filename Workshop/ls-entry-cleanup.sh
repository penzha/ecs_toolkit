#!/bin/bash

ns="$1"
bucket="$2"
ip="$3"
obj="$4"

outside_log_base=/opt/emc/caspian/fabric/agent/services/object/main/log
inside_log_base=/opt/storageos/logs
tmp_suffix=.LSCLEANUP

CURL='./s3curl.pl'

test -f $CURL || {
  echo "please cd to s3curl directory, or edit the script, see CURL= const"
  exit 1
}

test $# -ge 3 || {
  echo "Usage: $0 <namespace> <bucket> <ip_of_patched_dtquery_in_bucket_owner_zone> <object>"
  echo "object is optional, if not provided we will look one up"
  exit 1
}

tmp=$(mktemp -p $outside_log_base --suffix $tmp_suffix)
tmp2=$(mktemp -p $outside_log_base --suffix $tmp_suffix)
tmp3=$(mktemp -p $outside_log_base --suffix $tmp_suffix)
tmp4=$(mktemp -p $outside_log_base --suffix $tmp_suffix)

inside_tmp="$inside_log_base/`basename $tmp`"
inside_tmp2="$inside_log_base/`basename $tmp2`"
inside_tmp3="$inside_log_base/`basename $tmp3`"
inside_tmp4="$inside_log_base/`basename $tmp4`"

echo "dtquery               $tmp"
echo "tmp s3curl            $tmp2"
echo "tmp formatted s3curl  $tmp3"
echo "full formatted s3curl $tmp4"
echo $inside_tmp
echo $inside_tmp2
echo $inside_tmp3
echo $inside_tmp4

if [[ -z "$obj" ]]; then
        echo "key not provided, list with max-keys=1"
        obj=`./s3curl.pl --debug --id=ecsee -- http://$ip:9020/${bucket}?max-keys=1 | perl -n -e'/<Key>(.*)<\/Key>/ && print $1'`
        echo $obj
fi

if [[ -z "$obj" ]]; then
        echo "cannot find key in bucket!"
        exit 1
fi

bucketid=$( curl "http://$ip:9101/diagnostic/object/showinfo?poolname=${ns}.${bucket}&objectname=${obj}&showvalue=gpb" | grep -m1 -A1 keypool-hash-id | awk '/keypool-hash/{getline;print}' | awk -F \" '{print $2}')
echo $bucketid

curl "http://$ip:9101/diagnostic/LS/0/DumpAllKeys/LIST_ENTRY?type=KEYPOOL&parent=${bucketid}" | grep ${bucketid} | grep child | awk -F'child ' '{print $NF}' | sed 's/ /%20/g; s/\//%2F/g' > $tmp

dos2unix $tmp

echo "sleep 600 seconds"
#sleep 600

token=""
while true; do
        qstring=""
        if [[ ! -z "$token" ]]; then
                echo "use $token"
                qstring="?marker=$token"
        fi

        ./s3curl.pl --debug --id=ecsee -- http://"$ip:9020/${bucket}${qstring}" > $tmp2
        token=`cat $tmp2 | perl -n -e'/<NextMarker>(.*)<\/NextMarker>/ && print $1'`

        # inside container for xmllint
        docker exec object-main xmllint --format $inside_tmp2 --output $inside_tmp3

        cat $tmp3 >> $tmp4

        if [[ -z "$token" ]]; then
                echo "no more results"
                break
        fi
done



grep '<Key>' $tmp4 | sed 's/.*<Key>\(.*\)<\/Key>/\1/' > ${tmp4}-keys

cat $tmp ${tmp4}-keys ${tmp4}-keys | sort | uniq -c | sort -n | awk '{if ($1==1) print $2}' > ${tmp}-ls-to-remove-${bucket}

echo "filename: ${tmp}-ls-to-remove-${bucket}"

num=`cat ${tmp}-ls-to-remove-${bucket} | wc -l`
count=0
batch_count=1000

cat ${tmp}-ls-to-remove-${bucket}| while read line; do
    ./s3curl.pl --head --id=ecsee -- http://"$ip:9020/${bucket}/$line" 2> /dev/null | grep "HTTP/1.1 404 Not Found" > /dev/null
    if [[ $? -ne 0 ]]; then
        echo "valid key found! $line"
    else
        echo "removing $ns.$bucket/$line"
        curl -X DELETE http://$ip:9101/removelsentry/$ns.$bucket/$line &
    fi
    count=$((count+1))
    if [ $((count%batch_count)) -eq 0 ]
    then
        echo "waiting for $batch_count total_count=$count"
        wait
    fi
    if [ $count -eq $num ];then
        break
    fi
done

rm $tmp $tmp2 $tmp3 $tmp4 ${tmp4}-keys # ${tmp}-ls-to-remove-${bucket}