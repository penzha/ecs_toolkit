#!/usr/bin/env python
# __CR__
# Copyright (c) 2008-2016 EMC Corporation
# All Rights Reserved
#
# This software contains the intellectual property of EMC Corporation
# or is licensed to EMC Corporation from third parties.  Use of this
# software and the intellectual property contained therein is expressly
# limited to the terms and conditions of the License Agreement under which
# it is provided by or on behalf of EMC.
# __CR__

"""
Author: Atmos/ECS L3 team
Primary Author: Artur Bacu (ECS version)
Purpose: object metadata query tool, similar to Atmos mauiobjbrowser
Usage: python %prog --help
Version: 0.6.2
Prerequisite : None
Input/Output restriction: Input is object ID or filename
Changelog:
    0.1.0 [Dec 8, 2014] - Proof of concept
    0.2.0 [Mar 5, 2015] - First release
    0.3.0 [Jun 12, 2015]
          - Added support for Data Services for Arrays (ViPR and ECS)
          - Added support for running inside containers
          - Improved get_nodes() to get only nodes with status 2
          - Added more human-readable MD times, improved time print method
          - Added timeout option for DT query (default 1 second)
          - Caught socket.timeout exception for Python 2.7
          - Clarified in print class: keypool-hash-id is also parent of object
          - Added decoding for version info to Printer class
          - Updated ECS versions detected, tested ECS 1.2
          - Added count for number of copies and segments within copy (like
                Atmos "Number of replicas" and "Total pieces")
          - Added support for counting DT table levels and querying all levels
                (based on DT query index page). Only first hit is used.
          - headSysMd entries are printed more clearly
          - Added option to list all sequences. By default will aggregate sequences
                like in DT query's showlatestinfo. Overwrites sysMd, headSysMd,
                userMd individual entries (append if not exist), but only appends
                dataIndices and reposUMRLocations.
          - Fixed bug so can get chunkIds from multiple sources in same segmentUMR
    0.4.0 [Aug 20, 2015]
          - Fixed namespace query bugs that prevented namespace OB lookups from working
          - Support space and Unicode characters in namespace object path
                (using HTTP %xx escapes). Use quotes if path has spaces.
          - Redirect namespace query to OB query for output consistency
          - Added option to print XML output (non-formatted print)
          - Added option to ignore ECS version check (-V)
          - Added option to query chunk ID directly, without object ID, either by single ID or
                comma separated list
          - Object ID lookup now accepts comma separated list
          - Added batch OID (-I) and chunk ID (-C) file support (like -f in mauiobjbrowser)
          - Performance improvement to clean_http_result function for large key/value pairs
          - Performance improvement through multiprocessing pool for chunk and object DT queries
          - ECS Community Edition is detected as an environment to run in
          - CAS: Convert WT to human readable time
          - CAS: Have more descriptive names for headers (were all OT, PR, RC, RD, etc)
          - CAS: Put in workaround for Jira STORAGE-7651 (blob IDs stored in DT key, not value)
    0.5.0 [July 19, 2016]
          - Fixed bugs with debug message printing in get_http() and table_id_query()
          - Added retry for get_http() when timeout happens
          - Increased default URL open timeout to 5 sec to avoid the new retry in get_http(), for most cases
          - Fixed bug with choose_node_dt() and timeout parameter
          - Added "sudo -i" to detect_env() to support detecting ECS 2.2.x (is backwards compatible to at least 2.1.x)
          - Added ECS 2.2.x to list of supported ECS versions (only above "sudo -i" addition was needed)
          - Simplified version check system (no more code names, just versions and if supported or not)
          - Fixed issue with pipe to head/tail generating IOError broken pipe exception
          - Modifed get_nodes() to handle query for private or public IPs, due to
                issue found in Jira ET-8 where query with private fails
    0.5.1 [Nov 9, 2016] OS-1322
          - Added ECS 3.0 to list of supported ECS versions (no relevant changes found against this tool)
    0.6.0 [Dec 22, 2016] OS-1351
          - Fixed ECSEE-2261. If there is more than one DT query URL to lookup OB entries, use the one
                with most OID/schemaType results. If there's a duplicate, just use one of the duplicates.
          - Added support for parsing INDEX type OB entries, to account for Index Compaction, see
                https://asdwiki.isus.emc.com:8443/display/ECS/Index+Compaction+in+v2
                Note: UPDATE key/value pairs overwrite INDEX if default aggregration method is used
          - Improved debugging output
          - Disabled ECS version check for now
    0.6.1 [Mar 27, 2017] OS-1463
          - Fixed issue reported in ECSEE-3408. Journal chunks were not supported, but initial support
                was added with updates to print_ct() method.
          - Fixed hang when OID or chunk ID files have empty lines in file
          - Fixed issue with chunk ID file's print_ct() output being incorrect (extra chunk info
                for chunk that shouldn't have it)
          - Tested Btree chunks as well, fixed issue with duplicate dtTypes key not showing, updated
                ParseCTRegex.str_to_dict()
          - Changed SIGINT/KeyboardInterrupt handling so Ctrl+C in multiprocessing portions handle this
                scenario more intuitively
     0.6.2 [Jun 6, 2017]
          - Added additional authorship info

Implementation Notes:
    - Not everything in mauiobjbrowser will apply to ECS
"""

#Ignore import error as some are version dependent
#pylint: disable=import-error
#Ignore unused arguments in NestedParser class, this is specific implementation with those methods required
#pylint: disable=unused-argument
#Ignore too many lines, goal is to have portable tool that can copy/paste in one step
#pylint: disable=too-many-lines


import sys
import errno
import os
import urllib
import urllib2
import re
import optparse
import json
import pprint
import copy
import time
import subprocess
import signal
from socket import error as socket_error
from socket import timeout as socket_timeout
from random import randint
import multiprocessing as mp
from itertools import repeat
from itertools import izip
try:
    import xml.etree.cElementTree as etree
except ImportError:
    import elementtree.ElementTree as etree
from xml.dom import minidom
import pdb

#Non-standard imports
try:
    import rpyc
    RPYC_SUPPORT = True
except ImportError:
    RPYC_SUPPORT = False

#General constants
INDEX_URL = 'http://{0}:9101/index'
DIAGNOSTIC_URL = 'http://{0}:9101/diagnostic'
OB_UPDATE_OID_QUERY_URL = DIAGNOSTIC_URL + \
    '/OB/{1}/DumpAllKeys/OBJECT_TABLE_KEY?type=UPDATE&objectId={2}'
OB_INDEX_OID_QUERY_URL = DIAGNOSTIC_URL + \
    '/OB/{1}/DumpAllKeys/OBJECT_TABLE_KEY?type=INDEX&objectId={2}'
OB_NAME_QUERY_URL = DIAGNOSTIC_URL + \
    '/object/showinfo?poolname={1}&objectname={2}'
CT_QUERY_URL = DIAGNOSTIC_URL + \
    '/CT/{1}/DumpAllKeys/CHUNK?chunkId={2}'
SHOWVALUE_GPB = '&showvalue=gpb'
#The following doesn't work without knowing parent. Probably not needed as
#    OB_NAME_QUERY_URL works.
LS_QUERY_URL = DIAGNOSTIC_URL + \
    '/LS/0/DumpAllKeys/LIST_ENTRY?type=KEYPOOL&parent={1}&child={2}'
VERSION_QUERY_URL = 'http://{0}:9101/ShowVersionInfo/{1}'
#Ignore list for keys not to print
IGNORE = ['count_segmentUMR', 'count_dataRange', 'count_rangeInfo',
          'count_reposUMRLocations', 'count_dataIndices', 'count_segment',
          'count_copies', 'count_segments', 'count_ssLocation',
          'count_segmentLocation', 'count_progress', 'count_ranges',
          'count_geoProgress', 'count_secondaries', 'count_ecCodeScheme',
          'count_headSysMd', 'count_compressInfo', 'count_sysMd']
#Multiprocessing limit (threads or processes)
MP_LIM = 4
#Num of objects or chunks to process at once
OBJ_CHUNK_LIM = 24

#Return status
SUCCESS = 0
# General failure
FAILURE = 1
# OID not found in DT query
NOT_FOUND = 2
# DT table not supported
NOT_SUPPORTED = 3
# Timeout in URL open
TIMEOUT = 4


#Allow multiprocessing in pdb
class ForkedPdb(pdb.Pdb):
    """
    A Pdb subclass that may be used from a forked multiprocessing child
    Usage: ForkedPdb().set_trace() on line to set breakpoint
    This is from http://stackoverflow.com/questions/4716533/how-to-attach-debugger-to-a-python-subproccess
    """
    def interaction(self, *args, **kwargs):
        _stdin = sys.stdin
        try:
            sys.stdin = file('/dev/stdin')
            pdb.Pdb.interaction(self, *args, **kwargs)
        finally:
            sys.stdin = _stdin


def py_ver_high():
    """
    Check if Python version is 2.7 or above (return True), or 2.6 and below (return False)
    Input: None
    Output: True if 2.7 or above, False if lower than 2.7
    """

    return bool(sys.hexversion >= 0x02070000)


def big_exec_cmd(cmd, flag=False):
    """
    Execute commands with large output (goes to temporary file). common module
    has exec_cmd function but uses PIPE, which has 64k character limit. See
    http://thraxil.org/users/anders/posts/2008/03/13/Subprocess-Hanging-PIPE-is-your-enemy/
    - `cmd`: the command to be run in the form of a list
    - `flag`: boolean value to enable execution by shell
    """
    ret = 1
    out = ""
    err = ""

    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=flag)
        out, err = proc.communicate()
        ret = proc.returncode
    except OSError, (errnum, msg):
        msg = "Error running command %s : %s" % (cmd, msg)
        return (errnum, "", msg)

    return (ret, out, err)


