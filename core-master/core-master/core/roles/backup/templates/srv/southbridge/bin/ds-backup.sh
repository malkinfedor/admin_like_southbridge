#!/bin/bash

PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
#"
cd -P -- "$(dirname -- "$0")"
REMOTEHOSTDIR=`hostname | awk -F '.' '{print $1}'`
HN=`/bin/hostname`
LLOG=""

SESS=$RANDOM

# Nice debugging messages
function e {
    echo -e $(date "+%F %T [$SESS]"): $1
}

# read configuration
if [ -f "$LOCATION/etc/ds-backup.conf.dist" ]; then
    . "$LOCATION/etc/ds-backup.conf.dist"
    if [ -f "$LOCATION/etc/ds-backup.conf" ]; then
        . "$LOCATION/etc/ds-backup.conf"
    fi
    if [ -f "$LOCATION/etc/ds-backup.local.conf" ]; then
        . "$LOCATION/etc/ds-backup.local.conf"
    fi
else
    echo "ds-backup.conf.dist not found"
    exit 0
fi

if [ "$RAID0" = "YES" ];then
    echo "Server someone right" > /dev/null 2>&1
else
    if [ x$1 != "xforce" ]; then
      RAID=`cat /proc/mdstat | awk '/^md[0-9]+/ {md++} /\[U+\]$/ {up++} END {if (md == up){print 1} else {print 0}}'`
      if [ "$RAID" == "0" ]; then
        e "RAID is not up! Backup aborted"
        LLOG=`cat /proc/mdstat`
        e "$LLOG"
        ALERT=${HN}$'\n''Raid is not up. Backup aborted'$'\n'${LLOG}
        echo "$ALERT" | mail -s "$HN vz-backup error alert" root
        exit
      fi
    fi
fi
 
if pidof -x $(basename $0) > /dev/null; then
  for p in $(pidof -x $(basename $0)); do
    if [ $p -ne $$ ]; then
      e "Script $0 is already running: exiting"
      ALERT=${HN}$'\n'"Script $0 is already running: exiting"
      echo "$ALERT" | mail -s "$HN vz-backup error alert" root
      exit
    fi
  done
fi

PBACKUP=`ps ax | grep postgresql-backup.sh | grep -v "grep"`
MBACKUP=`ps ax | grep mysql-backup.sh | grep -v "grep"`

while [ -n "$PBACKUP$MBACKUP" ]; do
  echo "Wait 300 sec for database backup..."
  sleep 300
  PBACKUP=`ps ax | grep postgresql-backup.sh | grep -v "grep"`
  MBACKUP=`ps ax | grep mysql-backup.sh | grep -v "grep"`
  DAT=`date +%H`
  if [ $DAT -ge 8 ]; then
      echo "Script database backup is running: exiting"
      ALERT=${HN}$'\n'"Script database backup is running: exiting"$'\n'
      ALERT=${ALERT}$'\n'${MBACKUP}$'\n'${PBACKUP}
      echo "$ALERT" | mail -s "$HN vz-backup error alert" root
      exit
  fi
done

if [ -z "$STATISTICS_REMOTE_LOG" ];then STATISTICS_REMOTE_LOG="/tmp/rdiff-backup_remote_statistics.tmp";fi

if [ "$PREBACKUP" ]
    then
        eval $PREBACKUP
fi

# Build up the --exclude string for the remote rdiff-backup command
  for EXCL_MOUNT in $EXCLUDE_MOUNTS; do
    for EM in `mount | grep " type $EXCL_MOUNT "| awk '{print $3}'`; do
        RDIFFBACKUP_LOCAL_ARGS+=" --exclude=$EM"
    done
  done

# Build up the --exclude string for the remote rdiff-backup command
  for EXCL_PATH in $EXCLUDE; do
        RDIFFBACKUP_LOCAL_ARGS+=" --exclude=$EXCL_PATH"
  done;

  for EXCL_PATH in $REMOTE_EXCLUDE; do
       RDIFFBACKUP_REMOTE_ARGS+=" --exclude=$EXCL_PATH"
  done;
  
#  RDIFFBACKUP_REMOTE_CMD="rdiff-backup --force $RDIFFBACKUP_REMOTE_ARGS"

  RDIFFBACKUP_REMOTE_CMD="rdiff-backup --force --print-statistics $RDIFFBACKUP_LOCAL_ARGS $RDIFFBACKUP_REMOTE_ARGS"

###########Проверяем#################
 for REMOTE_HOST in $REMOTE_HOSTS; do
        e "Doing remote backup"
        e "$RDIFFBACKUP_REMOTE_CMD / $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$REMOTEHOSTDIR"
        LLOG=`$RDIFFBACKUP_REMOTE_CMD / $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$REMOTEHOSTDIR 2>&1`
         if [ $? -gt 0 ]; then
           ALERT21=${ALERT21}"Alert rdiff-backup REMOTE stage error !"$'\n'
           ALERT21=${ALERT21}"$RDIFFBACKUP_REMOTE_CMD / $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$REMOTEHOSTDIR"$'\n'
           ALERT21=${ALERT21}${LLOG}
         fi
        e "$LLOG"
        echo -e "$LLOG" > ${STATISTICS_REMOTE_LOG}
        e "Removing old files"

        LLOG=`$RDIFFBACKUP_REMOTE_CMD --force --remove-older-than $REMOVE_AGE $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$REMOTEHOSTDIR 2>&1`
        if [ $? -gt 0 ]; then
              ALERT22=${ALERT22}"Alert rdiff-backup REMOTE stage error !"$'\n'
              ALERT22=${ALERT22}"$RDIFFBACKUP_REMOTE_CMD --force --remove-older-than $REMOVE_AGE $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$REMOTEHOSTDIR"$'\n'
              ALERT22=${ALERT22}${LLOG}
        fi
        e "$LLOG"

  done;

ALERT=${ALERT21}${ALERT22}

if [ "$ALERT" != "" ]; then
  ALERT=$HN$'\n'${ALERT21}$'\n'${ALERT22}$'\n'
  echo "$ALERT"
  echo "$ALERT" | tr -d '\015' | mail -s "$HN ds-backup error alert" root
fi

if [ "$POSTBACKUP" ]
    then
        eval $POSTBACKUP
fi
 

