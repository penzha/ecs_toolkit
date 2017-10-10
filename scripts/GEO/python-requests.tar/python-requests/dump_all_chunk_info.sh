#!/bin/sh
dataip=localhost
if [ $# -gt 0 ]; then
    dataip=$1
fi

curl -s "http://${dataip}:9101/diagnostic/CT/1/" | xmllint --format - | grep table_detail_link | awk -F"[<|>|?]" '{print "sh /home/admin/python-requests/dt_pag_dump.sh \""$3"\CHUNK?showvalue=gpb\""}' > /home/admin/python-requests/curl_command
sh -x /home/admin/python-requests/curl_command > /home/admin/python-requests/ct_info
