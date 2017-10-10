#!/usr/bin/python
# __CR__
# Copyright (c) 2016-2017 EMC Corporation
# All Rights Reserved
#
# This software is protected, without limitation, by copyright law
# and international treaties. Use of this software and the intellectual property
# contained therein is expressly limited to the terms and conditions of the
# License Agreement under which it is provided by or on behalf of EMC.
# __CR__
#
#
#   Authors:  Jason Klein
#   Version:  1.0.0
#   Created:  2016/12/08
#
#   1.0.0.0  2016/12/09  Initial build
#   1.0.0.1  2016/12/10  Add options -D (debug details) and -E (debug extra cmommands)
#                        Fix issue where fixed IP was present instead of hostname -i
#                        Added hostname function to provide other functions physical public IP
#   1.0.5.0  2016/12/10  Added options t/show_token, u/user, p/password, o/object_list, i/ip_diagnostic
#                        --> I/ip_public, k/secret_key
#   1.0.7.0  2017/01/10  Added Object ID in output for list of clips
#                        Fixed issue where MAP wouldn't display when key or pea option was not used
#                        Added support where tool can now be run in container
#                        Fixed rare crash when variable mapped does not exist
#   1.0.8.0  2017/02/08  Fixed pool name issue due to change in 1.0.7.0
#                        Fixed issue where false / positive "object not found" on existance check
#                        --> Tool will now search both objectname and object ID should the first return error
#                        Added additional support for ECS 2.x
#   1.0.9.0  2017/02/14  Fixed crash when checking clips in list for existance, caused by fix in 1.0.8.0
#                        Fixed bug since initial build where delete time showed as create time
#                        --> Uncovered this bug from fix in 1.0.8.0.
#                        Redisigned function "del_chk".  Simpler and more efficient
#                        Added function "time_conv" for timestamp conversion
#                        Added more debug messages
#                        Added notification when NS has no buckets, that it can't be mapped
#   1.1.0.0  2017/02/16  Correct cosmetics where Bucket Owner was reported as User
#   2.0.0.0  2017/03/24  Added additional mapping for namespace and users in addition to bucket owners.  Secrets and passwords are optional
#                        Added options -x, -y and -z to disable specific map printing
#                        Added User name in print for function "del_chk"
#                        Added additional mapping for Namespace, Bucket and associated Users (by ACL)
#                        Added option -s, --secrets, to Generate secrets and PEA file for specific ns and user
#                        Added option -S, --sleep for sleep time of between 500 and 10000 MS (default = 500) in loops running API commands.
#                        --> This helps large ECS sites from getting overwhelemd from enumeration.
#                        Fixed issue with long options which require an argument.
#                        Added retry logic for when API call fails
#                        Added options -R, --retry, -T, --retry_sleep for retry logic configuration
#   2.0.1.0  2017/03/28  Added cosmetics for easier to read output.
#                        Added message to indicate when the tool is finished and will exit.
#                        Added checks to determine supplied object or clip list exists. If not, tool will exit
#                        Improved performance in function "del_chk".  This will make checking for objects and clips faster
#                        Fixed crash if user is not found in metadata of object/clip being checked.  Crash was introduced in v2.0.0.0
#                        Added option -O, --order. Order in how delete check performs ("objectid" or "objectname"). Order improves performance
#                        --> Default is "objectname"
#  2.0.2.0  2017/04/11   Fixed minor bug when -i and I are not used
#                        Added option -B --bypass. This allows spcification of namespace and bucket when checking status of each object or clip.
#                        --> This bypasses the required namespace and bucket mapping process.
#                        Fixed incorrect Delete timestamp issue.
#                        Updated messages
#
# To do:
# --> Check object list for "/" characters and report error if found.  Basically prevent trace back on bad list.
# --> Enhance to supply Swift password:
#     ----> curl -s -H "$tok" -i -k -X GET https://10.246.23.75:4443/object/user-password/oc_user_swift
# --> Modify coding style
# --> Option to build clip lists, mapping to correct user
#
###############################################################################

import sys
import os
import datetime
import time
import commands
import getopt
import traceback
import re
import itertools

def timestamp():

        """
        Generate TimeStamp for all Functions:
        """

        current_time = datetime.datetime.now().strftime("[%m-%d-%Y_%H:%M:%S]:")
        return current_time

def tok(ip, un, pw, retry, retry_sleep):

        """
        Generate Token:
        """

        tok_cmd = 'curl -iks https://%s:4443/login -u %s:%s | grep X-SDS-AUTH-TOKEN' % (ip, un, pw)
        retry_cmd = tok_cmd
        tok_cmd, tok = commands.getstatusoutput(tok_cmd)

        err_chk = api_err_chk(tok, retry_cmd, retry, retry_sleep)
        err_chk_res = (err_chk['error'])
        if err_chk_res == True: tok = (err_chk['cmd_res'])

        if tok == '': print 'Token cannot be generated', sys.exit()

        return {'tok' :tok.replace(' ', '')}

def namespace(tok, debug, debug_d, debug_e, ip, retry, retry_sleep):

        """
        Get namespace:
        """

        tok_pre = tok.split()
        tok = '\n'.join(tok_pre)

        namespace = []

        # Collect

        if debug == True: print; print timestamp()+'Get Namespaces'; print

        ns_cmd = 'curl -ks -H "%s"  https://%s:4443/object/namespaces | xmllint --format -' % (tok, ip)
        retry_cmd = ns_cmd
        if debug_e == True: print; print timestamp()+ ns_cmd; print

        ns_cmd, ns_raw = commands.getstatusoutput(ns_cmd)

        err_chk = api_err_chk(ns_raw, retry_cmd, retry, retry_sleep)
        err_chk_res = (err_chk['error'])
        if err_chk_res == True: ns_raw = (err_chk['cmd_res'])

        ns = ns_raw.split("\n")

        if debug_e == True: print; print timestamp()+'ns_cmd_results:\n'; print ns; print

        # Search

        if debug_d == True: print; print timestamp()+'Search ns output for ns\'s'; print

        count = 0

        while (count < len(ns)):

                name_chk = re.search(('    <name>.*'), ns[count])

                if name_chk != None:

                        name = re.search(('    <name>.*'), ns[count]).group().split('>')[1].split('<')[0]

                        if debug_e == True: print; print timestamp()+'Search Progress:\n%s\n' % name

                        namespace.append(name)

                count = count + 1

        if debug_e == True: print; print timestamp()+'Namespace list:'; print namespace; print

        return{'namespace' :namespace}

