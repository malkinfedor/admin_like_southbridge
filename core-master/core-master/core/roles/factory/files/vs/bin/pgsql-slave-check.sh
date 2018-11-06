#!/bin/bash

# pgsql-slave-check v.1.3

PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin

PORTS="5432"
LOG=/var/log/pgsql-slave-check.log

################# Set in the conf file!
# Maintenance window. Set the equal for off
BEGINMAINT_s="02:00:00"
ENDMAINT_s="02:00:00"
# Thresholds
REGULAR_LAG_THRESHOLD_WARNING=300
REGULAR_LAG_THRESHOLD_CRITICAL=600
MAINTENANCE_LAG_THRESHOLD=2000
#################

function e {
    echo -e "$(date "+%F %T"): $1"
}

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
#"

if [ -f "$LOCATION/etc/pgsql-slave-check.conf.dist" ]; then
    . "$LOCATION/etc/pgsql-slave-check.conf.dist"
    if [ -f "$LOCATION/etc/pgsql-slave-check.conf" ]; then
        . "$LOCATION/etc/pgsql-slave-check.conf"
    fi
    if [ -f "$LOCATION/etc/pgsql-slave-check.local.conf" ]; then
        . "$LOCATION/etc/pgsql-slave-check.local.conf"
    fi
else
    echo "pgsql-slave-check.conf not found"
    exit 0
fi

BEGINMAINT=$(date +%s --date="$BEGINMAINT_s")
ENDMAINT=$(date +%s --date="$ENDMAINT_s")

for PORT in $PORTS; do

    TMPLOG=/tmp/postgreslag_$PORT.tmp
    if [ ! -f $TMPLOG ]; then echo "0" > $TMPLOG; fi
    LASTCODE=$(cat "$TMPLOG")

    currTime=$(date +%s)
    if [ "$currTime" -gt "$BEGINMAINT" ] && [ "$currTime" -lt "$ENDMAINT" ]; then
        LAG_THRESHOLD_WARNING="$MAINTENANCE_LAG_THRESHOLD"
        LAG_THRESHOLD_CRITICAL="$MAINTENANCE_LAG_THRESHOLD"
    else
        LAG_THRESHOLD_CRITICAL="$REGULAR_LAG_THRESHOLD_CRITICAL"
        LAG_THRESHOLD_WARNING="$REGULAR_LAG_THRESHOLD_WARNING"
    fi

# detect Postgres server verison
    PG_VER=$(psql -At -U postgres -p "$PORT" -c "SHOW server_version;" | awk -F "." '{print $1}')
    if [ "$PG_VER" -ge 10 ]; then
      LAG_SELECT="SELECT CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())::INTEGER END AS replication_lag;"
    else
      LAG_SELECT="SELECT CASE WHEN pg_last_xlog_receive_location() = pg_last_xlog_replay_location() THEN 0 ELSE EXTRACT (EPOCH FROM now() - pg_last_xact_replay_timestamp())::INTEGER END AS replication_lag;"
    fi

    LAG=$( psql -At -U postgres -p $PORT -c "$LAG_SELECT")
    LAG=${LAG/.*}

    TMPLOG="/tmp/postgreslag_$PORT.tmp"
    LASTCODE=$(cat $TMPLOG)

    HN=$(hostname)
    if [ "$LAG" -eq "0" ]; then
        echo "0" > "$TMPLOG"
    elif [ "$LAG" -gt "$LAG_THRESHOLD_CRITICAL" ]; then
        e "$PORT - $LASTCODE - $LAG" >> $LOG
        if [ "$LASTCODE" -gt 1 ];then
            e "$PORT - $LASTCODE - $LAG - Critical" >> $LOG
            echo "$HN CRITICAL Replication LAG = $LAG. Port: $PORT" | mail -s "$HN Postgres replication check. Critical" root
        fi
        LASTCODE=$((LASTCODE+1))
        echo "$LASTCODE" > "$TMPLOG"
    elif [ "$LAG" -gt "$LAG_THRESHOLD_WARNING" ]; then
        e "$PORT - $LASTCODE - $LAG" >> $LOG
        if [ "$LASTCODE" -gt 2 ];then
            e "$PORT - $LASTCODE - $LAG - Warning" >> $LOG
            echo "$HN Warninig Replication LAG = $LAG. Port: $PORT" | mail -s "$HN Postgres replication check. Warning" root
        fi
        LASTCODE=$((LASTCODE+1))
        echo "$LASTCODE" > "$TMPLOG"
    fi

done