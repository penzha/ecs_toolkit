#!/usr/bin/python

######################### Keywords #########################
# linecache, Queue, multi-threads
# concurrent.futures,
# list of dicts
# python files operation, with option
# 
############################################################


# 0. save scan objects in a file
# 1. read objects list from file and split, save each parts in List but not in a file
# 2. multi-threads process these Lists

import sys
import commands
import re
import os

import datetime
import socket
import getopt
import time

import subprocess
import threading
import linecache
import hashlib
import Queue

from svc_base import Common
import pdb

start_time = time.time()
result_filename = ""

debug = False
threads = 1
checkonly = 0
ip_addr = ""

common = Common("object_ownerhistory_check")

# TODO:
# use Queue + multi-threads
# use concurrent.futures
# use zip() to replace split_objects()
# use logging()


def get_linenum_option1 (filename):
    count = 0
    fp = open(filename, "rb")
    while 1:
      buffer = fp.read(65536)
      if not buffer:break
      count += buffer.count('\n')
      
    return count

# get_linenum_option2 seems faster than get_linenum_option1
def get_linenum_option2 (filename):
    print "++++++++++++++ get_linenum_option2 ++++++++++++++"
    count = 0
    with open(filename) as fp:
      count = sum(1 for x in fp)
      
    return count

def split_objects(count):
    print "++++++++++++++ split_objects ++++++++++++++"
    
    mod = count / threads
    print "mod: ", mod
    result_list = []
    
    if count % threads == 0:
      split_num = threads
    else:
      split_num = threads + 1
      
    for i in range(split_num):
      start = i * mod + 1
      end = start + mod -1
      if (end > count):
        end = count
      result_list.append((start, end))
      
    return result_list
  

### two methods for multiple threads read file
# 1. Queue
# 2. linecache
def get_OBJECT_OWNER_HISTORY_from_ls(workdir, timestamp):
    print "++++++++++++++ get_OBJECT_OWNER_HISTORY_from_ls ++++++++++++++"
    
    object_file_name = '{}/OBJECT_OWNER_HISTORY.{}'.format(workdir, timestamp)
    #object_file_name = '/tmp/penzha/object_python/object_check/OBJECT_OWNER_HISTORY'
    cmd = 'curl -s http://{}:9101/diagnostic/LS/0/DumpAllKeys/LIST_ENTRY?type=OBJECT_OWNER_HISTORY | grep schemaType > {}'.format(ip_addr, object_file_name)
    result = common.run_cmd(cmd, noErrorHandling=True)
    
    object_count = get_linenum_option2(object_file_name)
    print "There are {} objects has OBJECT_OWNER_HISTORY type and need to be scannedobject_count".format(object_count)
    
    if (checkonly == 1):
        return
    
    # separate objects to multiple files (align with thread number), each thread parse each file
    #parse_objects_linecache(object_file_name, object_count)
    
    # read all objects to queue and different threads read object from queue
    parse_objects_queue(object_file_name)
    
  

'''
============= functions for using linecache to multi-threads process objects =============
'''
### use linecache to seperate objects list into different parts, each threads read each parts
def parse_objects_linecache(file_name, count):
    print "++++++++++++++ parse_objects_linecache ++++++++++++++"
    line_range = split_objects(count)
    print "line_range: ", line_range
    
    # multi-threads process (how to do sth after all threads completed ?)
    for i in range(len(line_range)):
        #print "thread %i: start %i, end %i" % (i, line_range[i][0], line_range[i][1])
        objects = linecache.getlines(file_name)[line_range[i][0]-1:line_range[i][1]]
        #print "objects: ", objects
        process_thread = threading.Thread(target=parse_objects, args=(objects,))
        process_thread.start()
        
        # clear cache here ???
        linecache.clearcache()
        
    # how to wait all threads complete and do sth after that. (close file descriptor, ....)
    print "+++++++ out of thread for"


'''
============= functions for using queue to multi-threads process objects =============
'''
### read all objects into queue, each threads read from queue (Queue in python is thread safe!)
def parse_objects_queue(file_name):
    print "++++++++++++++ parse_objects_queue ++++++++++++++"


'''
============= concurrent.futures =============
'''


