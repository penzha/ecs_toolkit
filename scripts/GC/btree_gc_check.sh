#!/bin/sh
vdcs=(10.247.198.59 10.247.198.67)

mkdir -p /tmp/btree_gc_check

current_date=`date +%s`

# get current check btree tasks
for i in "${!vdcs[@]}"; do 
    index=$[$i+1]
    curl -s "http://${vdcs[$i]}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=CHECK_BTREE"  > /tmp/btree_gc_check/check_btree_vdc$index""_$current_date.tmp
    curl -s "http://${vdcs[$i]}:9101/diagnostic/CT/2/DumpAllKeys/CM_TASK?type=CHECK_BTREE"  >> /tmp/btree_gc_check/check_btree_vdc$index""_$current_date.tmp
done

reclaimed_chunks_array=()
reclaimed_size_array=()
new_chunks_array=()
new_size_array=()

if [ -f /tmp/btree_gc_check/last_timestamp.tmp ]; then

    last_date=`cat /tmp/btree_gc_check/last_timestamp.tmp`

    # check the diff
    for i in "${!vdcs[@]}"; do
        index=$[$i+1]
        reclaimed_chunks_array[$i]=`diff /tmp/btree_gc_check/check_btree_vdc$index""_$last_date.tmp /tmp/btree_gc_check/check_btree_vdc$index""_$current_date.tmp | grep -c '<'`
        reclaimed_size_array[$i]=$(echo "scale=2;${reclaimed_chunks_array[$i]}*134217600/1024/1024/1024" | bc -l)
        new_chunks_array[$i]=`diff /tmp/btree_gc_check/check_btree_vdc$index""_$last_date.tmp /tmp/btree_gc_check/check_btree_vdc$index""_$current_date.tmp | grep -c '>'`
        new_size_array[$i]=$(echo "scale=2;${new_chunks_array[$i]}*134217600/1024/1024/1024" | bc -l)
    done

    echo Last:   `date -d @$last_date`
    echo Now:    `date -d @$current_date`

    for i in "${!vdcs[@]}"; do
        index=$[$i+1]
        echo
        echo vdc$index:
        echo Reclaimed Chunks:    ${reclaimed_chunks_array[$i]}
        echo Reclaimed Size:      ${reclaimed_size_array[$i]} GB
        echo New Sealed Chunks:   ${new_chunks_array[$i]} 
        echo New Sealed Size:     ${new_size_array[$i]} GB
    done

else
    echo "No previous dump found. Skip GC status report."
fi

if [ $1"" == "dryrun" ]
then
    echo
    echo "Dryrun mode. Dump of current round will be deleted."
    for i in "${!vdcs[@]}"; do
        index=$[$i+1]
        rm -f /tmp/btree_gc_check/check_btree_vdc$index""_$current_date.tmp
    done
else
    echo $current_date > /tmp/btree_gc_check/last_timestamp.tmp
    echo
    echo "Update last timestamp to" `date -d @$current_date`
fi

