#!/bin/bash

# xmllint 2>/dev/null | grep -q Usage  && echo "yes"

ip=`sudo ifconfig public | grep "inet addr" | awk -F : '{print $2}' | awk '{print $1}'`
server="http://$ip:9101"
diagnostic="http://$ip:9101/diagnostic"
paxos="http://$ip:9101/paxos"

case ${1} in
dt)
    curl "$server/stats/dt/DTInitStat/$2" | xmllint --format -
    ;;

owner)
    curl "$diagnostic/DumpOwnershipInfo" 2> /dev/null
    ;;

balance)
    tmp=$(mktemp)
    curl "$diagnostic/DumpOwnershipInfo" 2> /dev/null > $tmp && for type in `awk -F _ '{print $3}' $tmp | sort | uniq`; do echo $type; grep "_$type" $tmp | awk '{print $5}' | sort | uniq -c; done
    rm $tmp
    ;;

stats)
    curl $diagnostic/stats/dtstats/$2 2> /dev/null
    ;;

object)
    show=""
    if [[ "$4" == "gpb" ]]; then
        show="\&showvalue=GPB"
    fi
    curl $diagnostic/object/showlatestinfo?poolname=$2\&objectname=$3\&showrepo=true$show 2> /dev/null | sed -n '1,/<pre>/!{/<\/pre>/,/<pre>/!p;}'
    ;;

chunk)
    chunkId="$2"
    dtId=`curl $server/chunkquery/location?chunkId=$chunkId -H Accept:application/xml 2>1 | grep -oPm1 "(?<=<DTId>)[^<]+"`
    [[ ! -z "$dtId" ]] && curl "$server/$dtId/CHUNK/?chunkId=$chunkId&showvalue=gpb" -L 2> /dev/null | sed 's/^<.*<pre>//' || echo "could not find chunk $chunkId"
    ;;

ns)
    curl $paxos/namespaces 2> /dev/null | sed -n '1,/SUMMARY/!{/done with listing/,/SUMMARY/!p;}'
    ;;

buckets)
    curl $paxos/buckets 2> /dev/null
    ;;

freeblocks)
    numBlocks=`curl $diagnostic/SS/2/DumpAllKeys/SSTABLE_KEY?type=FREE_BLOCK | grep schemaType | wc -l`
    echo "Num free blocks from SS L2 - $numBlocks"
    ;;

enablenest)
    enabled=true
    if [ ! -z "$2" ]; then
        $enabled=$2
    fi
    echo "setting vnest diagnostics to $enabled"
    curl $server/nest/diagnosticEnabler?enabled=$enabled -X PUT
    ;;

*)
    echo "unknown action"
    ;;

esac
