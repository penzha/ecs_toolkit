#! /bin/sh
# set -x

# Primary author: Ian Schorr

# Version 1.1:  Added ktrace support
# Version 1.0:  Initial release

SNAPLEN=0 		# default to 0, or entire frame
MAXFILES=100000		# Maximum number of files that can be specified
MINFILES=2		
MAXSIZE=2000		# Maximum size in MB of a given capture file (files too large are difficult to process)
MINSIZE=1		# Minimum size in MB of a given capture files
TCPDUMP=/usr/sbin/tcpdump	# Location of tcpdump on this system



parse_args() {

	if [ $# -eq 0 ]; then
		usage
	fi

	while( true )
	do

	if [ $# -eq 0 ]; then
	    break;
	fi

	case $1 in

	"-h" )
		usage
		;;

	"-p" )
		if [ "$2" != "" ]; then
			PATTERN="$2"
			shift 2
		else
			echo "ERROR: No pattern supplied after -p"
			exit 1
		fi
		;;

	"-f" )
		if [ "$2" != "" ]; then
			FILTER="$2"
			shift 2
		else
			echo "ERROR: No filter string supplied after -f"
			exit 1
		fi
		;;

	"-i" )
		INTERFACE=$2
		shift 2
		validate_interface $INTERFACE
		;;

	"-s" )
		SNAPLEN=$2
		shift 2

		# The test below not only does a range check but confirms the parameter is numeric
		if [[ ! ( $SNAPLEN -le 65535 && $SNAPLEN -ge 0 ) ]]; then
			echo "ERROR: Invalid snaplen \"$SNAPLEN\".  Range is 0 - 65535"
			exit 1
		fi
		;;

	"-numfiles" )
		
		# The test below not only does a range check but confirms the parameter is numeric
		NUMFILES=$2
		shift 2
		if [[ ! ( $NUMFILES -le $MAXFILES && $NUMFILES -ge $MINFILES ) ]]; then
			echo "ERROR: Invalid number of files \"$NUMFILES\".  Range is $MINFILES - $MAXFILES"
			exit 1
		fi
		;;
	
	"-filesize" )
		FILESIZE=$2
		shift 2
		if [[ ! ( $FILESIZE -le $MAXSIZE && $FILESIZE -ge $MINSIZE ) ]]; then
			echo "ERROR: Invalid file size \"$FILESIZE\".  Range is $MINSIZE - $MAXSIZE (value is in millions of bytes)"
			exit 1
		fi
		;;

	"-logfile" )
		if [ "$2" != "" ]; then
			LOGFILE="$2"
			shift 2
			if [[ ! -f $LOGFILE ]]; then
				echo "ERROR: Invalid log file name \"$LOGFILE\".  File must exist and must not be a directory."
				exit 1
			fi
		else
			echo "ERROR: No logfile name supplied after -logfile"
			exit 1
		fi
		;;
	
	"-w" )
		if [ "$2" != "" ]; then
			FILENAME="$2"
			shift 2
		else
			echo "ERROR: No filename supplied after -w"
			exit 1
		fi
		;;

	* )
		echo "ERROR:  Invalid argument \"$1\""
		usage ;

	esac
	done


	check_required_args


}

usage() {

	echo "usage: $0"
	echo -e "\t-w <filename> -numfiles # -filesize # -i <interface>"
	echo -e "\t[-p <log pattern>] [-logfile <log file>]"
	echo -e "\t[-f <filter>] [-s <snaplen>]"
	echo -e "\tWhere:"
	echo -e "\t\t-w <filename> - the base name to use for tcpdump filenames"
	echo -e "\t\t-numfiles - the maximum number of tcpdump files to rotate through"
	echo -e "\t\t-filesize - the maximum size (in MB) of each file in the rotation"
	echo -e "\t\t-i <interface> - the network interface to capture on (e.g. bond0, eth3)"
	echo -e "\t\t-p <log pattern> - The string to search for in the logs.  Once"
	echo -e "\t\t\tthis is matched, the capture will stop."
	echo -e "\t\t\tBe sure to enclose the pattern in quotes."
	echo -e "\t\t-logfile <log file> - The log file to monitor for the pattern"
	echo -e "\t\t-f <filter> - tcpdump filter to use"
	echo -e "\t\t\tIf the filter contains spaces, enclose it in quotes"
	echo -e "\t\t-s <snaplen> - capture only <snaplen> number of bytes of each packet"
	exit 1

}

