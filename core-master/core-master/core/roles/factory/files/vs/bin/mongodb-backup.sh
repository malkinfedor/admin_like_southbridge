#!/bin/bash
#
# MongoDB Backup Script
# VER. 1.0
# More Info: http://github.com/micahwedemeyer/automongobackup
# add Backup Rotation and local config
#=====================================================================


#=====================================================================
# Set the following variables to your system needs
# (Detailed instructions below variables)
#=====================================================================

PATH=/usr/local/bin:/usr/bin:/bin
DATE=`date +%Y-%m-%d_%Hh%Mm`                            # Datestamp e.g 2002-09-21
DOW=`date +%A`                                                  # Day of the week e.g. Monday
DNOW=`date +%u`                                         # Day number of the week 1 to 7 where 1 represents Monday
DOM=`date +%d`                                                  # Date of the Month e.g. 27
M=`date +%B`                                                    # Month e.g January
W=`date +%V`                                                    # Week Number e.g 37
VER=1.0 # Version Number
BACKUPFILES=""
OPT="" # OPT string for use with mongodump

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
# "

if [ -f "$LOCATION/etc/mongodb-backup.conf.dist" ]; then
  . "$LOCATION/etc/mongodb-backup.conf.dist"
  if [ -f "$LOCATION/etc/mongodb-backup.conf" ]; then
    . "$LOCATION/etc/mongodb-backup.conf"
  fi
  if [ -f "$LOCATION/etc/mongodb-backup.local.conf" ]; then
    . "$LOCATION/etc/mongodb-backup.local.conf"
  fi
else
  echo "mongodb-backup.conf.dist not found"
  exit 0
fi

#### ERRORS HANDLING BEGIN ####

readonly bn=$(basename $0)
typeset -i KEEPLOGS=0

if [[ -z "$LOGFILE" ]]; then
  LOGFILE=${BACKUPDIR}/log/${bn%\.*}-${DBHOST}-$(date '+%F-%T').out    # stdout log file
fi

if [[ -z "$LOGERR" ]]; then
  LOGERR=${BACKUPDIR}/log/${bn%\.*}-${DBHOST}-$(date '+%F-%T').err     # stderr log file
fi

# Username to access the mongo server e.g. dbuser
# Unnecessary if authentication is off
# DBUSERNAME=""

# Username to access the mongo server e.g. password
# Unnecessary if authentication is off
# DBPASSWORD=""

# Should not need to be modified from here down!!
#

if [ ! -f "/root/.mongodb" ];then
	exit;
fi

if /sbin/pidof -x $(basename $0) > /dev/null; then
  for p in $(/sbin/pidof -x $(basename $0)); do
    if [ $p -ne $$ ]; then
      ALERT=${HN}$'\n'"Script $0 is already running: exiting"
      echo "$ALERT" | mail -s "ERRORS REPORTED: MongoDB Backup error Log $HN" root
      exit
    fi
  done
fi

# Do we need to use a username/password?
if [ "$DBUSERNAME" ]
    then
    OPT="$OPT --username=$DBUSERNAME --password=$DBPASSWORD"
fi

if [ ! "$NICE" ]; then
  NICE=20
fi

if [ -x /usr/bin/nice ]; then
  NICE_CMD="/usr/bin/nice -n $NICE"
else
  NICE_CMD=""
fi

# Do we use oplog for point-in-time snapshotting?
if [ "$OPLOG" = "yes" ]
    then
    OPT="$OPT --oplog"
fi

if [ ! "$DO_HOT_BACKUP" ];
    then
    DO_HOT_BACKUP="no"
fi
if [ "$DO_HOT_BACKUP" = "yes" ]; then
    if [ ! -f "$LOCATION/etc/mongo-backup.js" ]; then
	echo "$LOCATION/etc/mongo-backup.js not found"
	exit 0
    fi
fi

# Do we enable and use journaling?
if [ "$JOURNAL" = "yes" ]
    then
    OPT="$OPT --journal"
fi

if [ 0$BACKUP_DAYS -eq 0 ]; then
    echo "Warning. BACKUP_DAYS in config set to 0. Force change to BACKUP_DAYS=1" | mail -s "ERRORS REPORTED: MongoDB Backup error Log $HN" root
    BACKUP_DAYS=1
fi
BACKUP_MINS=$(( $BACKUP_DAYS * 24 * 60 + 12 * 60 ))

# Create required directories
if [ ! -d "$BACKUPDIR" ] # Check Backup Directory exists.
    then
    mkdir -p "$BACKUPDIR"
fi

if [ ! -d "$BACKUPDIR/daily" ] # Check Daily Directory exists.
    then
    mkdir -p "$BACKUPDIR/daily"
