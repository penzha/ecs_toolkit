host=`hostname`
level="1"
if [ "$1" == "2" ]
then
    level="2"
fi
echo level is $level

checkBtree=1
# REPO is disabled by default
checkRepo=0
# so far JOURNAL MNS cannot be checked because we didn't get sequence according to chunkId
checkJournal=0

if [ $checkBtree -eq 1 ]
then
    echo "check BTREE is enabled"
fi
if [ $checkRepo -eq 1 ]
then
    echo "check REPO is enabled"
fi
if [ $checkJournal -eq 1 ]
then
    echo "check JOURNAL is enabled"
fi

echo "Step 1: get CHUNK_SEQUENCE of all CT tables"
echo "generate script /tmp/ronnie.chunk.sequence.sh to get CHUNK_SEQUENCE"
curl -s http://$host:9101/diagnostic/CT/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo \"list "$3"\"\n""curl -L -s \""$3"CHUNK_SEQUENCE?showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.chunk.sequence.sh
echo "run script /tmp/ronnie.chunk.sequence.sh and save result in /tmp/ronnie.chunk.sequence.tmp"
sh /tmp/ronnie.chunk.sequence.sh > /tmp/ronnie.chunk.sequence.tmp
echo successfully query CT DT number: `grep http /tmp/ronnie.chunk.sequence.tmp | wc -l`
echo fetched CHUNK_SEQUENCE from CT:
grep schema /tmp/ronnie.chunk.sequence.tmp | sort | uniq -c
echo "parse the result to /tmp/ronnie.chunk.sequence.2.tmp"
grep -e list -e schemaType -e value /tmp/ronnie.chunk.sequence.tmp | tr -d $'\r' | awk -F' |/' '{if($1=="list"){ct=$5}else if($1=="schemaType"){key=$0}else{print ct " " key " " $0}}' | sed 's/rgId  dataType/rgId None dataType/g' > /tmp/ronnie.chunk.sequence.2.tmp
echo "fetched CHUNK_SEQUENCE:"
cat /tmp/ronnie.chunk.sequence.2.tmp | awk '{print $5 " " $7}' | sort | uniq -c

if [ $checkBtree -eq 1 ]
then
    echo ""
    echo "Step 2: get BTREE GC_REF_COLLECTION for each CT-DT pair"
    echo "generate script /tmp/ronnie.btree.mns.sh to get GC_REF_COLLECTION"
    curl -s http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo \""$3"\"\n""curl -L -s \""$3"GC_REF_COLLECTION?type=BTREE&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.btree.mns.sh
    echo "run script /tmp/ronnie.btree.mns.sh and save result in /tmp/ronnie.btree.mns.tmp"
    sh /tmp/ronnie.btree.mns.sh > /tmp/ronnie.btree.mns.tmp
    echo successfully query PR DT number: `grep http /tmp/ronnie.btree.mns.tmp | wc -l`
    echo fetched parsed BTREE MNS from PR:
    grep schema /tmp/ronnie.btree.mns.tmp | awk '{print $4 " " $10}' | sort | uniq -c
fi

if [ $checkRepo -eq 1 ]
then
    echo ""
    echo "Step 2: get REPO GC_REF_COLLECTION for each CT-DT pair"
    echo "generate script /tmp/ronnie.repo.mns.sh to get GC_REF_COLLECTION"
    curl -s http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo \""$3"\"\n""curl -L -s \""$3"GC_REF_COLLECTION?type=REPO&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.repo.mns.sh
    echo "run script /tmp/ronnie.repo.mns.sh and save result in /tmp/ronnie.repo.mns.tmp"
    sh /tmp/ronnie.repo.mns.sh > /tmp/ronnie.repo.mns.tmp
    echo successfully query PR DT number: `grep http /tmp/ronnie.repo.mns.tmp | wc -l`
    echo fetched parsed REPO MNS from PR:
    grep schema /tmp/ronnie.repo.mns.tmp | awk '{print $4 " " $10}' | sort | uniq -c
fi

if [ $checkJournal -eq 1 ]
then
    echo ""
    echo "Step 2: get JOURNAL GC_REF_COLLECTION for each CT-DT pair"
    echo "generate script /tmp/ronnie.journal.mns.sh to get GC_REF_COLLECTION"
    curl -s http://$host:9101/diagnostic/PR/$level/ | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "echo \""$3"\"\n""curl -L -s \""$3"GC_REF_COLLECTION?type=JOURNAL&showvalue=gpb&useStyle=raw\""}' > /tmp/ronnie.journal.mns.sh
    echo "run script /tmp/ronnie.journal.mns.sh and save result in /tmp/ronnie.journal.mns.tmp"
    sh /tmp/ronnie.journal.mns.sh > /tmp/ronnie.journal.mns.tmp
    echo successfully query PR DT number: `grep http /tmp/ronnie.journal.mns.tmp | wc -l`
    echo fetched parsed JOURNAL MNS from PR:
    grep schema /tmp/ronnie.journal.mns.tmp | awk '{print $4 " " $10}' | sort | uniq -c
