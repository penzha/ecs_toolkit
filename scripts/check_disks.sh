#!/bin/bash   
################################################################
#
# NAME
#	check_disks.sh
#
# SYNOPSIS
#	check_disks.sh  [-s] [-l] [-r]
#
# VERSION
VERSION="1.0.0.7"
#
# DESCRIPTION
#       Check ECS disks, and report issues recommendations
#
################################################################
VERBOSE=0
V_IP="`sudo ifconfig public 2> /dev/null| grep Mask | awk '{print $2}' | sed -e 's/addr://'`"

if [ "x${V_IP}" = "x" ] ; then
  V_IP="`sudo ifconfig -a | grep inet | awk '{print $2}' | grep -v "::" | grep -v 127.0.0.1 | tail -1`"
fi

if [ "x${V_IP}" = "x" ] ; then
  V_IP="`hostname -i | sed -e 's/ //g'`"
fi

while [ "$1" = "-s"  -o "$1" = "-r" -o  "$1" = "-l" -o "$1" = "--help" ]; do
        if [ "$1" = "-s" ]; then
                # shift
                SILENT_MODE="-s"
        elif [ "$1" = "-l" ]; then
                # shift
                LIST_MODE="-l"
        elif [ "$1" = "-r" ]; then
                # shift
                LIST_MODE="-r"
        elif [ "$1" = "--help" ]; then
                # shift
                VERBOSE=1
                echo "usage: disks_check.sh [ -s ]"
                echo " -s  silent "
                exit 
        fi 
        shift
done


function checkRepair {
REPAIR_TASK=`curl -s "http://${V_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=REPAIR" | grep -c schemaType`
VDC="`curl -s "http://${V_IP}:9101/stats/ssm/varraycapacity" | awk -F'<|>' '{print $3}' | grep storageos`"

if [ ! ${REPAIR_TASK} = 0 ] ; then

   echo "WARNING $REPAIR_TASK Repair tasks ongoing"

if [ "${LIST_MODE}" = "-r" ] ; then
for i in $( curl -s "http://${V_IP}:9101/diagnostic/CT/1/DumpAllKeys/CM_TASK?type=REPAIR" | grep schemaType | sed -e 's/.$//' | awk '{print $8}') 
do
    echo ""
    echo "CHUNK ######### $i ###########"
    curl -s "http://${V_IP}:9101/diagnostic/1/ShowChunkInfo?cos=${VDC}&chunkid=${i}"  | egrep "segments|ssId|partitionId|recoveryStatus|status:" | awk '{printf("%s %s ",$1,$2)}' | sed -e 's/segments/\nsegments/g'
done
fi 
fi
echo ""

}



checkRepair

echo -n "${V_IP} "
echo -n "$(nslookup ${V_IP} | grep name) "

function mk_tmp_file {
    local _RESULTVAR=$1
    local _FILENAME=$2
    local _TMPFILE="/tmp/${_FILENAME}.$$"

    eval "${_RESULTVAR}='${_TMPFILE}'"
}

function cleanup {
    rm -f /tmp/.*.$$
}

function echo_and_run {	
    mk_tmp_file _CURLCOMMAND ".curl_command"
    echo "$@" > ${_CURLCOMMAND} 
    chmod +x ${_CURLCOMMAND}
    ${_CURLCOMMAND} 2> /dev/null
}


mk_tmp_file _PARTITIONS ".partitions"
mk_tmp_file _PART ".part"
mk_tmp_file _FCLIDISKS ".fclidisks"
mk_tmp_file _HALVOLS ".halvols"
mk_tmp_file _HALDISK ".haldisk"
mk_tmp_file _OWNERSHIP ".ownership"

/opt/emc/hal/bin/cs_hal list vols > ${_HALVOLS}
/opt/emc/hal/bin/cs_hal list disks > ${_HALDISK}

_IPS="$(ifconfig  | grep "inet " | grep -v 127.0.0.1  | sed -e 's/:/ /g' | awk '{ printf ("-e %s ",$3)}')"

