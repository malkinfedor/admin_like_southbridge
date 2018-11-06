#!/bin/bash
# vz-backup v.1.4

PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
cd -P -- "$(dirname -- "$0")"
HN=`/bin/hostname`
LLOG=""
#"

SESS=$RANDOM
SECONDTRY_CMD=""

function e { 
    echo -e $(date "+%F %T [$SESS]"): $1
}

if [ x$1 != "xforce" ]; then
  RAID=`cat /proc/mdstat | awk '/^md[0-9]+/ {md++} /\[U+\]$/ {up++} END {if (md == up){print 1} else {print 0}}'`
  if [ "$RAID" == "0" ]; then
    e "RAID is not up! Backup aborted"
    LLOG=`cat /proc/mdstat`
    echo $LLOG
    ALERT=${HN}$'\n''Raid is not up. Backup aborted'$'\n'${LLOG}
    echo "$ALERT" | mail -s "$HN vz-backup error alert" root
    exit
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
  e "Wait 300 sec for database backup..."
  sleep 300
  PBACKUP=`ps ax | grep postgresql-backup.sh | grep -v "grep"`
  MBACKUP=`ps ax | grep mysql-backup.sh | grep -v "grep"`
  DAT=`date +%H`
  if [ $DAT -ge 8 ]; then
      e "Script database backup is running: exiting"
      ALERT=${HN}$'\n'"Script database backup is running: exiting"$'\n'
      ALERT=${ALERT}$'\n'${MBACKUP}$'\n'${PBACKUP}
      echo "$ALERT" | mail -s "$HN vz-backup error alert" root
      exit
  fi
done

# read configuration
if [ -f "$LOCATION/etc/vz-backup.conf.dist" ]; then
    . "$LOCATION/etc/vz-backup.conf.dist"
    if [ -f "$LOCATION/etc/vz-backup.conf" ]; then
        . "$LOCATION/etc/vz-backup.conf"
    fi
    if [ -f "$LOCATION/etc/vz-backup.local.conf" ]; then
        . "$LOCATION/etc/vz-backup.local.conf"
    fi
else
    echo "vz-backup.conf.dist not found"
    exit 0
fi

# Nice debugging messages
function die {
    e "Error: $1" >&2
    exit 1;
}

# Make sure all is sane
[ ! -d "$VZ_PRIVATE" ] && die "\$VZ_PRIVATE directory doesn't exist. ($VZ_PRIVATE)"
[ "$VEIDS" = "*" ] && die "VEID in \$VZ_PRIVATE directory not found."
[ "$LOCAL_DIR" != "" -a ! -d "$LOCAL_DIR" ] && mkdir -p $LOCAL_DIR

if [ -z "$STATISTICS_LOCAL_LOG" ];then STATISTICS_LOCAL_LOG="/tmp/rdiff-backup_local_statistics";fi
if [ -z "$STATISTICS_REMOTE_LOG" ];then STATISTICS_REMOTE_LOG="/tmp/rdiff-backup_remote_statistics";fi

if [ "$PREBACKUP" ]
    then
        eval $PREBACKUP
fi

# Exclude unneeded VEIDS
for VEID in $VEIDS_EXCLUDE; do
    VEIDS=`echo $VEIDS | sed "s/\b$VEID\b//"`
done

# Build up the --exclude string for the local rdiff-backup command
for EXCL_PATH in $EXCLUDE; do
    RDIFFBACKUP_LOCAL_ARGS+=" --exclude=$EXCL_PATH"
done;

# Build up the --exclude string for the remote rdiff-backup command
for EXCL_PATH in $REMOTE_EXCLUDE; do
    RDIFFBACKUP_REMOTE_ARGS+=" --exclude=$EXCL_PATH"
done;

