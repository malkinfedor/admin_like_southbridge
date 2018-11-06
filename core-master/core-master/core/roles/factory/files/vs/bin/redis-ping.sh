#!/bin/bash
#
# Redis check Script
# VER. 0.0.2
#=====================================================================

# Dir search with redis config
DIR="/etc"

# redis-cli path
REDISCLI=/usr/bin/redis-cli

if [ ! -f "/root/.redis" ];then
        exit;
fi

#=====================================================================

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."

if [ -f "$LOCATION/etc/redis-backup.conf.dist" ]; then
    . "$LOCATION/etc/redis-backup.conf.dist"
    if [ -f "$LOCATION/etc/redis-backup.conf" ]; then
        . "$LOCATION/etc/redis-backup.conf"
    fi
else
    echo "redis-backup.conf.dist not found"
    exit 0
fi

# Functions

dbping () {

for i in `find $DIR -maxdepth 1 -name "redis*.conf" -type f -print | grep -v "sentinel"`
do

    DBPORT=`cat $i | grep -v "^#" | grep "." | grep port | awk '{print($2)}'`
    DBPASS=`cat $i | grep -v "^#" | grep "." | grep requirepass | awk '{print($2)}'`
    if [ -z "$DBPASS" ];then
        DBPASS="password"
    fi
    echo -n "$i: Ping REDIS localhost:$DBPORT - "
    $REDISCLI -a $DBPASS -p $DBPORT ping
done

}

echo ======================================================================
    dbping
echo ======================================================================

exit $STATUS
