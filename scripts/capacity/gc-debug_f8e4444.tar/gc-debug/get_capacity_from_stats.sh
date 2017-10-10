chunk_size=134217600
ECS_NODE_IP=$1
ECS_DATA_NODE_IP=$1
foldername=$2

if [ -z $foldername ]; then
    foldername="/tmp/stats_data"
fi

cm_stats_filename=$foldername/cm_stats.txt
cache_stats_filename=$foldername/cahe_stats.txt
ec_stats_filename=$foldername/ec_stats.txt


curl -L -k -s http://${ECS_NODE_IP}:9101/diagnostic/DumpOwnershipInfo > /dev/null


########## STATS #####################
echo -e "\n\nStart getting STATS values at `date`"

#varray=`curl -k -s https://${ECS_NODE_IP}:4443/stat/json/aggregate?path=cm/Chunk%20Statistics/ | grep CoS | sed 's/^.* : "//' | sed 's/",//'` || true
#curl -k -s https://${ECS_NODE_IP}:4443/stat/json/aggregate?path=cm/Chunk%20Statistics/${varray} > $cm_stats_filename
curl -L -k -s https://${ECS_NODE_IP}:4443/stat/json/aggregate?path=cm/Chunk%20Statistics > $cm_stats_filename
echo `cat $cm_stats_filename | grep chunks_repo.TOTAL -A 5 | grep timestamp`
chunks_repo_sealed_stats=`cat $cm_stats_filename | grep chunks_repo.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_repo_active.TOTAL -A 5 | grep timestamp`
chunks_repo_unsealed_stats=`cat $cm_stats_filename | grep chunks_repo_active.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_repo_s0.TOTAL -A 5 | grep timestamp`
chunks_repo_s0_stats=`cat $cm_stats_filename | grep chunks_repo_s0.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
chunks_repo_stats=`expr $chunks_repo_sealed_stats + $chunks_repo_unsealed_stats - $chunks_repo_s0_stats` || true
data_repo_stats=`expr $chunks_repo_stats \* $chunk_size` || true

echo `cat $cm_stats_filename | grep chunks_level_0_btree.TOTAL -A 5 | grep timestamp`
chunks_l0_btree_sealed_stats=`cat $cm_stats_filename | grep chunks_level_0_btree.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_0_btree_active.TOTAL -A 5 | grep timestamp`
chunks_l0_btree_unsealed_stats=`cat $cm_stats_filename | grep chunks_level_0_btree_active.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_1_btree.TOTAL -A 5 | grep timestamp`
chunks_l1_btree_sealed_stats=`cat $cm_stats_filename | grep chunks_level_1_btree.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_1_btree_active.TOTAL -A 5 | grep timestamp`
chunks_l1_btree_unsealed_stats=`cat $cm_stats_filename | grep chunks_level_1_btree_active.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_0_btree_s0.TOTAL -A 5 | grep timestamp`
chunks_l0_btree_s0_stats=`cat $cm_stats_filename | grep chunks_level_0_btree_s0.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_1_btree_s0.TOTAL -A 5 | grep timestamp`
chunks_l1_btree_s0_stats=`cat $cm_stats_filename | grep chunks_level_1_btree_s0.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_0_journal.TOTAL -A 5 | grep timestamp`
chunks_l0_journal_sealed_stats=`cat $cm_stats_filename | grep chunks_level_0_journal.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_0_journal_active.TOTAL -A 5 | grep timestamp`
chunks_l0_journal_unsealed_stats=`cat $cm_stats_filename | grep chunks_level_0_journal_active.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_1_journal.TOTAL -A 5 | grep timestamp`
chunks_l1_journal_sealed_stats=`cat $cm_stats_filename | grep chunks_level_1_journal.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_1_journal_active.TOTAL -A 5 | grep timestamp`
chunks_l1_journal_unsealed_stats=`cat $cm_stats_filename | grep chunks_level_1_journal_active.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_0_journal_s0.TOTAL -A 5 | grep timestamp`
chunks_l0_journal_s0_stats=`cat $cm_stats_filename | grep chunks_level_0_journal_s0.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_level_1_journal_s0.TOTAL -A 5 | grep timestamp`
chunks_l1_journal_s0_stats=`cat $cm_stats_filename | grep chunks_level_1_journal_s0.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
chunks_btree_stats=`expr $chunks_l0_btree_sealed_stats + $chunks_l0_btree_unsealed_stats + $chunks_l1_btree_sealed_stats + $chunks_l1_btree_unsealed_stats - $chunks_l0_btree_s0_stats - $chunks_l1_btree_s0_stats` || true
chunks_journal_stats=`expr $chunks_l0_journal_sealed_stats + $chunks_l0_journal_unsealed_stats + $chunks_l1_journal_sealed_stats + $chunks_l1_journal_unsealed_stats - $chunks_l0_journal_s0_stats - $chunks_l1_journal_s0_stats` || true
chunks_meta_stats=`expr $chunks_btree_stats + $chunks_journal_stats` || true
data_meta_stats=`expr $chunks_meta_stats \* $chunk_size` || true

