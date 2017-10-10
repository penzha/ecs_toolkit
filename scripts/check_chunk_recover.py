#!/usr/bin/env python
import os
import sys
import urllib2
import datetime
import time
import subprocess
import threading
from random import randint
MULTI_THREADING_NUM = 20
node_ips = ["10.249.246.68", "10.249.246.68", "10.249.246.68", "10.249.246.68"]
CHUNKID_SSLOCATION_DICT = {}


class SsLocation:
    def __init__(self, node, partition, blockBin):
        self.node = node
        self.partition = partition
        self.blockBin = blockBin



def get_chunk_info(varray, chunk, level):
    node_ip = randomize_datanode()
    if level == '1':
        urlName = "".join(["http://", node_ip, ":9101/diagnostic/", str(1), \
                            "/ShowChunkInfo?cos=", varray,"&chunkid=", chunk])
        try:
            response = urllib2.urlopen(urlName)
        except:
            return None
    else:
        urlName = "".join(["http://", node_ip, ":9101/diagnostic/", str(2), \
                        "/ShowChunkInfo?cos=", varray,"&chunkid=", chunk])
        try:
            response = urllib2.urlopwen(urlName)
        except:
            return None
    if response is not None:
        return response.read()
    else:
        return None


def trigger_send_chunk(varray, level, chunkId):
    node_ip = randomize_datanode()
    print "trigger chunkInfoSend to: " + node_ip + " for chunk " + chunkId
    urlName = "".join(["http://", node_ip, ":9101/cm/recover/addGeoInfoSendTask/", \
                     varray, "/", level, "/", chunkId])
    return_code = subprocess.call(["curl", "-X", "PUT", urlName])
    print "return code: {} for chunk {}".format(return_code, chunkId)
    return return_code


def trigger_remove_empty_secondary(varray, level, chunkId):
    node_ip = randomize_datanode()
    print "trigger remove empty secondary to: " + node_ip + " for chunk " + chunkId
    urlName = "".join(["http://", node_ip, ":9101/cm/unsealedgeo/removeSecondary/", \
                     varray, "/", level, "/", chunkId, "/%20"])
    return_code = subprocess.call(["curl", "-X", "PUT", urlName])
    print "return code: {} for chunk {}".format(return_code, chunkId)
    return return_code


def trigger_set_replicated(varray, level, chunkId, secondary):
    node_ip = randomize_datanode()
    print "trigger remove secondary to: " + node_ip + " for chunk " + chunkId
    urlName = "".join(["http://", node_ip, ":9101/cm/unsealedgeo/updateSecondary/", \
                     varray, "/", level, "/", chunkId, "/", secondary, "/true"])
    return_code = subprocess.call(["curl", "-X", "PUT", urlName])
    print "return code: {} for chunk {}".format(return_code, chunkId)
    return return_code

def trigger_set_capacity(varray, level, chunkId):
    node_ip = randomize_datanode()
    print "trigger set capacity to: " + node_ip + " for chunk " + chunkId
    urlName = "".join(["http://", node_ip, ":9101/cm/recover/setChunkCapacity/", \
                     varray, "/", level, "/", chunkId, "/134217728"])
    return_code = subprocess.call(["curl", "-X", "PUT", urlName])
    print "return code: {} for chunk {}".format(return_code, chunkId)
    return return_code

def trigger_set_sealed(varray, level, chunkId):
    node_ip = randomize_datanode()
    print "trigger setSealed to: " + node_ip + " for chunk " + chunkId
    urlName = "".join(["http://", node_ip, ":9101/cm/recover/setChunkStatus/", \
                     varray, "/", level, "/", chunkId,"/SEALED"])
    return_code = subprocess.call(["curl", "-X", "PUT", urlName])
    print "return code: {} for chunk {}".format(return_code, chunkId)
    return return_code

def trigger_recovery(varray, level, chunkId,index):
    node_ip = randomize_datanode()
    print "trigger recovery to: " + node_ip + " for chunk " + chunkId
    urlName = "".join(["http://", node_ip, ":9101/cm/recover/", \
                     varray, "/", level, "/", chunkId,"/", str(index), "/BAD"])
    return_code = subprocess.call(["curl", "-X", "PUT", urlName])
    #print "return code: {} for chunk {}".format(return_code, chunkId)
    return return_code