def clean_http_result(http_response):
    """
    Take HTTP response and remove beginning headers (<script> to <pre>) and
        footer (</pre>) and trailing whitespace
    Input: HTTP response (string)
    Output: HTTP response (string) with header/footer stripped (JS info type headers, not HTTP)
    """
    re_head_new = re.compile(r'^.*<pre>(.*)', re.S|re.M)
    re_foot_new = re.compile(r'^(.*)</pre>$', re.S|re.M)
    re_head_old = re.compile(r'(?ms)^.*<pre>(.*)')
    re_foot_old = re.compile(r'(?ms)^(.*)</pre>$')

    #If Python 2.7 or above
    if py_ver_high() is True:
        #Remove header, if it's there
        result = re_head_new.sub(r'\1', http_response)
        #Remove footer, if it's there
        result = re_foot_new.sub(r'\1', result.strip())
        #Remove any link in chunkId (if using namespace DT query)
    #If Python 2.6 or below
    else:
        #Remove header, if it's there
        result = re_head_old.sub(r'\1', http_response)
        #Remove footer, if it's there
        result = re_foot_old.sub(r'\1', result.strip())
    #Remove any link in chunkId (if using namespace DT query)
    if "chunkId: " in result:
        result = re.sub(r'chunkId: .*>(.*)<.*', r'chunkId: \1', result)
    result_clean = result.strip()

    return result_clean


def get_http(url, debug, retry=False, time_out=5):
    """
    Retrieve HTTP response from a URL
    Input: URL, timeout for URL open (optional)
    Output: HTTP response as string, return code (if URL opened or raised exception)
    See http://www.voidspace.org.uk/python/articles/urllib2.shtml for more info on urllib2
    """
    ret_code = SUCCESS

    try:
        result = urllib2.urlopen(url, timeout=time_out).read()
    except urllib2.URLError, exp:
        msg = "Exception during URL open for {0}:\n\t" + \
            "Error: {1}\nCheck host for DT query."
        if debug:
            try:
                print msg.format(url, exp.reason)
            except AttributeError:
                print msg.format(url, exp)
        result = None
        ret_code = FAILURE
    except socket_timeout as exp:
        if retry:
            time_out += 5
            result, ret_code = get_http(url, debug, False, time_out)
        else:
            msg = "Timeout during URL open for {0}:\n\t" + \
                "Error: {1}\nCheck host for DT query."
            if debug:
                try:
                    print msg.format(url, exp.reason)
                except AttributeError:
                    print msg.format(url, exp)
            result = None
            ret_code = TIMEOUT

    return result, ret_code


def get_ecs_version_code():
    """
    Get ECS version code from /etc/issue, outside container
    Input: none
    Output: ECS version code
    """
    version = None
    versioncode = None
    ver_file = '/etc/issue'
    ver_reg = re.compile(r".*ECS (.*) -.*")

    try:
        vftemp = open(ver_file, 'r')
        version = vftemp.read()
        vftemp.close()
    except IOError:
        print 'ERROR: Failed to open/read %s.' % ver_file
        print 'Run on ECS node, not in container'
    if version and ver_reg.search(version):
        version = ver_reg.search(version).group(1)
        versioncode = version.split('-')[0]

    return versioncode


def get_ecs_supported(ecs_version_code):
    """
    Check if ECS version code is supported for this tool
    Input: ECS version code
    Output: ECS supported or not
    """
    all_version = {
        # See https://asdwiki.isus.emc.com:8443/display/ECS/History+of+all+Released+Codes and
        # http://xdoctor.isus.emc.com/extra?product=ecs&link_id=released_versions and
        # See http://xdoctor.isus.emc.com/extra?product=ecs&link_id=version_overview for different customer versions
        'SUPPORT': 'Supported version',
        'NONSUPPORT': 'Non-supported version'
    }
    #ViPR 2.0, ViPR 2.1, ECS 1.2/2.0, ECS 1.3/2.1, ECS 1.4/2.2, and ECS 3.0
    #Note: for slashes above, that's OS version/ECS version
    supported = ['2.0', '2.1', '1.2', '1.3', '1.4', '2.2', '3.0']

    if ecs_version_code and ecs_version_code[0:3] in supported:
        ecssupported = all_version['SUPPORT']
    else:
        ecssupported = all_version['NONSUPPORT']

    return ecssupported


def detect_env(debug):
    """
    Detect if being run in ECS container, ECS outstide container, or
        ViPR Data Services for Arrays
    Input: None
    Output: environment script is run in
    """
    systool = "/etc/systool"
    #Possible values are: "in_cont" for ECS inside container,
    #"out_cont" for ECS outside container, "array" for ViPR DS for arrays,
    #or "out_ce" for Community Edition outside container
    detected = ""
    version = ""
    versioncode = ""

    if os.path.isfile(systool):
        #Either is ECS in container or ViPR DS for arrays
        (ret, out, err) = big_exec_cmd([systool, "--get-default"])
        if ret != 0:
            print "ERROR: %s had errror: %s" % (systool, err)
            return FAILURE, detected, version, versioncode
        else:
            if "Warning: Fabric deployment" in err:
                detected = "in_cont"
            else:
                detected = "array"
            version = re.search(r"vipr-(.*)", out).group(1)
            versioncode = ".".join(version.split(".")[0:2])
    else:
        #Is outside container, ECS, Community Edition or invalid
        #Check if docker images has ECS
        (ret, out, err) = big_exec_cmd(["sudo", "-i", "docker", "images"])
        if ret == 0 and ('emcvipr/object' in out or 'emccorp/ecs-software' in out):
            versioncode = get_ecs_version_code()
            if versioncode:
                detected = "out_cont"
            else:
                detected = "out_ce"

    supported = get_ecs_supported(versioncode)

    if debug:
        print "DEBUG: ECS version is %s, which is '%s', detected environment is '%s'" % \
              (versioncode, supported, "Outside Container" if detected == "out_cont" else "Outside Community Edition")

    return SUCCESS, detected, supported, versioncode


def get_rack():
    """
    Get rack info from rackServiceMgr service.
        Borrowed from /usr/local/xdoctor/lib/xdoctor/rack.py
    Input: none
    Output: JSON document loaded in dictionary
    """
    rack = {}
    rpyc_host = '192.168.219.254'
    rpyc_port = 21902

    try:
        connection = rpyc.connect(rpyc_host, rpyc_port)
        rack = json.loads(connection.root.getNodes())
    except socket_error as serr:
        print "ERROR: connection error to {0}:{1}".format(rpyc_host, rpyc_port)
        print serr

    return rack


def get_nodes(rack, query_type):
    """
    From rack info output get_rack(), validate and return list of nodes
    Input: dictionary of rack info, type of node IP (private or public)
    Output: list of valid nodes in rack
    """
    nodes = []

    if rack:
        for node in rack.keys():
            if rack[node]['status'] == 2:
                #Get private IPs
                if query_type == 'private':
                    nodes.append(node)
                #Get public IPs
                else:
                    nodes.append(rack[node]['public']['ip'])

    return nodes


def select_random(data):
    """
    Randomly select an element from a list but remove that element from the list
    Input: any list
    Output: a random element, consuming that element and shrinking list
    """

    if data != []:
        index = randint(0, len(data) - 1)
        element = data[index]
        data[index] = data[-1]
        del data[-1]
        return element
    else:
        return data


def choose_node_dt(host, detected_env, timeout, debug):
    """
    Choose a node to do DT query against
    Input: Host to use for query (from CLI options), detected environment, timeout value, debug output
    Output: Node IP that can be used to do DT query against
    """
    node_ip = None
    nodes = []

    #Validate if entered host can do DT query
    if host:
        _, ret_code = get_http(DIAGNOSTIC_URL.format(host), debug, False, timeout)
        if ret_code == SUCCESS:
            node_ip = host
        else:
            print "ERROR: %s is not valid for DT query" % host
    #Do DT query against local node IP. If successful, use localhost.
    else:
        _, ret_code = get_http(DIAGNOSTIC_URL.format('127.0.0.1'), debug, False, timeout)
        if ret_code == SUCCESS:
            node_ip = '127.0.0.1'
        else:
            if detected_env in ("in_cont", "array") or not RPYC_SUPPORT:
                print "ERROR: Failed to use localhost for DT query and " + \
                        "cannot use auto-detection. Try to specify " + \
                        "node with -d option."
            else:
                #Get rack info and list of node IPs (private)
                rack = get_rack()
                nodes = get_nodes(rack, 'private')
                #Select random nodes and remove that node from the list
                if nodes:
                    found1 = select_random(nodes)
                    #Test if random node is valid for DT query
                    _, ret_code = get_http(DIAGNOSTIC_URL.format(found1), debug, False, timeout)
                    if ret_code == SUCCESS:
                        node_ip = found1
                    #Else do one more random test before exiting, this time with public IPs
                    else:
                        nodes = get_nodes(rack, 'public')
                        found2 = select_random(nodes)
                        _, ret_code = get_http(DIAGNOSTIC_URL.format(found2), debug, False, timeout)
                        if ret_code == SUCCESS:
                            node_ip = found2
                        else:
                            print "Error: failed to choose node for DT query, " + \
                                    "check {0} and {1}. Try to specify node with -d option.".format(found1, found2)
                            node_ip = None

    return node_ip


def dict_to_xml(oid, ob_update_obj, chunk_ids, ct_objs):
    """
    Take IDs and dicts and print them in XML
    Input: object ID, object dict, chunk ID, chunk dict
    Output: print XML output
    """

    try:
        #Root tag setup
        objroottag = "ecs"
        objroot = etree.Element(objroottag)

        #Convert OB metadata dictionary
        mdroottag = "object"
        mdroot = etree.Element(mdroottag)
        if oid:
            mdroot.set('oid', oid)
            dict_to_xml_recurse(mdroot, ob_update_obj.segment_dict)
        objroot.append(mdroot)

        #Iterate through Chunk IDs and convert those dictionaries
        if chunk_ids:
            for num, c_id in enumerate(chunk_ids):
                chunkroottag = "chunk" + str(num + 1)
                chunkroot = etree.Element(chunkroottag)
                chunkroot.set('chunk_id', c_id)
                dict_to_xml_recurse(chunkroot, ct_objs[num].copies_dict)
                objroot.append(chunkroot)

        #Pretty print XML
        xmlstr = minidom.parseString(etree.tostring(objroot)).toprettyxml(indent="   ")
        print xmlstr
    except StandardError, err:
        print "ERROR: %s" % err
        return FAILURE

    return SUCCESS


