#!/bin/sh
dataip=localhost
chunksfile=/tmp/chunks.txt
#dumpfile=/tmp/ct_info-`date +"%s"`
dumpfile=/tmp/ct_info
if [ $# -gt 0 ]; then
    dataip=$1
    echo "dataip $dataip"
fi
if [ $# -gt 1 ]; then
    chunksfile=$2
fi
while read chunk
do
    location=`curl -s "http://${dataip}:9101/chunkquery/location/?chunkId=${chunk}"  -H Accept:application/xml 2>/dev/null `
    IFS='<' read -a myarray <<< "$location"
    ip=`echo ${myarray[4]}|awk -F'>' '{print $2}'`
    dt=`echo ${myarray[6]}|awk -F'>' '{print $2}'`
    if [ -z != $ip ]
    then
        curl -k "http://${ip}:9101/$dt/CHUNK/?chunkId=${chunk}&showvalue=gpb" >> $dumpfile
    fi
done < $chunksfile