#!/bin/bash

request10_log="/tmp/request10_kpi.log"
request11_log="/tmp/request11_kpi.log"
request12_log="/tmp/request12_kpi.log"
request_1_log="/tmp/request1_kpi.log"
request_log="/tmp/request_kpi.log"
get_log="/tmp/get_kpi.log"
put_log="/tmp/put_kpi.log"
delete_log="/tmp/delete_kpi.log"
head_log="/tmp/head_kpi.log"

function collect_data () {
	echo -n "Data collecting and processing, please wait..."
	DATE=`date +%Y%m%d`
	LOG_FILE='dataheadsvc.log.'$DATE*''
	y=$( date -d "${DATE} -1 days" +'%Y%m%d' )
	LOG_FILE2='dataheadsvc.log.'$y*''
	viprexec "zgrep "RequestLog" /opt/emc/caspian/fabric/agent/services/object/main/log/dataheadsvc.log.${DATE}*"  > $request11_log
	grep -wv '/opt/emc/caspian' $request11_log > $request_1_log
	grep -w '/opt/emc/caspian' $request11_log | cut -c 91-  >> $request_1_log

	viprexec "grep  "RequestLog" /opt/emc/caspian/fabric/agent/services/object/main/log/dataheadsvc.log"  >> $request_1_log
	viprexec "zgrep "RequestLog" /opt/emc/caspian/fabric/agent/services/object/main/log/dataheadsvc.log.${y}*"   >> $request12_log
	grep -wv '/opt/emc/caspian' $request12_log >> $request_1_log
	grep -w '/opt/emc/caspian' $request12_log | cut -c 91-  >> $request_1_log
	echo "DONE"
 }

function option () {

while [ $choice -le 9 ]
do

if [ $batch -ne 1 ]
then
	  echo
      echo '---------------------------- Please select an option from the below list ----------------------------'
      echo ' 1---- To Last 1 hour Data'
      echo ' 2---- To Last 2 hour Data'
      echo ' 3---- To Last 4 hour Data'
      echo ' 4---- To Last 6 hour Data'
      echo ' 5---- To Last 8 hour Data'
      echo ' 6---- To Last 10 hour Data'
      echo ' 7---- To Last 12 hour Data'
      echo ' 8---- To Last 24 hour Data'
      echo ' 9---- To get data between 8AM to 6PM of the current day'
      echo ' 10--- To Exit'
      read -p 'Enter Your choice: ' choice
fi


if [ "$choice" == "1" ]
then
        echo "_________________1 hour data_________________"
        awk -v d="$(date -d'01 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'    $request_1_log >  $request_log
        report

elif [ "$choice" == "2" ]
then
   echo "_________________2 hour data_________________"
    awk -v d="$(date -d'02 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'    $request_1_log >  $request_log
        report

elif [ "$choice" == "3" ]
then
    echo "_________________4 hour data_________________"
    awk -v d="$(date -d'04 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'   $request_1_log >  $request_log
        report

elif [ "$choice" == "4" ]
then
    echo "_________________6 hour data_________________"
    awk -v d="$(date -d'06 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'   $request_1_log >  $request_log
        report

elif [ "$choice" == "5" ]
then
    echo "_________________8 hour data_________________"
    awk -v d="$(date -d'08 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'   $request_1_log >  $request_log
        report

elif [ "$choice" == "6" ]
then
    echo "_________________10 hour data_________________"
    awk -v d="$(date -d'10 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'    $request_1_log >  $request_log
        report

elif [ "$choice" == "7" ]
then
    echo "_________________12 hour data_________________"
    awk -v d="$(date -d'12 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'    $request_1_log >  $request_log
        report

elif [ "$choice" == "8" ]
then
    echo "_________________24 hour data_________________"
    awk -v d="$(date -d'24 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'    $request_1_log >  $request_log
        report

elif [ "$choice" == "9" ]
then
    echo "_________________8AM to 6PM of the current day_________________"
    #awk -v d="$(date -d'24 hours ago' +'%FT%T,000')" '$1>=d &&/RequestLog/'    $request_1_log >  $request_log
    d=`date +%Y-%m-%d`
    grep "${d}T" $request_1_log >  $request_log
    awk -F'[: T]' '$2 >= 8 && $2 <= 18 { print }'  $request_log > $request10_log
    cp $request10_log $request_log
      report
else
	batch=1
fi

if [ $batch -eq 1 ]; then break; fi

done
}



