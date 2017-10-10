#!/bin/bash


VERSION="2.0-beta4"
SCRIPTNAME="$(basename $0)"

ECHO="/bin/echo -e"
OKColor='\033[92m'
FAILColor='\033[91m'
SKIPColor='\033[93m'
GREYColor='\033[0,37m'
ENDColor='\033[0m'

MACHINES="$(realpath ~/MACHINES)"
ALL=""

request_log="/tmp/kpi_reqlog.out"
get_log="/tmp/kpi_getlog.out"
put_log="/tmp/kpi_putlog.out"
delete_log="/tmp/kpi_deletelog.out"
head_log="/tmp/kpi_headlog.out"

RemoteCmdSetup='
request_log="/tmp/kpi_reqlog.out"
get_log="/tmp/kpi_getlog.out"
put_log="/tmp/kpi_putlog.out"
delete_log="/tmp/kpi_deletelog.out"
head_log="/tmp/kpi_headlog.out"

nodeIP="$(hostname -i)"
'



function usage
{
  $ECHO "Usage:  $SCRIPTNAME -n <# hours> [-m <machines file> ]"
  $ECHO "                       [ -all ] |"
  $ECHO "                       < [ -summary ] [ -latency ] [ "
  $ECHO ""
  $ECHO "Options:"
  $ECHO "\t-h: Help              - This help screen"
  $ECHO
  $ECHO "\t-n: NumHours          - Number of hours of history to display"
  $ECHO "\t                        (1 - 24)"
  $ECHO "\t-m: Machines file     - Name and location of machines file to use"
  $ECHO "\t                        (default: '~/MACHINES')"
  $ECHO ""
  $ECHO "\t-all: all data        - Show all KPI tables (default)"
  $ECHO ""
  $ECHO "\t-summary              - Show request count and error count table"
  $ECHO "\t-latency              - Show request latency table"
  $ECHO "\t-top <n>              - Show "


  exit 1

}


function parse_args
{

	if [[ $# -lt 1 ]]; then
		echo "No arguments specified"
		usage
	fi

	while [ -n "$1" ]
	do
		case $1 in
		"" )
			;;
        "-h" )
            usage
            ;;
		"-n" )
			NUMHOURS="$2"

			shift 2
			;;
		"-m" )
			MACHINES="$2"

			if [[ ! -f "$MACHINES" ]]; then
				echo "ERROR:  No file named '$MACHINES' exists"
				exit 1
			fi
			shift 2
			;;
		"-all" )

			ALL="true"

			shift 1
			;;
		"-summary" )

			SUMMARY="true"

			if [[ "$ALL" == "" ]]; then
				ALL="false"
			fi

			shift 1
			;;
		"-latency" )

			LATENCY="true"

			if [[ "$ALL" == "" ]]; then
				ALL="false"
			fi

			shift 1
			;;


        *)
			echo "ERROR:  Invalid option '${1}'"
			echo ""
            usage
            ;;
		esac
	done # Loop through parameters

	if [[ $NUMHOURS -lt 1 || $NUMHOURS -gt 24 ]]; then
		echo "ERROR:  Invalid number of hours.  1 to 24 hours supported."
		exit 1
	fi

	if [[ "$ALL" == "" ]]; then
		ALL="true"
	fi


}

function printDone() {
	echo -e "${OKColor}DONE${ENDColor}"
}

function printFail() {
	echo -e "${FAILColor}FAILED${ENDColor}"
}

function printSkip() {
	if [[ $1 -eq 1 ]]; then # Don't print a newline
		echo -n -e "${SKIPColor}SKIPPED${ENDColor}"
	else
		echo -e "${SKIPColor}SKIPPED${ENDColor}"
	fi
}


# -------------------- Worker functions --------------------

function collect_data () {
	echo -n "Extracting RequestLog data for the last $NUMHOURS hour(s)..."

	TODAYS_DATE="$(date +%Y-%m-%d)"

	tools/eeviprexec -f "$MACHINES" -c "FILES=\"\$(find /var/log -name dataheadsvc.log* -mtime -1 )\"; echo \$FILES; zgrep -h RequestLog \$FILES |  awk -v d=\"\$(date -d'$NUMHOURS hours ago' +'%FT%T,000')\" '\$1>=d &&/RequestLog/' > $request_log" > /dev/null

	printDone

	echo -n "Preprocessing data..."


	tools/eeviprexec -f "$MACHINES" -c "grep -w 'GET' $request_log > $get_log" >/dev/null
	tools/eeviprexec -f "$MACHINES" -c "grep -w 'HEAD' $request_log > $head_log" >/dev/null
	tools/eeviprexec -f "$MACHINES" -c "grep -w 'PUT' $request_log > $put_log" >/dev/null
	tools/eeviprexec -f "$MACHINES" -c "grep -w 'DELETE' $request_log > $delete_log" >/dev/null

	printDone

 }