def dict_to_xml_recurse(parent, dictitem):
    """
    Recursive function to generate XML doc from dictionary
    Based on https://code.activestate.com/recipes/573463-converting-xml-to-dictionary-and-back/
    Input: dictionary object
    Output: ElementTree XML object
    """
    assert not isinstance(dictitem, list)

    if isinstance(dictitem, dict):
        for (tag, child) in dictitem.iteritems():
            if isinstance(child, str):
                elem = etree.Element(tag)
                parent.append(elem)
                elem.text = child
            elif isinstance(child, list):
                #Iterate through list and convert
                for item in child:
                    elem = etree.Element(tag)
                    parent.append(elem)
                    dict_to_xml_recurse(elem, item)
            else:
                elem = etree.Element(tag)
                parent.append(elem)
                dict_to_xml_recurse(elem, child)
    else:
        parent.text = str(dictitem)


def dedup_with_order(in_list):
    """
    Take list and remove duplicates, but keep order
    Input: list
    Output: list with duplicates removed but order kept
    """

    seen = set()
    seen_add = seen.add
    result_list = [x for x in in_list if not (x in seen or seen_add(x))]

    return result_list


def file_to_list(fname):
    """
    Take file, open it, and create list of contents
    Input: filename
    Output: list with contents, separated on line break
    """
    result_list = []

    try:
        fin = open(fname, 'r')
        result_list = fin.readlines()
        fin.close()
    except IOError:
        raise IOError, "file not found: %s" % fname

    #Remove any newlines and duplicates but keep order
    result_list = [x.strip() for x in result_list]
    result_list = dedup_with_order(result_list)

    return result_list


def tryint(string):
    """
    Test if string is an integer
    """

    try:
        return int(string)
    except ValueError:
        return string

def str_none(string):
    """
    If string is None, then return empty string, else return the string
    """
    if string is None:
        return ''

    return str(string)


def alphanum_key(string):
    '''
    Turn a string into a list of string and number chunks.
        "z23a" -> ["z", 23, "a"]
    Borrowed from http://nedbatchelder.com/blog/200712.html
    '''
    return [tryint(item) for item in re.split('([0-9]+)', string)]


class ParseNode(list):
    '''
    Utility class to track found patterns in NestedParser
    '''

    def __init__(self, parent=None):
        list.__init__(self)
        self.parent = parent


class NestedParser(object):
    '''
    Parser to allow regex matching of nested parenthesis or other separators.
        Borrowed from
        http://stackoverflow.com/questions/1099178/matching-nested-structures-with-regular-expressions-in-python .
        Alternative is to use pyparsing, but that would be an external dependency and NestedParser may be faster:
        http://gotoanswer.stanford.edu/?q=Python%3A+How+to+match+nested+parentheses+with+regex%3F .
    Input: field delimiters (optional, paranthesis is default), string for parse method
    Output: nested list with split on the delimiters
    '''

    def __init__(self, left=r'\(', right=r'\)'):
        self.scanner = re.Scanner([
            (left, self.left),
            (right, self.right),
            (r"\s+", None),
            (".+?(?=(%s|%s|$))" % (right, left), self.other),
        ], re.S)
        self.result = ParseNode()
        self.current = self.result

    def parse(self, content):
        """
        parse method
        """
        self.scanner.scan(content)
        return self.result

    def left(self, scanner, token):
        """
        method for lexicon's left definition
        """
        new = ParseNode(self.current)
        self.current.append(new)
        self.current = new

    def right(self, scanner, token):
        """
        method for lexicon's right definition
        """
        self.current = self.current.parent

    def other(self, scanner, token):
        """
        method for lexicon's other definition
        """
        self.current.append(token.strip())


class ParserOpts(object):
    """
    Class for basic options related to parser
    """

    def __init__(self, result_clean, output_parser, dt_table):
        self.result_clean = result_clean
        self.output_parser = output_parser
        self.dt_table = dt_table

    def get_result_clean(self):
        """Getter for result_clean"""
        print self.result_clean

    def get_output_parser(self):
        """Getter for output_parser"""
        print self.output_parser

    def get_dt_table(self):
        """Getter for dt_table"""
        print self.dt_table


class BaseDTParser(object):
    """
    Common base class for parsers
    """
    #ignore pylint E1101 complaining of __subclasses__ not being member of class, is dynamically generated
    #pylint: disable=no-member
    #Parser to use for DT query output ("gpb" for now)
    _output_parser = ""
    #DT table to work on
    _dt_table = ""
    #Cleaned HTTP result to parse
    _result_clean = ""
    #ID being worked on (OID, Chunk ID, etc)
    in_id = ""

    def __init__(self):
        pass

    @classmethod
    def gen_parser(cls, parser_opts, in_id, all_seq, debug):
        """
        Generate parser based on output format/parser chosen and DT table requested
        """

        # get the subclass which handles this parser and DT table
        subclass = [subc for subc in cls.__subclasses__()
                    if subc.get_output_parser() == parser_opts.output_parser and
                    subc.get_dt_table() == parser_opts.dt_table]
        if subclass:
            subclass = subclass[0]
            #if subclass matches conditions, pass it cleaned DT query results
            #for parsing and ID (OID, Chunk ID, etc)
            return subclass(parser_opts.result_clean, in_id, all_seq, debug)
        else:
            raise Exception("Unsupported parser or DT table")

    @classmethod
    def get_output_parser(cls):
        """
        Return output parser variable
        """

        return cls._output_parser

    @classmethod
    def get_dt_table(cls):
        """
        Return DT table variable
        """

        return cls._dt_table