def bucket(tok, ns, debug, debug_d, debug_e, ip, retry, retry_sleep):

        """
        Get namespace with corresponding bucket:
        """

        tok_pre = tok.split()
        tok = '\n'.join(tok_pre)

        bucket_name = []

        # Collect

        if debug == True: print; print timestamp()+'Get Bucket info:\n'

        ns_bucket_cmd = 'curl -s -k -X GET -H "%s" https://%s:4443/object/billing/namespace' % (tok, ip)
        ns_bucket_cmd += '/%s/info?include_bucket_detail=true | xmllint --format -' % ns
        retry_cmd = ns_bucket_cmd
        if debug_e == True: print; print timestamp()+'Bucket cmd:\n%s\n' % ns_bucket_cmd

        ns_bucket_cmd, ns_bucket_raw = commands.getstatusoutput(ns_bucket_cmd)

        err_chk = api_err_chk(ns_bucket_raw, retry_cmd, retry, retry_sleep)
        err_chk_res = (err_chk['error'])
        if err_chk_res == True: ns_bucket_raw = (err_chk['cmd_res'])

        ns_bucket = ns_bucket_raw.split("\n")

        if debug_e == True: print; print timestamp()+'Bucket cmd result:\n%s\n' % ns_bucket

        if str('No buckets exist') in ns_bucket_raw:
                print '--> NOTE: NAMESPACE "%s" cannot be mapped as it has no assigned buckets.' % ns; print

        # Search

        count = 0

        while (count < len(ns_bucket)):

                bucket_ns_chk = re.search(('    <name>.*'), ns_bucket[count])

                if bucket_ns_chk != None:

                        bucket_ns = re.search(('    <name>.*'), ns_bucket[count]).group().split('>')[1].split('<')[0]

                        if debug_e == True: print; print timestamp()+'Search Progress:\n%s\n' % bucket_ns

                        bucket_name.append('%s/info?namespace=%s' % (bucket_ns, ns))

                count = count + 1

        if debug_e == True: print; print timestamp()+'bucket_name list:\n%s\n' % bucket_name

        return{'bucket_name' :bucket_name}

def map_bucket(tok, bucket_names, debug, debug_d, debug_e, ip, sleep, retry, retry_sleep):

        """
        Map namespace to bucket and owner:
        """

        tok_pre = tok.split()
        tok = '\n'.join(tok_pre)

        bucket_name_pre = '\n'.join(bucket_names)
        bucket_name = bucket_name_pre.split()

        ns = ''
        bucket = ''
        owner = ''

        ns_own_bucket_map = []

        # Collect and search

        if debug == True: print 'Map NS and Buckets to Owner(s)'; print

        count = 0

        while (count < len(bucket_name)):


                ns_bucket_cmd = 'curl -s -k -X GET -H "%s" https://%s:4443/object/bucket' % (tok, ip)
                ns_bucket_cmd += '/%s | xmllint --format -' % bucket_name[count]
                retry_cmd = ns_bucket_cmd
                if debug_d == True: print 'ns bucket cmd:\n%s\n' % ns_bucket_cmd

                ns_bucket_cmd, ns_bucket = commands.getstatusoutput(ns_bucket_cmd)

                err_chk = api_err_chk(ns_bucket, retry_cmd, retry, retry_sleep)
                err_chk_res = (err_chk['error'])
                if err_chk_res == True: ns_bucket = (err_chk['cmd_res'])

                if debug_e == True: print 'ns bucket cmd result:\n%s\n' % ns_bucket

                ns_chk = re.search(('  <namespace>.*'), ns_bucket)

                bucket_chk = re.search(('  <name>.*'), ns_bucket)
                owner_chk = re.search(('  <owner>.*'), ns_bucket)

                if ns_chk != None:
                        ns = re.search(('  <namespace>.*'), ns_bucket).group().split('>')[1].split('<')[0]

                if bucket_chk != None:
                        bucket = re.search(('  <name>.*'), ns_bucket).group().split('>')[1].split('<')[0]

                if owner_chk != None:
                        owner = re.search(('  <owner>.*'), ns_bucket).group().split('>')[1].split('<')[0]

                ns_own_bucket_map.append('%s:%s:%s' % (ns, bucket, owner))

                if debug_e == True: print 'ns_own_bucket_map list:\n%s\n' % ns_own_bucket_map

                time.sleep(sleep)

                count = count + 1

        return{'ns_own_bucket_map' :ns_own_bucket_map}

def collector(token, debug, debug_d, debug_e, ip, key, pea, sleep, retry, retry_sleep):

        """
        Collect data and build map:
        """

        token_pre = token.split()
        token = '\n'.join(token_pre)

        users = False
        mapped_pre = []
        mapped = []
        mapped_key = []
        mapped_only = []

        ns_run = namespace (token, debug, debug_d, debug_e, ip, retry, retry_sleep)
        ns = (ns_run['namespace'])

        count = 0

        while (count < len(ns)):

                bucket_run = bucket (token, ns[count], debug, debug_d, debug_e, ip, retry, retry_sleep)
                buckets = (bucket_run['bucket_name'])

                map_run = map_bucket(token, buckets, debug, debug_d, debug_e, ip, sleep, retry, retry_sleep)
                map_result = (map_run['ns_own_bucket_map'])

                if map_result != []:
                        mapped_pre.append(map_result)
                        mapped = list(itertools.chain.from_iterable(mapped_pre))

                        for line in map_result:
                                mapped_only.append('NAMESPACE:%s: BUCKET:%s: OWNER:%s' % (line.split(':')[0], line.split(':')[1], line.split(':')[2]))

                count = count + 1

        if key == True or pea == True:

                if debug == True and key == True: print timestamp()+'Get Owner Key'
                if debug == True and pea == True: print timestamp()+'Get Owner Pea File'

                count = 0

                while (count < len(mapped)):
                        s_keys_run = s_keys (token, debug, debug_d, debug_e, mapped[count], ip, key, pea, users, sleep, retry, retry_sleep)
                        s_key = (s_keys_run['secret'])
                        if s_key != []: mapped_key.append(s_key)

                        count = count + 1

        return{'mapped' :mapped, 'mapped_only' :mapped_only, 'mapped_key' :mapped_key}

