import commands
import xml
import xml.etree.ElementTree as ET
import os
import re
import sys

def comfunc(ucmd):
#    print ucmd
    status,output = commands.getstatusoutput(ucmd)
    #print output
   # print status
   # print ('you in unix command funcgtion')
    if  not status:
        return (output.split())
    else:
        return None

def unixcmd(cmd):
    status, output = commands.getstatusoutput(cmd)
    return output

ss_level_dt=comfunc('curl -s "http://`hostname -i`:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_KEY?type=PARTITION"|grep -B1 schemaType|grep http')
#print (ss_level_dt)
if ss_level_dt:
    for i in ss_level_dt:
#print lines
        print (i)
       # cmd = "curl -s '%s&showvalue=gpb'" % i
        #ss = comfunc(cmd)
        #print (ss)
        cmd = "curl -s '%s&showvalue=gpb' | grep -B1 'PARTITION_UP'  | grep 'schemaType SSTABLE_KEY type ' | awk '{print $8} END {print $6}' " % i
        partitiondown_sstable = comfunc(cmd)
        #print partitiondown_sstable
        if partitiondown_sstable:
            node_ip = partitiondown_sstable.pop()
            print ("****NODE IP ===== %s ****"  % node_ip)
           # if partitiondown_sstable[0] == '#ffffff;':
                 #      x= partitiondown_sstable.pop()
                                #print partitiondown_sstable
            print ("==>Number of partitions up in SS_1 is : %s" % len(partitiondown_sstable))

ss_level2_dt=comfunc('curl -s "http://`hostname -i`:9101/diagnostic/SS/2/DumpAllKeys/SSTABLE_KEY?type=PARTITION"|grep -B1 schemaType|grep http')
#print (ss_level2_dt)
if ss_level2_dt:
    for i in ss_level2_dt:
#print lines
        print (i)
       # cmd = "curl -s '%s&showvalue=gpb'" % i
        #ss = comfunc(cmd)
        #print (ss)

        cmd = "curl -s '%s&showvalue=gpb' | grep -B1 'PARTITION_UP'  | grep 'schemaType SSTABLE_KEY type ' | awk '{print $8} END {print $6}' " % i
        partitiondown_sstable = comfunc(cmd)
        #print partitiondown_sstable
        if partitiondown_sstable:
            node_ip = partitiondown_sstable.pop()
            print "****NODE IP ===== %s ****"  % node_ip
           # if partitiondown_sstable[0] == '#ffffff;':
                 #      x= partitiondown_sstable.pop()
                                #print partitiondown_sstable
            print ("==>Number of partitions up in SS_2 is : %s" % len(partitiondown_sstable))






ss_level2_dt=comfunc('curl -s "http://`hostname -i`:9101/diagnostic/SS/2/DumpAllKeys/SSTABLE_KEY?type=PARTITION"|grep -B1 schemaType|grep http')
#print (ss_level2_dt)
if ss_level2_dt:
    for i in ss_level2_dt:
#print lines
        print (i)
       # cmd = "curl -s '%s&showvalue=gpb'" % i
        #ss = comfunc(cmd)
        #print (ss)

        cmd = "curl -s '%s&showvalue=gpb' | grep -B1 'PARTITION_REMOVED'  | grep 'schemaType SSTABLE_KEY type ' | awk '{print $8} END {print $6}' " % i
        partitiondown_sstable = comfunc(cmd)
        #print partitiondown_sstable
        if partitiondown_sstable:
            node_ip = partitiondown_sstable.pop()
            print "****NODE IP ===== %s ****"  % node_ip
           # if partitiondown_sstable[0] == '#ffffff;':
                 #      x= partitiondown_sstable.pop()
                                #print partitiondown_sstable
            print ("==>Number of partitions removed in SS_2 is : %s" % len(partitiondown_sstable))




ss_level2_dt=comfunc('curl -s "http://`hostname -i`:9101/diagnostic/SS/1/DumpAllKeys/SSTABLE_KEY?type=PARTITION"|grep -B1 schemaType|grep http')
#print (ss_level2_dt)
if ss_level2_dt:
    for i in ss_level2_dt:
#print lines
        print (i)
       # cmd = "curl -s '%s&showvalue=gpb'" % i
        #ss = comfunc(cmd)
        #print (ss)

cmd = "curl -s '%s&showvalue=gpb' | grep -B1 'PARTITION_REMOVED'  | grep 'schemaType SSTABLE_KEY type ' | awk '{print $8} END {print $6}' " % i
        partitiondown_sstable = comfunc(cmd)
        #print partitiondown_sstable
        if partitiondown_sstable:
            node_ip = partitiondown_sstable.pop()
            print "****NODE IP ===== %s ****"  % node_ip
           # if partitiondown_sstable[0] == '#ffffff;':
                 #      x= partitiondown_sstable.pop()
                                #print partitiondown_sstable
            print ("==>Number of partitions removed in SS_1 is : %s" % len(partitiondown_sstable))
sys.exit(0)

