#!/bin/bash


VERSION="0.0.4"
SCRIPTNAME="$(basename $0)"

ECHO="/bin/echo -e"
OKColor='\033[92m'
FAILColor='\033[91m'
WARNColor='\033[93m'
GREYColor='\033[0,37m'
ENDColor='\033[0m'

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MACHINES="$(realpath ~/MACHINES)"
ALL=""
ERRORCODES=""

source_logs=

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

MAX_REPORT_DAYS=10 # Max time the user can specify to run a report for, in days.
MAX_REPORT_DURATION=$(( $MAX_REPORT_DAYS*24*60*60 ))



function usage
{
  $ECHO "Usage:  $SCRIPTNAME [-start <time>] [-end <time>] [ -m <machines file> ]"
  $ECHO ""
  $ECHO "Options:"
  $ECHO "\t-h: Help                - This help screen"
  $ECHO
  $ECHO "\t-start <time>           - Start time for statistics to calculate.  Can be any string"
  $ECHO "\t                          supported by the date -d option, including absolute"
  $ECHO "\t                          timestamps (e.g. '2017-07-19 21:00:00'), relative time"
  $ECHO "\t                          strings (e.g. '2 hours ago'), etc."
  $ECHO "\t                          (default: '1 hour ago')"
  $ECHO "\t-end <time>             - End time for statistics."
  $ECHO "\t                          (default: 'now')"
  $ECHO "\t-n <x hours>            - Shorthand for '-start \"x hours ago\"'"
  $ECHO ""


  exit 1

}


function parse_args
{


        STARTTIME="1 hour ago" # Default kpi report period
        ENDTIME="now"

        while [ -n "$1" ]
        do
                case "$1" in
                "" )
                        ;;
        "-h" )
            usage
            ;;
                "-n" )

                        NUMTIMESET=1
                        if [[ $STARTTIMESET -eq 1 ]]; then
                                echo "ERROR:  Cannot specify both -n and -start options."
                                exit 1
                        fi

                        STARTTIME="$2 hours ago"

                        shift 2
                        ;;
                "-start" )

                        STARTTIMESET=1
                        if [[ $NUMTIMESET -eq 1 ]]; then
                                echo "ERROR:  Cannot specify both -n and -start options."
                                exit 1
                        fi

                        STARTTIME="$2"

                        shift 2
                        ;;
                "-end" )

                        ENDTIME="$2"

                        shift 2
                        ;;
                "-topnum" )
                        NUMTOP="$2"

                        if [[ $NUMTOP -lt 1 || $NUMTOP -gt 1000 ]]; then
                                echo "ERROR:  Invalid number of hosts and files.  1 to 1000 supported."
                                echo
                                exit 1
                        fi

                        shift 2
                        ;;
                "-m" )
                        MACHINES="$2"

                        if [[ ! -f "$MACHINES" ]]; then
                                echo "ERROR:  No file named '$MACHINES' exists"
                                echo
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
                "-sizes" )

                        SIZES="true"

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
                "-rates" )

                        RATES="true"

                        if [[ "$ALL" == "" ]]; then
                                ALL="false"
                        fi

                        shift 1
                        ;;
                "-top" )

                        TOP="true"

                        if [[ "$ALL" == "" ]]; then
                                ALL="false"
                        fi

                        shift 1
                        ;;
                "-errorcode" )

                        if [[ "$(echo "$2" | tr '[:upper:]' '[:lower:]')" == "all" ]]; then
                                ERRORCODES="500 503 404 403 400"
                        else
                                ERRORCODES="$ERRORCODES $2"
                        fi

                        shift 2
                        ;;
                "-keepcache" ) # Do not delete cache files containing requestlog messages for the specified timeframe
                               # Useful in certain debugging situations
                    KEEPCACHE="true"
                    shift 1
                    ;;

        *)
                        echo "ERROR:  Invalid option '${1}'"
                        echo ""
            usage
            ;;
                esac
        done # Loop through parameters


        # Validate specified (or default) start and end times

        # Argument can be any number of strings representing a date in different formats, including relative
        # times, etc.  Anything accepted by "date -d" command.

        # Get the absolute time corresponding to what the user passed.  At the same time, validate the
        # timestamp looks valid

        START_TIMESTAMP="$(date -d"$STARTTIME" +'%F %T' 2>/dev/null)"
        END_TIMESTAMP="$(date -d"$ENDTIME" +'%F %T' 2>/dev/null)"

        if [[ "$START_TIMESTAMP" == "" ]]; then
                echo "ERROR: Start timestamp passed ('$STARTTIME') is not a valid time string."
                echo
                exit 1
        fi

        if [[ "$END_TIMESTAMP" == "" ]]; then
                echo "ERROR: End timestamp passed ('$ENDTIME') is not a valid time string."
                echo
                exit 1
        fi



        # Check to see if the timeframes specified are greater than the max allowed

        report_duration=$(( $(date --date="$ENDTIME" +%s) - $(date --date="$STARTTIME" +%s ) ))

        if [[ $report_duration -gt $MAX_REPORT_DURATION ]]; then
                echo "ERROR: Specified report duration is longer than the max allowed of $MAX_REPORT_DAYS days."
                echo ""
                exit 2
        fi



        if [[ "$ALL" == "" ]]; then
                ALL="true"
        fi

        if [[ "$ERRORCODES" == "" ]];then
                ERRORCODES="500"
        fi
        if [[ "$NUMTOP" == "" ]];then
                NUMTOP="10"
        fi

        RemoteCmdSetup="$RemoteCmdSetup\
        report_duration=\"$report_duration\" \
        GC_LOGS=\"/var/log/blobsvc-gc-*.current\"
        "

}

function printDone() {
        echo -e "${OKColor}DONE${ENDColor}"
}

