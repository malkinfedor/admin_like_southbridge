#!/bin/bash
# ddos_protect v.1.1.9

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
#"

if [ -f "$LOCATION/etc/ddos_protect.conf.dist" ]; then
    . "$LOCATION/etc/ddos_protect.conf.dist"
    if [ -f "$LOCATION/etc/ddos_protect.conf" ]; then
        . "$LOCATION/etc/ddos_protect.conf"
    fi
else
    echo "ddos_protect.conf.dist not found"
    exit 0
fi

################################################

[ ! -f /usr/bin/host ] && echo "/usr/bin/host not found. Please yum install bind-utils" && exit
[ -z "$DOMAIN_LIST" ] && echo "DOMAIN_LIST is empty"
[ ! -f $LOGFILE ] && touch $LOGFILE
debug="0"

function e {
    echo -e $(date "+%F %T") $1
}

if [ -f "$LOCK" ]; then
  filemtime=`stat -c '%Y' "$LOCK"`
  currtime=`date '+%s'`
  diff=$(( currtime - filemtime ))
  #  echo $diff
  if [ $diff -le 600 ]; then
    e "Script $0 is already runing"
    exit
  fi
fi
touch $LOCK


for D in $DOMAIN_LIST
do


    MSG=/tmp/ddos_${D}_msg.log
    MSG1=/tmp/ddos_${D}_msg1.log
    MSG2=/tmp/ddos_${D}_msg2.log
    #MSG=/tmp/ddos_${D}_msg.log
    TMP_LOG=/tmp/ddos-$D-acc-temp.log
    NGINX_LOG=/srv/www/$D/logs/$D-acc
    DT=`date "+%F %T"`

    if [ ! -f $NGINX_LOG ];then
        echo "Log ($NGINX_LOG) not found."
        /bin/rm -rf $LOCK
        exit
    fi

    # смотрим логи за последние 20 минут
    grep -h -A9999999 `date -d "-$INTERVAL_MIN minutes" "+%d/%b/%Y:%H:%M"` $NGINX_LOG | awk '{print $1}' | sort | uniq -c | sort -n | awk -v x=$RECORDS ' $1 > x {print $2} ' > $TMP_LOG

    # Добавляем собственные адреса в whitelist
    for ip in `/sbin/ip a | grep 'inet ' | awk '{print $2}' | awk -F/ '{print $1}' | sort -u`; do
      IP_WHITELIST=$IP_WHITELIST' '$ip
    done

    #Разблокируем адреса
    while read line
        do
            if [[ "$line" == *=* ]]; then
                GET_TIME=`echo $line | awk -F"=" '{print $2}'`
                NOW=`date +%s`
                #echo $NOW
                #echo $GET_TIME
                if [ "$NOW" -gt "$GET_TIME" ]; then
                    IP=`echo $line | awk '{print $3}'`
                    if [ "$BLOCK_ENABLE" = "true" ];then
                        e "$IP unblocked." >> $LOGFILE2
                        /sbin/iptables -D INPUT -s $IP -j DROP
                    else
                        e "(TEST MODE) $IP unblocked." >> $LOGFILE2
                    fi

                    /bin/sed -i '/'$IP'/d' $LOGFILE

                #else
                    #echo "Nothing to do"
               fi
            fi
        done < $LOGFILE


    #Блокируем адреса
    while read line
    do
            IP=$line
            wh=0
            for I in $IP_WHITELIST
            do
                if [ "$I" = "$IP" ];then
                    wh=1
                    [ "$debug" -gt "1" ] && echo $IP in WHITELIST
                fi
            done

            if [ "$wh" = "1" ]; then
               [ "$debug" -gt "1" ] && e "$IP in whitelist" >> $LOGFILE2
            else
                        DOUBLE=`/sbin/iptables-save | grep "\-j DROP" | grep "$IP"`
                        if [ -n "$DOUBLE" ]; then
                            [ "$debug" -gt "0" ] && e "$IP exist in DROP rule" >> $LOGFILE2
                            [ "$debug" -gt "2" ] && echo "$IP DBL: YES"
                        else
                            PTR=""
                            SRCHBOT=""
                            FINDPTR="`/usr/bin/host $IP | grep -v 'not found' | grep -v 'no PTR record' | head -1 | awk '{ print $5 }' | sed 's/\.$//'`"
                            if [ -z "$FINDPTR" ];then
                                PTR=" (PTR record not found)"
                            else
                                PTR=" ($FINDPTR)"
                            fi
                            SRCHBOT=`/usr/bin/host $IP | awk '{ print $5 }' | rev | cut -d . -f 2-3 | rev | egrep "$BOTS"`
                            [ -n "$SRCHBOT" ] && BOT="YES" || BOT="NO"
                            [ -z "$BLOCK_WITH_PTR" ] && BLOCK_WITH_PTR=true

                            DOUBLETEST=""

                            if [ "$BLOCK_ENABLE" == "true" ]; then
                                if [ "$BOT" == "NO" ]; then
                                    if [ "$BLOCK_WITH_PTR" = "true" ];then
                                        [ "$debug" -gt "1" ] && echo "$IP$PTR blocked"
                                        e "$IP blocked $BLOCK_TIME minutes. ($D) Unblock = `date --date="$BLOCK_TIME minute" +%s`" >> $LOGFILE
                                        e "$IP$PTR blocked $BLOCK_TIME minutes. ($D)" >> $LOGFILE2
                                        $IPT -I INPUT -s $IP -j DROP
                                    else
                                        if [ -z "$FINDPTR" ];then
                                            [ "$debug" -gt "1" ] && echo "$IP$PTR blocked"
                                            e "$IP blocked $BLOCK_TIME minutes. ($D) Unblock = `date --date="$BLOCK_TIME minute" +%s`" >> $LOGFILE
                                            e "$IP$PTR blocked $BLOCK_TIME minutes. ($D)" >> $LOGFILE2
                                            $IPT -I INPUT -s $IP -j DROP
                                        fi
                                    fi
                                    if [ "$email"  != "" ];then
                                        echo "$IP $PTR blocked $BLOCK_TIME minutes. Match $RECORDS records. ($D)" >> $MSG1
                                        if [ "$DETAILLOG" = "true" ];then
                                            echo "--- Start log $IP ---" >> $MSG2
                                            tail -10000 $NGINX_LOG | grep $IP | tail -10 >> $MSG2
                                            echo "--- End log $IP ---" >> $MSG2
                                            echo "" >> $MSG2
                                        fi
                                    fi
                                else
                                    [ "$debug" -gt "0" ] && echo -e "IS_BOT $IP$PTR from domain $SRCHBOT"
                                    [ "$debug" -gt "0" ] && e "$IP$PTR IS SEARCH BOT" >> $LOGFILE2
                                fi
                            else
                                DOUBLETEST=`cat $LOGFILE | grep $IP`
                             if [ $BOT = "NO" ];then
                                if [ -z "$DOUBLETEST" ];then
                                        if [ "$BLOCK_WITH_PTR" = "false" -a -z "$FINDPTR" ];then
                                            e "$IP TEST_blocked $BLOCK_TIME minutes. ($D) Unblock = `date --date="$BLOCK_TIME minute" +%s`" >> $LOGFILE
                                            e "(TEST MODE) $IP$PTR SearchBot: $BOT. Match $RECORDS records. ($D)" >> $LOGFILE2
                                        fi
                                        if [ "$BLOCK_WITH_PTR" = "true" -a "$BOT" == "NO" ];then
                                            e "$IP TEST_blocked $BLOCK_TIME minutes. ($D) Unblock = `date --date="$BLOCK_TIME minute" +%s`" >> $LOGFILE
                                            e "(TEST MODE) $IP$PTR SearchBot: $BOT. Match $RECORDS records. ($D)" >> $LOGFILE2
                                        fi

                                        if [ "$email"  != "" ];then
                                            echo "(TEST MODE) $IP$PTR SearchBot: $BOT. Match $RECORDS records. ($D)" >> $MSG1
                                            if [ "$DETAILLOG" = "true" ];then
                                                echo "--- Start log $IP ---" >> $MSG2
                                                tail -10000 $NGINX_LOG | grep $IP | tail -10 >> $MSG2
                                                echo "--- End log $IP ---" >> $MSG2
                                                echo "" >> $MSG2
                                            fi
                                        fi

                                fi
                             fi


                            fi
                        fi
            fi
    done < $TMP_LOG

# отправка сообщения
if [ -s "$MSG1" ];then
    echo "### $DT List block IP ###" > $MSG
    echo "" >> $MSG
    cat $MSG1 >> $MSG
    echo "" >> $MSG
    echo "### $DT Detail LOG ### " >> $MSG
    echo "" >> $MSG
    cat $MSG2 >> $MSG
    if [ "$BLOCK_ENABLE" == "true" ];then
        cat $MSG | /bin/mail -s "IP Blocked" $email
    else
        cat $MSG | /bin/mail -s "(TEST MODE) IP Blocked" $email
    fi
    rm -f $MSG
    rm -f $MSG1
    rm -f $MSG2
fi

done
/bin/rm -rf $LOCK
