#!/bin/bash
#
# Redis Backup Script
# VER. 0.0.3
#=====================================================================
#=====================================================================
# Set the following variables to your system needs
# (Detailed instructions below variables)
#=====================================================================

# External config - override default values set below
# EXTERNAL_CONFIG="/etc/default/automongobackup" # debian style
# EXTERNAL_CONFIG="/srv/southbridge/etc/redis-backup.conf" # centos style

# Username to access the mongo server e.g. dbuser
# Unnecessary if authentication is off
# DBUSERNAME=""

# Username to access the mongo server e.g. password
# Unnecessary if authentication is off
# DBPASSWORD=""

# Host name (or IP address) of mongo server e.g localhost
DBHOST="localhost"

# Port that mongo is listening on
DBPORT="6379"

# Backup directory location e.g /backups
BACKUPDIR="/var/backups/redis"

# Mail setup
# What would you like to be mailed to you?
# - log : send only log file
# - files : send log file and sql files as attachments (see docs)
# - stdout : will simply output the log to the screen if run manually.
# - quiet : Only send logs if an error occurs to the MAILADDR.
MAILCONTENT="quiet"

# Set the maximum allowed email size in k. (4000 = approx 5MB email [see docs])
MAXATTSIZE="4000"

# Email Address to send mail to? (user@domain.com)
MAILADDR="root"

# ============================================================
# === ADVANCED OPTIONS ( Read the doc's below for details )===
#=============================================================

# Which day do you want weekly backups? (1 to 7 where 1 is Monday)
DOWEEKLY=6

DAILY=6

# Choose Compression type. (gzip or bzip2)
COMP="gzip"

# Choose if the uncompressed folder should be deleted after compression has completed
CLEANUP="yes"

# Additionally keep a copy of the most recent backup in a seperate directory.
LATEST="yes"

# Make Hardlink not a copy
LATESTLINK="yes"

# Use oplog for point-in-time snapshotting.
OPLOG="yes"

# Enable and use journaling.
JOURNAL="yes"

# Dir search with redis config
DIR="/etc"

# redis-cli path
REDISCLI=/usr/bin/redis-cli

BACKUP_AOF="no"
BACKUP_RDB="yes"

# Enable cron for run redis-cli -p port bgrewriteaof
REWRITEAOF="yes"

# when run first job (Day of mont)
CRONSTART=1

# difference between jobs (Days)
CRONDIFFDAY=2

# Choose other Server if is Replica-Set Master
#REPLICAONSLAVE="no"

# Command to run before backups (uncomment to use)
# PREBACKUP=""

# Command run after backups (uncomment to use)
# POSTBACKUP=""

# === Advanced options ===
#
# To set the day of the week that you would like the weekly backup to happen
# set the DOWEEKLY setting, this can be a value from 1 to 7 where 1 is Monday,
# The default is 6 which means that weekly backups are done on a Saturday.
#
# Use PREBACKUP and POSTBACKUP to specify Pre and Post backup commands
# or scripts to perform tasks either before or after the backup process.
#=====================================================================
# Backup Rotation..
#=====================================================================
#
# Daily Backups are rotated weekly.
#
# Weekly Backups are run by default on Saturday Morning when
# cron.daily scripts are run. This can be changed with DOWEEKLY setting.
#
# Weekly Backups are rotated on a 5 week cycle.
# Monthly Backups are run on the 1st of the month.
# Monthly Backups are NOT rotated automatically.
#
# It may be a good idea to copy Monthly backups offline or to another
# server.
#
#=====================================================================
# Please Note!!
#=====================================================================
#
# I take no resposibility for any data loss or corruption when using
# this script.
#
# This script will not help in the event of a hard drive crash. You
# should copy your backups offline or to another PC for best protection.
#
# Happy backing up!
#
#=====================================================================

# Should not need to be modified from here down!!
#

if [ ! -f "/root/.redis" ];then
	exit;
fi 

# Include external config
[ ! -z "$EXTERNAL_CONFIG" ] && [ -f "$EXTERNAL_CONFIG" ] && source "${EXTERNAL_CONFIG}"
# Include extra config file if specified on commandline, e.g. for backuping several remote dbs from central server
[ ! -z "$1" ] && [ -f "$1" ] && source ${1}

#=====================================================================

PATH=/usr/local/bin:/usr/bin:/bin
DATE=`date +%Y-%m-%d_%Hh%Mm` # Datestamp e.g 2002-09-21
DOW=`date +%A` # Day of the week e.g. Monday
DNOW=`date +%u` # Day number of the week 1 to 7 where 1 represents Monday
DOM=`date +%d` # Date of the Month e.g. 27
M=`date +%B` # Month e.g January
W=`date +%V` # Week Number e.g 37
VER=0.0.1 # Version Number
LOGFILE=$BACKUPDIR/$DBHOST-`date +%N`.log # Logfile Name
LOGERR=$BACKUPDIR/ERRORS_$DBHOST-`date +%N`.log # Logfile Name
BACKUPFILES=""
OPT="" # OPT string for use with mongodump
DAY=`date +%d%m%Y`
CRONMSGTMP=/tmp/cron_redis_rewriteaof
CRONMSG=/etc/cron.d/redis_rewriteaof

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

if [ ! "$DO_HOT_BACKUP" ];
    then
    DO_HOT_BACKUP="no"
fi
# Create required directories
if [ ! -e "$BACKUPDIR" ] # Check Backup Directory exists.
    then
    mkdir -p "$BACKUPDIR"
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

# When a desire is to receive log via e-mail then we close stdout and stderr.
[ "x$MAILCONTENT" == "xlog" ] && exec 6>&- 7>&-

# Functions

