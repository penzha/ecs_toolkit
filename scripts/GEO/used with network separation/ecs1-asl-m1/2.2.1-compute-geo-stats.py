#!/usr/bin/python -u

# Usage:
#    ./compute-geo-stats.py vdcIp user password
#
# Description:
# compute geo stats from chunkInfo entries
#
# This script produces the following files:
#     /tmp/compute-geo-stats.log - log output of the script
#     /tmp/compute-geo-stats-lock - makes sure only one script runs at a time, if script
#         crashed and the lock file stayed behind, it has to be removed before resuming
#     /tmp/compute-geo-stats-progress.txt - scanning progress of the DTs
#     /tmp/compute-geo-stats.txt stats computed

import sys
import traceback
import requests
import logging
import logging.handlers
import os.path
import struct
from operator import itemgetter
from xml.dom import minidom
import random
import json
import time

chunkInfoDumpFile = None

logpath=os.getcwd()

if len(sys.argv) > 3:
    thisVdcIp = sys.argv[1]
    user = sys.argv[2]
    password = sys.argv[3]
elif len(sys.argv) > 1:
    chunkInfoDumpFile = sys.argv[1]
else:
    print "Usage:"
    print "    ./compute-geo-stats.py <vdcIp> <user> <password> or\n"
    print "    ./compute-geo-stats.py <vdcIp> <user> <password> <chunkInfoDumpFile>or\n"
    print "    ./compute-geo-stats.py <chunkInfoDumpFile>\n" 
    sys.exit(1)

log = logging.getLogger('compute-geo-stats')
log.setLevel(logging.DEBUG)
handler = logging.handlers.RotatingFileHandler(
              logpath+'/compute-geo-stats.log', maxBytes=0, backupCount=1)
formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(lineno)s - %(message)s')
handler.setFormatter(formatter)
log.addHandler(handler)

log.info("\n==============\n======= start\n==============")

failure_point = -1
failure_probability = -0.1
if len(sys.argv) > 4:
    chunkInfoDumpFile = sys.argv[4]

progress_file = logpath+'/compute-geo-stats-progress.txt'
lock_file = logpath+"/compute-geo-stats-lock"
results_file = logpath+"/compute-geo-stats.txt"
stats_update_file = logpath+"/compute-geo-stats-update.txt"
rpo_update_file = logpath+"/compute-geo-stats-rpo-update.txt"

objControlPort = "4443"  
dtQueryPort = "9101"  # 20060

thisVdcId = ""
thisVdcName = ""

def simulateFailure(point, probability=failure_probability):
    if point == failure_point:
        if probability > random.random():
            raise Exception("simulateFailure " + str(point) + " " + str(probability))

def login(vdcIp):
    try:
        simulateFailure(1)
        r = requests.get("https://" + thisVdcIp + ":4443/login", auth=(user, password), verify=False)
        token = r.headers["x-sds-auth-token"]
        headers = {"X-SDS-AUTH-TOKEN": token, "ACCEPT": "application/xml"}
        return headers
    except:
        log.error("Failed to login")
        log.error(traceback.format_exc())
        raise
    
def logout(vdcIp, headers):
    try:
        simulateFailure(1)
        requests.get("https://" + thisVdcIp + ":4443/logout?force=true", headers=headers, verify=False)
    except:
        log.error("Failed to logout")
        log.error(traceback.format_exc())
        raise

def getVdcIpMap():
    try:
        simulateFailure(2)
        r = requests.get("https://" + thisVdcIp + ":" + objControlPort + "/object/vdcs/vdc/list",
                         headers=headers, verify=False)
        xmldoc = minidom.parseString(r.text)
        itemlist = xmldoc.getElementsByTagName("vdc")
        vdcIpMap = {}
        ipList = {}
        for s in itemlist:
           vdc = s.getElementsByTagName("vdcId")[0].childNodes[0].data        
	   ipList = s.getElementsByTagName("managementEndPoints")[0].childNodes[0].data
           vdcIpMap[vdc] = ipList
            
        return vdcIpMap
    except:
        log.error("Failed to get VDC-IP map")
        log.error(traceback.format_exc())
        raise