fi

if [ $checkBtree -eq 1 ]
then
    echo ""
    echo "Step 3: combine all (/tmp/ronnie.chunk.sequence.2.tmp /tmp/ronnie.btree.mns.tmp)"
    echo "group the result for BTREE according to CT table in /tmp/ronnie.btree.mns.perCt.tmp"
    for rg in `grep schemaType /tmp/ronnie.btree.mns.tmp | awk '{print $10}' | sort | uniq` ; do for i in {0..127} ; do ct="CT_"$i"_128_"$level ; echo "checking " $ct " " $rg ; grep -A1 "GC_REF_COLLECTION.*"$ct".*rgId $rg" /tmp/ronnie.btree.mns.tmp | grep minNotSealedValue | awk 'BEGIN{minor=2^53; major=0} {if($2<minor) {minor=$2} else if ($2>major) {major=$2}} END{print "minor MNS "minor" major MNS "major}' ; grep $ct.*rgId.$rg.*BTREE /tmp/ronnie.chunk.sequence.2.tmp | awk '{print "current sequence: " $NF}' ; done ; done > /tmp/ronnie.btree.mns.perCt.tmp
    echo "parse the result to /tmp/ronnie.btree.mns.perCt.2.tmp"
    cat /tmp/ronnie.btree.mns.perCt.tmp | tr -d $'\r' | awk '{if($1=="checking"){ct=$0}else if($1=="minor"){mns=$0}else{print ct " " mns " " $0}}' > /tmp/ronnie.btree.mns.perCt.2.tmp
    echo "generate the final result /tmp/ronnie.btree.mns.perCt.result.tmp"
    cat /tmp/ronnie.btree.mns.perCt.2.tmp | awk '{print "ratio " ($12-$6)/($6+1) " " $0}' | sort -g -r -k 2 > /tmp/ronnie.btree.mns.perCt.result.tmp
fi

if [ $checkRepo -eq 1 ]
then
    echo ""
    echo "Step 3: combine all (/tmp/ronnie.chunk.sequence.2.tmp /tmp/ronnie.repo.mns.tmp)"
    echo "group the result for REPO according to CT table in /tmp/ronnie.repo.mns.perCt.tmp"
    for rg in `grep schemaType /tmp/ronnie.repo.mns.tmp | awk '{print $10}' | sort | uniq` ; do for i in {0..127} ; do ct="CT_"$i"_128_"$level ; echo "checking " $ct " " $rg ; grep -A1 "GC_REF_COLLECTION.*"$ct".*rgId $rg" /tmp/ronnie.repo.mns.tmp | grep minNotSealedValue | awk 'BEGIN{minor=2^53; major=0} {if($2<minor) {minor=$2} else if ($2>major) {major=$2}} END{print "minor MNS "minor" major MNS "major}' ; grep $ct.*rgId.$rg.*REPO /tmp/ronnie.chunk.sequence.2.tmp | awk '{print "current sequence: " $NF}' ; done ; done > /tmp/ronnie.repo.mns.perCt.tmp
    echo "parse the result to /tmp/ronnie.repo.mns.perCt.2.tmp"
    cat /tmp/ronnie.repo.mns.perCt.tmp | tr -d $'\r' | awk '{if($1=="checking"){ct=$0}else if($1=="minor"){mns=$0}else{print ct " " mns " " $0}}' > /tmp/ronnie.repo.mns.perCt.2.tmp
    echo "generate the final result /tmp/ronnie.repo.mns.perCt.result.tmp"
    cat /tmp/ronnie.repo.mns.perCt.2.tmp | awk '{print "ratio " ($12-$6)/($6+1) " " $0}' | sort -g -r -k 2 > /tmp/ronnie.repo.mns.perCt.result.tmp
fi