echo `cat $cm_stats_filename | grep chunks_copy.TOTAL -A 5 | grep timestamp`
chunks_copy_sealed_stats=`cat $cm_stats_filename | grep chunks_copy.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_copy_active.TOTAL -A 5 | grep timestamp`
chunks_copy_unsealed_stats=`cat $cm_stats_filename | grep chunks_copy_active.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_copy_s0.TOTAL -A 5 | grep timestamp`
chunks_copy_s0_stats=`cat $cm_stats_filename | grep chunks_copy_s0.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_xor.TOTAL -A 5 | grep timestamp`
chunks_xor_stats=`cat $cm_stats_filename | grep chunks_xor.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
chunks_geo_copy_xor_stats=`expr $chunks_copy_sealed_stats + $chunks_copy_unsealed_stats - $chunks_copy_s0_stats + $chunks_xor_stats` || true
data_geo_copy_xor_stats=`expr $chunks_geo_copy_xor_stats \* $chunk_size` || true


curl -L -k -s https://${ECS_NODE_IP}:4443/stat/json/aggregate?path=cm/Geo%20Replication%20Statistics/Geo%20Chunk%20Cache > $cache_stats_filename
echo `cat $cache_stats_filename | grep "Number of Chunks.TOTAL" -A 5 | grep timestamp`
chunks_cache_stats=`cat $cache_stats_filename | grep "Number of Chunks.TOTAL" -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cache_stats_filename | grep "Capacity of Cache.TOTAL" -A 5 | grep timestamp`
data_cache_stats=`cat $cache_stats_filename | grep "Capacity of Cache.TOTAL" -A 5 | grep counter | sed 's/^.* : //'` || true


#curl -k -s https://${ECS_NODE_IP}:4443/stat/json/aggregate?path=cm/EC%20Statistics/${varray} > $ec_stats_filename
curl -L -k -s https://${ECS_NODE_IP}:4443/stat/json/aggregate?path=cm/EC%20Statistics > $ec_stats_filename
echo `cat $ec_stats_filename | grep chunks_ec_encoded_alive.TOTAL -A 5 | grep timestamp`
chunks_ec_encoded_alive_stats=`cat $ec_stats_filename | grep chunks_ec_encoded_alive.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_typeI_ec_pending.TOTAL -A 5 | grep timestamp`
chunks_typeI_ECpending_stats=`cat $cm_stats_filename | grep chunks_typeI_ec_pending.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_typeII_ec_pending.TOTAL -A 5 | grep timestamp`
chunks_typeII_ECpending_stats=`cat $cm_stats_filename | grep chunks_typeII_ec_pending.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
echo `cat $cm_stats_filename | grep chunks_undertransform_ec_pending.TOTAL -A 5 | grep timestamp`
chunks_undertransform_ec_pending_stats=`cat $cm_stats_filename | grep chunks_undertransform_ec_pending.TOTAL -A 5 | grep counter | sed 's/^.* : //'` || true
chunks_ecencoded_typeItypeIIincluded_stats=`expr ${chunks_ec_encoded_alive_stats} + ${chunks_typeI_ECpending_stats} + ${chunks_typeII_ECpending_stats} + ${chunks_undertransform_ec_pending_stats}` || true
ecdataoverhead_stats=`expr ${chunks_ecencoded_typeItypeIIincluded_stats} \* $chunk_size / 3` || true
non_ec_chunkcount_stats=`expr $chunks_repo_stats - $chunks_typeII_ECpending_stats - $chunks_undertransform_ec_pending_stats + $chunks_meta_stats + $chunks_geo_copy_xor_stats - $chunks_ec_encoded_alive_stats` || true
non_ec_dataoverhead_stats=`expr $non_ec_chunkcount_stats \* $chunk_size \* 2` || true
localprotection_stats=`expr $ecdataoverhead_stats + $non_ec_dataoverhead_stats` || true

echo -e "\n\nCompleted getting STATS values at `date`"

echo "chunks_repo_sealed_stats=${chunks_repo_sealed_stats}"
echo "chunks_repo_unsealed_stats=${chunks_repo_unsealed_stats}"
echo "chunks_repo_s0_stats=${chunks_repo_s0_stats}"
echo "chunks_l0_btree_sealed_stats=${chunks_l0_btree_sealed_stats}"
echo "chunks_l0_btree_unsealed_stats=${chunks_l0_btree_unsealed_stats}"
echo "chunks_l1_btree_sealed_stats=${chunks_l1_btree_sealed_stats}"
echo "chunks_l1_btree_unsealed_stats=${chunks_l1_btree_unsealed_stats}"
echo "chunks_l0_btree_s0_stats=${chunks_l0_btree_s0_stats}"
echo "chunks_l1_btree_s0_stats=${chunks_l1_btree_s0_stats}"
echo "chunks_l0_journal_sealed_stats=${chunks_l0_journal_sealed_stats}"
echo "chunks_l0_journal_unsealed_stats=${chunks_l0_journal_unsealed_stats}"
echo "chunks_l1_journal_sealed_stats=${chunks_l1_journal_sealed_stats}"
echo "chunks_l1_journal_unsealed_stats=${chunks_l1_journal_unsealed_stats}"
echo "chunks_l0_journal_s0_stats=${chunks_l0_journal_s0_stats}"
echo "chunks_l1_journal_s0_stats=${chunks_l1_journal_s0_stats}"
echo "chunks_copy_sealed_stats=${chunks_copy_sealed_stats}"
echo "chunks_copy_unsealed_stats=${chunks_copy_unsealed_stats}"
echo "chunks_copy_s0_stats=${chunks_copy_s0_stats}"
echo "chunks_xor_stats=${chunks_xor_stats}"
echo "chunks_cache_stats=${chunks_cache_stats}"
echo "data_cache_stats=${data_cache_stats}"
echo "chunks_ec_encoded_alive_stats=${chunks_ec_encoded_alive_stats}"
echo "chunks_typeI_ECpending_stats=${chunks_typeI_ECpending_stats}"
echo "chunks_typeII_ECpending_stats=${chunks_typeII_ECpending_stats}"

echo "data_repo_stats=${data_repo_stats}"
echo "data_meta_stats=${data_meta_stats}"
echo "data_geo_copy_xor_stats=${data_geo_copy_xor_stats}"
echo "data_cache_stats=${data_cache_stats}"
echo "localprotection_stats=${localprotection_stats}"
