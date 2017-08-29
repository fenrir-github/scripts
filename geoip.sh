#!/bin/bash
#version 1.0
###################################################### SETTINGS
#PREFIX         =>      Prefix all files, sets and groups by this string, CHOOSE IT CAREFULY (ie: "geoip" as prefix while result in objects named "geoipIPv4_fr")
PREFIX="geoip"
#BASEDIR        =>      Directory where saved lists while be created (ie for quick restoration at boot), the script must be able to write inside
BASEDIR="/opt/scripts/geoipdb"
#MAXELEM        =>      Maximum number of elements in ipset hash, adjust it for your needs
MAXELEM=65536
###################################################### SYNOPSIS
#       <script name> action TAG Ipversion [URL]
###################################################### USAGE
#       This script allows 4 actions: load, restore, list and delete
#
#       Use "load" for each list+IP procotole paire you want to create or update:
#               <script name> load TAG IPversion
#       You can also load a custom URL by adding a 4th arguments:
#               <script name> load TAG IPversion URL
#
#       Use "restore" in order to restore the last loaded lists, usefull at boot time:
#               <script name> restore TAG IPversion
#
#       Use "list" in order to show groups managed by this script:
#               <script name> list
#
#       Use "delete" in order to delete network groups, hash and lists:
#               <script name> delete TAG IPversion
#       nb: delete will failed if the group is used by Kernel (ie: in a rule)
######################################################EXAMPLES
#       <script name> load fr 4 && <script name> load fr 6
#               This example will create 2 networks groups: geoipIPv4_fr and geoipIPv6_fr
#               Use them as usual in your firewall rules
#
#       <script name> load CloudFlare 4 https://www.cloudflare.com/ips-v4
#               This example will create a network group named "geoipIPv4_CloudFlare" from a custom URL
#
#       <script name> restore fr 4 && <script name> restore fr 6
#               This example will fills ipset with the content of $BASEDIR/geoipIPv4_fr and $BASEDIR/geoipIPv6_fr files
######################################################NOTES
#nb:
#       should (must ?) be buggy, use with caution
#       in case you're using this to block countries, add a rule to prevent your own IP(s) address(es) to be blocked by accident
#       it's useless to update lists daily, once a week or a month is enough
#       watch free memory before adding large lists
#       use restore after a reboot
######################################################LIMITS
#thanks to respect this policy: http://www.ipdeny.com/usagelimits.php
######################################################
do_usage(){
        echo ""
        echo "Usage: $0 {load|delete|restore} {TAG} {IPversion} [{URL}]"
        echo "  load: create or update [network-group] and [ipset]"
        echo "  delete: delete a [network-group] and [ipset]: use with caution, can result in blank rules !!"
        echo "  restore: restore the last imported list (in case of reboot)"
        echo ""
        echo "  second arg must be a valid country code (ie: fr) or TAG (depending or source)"
        echo "  third arg must be the IP protocole version to use: 4 or 6"
        echo "  fourth arg is an optionnal URL"
        echo ""
        echo "Example: $0 load fr 6"
        echo "IP lists will be stored under $BASEDIR"
        exit 2
}
######################################################
ACTION=$1
TAG=$2
IPv=$3
URL=$3
######################################################
if [ -z "$1" ]; then
        do_usage
elif [ "$1" == "list" ]; then
        echo "Managed groups: "
elif [ -z "$2" ]; then
        echo "ERROR: second arg must be a valid country code (or tag) like: fr"
        do_usage
elif [ -z "$3" ]; then
        echo "ERROR: third arg must be the IP protocole version to use: 4 or 6"
        do_usage
elif [ $3 -eq 6 ]; then
        BASEURL="http://www.ipdeny.com/ipv6/ipaddresses/aggregated/${TAG}-aggregated.zone"
        GRPTYPE="ipv6-network-group"
        IPSETOptions="hash:net family inet6 maxelem $MAXELEM"
elif [ $3 -eq 4 ]; then
        IPv=$3
        BASEURL="http://www.ipdeny.com/ipblocks/data/aggregated/${TAG}-aggregated.zone"
        GRPTYPE="network-group"
        IPSETOptions="hash:net family inet maxelem $MAXELEM"
else
        echo "ERROR: third arg must be the IP protocole version to use: 4 or 6"
        do_usage
fi
if [ "$4" != "" ]; then
        BASEURL=$4
