#!/bin/bash


# printf "\n";echo "DATE"; echo "====";date '+%Y-%m-%d %H:%M:%S'; printf "\n"; echo "XDOCTOR VERSION";echo "===============";sudo -i xdoctor --version;printf "\n";echo "ECS VERSION";echo "============"; sudo -i xdoctor --ecsversion;printf "\n";echo "ECS RACK INFO\TOPOLOGY";echo "======================";sudo -i getrackinfo| grep -v Status | grep -v Epoxy| grep -v Master|grep -v Initializing|grep -v Off|grep -v "Warning/Error"|grep -v "Hostname set to default hostname"|grep -v "private interface" | grep -v "Port ID";sudo -i xdoctor --topology; sudo -i xdoctor --topology --vdc; echo "HARDWARE MODEL";echo "==============";sudo doit dmidecode -s system-product-name; printf "\n";echo "SKU"; echo "==="; sed -n 's/.*--sku,\(.*\),--t.*/\1/p' /opt/emc/caspian/installer/log/installer.log; printf "\n"; 



printf "\n";
echo "DATE";
echo "====";
date '+%Y-%m-%d %H:%M:%S';
printf "\n";

echo "XDOCTOR VERSION";
echo "===============";
sudo -i xdoctor --version;
printf "\n";

echo "ECS VERSION";
echo "============";
sudo -i xdoctor --ecsversion;
printf "\n";

echo "ECS RACK INFO\TOPOLOGY";
echo "======================";
sudo -i getrackinfo| grep -v Status | grep -v Epoxy| grep -v Master|grep -v Initializing|grep -v Off|grep -v "Warning/Error"|grep -v "Hostname set to default hostname"|grep -v "private interface" | grep -v "Port ID";
sudo -i xdoctor --topology;
sudo -i xdoctor --topology --vdc;

echo "HARDWARE MODEL";
echo "==============";
sudo doit dmidecode -s system-product-name;
printf "\n";

echo "SKU";
echo "===";
sed -n 's/.*--sku,\(.*\),--t.*/\1/p' /opt/emc/caspian/installer/log/installer.log;
printf "\n"; 