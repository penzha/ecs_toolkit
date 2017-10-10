#!/bin/sh
dataip=localhost
dumpfile=/tmp/ct_info
if [ $# -gt 0 ]; then
    dataip=$1
    echo "dataip $dataip"
fi
if [ $# -gt 1 ]; then
    dumpfile=$2
fi

for chunk in `cat /tmp/chunks.txt`
do 
    echo $chunk
    location=`curl -s "http://${dataip}:9101/chunkquery/location/?chunkId=${chunk}"  -H Accept:application/xml`
    IFS='<' read -a myarray <<< "$location"
    ip=`echo ${myarray[4]}|awk -F'>' '{print $2}'`
    dt=`echo ${myarray[6]}|awk -F'>' '{print $2}'`
    curl -k "http://${ip}:9101/$dt/CHUNK/?chunkId=${chunk}&showvalue=gpb" >> $dumpfile 
done