def getVdcCosMap():
    try:
        simulateFailure(3)
        r = requests.get("https://" + thisVdcIp + ":" + objControlPort + "/vdc/data-service/vpools/",
                         headers=headers, verify=False)
        xmldoc = minidom.parseString(r.text)
        repGroupList = []
        repGroupsElementList = xmldoc.getElementsByTagName("data_service_vpool")
        for repGroupElement in repGroupsElementList:
            repGroupId = repGroupElement.getElementsByTagName("id")[0].childNodes[0].data
            itemlist = repGroupElement.getElementsByTagName("varrayMappings")
            vdcCosMap = {}
            for s in itemlist:
                vdc = s.getElementsByTagName("name")[0].childNodes[0].data
                cos = s.getElementsByTagName("value")[0].childNodes[0].data
                vdcCosMap[vdc] = cos
            repGroupEntry = (repGroupId, vdcCosMap)
            repGroupList.append(repGroupEntry)
        return repGroupList
    except:
        log.error("Failed to get VDC-COS map")
        log.error(traceback.format_exc())
        raise

def getThisVdcId():
    global thisVdcId
    global thisVdcName
    try:
        r = requests.get("https://" + thisVdcIp + ":" + objControlPort + "/object/vdcs/vdc/local",
                         headers=headers, verify=False)
        xmldoc = minidom.parseString(r.text)
        itemlist = xmldoc.getElementsByTagName("vdc")
        s = itemlist[0]
        thisVdcId = s.getElementsByTagName("vdcId")[0].childNodes[0].data
        thisVdcName = s.getElementsByTagName("name")[0].childNodes[0].data
    except:
        log.error("Failed to get VDC-IP map")
        log.error(traceback.format_exc())
        raise

def getCtTableUrls():
    try:
        url = "http://10.6.38.50:" + dtQueryPort + "/diagnostic/CT/1/?useStyle=raw"
        ctList = []
        r = requests.get(url)
        xmldoc = minidom.parseString(r.text)
        itemlist = xmldoc.getElementsByTagName('entry')
        for entry in itemlist:
            simulateFailure(4)
            tableUrl = entry.getElementsByTagName('table_detail_link')[0].childNodes[0].data + "&useStyle=raw"
            table = entry.getElementsByTagName('id')[0].childNodes[0].data
            # if 'CT_0_' in table:
            ctList.append({'table': table, 'tableUrl': tableUrl})
        ctList = sorted(ctList, key=itemgetter("table"))
        return ctList
    except:
        log.error("Failed to get CT DTs")
        log.error(traceback.format_exc())
        raise

statsGeoPending = {}
statsGeoPending['REPO'] = {}
statsGeoPending['JOURNAL'] = {}
statsGeoPending['BTREE'] = {}
statsGeoCompleted = {}
statsGeoCompleted['REPO'] = {}
statsGeoCompleted['JOURNAL'] = {}
statsGeoCompleted['BTREE'] = {}

def processChunk(chunk):
    if chunk["type"] != 'LOCAL':
        return
    if "repGroup" in chunk and chunk["repGroup"] == "urn:storageos:ReplicationGroupInfo:00000000-0000-0000-0000-000000000000:global":
        return
    if "sealedLength" in chunk:
        length = int(chunk["sealedLength"])
        for zone in chunk["secondaries"]:
            geoTarget = chunk["ownerNode"]+","+chunk["repGroup"]+","+zone["secondary"]
            if zone["replicated"] == 'false':
                if statsGeoPending[chunk["dataType"]].get(geoTarget) != None:
                    statsGeoPending[chunk["dataType"]][geoTarget] += length 
                else:
                    statsGeoPending[chunk["dataType"]][geoTarget] = length
            else:
                if statsGeoCompleted[chunk["dataType"]].get(geoTarget) != None:
                    statsGeoCompleted[chunk["dataType"]][geoTarget] += length 
                else:
                    statsGeoCompleted[chunk["dataType"]][geoTarget] = length 

    elif "lastKnownLength" in chunk:
        for targetZone in chunk["unsealedTargets"]: 
            geoTarget = chunk["ownerNode"]+","+chunk["repGroup"]+","+targetZone["targetZone"]
            replicatedLength = int(targetZone["replicatedLength"])
            pendingBytes = int(chunk["lastKnownLength"]) - replicatedLength
            if pendingBytes >= 0:
                if statsGeoPending[chunk["dataType"]].get(geoTarget) != None:
                    statsGeoPending[chunk["dataType"]][geoTarget] += pendingBytes
                else:
                    statsGeoPending[chunk["dataType"]][geoTarget] = pendingBytes
            if statsGeoCompleted[chunk["dataType"]].get(geoTarget) != None:
                statsGeoCompleted[chunk["dataType"]][geoTarget] += replicatedLength
            else:          
                statsGeoCompleted[chunk["dataType"]][geoTarget] = replicatedLength
    

