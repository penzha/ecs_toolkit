host=`hostname`
level="1"
if [ "$1" == "2" ]
then
    level="2"
fi

echo "Step 1: get and parse JOURNAL_REGION_GC_MARKER"
echo "generate script /tmp/ronnie.jr.gc.marker.sh to get JOURNAL_REGION_GC_MARKER"
curl -s -L http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo jr gc marker \""$3"\"\n""curl -s -L \""$3"DIRECTORYTABLE_RECORD/?type=JOURNAL_REGION_GC_MARKER&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.jr.gc.marker.sh
echo "run script /tmp/ronnie.jr.gc.marker.sh and save result in /tmp/ronnie.jr.gc.marker.tmp"
sh /tmp/ronnie.jr.gc.marker.sh > /tmp/ronnie.jr.gc.marker.tmp
echo successfully query PR DT number: `grep http /tmp/ronnie.jr.gc.marker.tmp | wc -l`
echo fetched DTs from PR:
grep schema /tmp/ronnie.jr.gc.marker.tmp | awk -F' |_' '{print $12 " " $NF}' | sort | uniq -c | sort

echo "Step 2: generate script /tmp/ronnie.first.jr.sh to get first journal region of each DT"
grep -e http -e schema /tmp/ronnie.jr.gc.marker.tmp | tr -d $'\r' | awk '{if($1=="jr"){pr=$4}else if($1=="schemaType"){printf "curl -s -L \"%sDIRECTORYTABLE_RECORD?maxkeys=1&useStyle=raw&showvalue=gpb&type=JOURNAL_REGION&dtId=%s&zone=%s\"\n", pr, $6, $8}}' > /tmp/ronnie.first.jr.sh
#grep -e http -e schema /tmp/ronnie.jr.gc.marker.tmp | tr -d $'\r' | awk '{if($1=="jr"){pr=$4}else if($1=="schemaType"){printf "curl -s -L \"%sDIRECTORYTABLE_RECORD?maxkeys=1024&useStyle=raw&showvalue=gpb&type=JOURNAL_REGION&dtId=%s&zone=%s\" | head -7 \n", pr, $6, $8}}' > /tmp/ronnie.first.jr.sh
echo "run script /tmp/ronnie.first.jr.sh and save result in /tmp/ronnie.first.jr.tmp"
sh /tmp/ronnie.first.jr.sh > /tmp/ronnie.first.jr.tmp
echo fetched DTs from PR:
grep schema /tmp/ronnie.first.jr.tmp | awk -F' |_' '{print $10 " " $(NF-4)}' | sort | uniq -c | sort

echo "if some keys are missing due to vnest list problem, please manually fetch the missing ones following sample in this script"
#grep schema.*CT_ /tmp/ronnie.first.jr.tmp | awk -F'_' '{print $6}' | sort -n | awk 'BEGIN{v=0}{while(v<$1){print v; v=v+1};v=v+1}END{while(v<=127){print v; v=v+1}}'
#grep CT_38 /tmp/ronnie.first.jr.sh
#curl -s -L "http://172.29.20.14:9101/urn:storageos:OwnershipInfo:53e05a33-5977-42fa-a4e0-f4a4afb31fbf__PR_74_128_2:/DIRECTORYTABLE_RECORD?maxkeys=100&useStyle=raw&showvalue=gpb&type=JOURNAL_REGION&dtId=urn:storageos:OwnershipInfo:53e05a33-5977-42fa-a4e0-f4a4afb31fbf__CT_38_128_1:&zone=urn:storageos:VirtualDataCenterData:b9182493-7780-475f-9a70-6c24f2657d68" | head -7 | tee -a /tmp/ronnie.first.jr.tmp

echo ""
echo ""
echo "FINAL RESULT"
echo ""

echo "number of fetched timestamps " `grep timestamp /tmp/ronnie.first.jr.tmp | wc -l`

echo "results are stored in /tmp/ronnie.first.jr.result.tmp"
grep -e schema -e timestamp /tmp/ronnie.first.jr.tmp | awk 'BEGIN{RS="schemaType"}{print $12 " " $13 " "  $5 " " $7 " " $8 " " $9 }' | grep timestamp | sort -n -k 2 | awk -v now=`date +%s%N | cut -b1-13` '{print "firstJr-now " int((now-$2)/3600000/24) " days " $0}' > /tmp/ronnie.first.jr.result.tmp
head /tmp/ronnie.first.jr.result.tmp