print_requests() {

	echo "                           All Requests                           500 Errors"
	echo "Node              GETs   PUTs   DELETEs  HEADs   Total    GETs   PUTs   DELETEs  HEADs   Total"



	tools/eeviprexec -f "$MACHINES" -c "$RemoteCmdSetup"'

	g=$(grep -w "GET" $request_log | wc -l)
	p=$(grep -w "PUT" $request_log | wc -l)
	h=$(grep -w "HEAD" $request_log | wc -l)
	d=$(grep -w "DELETE" $request_log | wc -l)
	total_request=$(($g + $p + $h + $d))

	printf "%-18s%-7s%-7s%-9s%-8s%-9s" $nodeIP $g $p $d $h $total_request

	test $total_request -eq 0 && continue

	g_500=$(awk '\''$11==500'\'' $get_log | wc -l)
	p_500=$(awk '\''$11==500'\'' $put_log | wc -l )
	d_500=$(awk '\''$11==500'\'' $delete_log | wc -l)
	h_500=$(awk '\''$11==500'\'' $head_log | wc -l )
	total_500=$(awk '\''$11==500'\'' $request_log | wc -l)


	printf "%-7s%-7s%-9s%-8s%-9s\n" $g_500 $p_500 $d_500 $h_500 $total_500

	' | grep ^[0-9] | sort

}


print_latency() {

	echo "                                     Latency"
	echo "                           GET          |           PUT          |         DELETE"
	echo "Node              <1s     1-10s   >10s  |  <1s     1-10s   >10s  |  <1s     1-10s   >10s"


	tools/eeviprexec -f "$MACHINES" -c "$RemoteCmdSetup"'

	get_lt1s=$(awk '\''$12<1000'\'' $get_log | wc -l)
	get_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $get_log | wc -l)
	get_gt10s=$(awk '\''$12>10000'\'' $get_log | wc -l)
	put_lt1s=$(awk '\''$12<1000'\'' $put_log | wc -l)
	put_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $put_log | wc -l)
	put_gt10s=$(awk '\''$12>10000'\'' $put_log | wc -l)
	del_lt1s=$(awk '\''$12<1000'\'' $delete_log | wc -l)
	del_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $delete_log | wc -l)
	del_gt10s=$(awk '\''$12>10000'\'' $delete_log | wc -l)
	#head_lt1s=$(awk '\''$12<1000'\'' $head_log | wc -l)
	#head_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $head_log | wc -l)
	#head_gt10s=$(awk '\''$12>10000'\'' $head_log | wc -l)

	printf "%-18s%-8s%-8s%-9s%-8s%-8s%-9s%-8s%-8s%-9s\n" $nodeIP $get_lt1s $get_gt1s $get_gt10s $put_lt1s $put_gt1s $put_gt10s $del_lt1s $del_gt1s $del_gt10s

	' | grep ^[0-9] | sort

}

print_sizes() {

	echo "                                      Request Sizes"
	echo "                              GET                             PUT"
	echo "Node              Avg (KB)  Max (KB)  Min (KB)    Avg (KB)  Max (KB)  Min (KB)"

	tools/eeviprexec -f "$MACHINES" -c "$RemoteCmdSetup"'

	get_size=$(awk '\''{sum+=$14}END{if (NR > 0) {printf("%.2f", sum/NR/1024)}else{print "-"}}'\'' $get_log)
	get_min=$(sort -k14 -n $get_log | awk '\''{print $14}'\'' | grep -v -- "-" | head -1 | awk '\''END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}'\'')
	get_max=$(sort -k14 -nr $get_log | awk '\''{print $14}'\'' | grep -v -- "-" | head -1 | awk '\''END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}'\'')

	put_size=$(awk '\''{sum+=$13}END{if (NR > 0) {printf("%.2f", sum/NR/1024)}else{print "-"}}'\'' $put_log)
	put_min=$(sort -k13 -n $put_log | awk '\''{print $13}'\'' | grep -v -- "-" | head -1 | awk '\''END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}'\'')
	put_max=$(sort -k13 -nr $put_log | awk '\''{print $13}'\'' | grep -v -- "-" | head -1 | awk '\''END{if (NR > 0) {printf("%.2f", $1/1024)}else{print "-"}}'\'')

	printf "%-18s%-10s%-10s%-12s%-10s%-10s%-12s\n" $nodeIP $get_size $get_max $get_min $put_size $put_max $put_min
	' | grep ^[0-9] | sort

}