def get_users(tok, ip, retry, retry_sleep):

        """
        Get namespace and its users:
        """

        tok_pre = tok.split()
        tok = '\n'.join(tok_pre)

        ns_user_list = []

        get_user_cmd = 'curl -ks -H "%s"  https://%s:4443/object/users | xmllint --format -' % (tok, ip)
        retry_cmd = get_user_cmd
        get_user_cmd, get_user_raw = commands.getstatusoutput(get_user_cmd)

        err_chk = api_err_chk(get_user_raw, retry_cmd, retry, retry_sleep)
        err_chk_res = (err_chk['error'])
        if err_chk_res == True: get_user_raw = (err_chk['cmd_res'])

        get_user = get_user_raw.split("\n")

        count = 0

        while (count < len(get_user)):

                ns_chk = re.search(('.*<namespace>.*'), get_user[count])
                if ns_chk != None:
                        ns = re.search(('.*<namespace>.*'), get_user[count]).group().split('>')[1].split('<')[0]

                usr_chk = re.search(('.*<userid>.*'), get_user[count])
                if usr_chk != None:
                        usr = re.search(('.*<userid>.*'), get_user[count]).group().split('>')[1].split('<')[0]
                        ns_user_list.append('%s:%s' % (ns, usr))

                count = count + 1

        return {'ns_user_list' :ns_user_list}

def usr_acl(tok, debug, debug_d, debug_e, ip, map, sleep, retry, retry_sleep):

        """
        Collect bucket user Acl's:
        """

        tok_pre = tok.split()
        tok = '\n'.join(tok_pre)

        users = True
        bkt_acl_usr = []
        temp = ''
        linked_usr = ''

        count = 0

        while (count < len(map)):

                temp = 'NAMESPACE:%s: BUCKET:%s: USERS:' % (map[count].split(':')[1], map[count].split(':')[3])

                acl_cmd = 'curl -s -k -H %s https://%s:4443/object/bucket/%s/acl?namespace=%s | xmllint --format -' % (tok, ip, map[count].split(':')[3], map[count].split(':')[1])
                retry_cmd = acl_cmd
                acl_cmd, acl = commands.getstatusoutput(acl_cmd)

                err_chk = api_err_chk(acl, retry_cmd, retry, retry_sleep)
                err_chk_res = (err_chk['error'])
                if err_chk_res == True: acl = (err_chk['cmd_res'])

                acl_usr_chk = re.search(('.*<user>.*'), acl)
                if acl_usr_chk != None:
                        acl_usr = re.findall(('.*<user>.*'), acl)

                        sub_count = 0
                        while (sub_count < len(acl_usr)):

                                acl_usr_trim = acl_usr[sub_count].split('>')[1].split('<')[0]

                                linked_usr = '%s%s,' % (linked_usr, acl_usr_trim)

                                sub_count = sub_count + 1

                        temp = '%s%s' % (temp, linked_usr[:-1])

                        bkt_acl_usr.append('%s' % temp)

                        temp = ''
                        linked_usr = ''

                time.sleep(sleep)

                count = count + 1

        return {'bkt_acl_usr' :bkt_acl_usr}

def user_collector(token, debug, debug_d, debug_e, ip, key, pea, sleep, retry, retry_sleep):

        """
        Collect user data and build map:
        """

        token_pre = token.split()
        token = '\n'.join(token_pre)

        users = True

        run_get_users = get_users(token, ip, retry, retry_sleep)
        ns_user_list = (run_get_users['ns_user_list'])

        mapped = []
        mapped_key = []

        count = 0

        while (count < len(ns_user_list)):

                mapped.append('NAMESPACE:%s: USER:%s' % (ns_user_list[count].split(':')[0], ns_user_list[count].split(':')[1]))

                count = count + 1

        if key == True or pea == True:

                if debug == True and key == True: print timestamp()+'Get User Key'
                if debug == True and pea == True: print timestamp()+'Get User Pea File'

                count = 0

                while (count < len(mapped)):
                        s_keys_run = s_keys (token, debug, debug_d, debug_e, mapped[count], ip, key, pea, users, sleep, retry, retry_sleep)
                        s_key = (s_keys_run['secret'])
                        if s_key != []: mapped_key.append(s_key)

                        count = count + 1

        return{'mapped' :mapped, 'mapped_key' :mapped_key}