class ParseOBRegex(BaseDTParser):
    """
    Parse DT OB table of type "update" using GPB input
    """
    #Parser implemented in this class
    _output_parser = "gpb_regex"
    #DT table to work on
    _dt_table = "OB"
    #Cleaned HTTP result to parse
    _result_clean = ""
    #ID being worked on, here OID
    in_id = ""
    #Regex patterns for key/value matching
    _sys_reg = re.compile(r'key: "(.*)".*value: "(.*)"', re.S)
    _user_reg = re.compile(r'key: "(.*)".*Value: "(.*)"', re.S)
    _repo_reg = re.compile(r'chunkId: "(.*)"', re.S)
    _entry_reg = re.compile(r'(.*?): "?(.*?)"?$', re.M)
    _header_reg = re.compile(r'[\n]?(.*)$')

    def __init__(self, result_clean, in_id, all_seq, debug):
        BaseDTParser.__init__(self)

        #Dictionaries to store and return results
        self.segment_dict = {}
        self.segmentumr_dict = {}
        self.nped = None

        self._result_clean = result_clean
        #OID
        self.in_id = in_id
        self.debug = debug
        self.all_seq = all_seq

        self._process()

    def _process(self):
        """
        main method for processing GPB OB record using NestedParser
        """

        npobj = NestedParser(r'\{', r'\}')
        self.nped = npobj.parse(self._result_clean)
        if self.debug:
            print "Cleaned GPB:"
            pprint.pprint(self._result_clean)
            print "Nested Parsed:"
            pprint.pprint(self.nped)

        if len(self.nped) != 0:
            if self.all_seq:
                self.segment_dict = self.list_to_dict(self.nped)
            else:
                self.ob_aggregate(self.nped)
        else:
            if self.debug:
                print "ERROR: failed to parse nested structure:"
                print self._result_clean

        if self.debug:
            print "Segment Dictionary:"
            pprint.pprint(self.segment_dict)


    def update_seg_sec(self, temp_dict, section, segumr_n):
        """
        Check for a certain section in a temporary dictionary and update segment_dict with that.
            Used by ob_aggregate to look for a section and aggregrate then remove that from temp dictionary.
        Input: temp dictionary and section to check/update
        Output: modified temp dictionary (also updates existing segment_dict)
        """

        if section in temp_dict['segmentUMR' + str(segumr_n)]:
            if section not in self.segment_dict['segment1']['segmentUMR1']:
                self.segment_dict['segment1']['segmentUMR1'][section] = {}
            self.segment_dict['segment1']['segmentUMR1'][section].update(
                temp_dict['segmentUMR' + str(segumr_n)][section])
            del temp_dict['segmentUMR' + str(segumr_n)][section]
        return temp_dict


    def append_seg_sec(self, temp_dict, section, segumr_n):
        """
        Check for a certain section in a temporary dictionary and append segment_dict with that.
            Used by ob_aggregate to look for a section and append those.
        Input: temp dictionary and section to check/append
        Output: modified temp dictionary (also updates existing segment_dict)
        """

        if 'count_' + section in temp_dict['segmentUMR' + str(segumr_n)]:
            sec_idx_count = int(temp_dict['segmentUMR' + str(segumr_n)]['count_' + section])
            for sec_dt_idx in range(1, sec_idx_count+1):
                if 'count_' + section in self.segment_dict['segment1']['segmentUMR1']:
                    max_count = int(self.segment_dict['segment1']['segmentUMR1']['count_' + section])
                else:
                    max_count = 0
                max_count += 1
                self.segment_dict['segment1']['segmentUMR1'][section + str(max_count)] =\
                        temp_dict['segmentUMR' + str(segumr_n)].pop(section + str(sec_dt_idx))
                self.segment_dict['segment1']['segmentUMR1']['count_' + section] = max_count
            del temp_dict['segmentUMR' + str(segumr_n)]['count_' + section]

        return temp_dict


    def ob_aggregate(self, listobj):
        """
        Iterate each segment separately and put all segmentUMR
            into same segment 1 segmentUMR, overwriting sysMd,
            headSysMd, and userMd, but appending dataIndices and
            reposUMRLocations
        Input: None (uses existing Nested Parsed result)
        Output: None (updates existing segment_dict)
        """
        temp_dict = {}

        for num, _ in enumerate(listobj):
            if listobj[num-1] == 'segment':
                temp_dict = self.list_to_dict(listobj[num])
                if num == 1:
                    #Do some initialization
                    self.segment_dict['segment1'] = {}
                    self.segment_dict['count_segment'] = 1
                    self.segment_dict['segment1']['segmentUMR1'] = {}
                    self.segment_dict['segment1']['count_segmentUMR'] = 1
                    self.segment_dict['segment1']['segmentUMR1']['sysMd'] = {}
                count_segumr = int(temp_dict['count_segmentUMR'])
                for segumr_n in range(1, count_segumr+1):
                    if 'sysMd' in temp_dict['segmentUMR' + str(segumr_n)]:
                        self.segment_dict['segment1']['segmentUMR1']['sysMd'].update(
                            temp_dict['segmentUMR' + str(segumr_n)]['sysMd'])
                        del temp_dict['segmentUMR' + str(segumr_n)]['sysMd']
                    #Aggregrate headSysMd and userMd, if exists, and remove from temp_dict
                    temp_dict = self.update_seg_sec(temp_dict, 'headSysMd', segumr_n)
                    temp_dict = self.update_seg_sec(temp_dict, 'userMd', segumr_n)
                    if temp_dict['segmentUMR' + str(segumr_n)]:
                        #Append dataIndices, reposUMRLocations, and dataRange
                        temp_dict = self.append_seg_sec(temp_dict, 'dataIndices', segumr_n)
                        #temp_dict = self.append_seg_sec(temp_dict, 'dataRange', segumr_n)
                        temp_dict = self.append_seg_sec(temp_dict, 'reposUMRLocations', segumr_n)
                        #temp_dict = self.append_seg_sec(temp_dict, 'segmentLocation', segumr_n)
                        #If anything left just update/overwrite
                        if temp_dict['segmentUMR' + str(segumr_n)]:
                            self.segment_dict['segment1']['segmentUMR1'].update(
                                temp_dict['segmentUMR' + str(segumr_n)])


    def str_to_dict(self, strobj, ret_dict=False, targetdict=None):
        """
        Take strings and create dictionary of them, based on self._entry_reg regex
        Input: string to process and either True to return or dictionary to merge results into (overwriting)
        Output: dictionary result or merge into existing dictionary
        """
        dictobj = {}

        for (key, value) in self._entry_reg.findall(strobj):
            dictobj[key.strip()] = value.strip()

        if ret_dict:
            return dictobj
        elif targetdict:
            targetdict.update(dictobj)

    def list_to_dict(self, listobj):
        """
        Take list and create dictionary, using GPB noun as key
        Input: list to process
        Output: dictionary result
        """
        temp_dict = {}

        for num, item in enumerate(listobj):
            if isinstance(item, list):
                #Find key from end of last list item (is reliable for GPB)
                header = self._header_reg.search(listobj[num-1]).group(1)
                header = header.strip()
                if header in ('sysMd', 'headSysMd'):
                    #Handle specific regex case and add that key and value
                    #to temp_dict at this level (don't do recursive call again)
                    if header not in temp_dict:
                        temp_dict[header] = {}
                    found = self._sys_reg.search(item[0])
                    if len(found.groups()) == 2:
                        key, value = found.group(1, 2)
                        temp_dict[header][key] = value
                elif header == 'userMd':
                    #Handle this specific regex case and add that key and value
                    #to temp_dict at this level (don't do recursive call again)
                    if 'userMd' not in temp_dict:
                        temp_dict['userMd'] = {}
                    found = self._user_reg.search(item[0])
                    if len(found.groups()) == 2:
                        key, value = found.group(1, 2)
                        temp_dict['userMd'][key] = value
                else:
                    #Then add header to counter
                    if 'count_' + header not in temp_dict:
                        temp_dict['count_' + header] = 1
                    else:
                        temp_dict['count_' + header] += 1
                    #Then retrieve that same header from counter and use that
                    #as key (header + counter) for dict
                    key = header + str(temp_dict['count_' + header])
                    temp_dict[key] = self.list_to_dict(item)
            else:
                #Get key/value and add to dict
                temp_dict.update(self.str_to_dict(item, True))

        return temp_dict

    def get_ob(self):
        """
        Pretty print whole object
        """
        pprint.pprint(self.segment_dict)

    def get_chunk_id(self):
        """
        Generate list of chunk IDs and return it
        Input: None
        Output: return generate list of chunk IDs for each segment, segment UMR, and reposUMRLocations
        """
        chunk_list = []

        for seg_n in range(1, int(self.segment_dict['count_segment'])+1):
            count_segumr = int(self.segment_dict['segment' + str(seg_n)]['count_segmentUMR'])
            for segumr_n in range(1, count_segumr+1):
                #If segmentLocation chunkId isn't there, error use the other
                #one in reposUMRLocations and then remove duplicates at end
                if ('count_dataIndices' in self.segment_dict['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]
                        and self.segment_dict['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]
                        ['count_dataIndices'] > 0):
                    count_idx = int(self.segment_dict['segment' + str(seg_n)]
                                    ['segmentUMR' + str(segumr_n)]['count_dataIndices'])
                    for dataidx_n in range(1, count_idx+1):
                        if ('count_segmentLocation' in self.segment_dict['segment' + str(seg_n)]
                                ['segmentUMR' + str(segumr_n)]['dataIndices' + str(dataidx_n)]):
                            count_segloc = int(self.segment_dict['segment' + str(seg_n)]
                                               ['segmentUMR' + str(segumr_n)]['dataIndices' + str(dataidx_n)]
                                               ['count_segmentLocation'])
                            for segloc_n in range(1, count_segloc+1):
                                chunk_list.append(self.segment_dict['segment' + str(seg_n)]
                                                  ['segmentUMR' + str(segumr_n)]['dataIndices' + str(dataidx_n)]
                                                  ['segmentLocation' + str(segloc_n)]['chunkId'])
                if ('count_reposUMRLocations' in
                        self.segment_dict['segment' + str(seg_n)]
                        ['segmentUMR' + str(segumr_n)]):
                    for repo_n in range(1, int(self.segment_dict['segment' + str(seg_n)]
                                               ['segmentUMR' + str(segumr_n)]['count_reposUMRLocations'])+1):
                        chunk_list.append(self.segment_dict['segment' + str(seg_n)]
                                          ['segmentUMR' + str(segumr_n)]['reposUMRLocations' + str(repo_n)]
                                          ['chunkId'])
                else:
                    if self.debug:
                        print "INFO: No chunk info found"
                #Remove any duplicates but keep order
                #There may be duplicates because some chunks may be written to multiple times,
                #at different offsets, for the same object (different segments of object in same chunk)
                chunk_list = dedup_with_order(chunk_list)

        return chunk_list


class ParseCTRegex(BaseDTParser):
    """
    Parse DT CT table of type "update" using GPB input
    """
    #Parser implemented in this class
    _output_parser = "gpb_regex"
    #DT table to work on
    _dt_table = "CT"
    #Cleaned HTTP result to parse
    _result_clean = ""
    #ID being worked on, here Chunk ID
    in_id = ""
    #Regex patterns for key/value matching
    _entry_reg = re.compile(r'(.*?): "?(.*?)"?$', re.M)
    _header_reg = re.compile(r'[\n]?(.*)$')


    def __init__(self, result_clean, in_id, all_seq, debug):
        BaseDTParser.__init__(self)

        #Dictionaries to store and return results
        #This contains copies with segments inside and ssLocation inside that
        self.copies_dict = {}
        self.nped = None

        self._result_clean = result_clean
        #Chunk ID
        self.in_id = in_id
        self.debug = debug
        self.all_seq = all_seq

        self._process()

    def _process(self):
        """
        main method for processing GPB CT record using NestedParser
        """

        npobj = NestedParser(r'\{', r'\}')
        self.nped = npobj.parse(self._result_clean)

        if len(self.nped) != 0:
            self.copies_dict = self.list_to_dict(self.nped)
        else:
            if self.debug:
                print "ERROR: failed to parse nested structure"

        if self.debug:
            print "Cleaned GPB:"
            pprint.pprint(self._result_clean)
            print "Nested Parsed:"
            pprint.pprint(self.nped)
            print "Copies Dictionary:"
            pprint.pprint(self.copies_dict)


    def str_to_dict(self, strobj, ret_dict=False, targetdict=None):
        """
        Take strings and create dictionary of them, based on self._entry_reg regex
        Input: list to process and either True to return  or dictionary to merge results into (overwriting)
        Output: dictionary result or merge into existing dictionary
        """
        dictobj = {}
        types_count = 0

        for (key, value) in self._entry_reg.findall(strobj):
            if "dtTypes" in key:
                types_count += 1
                dictobj[key.strip() + str(types_count)] = value.strip()
            else:
                dictobj[key.strip()] = value.strip()

        if ret_dict:
            return dictobj
        elif targetdict:
            targetdict.update(dictobj)

    def list_to_dict(self, listobj):
        """
        Take list and create dictionary, using GPB noun as key
        Input: list to process
        Output: dictionary result
        """
        temp_dict = {}

        for num, item in enumerate(listobj):
            if isinstance(item, list):
                #Find key from end of previous list item
                #(is reliable for GPB format)
                header = self._header_reg.search(listobj[num-1]).group(1)
                header = header.strip()
                #Then add header to counter
                if 'count_' + header not in temp_dict:
                    temp_dict['count_' + header] = 1
                else:
                    temp_dict['count_' + header] += 1
                #Then retrieve that same header from counter and use that as
                #key (header + counter) for dict
                key = header + str(temp_dict['count_' + header])
                temp_dict[key] = self.list_to_dict(item)
            else:
                #Get key/value and add to dict
                temp_dict.update(self.str_to_dict(item, True))

        return temp_dict

    def get_ct(self):
        """
        Pretty print whole object
        """
        pprint.pprint(self.copies_dict)


class ParseOBGPB(BaseDTParser):
    """
    Parse DT OB table of type "update" using GPB input
    """
    #Parser implemented in this class
    _output_parser = "gpb"
    #DT table to work on
    _dt_table = "OB"
    #Cleaned HTTP result to parse
    _result_clean = ""
    #ID being worked on, here OID
    in_id = ""
    #Dictionaries to store and return results
    sys_dict = {}
    user_dict = {}
    repo_dict = {}

    #This ParseOBGPB subclass is a placeholder in case a new parser is
    #need for just GPB. The regex GPB parser should be flexible enough, but
    #this could be a future enhancement if needed.

    #Test for import (2 layers), first import pretending inside container
    #(if sys.path exists then add it to sys.path and import), otherwise in
    #exception do another try statement to see if can get path going through
    #devmapper. Otherwise maybe set a variable that there are no libs available
    #or must specify -h manually or tool must be run on ECS node, outside or
    #inside container. See
    #http://stackoverflow.com/questions/17015230/ \
    #are-nested-try-except-blocks-in-python-a-good-programming-practice

    #If need to, maybe could get to /opt/storageos/lib in object container
    #through devicemapper mount.

    def __init__(self, result_clean, in_id, all_seq, debug):
        BaseDTParser.__init__(self)
        self._result_clean = result_clean
        #OID
        self.in_id = in_id
        self.debug = debug
        self.all_seq = all_seq

        self._process()

    def _process(self):
        """
        main method for processing GPB record using GPB
        """

        pass

        #See escalationtools/misc/test_gpb.py for how to do this. Still build
        #a dictionary, same ones as in gpb_regex parser.

    def get_chunk_id(self):
        """
        return chunk IDs
        """
        pass


class PrinterOpts(object):
    """
    Class for basic options related to results printer class
    """

    def __init__(self, ob_obj, ct_objs):
        self.ob_obj = ob_obj
        self.ct_objs = ct_objs

    def get_ob_obj(self):
        """Getter for ob_obj"""
        print self.ob_obj

    def get_ct_objs(self):
        """Getter for ct_objs"""
        print self.ct_objs


class Printer(object):
    """
    Print the parsed object and chunk (if applicable)
    """
    #Regex patterns for key/value matching
    _entry_reg = re.compile(r'(.*?): "?(.*?)"?$', re.M)

    def __init__(self, printer_opts, debug, datanode, timeout):
        self.ob_obj = printer_opts.ob_obj
        self.ct_objs = printer_opts.ct_objs
        self.debug = debug
        self.datanode = datanode
        self.timeout = timeout

        self.print_ob_header()
        if self.ob_obj:
            self.print_ob()
        else:
            print "    No object data"
        self.print_ct_header()
        if self.ct_objs:
            self.print_ct()
        else:
            print "    No chunk data"

    @staticmethod
    def print_ob_header():
        """
        print header
        """

        print "="*30
        print "Object Info:"

    def print_ob(self):
        """
        print system/user/basic metadata
        """
        ob_temp = {}

        print "ObjectId: {0}\n".format(self.ob_obj.in_id)
        ob_temp = copy.deepcopy(self.ob_obj.segment_dict)
        #Print for each segment and segmentUMR in a loop
        for seg_n in range(1, ob_temp['count_segment']+1):
            for segumr_n in range(1, ob_temp['segment' + str(seg_n)]['count_segmentUMR']+1):
                print "Segment {0} SegmentUMR {1}".format(seg_n, segumr_n)
                #Print system metadata
                ob_temp, versionmd = self.print_ob_sys(ob_temp, seg_n, segumr_n)

                #Print head system metadata
                ob_temp = self.print_ob_headsys(ob_temp, seg_n, segumr_n)

                #Print user metadata
                ob_temp = self.print_ob_user(ob_temp, seg_n, segumr_n)

                #Print version metadata
                if versionmd:
                    print "Version Info:"
                    if isinstance(versionmd, str):
                        print "{pre}{0:<{fill}} {1}".format('version-info:', versionmd, pre=' '*8,
                                                            fill=len('version-info') + 2)
                    else:
                        width = max(len(key) for key in versionmd)
                        if 'type' in versionmd:
                            print "{pre}{0:<{fill}} {1}".format('type:', versionmd['type'], pre=' '*8,
                                                                fill=width + 2)
                            del versionmd['type']
                        for k in sorted(versionmd):
                            print "{pre}{0:<{fill}} {1}".format(k+':', versionmd[k],
                                                                pre=' '*8, fill=width + 2)
                else:
                    print

                #Print rest of object metadata
                if ob_temp:
                    self.print_nest_dict(ob_temp['segment' + str(seg_n)]
                                         ['segmentUMR' + str(segumr_n)])

                #Extra newline for clarity
                print

    def print_ob_sys(self, ob_temp, seg_n, segumr_n):
        """
        print system metadata
        """
        sysmd = {}
        versionmd = {}

        #Separate out system metadata
        if 'sysMd' in ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]:
            print "System Metadata:"
            sysmd = ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]['sysMd']
            del ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]['sysMd']

        if sysmd:
            #Remove version-info MD, parse, and print later in own section
            if 'version-info' in sysmd:
                versionmd = sysmd['version-info']
                versionmd = self.parse_version_info(versionmd)
                del sysmd['version-info']

            #If keypool-hash-id is in sysMd, it's also the parent id
            if 'keypool-hash-id' in sysmd:
                sysmd['parent-id'] = sysmd['keypool-hash-id']

            #Get string width for padding based on largest word
            width = max(len(key) for key in sysmd)

            #Print atime/mtime/ctime/item
            sysmd = self.print_ob_times(width, sysmd)
            if ('object-name' in sysmd and 'objname' in sysmd and
                    sysmd['object-name'] == sysmd['objname']):
                del sysmd['objname']
            #If there's unicode in object name, interpret the embedded escape sequence
            if 'object-name' in sysmd:
                sysmd['object-name'] = sysmd['object-name'].decode('string_escape')
            #Remove duplicate objectId which is already printed earlier
            if 'objectid' in sysmd:
                del sysmd['objectid']

            #Then print the other sysMd in sorted order
            for k in sorted(sysmd):
                if k == 'acl2' or k == 'data-range':
                    #NOTE: There's not enough information currently to
                    #decode these. For now, will print out encoded and
                    #later can decode.
                    #s = repr(base64.b64decode(sysMd[k])).strip("'")
                    #print "{pre}{0:<{fill}} {1}".format(k+':', s,
                            #pre=' '*8, fill=width + 2)
                    print "{pre}{0:<{fill}} {1}".format(k+':', sysmd[k], pre=' '*8, fill=width + 2)
                else:
                    print "{pre}{0:<{fill}} {1}".format(k+':', sysmd[k], pre=' '*8, fill=width + 2)

        return ob_temp, versionmd

    def print_ob_headsys(self, ob_temp, seg_n, segumr_n):
        """
        print head system metadata
        """
        headsysmd = {}
        rename_md = {'IM': 'intermediate md5',
                     'WT': 'write time',
                     'BR': 'blob reference',
                     'OT': 'object type',
                     'RP': 'reflection privileged',
                     'RC': 'reflection client type',
                     'RR': 'reflection reason',
                     'PR': 'reflection principal',
                     'RI': 'reflection incoming ip',
                     'RD': 'reflection processed',
                     'AR': 'application registry'}
        blob_reg = re.compile(r'^.{15}x.{39}$')
        blob_count = 0

        #Separate out head system metadata
        if 'headSysMd' in ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]:
            headsysmd = ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]['headSysMd']
            del ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]['headSysMd']

        #Print head system metadata in sorted order
        if headsysmd:
            print "Head System Metadata:"

            #Workaround for Jira STORAGE-7651
            for key in headsysmd.keys():
                if blob_reg.match(key) and not headsysmd[key]:
                    blob_count += 1
                    headsysmd[rename_md['BR'] + ' ' + str(blob_count)] = key[2:]
                    del headsysmd[key]

            #rewrite some headers to more descriptive names
            for key, value in rename_md.iteritems():
                if key in headsysmd:
                    headsysmd[value] = headsysmd[key]
                    del headsysmd[key]

            #find max width for keys
            width = max(len(key) for key in headsysmd)

            #convert any times to human readable:
            headsysmd = self.print_ob_times(width, headsysmd)

            for k in sorted(headsysmd):
                print "{pre}{0:<{fill}} {1}".format(k+':', headsysmd[k], pre=' '*8, fill=width + 2)

        return ob_temp

    @staticmethod
    def print_ob_user(ob_temp, seg_n, segumr_n):
        """
        print user metadata
        """
        usermd = {}

        #Remove user MD and print later
        if 'userMd' in ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]:
            usermd = ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]['userMd']
            del ob_temp['segment' + str(seg_n)]['segmentUMR' + str(segumr_n)]['userMd']

        #Print user metadata in sorted order
        if usermd:
            print "User Metadata:"
            width = max(len(key) for key in usermd)
            for k in sorted(usermd):
                print "{pre}{0:<{fill}} {1}".format(k+':', usermd[k], pre=' '*8, fill=width + 2)

        return ob_temp

    @staticmethod
    def print_ob_times(width, sysmd):
        """
        print system metadata which are time related, in a specific order
        """
        #If exists, print times in following order
        times_list = ['atime', 'mtime', 'createtime', 'ctime', 'itime',
                      'fs-ctime', 'fs-mtime', 'parent-createtime', 'write time']

        for time_type in times_list:
            if time_type in sysmd and sysmd[time_type] != 0:
                if len(sysmd[time_type]) > 1:
                    #Convert Unix epoch format (without last 3 #s for milliseconds) to standard format
                    #Then print in human readable format
                    time_conv = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(int(sysmd[time_type][:-3])))
                else:
                    #Handle if a time is 0 (unix epoch)
                    time_conv = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(int(sysmd[time_type])))
                print "{pre}{0:<{fill}} {1} UTC".format(time_type+':', time_conv, pre=' '*8, fill=width + 2)
                del sysmd[time_type]

        return sysmd

    @staticmethod
    def print_ct_header():
        """
        print chunk header
        """

        print "="*30
        print "Chunk Info:"

    def print_ct(self):
        """
        print chunk metadata
        """

        for ct_obj in self.ct_objs:
            ct_temp = {}
            copies = {}

            print "ChunkId: {0}".format(ct_obj.in_id)
            ct_temp = copy.deepcopy(ct_obj.copies_dict)
            if 'count_copies' in ct_temp:
                for copy_n in range(1, ct_temp['count_copies']+1):
                    copies['copies'+str(copy_n)] = copy.deepcopy(ct_temp['copies' + str(copy_n)])
                    copies['copies'+str(copy_n)]['numberOfSegments'] = copies['copies'+str(copy_n)]['count_segments']
                    del ct_temp['copies'+str(copy_n)]

            #Print rest of object metadata first
            if ct_temp:
                #Add in number of data copies
                ct_temp['numberOfCopies'] = ct_temp['count_copies'] if 'count_copies' in ct_temp else 0
                self.print_nest_dict(ct_temp)
            #Then print copies
            if copies:
                self.print_nest_dict(copies)
            print

    def print_nest_dict(self, dictobj, depth=0):
        """
        print nested dictionary, taking into account the depth
        """

        for k in sorted(dictobj, key=alphanum_key):
            width = max(len(key) for key in dictobj)
            #Rewrite headers for subsections
            if isinstance(dictobj[k], dict):
                if 'copies' in k:
                    k_sub = re.sub(r'copies', r'Copy #', k)
                elif 'segments' in k:
                    k_sub = re.sub(r'segments', r'Segment #', k)
                elif 'ssLocation' in k:
                    k_sub = re.sub(r'ssLocation', r'SS Location #', k)
                elif 'dataIndices' in k:
                    k_sub = re.sub(r'dataIndices', r'Data Index #', k)
                elif 'reposUMRLocations' in k:
                    k_sub = re.sub(r'reposUMRLocations', r'Repos UMR Location #', k)
                else:
                    k_sub = re.sub(r'(.*)[1-9]+$', r'\1', k)
                print "{pre}{0}".format(k_sub+':', pre=' '*8*depth)
                self.print_nest_dict(dictobj[k], depth+1)
            else:
                if k not in IGNORE:
                    if k in ('autoSealTime', 'geoTrackTime', 'sealedTime'):
                        md_time = time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(int(dictobj[k][:-3])))
                        print "{pre}{0:<{fill}} {1}".format(k+':', md_time, pre=' '*8*depth, fill=width+2)
                    else:
                        print "{pre}{0:<{fill}} {1}".format(k+':', dictobj[k], pre=' '*8*depth, fill=width+2)

    def parse_version_info(self, enc_version):
        """
        Parse version_info. Note that table_id_query function is not used here
            since this is not a DT table query but version decoding (extra function
            in DT query API).
        """
        dec_version = {}

        id_url = VERSION_QUERY_URL.format(self.datanode, enc_version)
        result, ret = get_http(id_url, self.debug, False, self.timeout)
        if ret == SUCCESS:
            result = clean_http_result(result)
            dec_version.update(self.str_to_dict(result, True))

        if dec_version:
            return dec_version
        else:
            return enc_version

    def str_to_dict(self, strobj, ret_dict=False, targetdict=None):
        """
        Take strings and create dictionary of them, based on self._entry_reg regex
        Input: string to process and either True to return or dictionary to merge results into (overwriting)
        Output: dictionary result or merge into existing dictionary
        """
        dictobj = {}

        for (key, value) in self._entry_reg.findall(strobj):
            dictobj[key.strip()] = value.strip()

        if ret_dict:
            return dictobj
        elif targetdict:
            targetdict.update(dictobj)