print_get_latency_per_size() {

	echo "                                GET Latency Per Request Size"
	echo "                          <10M                     10-100M               >100M"
	echo "Node              <1s     1-10s   >10s  |  <1s     1-10s   >10s  |  <1s     1-10s   >10s"

	tools/eeviprexec -f "$MACHINES" -c "$RemoteCmdSetup"'

	get_lt10M_lt1s=$(awk '\''$12<1000'\'' $get_log | awk '\''$14<10000'\'' | wc -l)
	get_lt10M_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $get_log | awk '\''$14<10000'\'' | wc -l)
	get_lt10M_gt10s=$(awk '\''$12>10000'\'' $get_log | awk '\''$14<10000'\'' | wc -l)

	get_gt10M_lt1s=$(awk '\''$12<1000'\'' $get_log | awk '\''$14>=10000 && $14 <= 100000'\'' | wc -l)
	get_gt10M_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $get_log | awk '\''$14>=10000 && $14 <= 100000'\'' | wc -l)
	get_gt10M_gt10s=$(awk '\''$12>10000'\'' $get_log | awk '\''$14>=10000 && $14 <= 100000'\'' | wc -l)

	get_gt100M_lt1s=$(awk '\''$12<1000'\'' $get_log | awk '\''$14>100000'\'' | wc -l)
	get_gt100M_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $get_log | awk '\''$14>100000'\'' | wc -l)
	get_gt100M_gt10s=$(awk '\''$12>10000'\'' $get_log | awk '\''$14>100000'\'' | wc -l)

	printf "%-18s%-8s%-8s%-9s%-8s%-8s%-9s%-8s%-8s%-9s\n" $nodeIP $get_lt10M_lt1s $get_lt10M_gt1s $get_lt10M_gt10s $get_gt10M_lt1s $get_gt10M_gt1s $get_gt10M_gt10s $get_gt100M_lt1s $get_gt100M_gt1s $get_gt100M_gt10s

	' | grep ^[0-9] | sort

}

print_put_latency_per_size() {

	echo "                                PUT Latency Per Request Size"
	echo "                          <10M                     10-100M               >100M"
	echo "Node              <1s     1-10s   >10s  |  <1s     1-10s   >10s  |  <1s     1-10s   >10s"

	tools/eeviprexec -f "$MACHINES" -c "$RemoteCmdSetup"'

	put_lt10M_lt1s=$(awk '\''$12<1000'\'' $put_log | awk '\''$13<10000'\'' | wc -l)
	put_lt10M_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $put_log | awk '\''$13<10000'\'' | wc -l)
	put_lt10M_gt10s=$(awk '\''$12>10000'\'' $put_log | awk '\''$13<10000'\'' | wc -l)

	put_gt10M_lt1s=$(awk '\''$12<1000'\'' $put_log | awk '\''$13>=10000 && $13 <= 100000'\'' | wc -l)
	put_gt10M_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $put_log | awk '\''$13>=10000 && $13 <= 100000'\'' | wc -l)
	put_gt10M_gt10s=$(awk '\''$12>10000'\'' $put_log | awk '\''$13>=10000 && $13 <= 100000'\'' | wc -l)

	put_gt100M_lt1s=$(awk '\''$12<1000'\'' $put_log | awk '\''$13>100000'\'' | wc -l)
	put_gt100M_gt1s=$(awk '\''$12>=1000 && $12<=10000'\'' $put_log | awk '\''$13>100000'\'' | wc -l)
	put_gt100M_gt10s=$(awk '\''$12>10000'\'' $put_log | awk '\''$13>100000'\'' | wc -l)

	printf "%-18s%-8s%-8s%-9s%-8s%-8s%-9s%-8s%-8s%-9s\n" $nodeIP $put_lt10M_lt1s $put_lt10M_gt1s $put_lt10M_gt10s $put_gt10M_lt1s $put_gt10M_gt1s $put_gt10M_gt10s $put_gt100M_lt1s $put_gt100M_gt1s $put_gt100M_gt10s

	' | grep ^[0-9] | sort

}


function report () {

	echo
	if [[ "$SUMMARY" == "true" || "$ALL" == "true" ]]; then
		print_requests
		echo
	fi
	if [[ "$LATENCY" == "true" || "$ALL" == "true" ]]; then
		print_latency
		echo
	fi
	print_sizes
	echo
	if [[ "$LATENCY" == "true" || "$ALL" == "true" ]]; then
		print_get_latency_per_size
		echo
		print_put_latency_per_size
		echo
	fi

}


function clearfiles () {

	echo
	echo -n "Cleaning up temp files..."
	tools/eeviprexec -f "$MACHINES" -c "rm $request_log $get_log $put_log $delete_log $head_log 2> /dev/null" > /dev/null
	printDone
	exit
}



# -------------------- Main program logic begins here --------------------

echo "$SCRIPTNAME Version ${VERSION}"
echo

parse_args $*

collect_data
report
#clearfiles

trap clearfiles SIGINT
