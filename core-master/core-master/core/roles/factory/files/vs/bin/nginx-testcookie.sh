#!/bin/sh
#
# nginx-testcookie v.1.3
#
########################################################

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."

if [ -f "$LOCATION/etc/nginx-testcookie.conf.dist" ]; then
    . "$LOCATION/etc/nginx-testcookie.conf.dist"
    if [ -f "$LOCATION/etc/nginx-testcookie.conf" ]; then
        . "$LOCATION/etc/nginx-testcookie.conf"
    fi
    if [ -f "$LOCATION/etc/nginx-testcookie.local.conf" ]; then
        . "$LOCATION/etc/nginx-testcookie.local.conf"
    fi
else
    echo "nginx-testcookie.conf.dist not found"
    exit 0
fi


########################################################
TMPDIR=/tmp
TMPFILE=nginx-testcookie.tmp
TMPLOG=$TMPDIR/$TMPFILE
NGINXCONN=`curl -s http://localhost/nginx-status | grep "Active" | awk '{print($3)}'`
LA=`cat /proc/loadavg | awk -F '.' '{print($1)}'`

function e {
    echo -en $(date "+%F %T"): "$1"
}

if [ ! -f $TMPLOG ];then echo 0 > $TMPLOG; fi
LASTRESULT=`cat $TMPLOG`

if [ -n "$NGINXCONN" ]; then
  if [ $NGINXCONN -gt $TRIGGER_CONNECT ]; then
    ALERT1="1"
  fi
fi

if [ -n "$LA" ]; then
  if [ $LA -gt $LA_ACTIVATE ]; then
    ALERT2="1"
  fi
fi

ALERT=$ALERT1$ALERT2

if [ -n "$ALERT" -a $LASTRESULT -eq 0 ]; then
    e; printf "Nginx connect: %-4s LA: %-3s | Activate testcookie\n" "$NGINXCONN" "$LA"
    sed -i 's/.*##-AUTO-DDOS-LABEL-##/\ttestcookie on; ##-AUTO-DDOS-LABEL-##/g' $NGINX_CONF
    /sbin/service nginx reload >/dev/null 2>&1
    echo 1 > $TMPLOG
    if [ "$MAIL_ACTIVATE" = "true" -a -n "$MAILTO" ];then
        echo "Nginx connect $NGINXCONN, LA $LA. Nginx test-cookie enable" | mail -s "`hostname` DDOS detected. Nginx test-cookie enable" $MAILTO
    fi
fi

if [ $LASTRESULT -eq 1 -a $MAIL_TIME_ALERT = "true" -a -n "$MAILTO" ];then
    ALERT_ENABLE=`find ${TMPDIR} -type f -name ${TMPFILE} -mmin +${ENABLE_TIME_ALERT} -ls | wc -l`
    if [ $ALERT_ENABLE -eq 1 ];then
        e; printf "Nginx connect: %-4s LA: %-3s | Testcookie send alert: %5s min\n" "$NGINXCONN" "$LA" "$ENABLE_TIME_ALERT"
        echo "Nginx connect $NGINXCONN, LA $LA. Nginx test-cookie enable $ENABLE_TIME_ALERT minutes" | mail -s "`hostname` DDOS detected. Nginx test-cookie enable" $MAILTO
        echo 1 > $TMPLOG
    fi
fi

if [ $LA -le $LA_DEACTIVATE -a $LASTRESULT -eq 1 ]; then
    e; printf "Nginx connect: %-4s LA: %-3s | Dectivate testcookie\n" "$NGINXCONN" "$LA"
    sed -i 's/.*##-AUTO-DDOS-LABEL-##/\ttestcookie off; ##-AUTO-DDOS-LABEL-##/g' $NGINX_CONF
    /sbin/service nginx reload >/dev/null 2>&1
    echo 0 > $TMPLOG
fi