def choose_parser(ecs_version, parser_override, no_parse, noversion, debug):
    """
    Choose output format and parser based on ECS version and override option -o.
    Input: override option -o
    Output: return which output format and parser to use
    """
    ecs_supported = ecs_version[0]
    ecs_v_code = ecs_version[1]

    #If -n option is set, don't use any parser (used to dump unparsed DT query)
    if no_parse:
        output_parser = 'none'
    #Else if ECS version is supported or override option is set, use GPB
    #output in DT query and parse GPB
    elif ecs_supported == 'Supported version' or noversion:
        if parser_override == 'gpb':
            #For now, use gpb_regex for everything
            #output_parser = 'gpb'
            output_parser = 'gpb_regex'
        elif parser_override == 'gpb_regex':
            output_parser = 'gpb_regex'
        else:
            #For now, use gpb_regex for everything
            #output_parser = 'gpb'
            output_parser = 'gpb_regex'
    #Else ECS version not supported. This is to catch any unexpected or future ECS versions, if have major changes.
    #As of ECS 3.0, disable and try proceeding anyway (avoid utilities container issue and anyway may not be
    #needed anymore)
    else:
        if debug:
            print 'DEBUG: ECS version %s not supported or no parser available, trying anyway' % ecs_v_code
        output_parser = 'gpb_regex'

    return output_parser


