#!/bin/bash

vnest_out="/tmp/vnest.out"

getrackinfo -c /tmp/MACHINES
viprexec -f /tmp/MACHINES 'grep "readOnly, chunk or JR is not created yet" /opt/emc/caspian/fabric/agent/services/object/main/log/vnest.log | tail -1' > $vnest_out

echo
readonly_nodes=$(grep -B1 "readOnly, chunk or JR is not created yet" $vnest_out | grep Output | awk '{print $NF}' | xargs echo)
if test -z "$readonly_nodes"; then
    echo "No vnest issue on any nodes"
else
    echo "Vnest is read only on the following node/s,"
    echo $readonly_nodes | tr ' ' '\n'
fi
echo
rm -f $vnest_out