def s_keys(token, debug, debug_d, debug_e, map, ip, key, pea, users, sleep, retry, retry_sleep):

        """
        Get secret and PEA file:
        """

        token_pre = token.split()
        token = '\n'.join(token_pre)

        s3_chk = None
        found_secret = False
        found_pea = False
        secret = ''
        cas_secret = ''
        cas_pea = ''

        if key == True:
                if users == False:
                        s3_cmd = 'curl -s -H %s -i -k -X GET https://%s:4443/object/user-secret-keys/%s | grep \'<\' | xmllint --format -' % (token, ip, map.split(':')[2])
                        retry_cmd = s3_cmd
                if users == True:
                        s3_cmd = 'curl -s -H %s -i -k -X GET https://%s:4443/object/user-secret-keys/%s | grep \'<\' | xmllint --format -' % (token, ip, map.split(':')[3])
                        retry_cmd = s3_cmd
                if debug_d == True: print; print timestamp()+'COMMAND: %s' % s3_cmd
                s3_cmd, s3 = commands.getstatusoutput(s3_cmd)

                err_chk = api_err_chk(s3, retry_cmd, retry, retry_sleep)
                err_chk_res = (err_chk['error'])
                if err_chk_res == True: s3 = (err_chk['cmd_res'])

                s3_chk = re.search(('  <secret_key_1>.*'), s3)

                if s3_chk != None:
                        s3_key = re.search(('  <secret_key_1>.*'), s3).group().split('>')[1].split('<')[0]
                        if users == False:
                                secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: S3_SECRET:%s' % (map.split(':')[0], map.split(':')[1], map.split(':')[2], s3_key)
                        if users == True:
                                secret = 'NAMESPACE:%s: USER:%s: S3_SECRET:%s' % (map.split(':')[1], map.split(':')[3], s3_key)
                        found_secret = True

                if users == False:
                        cas_cmd = 'curl -s -k -H %s https://%s:4443/object/user-cas/secret/%s/%s | xmllint --format -' % (token, ip, map.split(':')[0], map.split(':')[2])
                        retry_cmd = cas_cmd
                if users == True:
                        cas_cmd = 'curl -s -k -H %s https://%s:4443/object/user-cas/secret/%s/%s | xmllint --format -' % (token, ip, map.split(':')[1], map.split(':')[3])
                        retry_cmd = cas_cmd
                if debug_d == True: print; print timestamp()+'COMMAND: %s' % cas_cmd
                cas_cmd, cas = commands.getstatusoutput(cas_cmd)

                err_chk = api_err_chk(cas, retry_cmd, retry, retry_sleep)
                err_chk_res = (err_chk['error'])
                if err_chk_res == True: cas = (err_chk['cmd_res'])

                cas_chk = re.search(('  <cas_secret>.*'), cas)

                if cas_chk != None and s3_chk == None:
                        cas_secret = re.search(('  <cas_secret>.*'), cas).group().split('>')[1].split('<')[0]
                        if users == False:
                                secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: CAS_SECRET:%s' % (map.split(':')[0], map.split(':')[1], map.split(':')[2], cas_secret)
                        if users == True:
                                secret = 'NAMESPACE:%s: USER:%s: CAS_SECRET:%s' % (map.split(':')[1], map.split(':')[3], cas_secret)
                        found_secret = True

                if cas_chk != None and s3_chk != None:
                        cas_secret = re.search(('  <cas_secret>.*'), cas).group().split('>')[1].split('<')[0]
                        if users == False:
                                secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: S3_SECRET:%s: CAS_SECRET:%s' % (map.split(':')[0], map.split(':')[1], map.split(':')[2], s3_key, cas_secret)
                        if users == True:
                                secret = 'NAMESPACE:%s: USER:%s: S3_SECRET:%s: CAS_SECRET:%s' % (map.split(':')[1], map.split(':')[3], s3_key, cas_secret)
                        found_secret = True

        if pea == True:

                if users == False:
                        cas_cmd = 'curl -s -k -H %s https://%s:4443/object/user-cas/secret/%s/%s/pea | xmllint --format -' % (token, ip, map.split(':')[0], map.split(':')[2])
                        retry_cmd = cas_cmd
                if users == True:
                        cas_cmd = 'curl -s -k -H %s https://%s:4443/object/user-cas/secret/%s/%s/pea | xmllint --format -' % (token, ip, map.split(':')[1], map.split(':')[3])
                        retry_cmd = cas_cmd
                if debug_d == True: print; print timestamp()+'COMMAND: %s' % cas_cmd
                cas_cmd, cas = commands.getstatusoutput(cas_cmd)

                err_chk = api_err_chk(cas, retry_cmd, retry, retry_sleep)
                err_chk_res = (err_chk['error'])
                if err_chk_res == True: cas = (err_chk['cmd_res'])

                cas_chk = re.search(('<pea .*'), cas)

                if cas_chk != None:
                        cas_pea_pre_0 = re.findall(('.*'), cas)
                        cas_pea = ''.join(cas_pea_pre_0).replace('><', '>\n<').replace('>  <', '>\n  <').replace('>    <', '>\n    <')

                        if users == False and key == False: secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: CAS_PEA:\n%s' % (map.split(':')[0], map.split(':')[1], map.split(':')[2], cas_pea)
                        if users == True and key == False: secret = 'NAMESPACE:%s: USER:%s: CAS_PEA:\n%s' % (map.split(':')[1], map.split(':')[3], cas_pea)

                        if users == False and key == True and s3_chk == None: secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: CAS_SECRET:%s: CAS_PEA:\n%s' % (map.split(':')[0], map.split(':')[1], map.split(':')[2], cas_secret, cas_pea)
                        if users == True and key == True and s3_chk == None: secret = 'NAMESPACE:%s: USER:%s: CAS_SECRET:%s: CAS_PEA:\n%s' % (map.split(':')[1], map.split(':')[3], cas_secret, cas_pea)

                        if users == False and key == True and s3_chk != None: secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: S3_SECRET:%s: CAS_SECRET:%s: CAS_PEA:\n%s' % (map.split(':')[0], map.split(':')[1], map.split(':')[2], s3_key, cas_secret, cas_pea)
                        if users == True and key == True and s3_chk != None: secret = 'NAMESPACE:%s: USER:%s: S3_SECRET:%s: CAS_SECRET:%s: CAS_PEA:\n%s' % (map.split(':')[1], map.split(':')[3], s3_key, cas_secret, cas_pea)

                        found_pea = True

        if users == False and found_secret == False and key == True and pea == False: secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: SECRET:NOT_FOUND' % (map.split(':')[0], map.split(':')[1], map.split(':')[2])
        if users == True and found_secret == False and key == True and pea == False: secret = 'NAMESPACE:%s: USER:%s: SECRET:NOT_FOUND' % (map.split(':')[1], map.split(':')[3])


        if users == False and found_pea == False and pea == True and key == False: secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: SECRET:NA: PEA:NOT_FOUND' % (map.split(':')[0], map.split(':')[1], map.split(':')[2])
        if users == True and found_pea == False and pea == True and key == False: secret = 'NAMESPACE:%s: USER:%s: SECRET:NA: PEA:NOT_FOUND' % (map.split(':')[1], map.split(':')[3])


        if users == False and found_pea == False and found_secret == False and pea == True and key == True: secret = 'NAMESPACE:%s: BUCKET:%s: OWNER:%s: SECRET:NOT_FOUND: PEA:NOT_FOUND' % (map.split(':')[0], map.split(':')[1], map.split(':')[2])
        if users == True and found_pea == False and found_secret == False and pea == True and key == True: secret = 'NAMESPACE:%s: USER:%s: SECRET:NOT_FOUND: PEA:NOT_FOUND' % (map.split(':')[1], map.split(':')[3])

        time.sleep(sleep)

        return{'secret' :secret}

def logout(token, debug, debug_d, debug_e, ip, retry, retry_sleep):

        """
        Logout
        """

        token_pre = token.split()
        token = '\n'.join(token_pre)

        if debug == True: print timestamp()+'Logging out'; print

        logout_cmd = 'curl -s -k -H "%s" -X GET https://%s:4443/logout?force=true' % (token, ip)
        logout_cmd += ' | xmllint --format - '
        retry_cmd = logout_cmd
        logout_cmd, logout = commands.getstatusoutput(logout_cmd)

        err_chk = api_err_chk(logout, retry_cmd, retry, retry_sleep)
        err_chk_res = (err_chk['error'])
        if err_chk_res == True: logout = (err_chk['cmd_res'])

        if debug == True: print timestamp()+'Logged out'; print

        return{'logout' :logout}