def choose_dt_table(header, debug):
    """
    Based on DT query result header (starts with schema), detect DT table
    Input: DT query result header
    Output: DT table detected (format is TABLE_TYPE like OB) and return code
    """
    dt_table = None

    if "schema" in header:
        if re.search(r'schemaType OBJECT_TABLE_KEY.*type (UPDATE|INDEX) .*', header):
            dt_table = 'OB'
        elif re.search(r'schemaType CHUNK .*', header):
            dt_table = 'CT'
        else:
            if debug:
                print "ERROR: DT table not supported, schema line is: %s" % \
                        header
    else:
        if debug:
            print "ERROR: DT query result header not found, input was: %s" % \
                    header

    return dt_table


class TableIDQueryOpts(object):
    """
    Class for basic options related to table_id_query
    """

    def __init__(self, datanode, output_parser, url, dt_table):
        self.datanode = datanode
        self.output_parser = output_parser
        self.url = url
        self.dt_table = dt_table

    def get_datanode(self):
        """Getter for datanode"""
        print self.datanode

    def get_output_parser(self):
        """Getter for output_parser"""
        print self.output_parser

    def get_url(self):
        """Getter for url"""
        print self.url

    def get_dt_table(self):
        """Getter for dt_table"""
        print self.dt_table

    def get_all(self):
        """Getter for all"""
        return (self.datanode, self.output_parser, self.url, self.dt_table)


def get_table_levels(query_opts, debug, timeout):
    """
    Get numer of DT table levels
    Input: query_opts (dt_table and datanode), debug, and timeout
    Output: number of levels, as list
    """
    levels = []
    regex_table_level = re.compile('.*http://.*:9101/diagnostic/' + query_opts.dt_table +
                                   '/([0-9]+)/(?!DumpAllKeys).*Show.*Table.*')

    result, ret = get_http(INDEX_URL.format(query_opts.datanode), debug, False, timeout)
    if ret == SUCCESS:
        levels = regex_table_level.findall(result)
        if debug:
            print "DEBUG: %s table levels found: %s" % (query_opts.dt_table, levels)
        return levels, SUCCESS
    else:
        print "ERROR: Failed to query index for DT table levels"
        return None, FAILURE


def table_id_query(query_opts, in_id, debug, timeout):
    """
    Query a certain DT table and return results. First query for which DT url the ID is in,
        then query that DT url for the ID.
    Input: ID to lookup (chunk ID, object ID, etc), data node to use for lookup, URL to use, DT table to query
    Output: DT query results and return status
    """
    id_url = ""
    id_dict = {}
    ob_type = ""

    #If is OB table query, check for type
    if '/OB/' in query_opts.url:
        if 'type=INDEX' in query_opts.url:
            ob_type = "INDEX"
        elif 'type=UPDATE' in query_opts.url:
            ob_type = "UPDATE"

    #Build list for number of DT table levels
    levels, ret = get_table_levels(query_opts, debug, timeout)
    if ret != SUCCESS:
        return None, FAILURE

    for level in levels:
        #We only care about first occurrence in any level or any partial result
        if id_url != "":
            break
        #Do DT query and clean results (strip header/footer)
        #If there was timeout, retry with higher timeout (add 5 seconds)
        result, ret = get_http(query_opts.url.format(query_opts.datanode, level, in_id), debug, True, timeout)
        #Handle results
        if ret != SUCCESS:
            id_url = ""
        else:
            result_list = clean_http_result(result).split("\r\n")
            #Loop over DT query output until find the URL to use for next query
            for entry in result_list:
                if entry.startswith("http"):
                    id_url = entry
                elif entry.startswith("schemaType"):
                    if (query_opts.output_parser == 'gpb' or query_opts.output_parser == 'none' or
                            query_opts.output_parser == 'gpb_regex'):
                        #Track number of hits for each URL
                        if id_url not in id_dict:
                            id_dict[id_url] = 1
                        else:
                            id_dict[id_url] += 1
            #From built hash/dictionary of URLs, choose max URL (most hits for schemaType header) or any of duplicates
            if id_dict:
                id_url = max(id_dict, key=lambda key: id_dict[key]) + SHOWVALUE_GPB

        if debug:
            print "DEBUG: DT URL to query: %s" % query_opts.url.format(query_opts.datanode, level, in_id)

    #If there was TIMEOUT, return that
    if ret == TIMEOUT:
        print "ERROR: URL open timeout"
        return None, TIMEOUT
    #If ID entry not found for any DT table, return NOT_FOUND
    elif id_url == "" or SHOWVALUE_GPB not in id_url:
        if debug and ob_type == "INDEX":
            print "WARN: ID %s not found in DT query for %s table type %s" % (in_id, query_opts.dt_table, ob_type) + \
                  " or unsupported DT parser"
        elif ob_type == "UPDATE":
            print "ERROR: ID %s not found in DT query for %s table type %s" % (in_id, query_opts.dt_table, ob_type) + \
                  " or unsupported DT parser"
        return None, NOT_FOUND

    #Use found URL to retrieve DT query result for ID in DT table
    return get_http(id_url, debug, False, timeout)


def table_id_query_helper(args):
    """
    Helper function to unpack arguments for table_id_query
    Input: arguments for table_id_query
    Output: table_id_query's result
    """
    args2 = (args[1],) + args[2]

    return table_id_query(args[0], *args2)


def query_ids_mp(query_opts, ids, opts):
    """
    Perform multiprocessing query for IDs (OID/Chunk ID) with table_id_query function
    Input: query options, IDs, CLI options
    Output: zipped results
    """
    #Ignore SIGINT to handle Ctrl+C correctly, so children inherit SIGINT handler:
    original_sigint_handler = signal.signal(signal.SIGINT, signal.SIG_IGN)
    #Do OB query using multiprocessing pool
    pool = mp.Pool(MP_LIM)
    #Restore SIGINT
    signal.signal(signal.SIGINT, original_sigint_handler)
    #Prepare arguments
    args_long = izip(repeat(query_opts), ids, repeat((opts.debug, opts.timeout)))
    #Get DT query results for this batch of IDs, using helper function to expand arguments
    zip_results = pool.map(table_id_query_helper, args_long)
    #Cleanup (though not needed as map() kills all children once they terminate)
    pool.close()
    pool.join()

    return zip_results


