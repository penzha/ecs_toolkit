#!/bin/bash

# dump the whole DT from dtquery with pagination

if [ $# -ne 1 ]; then
    echo "Usage: `basename $0` <DT URL>"
    exit -1
fi

QUERY_URL=$1
QUERY_URL=${QUERY_URL%/}
if [[ $QUERY_URL == *"?"* ]]
then
    QUERY_URL=$QUERY_URL"&useStyle=raw"
else
    QUERY_URL=$QUERY_URL"?useStyle=raw"
fi

TMP_FILE=`mktemp`

MORE_WORDS="Get more:"
has_more=0

while [[ $has_more -eq 0 ]]; do
    curl -Ls $QUERY_URL > $TMP_FILE
    cat $TMP_FILE | grep -v "$MORE_WORDS"

    tail -n1 $TMP_FILE | grep -q "$MORE_WORDS"
    has_more=$?
    QUERY_URL=`tail -n1 $TMP_FILE | awk -F'"' '{print $2}'`
done

rm -f $TMP_FILE