# Loop through each VEID
for VEID in $VEIDS; do

    RDIFFBACKUP_CMD="rdiff-backup --force"
    RDIFFBACKUP_LOCAL_CMD="$RDIFFBACKUP_CMD $RDIFFBACKUP_LOCAL_ARGS"
    RDIFFBACKUP_REMOTE_CMD="$RDIFFBACKUP_CMD $RDIFFBACKUP_REMOTE_ARGS"
    PATH_TO_VEID=""

    e "Beginning backup of VEID $VEID";
    flag_exclude_local=0

    # check if VEID dir is symlink
    if [ -L "$VZ_PRIVATE/$VEID" ]; then
       PATH_TO_VEID=$(/usr/bin/readlink -f "$VZ_PRIVATE/$VEID")
       e "$VZ_PRIVATE/$VEID linked to $PATH_TO_VEID"
       SAVE_VZ_PRIVATE="$VZ_PRIVATE"
       SAVE_VEID="$VEID"
       VZ_PRIVATE=$(/usr/bin/dirname "$PATH_TO_VEID")
    fi
    
    if [ "$LOCAL_DIR" != "" ]; then
      re="\b$VEID\b"
      if [[ $VEIDS_EXCLUDE_LOCAL =~ $re ]]; then
        e "Skip local backup VEID $VEID due exclude"
        flag_exclude_local=1
      else
	e "Doing first pass sync"
	e "Doing local backup VEID $VEID"
	e "$RDIFFBACKUP_LOCAL_CMD $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID"
	LLOG=$($RDIFFBACKUP_LOCAL_CMD --print-statistics $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID 2>&1)
	if [ $? -gt 0 ]; then
	      ALERT1="Alert rdiff-backup LOCAL stage error !"$'\n'
	      ALERT1=${ALERT1}"$RDIFFBACKUP_LOCAL_CMD $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID"$'\n'$'\n'
	      ALERT1=${ALERT1}${LLOG}
	fi
	e "$LLOG"
	echo -e "$LLOG" > ${STATISTICS_LOCAL_LOG}_${VEID}.tmp

	e "Removing old files"
	LLOG=$($RDIFFBACKUP_CMD --remove-older-than $REMOVE_LOCAL_AGE $LOCAL_DIR/$VEID 2>&1)
	if [ $? -gt 0 ]; then
	      ALERT11="Alert rdiff-backup LOCAL stage error !"$'\n'
	      ALERT11=${ALERT11}"$RDIFFBACKUP_CMD --remove-older-than $REMOVE_LOCAL_AGE $LOCAL_DIR/$VEID"
	      ALERT11=${ALERT11}${LLOG}
	fi
        e "$LLOG"
	if [ "$CHKPNT_ENABLED" != "" -a "$CHKPNT_ENABLED" != "NO" -a "$CHKPNT_ENABLED" != "no" ]; then
	    # If the VE is running, suspend, re-rsync and then resume it ...
	    if [ -n "$(vzctl status $VEID | grep running)" ]; then
		e "Suspending VEID $VEID"
		vzctl chkpnt $VEID --suspend

		e "Doing second pass sync"
		$RDIFFBACKUP_LOCAL_CMD $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID

		e "Resuming VEID: $VEID"
		vzctl chkpnt $VEID --resume

		e "VE operations done."
	    else
		e "# # # Skipping suspend/re-rsync/resume, as the VEID $VEID is not curently running."
	    fi
	fi
      fi
    else
	# if there is no local backup, add local exclude paths to the remote
	RDIFFBACKUP_REMOTE_CMD="$RDIFFBACKUP_CMD $RDIFFBACKUP_LOCAL_ARGS $RDIFFBACKUP_REMOTE_ARGS"
    fi

    re="\b$VEID\b"
    if [[ $VEIDS_EXCLUDE_REMOTE =~ $re ]]; then
      e "Skip remote backup VEID $VEID due exclude"
    else
      for REMOTE_HOST in $REMOTE_HOSTS; do
	e "Doing remote backup VEID $VEID"

	if [ "$LOCAL_DIR" != "" -a $flag_exclude_local -eq 0 ]; then

	    RDIFFBACKUP_REMOTE_CMD=${RDIFFBACKUP_REMOTE_CMD}" --backup-mode --exclude=$LOCAL_DIR/$VEID/rdiff-backup-data"
            DOIT_CMD="$RDIFFBACKUP_REMOTE_CMD --print-statistics $LOCAL_DIR/$VEID $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$VEID"
	    e "$DOIT_CMD"
	    LLOG=$($DOIT_CMD 2>&1)
	    if [ $? -gt 0 ]; then
	      SECONDTRY_CMD=${SECONDTRY_CMD}${DOIT_CMD}$'\n'
	      ALERT21=${ALERT21}"Alert rdiff-backup REMOTE stage error !"$'\n'
	      ALERT21=${ALERT21}${DOIT_CMD}$'\n'
	      ALERT21=${ALERT21}${LLOG}
	     fi
            e "$LLOG"
	    echo -e "$LLOG" > ${STATISTICS_REMOTE_LOG}_${VEID}.tmp

	else
	    DOIT_CMD="$RDIFFBACKUP_REMOTE_CMD --print-statistics $VZ_PRIVATE/$VEID $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$VEID"
	    e "$DOIT_CMD"
	    LLOG=$($DOIT_CMD 2>&1)
	    if [ $? -gt 0 ]; then
	      SECONDTRY_CMD=${SECONDTRY_CMD}${DOIT_CMD}$'\n'
	      ALERT21=${ALERT21}"Alert rdiff-backup REMOTE stage error !"$'\n'
	      ALERT21=${ALERT21}${DOIT_CMD}$'\n'
	      ALERT21=${ALERT21}${LLOG}
            fi
            e "$LLOG"
	    echo -e "$LLOG" > ${STATISTICS_REMOTE_LOG}_${VEID}.tmp
	fi

	e "Removing old files"
	DOIT_CMD="$RDIFFBACKUP_CMD --remove-older-than $REMOVE_REMOTE_AGE $USERNAME@$REMOTE_HOST::$REMOTE_DIR/$VEID"
        e "$DOIT_CMD"
        LLOG=$($DOIT_CMD 2>&1)
	if [ $? -gt 0 ]; then
	      SECONDTRY_CMD=${SECONDTRY_CMD}${DOIT_CMD}$'\n'
	      ALERT22=${ALERT22}"Alert rdiff-backup REMOTE stage error !"$'\n'
	      ALERT22=${ALERT22}${DOIT_CMD}$'\n'
	      ALERT22=${ALERT22}${LLOG}
	fi
        e "$LLOG"
      done;
    fi

    # restore config value
    if [ -n "$PATH_TO_VEID" ]; then
       VZ_PRIVATE="$SAVE_VZ_PRIVATE"
       VEID="$SAVE_VEID"
       PATH_TO_VEID=""
    fi
    e "Done backup of VEID $VEID"