def runCmd(cmd, prefix = ""):
    debug_print(cmd)
    f=os.popen(cmd)
    for i in f.readlines():
        debug_print("%s: %s" % (prefix, i))


def randomize_datanode():
    time.sleep(0.01)
    i = randint(0, len(node_ips) - 1)
    data_node = node_ips[i]
    return data_node


def check_chunk(chunk_info, chunkId):
    line = ""
    chunk = []
    for c in chunk_info:
        if c == '\n':
            chunk.append(line.strip())
            line = ""
        else:
             line = line + c
    ssLocationList = CHUNKID_SSLOCATION_DICT[chunkId]
    start = False
    segment_cnt = -1
    ssId = ""
    partitionId = ""
    filename = ""
    segments_index = []
    for string in chunk:
        if "segments {" in string:
            start = True
            segment_cnt = segment_cnt + 1
        if start:
            if "ssId:" in string:
                words = string.split(" ")
                ssId = words[1].strip('\"')
            if "partitionId:" in string:
                words = string.split(" ")
                partitionId = words[1].strip('\"')
            if "filename:" in string:
                words = string.split(" ")
                filename = words[1].strip('\"')
            if "sequence:" in string:
                start = False
                for ssLocation in ssLocationList:
                    if ssLocation.node == ssId and ssLocation.partition == partitionId and ssLocation.blockBin == filename:
                        segments_index.append(segment_cnt)
                ssId = ""
                partitionId = ""
                filename = ""
    return segments_index


def check(chunkId, cos, level, targetfile):
    chunk_info = get_chunk_info(cos, chunkId, level)
    if chunk_info is not None:
        segments_index = check_chunk(chunk_info, chunkId)
        if len(segments_index) > 0:
            if len(segments_index) > 4:
                targetfile.write('chunk with more than 4 bad segments: ' + chunkId + '\n')
            else:
                for index in segments_index:
                    return_code = trigger_recovery(cos, level, chunkId, index)
                    if return_code != '0':
                        targetfile.write('chunk trigger recover failed: ' + chunkId + '\n')
        else:
            targetfile.write('chunk with no bad segments: ' + chunkId + '\n')
        return True
    else:
        return False


def debug_print(msg):
    print "%s: %s" % (datetime.datetime.now(), msg)


def split_chunks(l, n):
    n = max(1, n)
    return (l[i:i+n] for i in xrange(0, len(l), n))


def check_with_retry(chunks, cos, targetfile):
    for i in range(0, 3):
        with open(targetfile, 'a') as _file:
            chunks[:] = [chunk for chunk in chunks if not check(chunk, cos, str(1), _file)]
        print "chunks remaining: {}, {} retries".format(str(len(chunks)), str(i))
    with open(targetfile, 'a') as file:
            file.write('======================CHUNKS NOT FOUND====================' + '\n')
            for entry in chunks:
                file.write('chunks not found:' + entry + '\n')


if __name__ == '__main__':
    user_args = sys.argv[1:]
    if len(user_args) == 3:
        chunkfile, cos, targetfile = user_args
        with open(chunkfile) as f:
            lines = f.read().splitlines()
            for line in lines:
                words = line.split(" ")
                chunkId = words[0]
                ssLocation = SsLocation(words[1], words[2], words[3])
                if chunkId in CHUNKID_SSLOCATION_DICT:
                    CHUNKID_SSLOCATION_DICT[chunkId].append(ssLocation)
                else:
                    CHUNKID_SSLOCATION_DICT[chunkId] = [ssLocation]
            chunks = list(CHUNKID_SSLOCATION_DICT.keys())
            print "{} chunks to check recovery".format(str(len(chunks)))
            chunks_divided = len(chunks) / MULTI_THREADING_NUM
        chunks_list = split_chunks(chunks, chunks_divided)
        i = 0
        for entry in chunks_list:
            t = threading.Thread(name='check_thread_' + str(i), target=check_with_retry, args=(entry, cos, targetfile))
            t.start()
            print "Thread {} started for {} chunks".format(str(i), str(len(entry)))
            i += 1