def time_conv(time_val, retry, retry_sleep):

        """
        Convert time
        """

        time_pre = re.search(('.*value.*'), time_val).group().split('"')[1]
        time_convert_cmd = 'date +%%m-%%d-%%Y_%%H-%%M-%%S-%%Z -d @%s' % time_pre[:-3]
        retry_cmd = time_convert_cmd
        time_convert_cmd, time_convert = commands.getstatusoutput(time_convert_cmd)

        err_chk = api_err_chk(time_convert, retry_cmd, retry, retry_sleep)
        err_chk_res = (err_chk['error'])
        if err_chk_res == True: time_convert = (err_chk['cmd_res'])

        return{'time_convert' :time_convert}

def del_chk(token, oc_list, list_type, map, debug, debug_d, debug_e, ip, chunkid, sleep, retry, retry_sleep, order):

        """
        Check if Objects or clips have been deleted
        """

        token_pre = token.split()
        token = '\n'.join(token_pre)

        match_format = ''
        chunk_id = ''
        oid = ''

        f1 = open(oc_list, 'r')
        oc_file = f1.readline()[:-1]

        if order != 'objectid' and order != 'objectname': order = 'objectname'

        chk2 = 'objectid'
        if order == 'objectid': chk2 = 'objectname'

        print '%s Map and Status Check:' % list_type; print

        # Get object info:

        while (oc_file != ''):

                matched = False
                deleted = False
                count = 0

                while (count < len(map) and matched == False):

                        if debug == True: print; print timestamp()+'Attempting to match object %s against namespace %s and bucket %s' % (oc_file, map[count].split(':')[1], map[count].split(':')[3]); print
                        chk_cmd = 'curl -s \'http://%s:9101/diagnostic/object/showinfo?poolname=%s%s%s&%s=%s&showvalue=gpb\'' % (ip, map[count].split(':')[1], '.', map[count].split(':')[3], order, oc_file)
                        retry_cmd = chk_cmd
                        if debug_d == True: print; print timestamp()+'COMMAND: %s' % chk_cmd
                        chk_cmd, chk = commands.getstatusoutput(chk_cmd)

                        err_chk = api_err_chk(chk, retry_cmd, retry, retry_sleep)
                        err_chk_res = (err_chk['error'])
                        if err_chk_res == True: chk = (err_chk['cmd_res'])

                        match_chk = re.search(('.*key:.*'), chk)
                        if debug_d == True: print; print timestamp()+'RESULT: \n%s' % chk

                        if match_chk == None:

                                if debug_d == True: print; print timestamp()+'1st check failed.  Run 2nd and final check.'
                                chk_cmd = 'curl -s \'http://%s:9101/diagnostic/object/showinfo?poolname=%s%s%s&%s=%s&showvalue=gpb\'' % (ip, map[count].split(':')[1], '.', map[count].split(':')[3], chk2, oc_file)
                                retry_cmd = chk_cmd
                                if debug_d == True: print; print timestamp()+'COMMAND: %s' % chk_cmd
                                chk_cmd, chk = commands.getstatusoutput(chk_cmd)

                                err_chk = api_err_chk(chk, retry_cmd, retry, retry_sleep)
                                err_chk_res = (err_chk['error'])
                                if err_chk_res == True: chk = (err_chk['cmd_res'])

                                match_chk = re.search(('.*key:.*'), chk)
                                if debug_d == True: print; print timestamp()+'RESULT: \n%s' % chk

                        if match_chk != None:

                                # Get Create (first found) and Modification Timestamps (last found):
                                # findall not used as wildcard is needed

                                c_time_stamp_0_chk = re.search(('    key: "createtime".*\n.*'), chk)
                                if c_time_stamp_0_chk != None: c_time_stamp_0 = re.search(('    key: "createtime".*\n.*'), chk).group()
                                else: c_time_stamp_0 = ''

                                mod_time_stamp_0_chk = re.search(('.*key: "mtime".*\n.*(?!.*key: "mtime".*\n.*)'), chk)
                                if mod_time_stamp_0_chk != None:

                                        m_time_stamp_0 = re.findall(('.*key: "mtime".*\n.*'), chk)

                                        del_count = 0
                                        while (del_count < len(m_time_stamp_0)):

                                                m_time_stamp_0_mod = m_time_stamp_0[del_count]
                                                del_count = del_count + 1

                                        m_time_stamp_0 = m_time_stamp_0_mod

                                else: m_time_stamp_0 = ''

                                if str('value') in c_time_stamp_0:

                                        c_conv_run = time_conv(c_time_stamp_0, retry, retry_sleep)
                                        c_time_stamp = (c_conv_run['time_convert'])

                                else: c_time_stamp = ''

                                if str('value') in m_time_stamp_0:

                                        m_conv_run = time_conv(m_time_stamp_0, retry, retry_sleep)
                                        m_time_stamp = (m_conv_run['time_convert'])

                                else: m_time_stamp = ''

                                # Get Chunk ID:

                                chunk_id_chk = re.search(('    chunkId:.*'), chk)
                                if chunk_id_chk != None: chunk_id = re.search(('    chunkId:.*'), chk).group().split('>')[1].split('<')[0]
                                else: chunk_id = ''

                                # Get Object ID:

                                oid_chk = re.search(('.*objectId.*'), chk)
                                if oid_chk != None: oid = re.search(('.*objectId.*'), chk).group().split()[3]
                                else: oid = ''

                                # Get User:

                                usr_chk = re.search(('.*key: "creation.profile".*\n.*'), chk)
                                if usr_chk != None: usr = re.search(('.*key: "creation.profile".*\n.*'), chk).group()
                                else: usr = ''

                                usr_val_chk = re.search(('.*value.*'), usr)
                                if usr_val_chk != None: usr_val = re.search(('.*value.*'), usr).group().split('"')[1]
                                else: usr_val = 'NOT_FOUND'

                                # Check if object was actually deleted:

                                d_chk = re.search(('.*key: "deletedsize".*\n.*'), chk)

                                if d_chk == None:
                                        d_chk = re.search(('.*key: "dmarker".*\n.*'), chk)

                                if d_chk != None: deleted = True

                                if deleted == True:

                                        # Check for reflection timestamp and incoming IP:

                                        match_del_ip_chk = re.search(('  key: "incomingip".*\n.*'), chk)
                                        if match_del_ip_chk != None:
                                                match_del_ip_chk = re.search(('  key: "incomingip".*\n.*'), chk).group()
                                                match_format_1 = re.search(('.*value.*'), match_del_ip_chk).group().split('"')[1]
                                                if match_del_ip_chk == None: match_format_1 = 'Unknown'

                                        else: match_format_1 = 'NA'

                                        match_format = '%s:DELETE_TIMESTAMP=%s:INCOMING_IP:%s' % ('False', m_time_stamp, match_format_1)

                                else:
                                        match_format = '%s:CREATE_TIMESTAMP=%s' % ('True', c_time_stamp)

                                # Print results:

                                if chunkid == False and list_type == 'OBJECT':
                                        print '    %s:%s:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                elif chunkid == True and chunk_id == '' and list_type == 'OBJECT':
                                        print '    %s:%s:CHUNK_ID:NOT_FOUND:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                elif chunkid == True and chunk_id != '' and list_type == 'OBJECT':
                                        print '    %s:%s:CHUNK_ID:%s:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, chunk_id, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                if chunkid == False and list_type == 'CLIP':
                                        print '    %s:%s:OBJECT:%s:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, oid, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                elif chunkid == True and chunk_id == '' and oid == '' and list_type == 'CLIP':
                                        print '    %s:%s:OBJECT:NOT_FOUND:CHUNK_ID:NOT_FOUND:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                elif chunkid == True and chunk_id == '' and oid != '' and list_type == 'CLIP':
                                        print '    %s:%s:OBJECT:%s:CHUNK_ID:NOT_FOUND:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, oid, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                elif chunkid == True and chunk_id != '' and oid == '' and list_type == 'CLIP':
                                        print '    %s:%s:OBJECT:NOT_FOUND:CHUNK_ID:%s:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, chunk_id, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                elif chunkid == True and chunk_id != '' and oid != '' and list_type == 'CLIP':
                                        print '    %s:%s:OBJECT:%s:CHUNK_ID:%s:NAMESPACE:%s:BUCKET:%s:OWNER:%s:USER:%s:EXISTS=%s' % (list_type, oc_file, oid, chunk_id, map[count].split(':')[1], map[count].split(':')[3], map[count].split(':')[5], usr_val, match_format)

                                matched = True

                        time.sleep(sleep)

                        count = count + 1

                if matched == False: print '    Could not find a match for %s %s' % (list_type, oc_file)

                oc_file = f1.readline()[:-1]

        f1.close()
        print