fi

if [ ! -d "$BACKUPDIR/weekly" ] # Check Weekly Directory exists.
    then
    mkdir -p "$BACKUPDIR/weekly"
fi

if [ ! -d "$BACKUPDIR/monthly" ] # Check Monthly Directory exists.
    then
    mkdir -p "$BACKUPDIR/monthly"
fi

if [ ! -d "$BACKUPDIR/log" ] # Check Monthly Directory exists.
    then
    mkdir -p "$BACKUPDIR/log"
fi

if [ "$LATEST" = "yes" ]
    then
    if [ ! -d "$BACKUPDIR/latest" ] # Check Latest Directory exists.
	then
	mkdir -p "$BACKUPDIR/latest"
    fi
    eval rm -f "$BACKUPDIR/latest/*"
fi

# IO redirection for logging.
touch $LOGFILE
exec 6>&1 # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > $LOGFILE # stdout replaced with file $LOGFILE.

touch $LOGERR
exec 7>&2 # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> $LOGERR # stderr replaced with file $LOGERR.

except() {
    echo -e "--------\n[trap]: Got signal ${1} in function ${FN:-BODY} DB: $DB$MDB\n-------- " >&2
    KEEPLOGS=1
}

trap 'except SEGV'  SIGSEGV
trap 'except ERR'   ERR

# Functions

# Database dump function
dbdump () {
    local FN=$FUNCNAME
    if [ "$DO_HOT_BACKUP" = "yes" ]; then
	$NICE_CMD mongo admin $LOCATION/etc/mongodb_backup.js
	[ -e "$1" ] && return 0
	echo "ERROR: mongo failed to create hot backup: $1" >&2
	return 1
    else
	$NICE_CMD mongodump --host=$DBHOST:$DBPORT $OPT --out=$1 
	[ -e "$1" ] && return 0
	echo "ERROR: mongodump failed to create dumpfile: $1" >&2
	return 1
    fi
}

#
# Select first available Secondary member in the Replica Sets and show its
# host name and port.
#
function select_secondary_member {
  local FN=$FUNCNAME
  # We will use indirect-reference hack to return variable from this function.
  local __return=$1

  # Return list of with all replica set members
  members=( $(mongo --quiet --eval \
      'rs.conf().members.forEach(function(x){ print(x.host) })') )

  # Check each replset member to see if it's a secondary and return it.
  if [ ${#members[@]} -gt 1 ] ; then
	for member in "${members[@]}" ; do
	    is_secondary=$(mongo --quiet --host $member --eval 'rs.isMaster().secondary')
#'
        	case "$is_secondary" in
        	'true')
                # First secondary wins ...
                secondary=$member
                break
        	;;
        	'false')
                # Skip particular member if it is a Primary.
                continue
        	;;
        	*)
                # Skip irrelevant entries. Should not be any anyway ...
                continue
        	;;
        	esac
	done
  fi

    if [ -n "$secondary" ] ; then
	# Ugly hack to return value from a Bash function ...
	eval $__return="'$secondary'"
    fi
}

# Compression function plus latest copy
SUFFIX=""
compression () {
  local FN=$FUNCNAME
  if [ "$COMP" = "gzip" ]; then
    SUFFIX=".tgz"
    echo Tar and gzip to "$2$SUFFIX"
    cd $1 && tar -cvzf "$2$SUFFIX" "$2"
  elif [ "$COMP" = "bzip2" ]; then
    SUFFIX=".tar.bz2"
    echo Tar and bzip2 to "$2$SUFFIX"
    cd $1 && tar -cvjf "$2$SUFFIX" "$2"
  else
    echo "No compression option set, check advanced settings"
  fi
  if [ "$LATEST" = "yes" ]; then
    if [ "$LATESTLINK" = "yes" ];then
	COPY="cp -l"
    else
	COPY="cp"
    fi
    $COPY $1$2$SUFFIX "$BACKUPDIR/latest/"
  fi
  if [ "$CLEANUP" = "yes" ]; then
    echo Cleaning up folder at "$1$2"
    rm -rf "$1$2"
  fi
  return 0
}

# Run command before we begin
if [ "$PREBACKUP" ]
then
echo ======================================================================
echo "Prebackup command output."
echo
eval $PREBACKUP
echo
echo ======================================================================
echo
fi

# Hostname for LOG information
if [ "$DBHOST" = "localhost" ]; then
    HOST=`hostname`
    if [ "$SOCKET" ]; then
	OPT="$OPT --socket=$SOCKET"
    fi
else
    HOST=$DBHOST
fi