def writeChunkStats():
    f = open(results_file, 'w')
    dumpChunkStats(f)
    queryChunkStatsGeoPending(f)
    f.close()
    f = open(stats_update_file, 'w')
    resetChunkStatsGeoPending(f)
    for chunkDataType, statsEntry in statsGeoPending.iteritems():
        for key, value in statsEntry.iteritems():
            if (value != 0):
                ownerNode, rgId, zoneId = key.split(",")
                updateUrl = "https://" + ownerNode.strip() + ":4443/stat/update?path=cm/Geo%20Replication%20Statistics/Replication%20Group:" + rgId + "/Replication%20Progress/Zone:" + zoneId + "/Chunk%20Type:" + chunkDataType + "/Outgoing%20Bytes%20Pending&value=" + str(value)
                f.write(updateUrl);
                f.write("\n");
    f.close()

def dumpChunkStats(f):
    f.write("\ngeo pending bytes\n")
    for chunkDataType, statsEntry in statsGeoPending.iteritems():
        f.write(chunkDataType)
        f.write("\n")
        for key, value in statsEntry.iteritems():
            f.write(key)
            f.write(" ")
            f.write(str(value))
            f.write("\n")
    f.write("\n")

def resetChunkStatsGeoPending(f):
    for repGroupEntry in repGroupList:
        rgId = repGroupEntry[0]
        vdcCosMap = repGroupEntry[1]
        for chunkDataType in ["REPO", "JOURNAL", "BTREE"]:
            for vdcId in vdcCosMap:
                if vdcId == thisVdcId:
                    continue
                endPoints = vdcIpMap[thisVdcId].split(",")
                for endPoint in endPoints:
                    # query the current value
                    queryUrl = "https://" + endPoint.strip() + ":4443/stat/update?path=cm/Geo%20Replication%20Statistics/Replication%20Group:" + rgId + "/Replication%20Progress/Zone:" + vdcId + "/Chunk%20Type:" + chunkDataType + "/Outgoing%20Bytes%20Pending&value=" + str(0)
                    f.write(queryUrl);
                    f.write("\n");

def resetChunkStatsRPO():
    f = open(rpo_update_file, 'w')
    ctList = getCtTableUrls()
    for repGroupEntry in repGroupList:
        rgId = repGroupEntry[0]
        vdcCosMap = repGroupEntry[1]
        for ctUrl in ctList:
            ctId = ctUrl['table']
            for vdcId in vdcCosMap:
                if vdcId == thisVdcId:
                    continue
                endPoints = vdcIpMap[thisVdcId].split(",")
                for endPoint in endPoints:
                    # query the current value
                    queryUrl = "https://" + endPoint.strip() + ":4443/stat/update?path=cm/Geo%20Replication%20Statistics/Replication%20Group:" + rgId + "/RPO/Secondary%20Zone:" + vdcId + "/DirectoryId:" + ctId + "/Oldest%20Unreplicated%20Journal%20Data&value=9223372036854775807"
                    f.write(queryUrl);
                    f.write("\n");
                    queryUrl = "https://" + endPoint.strip() + ":4443/stat/update?path=cm/Geo%20Replication%20Statistics/Replication%20Group:" + rgId + "/RPO/DirectoryId:" + ctId + "/Oldest%20Unreplicated%20Journal%20Data&value=9223372036854775807"
                    f.write(queryUrl);
                    f.write("\n");
    f.close()

def queryChunkStatsGeoPending(f):
    f.write("print current stats\n")
    for repGroupEntry in repGroupList:
        rgId = repGroupEntry[0]
        vdcCosMap = repGroupEntry[1]
        for vdcId in vdcCosMap:
            if vdcId == thisVdcId:
                continue
            endPoints = vdcIpMap[thisVdcId].split(",")
            for endPoint in endPoints:
                #headers = login(endPoint.strip())
                # query the current value
                for chunkDataType in ["REPO", "JOURNAL", "BTREE"]:
                    queryUrl = "https://" + endPoint.strip() + ":4443/stat/json/aggregate?path=cm/Geo%20Replication%20Statistics/Replication%20Group:" + rgId + "/Replication%20Progress/Zone:" + vdcId + "/Chunk%20Type:" + chunkDataType
                    f.write(queryUrl);
                    f.write("\n");
                    #statOutput = requests.get(queryUrl, headers=headers, verify=False)
                    statOutput = requests.get(queryUrl, verify=False)
                    if statOutput.status_code != 200:
                        continue
                    # parse the json output
                    '''
                    {
                        "type" : "group",
                        "id" : "Chunk Type:REPO",
                        "description" : "",
                        "timestamp" : 1459171212402,
                        "groups" : [ ],
                        "primitives" : [ {
                        "type" : "counter",
                        "id" : "Outgoing Bytes Pending.TOTAL",
                        "description" : "Amount of data yet to be replicated to this secondary zone.",
                        "timestamp" : 1459170517712,
                        "aggregationTypes" : [ "TOTAL" ],
                        "counter" : 1448061636
                        } ]
                    }
                    '''
                    parsedStatOutput = json.loads(statOutput.text)
                    for primitives in parsedStatOutput["primitives"]:
                        f.write(str(primitives["counter"]))
                    f.write("\n");
                #logout(endPoint.strip(), headers)