def public_ip(debug, debug_d, debug_e, retry, retry_sleep):

        """
        Get public IP of current node
        """

        ip_cmd = 'hostname -i'
        ip_cmd, ip = commands.getstatusoutput(ip_cmd)

        if debug_d == True: print; print timestamp()+'IP: %s' % ip

        return{'ip' :ip}

def print_map(map, map_keys, ez_map_format, acl):

        """
        Print Map
        """

        print 'MAP:'

        if map_keys != []:

                map_format = '\n'.join(map_keys)
                maps = map_format.split('\n')

        else:
                map_format = '\n'.join(map)
                maps = map_format.split('\n')

        count = 0

        while (count < len(maps)):

                if acl == False and str('<') not in maps[count] and ez_map_format == False:
                        if count == 0: print
                        print '    %s' % maps[count].replace(': ', ' ')

                elif acl == False and str('<') not in maps[count] and ez_map_format == True and str('NAMESPACE') in maps[count]: print '    %s' % maps[count].replace(': ', '\n').replace('NAMESPACE', '\nNAMESPACE')

                elif acl == False and str('<') in maps[count]:
                        if maps[count] != '': print '    %s' % maps[count]

                elif acl == True and ez_map_format == False:
                        if count == 0: print
                        print '    %s' % maps[count]

                elif acl == True and ez_map_format == True and str('NAMESPACE') in maps[count]: print '    %s' % maps[count].replace(': ', '\n').replace('NAMESPACE', '\nNAMESPACE')

                count = count + 1
        print

        return{'map_format' :map_format, 'map' :map}

def api_err_chk(result, api_cmd, retry, retry_sleep):

        """
        Check for API error
        """

        error = False
        cmd_res = ''

        if str('<code>6503</code>') in result:
                print '--> ERROR: API Error Code 6503 detected. Map could be blank.' \
                ' Will retry again.\n'
                error = True

                count = 0

                while (count < int(retry) and error == True):

                        time.sleep(retry_sleep)
                        cmd_pre = api_cmd
                        cmd_pre, cmd_res = commands.getstatusoutput(cmd_pre)

                        if str('<code>6503</code>') not in cmd_res: error = False

                        count = count + 1

                if error == True: print '--> All %s retries failed.  Map will be incomplete. However, will continue...\n' % count
                if error == False: print '--> Success on %s retries.  Will continue...\n' % count

        return {'error' :error, 'cmd_res' :cmd_res}