# Try to select an available secondary for the backup or fallback to DBHOST.
#if [ "x${REPLICAONSLAVE}" == "xyes" ] ; then
#  # Return value via indirect-reference hack ...
#  select_secondary_member secondary

#  if [ -n "$secondary" ] ; then
#    DBHOST=${secondary%%:*}
#    DBPORT=${secondary##*:}
#  else
#    SECONDARY_WARNING="WARNING: No suitable Secondary found in the Replica Sets. Falling back to ${DBHOST}."
#  fi
#fi

echo ======================================================================
echo AutoMongoBackup VER $VER

#[ ! -z "$SECONDARY_WARNING" ] &&
#{
#    echo
#    echo "$SECONDARY_WARNING"
#}

echo
echo Backup of Database Server - $HOST on $DBHOST
echo ======================================================================

echo Backup Start `date`
echo ======================================================================
# Monthly Full Backup of all Databases
if [ $DOM = "01" ]; then
    echo Monthly Full Backup

    TTT=`expr 33 \* $BACKUP_MONTH`
    /usr/bin/find "$BACKUPDIR/monthly/" -mtime +$TTT -type f -delete
    dbdump "$BACKUPDIR/monthly/$DATE.$M" &&
    compression "$BACKUPDIR/monthly/" "$DATE.$M"
    echo ----------------------------------------------------------------------
# Weekly Backup
elif [ $DNOW = $DOWEEKLY ]; then
    echo Weekly Backup
    echo
    echo Rotating 5 weeks Backups...
    if [ "$W" -le 05 ];then
       REMW=`expr 48 + $W`
    elif [ "$W" -lt 15 ];then
       REMW=0`expr $W - 5`
    else
       REMW=`expr $W - 5`
    fi
    eval rm -f "$BACKUPDIR/weekly/week.$REMW.*"
    echo
    dbdump "$BACKUPDIR/weekly/week.$W.$DATE" &&
    compression "$BACKUPDIR/weekly/" "week.$W.$DATE"
    echo ----------------------------------------------------------------------
# Daily Backup
else
    echo Daily Backup of Databases
    echo Rotating last day Backup...
    echo
    /usr/bin/find "$BACKUPDIR/daily/" -mmin +$BACKUP_MINS -type f -delete
    echo
    dbdump "$BACKUPDIR/daily/$DATE.$DOW" &&
    compression "$BACKUPDIR/daily/" "$DATE.$DOW"
    echo ----------------------------------------------------------------------
fi
echo Backup End Time `date`
echo ======================================================================

echo Total disk space used for backup storage..
echo Size - Location
echo `du -hs "$BACKUPDIR"`
echo
echo ======================================================================

# Run command when we're done
if [ "$POSTBACKUP" ]
then
echo ======================================================================
echo "Postbackup command output."
echo
eval $POSTBACKUP
echo
echo ======================================================================
fi

#Clean up IO redirection
exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
exec 2>&7 7>&-      # Restore stderr and close file descriptor #7.

if [ -s "$LOGERR" ]; then
    sed -i "/^connected/d" "$LOGERR"
    sed -i "/writing/d" "$LOGERR"
    sed -i "/done/d" "$LOGERR"
    sed -i "/%)$/d" "$LOGERR"
    sed -i "/[0-9\-+:\.]\t$/d" "$LOGERR"
fi

if [ "$MAILCONTENT" = "log" ]
    then
    cat "$LOGFILE" | mail -s "Mongo Backup Log for $HOST - $DATE" $MAILADDR
    if [ -s "$LOGERR" ]; then
      cat "$LOGERR"
      (cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: Mongo Backup error Log for $HOST - $DATE" $MAILADDR
    fi
elif [ "$MAILCONTENT" = "quiet" ]; then
    if [ -s "$LOGERR" ]; then
      cat "$LOGFILE" | mail -s "MongoDB Backup Log for $HOST - $DATE" $MAILADDR
      (cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: MongoDB Backup error Log for $HOST - $DATE" $MAILADDR
    fi
else
    if [ -s "$LOGERR" ]; then
	cat "$LOGFILE"
	echo
	echo "###### WARNING ######"
        echo "STDERR written to during mongodump execution."
        echo "The backup probably succeeded, as mongodump sometimes writes to STDERR, but you may wish to scan the error log below:"
        cat "$LOGERR"
    else
	cat "$LOGFILE"
    fi
fi

if [ -s "$LOGERR" ]; then
  STATUS=1
else
  STATUS=0
fi

# Clean up Logfile (if flag KEEPLOGS is unset)
if (( ! KEEPLOGS )); then
  eval rm -f "$LOGFILE"
  eval rm -f "$LOGERR"
fi

exit $STATUS