def main_lookup_process_oids(oids, datanode, opts, output_parser, use_oid):
    """
    Process OIDs in inner loop of main_lookup
    Input: OIDs to process, data node IP, CLI options, output_parser to use, if is OID or namespace
    Output: printed object
    """
    while oids:
        #Get an ordered batch of OIDs to work on, poping it out of list, taking limit into account
        if len(oids) > OBJ_CHUNK_LIM:
            cur_oids = [oids.pop(0) for num in range(0, OBJ_CHUNK_LIM)]
        else:
            cur_oids = [oids.pop(0) for num in range(0, len(oids))]
        #Process OIDs and return results
        ret, list_ob_update_obj, list_chunk_ids = ob_lookup(datanode, opts, cur_oids, output_parser, use_oid)
        if ret != SUCCESS:
            return ret

        for num, oid in enumerate(cur_oids):
            ob_update_obj = list_ob_update_obj[num]
            chunk_ids = list_chunk_ids[num]

            #Do CT table lookup for chunk Ids (with multiprocessing)
            ret, ct_objs = ct_lookup(datanode, opts, output_parser, chunk_ids)
            if ret != SUCCESS:
                return ret

            #If option is set, convert dictionaries to XML and show output
            if opts.xml:
                if oid == "namespace":
                    oid = ""
                dict_to_xml(oid, ob_update_obj, chunk_ids, ct_objs)

            #With the OB table and all CT chunks parsed, pass those to print function
            #for formatted print, unless using XML option
            if not opts.xml and output_parser != 'none':
                Printer(PrinterOpts(ob_update_obj, ct_objs), opts.debug, datanode, opts.timeout)


def main_lookup(datanode, opts, ids, use_oid, ecs_version):
    """
    Lookup OID, name, or chunk ID in DT table OB and return the results
    Input: data node IP, CLI options (for OID/name or chunk ID to check)
    Output: mauiobjbrowser-like output of object
    """
    oid = ""
    chunk_ids = []
    ob_update_obj = None
    ct_objs = None

    #Choose output parser based on ECS version and CLI options
    output_parser = choose_parser(ecs_version, opts.parser, opts.no_parse, opts.noversion, opts.debug)
    if output_parser == FAILURE:
        return FAILURE

    #Process "chunk IDs only" option
    if opts.cid or opts.c_file:
        if opts.c_file:
            chunk_ids = ids
        else:
            chunk_ids = [cid.strip() for cid in opts.cid.split(",")]

        #Do CT table lookup for chunk Ids (with multiprocessing)
        ret, ct_objs = ct_lookup(datanode, opts, output_parser, chunk_ids)
        if ret != SUCCESS:
            return ret

        #If option is set, convert dictionaries to XML and show output
        if opts.xml:
            dict_to_xml(oid, ob_update_obj, chunk_ids, ct_objs)

        #With the OB table and all CT chunks parsed, pass those to print function
        #for formatted print, unless using XML option
        if not opts.xml and output_parser != 'none':
            Printer(PrinterOpts(ob_update_obj, ct_objs), opts.debug, datanode, opts.timeout)
    #Process OIDs using multiprocessing pool
    else:
        #Split input into list
        if ids:
            if opts.o_file:
                oids = filter(None, ids)
            else:
                oids = [oid.strip() for oid in ids.split(",")]
        #If no OIDs, then must be using namespace. Fill in a value for oids, will be overwritten
        #with correct OID later in ob_lookup
        else:
            oids = ["namespace"]
        #Process OIDs
        main_lookup_process_oids(oids, datanode, opts, output_parser, use_oid)

    return SUCCESS


def ob_lookup(datanode, opts, oids, output_parser, use_oid):
    """
    Do OB part of query and processing
    """
    list_ob_obj = []
    ob_update_obj = None
    list_chunk_ids = []
    chunk_ids = []
    regex_schema_header = re.compile("schemaType OBJECT_TABLE_KEY.*type (UPDATE|INDEX) .*")
    regex_seq = re.compile("schemaType .* sequence .*")
    dt_table = 'OB'
    zip_results = []

    #Query OB table for OID
    #If -n -b option is used, do bucket & name based query
    if not use_oid:
        #Convert string to HTTP escape string
        escaped_path = urllib.quote(opts.path_name)
        result, ret = get_http(OB_NAME_QUERY_URL.format(datanode, opts.bucket, escaped_path), opts.debug, False,
                               opts.timeout)
        if ret != SUCCESS:
            print "ERROR: Check namespace, bucket, and object path. Use quotes if path contains spaces."
            return ret, list_ob_obj, list_chunk_ids
        else:
            header = regex_schema_header.search(result).group(0)
            oids = [re.search(r"schemaType OBJECT_TABLE_KEY objectId (.*) type.*",
                              header).group(1)]

    #Whether namespace or not, do OID lookup for consistency, multiprocessed
    if oids:
        #Do multiprocessing-based lookup of OB query
        #Setup zipped (iterator version) arguments for use with table_id_query function,
        #using repeat() duplicate arguments according # of OIDs
        for query in (OB_INDEX_OID_QUERY_URL, OB_UPDATE_OID_QUERY_URL):
            query_opts = TableIDQueryOpts(datanode, output_parser, query, dt_table)
            for num, oid_result in enumerate(query_ids_mp(query_opts, oids, opts)):
                if oid_result[0]:
                    if opts.debug:
                        print "Non-cleaned GPB:"
                        pprint.pprint(oid_result[0])
                    oid_result = list(oid_result)
                    oid_result[0] = clean_http_result(oid_result[0])
                    #For Index query, do additional cleanup (don't keep header and reformat GPB as segmentUMR)
                    if "INDEX" in query:
                        #Put in GPB beginning
                        if re.match(r"^schemaType .*? objectIndexKeySubType RANGE .*", oid_result[0]):
                            oid_result[0] = re.sub(r"^schemaType .*? objectIndexKeySubType RANGE .*?\r\n(.*?)\r\n",
                                                   r"segment {\n  segmentUMR {\n  dataIndices {\n\1\r\n}",
                                                   oid_result[0], flags=re.S).strip()
                        else:
                            oid_result[0] = re.sub(r"^schemaType .*", "segment {\n  segmentUMR {\n",
                                                   oid_result[0]).strip()
                        #Handle special case of objectIndexKeySubType RANGE is actually a dataIndices
                        if "objectIndexKeySubType RANGE" in oid_result[0]:
                            oid_result[0] = re.sub(r"schemaType .*? objectIndexKeySubType RANGE .*?\r\n(.*?)\r\n",
                                                   r"\n}\n  segmentUMR {\n  dataIndices {\n\1\r\n}", oid_result[0],
                                                   flags=re.S).strip()
                            oid_result[0] = re.sub(r"schemaType .*? objectIndexKeySubType RANGE .*?\r\n(.*?)$",
                                                   r"\n}\n  segmentUMR {\n  dataIndices {\n\1}", oid_result[0],
                                                   flags=re.S).strip()
                        #Replace rest of schema headers with GPB segmentUMR
                        oid_result[0] = re.sub(r"schemaType .*", "\n}\n  segmentUMR {\n", oid_result[0]).strip()
                        #Close new GPB
                        oid_result[0] = oid_result[0] + "}}"
                #if zip_results:
                #    if oid_result[0]:
                if 0 <= num < len(zip_results):
                    zip_results[num] = (str_none(zip_results[num][0]) + str_none(oid_result[0]),
                                        min(zip_results[num][1], oid_result[1]))
                else:
                    zip_results.append(oid_result)
                #else:
                #    zip_results.append(oid_result)
        #Separate out results
        results = [result[0] for result in zip_results]
        #Separate out return values
        #Catch URL open errors and return, if no successes found
        if SUCCESS not in [result[1] for result in zip_results]:
            return FAILURE, list_ob_obj, list_chunk_ids

        for num, oid in enumerate(oids):
            #Split schema header from rest of object record
            if regex_schema_header.search(results[num]):
                header = regex_schema_header.search(results[num]).group(0)
                ob_result_clean = re.sub(r"schemaType .*", "", clean_http_result(results[num])).lstrip()
            else:
                print "ERROR: OID not found: %s" % oid
                return FAILURE, list_ob_obj, list_chunk_ids
            #If header has sequence in OB entry and list all sequences is specified(-s),
            #list all sequences, otherwise aggregrate into one
            all_seq = bool(regex_seq.match(header) and opts.seq)
            #If using namespace and outer segment is missing, add it back in
            #to help with processing
            if not use_oid and not ob_result_clean.startswith('segment {'):
                ob_result_clean = 'segment {\n' + ob_result_clean + '\n}'

            #If user doesn't want any parsing, just dump DT query result
            if output_parser == 'none':
                print "OB table:\n" + ob_result_clean
                if re.search(r'chunkId: (.*)', ob_result_clean):
                    chunk_ids = [re.search(r'chunkId: "(.*)"', ob_result_clean).group(1)]
                else:
                    chunk_ids = []
                list_ob_obj.append(None)
                list_chunk_ids.append(chunk_ids)
            #Else call class generator to instantiate correct parser
            else:
                dt_table = choose_dt_table(header, opts.debug)
                #Here we want OB table with update or index type
                if dt_table == "OB":
                    ob_parser_opts = ParserOpts(ob_result_clean, output_parser, dt_table)
                    ob_update_obj = BaseDTParser.gen_parser(ob_parser_opts, oid, all_seq, opts.debug)
                    list_ob_obj.append(ob_update_obj)
                    #Get chunk IDs for this object
                    chunk_ids = list_ob_obj[num].get_chunk_id()
                    list_chunk_ids.append(chunk_ids)
                else:
                    if opts.debug:
                        print "ERROR: DT table type is not expected: %s " % dt_table
                    return NOT_SUPPORTED, list_ob_obj, list_chunk_ids

    return SUCCESS, list_ob_obj, list_chunk_ids