###
def parse_updates (oid, update_info, update_list):
    print "++++++++++++++ retrieve_updates ++++++++++++++"
    updates = update_info.split('schemaType')
    #index = 0
    #update_dict = {}
    update_list = []    
    
    for update in updates:
        if len(update) == 0:
            continue
        update_dict = {}
        update_dict['current-zone-is-owner'] = 'NA'
        update_dict['omarker'] = 'NA'
        update_dict['dmarker'] = 'NA'
        update_dict['has-ownerhistory'] = 'NA'
        owner_flag = False
        omarker_flag = False
        dmarker_flag = False
        ownerhistory_flag = False
        
        update_content = update.split('\n')
        for line in update_content:
            if 'sequence' in line:
                words = line.split()
                update_dict['sequence'] = words[6]
            if 'current-zone-is-owner' in line:
                owner_flag = True
            if 'omarker' in line:
                omarker_flag = True
            if 'dmarker' in line:
                dmarker_flag = True
            if 'has-ownerhistory' in line:
                ownerhistory_flag = True
                
            if 'value' in line:
                if owner_flag:
                    content = line.split('"')
                    update_dict['current-zone-is-owner'] = content[1]
                    owner_flag = False
                if omarker_flag:
                    content = line.split('"')
                    update_dict['omarker'] = content[1]
                    omarker_flag = False
                if dmarker_flag:
                    content = line.split('"')
                    update_dict['dmarker'] = content[1]
                    dmarker_flag = False
                if ownerhistory_flag:
                    content = line.split('"')
                    update_dict['has-ownerhistory'] = content[1]
                    ownerhistory_flag = False
                    
        update_list.append(update_dict)
        #print "update_dict: ", update_dict
        
    #print "update count: ", len(update_list)
    #print "update_list: ", update_list
    
    # detect ownerhistory issue
    # check the last update, if its key "dmarker" is true then go to next step. If not, skip this object.
    # check the previous update of the last one, if its key "has-ownerhistory" is true and the last object does not have key "has-ownerhistory", then report this objects.
    last_index = len(update_list) - 1
    last_update_dmarker = update_list[last_index]['dmarker']
    last_update_hasownerhistory = update_list[last_index]['has-ownerhistory']
    previous_last_update_hasownerhistory = update_list[last_index-1]['has-ownerhistory']
    
    if last_update_dmarker == "true":
        print "last_update_dmarker is true"
        if previous_last_update_hasownerhistory == "true":
            print "previous_last_update_hasownerhistory is true"
            if last_update_hasownerhistory == "NA":
                result_content = "object: {} detect has-ownerhistory missing issue.\n".format(oid)
                #print result_content
                with open(result_filename, 'a') as f:
                    f.write(result_content)


def parse_objects(list):
    print "++++++++++++++ parse_objects ++++++++++++++"
    
    for i in range(len(list)):
        line = list[i].strip('\n')
        
        # get parent and child
        string_dict = line.split(' ')
        parent = string_dict[5]
        string_dict = line.split('child ')
        child = string_dict[1]
        
        # caculate oid
        oid = hashlib.sha256(b'%s.%s' % (parent, child)).hexdigest()
        #print "oid: ", oid
        #time.sleep(5)
        
        # query url for retrieve update
        cmd = 'curl -s "http://{}:9101/diagnostic/OB/0/DumpAllKeys/OBJECT_TABLE_KEY?type=UPDATE&objectId={}" | grep -B1 schemaType | grep -v schemaType | tr -d \'\r\' | sed \'s/<.*>//g\''.format(ip_addr, oid)
        result = common.run_cmd(cmd, noErrorHandling=True)
        ob_url = result['stdout']
        #print "ob_url: ", ob_url
        
        # get update info and save to a list of Dict Hash Table
        # List: update_list = []; update_list[0] = update0, update_list[1] = update1 
        # Dict Hash Table: update = {}; 
        #   update0['sequence'] = xxx
        #   update0['current-zone-is-owner'] = xxx
        #   update0['omarker'] = xxx
        #   update0['dmarker'] = xxx
        #   update0['has-ownerhistory'] = xxx
        cmd = 'curl -s "{}&useStyle=raw&showvalue=gpb" | grep -A1 \'schemaType\|current-zone-is-owner\|omarker\|dmarker\|has-ownerhistory\''.format(ob_url.strip('\n'))
        result = common.run_cmd(cmd, noErrorHandling=True)
        update_info = result['stdout']
        #print "ob_url: ", ob_url
        #print "==================== update_info: ", update_info
        
        if update_info:
            update_list = []
            parse_updates(oid, update_info, update_list)

    
def get_host_ip():
    try:
      s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
      s.connect(('8.8.8.8', 80))
      ip = s.getsockname()[0]
    finally:
      s.close()
    
    return ip
	
def parse_args():
    options = """
        Usage:  $SCRIPTNAME [-h] [--debug] [--ip ipaddr] [--threads thread_num]
        
        Options:
        \t-h: Help         - This help screen
        \t--debug: Debug    - Produces additional debugging output
        \t--ip:             - used when customer using network separation to specify data ip
        \t--threads: num    - simulate multiple threads
        \t--objects         - only check how many objects need to be scanned
        """
    
    try:
        opts, args = getopt.getopt(sys.argv[1:], "h", ["debug","ip=","threads=","objects"])
    except getopt.GetoptError as err:
        # print help information and exit
        print (err)
        print options
        sys.exit(2)
      
    for opt, arg in opts:
        if opt == '-h':
            print options
            sys.exit(0)
        if opt == '--debug':
            global debug
            debug = True
        if opt == '--ip':
            global ip_addr
            ip_addr = arg
        if opt == '--threads':
            global threads
            threads = int(arg)
        if opt == '--objects':
            global checkonly
            checkonly = 1
        
        if not opts or '' in opts:
            print options
            sys.exit(0)
      

def main():
    workdir = "/tmp/penzha/object_python/object_check"
    cmd = "mkdir -p %s" % workdir
    result = common.run_cmd(cmd, noErrorHandling=True)
    
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    global ip_addr
    ip_addr = get_host_ip()
    
    print "timestamp - ", timestamp
    global result_filename
    result_filename = "result.{}".format(timestamp)
    
    parse_args()
    print "ip - ", ip_addr
    print "debug - ", debug
    print "threads - ", threads
    
    get_OBJECT_OWNER_HISTORY_from_ls(workdir, timestamp)
    
    
    # the end
    print time.time() - start_time, "seconds"

if __name__ == '__main__':
    main()