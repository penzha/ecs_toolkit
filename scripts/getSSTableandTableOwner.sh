#!/bin/bash
#For Customer with Network Separation , use data_ip instead of public IP.You can get data_ip using below command.
#/opt/emc/caspian/fabric/cli/bin/fcli agent node.network |grep data_ip
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
LIGHT_BLUE='\033[1;34m'
LIGHT_CYAN='\033[1;36m'
LIGHT_PURPLE='\033[1;35m'
LIGHT_GREEN='\033[1;32m'
RED='\033[0;31m'
LIGHT_RED='\033[1;31m'
NC='\033[0m'

function getOwnershipInfo {
hostIP=$1
curl "http://$hostIP:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_KEY?type=PARTITION" -s > /tmp/ss_l1.txt
nodeList1=($(grep -B1 schemaType /tmp/ss_l1.txt | grep "schemaType SSTABLE_KEY" | awk -F " " '{print $6}' | uniq))
urlList1=($(grep -B1 "schemaType" /tmp/ss_l1.txt | grep -v "schemaType SSTABLE_KEY" | grep -v "\-\-"))
ownerIPList1=($(grep -B1 schemaType /tmp/ss_l1.txt | grep -v "schemaType SSTABLE_KEY" | awk -F "/" '{print $3}' | awk -F ":" '{print $1}'))
SSTableList1=($(grep -B1 schemaType /tmp/ss_l1.txt | grep -v "schemaType SSTABLE_KEY" | awk -F "/" '{print $4}'))
curl "http://$hostIP:9101/diagnostic/SS/2/DumpAllKeys/SSTABLE_KEY?type=PARTITION" -s > /tmp/ss_l2.txt
nodeList2=($(grep -B1 schemaType /tmp/ss_l2.txt | grep "schemaType SSTABLE_KEY" | awk -F " " '{print $6}' | uniq))
urlList2=($(grep -B1 "schemaType" /tmp/ss_l2.txt | grep -v "schemaType SSTABLE_KEY" | grep -v "\-\-"))
ownerIPList2=($(grep -B1 schemaType /tmp/ss_l2.txt | grep -v "schemaType SSTABLE_KEY" | awk -F "/" '{print $3}' | awk -F ":" '{print $1}'))
SSTableList2=($(grep -B1 schemaType /tmp/ss_l2.txt | grep -v "schemaType SSTABLE_KEY" | awk -F "/" '{print $4}'))
outCounter=0
for ip1 in ${nodeList1[@]}
do
   inCounter=0
   for ip2 in ${nodeList2[@]}
   do
      if [ "$ip1" != "$ip2" ]
      then
         inCounter=$((inCounter+1))
      else
         printf "${LIGHT_GREEN}For node:${NC} ${YELLOW}$ip1${NC}\n"
         printf "${LIGHT_GREEN}*************************${NC}\n\n"
         printf "${LIGHT_BLUE}Level 1:${NC}\n"
         printf "${LIGHT_RED}SSTable:${NC} ${SSTableList1[$outCounter]}\n"
         printf "${LIGHT_RED}Owner:${NC} ${ownerIPList1[$outCounter]}\n"
         printf "${LIGHT_RED}URL:${NC} ${urlList1[$outCounter]}\n\n"
         printf "${LIGHT_BLUE}Level 2:${NC}\n"
         printf "${LIGHT_RED}SSTable:${NC} ${SSTableList2[$inCounter]}\n"
         printf "${LIGHT_RED}Owner:${NC} ${ownerIPList2[$inCounter]}\n"
         printf "${LIGHT_RED}URL:${NC} ${urlList2[$inCounter]}\n\n"
      fi
   done
   outCounter=$((outCounter+1))
done
}

function usage {
printf "${LIGHT_GREEN}Usage:${NC} sh getSSTableandTableOwner.sh\n"
echo "Supported Arguments:"
echo "  -h | --help"
echo "-hip | --hostIP=<node ip>"
}

function main {
hostIP=$1;shift
ipFile=$1
getOwnershipInfo $hostIP
rm -rf /tmp/ss_l1.txt
rm -rf /tmp/ss_l2.txt
}

delimiter="="
if [ "$#" == "0" ]
then
    echo "No arguments provided. Please refer usage by specifying -h | --help option."
elif [ "$#" == "1" ]
then
    if [ "$1" == "-h" ] || [ "$1" == "--help" ]
    then
        usage
    elif [ "${1%${delimiter}*}" == "-hip" ] || [ "${1%${delimiter}*}" == "--hostIP" ]
    then
        hostIP=${1#*${delimiter}}
        main $hostIP
    else
        echo "Argument not supported. Please refer usage by specifying -h | --help option."
    fi
else
    echo "Invalid number of arguments provided. Please refer usage by specifying -h | --help option."
fi