function report () {
echo
grep -w 'GET' $request_log   > $get_log
grep -w 'HEAD' $request_log   > $head_log
grep -w 'PUT' $request_log   > $put_log
grep -w 'DELETE' $request_log   > $delete_log

g=$(grep -w 'GET' $request_log | wc -l)
p=$(grep -w 'PUT' $request_log | wc -l)
h=$(grep -w 'HEAD' $request_log | wc -l)
d=$(grep -w 'DELETE' $request_log | wc -l)
total_request=$(($g + $p + $h + $d))

echo "****** Summary - Request Type *******"
echo -e "Request Type\tCount"
echo "-------------------------"
echo -e "GET\t\t$g"
echo -e "PUT\t\t$p"
echo -e "DELETE\t\t$d"
echo -e "HEAD\t\t$h"
echo "-------------------------"
echo -e "Total\t\t$total_request"
echo
test $total_request -eq 0 && continue

#printf 'Total number of Get request ----> '
#echo $g
#printf 'Total number of put request ----> '
#echo $p
#printf 'Total number of delete request ----> '
#echo $d
#printf 'Total number of head request ----> '
#echo $h
#printf 'Total number of request ---------> '
#echo $total_request

g_500=$(awk '$12==500' $get_log | wc -l)
p_500=$(awk '$12==500' $put_log | wc -l )
d_500=$(awk '$12==500' $delete_log | wc -l)
h_500=$(awk '$12==500' $head_log | wc -l )

echo "***** Summary - HTTP 500 errors *****"
echo -e "Request Type\tCount"
echo "-------------------------"
echo -e "GET\t\t$g_500"
echo -e "PUT\t\t$p_500"
echo -e "DELETE\t\t$d_500"
echo -e "HEAD\t\t$h_500"
echo "-------------------------"
echo -en "Total\t\t"
awk '$12==500' $request_log | wc -l
total_500=$(($g_500 + $p_500 + $d_500 + $h_500))
echo
if test $total_request -gt 0; then
	printf 'SLA on 500 error --------> '
	echo "scale=5; ($total_500/$total_request)*100" | bc -l
	echo
fi

#echo "*************** 500 Error Report on Each type of Request ***************"
#printf 'Total number 500 error for Get request ----> '
#echo $g_500
#printf 'Total number 500 error for put request ----> '
#echo $p_500
#printf 'Total number 500 error for delete request ----> '
#echo $d_500
#printf 'Total number 500 error for head request ----> '
#echo $h_500
#printf 'Total 500 error ---> '
#awk '$12==500' $request_log | wc -l

#total_500=$(($g_500 + $p_500 + $d_500 + $h_500))
#printf 'SLA on 500 error --------> '
#calc() { awk "BEGIN{print $*}"; }
#calc "($total_500/$total_request)*100"

get_lt1s=$(awk '$13<1000' $get_log | wc -l)
get_gt1s=$(awk '$13>=1000 && $13<=10000' $get_log | wc -l)
get_gt10s=$(awk '$13>10000' $get_log | wc -l)
put_lt1s=$(awk '$13<1000' $put_log | wc -l)
put_gt1s=$(awk '$13>=1000 && $13<=10000' $put_log | wc -l)
put_gt10s=$(awk '$13>10000' $put_log | wc -l)
del_lt1s=$(awk '$13<1000' $delete_log | wc -l)
del_gt1s=$(awk '$13>=1000 && $13<=10000' $delete_log | wc -l)
del_gt10s=$(awk '$13>10000' $delete_log | wc -l)
head_lt1s=$(awk '$13<1000' $head_log | wc -l)
head_gt1s=$(awk '$13>=1000 && $13<=10000' $head_log | wc -l)
head_gt10s=$(awk '$13>10000' $head_log | wc -l)

echo
echo "****************** Latency Report *******************"
echo -e "Request Type\t<1s\t\t1-10s\t\t>10s"
echo -e "-----------------------------------------------------"
echo -e "GET\t\t${get_lt1s}\t\t${get_gt1s}\t\t${get_gt10s}"
echo -e "PUT\t\t${put_lt1s}\t\t${put_gt1s}\t\t${put_gt10s}"
echo -e "DELETE\t\t${del_lt1s}\t\t${del_gt1s}\t\t${del_gt10s}"
echo -e "HEAD\t\t${head_lt1s}\t\t${head_gt1s}\t\t${head_gt10s}"
echo

if test $p -gt 0; then
put_lt1s_size=$(awk '$13<1000' $put_log | awk '{sum+=$14}END{if (NR > 0) {printf("%.2f", sum/NR/1024)}else{print "-"}}')
put_gt1s_size=$(awk '$13>=1000 && $13<=10000' $put_log | awk '{sum+=$14}END{if (NR > 0) {printf("%.2f", sum/NR/1024)}else{print "-"}}')
put_gt10s_size=$(awk '$13>10000' $put_log | awk '{sum+=$14}END{if (NR > 0) {printf("%.2f", sum/NR/1024)}else{print "-"}}')

put_lt1s_ssize=$(awk '$13<1000' $put_log | sort -k14 -n | awk '{print $14}' | grep -v -- "-" | head -1 | awk 'END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}')
put_gt1s_ssize=$(awk '$13>=1000 && $13<=10000' $put_log | sort -k14 -n | awk '{print $14}' | grep -v -- "-" | head -1 | awk 'END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}')
put_gt10s_ssize=$(awk '$13>10000' $put_log | sort -k14 -n | awk '{print $14}' | grep -v -- "-" | head -1 | awk 'END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}')

put_lt1s_lsize=$(awk '$13<1000' $put_log | sort -k14 -nr | awk '{print $14}' | grep -v -- "-" | head -1 | awk 'END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}')
put_gt1s_lsize=$(awk '$13>=1000 && $13<=10000' $put_log | sort -k14 -nr | awk '{print $14}' | grep -v -- "-" | head -1 | awk 'END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}')
put_gt10s_lsize=$(awk '$13>10000' $put_log | sort -k14 -nr | awk '{print $14}' | grep -v -- "-" | head -1 | awk 'END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}')

echo "******************** PUT request size *********************"
echo -e "Response Time\tAvg Size(KB)\tSmallest(KB)\tLargest(KB)"
echo -e "-----------------------------------------------------------"
echo -e "<1s\t\t$put_lt1s_size\t\t$put_lt1s_ssize\t\t$put_lt1s_lsize"
echo -e "1-10s\t\t$put_gt1s_size\t\t$put_gt1s_ssize\t\t$put_gt1s_lsize"
echo -e ">10s\t\t$put_gt10s_size\t\t$put_gt10s_ssize\t\t$put_gt10s_lsize"
echo

echo "************************* Top 5 PUT requests by file size *************************"
sort -k14 -nr $put_log | head -5 | awk '{print $1"T"$2,$8,$9,$10,$11,$12,$13,$14,$15}'
echo
echo
echo "*********************** Top 5 PUT requests by Response time ***********************"
sort -k13 -nr $put_log | head -5 | awk '{print $1"T"$2,$8,$9,$10,$11,$12,$13,$14,$15}'
echo
echo
fi
}


function clearfiles () {

	rm $request10_log $request11_log $request12_log $request_1_log $request_log $get_log $put_log $delete_log $head_log 2> /dev/null
	echo
	exit
}

function main () {
    collect_data
    option
    clearfiles
}

trap clearfiles SIGINT
if [ $# -eq 1 ]; then choice=$1;batch=1; else choice=1;batch=0; fi
main