done;

if [ -n "$SECONDTRY_CMD" ]; then
  e ""
  e "################# Second try remote backup #############"
  e "################# sleep 600 seconds        #############"
  e ""
  sleep 600
  OIFS="$IFS"
  IFS=$'\n'
  for DOIT_CMD in $SECONDTRY_CMD ; do
    IFS=$OIFS
    e "$DOIT_CMD"
    LLOG=`$DOIT_CMD 2>&1`
    if [ $? -gt 0 ]; then
      ALERT30="${ALERT30}Alert rdiff-backup REMOTE stage error !"$'\n'
      ALERT30="${ALERT30}${DOIT_CMD}"$'\n'
      ALERT30="${ALERT30}${LLOG}"
    fi
    e "$LLOG"
    IFS=$'\n'
  done
  IFS="$OIFS"
fi

e "All done backup"

if [ -z "$ALERT30" ]; then 
  ALERT21=""
  ALERT22=""
fi

ALERT=${ALERT1}${ALERT11}${ALERT21}${ALERT22}

if [ "$ALERT" != "" ]; then
  ALERT=$HN$'\n'${ALERT1}$'\n'$'\n'${ALERT11}$'\n'$'\n'${ALERT21}$'\n'$'\n'${ALERT22}$'\n'$'\n'${ALERT30}$'\n'
  echo "$ALERT"
  echo "$ALERT" | tr -d '\015' | mail -s "$HN vz-backup error alert" root
fi

if [ "$POSTBACKUP" ]
    then
        eval $POSTBACKUP
fi
