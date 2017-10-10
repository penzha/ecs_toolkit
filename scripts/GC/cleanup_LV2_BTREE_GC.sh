#!/bin/bash

if [ -z "$ip" ]; then
    echo "Setting dtquery ip to localhost";
    ip=$(netstat -an | grep :9101 | grep LISTEN | grep -oP "(?:[0-9]{1,3}\.){3}[0-9]{1,3}");
fi

if [ -z "$cmfuser" ]; then
    echo "Setting cmfuser to emcservice";
    cmfuser="emcservice";
fi

if [ -z "$cmfpassword" ]; then
    echo "Setting cmfpassword to ChangeMe";
    cmfpassword="ChangeMe";
fi

mkdir -p /tmp/clearlv2
rm -f /tmp/clearlv2/*

dockerId=`sudo docker ps | grep "emcvipr/object" | awk '{print $1}'`
# Verify if com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled has been updated and set to false
echo "######################################################"
echo "####         Checking LV2 BTREE GC disabled       ####"
echo "######################################################"
sudo docker exec -it $dockerId /opt/storageos/tools/cf_client --list --name "com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled" --user ${cmfuser} --password ${cmfpassword} > /tmp/clearlv2/reclaimer.config
if [ ! -f  /tmp/clearlv2/reclaimer.config ]; then
    echo "# Unable to find /tmp/clearlv2/reclaimer.config, please check if able to create file under /tmp/clearlv2"
    exit 1
fi
grep '"configured_value":' /tmp/clearlv2/reclaimer.config
if [ $? -gt 0 ]; then
    # There are no configured value, check default value
    grep '"default_value": "false"' /tmp/clearlv2/reclaimer.config
    if [ $? -gt 0 ]; then
        echo "# CMF key com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled not exist or default value not to be false, can not cleanup with LV2 btree GC enabled."
        echo "# Check if CMF cache has been cleaned up and vnest has been restarted after applied patch"
        exit 1
    else
        echo "# CMF key com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled has been updated as expected"
    fi
else
    grep '"configured_value": "false"' /tmp/clearlv2/reclaimer.config
    if [ $? -gt 0 ]; then
        echo "# CMF key com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled is not set to false, no need to do cleanup with LV2 btree GC enabled"
        exit 1
    else
        echo "# CMF key com.emc.ecs.chunk.gc.btree.reclaimer.level2.enabled is set to false as expected"
    fi
fi

echo ""

echo "###################################################################"
echo "####         Checking LV2 BTREE GC verification disabled       ####"
echo "###################################################################"
# Verify if com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled has been updated
sudo docker exec -it $dockerId /opt/storageos/tools/cf_client --list --name "com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled" --user ${cmfuser} --password ${cmfpassword} > /tmp/clearlv2/varification.config
if [ ! -f  /tmp/clearlv2/varification.config ]; then
    echo "# Unable to find /tmp/clearlv2/varification.config, please check if able to create file under /tmp/clearlv2"
    exit 1
fi
grep '"configured_value":' /tmp/clearlv2/varification.config
if [ $? -gt 0 ]; then
    # There is no configured value, check default value
    grep '"default_value": "false"' /tmp/clearlv2/varification.config
    if [ $? -gt 0 ]; then
        echo "# CMF key com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled not exist or default value not to be false, can not cleanup with LV2 btree GC verification enabled."
        echo "# Check if CMF cache has been cleaned up and vnest has been restarted after applied patch"
        exit 1
    else
        echo "# CMF key com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled has been updated as expected"
    fi
else
    # There is configured value for this, check configured value
    grep '"configured_value": "false"' /tmp/clearlv2/varification.config
    if [ $? -gt 0 ]; then
        echo "# CMF key com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled is not set to false, no need to do cleanup with LV2 btree GC verification enabled"
        exit 1
    else
        echo "# CMF key com.emc.ecs.chunk.gc.btree.scanner.level2.verification.enabled is set to false as expected"
    fi
fi

echo ""

# Clean up LV2 BTREE GC verification checkpoints
echo "############################################################"
echo "####   Cleanup LV2 BTREE GC verification checkpoints    ####"
echo "############################################################"
curl -s -f -X DELETE "http://${ip}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/CT/1"
curl -s -f -X DELETE "http://${ip}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/PR/1"
curl -s -f -X DELETE "http://${ip}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/SS/1"
curl -s -f -X DELETE "http://${ip}:9101/triggerGcVerification/deleteAllCheckpoint/BTREE/BR/1"
# Verify delete result
curl -f -s -L "http://${ip}:9101/diagnostic/PR/2/DumpAllKeys/CHUNK_REFERENCE_SCAN_PROGRESS?type=BTREE&dt=" > /tmp/clearlv2/checkpoints.log
if [ $? -gt 0 ]; then
    echo "# Unable to validate LV2 BTREE GC verification checkpoint cleanup, will continue since this step is optional"
    echo "# Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to verify if cleanup is done"
fi
if [ ! -f  /tmp/clearlv2/checkpoints.log ]; then
    echo "# Unable to find /tmp/clearlv2/checkpoints.log, please check if able to create file under /tmp/clearlv2"
    exit 1
fi
btreeVerifyCheckpointNum=`grep schemaType /tmp/clearlv2/checkpoints.log | wc -l`
if [ ${btreeVerifyCheckpointNum} -gt 0 ]; then
	echo "# Cleanup LV2 BTREE GC verification checkpoints failed, will continue since this step is optional."
	echo "# Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to do cleanup manually if necessary"
else
	echo "# Cleanup LV2 BTREE GC verification checkpoints successfully"
fi

echo ""

# Clean up LV2 BTREE GC task status
echo "#####################################################"
echo "####   Cleanup LV2 BTREE GC verification tasks   ####"
echo "#####################################################"
curl -s -L "http://${ip}:9101/diagnostic/CT/2" | xmllint --format - | grep "<id>" | awk -F '<|>' '{print $3}' > /tmp/clearlv2/ct.list
for ctId in `cat /tmp/clearlv2/ct.list`
do
	echo "Cleanup LV2 BTREE GC task for table ${ctId}"
	curl -f -s -X DELETE -L "http://${ip}:9101/triggerGcVerification/clearTasksOfCT/BTREE/${ctId}/false"
	if [ $? -gt 0 ]; then
	    echo "Unable to delete LV2 BTREE GC task for CT ${ctId}"
	fi
done
curl -f -s -L "http://${ip}:9101/diagnostic/CT/2/DumpAllKeys/CHUNK_GC_SCAN_STATUS_TASK" > /tmp/clearlv2/chunk_gc_scan_task.log
if [ $? -gt 0 ]; then
    echo "# Unable to validate LV2 BTREE GC verification checkpoint cleanup, will continue since this step is optional"
    echo " Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to verify if cleanup is done"
fi
if [ ! -f  /tmp/clearlv2/chunk_gc_scan_task.log ]; then
    echo "# Unable to find /tmp/clearlv2/chunk_gc_scan_task.log, please check if able to create file under /tmp/clearlv2"
    exit 1
fi
ctTaskNum=`grep schema /tmp/clearlv2/chunk_gc_scan_task.log | wc -l`
if [ ${ctTaskNum} -gt 0 ]; then
	echo "# Cleanup LV2 CHUNK_GC_SCAN_STATUS_TASK failed, will continue since this step is optional"
	echo "# Please follow the instruction on https://asdwiki.isus.emc.com:8443/display/ECS/3.0+HF1+General+Patch+Steps+for+BTREE+GC+tickets to do cleanup manually if necessary"
else
	echo "# Cleanup LV2 CHUNK_GC_SCAN_STATUS_TASK successfully"
fi

echo ""
echo "##################################"
echo "####         Done             ####"
echo "##################################"
