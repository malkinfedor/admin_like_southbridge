#!/bin/sh

HN=`hostname`
PASS=`cat /root/.mysql`;
RES='/tmp/mysql_slave.msg'
echo "show slave status\G" | /usr/bin/mysql -p$PASS >$RES 2>&1

CSQL=`cat $RES | grep "Slave_SQL_Running: Yes"`
CIO=`cat $RES | grep "Slave_IO_Running: Yes"`

if [ -z "$CSQL" -o -z "$CIO" ]; then
  if [ -f /tmp/mysql-slave-error.flag ]; then
    s=`ls -d -l --full-time /tmp/mysql-slave-error.flag | awk '{print $6" "$7}'`
    a=`date +%s`
    b=`date --date="$s" +%s`
    d=$(( ($a - $b) ))
    if [ $d -le 3600 ]; then
      exit
    fi
  fi    
  (echo $HN; cat $RES) | mail -s "$HN mysql slave error" root
  touch /tmp/mysql-slave-error.flag
else
  if [ -f /tmp/mysql-slave-error.flag ]; then
    rm /tmp/mysql-slave-error.flag
  fi
fi

rm $RES