start_tcpdump() {
	$TCPDUMP -q -C $FILESIZE -W $NUMFILES -s $SNAPLEN -i $INTERFACE -w "$FILENAME" "$FILTER" &
	TCPDUMPPID=$!
	#echo "tcpdump pid is $TCPDUMPPID"

}

validate_interface() {
	# Confirm that the specified interface name appears to be valid.

	#OLD_IFS=$IFS
	#IFS="\n"
	IFTEMP=`cat /proc/net/dev | cut -f1 -d: | awk '{ print $1 }' | tail -n+3`
	#echo $IFTEST
	# IFNAMES=( `tcpdump -D | cut -f2 -d. | awk '{ print $1 }'` )
	IFNAMES=$IFTEMP
	#IFS=$OLD_IFS

	FOUND_NAME=0

	for NAME in $IFNAMES; do
		if [ "$1" == "$NAME" ]; then
			FOUND_NAME=1
		fi
	done

	if [ $FOUND_NAME -ne 1 ]; then
		echo "ERROR: Invalid interface name \"$1\" specified."
		exit 1
	fi
}


check_required_args() {
	# Just validate that every argument that needs to have been specified has been specified
	
	FAILED=0

	if [ "$INTERFACE" == "" ]; then
		ERRORSTRING="Interface name is required (-i option)\n"
		FAILED=1
	fi
	if [ "$NUMFILES" == "" ]; then
		ERRORSTRING="${ERRORSTRING}Maximum number of files is required (-numfiles option)\n"
		FAILED=1
	fi
        if [ "$FILESIZE" == "" ]; then
                ERRORSTRING="${ERRORSTRING}Maximum file size is required (-filesize option)\n"
                FAILED=1
        fi
        if [ "$FILENAME" == "" ]; then
                ERRORSTRING="${ERRORSTRING}A base filename must be specified (-w option)\n"
                FAILED=1
        fi
        if [ "$PATTERN" == "" -a "$LOGFILE" != "" ]; then
                ERRORSTRING="${ERRORSTRING}If a log file is specified (-logfile option), must define a pattern to search for (-p option)\n"
                FAILED=1
        fi
        if [ "$LOGFILE" == "" -a "$PATTERN" != "" ]; then
		ERRORSTRING="${ERRORSTRING}If a search pattern is specified (-p option), must define a log file to search in (-logfile option)\n"
                FAILED=1
        fi


	if [ $FAILED -eq 1 ]; then
		echo "ERROR:  Required arguments missing."
		echo -e "$ERRORSTRING"
		exit 1
	fi

	
}

check_tcpdump() {
	# Check to see if tcpdump is still running, or has exited for
	# any reason (syntax error, failure writing, killed by something
	# else, etc)

	kill -0 $TCPDUMPPID 2>/dev/null > /dev/null   # Yes, kill -0 checks if the PID still exists

	ret=$?

	if [ $ret -eq 1 ]; then  # process no longer exists
		echo "tcpdump has exited.  Terminating..."
		exit 1
	fi
}

check_pattern() {


	PATTERN_FOUND=`cat $LOGFILE | grep -e '^[A-Z\"0-9]' | grep -e "$PATTERN" |tail -1`

	if [ "$PATTERN_FOUND" != "" ]; then
		END_TIME_CMD="echo \"$PATTERN_FOUND\" $DATEPARSE"
		#END_TIME_TEXT=`echo "$PATTERN_FOUND" $DATEPARSE`
		END_TIME_TEXT=`eval $END_TIME_CMD`
		END_TIME=`date --date="$END_TIME_TEXT" '+%s'`
		#echo $END_TIME_TEXT
		#echo $END_TIME
		if [ -n "$END_TIME" ]; then
			echo "End Time: $END_TIME"
			echo "Start Time: $START_TIME"
			if [ "$END_TIME" -le "$START_TIME" ]; then
				PATTERN_FOUND=""
			fi
		else
			PATTERN_FOUND=""
		fi
	fi
}