def ct_lookup(datanode, opts, output_parser, chunk_ids):
    """
    Do CT part of query and processing
    """
    ct_objs = []
    regex_schema_header = re.compile("schemaType CHUNK .*")
    dt_table = 'CT'
    all_seq = False
    work_chunk_ids = copy.deepcopy(chunk_ids)
    work_chunk_ids = filter(None, work_chunk_ids)

    #Call class generator to parse chunk IDs, adding each instance to a list
    if work_chunk_ids:
        while work_chunk_ids:
            #Get an ordered batch of chunk IDs to work on, poping it out of list, taking limit into account
            if len(work_chunk_ids) > OBJ_CHUNK_LIM:
                cur_chunk_ids = [work_chunk_ids.pop(0) for num in range(0, OBJ_CHUNK_LIM)]
            else:
                cur_chunk_ids = [work_chunk_ids.pop(0) for num in range(0, len(work_chunk_ids))]
            #Do CT chunk query using multiprocessing pool
            query_opts = TableIDQueryOpts(datanode, output_parser, CT_QUERY_URL, dt_table)
            zip_results = query_ids_mp(query_opts, cur_chunk_ids, opts)
            #Separate out results
            results = [result[0] for result in zip_results]
            #Separate out return values
            #Catch any URL open errors and return
            for ret in [result[1] for result in zip_results]:
                if ret != SUCCESS:
                    return ret, ct_objs

            for num, c_id in enumerate(cur_chunk_ids):
                #Split schema header from rest of object record and remove extra
                #header/footer from result
                header = regex_schema_header.search(results[num]).group(0)
                ct_result_clean = re.sub(r"schemaType .*", "",
                                         clean_http_result(results[num])).lstrip()

                if output_parser == 'none':
                    print "\nCT table:\n" + ct_result_clean
                else:
                    dt_table = choose_dt_table(header, opts.debug)
                    #Here we want CT table
                    if dt_table == "CT":
                        ct_parser_opts = ParserOpts(ct_result_clean, output_parser, dt_table)
                        ct_objs.append(BaseDTParser.gen_parser(ct_parser_opts, c_id, all_seq, opts.debug))
                    else:
                        if opts.debug:
                            print "ERROR: DT table type not expected: %s" % dt_table
                        return FAILURE, ct_objs

    return SUCCESS, ct_objs


def main_setup_opts(usg):
    """
    Setup opts for main()
    Input: usage/description
    Output: opts parser, opts object with options
    """
    optparser = optparse.OptionParser(usage=usg)
    optparser.add_option("-i", "--oid", dest="oid", default="")
    optparser.add_option("-I", "--o_file", dest="o_file", default="")
    optparser.add_option("-p", "--path_name", dest="path_name", default="")
    optparser.add_option("-c", "--chunkid", dest="cid", default="")
    optparser.add_option("-C", "--c_file", dest="c_file", default="")
    optparser.add_option("-n", "--no_parse", action="store_true", dest="no_parse")
    optparser.add_option("-x", "--xml", action="store_true", dest="xml")
    optparser.add_option("-d", "--dt_node", dest="dt_node", default="")
    optparser.add_option("-b", "--bucket", dest="bucket", default="")
    optparser.add_option("-o", "--override", dest="parser", default="")
    optparser.add_option("-s", "--sequences", action="store_true", dest="seq")
    optparser.add_option("-t", "--timeout", dest="timeout", default=5)
    optparser.add_option("-D", "--debug", action="store_true", dest="debug")
    optparser.add_option("-V", "--noversion", action="store_true", dest="noversion")
    opts, _ = optparser.parse_args()

    return optparser, opts


def main_basic_env(opts):
    """
    Setup basic environment for main()
    Input: CLI options
    Output: modified CLI options, data node IP to use, ecs_version info
    """
    ret, detected_env, ecs_supported, ecs_v_code = detect_env(opts.debug)
    ecs_version = [ecs_supported, ecs_v_code]
    if ret == FAILURE:
        sys.exit(FAILURE)
    data_node_ip = choose_node_dt(opts.dt_node, detected_env, opts.timeout, opts.debug)
    if data_node_ip is None:
        sys.exit(FAILURE)
    #If ECS Community Edition and outside container, ignore ECS version check
    #if detected_env == "out_ce":
    #    opts.noversion = True
    #Starting with ECS 3.0, ignore version check
    opts.noversion = True

    return opts, data_node_ip, ecs_version


def main_bad_opts(optparser, opts):
    """
    Check for bad options combinations, printing help and exitting
    Input: opts parser, opts object with options
    Output: none
    """
    if not (opts.oid or opts.path_name or opts.cid or opts.o_file or opts.c_file):
        optparser.print_help()
        print "\nERROR: OID (-i or -I), Chunk ID (-c or -C), or object name must be specified"
        sys.exit(FAILURE)
    elif opts.parser != "" and opts.parser != "gpb" and opts.parser != "gpb_regex":
        optparser.print_help()
        print "\nERROR: Parser override must be valid (i.e. gpb_regex)"
        sys.exit(FAILURE)
    elif opts.parser != "" and opts.no_parse:
        optparser.print_help()
        print "\nERROR: Can't specify parser override and no parser"
        sys.exit(FAILURE)
    elif any([opts.cid, opts.c_file]) and any([opts.oid, opts.o_file, opts.path_name, opts.bucket]):
        optparser.print_help()
        print "\nERROR: Can't specify chunk ID and OID/path name/bucket at same time"
        sys.exit(FAILURE)
    elif any([opts.oid, opts.o_file]) and any([opts.cid, opts.c_file, opts.path_name, opts.bucket]):
        optparser.print_help()
        print "\nERROR: Can't specify OID and Chunk ID/path name/bucket at same time"
        sys.exit(FAILURE)
    elif (opts.oid and opts.o_file) or (opts.cid and opts.c_file):
        optparser.print_help()
        print "\nERROR: Use either file or CLI option for OID or Chunk ID, not both"
        sys.exit(FAILURE)
    elif opts.cid.strip().endswith(",") or opts.oid.strip().endswith(","):
        optparser.print_help()
        print "\nERROR: OID/Chunk ID list must be comma separated and contain no spaces in between"
        sys.exit(FAILURE)


def main_opt_pipe_exit(fun, fun_opts):
    """
    Execute command while preventing broken pipes (if using head/tail cmd) and exit with return code
    Input: function to execute, options to function
    Output: none
    """
    try:
        ret = fun(*fun_opts)
    except IOError, (errnum, dummy_msg):
        if errnum == errno.EPIPE:
            try:
                sys.stdout.close()
            except IOError:
                pass
            try:
                sys.stderr.close()
            except IOError:
                pass
    except KeyboardInterrupt:
        ret = FAILURE
        print
    sys.exit(ret)


def main():
    """
    the main function
    """

    usg = r'''
    %prog [options]
          This tool is used to query metadata for objects, by name (-b and -p) or object ID (OID) (-i).
          Chunk queries are also supported (-c), either a single ID or a comma separated list.
          Tool output can be formatted output (default), direct GPB/no parsing/no formatting (-n), or XML (-x).
          
          Options:
             -i, --oid          Object ID, accepts single ID or comma separated list
             -I, --o_file       File with list of Object IDs, one per line
             -p, --path_name    Object name or path under bucket. Directory object lookup should end with "/".
             -b, --bucket       Namespace and bucket name (required for -p option)
                                    Format should be <namespace name>.<bucket name> (period separated)
                                    This is the same as keypoolid or <namespace>.<keypoolname>
             -c, --chunkid      Chunk ID, accepts single ID or comma separated list
             -C, --c_file       File with list of Chunk IDs, one per line
             -n, --no_parse     Do not parse or format, just output DT query results
             -x, --xml          Print tool output in XML (not formatted)
             -d, --dt_node      IP to use for DT query. If not specified, will be determined. (optional)
             -h, --help         Print this help menu
             
          Advanced Options:
             -o, --override     Force use of a specific parser. Valid options are:
                 -o gpb_regex       Use regex based parser on GPB output
             -s, --sequences    Show all sequences, otherwise aggregate all sequences
             -t, --timeout      Timeout to use for DT query (may need increase in larger environments). 
                                    Default is 1 second.
             -D, --debug        Enable debug logging
             -V, --noversion    Ignore ECS version check
          
          Example: 
              python ecsobjbrowser.py -i <OID>
              python ecsobjbrowser.py -b <namespace>.<bucket name> -p <Object name>
              python ecsobjbrowser.py -c <chunk ID 1>,<chunk ID 2>,<chunk ID 3>
              python ecsobjbrowser.py -I <filename>
              python ecsobjbrowser.py -C <filename>
    '''
    optparser, opts = main_setup_opts(usg)

    #Basic environment setup
    use_oid = False
    opts.timeout = tryint(opts.timeout)
    opts, data_node_ip, ecs_version = main_basic_env(opts)

    #Validate options
    #First check for bad options and filter them out
    main_bad_opts(optparser, opts)
    #Process main options
    if opts.oid != "" or opts.cid != "" and not (opts.path_name or opts.bucket):
        use_oid = True
        #Execute options, handling broken pipe if pipe to head/tail
        main_opt_pipe_exit(main_lookup, (data_node_ip, opts, opts.oid, use_oid, ecs_version))
    elif opts.path_name != "":
        if opts.bucket == "":
            print "\nERROR: bucket name must be specified if using object name"
            sys.exit(FAILURE)
        elif not re.match(r".*\..*", opts.bucket):
            print "\nERROR: format must be <namespace>.<bucket name>"
            sys.exit(FAILURE)
        use_oid = False
        #Execute options, handling broken pipe if pipe to head/tail
        main_opt_pipe_exit(main_lookup, (data_node_ip, opts, opts.oid, use_oid, ecs_version))
    elif opts.o_file != "":
        use_oid = True
        oids = file_to_list(opts.o_file)
        #Execute options, handling broken pipe if pipe to head/tail
        main_opt_pipe_exit(main_lookup, (data_node_ip, opts, oids, use_oid, ecs_version))
    elif opts.c_file != "":
        chunk_ids = file_to_list(opts.c_file)
        #Execute options, handling broken pipe if pipe to head/tail
        main_opt_pipe_exit(main_lookup, (data_node_ip, opts, chunk_ids, use_oid, ecs_version))
    else:
        optparser.print_help()
        print "\nERROR: Invalid option"
        sys.exit(FAILURE)

    sys.exit(SUCCESS)

if __name__ == '__main__':
    main()