def dequote(s):
    """
    If a string has single or double quotes around it, remove them.
    Make sure the pair of quotes match.
    If a matching pair of quotes is not found, return the string unchanged.
    """
    if (s[0] == s[-1]) and s.startswith(("'", '"')):
        return s[1:-1]
    return s

def parseChunkInfo(chunkInfoIter, ownerNode):
    for line in chunkInfoIter:
        line = line.strip()
        if line.find("schemaType CHUNK chunkId") != -1:
            chunk = {}
            chunk["status"] = "UNKNOWN"
            chunk["ownerNode"] = ownerNode
            chunk["id"] = line.split(" ")[3]
            chunk["secondaries"] = []
            chunk["unsealedTargets"] = []
            lastKnownLength = 0
            line = next(chunkInfoIter)
            if line.startswith("status:"):
                chunk["status"] = line.split(" ")[1]
        # in CT table dump CHUNK entries come first, so it is ok to break out here
        elif line.startswith("schemaType CM_TASK"):
            break
        elif line.startswith("dataType:"):
            chunk["dataType"] = line.split(" ")[1]
        elif line.startswith("type:"):
            chunk["type"] = line.split(" ")[1]
        elif line.startswith("repGroup:"):
            chunk["repGroup"] = dequote(line.split(" ")[1])
        elif line.startswith("primary:"):
            chunk["primary"] = line.split(" ")[1]
        elif line.startswith("secondaries {"):
            secondary = {}
            line = next(chunkInfoIter).strip()
            if line.startswith("secondary:") >= 0: 
                secondary["secondary"] = dequote(line.split(" ")[1])
            line = next(chunkInfoIter).strip()
            if line.startswith("replicated:") >= 0: 
                secondary["replicated"] = line.split(" ")[1]
            chunk["secondaries"].append(secondary)
        elif line.startswith("sealedLength:"):
            chunk["sealedLength"] = int(line.split(" ")[1])
        elif line.startswith("lastKnownLength:"):
            lastKnownLength = int(line.split(" ")[1])
            chunk["lastKnownLength"] = lastKnownLength
        # for unsealed geo chunk replication, chunk may not be sealed but some ranges are replicated
        # geoProgress {
        #     targetZone: "urn:storageos:VirtualDataCenterData:c4774cb9-d5d4-413a-9f21-526532cb824c"
        #     progress {
        #         version: 0
        #         ranges {
        #            startOffset: 0
        #            endOffset: 50331168
        #            status: GEO_SHIPPING_STATUS_SUCCESS
        #         }
        #     }
        # }
        elif line.startswith("geoProgress {"):
            targetZone = {}
            startOffset = 0
            endOffset = 0
            replicatedLength = 0
            line = next(chunkInfoIter).strip()
            if line.startswith("targetZone:"): 
                targetZone["targetZone"] = dequote(line.split(" ")[1])
                targetZone["replicatedLength"] = 0        
            line = next(chunkInfoIter).strip()
            # TODO: will there be multiple progress blocks
            if line.startswith("progress {"):
                next(chunkInfoIter) #skip verison:
                line = next(chunkInfoIter).strip()
                if line.startswith("ranges {"):
                    line = next(chunkInfoIter).strip()
                    if line.startswith("startOffset:"):
                        startOffset = int(line.split(" ")[1])
                    line = next(chunkInfoIter).strip()
                    if line.startswith("endOffset:"):
                        endOffset = int(line.split(" ")[1])
                    line = next(chunkInfoIter).strip()
                    if line.startswith("status:"):
                        geoStatus = line.split(" ")[1] 
                    if geoStatus == "GEO_SHIPPING_STATUS_SUCCESS":
                        replicatedLength = endOffset - startOffset
                        targetZone["replicatedLength"] += replicatedLength        

            chunk["unsealedTargets"].append(targetZone)
        elif line == "":
            processChunk(chunk)
            chunk = {}
            secondary = {}
        elif line.startswith("Get more:"):
            url = line.split("\"")[1]