function printFail() {
        echo -e "${FAILColor}FAILED${ENDColor}"
}

function printWarn() {
        if [[ $1 -eq 1 ]]; then # Don't print a newline
                echo -n -e "${WARNColor}SKIPPED${ENDColor}"
        else
                echo -e "${WARNColor}SKIPPED${ENDColor}"
        fi
}


# -------------------- Worker functions --------------------


function check_log_age() {
        # Verify that each node's logs appear to contain data that's older than the start of the request period.  If not,
        # then generate a warning for each node

        echo -n -e "${WARNColor}"

        remote_cmd="$RemoteCmdSetup"'

        FILE="$(ls -t $GC_LOGS | tail -1)"
        #echo $nodeIP
        #echo $FILE
        FIRST_TSTAMP="$(zgrep -e "^[0-9]*-[0-9]*-[0-9]*T[0-9]*:[0-9]*:[0-9]*" $FILE | head -1 | awk "{ print \$1 }")"
        #echo "FIRST_TSTAMP: $FIRST_TSTAMP"
        '

        #FIRST_TSTAMP="$(zgrep -e "^[0-9]*-[0-9]*-[0-9]* [0-9]*:[0-9]*:[0-9]*," $FILE | head -1 | awk "{ print \$1 }")"

        remote_cmd="${remote_cmd}echo \"\$FIRST_TSTAMP\" | awk -v s=\"$(date -d"$STARTTIME" +'%FT%T,000')\" "
        remote_cmd="${remote_cmd}"'"s<\$1 { print \"WARNING: \"$nodeIP\": Start time specified (\"s\") is earlier than the oldest log data (\"\$1\").  Results will be partial.\" }"
        echo $nodeIP
        '

        #echo "$remote_cmd"


        ${SCRIPTDIR}/tools/eeviprexec -c -f "$MACHINES" "$remote_cmd" | grep "^WARNING" | sort

        echo -e "${ENDColor}"


}



print_stalls() {


        echo "                  Total         App         App stopped  # long    Running     Stopped     Long Stall"
        echo "Node              time (mins)   ran (mins)  (mins)       stalls    time %      time %      time %"
        echo

        STALL_DATA="$(${SCRIPTDIR}/tools/eeviprexec -c -f "$MACHINES" "$RemoteCmdSetup "'
        read total_time app_ran app_stopped num_stalls run_perc stop_perc stall_perc <<< '"\
        \$(awk -v stall_time=0 -v s=\"\$(date -d'$STARTTIME' +'%FT%T,000')\" -v e=\"\$(date -d'$ENDTIME' +'%FT%T,000')\" '\$1>=s && \$1<=e' "'$GC_LOGS | awk '\''
                /Application time:/ { ran += $(NF-1) } /stopped:/ { stoptime=$(NF-6); if (stoptime > 5) { num_stalls+=1; stall_time+=stoptime } stopped += stoptime; stopThread += $(NF-1) } END {
                total = ran + stopped

                printf("%.2f %.2f %.2f %d %.2f%% %.2f%% %.2f%%", total/60.0, ran/60.0, stopped/60.0, num_stalls, ran*100.0/total, stopped*100.0/total, stall_time*100.0/total)
                }'\'')


    printf "%-17s %-13s %-11s %-12s %-11s %-11s %-10s %-10s\n" $nodeIP $total_time $app_ran $app_stopped $num_stalls $run_perc $stop_perc $stall_perc

        #count=5
        #echo -e "\nTop $count gc stalls"
        #grep stopped $GC_LOGS | sort -k 11 -n -r | head -n $count

        ' | grep ^[0-9] | sort )"



        total_avg=$(echo "$STALL_DATA" | awk '{sum+=$2}END{if (NR > 0) {printf("%.2f", sum/NR)}else{print "0"}}')
        app_ran_avg=$(echo "$STALL_DATA" | awk '{sum+=$3}END{if (NR > 0) {printf("%.2f", sum/NR)}else{print "0"}}')
        app_stopped_avg=$(echo "$STALL_DATA" | awk '{sum+=$4}END{if (NR > 0) {printf("%.2f", sum/NR)}else{print "0"}}')
        stall_count_avg=$(echo "$STALL_DATA" | awk '{sum+=$5}END{if (NR > 0) {printf("%.0f", sum/NR)}else{print "0"}}')
        runtime_perc_avg=$(echo "$STALL_DATA" | awk '{sum+=$6}END{if (NR > 0) {printf("%.2f%%", sum/NR)}else{print "0"}}')
        stoptime_perc_avg=$(echo "$STALL_DATA" | awk '{sum+=$7}END{if (NR > 0) {printf("%.2f%%", sum/NR)}else{print "0"}}')
        #stopthread_perc_avg=$(echo "$STALL_DATA" | awk '{sum+=$}END{if (NR > 0) {printf("%.2f%%", sum/NR)}else{print "0"}}')
        stalltime_perc_avg=$(echo "$STALL_DATA" | awk '{sum+=$8}END{if (NR > 0) {printf("%.2f%%", sum/NR)}else{print "0"}}')


        echo "$STALL_DATA"
        echo
        printf "%-17s %-13s %-11s %-12s %-11s %-11s %-10s %-10s\n" "Overall:" $total_avg $app_ran_avg $app_stopped_avg $stall_count_avg $runtime_perc_avg $stoptime_perc_avg $stalltime_perc_avg
        echo
        echo '(Note:  "Long stall time" is defined as a Java GC operation that ran - stalling processing - for more than 5s)'


}


# -------------------- Main program logic begins here --------------------

echo "$SCRIPTNAME Version ${VERSION}"
echo

parse_args "$@"

echo "Report start: $START_TIMESTAMP"
echo "Report end:   $END_TIMESTAMP"

check_log_age
print_stalls