for i in $(curl -# -s http://${V_IP}:9101/diagnostic/SS/2/DumpAllKeys/SSTABLE_KEY?type=PARTITION| sed -e 's/http:/\nhttp:/g' |  grep http | sort | uniq)
     do
     CMD=`echo "curl -s --progress-bar $i"| sed s/PARTITION/PARTITION'\&'showvalue=gpb\'/g | sed  s/http/\'http/g  | awk ' {printf "%s\n",$0}' | sed -e 's/.$//' `
    echo_and_run $CMD | sed -e 's/schemaType/\nschemaType/g' | grep -A1 SSTABLE >  ${_PART}
     echo ${CMD} | sed -e 's/:/ /g' -e 's/\/\///g'  | awk '{printf("\nLevel2 Owner: %s DT: %s\n",$5,$9)}' >> ${_OWNERSHIP}  
     cat ${_PART} 2> /dev//null | sed -e 's/PARTITION_REMOVED/PARTITION_REMOVED_2/g'  >> ${_PARTITIONS}
     cat ${_PART} 2> /dev/null | sed -e 's/schemaType SSTABLE_KEY type PARTITION device/\n/g'  | sed -e 's/.$//' | awk '{printf("%s %s %s %s ",$1,$2,$3,$4)}' | sed -e 's/PARTITION_U/PARTITION_UP\n/g' -e 's/PARTITION_REMOVE/PARTITION_REMOVED_2\n/g' -e 's/PARTITION_PERMANENT_DOW/PARTITION_PERMANENT_DOWN\n/g' -e 's/PARTITION_TRANSIENT_DOW/PARTITION_TRANSIENT_DOWN\n/g' -e 's/partition//g' -e 's/-        //g'  >> ${_OWNERSHIP}
     #echo "" >> ${_OWNERSHIP}
    done

for i in $(curl -# -s http://${V_IP}:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_KEY?type=PARTITION| sed -e 's/http:/\nhttp:/g' |  grep http | sort  |uniq)
     do
     CMD=`echo "curl -s --progress-bar $i"| sed s/PARTITION/PARTITION'\&'showvalue=gpb\'/g | sed  s/http/\'http/g  | awk ' {printf "%s\n",$0}' | sed -e 's/.$//' `
     echo_and_run $CMD | sed -e 's/schemaType/\nschemaType/g' | grep -A1 SSTABLE >  ${_PART}
     echo ${CMD} | sed -e 's/:/ /g' -e 's/\/\///g'  | awk '{printf("\nLevel1 Owner: %s DT: %s \n",$5,$9)}' >> ${_OWNERSHIP}  
     cat ${_PART} 2> /dev//null | sed -e 's/PARTITION_REMOVED/PARTITION_REMOVED_1/g'  >> ${_PARTITIONS}
     cat ${_PART} 2> /dev/null | sed -e 's/schemaType SSTABLE_KEY type PARTITION device/\n/g'  | sed -e 's/.$//' | awk '{printf("%s %s %s %s ",$1,$2,$3,$4)}' | sed -e 's/PARTITION_U/PARTITION_UP\n/g' -e 's/PARTITION_REMOVE/PARTITION_REMOVED_1\n/g' -e 's/PARTITION_PERMANENT_DOW/PARTITION_PERMANENT_DOWN\n/g' -e 's/PARTITION_TRANSIENT_DOW/PARTITION_TRANSIENT_DOWN\n/g' -e 's/partition//g' -e 's/-        //g'  >> ${_OWNERSHIP}
     #echo "" >> ${_OWNERSHIP}
    done
/opt/emc/caspian/fabric/cli/bin/fcli agent disk.disks  > ${_FCLIDISKS}

_count=0

if [ "${LIST_MODE}" = "-l" ] ; then 
cat ${_OWNERSHIP}
echo ------------------Local Disks--------------------------
for i in $(cat ${_HALVOLS} | grep xfs |  awk '{print $3 }' ) ; do 
mk_tmp_file _TMPUUID .uuid
 echo -n "$i "
 _count=$(expr $_count + 1)
 grep -c $i ${_FCLIDISKS} | awk '{ printf(" %d ",$1/2) }'
docker exec object-main ls -alt /dae 2>/dev/null | grep -c $i | awk '{printf( " %d ",$1)}'
grep -e health  -e uuid -e status -e mount_path -e serial_number ${_FCLIDISKS} | sed -e 's/\"//g' -e 's/://g' -e 's/,//g' > ${_TMPUUID}
$(grep -B2 -A4 " ${i}" ${_TMPUUID} | awk '{printf("export _%s=%s\n",$1,$2)}')
_PARTITION="$(grep -A1  ${_uuid} ${_PARTITIONS} 2> /dev/null | grep state | tail -1  | awk '{print $2}')"

if [ "m${_PARTITION}" = "m" ] ; then 
   _PARTITION="0"
fi
echo ${_PARTITION}
done
else
for i in $(cat ${_FCLIDISKS} | grep \"uuid\" | sed -e 's/\"//g' -e 's/,//g' | awk '{print $2 }' ) ; do 
mk_tmp_file _TMPUUID .uuid
grep -e health  -e uuid -e status -e mount_path -e serial_number ${_FCLIDISKS} | sed -e 's/\"//g' -e 's/://g' -e 's/,//g' > ${_TMPUUID}
$(grep -B2 -A4 " ${i}" ${_TMPUUID} | awk '{printf("export _%s=%s\n",$1,$2)}')
_HAL=$(grep $i ${_HALVOLS} | awk '{print $7}')
_DISK=$(grep $i ${_HALVOLS} | awk '{print $2}')
_DISK1=$(grep $i ${_HALVOLS}  | awk '{print $1}')
_count=$(expr $_count + 1)

if [ "m${_serial_number}" = "m" ] ; then 
   _serial_number="unknownunknownunknownunknow"
fi

   _serial="$(echo ${_serial_number}| awk '{print substr($0,length-15,16)}')"

if [ "m${_DISK1}" = "m" ] ; then 
   _DISK1="$(grep ${_serial}  ${_HALDISK}  | awk '{print $1}')"
fi

if [ "m${_DISK1}" = "m" ] ; then 
   _DISK1="/dev/null"
fi

if [ "m${_DISK}" = "m" ] ; then 
   _DISK="$(grep ${_serial} ${_HALDISK}  | awk '{print $2}')"
fi

if [ "m${_DISK}" = "m" ] ; then 
   _DISK="/dev/null"
fi
#echo $i ${_serial_number} ${_serial}
if [ "m${_HAL}" = "m" ] ; then
_HAL="$(grep ${_DISK} ${_HALVOLS} | awk '{print $7}')"
fi

if [ "m${_HAL}" = "m" ] ; then 
   _HAL="Unknown"
fi

_EXIST=$(docker exec object-main ls -alt /dae 2>/dev/null | grep ${_uuid})
_EXIST1=$(docker exec object-main ls -alt /dae 2>/dev/null| grep ${_serial_number})

if [ "m${_EXIST}" = "m" ] && [ "m${_EXIST1}" = "m" ]  ; then 
 _EXIST="n"
else
 _EXIST="y"
fi

_DF=$( docker exec object-main df 2> /dev/null | grep ${_uuid})

if [ "m${_DF}" = "m" ] ; then 
 _DF="n"
else
 _DF="y"
fi
_PARTITION="$(grep -A1  ${_uuid} ${_PARTITIONS} 2> /dev/null | grep state |  awk '{printf("%s ", $2)}')"
#echo "XX${_PARTITION}iXX"
if [ "m${_PARTITION}" = "m" ] ; then 
   _PARTITION="unknown"
fi

if [ ${VERBOSE} -ge 1 ] ; then 
  echo -e "\e[1;31m Disk (${_DISK}) ${_uuid} => HAL_status= ${_HAL} Health_status= ${_health} Operational_status= ${_operational_status} Mount_status= ${_mount_status} Partition_status= ${_PARTITION}\e[0m" 
fi

if [ "${_PARTITION}" = "PARTITION_UP PARTITION_UP " ] && [ "${_health}" = "GOOD" ] && [ "${_HAL}" = "GOOD" ] && [ "${_mount_status}" = "MOUNTED" ] && [ "${_operational_status}" = "OPERATIVE"  ] ; then 
  #echo -n "${_count} "
  echo -n "$(echo ${_DISK}| sed -e 's/\/dev\///g') "
elif [ "${_PARTITION}" = "PARTITION_UP PARTITION_REMOVED_1 " ] && [ "${_health}" = "GOOD" ] && [ "${_HAL}" = "GOOD" ] && [ "${_mount_status}" = "MOUNTED" ] && [ "${_operational_status}" = "OPERATIVE"  ] ; then
if [ "${SILENT_MODE}" = "-s" ] ; then
    echo -en "\e[1;35m$(echo ${_DISK} | sed -e 's/\/dev\//(L1)/g') \e[0m"
else 
    echo -en "\e[1;35m$(echo ${_DISK} | sed -e 's/\/dev\//(L1)/g') \e[0m"
 fi
elif [ "${_PARTITION}" = "PARTITION_REMOVED_2 PARTITION_UP " ] && [ "${_health}" = "GOOD" ] && [ "${_HAL}" = "GOOD" ] && [ "${_mount_status}" = "MOUNTED" ] && [ "${_operational_status}" = "OPERATIVE"  ] ; then
if [ "${SILENT_MODE}" = "-s" ] ; then
    echo -en "\e[1;35m$(echo ${_DISK} | sed -e 's/\/dev\//(L2)/g') \e[0m"
else 
    echo -en "\e[1;35m$(echo ${_DISK} | sed -e 's/\/dev\//(L2)/g') \e[0m"
 fi
elif [ "${_PARTITION}" = "PARTITION_REMOVED_2 PARTITION_REMOVED_1 " ] && [ "${_health}" = "GOOD" ] && [ "${_HAL}" = "GOOD" ] && [ "${_mount_status}" = "MOUNTED" ] && [ "${_operational_status}" = "OPERATIVE"  ] ; then
if [ "${SILENT_MODE}" = "-s" ] ; then
    echo -en "\e[1;35m$(echo ${_DISK} | sed -e 's/\/dev\//(L2)(L1)/g') \e[0m"
else 
    echo -en "\e[1;35m$(echo ${_DISK} | sed -e 's/\/dev\//(L2)(L1)/g') \e[0m"
 fi
elif [  "${_health}" = "GOOD" ] && [ "${_HAL}" = "GOOD" ] && [ "${_mount_status}" = "MOUNTED" ] && [ "${_operational_status}" = "OPERATIVE"  ] ; then
echo -en "\e[1;34m${_count} \e[0m" 
elif [ "${_operational_status}" = "REMOVED"  ] ; then 
  echo -n "R "
elif [ "${_PARTITION}" = "PARTITION_PERMANENT_DOWN" ] && [ "${_health}" = "GOOD" ] && [ "${_HAL}" = "GOOD" ] && [ "${_mount_status}" = "UNMOUNTED" ] && [ "${_operational_status}" = "INOPERATIVE"  ] ; then 
 #echo -en "\e[1;31m C \e[0m" 
 echo -en "\e[1;31m C (${_DISK}) \e[0m" 
  if [ "${SILENT_MODE}" = "-s" ] ; then 
   echo
   echo "--------- Mount point exists= ${_EXIST}"
   echo "--------- Mount point Mounted= ${_DF}"
   echo "Recommneded commands which could be used for remediation"
  if [ "${_DF}" = "y" ] ; then
   echo " docker exec object-main umount /dae/uuid-${_uuid}" 
  fi 
  if [ "${_EXIST}" = "y" ] ; then
   echo " docker exec object-main rmdir /dae/uuid-${_uuid}"
  fi 
  #echo "/opt/emc/caspian/fabric/cli/bin/fcli agent disk.add --disk ${_uuid}"
 fi
else
 echo -en "\e[1;31m C (${_DISK}) \e[0m" 
 if [ "${SILENT_MODE}" = "-s" ] ; then 
    echo
    echo -e "\e[1;31m Disk (${_DISK}) ${_uuid} => HAL_status= ${_HAL} Health_status= ${_health} Operational_status= ${_operational_status} Mount_status= ${_mount_status} Partition_status= ${_PARTITION}\e[0m"  
 fi
  if [ "${SILENT_MODE}" = "-s" ] ; then 

    echo "--------- Mount point exists= ${_EXIST}"
    echo "--------- Mount point Mounted= ${_DF}"
    echo "Recommneded commands which could be used for remediation"
    if [ "${_DF}" = "y" ] ; then
     echo " docker exec object-main umount /dae/uuid-${_uuid}" 
    fi 
    if [ "${_EXIST}" = "y" ] ; then
     echo " docker exec object-main rmdir /dae/uuid-${_uuid}"
    fi 
    if [  ! "${_operational_status}" = "REMOVED" ] ; then
      echo "/opt/emc/caspian/fabric/cli/bin/fcli disks remove --diskid ${_uuid} --force "
    else
      echo "if this disk was intentionally removed, in future versions you will be able to PURGE these entries. "
    fi
    echo "/opt/emc/caspian/fabric/cli/bin/fcli agent disk.add --disk ${_uuid}"
    if [  ! "${_DISK}" = "/dev/null" ] ; then
     echo  dd if=${_DISK} of=/dev/null count=1
     echo blkid  ${_DISK}1 
     echo cs_hal info  ${_DISK} 
     echo fdisk -l  ${_DISK} 
     echo /opt/emc/caspian/fabric/cli/bin/fcli agent disk.purge 
     echo /opt/emc/caspian/fabric/cli/bin/fcli agent disk.disks --statuses ALL
     echo wipedisks.sh ${_DISK}1 wipedisks.sh ${_DISK}
     echo parted ${_DISK} rm 1
     echo partprobe
     echo wipefs -a ${_DISK}1
     echo parted  ${_DISK} print
    fi
    if [  ! "${_DISK1}" = "/dev/null" ] ; then
      echo cs_hal info  ${_DISK1} 
    fi
  fi
fi

done
echo ""
echo "Done Checking ${_count} Disks"
fi
cleanup
