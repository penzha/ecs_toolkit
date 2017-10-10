#!/bin/sh

################################################################
#
# NAME
#	check_dt_dist.sh
#
# SYNOPSIS
#	check_dt_dist.sh  
#
# VERSION
VERSION="3.0.0.0"
#
# DESCRIPTION
#	Obtain DT distribution
#
# SAMPLE OUTPUT 
#	admin@sc-ecs-u300-prd-001:~> ./dist.sh
#	IP               CT1 SS1 CT2 SS2 OB0 MA0 LS0 TT0 BR1 BR2 RR0 MR0 ET0 RT0 PR1 PR2 TOT
#	10.10.192.91      32  32  32  32  32  32  32  58  32  32  32  32  32  32  32  32 538
#	10.10.192.92      32  32  32  32  32  32  32  68  32  32  32  32  32  32  32  32 548
#	10.10.192.93      32  32  32  32  32  32  32  xx  32  32  32  32  32  32  32  32 480
#	10.10.192.94      32  32  32  32  32  32  32   2  32  32  32  32  32  32  32  32 482
################################################################

echo "$0 Version: ${VERSION}"
V_IP1="`sudo ifconfig public 2> /dev/null| grep Mask | awk '{print $2}' | sed -e 's/addr://'`"
V_IP2="`sudo ifconfig -a | grep inet | awk '{print $2}' | grep -v "::" | grep -v 127.0.0.1 | tail -1`"
V_IP3="`hostname -i 2> /dev/null | sed -e 's/ //g' `"
V_IP4="`sudo netstat -anp | grep LISTEN| grep 9101 | awk '{print $4}' | awk -F ':' '{print $1}'`"
for i in $(echo ${V_IP4} ${V_IP3} ${V_IP1} ${V_IP2} ); do
if [ ! "${i}" = "" ] ; then 
 V_IP=$(echo $i )
 break
fi
done
curl -s "http://${V_IP}:9101/diagnostic/" | xmllint --format - | grep http | awk -F">" '{print $2}' | awk -F"<" '{print $1}' | while read a; do curl -s "${a}" |xmllint --format -; done | sed 's/<pre>/\r/'|  awk 'BEGIN {RS="<entry>";FS="_"}
{ 
if (NF > 1)
{
        OB=substr($3$6,0,index($3$6,":")-1);
        gsub("ipaddress>","",$7);
        gsub("</owner","",$7);
        if(sum[$7,OB] == "")
        {
                sum[$7,OB]=1
        }
        else
        {
                sum[$7,OB]++
        }
        if (allOB[OB] =="")
        {
                allOB[OB] = 1;
        }
        else
        {
                allOB[OB] ++;
        }
        if (allIP[$7] == "")
        {
                allIP[$7] =1;
        }
        else
        {
                allIP[$7]++;
        }
}
}
END {
        #format Header
    if (format == "")
    {
            printf("IP\t\t")
            for (ob in allOB)
            {
                    printf("%4s",ob);
            }
            printf(" TOT\n");
num_of_ip=asorti(allIP,sorted_IP)
        for ( i =1; i<=num_of_ip; i++  )
        {
                ip=sorted_IP[i];    
            #for ( ip in allIP)
            #{
                    printf("%4s\t",ip);
            totalDT=0;
                    for (ob in allOB)
                    {
                            if (sum[ip,ob] == "")
                            {
                                    printf("  xx");
                            }
                            else
                            {
                                    printf("%4s",sum[ip,ob]);
                    totalDT += sum[ip,ob];
                            }
                    }
                    printf("%4s\n",totalDT);
    
            }
    }
    else
    {
               #format Header
                printf("<HTML><TABLE border=1><TR><B><TH>IP</TH>")
                for (ob in allOB)
                {
                        printf("<TH>%s</TH>",ob);
                }
                printf("<TH>TotalDTs</TH></B></TR>\n");
                for ( ip in allIP)
                {
                        printf("<TR align=center><TD>%s</TD>",ip);
                        totalDT=0;
                        for (ob in allOB)
                        {
                                if (sum[ip,ob] == "")
                                {
                                        printf("<TD>n/a</TD>");
                                }
                                else
                                {
                                        totalDT += sum[ip,ob];
                                        printf("<TD>%s</TD>",sum[ip,ob]);
                                }
                        }
                        printf("<TD>%s</TD></TR>\n",totalDT);
                }
                print "</table></html>"
    }
}' format=$1
