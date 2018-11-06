#!/bin/bash
###############################################
#        Apache DOS protect v.0.3.3           #
###############################################

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
#"

if [ -f "$LOCATION/etc/apache_dos_protect.conf.dist" ]; then
    . "$LOCATION/etc/apache_dos_protect.conf.dist"
    if [ -f "$LOCATION/etc/apache_dos_protect.conf" ]; then
        . "$LOCATION/etc/apache_dos_protect.conf"
    fi
    if [ -f "$LOCATION/etc/apache_dos_protect.local.conf" ]; then
        . "$LOCATION/etc/apache_dos_protect.local.conf"
    fi
else
    echo "apache_dos_protect.conf.dist not found"
    exit 0
fi

################################################

PREF=""
STATUS="OK"
LOCK="/var/lock/subsys/${PREF}apache_dos_protect_dump.lck"
LOG="/var/log/${PREF}apache_dos_blockip.log"
LOG2="/var/log/${PREF}apache_dos_history.log"
LOGDUMP="/tmp/${PREF}apache_dos_dump.tmp"
LOGDUMPAPPEND="/var/log/${PREF}apache_dos_dump_append.log"
PIDLOG="/tmp/${PREF}apache_dos_protect_pids.log"
IPSDUMP="/tmp/${PREF}apache_dos_ipsdump.tmp"
IPT="/sbin/iptables"
MaxClient=`cat /etc/httpd/conf.d/server.conf | grep MaxClients| awk '{print $2}'`

function e {
    echo -e $(date "+%F %T"): $1
}

[ -f $LOCK ] && e "Script $0 is already runing" && exit
touch $LOCK

[ ! -f "$LOG" ] && touch $LOG


function blockIP {
    if [ "$BLOCK_IP" = "true" ];then
        $IPT -A INPUT -s $IP/32 -j DROP >/dev/null 2>&1
        e "$IP Blocked $BLOCK_TIME minutes Unblock = `date --date="$BLOCK_TIME minute" +%s`" >> $LOG
        e "$IP: CUR%-$CUR_PERCENT: Blocked $BLOCK_TIME minutes Unblock `date "+%F %T" --date="$BLOCK_TIME minute"`" >> $LOG2
    else
        e "$IP: [DISABLE] CUR%-$CUR_PERCENT: Blocked $BLOCK_TIME minutes Unblock `date "+%F %T" --date="$BLOCK_TIME minute"`" >> $LOG2
    fi
}

function unblockIP {
    #Разблокируем адреса
    while read line
        do
            if [[ "$line" == *=* ]]; then
                GET_TIME=`echo $line | awk -F"=" '{print $2}'`
                NOW=`date +%s`
                if [ "$NOW" -gt "$GET_TIME" ]; then
                    IP=`echo $line | awk '{print $3}'`
                    if [ "$BLOCK_IP" = "true" ];then
                        e "$IP: Unblocked." >> $LOG2
                        $IPT -D INPUT -s $IP/32 -j DROP
                    else
                        e "$IP: [DISABLE] Unblocked." >> $LOG2
                    fi

                    /bin/sed -i '/'$IP'/d' $LOG
               fi
            fi
        done < $LOG
}

function killhttpd {
        cat $LOGDUMP | grep $IP | awk '{print $2}'| awk '$1 ~ "[0-9]"' > $PIDLOG
        NUMPID=`cat $PIDLOG | wc -l`
        if [ "$KILL_BLOCK_HTTPD_WORKERS" = "true" ];then
            while read PID; do
                /usr/bin/kill $PID
            done < $PIDLOG
            e "$IP: CUR%-$CUR_PERCENT: Kill $NUMPID httpd workers for this IP" >> $LOG2
        else
            e "$IP: [DISABLE] CUR%-$CUR_PERCENT: Kill $NUMPID httpd workers for this IP" >> $LOG2
        fi
        rm -f $PIDLOG
}



# Unblock IP
unblockIP

# Dump /apache-status to log
LINKSVER=`links --help | grep "\-retries" |wc -l`
if [ $LINKSVER -gt 0 ]; then
    links -dump -width 180 -retries 1 -receive-timeout 9 http://localhost:8080/apache-status/ | grep -v 127.0.0.1 | awk '$2 != "-"' |awk '$11 ~ "^[0-9]"'|sort -rnk 6 > $LOGDUMP
else
    links -dump -eval 'set document.dump.width = 180' -eval 'set connection.retries = 1' -eval 'set connection.receive_timeout = 9' -dump http://localhost:8080/apache-status/ | grep -v 127.0.0.1 | awk '$2 != "-"' | awk '$11 ~ "^[0-9]"'|sort -rnk 6 > $LOGDUMP
fi

CUR_WORKERS=`cat $LOGDUMP | wc -l`
CUR_WORKERS_PERCENT=`expr $CUR_WORKERS \* 100 / $MaxClient`
NUM_WORKERS_FOR_BLOCK=`expr $MaxClient / 100 \* $BLOCK_PERCENT`
#echo $CUR_WORKERS $MaxClient $NUM_WORKERS_FOR_BLOCK
#echo $CUR_WORKERS_FOR_BLOCK
#echo $CUR_WORKERS_PERCENT

cat $LOGDUMP | awk '$2 != "-"' | awk '{print $11}' | sort | uniq -c | sort -nr | awk '$1 > $NUM_WORKERS_FOR_BLOCK' > $IPSDUMP

if [ -s "$LOGDUMP" -a "$DUMP_LOG" == "true" -a "$CUR_WORKERS_PERCENT" -gt "$DUMP_LOG_PERCENT" ];then
    e "### Use workers: $CUR_WORKERS ($CUR_WORKERS_PERCENT%) ###########" >> $LOGDUMPAPPEND
    cat $LOGDUMP >> $LOGDUMPAPPEND
    echo "" >> $LOGDUMPAPPEND
fi

if [ ! -s "$IPSDUMP" ];then
    /bin/rm -rf $LOCK
    exit
fi

# Добавляем собственные адреса в whitelist
for ip in ` ip a |grep 'inet ' | awk '{print $2}' | awk -F/ '{print $1}' | sort -u`; do
  EXCLUDE_IPS=$EXCLUDE_IPS' '$ip
done

while read NUM_IP; do
    Num=`echo $NUM_IP | awk '{print $1}'`
    IP=`echo $NUM_IP | awk '{print $2}'`
    #echo "$IP : $Num"

    CUR_PERCENT=`expr $Num \* 100 / $MaxClient`

    for EXCLUDE_IP in $EXCLUDE_IPS; do
        if [ "$EXCLUDE_IP" == "$IP" ];then
        e "$IP: CUR%-$CUR_PERCENT: Exclude this IP" >> $LOG2
        IP=""
        fi
    done

    if [ -n "$IP" -a "$CUR_PERCENT" -gt "$BLOCK_PERCENT" ];then
        blockIP $IP
        killhttpd $IP
    fi

done < $IPSDUMP


/bin/rm -rf $LOCK
