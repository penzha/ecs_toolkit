#!/bin/bash

folders="$1"

while read folder; do
    grep ^"${folder}/" WaferProbe.list >> WaferProbe.list.out
done < ${folders}

printf "Done\n"