# read CT table line by line
# follow "Get more" link at the bottom of each page
def scanCt(ctUrl, tok):
    simulateFailure(5)
    if tok == None:
        url = ctUrl
    else:
        url = ctUrl + "&token=" + tok
    # url = url + "&maxkeys=50"  ##################### TEMP
    ctUrlTokens = ctUrl.split("/")
    ct = ctUrlTokens[3]
    ownerNode = ctUrlTokens[2].split(":")[0].strip()

    try:
        while (url != None):
            log.debug("attempt page: " + url)
            simulateFailure(6)
            t = requests.get(url)
            url = None
            chunkInfoIter = iter(t.text.splitlines())
            parseChunkInfo(chunkInfoIter, ownerNode)
            # write progress
            p = open(progress_file, 'w')
            if url == None:
                p.write("scan," + ct + "\n")  # CT done
            else:
                token = url.split("token=")[1]
                p.write("scan," + ct + "," + token + "\n")  # next CT page
            p.close()
    except:
        log.error("Failed to scan : " + str(url))
        log.error(traceback.format_exc())
        raise

# main
processing_ended = True
if os.path.isfile(lock_file):
    log.warn("the script is already running, exiting")
    sys.exit(1)
else:
    log.info("creating lock file " + lock_file)
    p = open(lock_file, 'w')
    p.close()

try:

    log.info("attempt to login" + thisVdcIp)
    headers = login(thisVdcIp)
    log.info("login success")
    
    getThisVdcId()
    if thisVdcId == None:
        log.error("this VDC ID not found")
        sys.exit(3)
    log.info("this vdcId: " + thisVdcId)
    log.info("this vdc name: " + thisVdcName)

    log.info("retrieve vdc IDs and IPs")
    vdcIpMap = getVdcIpMap()
    if len(vdcIpMap) == 0:
        log.error("Did not find any VDCs and IPs")
        sys.exit(2)
    else:
        log.info("Retrieved following VDCs-IPs: " + str(vdcIpMap))
    
    log.info("retrieve vdc IDs and COSs")
    repGroupList = getVdcCosMap()
    if len(repGroupList) == 0:
        log.error("Did not find any VDCs and COSs")
        sys.exit(4)
    else:
        log.info("Retrieved following VDCs-COSs: " + str(repGroupList))

    if chunkInfoDumpFile != None:
        ownerNode = "localhost"
        cf = open(chunkInfoDumpFile, 'r')
        chunkInfoIter = iter(cf.readline, "")
        parseChunkInfo(chunkInfoIter, ownerNode)
        writeChunkStats()
        resetChunkStatsRPO()
        logout(thisVdcId, headers)
        sys.exit(0)

    # everything seems in order
    status = None
    token = None
    if os.path.isfile(progress_file): 
        p = open(progress_file, 'r')
        line = p.readline().strip()
        if line == "scan-done":
            status = 'SCAN_DONE'
        else:
            arr = line.split(",")
            table = arr[1]
            if len(arr) > 2:
                token = arr[2]
            status = 'SCAN_INCOMPLETE'
    else:
        status = 'SCAN_NOT_STARTED'
    
    if status != 'SCAN_DONE':
        log.info("retrieve all CT DT URLs")
        ctList = getCtTableUrls()
        if len(ctList) > 0:
            log.info("got " + str(len(ctList)) + " CT DTs")
            
        try:
            ctCount = len(ctList)
            x = 0
            if status == 'SCAN_INCOMPLETE':
                # find table to continue scanning
                for x in range(0, ctCount):
                    if table != ctList[x]["table"]:
                        log.info('skipping ' + ctList[x]["table"])
                    else:
                        break
                if token == None:  # if token is None, then this table was done
                    log.info('skipping ' + ctList[x]["table"])
                    x += 1

            for y in range(x, ctCount):
                log.info("scan CT: " + ctList[y]["tableUrl"])
                scanCt(ctList[y]["tableUrl"], token)
        except:
            log.error(traceback.format_exc())

        status = 'SCAN_DONE'
        p = open(progress_file, 'w')
        p.write("scan-done\n")
        p.close()
    else:
        log.info("scanning was completed previously")
    processing_ended = True
except SystemExit as e:
    if e.code != 0:
        log.error(traceback.format_exc())
        processing_ended = False
    else:
        processing_ended = True
finally:
    logout(thisVdcId, headers)
    log.info("removing lock file " + lock_file)
    os.remove(lock_file)
    if processing_ended:
        os.remove(progress_file)
        writeChunkStats()
        log.info('==== DONE ====')

