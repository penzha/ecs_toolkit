host=`hostname`
level="1"
if [ "$1" == "2" ]
then
    level="2"
fi

echo call for leve $level PR tables

echo "Step 1: get and parse dump marker"
echo "generate script /tmp/ronnie.dump.marker.sh to get dump marker"
curl -s -L http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo dump marker \""$3"\"\n""curl -s -L \""$3"DIRECTORYTABLE_RECORD/?type=BPLUSTREE_DUMP_MARKER&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.dump.marker.sh
echo "run script /tmp/ronnie.dump.marker.sh and save result in /tmp/ronnie.dump.marker.tmp"
sh /tmp/ronnie.dump.marker.sh > /tmp/ronnie.dump.marker.tmp
echo successfully query PR DT number: `grep http /tmp/ronnie.dump.marker.tmp | wc -l`
echo fetched DTs from PR:
grep schema /tmp/ronnie.dump.marker.tmp | awk -F' |_' '{print $11 " " $NF}' | sort | uniq -c | sort
echo "parse the result to /tmp/ronnie.dump.marker.2.tmp"
cat /tmp/ronnie.dump.marker.tmp | tr -d $'\r' | grep -e schema -e progress | awk '{if($1=="schemaType"){dtId=$6;zone=$8}else{print dtId " " zone " subkey dumpMarker " $2}}' > /tmp/ronnie.dump.marker.2.tmp
echo "verify /tmp/ronnie.dump.marker.2.tmp that dump markers for all DTs are fetched"
grep dumpMarker /tmp/ronnie.dump.marker.2.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo ""
echo "Step 2: get and parse parser marker"
echo "generate script /tmp/ronnie.parser.marker.sh to get parser marker"
curl -s -L http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo parser marker \""$3"\"\n""curl -s -L \""$3"DIRECTORYTABLE_RECORD/?type=BPLUSTREE_PARSER_MARKER&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.parser.marker.sh
echo "run script /tmp/ronnie.parser.marker.sh and save result in /tmp/ronnie.parser.marker.tmp"
sh /tmp/ronnie.parser.marker.sh > /tmp/ronnie.parser.marker.tmp
echo successfully query PR DT number: `grep http /tmp/ronnie.parser.marker.tmp | wc -l`
echo fetched DTs from PR:
grep schema /tmp/ronnie.parser.marker.tmp | awk -F' |_' '{print $11 " " $NF}' | sort | uniq -c | sort
echo "generate script /tmp/ronnie.parser.tree.sh to get bplustree of parser marker in /tmp/ronnie.parser.marker.tmp"
grep -e parser -e schema -e bTreeInfoMajor /tmp/ronnie.parser.marker.tmp | tr -d $'\r' | awk '{if($1=="parser"){pr=$3}else if($1=="schemaType"){dtId=$6;zone=$8}else{printf "curl -s -L \"%sDIRECTORYTABLE_RECORD?useStyle=raw&showvalue=gpb&type=BPLUSTREE_INFO&dtId=%s&zone=%s&major=%016x\"\n", pr, dtId, zone, $2-1 }}' > /tmp/ronnie.parser.tree.sh
echo "the script only covers the following DTs:"
cat /tmp/ronnie.parser.tree.sh | awk -F' |_|&' '{print $16 " " $20}' | sort | uniq -c | sort
echo "run script /tmp/ronnie.parser.tree.sh to get bplustree of parser marker and save result in /tmp/ronnie.parser.tree.tmp"
sh /tmp/ronnie.parser.tree.sh > /tmp/ronnie.parser.tree.tmp
echo "successfully get number of btree roots:"
grep schema /tmp/ronnie.parser.tree.tmp | awk -F' |_' '{print $10 " " $15}' | sort | uniq -c | sort
echo "parse the result to /tmp/ronnie.parser.tree.2.tmp"
grep -e schema -e timestamp /tmp/ronnie.parser.tree.tmp | grep -v "    timestamp: " | tr -d $'\r''\"' | awk '{if($1=="schemaType"){dtId=$6;zone=$8;major=$10}else{print dtId " " zone " subkey parserMajor " major " parserMarker " $2}}' > /tmp/ronnie.parser.tree.2.tmp
echo "verify /tmp/ronnie.parser.tree.2.tmp that all bplustree of parser markers are fetched"
grep parserMarker /tmp/ronnie.parser.tree.2.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo ""
echo "Step 3: get and parse consistent marker"
echo "generate script /tmp/ronnie.consistent.marker.sh to get consistent marker"
curl -s -L http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo consistent marker \""$3"\"\n""curl -s -L \""$3"DIRECTORYTABLE_RECORD/?type=GEOREPLAYER_CONSISTENCY_CHECKER_MARKER&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.consistent.marker.sh
echo "run script /tmp/ronnie.consistent.marker.sh to get consistent markers and save result in /tmp/ronnie.consistent.marker.tmp"
sh /tmp/ronnie.consistent.marker.sh > /tmp/ronnie.consistent.marker.tmp
echo successfully query PR DT number: `grep http /tmp/ronnie.consistent.marker.tmp | wc -l`
echo fetched DTs from PR:
grep schema /tmp/ronnie.consistent.marker.tmp | awk -F' |_' '{print $12 " " $NF}' | sort | uniq -c | sort
echo "generate script /tmp/ronnie.consistent.tree.sh to get bplustree of consistent marker in /tmp/ronnie.consistent.marker.tmp"
cat /tmp/ronnie.consistent.marker.tmp | tr -d $'\r''\"' | awk '{if($1=="consistent"){pr=$3}if($1=="schemaType"){key=$0}if($1=="subKey:"){print pr " " key " " $2}}' | sed 's/\\020/ /g' | sed 's/\\022//g' | awk '{print $1 " " $7 " " $9 " " $11 " " $12}' > /tmp/ronnie.consistent.marker.2.tmp
cat /tmp/ronnie.consistent.marker.2.tmp | awk '{print "echo consistent marker " $2 " " $3 " " $4 ; print "curl -s -L \"" $1 "DIRECTORYTABLE_RECORD?useStyle=raw&showvalue=gpb&type=BPLUSTREE_INFO&dtId=" $2 "&zone=" $3 "&major=" $4 "\""}' > /tmp/ronnie.consistent.tree.sh
echo "run script /tmp/ronnie.consistent.tree.sh to get all consistent trees and save result in /tmp/ronnie.consistent.tree.tmp"
sh /tmp/ronnie.consistent.tree.sh > /tmp/ronnie.consistent.tree.tmp
echo "parse all consistent trees in /tmp/ronnie.consistent.tree.2.tmp"
grep -e schema -e timestamp /tmp/ronnie.consistent.tree.tmp | grep -v "    timestamp: " | tr -d $'\r''\"' | awk '{if($1=="schemaType"){dtId=$6;zone=$8;major=$10}else{print dtId " " zone " subkey cc_major " major " ccMarker " $2}}' > /tmp/ronnie.consistent.tree.2.tmp
echo "verify /tmp/ronnie.consistent.tree.2.tmp that all consistent trees are fetched"
grep ccMarker /tmp/ronnie.consistent.tree.2.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo ""
echo "Step 4: combine all three parsers (/tmp/ronnie.dump.marker.2.tmp /tmp/ronnie.parser.tree.2.tmp /tmp/ronnie.consistent.tree.2.tmp)"
echo "combine all result files into /tmp/ronnie.btree.marker.combine.tmp"
cat /tmp/ronnie.dump.marker.2.tmp /tmp/ronnie.parser.tree.2.tmp /tmp/ronnie.consistent.tree.2.tmp | sort | awk -F'subkey' 'BEGIN{key="none";subkey=""}{if(key==$1){subkey=subkey $2}else{print key " " subkey ; key=$1 ; subkey=$2}}END{print key " " subkey}' | grep -v none > /tmp/ronnie.btree.marker.combine.tmp
echo "DTs in combined file:"
cat /tmp/ronnie.btree.marker.combine.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo "DTs without dumpMarker in combined file:"
grep -v dumpMarker /tmp/ronnie.btree.marker.combine.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo "DTs without parserMarker in combined file:"
grep -v parserMarker /tmp/ronnie.btree.marker.combine.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo "Remote DTs with ccMarker in combined file:"
grep ccMarker /tmp/ronnie.btree.marker.combine.tmp | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo "check local DT and save result in /tmp/ronnie.parser.delay.local.tmp"
cat /tmp/ronnie.btree.marker.combine.tmp | grep dumpMarker | grep parserMarker | grep -v ccMarker | awk -v now=`date +%s%N | cut -b1-13` '{print "parser-now " int((now-$8)/3600000) " hours parser-dump " int(($4-$8)/3600000) " hours " $0}' | sort -n -r -k 2 > /tmp/ronnie.parser.delay.local.tmp
echo "check remote DT and save result in /tmp/ronnie.parser.delay.remote.tmp"
cat /tmp/ronnie.btree.marker.combine.tmp | grep dumpMarker | grep parserMarker | grep ccMarker | awk -v now=`date +%s%N | cut -b1-13` '{print "cc-now " int((now-$6)/3600000) " hours parser-cc " int(($6-$12)/3600000) " hours cc-dump " int(($8-$6)/3600000) " hours " $0}' | sort -n -r -k 2 > /tmp/ronnie.parser.delay.remote.tmp
echo ""
echo ""
echo "FINAL RESULT"
echo ""
echo "meaning:"
echo "parser-now means the difference between OccupancyScanner and current time. If this value is huge, we may have min-not-seal problem and more BR references are not updated in BR table."
echo "cc-now means the time between consistent tree and current time. If this value is huge, cc marker may be blocked or lagged."
echo "parser-cc means the difference between OccupancyScanner and consistent tree. If this value is small, then OccupancyScanner is blocked by cc marker. "
echo ""
echo "Fetched local DTs"
cat /tmp/ronnie.btree.marker.combine.tmp | grep dumpMarker | grep parserMarker | grep -v ccMarker | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo "Fetched remote DTs"
cat /tmp/ronnie.btree.marker.combine.tmp | grep dumpMarker | grep parserMarker | grep ccMarker | awk -F' |_' '{print $3 " " $7}' | sort | uniq -c | sort
echo ""
echo "Result file for local DTs: /tmp/ronnie.parser.delay.local.tmp"

echo "Result file for remote DTs: /tmp/ronnie.parser.delay.remote.tmp"