fi
######################################################
mkdir -p "${BASEDIR}"
######################################################
IPSET="/sbin/ipset -quiet"
IPTABLES="/sbin/iptables"
######################################################
DATE=`date +"%Y-%m-%d %H:%M"`
IPversion="IPv${IPv}"
NETGROUP="${PREFIX}${IPversion}_${TAG}"
NETGROUPtmp="${NETGROUP}_tmp"
NETGROUPFILE="${BASEDIR}/${NETGROUP}"
NETGROUPFILEtmp="${NETGROUPFILE}_tmp"
######################################################
f_ipset_create(){
##create $1 with $IPSETOptions options
        $IPSET -name list $1 > /dev/null 2>&1
        if [ "$?" != 0 ]; then
                $IPSET create $1 $IPSETOptions
                if [ "$?" != 0 ]; then
                        echo "ERROR: There was an error trying to create set $1 with $IPSETOptions options"
                        exit 1
                fi
        fi
        $IPSET -name list $2 > /dev/null 2>&1
        if [ "$?" != 0 ]; then
                $IPSET create $2 $IPSETOptions
                if [ "$?" != 0 ]; then
                        echo "ERROR: There was an error trying to create set $1 with $IPSETOptions options"
                        exit 1
                fi
        fi
        return 0
}
f_ipset_destroy(){
##destroy $1
        $IPSET -name list $1 > /dev/null 2>&1
        if [ "$?" == 0 ]; then
                $IPSET destroy $1
                if [ "$?" != 0 ]; then
                        echo "ERROR: There was an error trying to destroy set $1"
                        exit 1
                fi
        fi
        return 0
}
f_ipset_restore(){
##restore $1 (file) in $2 (set)
        $IPSET -name list $2 > /dev/null 2>&1
        if [ "$?" != 0 ]; then
                echo "ERROR: $2 don't exist, can't restore"
                exit 1
        else
                $IPSET -file $1 restore > /dev/null 2>&1
                if [ "$?" != 0 ]; then
                        echo "ERROR: An error occured while restoring $2 set from $1"
                        exit 1
                fi
        fi
        return 0
}
f_ipset_swap(){
##swap $1 with $2
        $IPSET -name list $1 > /dev/null 2>&1
        if [ "$?" != 0 ]; then
                echo "ERROR1: ipset SET $1 doesn't exist"
                exit 1
        fi
        $IPSET -name list $2 > /dev/null 2>&1
        if [ "$?" != 0 ]; then
                echo "ERROR2: ipset SET $2 doesn't exist"
                exit 1
        fi
        $IPSET swap $1 $2
        if [ "$?" != 0 ]; then
                echo "ERROR: There was an error trying to swap $1 with $2"
                exit 1
        fi
}
f_netlist_get(){
##get networks list
        rm -f $NETGROUPFILEtmp
        curl -s $BASEURL | grep -E '^[0-9]' | sort -u | awk -v list=$NETGROUPtmp '{print "add -exist "list" "$1}' > $NETGROUPFILEtmp
        if [ `wc -l < $NETGROUPFILEtmp` -lt 1 ] || [ ! -f $NETGROUPFILEtmp ]; then
                echo "ERROR: $BASEURL for $TAG is empty or not exist"
                rm -f $NETGROUPFILEtmp
                exit 1
        fi
}
f_ipt_search_rule(){
##search if group $1 is used by netfilter
        ISUSED=`$IPTABLES -L -n -v | grep $1`
        if [ "$?" == 0 ]; then
                echo "ERROR: $1 is used by, at least, one rule"
                exit 1
        fi
}
f_ipt_search_rule2(){
##search if group $1 is used by netfilter
        ISUSED=`ipset -terse list $1 | grep '^References' | awk '{print $2}'`
        if [ "$ISUSED" != 0 ]; then
                echo "ERROR: $1 is used (References: $ISUSED)"
                exit 1
        fi
}
######################################################
do_list(){
        # echo `$IPSET -terse list | grep -E "^Name|References"`
        for IPGROUP in `$IPSET -name list | grep -E "^$PREFIX"`
        do
                echo ""
                $IPSET -terse list $IPGROUP
        done
        exit 0
}
do_load(){
        f_netlist_get
##create temporary set
        f_ipset_destroy $NETGROUPtmp
        f_ipset_create $NETGROUP $NETGROUPtmp
##add networks into temporary set
        f_ipset_restore $NETGROUPFILEtmp $NETGROUPtmp
        mv -f $NETGROUPFILEtmp $NETGROUPFILE
        f_ipset_swap $NETGROUPtmp $NETGROUP
        f_ipset_destroy $NETGROUPtmp
        echo -e "FINISH: $NETGROUP was loaded"
        exit 0
}
do_delete(){
        read -p "Do you really want to delete $NETGROUP (y/[n]): " DELETE
        case "$DELETE" in
                y)
                        f_ipt_search_rule2 $NETGROUP
                        DEL1=$( f_ipset_destroy $NETGROUPtmp )
                        DEL2=$( f_ipset_destroy $NETGROUP )
                        rm -f $NETGROUPFILE $NETGROUPFILEtmp
                ;;
                n|N|"")
                        exit 0
                ;;
                *)
                        do_delete
                ;;
        esac
        exit 0
}
do_restore(){
        if [ ! -f $NETGROUPFILE ]; then
                echo "ERROR: $NETGROUPFILE does not exist"
                exit 1
        fi
        f_ipset_destroy $NETGROUPtmp
        f_ipset_create $NETGROUP $NETGROUPtmp
        f_ipset_restore $NETGROUPFILE $NETGROUPtmp
        f_ipset_swap $NETGROUP $NETGROUPtmp
        f_ipset_destroy $NETGROUPtmp
        echo "FINISH: restore complete"
        exit 0
}
case "$ACTION" in
        list)
                do_list
        ;;
        load)
                do_load
        ;;
        delete)
                do_delete
        ;;
        restore)
                do_restore
        ;;
        *)
                do_usage
                exit 2
        ;;
esac
exit 0