rotateFolder () {
mdbdir="$1"
## set to the number of monthly backups to keep
keep="$2"

(cd ${mdbdir}

    totalFilesCount=`/bin/ls -1 | egrep ".rdb|.aof|.bz2|.tgz|.gz|.log" | wc -l`

    if [ ${totalFilesCount} -gt ${keep} ]; then
        purgeFilesCount=`expr ${totalFilesCount} - ${keep}`
        purgeFilesList=`/bin/ls -1tr | egrep ".rdb|.aof|.bz2|.tgz|.gz|.log" | head -${purgeFilesCount}`

        echo ""
        echo "Rotating Folder: Purging in ${mdbdir}"
        rm -fv ${purgeFilesList} | sed -e 's/^//g'
    fi
)
}


# Database dump function
dbdump () {

for i in `find $DIR -maxdepth 1 -name "redis*.conf" -type f -print | grep -v "sentinel"`
do

    DBPORT=`cat $i | grep -v "^#" | grep "." | grep port | awk '{print($2)}'`
    DBPATH=`cat $i | grep -v "^#" | grep "." | grep dir | awk '{print($2)}'`
    DBFILE=`cat $i | grep -v "^#" | grep "." | grep dbfilename | awk '{print($2)}'`
    DBFILE=`basename $DBFILE`
    DBPASS=`cat $i | grep -v "^#" | grep "." | grep requirepass | awk '{print($2)}'`
    APPEND=`cat $i | egrep -v "^#|aof" | grep "." | grep appendonly | awk '{print($2)}'`
    if [ "$APPEND" = "yes" ];then
	APPENDFILE=`cat $i | grep -v "^#" | grep "." | grep appendfilename | awk '{print($2)}' | sed "s/\"//g"`
	APPENDFILE=`basename $APPENDFILE`
    fi
    if [ -z "$DBPASS" ];then
	DBPASS="password"
    fi
    BACKUPDIRNAME=$BACKUPDIR/$DBPORT/
    [ ! -d "$BACKUPDIRNAME" ] && mkdir $BACKUPDIRNAME
    if [ "$BACKUP_RDB" = "yes" ];then
	#$REDISCLI -p $DBPORT -a $DBPASS bgsave >> /dev/null
	/bin/cp -f ${DBPATH}${DBFILE} ${BACKUPDIRNAME}${DATE}_$DBFILE
	compression $BACKUPDIRNAME ${DATE}_$DBFILE
    fi
    if [ "$APPEND" = "yes" -a "$BACKUP_AOF" = "yes" ];then
	/bin/cp -f ${DBPATH}${APPENDFILE} ${BACKUPDIRNAME}${DATE}_$APPENDFILE
	compression $BACKUPDIRNAME ${DATE}_$APPENDFILE
    fi

    if [ "$REWRITEAOF" = "yes" -a "$APPEND" = "yes" ];then
	if [ ! -e $CRONMSG ];then
    	    echo "0 0 $CRONSTART * * root $REDISCLI -p $DBPORT -a $DBPASS bgrewriteaof >/dev/null" >> $CRONMSGTMP
    	    CRONSTART=`expr $CRONSTART + $CRONDIFFDAY`
	fi
    fi

    #rotate backups
    if [ "$APPEND" = "yes" -a "$BACKUP_AOF" = "yes" -a "$BACKUP_RDB" = "yes" ];then
        rotateFolder $BACKUPDIRNAME `expr $DAILY \* 2`
    else
        rotateFolder $BACKUPDIRNAME $DAILY
    fi

done

}

# Compression function plus latest copy
SUFFIX=""
compression () {
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
    $COPY $1$2$SUFFIX "$BACKUPDIRNAME/latest/"
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

echo ======================================================================
echo AutoRedisBackup VER $VER

echo
echo Backup of Database Server - $HOST on $DBHOST
echo ======================================================================

echo Backup Start `date`

echo ======================================================================

    echo Doing backup
    dbdump 

    if [ "$REWRITEAOF" = "yes" -a ! -e $CRONMSG -a -e $CRONMSGTMP ];then
	cat $CRONMSGTMP > $CRONMSG
    	/sbin/service crond reload
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


# Clean Backup Logs
rotateFolder $BACKUPDIR `expr $DAILY \* 2`

# Clean up IO redirection if we plan not to deliver log via e-mail.
[ ! "x$MAILCONTENT" == "xlog" ] && exec 1>&6 2>&7 6>&- 7>&-

if [ "$MAILCONTENT" = "log" ]
    then
    cat "$LOGFILE" | mail -s "Redis Backup Log for $HOST - $DATE" $MAILADDR

    if [ -s "$LOGERR" ]
        then
	sed -i "/^connected/d" "$LOGERR"
    fi

    if [ -s "$LOGERR" ]
	then
	if [ -s "$LOGERR" ]
    	    then
	    cat "$LOGERR"
	    (cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: Redis Backup error Log for $HOST - $DATE" $MAILADDR
	fi
    fi
elif [ "$MAILCONTENT" = "quiet" ]
    then
    if [ -s "$LOGERR" ]
    then
	(cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: Redis Backup error Log for $HOST - $DATE" $MAILADDR
	cat "$LOGFILE" | mail -s "Redis Backup Log for $HOST - $DATE" $MAILADDR
    fi
else
    if [ -s "$LOGERR" ]
	then
	sed -i "/^connected/d" "$LOGERR"
    fi

    if [ -s "$LOGERR" ]
	then
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

# TODO: Would be nice to know if there were any *actual* errors in the $LOGERR
#STATUS=1
if [ -s "$LOGERR" ]
    then
	STATUS=1
    else
        STATUS=0
	eval rm -f "$LOGFILE"
	eval rm -f "$LOGERR"
fi
# Clean up Logfile
eval rm -f "$CRONMSGTMP"

exit $STATUS