get_timestamp_format() {
	# Various log files have various timestamp formats.  Some are parseable by "date" without modification, some aren't.  Need to set up rules for parsing the timestamp in each log message, if any

	formatfound=0

	sample_line=`cat $LOGFILE | grep -e '^[A-Z\"0-9]' | tail -1`
	
	#### EMCSystemLogFile format
	# Line will start with something like "2014-06-12T18:53:46.015Z" (Quotes as part of the string)
	echo $sample_line | grep \"20..-..-..T..:..:..\....Z\" > /dev/null
	if [ $? -eq 0 ]; then
		DATEPARSE=" | cut -b1-24 | sed 's/\"//g' | sed 's/./ /11' | sed 's/./ /24'" # Clear the 11th and 24th characters (the T and the Z), extract only the first 24 chars, remove unnecessary quotes
		LOGFILEFORMAT="EMCSystemLogFile"
		formatfound=1
	fi

	#### syslog format
	# Will be in format like Jun 12 19:04:34
	echo $sample_line | grep -e "[A-Z][a-z][a-z] [0-9][0-9] ..:..:.." > /dev/null
	if [ $? -eq 0 ]; then
		DATEPARSE=" | cut -b1-16" # Date already in parseable format, just need to extract the date portion from the line
		LOGFILEFORMAT="syslog"
		formatfound=1
	fi
	
	#### cemtracer format
	# Format looks like "12 Jun 2014 19:49:32"

	echo $sample_line | grep -e "[0-9][0-9] [A-Z][a-z][a-z] 20[0-9][0-9] ..:..:.." > /dev/null

	if [ $? -eq 0 ]; then
                DATEPARSE=" | cut -b1-21" # Date already in parseable format, just need to extract the date portion from the line
                LOGFILEFORMAT="cemtracer"
                formatfound=1
        fi

	#### ktrace format
	# Format looks like "2015/06/05-17:38:29.645646"

	echo $sample_line | grep -e 20../../..-..:..:..\....... > /dev/null

	if [ $? -eq 0 ]; then
		DATEPARSE=" | cut -b1-26 | sed 's/./ /11'" #Clear the 11th character (the - ), extract the appropriate characters
		LOGFILEFORMAT="ktrace"
		formatfound=1
	fi

	if [ $formatfound -eq 0 ]; then
		echo "ERROR: Format of log file not recognized."
		exit 1
	fi

	echo "Log file format is $LOGFILEFORMAT"
}


clean_up() {
	# Need a better way to do this since it'd kill any tcpdump process running, not just the one spawned by this instance of the script

	#killall tcpdump
	kill $TCPDUMPPID
	exit 0
}

############ Main loop

parse_args "$@"

if [ "$PATTERN" != "" ]; then
	get_timestamp_format

	START_TIME_COMMAND="cat $LOGFILE | grep -e '^[A-Z\"0-9]' | tail -1 $DATEPARSE"
	#echo $START_TIME_COMMAND
	START_TIME_TEXT=`eval ${START_TIME_COMMAND} `
	#START_TIME_TEXT=` eval cat $LOGFILE | grep -e '^[A-Z]' |tail -1 $DATEPARSE`
	START_TIME=`date --date="$START_TIME_TEXT" '+%s'`
	#echo $START_TIME_TEXT
	#echo $START_TIME
	#exit
fi

trap 'clean_up' 1 2 3 4 5 6 7 8 9 10 \
	12 13 15 16 17 19 20 21 22 23 \
	24 25 26 27 28 29 30 31

start_tcpdump

echo "Running.  Hit CTRL-C or kill this script to abort."

FIRST_LOOP=0

sleep 2

while true; do
	check_tcpdump	
	if [ "$PATTERN" != "" ]; then
		if [ $FIRST_LOOP -eq 0 ]; then
			curtime=`date +"%D %T"`
			echo "$curtime:  Waiting for pattern \"$PATTERN\""
			FIRST_LOOP=1
		fi
		check_pattern
		if [ -n "$PATTERN_FOUND" ]; then
			curtime=`date +"%D %T"`
			echo "$curtime: Log message detected.  Stopping tcpdump."
			clean_up
		fi
	fi
	sleep 5
done