def run ():


        options = """
oc_map performs the following:

1) Maps namespace, bucket, and owner.
2) Maps namespace and users.
3) Maps namespace, bucket and Associated Users (by ACL).
4) Option to generate secrets, passwords, PEA file for specific user.
5) Provides S3 secret, Swift Secret, CAS secret, CAS PEA for bucket owners and users.
6) Checks the status of each object or clip, against all namespace and bucket combinatations:
--> Maps the clip or object to the corresponding namespace, bucket, and user.
--> Reports status, Exists, Deleted, creation time, Reflection time, and Incoming IP.
--> Supplies Chunk ID.
7) Option to use specific namespace and bucket when checking status of each object or clip.
--> This bypasses the required namespace bucket mapping process.

Options:

-h, --help                     "Usage"
-c  --clip_list                "File Path of clip list"
-d  --debug                    "Enable Debug Messages"
-D  --debug_detail             "debug details"
-E  --debug_extra              "debug extra commands"
-t  --show_token               "Show Token"
-u  --user                     "user name"
-p  --password                 "password"
-o  --object_list              "File Path to object list"
                               --> NOTE: List can contain file names (without dir and \"/\") or object ID's
-i  --ip_diagnostic            "dianostic ip"
-I  --ip_public                "public ip"
-k  --key                      "secret key"
-P  --pea                      "pea file"
-C  --chunk_id                 "Show Chunk ID"
-f  --ez_map_format            "easy map format"
-x  --disable_bkt_usr_print    "Disable mapping and print of bkt, usr acls"
-y  --disable_ns_bkt_own_print "Disable print of ns, bkt, own"
-z  --disable_ns_usr_print     "Disable mapping and print of ns, usr"
-s  --secrets                  "Generate secrets for specific ns and user"
                               --> Example: -s <namespace>:<user>
-S  --sleep                    "Sleep in loops (500 - 10000 MS, default = 500)"
                               --> NOTE: If any MAP appears blank, increase sleep time
-R  --retry                    "retries (1 - 10)"
-T  --retry_sleep              "time between retries (1 - 10 Seconds)"
-O  --order                    "Order in how delete check performs ('objectid' or 'objectname'). Order improves performance. Default is 'objectname'"
                               --> NOTE: For list of Clips or S3 File Names, chose "objectname". For list of object id's, chose "objectid"
-B  --bypass                   Specify namespace and bucket when checking status of objects of clips with optoins -o or -c.  Argument <namespace:bucket>

Note: If options -i and / or -I are not used, public IP will be used for default.
--> If network separation is in use, these options are necessary.

Example of usage:

- All Maps with delete check:

--> sudo python -u oc_map.py -u emcservice -p ChangeMe -i 10.xxx.xx.xx -I 10.xxx.xx.xx -k -P -f -C -c /tmp/clips -O objectname -S 1000 -R 5 -T 5

- Delete Check while disabling printing of all maps and generate of 2 out of 3.  This saves time when checking for clips and objects:

--> sudo python -u oc_map.py -u emcservice -p ChangeMe -i 10.xxx.xx.xx -I 10.xxx.xx.xx -f -C -c /tmp/oids -O objectid -x -y -z -S 1000 -R 5 -T 5

- Generate secrets (s3, cas secret, PEA file) for specific ns and user:

--> sudo python -u oc_map.py -u emcservice -p ChangeMe -i 10.xxx.xx.xx -I 10.xxx.xx.xx -f -s ns:user -x -y -z -S 1000 -R 5 -T 5

Note: The -u for python is to not use a buffer.  THis is not needed unless using nohup for sites which take a long time to run.

Example of nohup:

- nohup sudo python -u oc_map.py -u emcservice -p ChangeMe -i 10.xxx.xx.xx -I 10.xxx.xx.xx -k -P -f -C -B namespace:bucket -c /tmp/clips -O objectname -S 1000 -R 5 -T 5 > oc_map.out 2>&1 &

Version: 2.0.2.0

Author: Jason Klein
"""

        help = ''
        clip_list = ''
        object_list = ''
        debug = False
        show_token = False
        debug_d = False
        debug_e = False
        username = ''
        password = ''
        un_exists = False
        p_exists = False
        ip_diag = ''
        ip_public = ''
        key = False
        map_only = True
        ez_map_format = False
        pea = False
        chunkid = False
        d_ns_bkt_own_print = False
        d_ns_usr_print = False
        d_bkt_usr_print = False
        secrets = False
        secrets_val = ''
        sleep = 0.500
        retry = 1
        retry_sleep = 1
        order = 'objectname'
        bypass = False
        bypass_val = ''

        try:
                opts, arg = getopt.getopt(sys.argv[1:],"hc:dDEtu:p:o:i:I:kfPCxyzs:S:R:T:O:B:",["help","clip_list=","debug","debug_detail","debug_extra","show_token","user=","password=","object_list=","ip_diagnostic=","ip_public=","key","ez_map_format","pea","chunk_id","disable_ns_bkt_own_print","disable_ns_usr_print","disable_bkt_usr_print","secrets=","sleep=","retry=","retry_sleep=","order=","bypass="])

        except getopt.GetoptError:
                print options
                sys.exit(2)

        for opt, arg in opts:

                if opt == '-c' or opt == '--clip_list':

                        if not os.path.exists(arg):
                                print 'ERROR: Clip List not found'
                                sys.exit(2)

                        clip_list = arg
                        map_only = False

                        chk_cmd = 'awk \'{ sub("\\r$", ""); print }\' %s 2>/dev/null | head -n 1 2>/dev/null | wc -m' % arg
                        chk_cmd, chk = commands.getstatusoutput(chk_cmd)

                        if int(chk) > 54 or int(chk) < 27:
                                print 'ERROR: Invalid Clip List'
                                sys.exit(2)

                if opt == '-o' or opt == '--object_list':

                        if not os.path.exists(arg):
                                print 'ERROR: Object List not found'
                                sys.exit(2)

                        object_list = arg
                        map_only = False

                if opt == '-u' or opt == '--user':
                        username = arg
                        un_exists = True

                if opt == '-p' or opt == '--password':
                        password = arg
                        p_exists = True

                if opt == '-i' or opt == '--ip_diagnostic':
                        ip_diag = arg

                if opt == '-I' or opt == '--ip_public':
                        ip_public = arg

                if opt == '-k' or opt == '--key':
                        key = True

                if opt == '-d' or opt == '--debug':
                        debug = True

                if opt == '-D' or opt == '--debug_detail':
                        debug_d = True
                        debug = True

                if opt == '-E' or opt == '--debug_extra':
                        debug_e = True
                        debug_d = True
                        debug = True

                if opt == '-t' or opt == '--show_token':
                        show_token = True

                if opt == '-f' or opt == '--ez_map_format':
                        ez_map_format = True

                if opt == '-P' or opt == '--pea':
                        pea = True

                if opt == '-C' or opt == '--chunk_id':
                        chunkid = True

                if opt == '-y' or opt == '--disable_ns_bkt_own_print':
                        d_ns_bkt_own_print = True

                if opt == '-z' or opt == '--disable_ns_usr_print':
                        d_ns_usr_print = True

                if opt == '-x' or opt == '--disable_bkt_usr_print':
                        d_bkt_usr_print = True

                if opt == '-s' or opt == '--secrets':
                        secrets = True
                        secrets_val = arg
                        if secrets_val == '' or ':' not in secrets_val:
                                print '\nERROR: Option "s, secrets dosn\'t have a valid argument."'
                                sys.exit(1)

                if opt == '-B' or opt == '--bypass':
                        bypass = True
                        bypass_val = arg
                        if bypass_val == '' or ':' not in bypass_val:
                                print '\nERROR: Option "B, bypass dosn\'t have a valid argument."'
                                sys.exit(1)

                if opt == '-S' or opt == '--sleep':
                        try:
                                if 500 <= int(arg) <= 10000:
                                        sleep = '0.%s' % int(arg)
                                        sleep = float(sleep)
                                else:
                                        print
                                        print 'Error: Option \"S, sleep\" must be a value 500 - 10000 (MS).\n'
                                        sys.exit(2)
                        except ValueError:
                                print
                                print 'Error: Option \"S, sleep\" must be a value 500 - 10000 (MS).\n'
                                sys.exit(2)

                if opt == '-R' or opt == '--retry':
                        try:
                                if 1 <= int(arg) <= 10:
                                        retry = int(arg)

                                else:
                                        print
                                        print 'Error: Option \"R, retry\" must be a value 1 - 10.\n'
                                        sys.exit(2)
                        except ValueError:
                                print
                                print 'Error: Option \"R, retry\" must be a value 1 - 10.\n'
                                sys.exit(2)

                if opt == '-T' or opt == '--retry_sleep':
                        try:
                                if 1 <= int(arg) <= 10:
                                        retry_sleep = int(arg)
                                        retry_sleep = float(retry_sleep)
                                else:
                                        print
                                        print 'Error: Option \"T, retry_sleep\" must be a value 1 - 10 (S).\n'
                                        sys.exit(2)
                        except ValueError:
                                print
                                print 'Error: Option \"T, retry_sleep\" must be a value 1 - 10 (S).\n'
                                sys.exit(2)

                if opt == '-O' or opt == '--order':
                        order = arg
                        if order != 'objectid' and order != 'objectname':
                                print 'Error: Option \"O, order\" must be a value of \"objectid\" or \"objectname\".\n'
                                sys.exit(2)

                if opt == '-h' or opt == '--help':
                        print options
                        sys.exit(0)

        if not opts or '' in opts:
                print options
                sys.exit(0)

        if un_exists == False or p_exists == False: print 'ERROR: Owner name and password must be supplied'; sys.exit(0)

        if bypass == True:

                if object_list == '' and clip_list == '':
                        print 'Option -B --bypass requires option -o or -c'
                        sys.exit(1)

        if object_list != '' and clip_list != '':
                print 'Options -c and -o cannot be combined.'
                sys.exit(1)

        print '\noc_map_v2.0.2.0\n'

        # Get IP's if options i, I were not chosen:

        if debug_d == True: print; print timestamp()+'Get IP'; print

        if ip_diag == '':
                ip_run = public_ip (debug, debug_d, debug_e, retry, retry_sleep)
                ip_diag = (ip_run['ip'])

        if ip_public == '':
                ip_run = public_ip (debug, debug_d, debug_e, retry, retry_sleep)
                ip_public = (ip_run['ip'])

        # Get Token

        if debug == True: print timestamp()+'Get Token'; print

        tok_run = tok (ip_public, username, password, retry, retry_sleep)
        token = (tok_run['tok'])

        if show_token == True: print timestamp()+'Token %s' % token; print

        # Check and execute option s, secret if it was chosen:

        if secrets == True:
                users = True
                acl = False
                map = ''
                s_key_list = []
                secrets_val_format = 'NAMESPACE:%s: USER:%s' % (secrets_val.split(':')[0], secrets_val.split(':')[1])

                s_keys_run = s_keys(token, debug, debug_d, debug_e, secrets_val_format, ip_public, key, pea, users, sleep, retry, retry_sleep)
                s_key = (s_keys_run['secret'])
                s_key_list.append(s_key)

                if s_key == []:
                        print 'ERROR: Unable to obtain secrets for %s.  Check that this combination is correct.' % secrets_val_format.replace(': ', ' ')
                        sys.exit(1)
                else:
                        print 'Secrets for %s:\n' % secrets_val_format.replace(': ', ' ')
                        print_map(map, s_key_list, ez_map_format, acl)
                        sys.exit(0)

        # Develop Maps:

        if debug == True: print timestamp()+'Develop map'

        # Develop ns, bucket, owner map. Print, if not disabled:

        if bypass == False:
                print 'Mapping Namespaces, Buckets, and Owners... Please be patient'; print
                mapping = collector(token, debug, debug_d, debug_e, ip_public, key, pea, sleep, retry, retry_sleep)
                map = (mapping['mapped_only'])
                map_keys = (mapping['mapped_key'])
                acl = False
                if d_ns_bkt_own_print == False: print_map(map, map_keys, ez_map_format, acl)
                else: print '--> Print of mapping has been disabled\n'

        # Develop bucket and User Acl map, and print, if not disabled:

        print 'Mapping Namespaces, Buckets and Associated Users (by ACL).  For secrets, reference mapping of Namespaces and Users... Please be patient'; print
        if d_bkt_usr_print == False and bypass == False:
                run_usr_acl = usr_acl(token, debug, debug_d, debug_e, ip_public, map, sleep, retry, retry_sleep)
                ns_bkt_usr_map = (run_usr_acl['bkt_acl_usr'])
                map_keys = []
                acl = True
                print_map(ns_bkt_usr_map, map_keys, ez_map_format, acl)
        elif d_bkt_usr_print == True and bypass == False: print '--> Mapping has been disabled\n'

        # Develop ns, user map, and print, if not disabled:

        print 'Mapping Namespaces and Users... Please be patient'; print
        if d_ns_usr_print == False and bypass == False:
                run_usr_collector = user_collector(token, debug, debug_d, debug_e, ip_public, key, pea, sleep, retry, retry_sleep)
                users_map = (run_usr_collector['mapped'])
                users_map_key = (run_usr_collector['mapped_key'])
                acl = False
                print_map(users_map, users_map_key, ez_map_format, acl)
        elif d_ns_usr_print == True and bypass == False: print '--> Mapping has been disabled\n'

        # Set Map format for function del_chk:

        if bypass == False:
                map_format = '\n'.join(map)
                map = map_format.split('\n')
        else:

                map = 'NAMESPACE:%s:BUCKET:%s:OWNER:%s' % (bypass_val.split(':')[0], bypass_val.split(':')[1], 'BYPASSED')
                map = map.split()

        # Run function del_chk if criteria is met:

        if clip_list != '' and map_only == False or object_list != '' and map_only == False:

                if clip_list != '':
                        list_type = 'CLIP'
                        if debug == True: print timestamp()+'Check Clips'; print
                        del_chk(token, clip_list, list_type, map, debug, debug_d, debug_e, ip_diag, chunkid, sleep, retry, retry_sleep, order)

                elif object_list != '':
                        list_type = 'OBJECT'
                        if debug == True: print timestamp()+'Check Objects'; print
                        del_chk(token, object_list, list_type, map, debug, debug_d, debug_e, ip_diag, chunkid, sleep, retry, retry_sleep, order)

        # Logout

        print 'Tool is finished.  Will now exit.'

        logout(token, debug, debug_d, debug_e, ip_public, retry, retry_sleep)

if __name__ == "__main__":
    run()