if [ $checkJournal -eq 1 ]
then
    echo ""
    echo "Step 3: query sequenceNumber of all chunks in /tmp/ronnie.journal.mns.tmp, which will be time consuming"
    echo "generate script /tmp/ronnie.journal.mns.fetch.sh to get sequence number according to chunkId"
    grep -A1 schema /tmp/ronnie.journal.mns.tmp | tr -d '"' | awk -v host=$host 'BEGIN{RS="--"}{print "echo check " $6 " " $8 " " $10 " " $12 ; print "curl -L -s \"http://"host":9101/"$6"/CHUNK?useStyle=raw&showvalue=gpb&chunkId="$14"\" | grep sequenceNumber"}' > /tmp/ronnie.journal.mns.fetch.sh
    echo "run /tmp/ronnie.journal.mns.fetch.sh and save result in /tmp/ronnie.journal.mns.fetch.tmp"
    echo "total requests to send" `grep -c curl /tmp/ronnie.journal.mns.fetch.sh`
    sh /tmp/ronnie.journal.mns.fetch.sh > /tmp/ronnie.journal.mns.fetch.tmp
    echo "total requests sent" `grep -c sequence /tmp/ronnie.journal.mns.fetch.tmp`
    echo "types of DT:"
    grep check /tmp/ronnie.journal.mns.fetch.tmp | awk -F'_' '{print $(NF-3)}' | sort | uniq -c
    echo "number of CT&DT pair"
    grep check /tmp/ronnie.journal.mns.fetch.tmp | awk -F'_' '{print "CT_"$4 " " $(NF-3)}' | sort | uniq -c | wc -l
    echo "number of incomplete CT&DT pairs"
    grep check /tmp/ronnie.journal.mns.fetch.tmp | awk -F'_' '{print "CT_"$4 " " $(NF-3)}' | sort | uniq -c | grep -v "128 CT_" | wc -l
    echo "sample incomplete CT&DT pairs"
    grep check /tmp/ronnie.journal.mns.fetch.tmp | awk -F'_' '{print "CT_"$4 " " $(NF-3)}' | sort | uniq -c | grep -v "128 CT_" | sort -n -k 1 | head


    echo ""
    echo "Step 4: combine all (/tmp/ronnie.chunk.sequence.2.tmp /tmp/ronnie.journal.mns.fetch.tmp)"
    echo "group the result for JOURNAL according to CT table in /tmp/ronnie.journal.mns.perCt.tmp"
    for rg in `grep schemaType /tmp/ronnie.journal.mns.tmp | awk '{print $10}' | sort | uniq` ; do for i in {0..127} ; do ct="CT_"$i"_128_"$level ; echo "checking " $ct " " $rg ; grep -A1 "check .*"$ct".*$rg" /tmp/ronnie.journal.mns.fetch.tmp | grep sequenceNumber | awk 'BEGIN{minor=2^53; major=0} {if($2<minor) {minor=$2} else if ($2>major) {major=$2}} END{print "minor MNS "minor" major MNS "major}' ; grep $ct.*rgId.$rg.*JOURNAL /tmp/ronnie.chunk.sequence.2.tmp | awk '{print "current sequence: " $NF}' ; done ; done > /tmp/ronnie.journal.mns.perCt.tmp
    echo "parse the result to /tmp/ronnie.journal.mns.perCt.2.tmp"
    cat /tmp/ronnie.journal.mns.perCt.tmp | tr -d $'\r' | awk '{if($1=="checking"){ct=$0}else if($1=="minor"){mns=$0}else{print ct " " mns " " $0}}' > /tmp/ronnie.journal.mns.perCt.2.tmp
    echo "generate the final result /tmp/ronnie.journal.mns.perCt.result.tmp"
    cat /tmp/ronnie.journal.mns.perCt.2.tmp | awk '{print "ratio " ($12-$6)/($6+1) " " $0}' | sort -g -r -k 2 > /tmp/ronnie.journal.mns.perCt.result.tmp
fi

echo ""
echo ""
echo "FINAL RESULT"
echo ""
echo "meaning:"
echo "Global MNS progress is calculated per RG per CT"
echo "current sequence is CHUNK_SEQUENCE stored in CT table for this rg"
echo "minor MNS is the minimal min-not-seal referenced by other DTs"
echo "major MNS is the maximal min-not-seal referenced by other DTs"
echo "If the difference between minor MNS and major MNS is huge, some DTs may have problem parsing MNS for this CT table."
echo "If current sequence is far greater than minor MNS and major MNS, MNS may have problem for this CT table."
echo "ratio = (current sequence - minor MNS)/(minor MNS + 1). the higher ratio is, the higher possibility that global MNS progress for this CT and RG is blocked."
echo "Note that this may not be 100% accurate, because it didn't parse chunkId to get sequence."
echo ""
if [ $checkBtree -eq 1 ]
then
    echo "MNS is calculated for BTREE:"
    cat /tmp/ronnie.btree.mns.perCt.result.tmp | awk '{print $5}' | sort | uniq -c
fi
if [ $checkRepo -eq 1 ]
then
    echo "MNS is calculated for REPO:"
    cat /tmp/ronnie.repo.mns.perCt.result.tmp | awk '{print $5}' | sort | uniq -c
fi
if [ $checkJournal -eq 1 ]
then
    echo "MNS is calculated for JOURNAL:"
    cat /tmp/ronnie.journal.mns.perCt.result.tmp | awk '{print $5}' | sort | uniq -c
fi

echo ""
if [ $checkBtree -eq 1 ]
then
    echo "MNS for BTREE is calculated for each CT & RG in /tmp/ronnie.btree.mns.perCt.result.tmp"
fi
if [ $checkRepo -eq 1 ]
then
    echo "MNS for REPO is calculated for each CT & RG in /tmp/ronnie.repo.mns.perCt.result.tmp"
fi
if [ $checkJournal -eq 1 ]
then
    echo "MNS for JOURNAL is calculated for each CT & RG in /tmp/ronnie.journal.mns.perCt.result.tmp"
fi
