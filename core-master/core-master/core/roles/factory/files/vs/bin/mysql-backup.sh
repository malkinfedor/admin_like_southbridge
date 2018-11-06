#!/bin/bash

# Southbridge MySQL backup script by Igor Olemskoi <igor@southbridge.ru> (based on AutoMySQLBackup)
# Ver 5.0

#=====================================================================
# Options documantation
#=====================================================================
# Set USERNAME and PASSWORD of a user that has at least SELECT permission
# to ALL databases.
#
# Set the DBHOST option to the server you wish to backup, leave the
# default to backup "this server".(to backup multiple servers make
# copies of this file and set the options for that server)
#
# Put in the list of DBNAMES(Databases)to be backed up. If you would like
# to backup ALL DBs on the server set DBNAMES="all".(if set to "all" then
# any new DBs will automatically be backed up without needing to modify
# this backup script when a new DB is created).
#
# If the DB you want to backup has a space in the name replace the space
# with a % e.g. "data base" will become "data%base"
# NOTE: Spaces in DB names may not work correctly when SEPDIR=no.
#
# You can change the backup storage location from /backups to anything
# you like by using the BACKUPDIR setting..
#
# The MAILCONTENT and MAILADDR options and pretty self explanitory, use
# these to have the backup log mailed to you at any email address or multiple
# email addresses in a space seperated list.
# (If you set mail content to "log" you will require access to the "mail" program
# on your server. If you set this to "files" you will have to have mutt installed
# on your server. If you set it to "stdout" it will log to the screen if run from 
# the console or to the cron job owner if run through cron. If you set it to "quiet"
# logs will only be mailed if there are errors reported. )
#
# MAXATTSIZE sets the largest allowed email attachments total (all backup files) you
# want the script to send. This is the size before it is encoded to be sent as an email
# so if your mail server will allow a maximum mail size of 5MB I would suggest setting
# MAXATTSIZE to be 25% smaller than that so a setting of 4000 would probably be fine.
#
# Finally copy automysqlbackup.sh to anywhere on your server and make sure
# to set executable permission. You can also copy the script to
# /etc/cron.daily to have it execute automatically every night or simply
# place a symlink in /etc/cron.daily to the file if you wish to keep it 
# somwhere else.
# NOTE:On Debian copy the file with no extention for it to be run
# by cron e.g just name the file "automysqlbackup"
#
# Thats it..
#
#
# === Advanced options doc's ===
#
# The list of MDBNAMES is the DB's to be backed up only monthly. You should
# always include "mysql" in this list to backup your user/password
# information along with any other DBs that you only feel need to
# be backed up monthly. (if using a hosted server then you should
# probably remove "mysql" as your provider will be backing this up)
# NOTE: If DBNAMES="all" then MDBNAMES has no effect as all DBs will be backed
# up anyway.
#
# If you set DBNAMES="all" you can configure the option DBEXCLUDE. Other
# wise this option will not be used.
# This option can be used if you want to backup all dbs, but you want 
# exclude some of them. (eg. a db is to big).
#
# Set CREATE_DATABASE to "yes" (the default) if you want your SQL-Dump to create
# a database with the same name as the original database when restoring.
# Saying "no" here will allow your to specify the database name you want to
# restore your dump into, making a copy of the database by using the dump
# created with automysqlbackup.
# NOTE: Not used if SEPDIR=no
#
# The SEPDIR option allows you to choose to have all DBs backed up to
# a single file (fast restore of entire server in case of crash) or to
# seperate directories for each DB (each DB can be restored seperately
# in case of single DB corruption or loss).
#
# To set the day of the week that you would like the weekly backup to happen
# set the DOWEEKLY setting, this can be a value from 1 to 7 where 1 is Monday,
# The default is 6 which means that weekly backups are done on a Saturday.
#
# COMP is used to choose the copmression used, options are gzip or bzip2.
# bzip2 will produce slightly smaller files but is more processor intensive so
# may take longer to complete.
#
# COMMCOMP is used to enable or diable mysql client to server compression, so
# it is useful to save bandwidth when backing up a remote MySQL server over
# the network. 
#
# LATEST is to store an additional copy of the latest backup to a standard
# location so it can be downloaded bt thrid party scripts.
#
# If the DB's being backed up make use of large BLOB fields then you may need
# to increase the MAX_ALLOWED_PACKET setting, for example 16MB..
#
# When connecting to localhost as the DB server (DBHOST=localhost) sometimes
# the system can have issues locating the socket file.. This can now be set
# using the SOCKET parameter.. An example may be SOCKET=/private/tmp/mysql.sock
#
# Use PREBACKUP and POSTBACKUP to specify Per and Post backup commands
# or scripts to perform tasks either before or after the backup process.
#
#
#=====================================================================
# Backup Rotation..
#=====================================================================
#
# Daily Backups are rotated weekly..
# Weekly Backups are run by default on Saturday Morning when
# cron.daily scripts are run...Can be changed with DOWEEKLY setting..
# Weekly Backups are rotated on a 5 week cycle..
# Monthly Backups are run on the 1st of the month..
# Monthly Backups are NOT rotated automatically...
# It may be a good idea to copy Monthly backups offline or to another
# server..
#
#=====================================================================
# Please Note!!
#=====================================================================
#
# I take no resposibility for any data loss or corruption when using
# this script..
# This script will not help in the event of a hard drive crash. If a 
# copy of the backup has not be stored offline or on another PC..
# You should copy your backups offline regularly for best protection.
#
# Happy backing up...
#
#=====================================================================
# Restoring
#=====================================================================
# Firstly you will need to uncompress the backup file.
# eg.
# gunzip file.gz (or bunzip2 file.bz2)
#
# Next you will need to use the mysql client to restore the DB from the
# sql file.
# eg.
# mysql --user=username --pass=password --host=dbserver database < /path/file.sql
# or
# mysql --user=username --pass=password --host=dbserver -e "source /path/file.sql" database
#
# NOTE: Make sure you use "<" and not ">" in the above command because
# you are piping the file.sql to mysql and not the other way around.
#
# Lets hope you never have to use this.. :)
#
#=====================================================================
# Change Log
#=====================================================================
#
# VER 2.5 - (2006-01-15)
#		Added support for setting MAXIMUM_PACKET_SIZE and SOCKET parameters (suggested by Yvo van Doorn)
# VER 2.4 - (2006-01-23)
#    Fixed bug where weekly backups were not being rotated. (Fix by wolf02)
#    Added hour an min to backup filename for the case where backups are taken multiple
#    times in a day. NOTE This is not complete support for mutiple executions of the script
#    in a single day.
#    Added MAILCONTENT="quiet" option, see docs for details. (requested by snowsam)
#    Updated path statment for compatibility with OSX.
#    Added "LATEST" to additionally store the last backup to a standard location. (request by Grant29)
# VER 2.3 - (2005-11-07)
#    Better error handling and notification of errors (a long time coming)
#    Compression on Backup server to MySQL server communications. 
# VER 2.2 - (2004-12-05)
#    Changed from using depricated "-N" to "--skip-column-names".
#    Added ability to have compressed backup's emailed out. (code from Thomas Heiserowski)
#    Added maximum attachment size setting.
# VER 2.1 - (2004-11-04)
#    Fixed a bug in daily rotation when not using gzip compression. (Fix by Rob Rosenfeld)
# VER 2.0 - (2004-07-28)
#    Switched to using IO redirection instead of pipeing the output to the logfile.
#    Added choice of compression of backups being gzip of bzip2.
#    Switched to using functions to facilitate more functionality.
#    Added option of either gzip or bzip2 compression. 
# VER 1.10 - (2004-07-17)
#    Another fix for spaces in the paths (fix by Thomas von Eyben)
#    Fixed bug when using PREBACKUP and POSTBACKUP commands containing many arguments.
# VER 1.9 - (2004-05-25)
#    Small bug fix to handle spaces in LOGFILE path which contains spaces (reported by Thomas von Eyben)
#    Updated docs to mention that Log email can be sent to multiple email addresses.
# VER 1.8 - (2004-05-01)
#    Added option to make backups restorable to alternate database names
#    meaning that a copy of the database can be created (Based on patch by Rene Hoffmann)
#    Seperated options into standard and advanced.
#    Removed " from single file dump DBMANES because it caused an error but
#    this means that if DB's have spaces in the name they will not dump when SEPDIR=no.
#    Added -p option to mkdir commands to create multiple subdirs without error.
#    Added disk usage and location to the bottom of the backup report.
# VER 1.7 - (2004-04-22)
#    Fixed an issue where weelky backups would only work correctly if server
#    locale was set to English (issue reported by Tom Ingberg)
#    used "eval" for "rm" commands to try and resolve rotation issues.
#    Changed name of status log so multiple scripts can be run at the same time.
# VER 1.6 - (2004-03-14)
#   Added PREBACKUP and POSTBACKUP command functions. (patch by markpustjens)
#   Added support for backing up DB's with Spaces in the name.
#   (patch by markpustjens)
# VER 1.5 - (2004-02-24)
#   Added the ability to exclude DB's when the "all" option is used.
#   (Patch by kampftitan)
# VER 1.4 - (2004-02-02)
#   Project moved to Sourceforge.net
# VER 1.3 - (2003-09-25)
#   Added support for backing up "all" databases on the server without
#    having to list each one seperately in the configuration.
#   Added DB restore instructions.
# VER 1.2 - (2003-03-16)
#   Added server name to the backup log so logs from multiple servers
#   can be easily identified.
# VER 1.1 - (2003-03-13)
#   Small Bug fix in monthly report. (Thanks Stoyanski)
#   Added option to email log to any email address. (Inspired by Stoyanski)
#   Changed Standard file name to .sh extention.
#   Option are set using yes and no rather than 1 or 0.
# VER 1.0 - (2003-01-30)
#   Added the ability to have all databases backup to a single dump
#   file or seperate directory and file for each database.
#   Output is better for log keeping.
# VER 0.6 - (2003-01-22)
#   Bug fix for daily directory (Added in VER 0.5) rotation.
# VER 0.5 - (2003-01-20)
#   Added "daily" directory for daily backups for neatness (suggestion by Jason)
#   Added DBHOST option to allow backing up a remote server (Suggestion by Jason)
#   Added "--quote-names" option to mysqldump command.
#   Bug fix for handling the last and first of the year week rotation.
# VER 0.4 - (2002-11-06)
#   Added the abaility for the script to create its own directory structure.
# VER 0.3 - (2002-10-01)
#   Changed Naming of Weekly backups so they will show in order.
# VER 0.2 - (2002-09-27)
#   Corrected weekly rotation logic to handle weeks 0 - 10 
# VER 0.1 - (2002-09-21)
#   Initial Release
#
#=====================================================================
#=====================================================================
#=====================================================================
#
# Should not need to be modified from here down!!
#
#=====================================================================
#=====================================================================
#=====================================================================
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/mysql/bin 
DATE=`date +%Y-%m-%d_%Hh%Mm`				# Datestamp e.g 2002-09-21
DOW=`date +%A`							# Day of the week e.g. Monday
DNOW=`date +%u`						# Day number of the week 1 to 7 where 1 represents Monday
DOM=`date +%d`							# Date of the Month e.g. 27
M=`date +%B`							# Month e.g January
W=`date +%V`							# Week Number e.g 37
VER=2.6									# Version Number
BACKUPFILES=""
OPT="--quote-names --opt --routines --single-transaction --events"	# OPT string for use with mysqldump ( see man mysqldump )
DBEXCLUDE+=" information_schema performance_schema"

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
# "

if [ -f "$LOCATION/etc/mysql-backup.conf.dist" ]; then
    . "$LOCATION/etc/mysql-backup.conf.dist"
    if [ -f "$LOCATION/etc/mysql-backup.conf" ]; then
	. "$LOCATION/etc/mysql-backup.conf"
    fi
    if [ -f "$LOCATION/etc/mysql-backup.local.conf" ]; then
	. "$LOCATION/etc/mysql-backup.local.conf"
    fi
else
    echo "mysql-backup.conf.dist not found"
    exit 0
fi

#### ERRORS HANDLING BEGIN ####

readonly bn=$(basename $0)
typeset -i KEEPLOGS=0

if [[ -z "$LOGFILE" ]]; then
    LOGFILE=${BACKUPDIR}/log/${bn%\.*}-${DBHOST}-$(date +%N).out    # stdout log file
fi
if [[ -z "$LOGERR" ]]; then
    LOGERR=${BACKUPDIR}/log/${bn%\.*}-${DBHOST}-$(date +%N).err     # stderr log file
fi

# traps on ERR is inherited by shell functions, command substitutions,
# and commands executed in a subshell environment.
set -E
# If pipefail is enabled, the pipe‐line's return status is the value of the last
# (rightmost) command to exit with a non-zero status, or zero if all commands exit successfully.
set -o pipefail

if [[ ! -d "${BACKUPDIR}/log" ]]; then		# Check Backup Directory exists.
    mkdir -p "${BACKUPDIR}/log"
fi

# IO redirection for logging.
touch $LOGFILE
exec 6>&1           # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > $LOGFILE     # stdout replaced with file $LOGFILE.

touch $LOGERR
exec 7>&2           # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> $LOGERR     # stderr replaced with file $LOGERR.

except() {
    echo -e "--------\n[trap]: Got signal ${1} in function ${FN:-BODY} DB: $DB$MDB\n-------- " >&2
    KEEPLOGS=1
}

trap 'except SEGV'  SIGSEGV
trap 'except ERR'   ERR

#### ERRORS HANDLING END ####

if /sbin/pidof -x $(basename $0) > /dev/null; then
  for p in $(/sbin/pidof -x $(basename $0)); do
    if [ $p -ne $$ ]; then
      ALERT=${HN}$'\n'"Script $0 is already running: exiting"
      echo "$ALERT" | mail -s "ERRORS REPORTED: MySQL Backup error Log $HN" root
      exit
    fi
  done
fi

# Add --compress mysqldump option to $OPT
if [ "$COMMCOMP" = "yes" ];
	then
		OPT="$OPT --compress"
	fi

# Add --compress mysqldump option to $OPT
if [ "$MAX_ALLOWED_PACKET" ];
	then
		OPT="$OPT --max_allowed_packet=$MAX_ALLOWED_PACKET"
	fi

if [ ! "$BACKUP_DAYS" ]; then
	BACKUP_DAYS=7
fi

if [ 0$BACKUP_DAYS -eq 0 ]; then
	echo "Warning. BACKUP_DAYS in config set to 0. Force change to BACKUP_DAYS=1" | mail -s "ERRORS REPORTED: MySQL Backup error Log $HN" root
	BACKUP_DAYS=1
fi
BACKUP_MINS=$(( $BACKUP_DAYS * 24 * 60 + 12 * 60 ))

if [ ! "$BACKUP_MONTH" ];
	then
		BACKUP_MONTH=4
	fi

if [ ! "$DO_SQL_DUMP" ];
	then
		DO_SQL_DUMP="yes"
	fi

if [ ! "$DO_HOT_BACKUP" ];
	then
		DO_HOT_BACKUP="no"
	fi

if [ ! "$NICE" ]; then
  NICE=20
fi
if [ -x /usr/bin/nice ]; then
  NICE_CMD="/usr/bin/nice -n $NICE"
else 
  NICE_CMD=""
fi

if [ "$COMP" = "gzip" ]; then
    COMP_CMD="| gzip -f "
    SUFFIX=".gz"
elif [ "$COMP" = "bzip2" ]; then
    COMP_CMD="| bzip2 -f "
    SUFFIX=".bz2"
else
    COMP_CMD=""
    SUFFIX=""
fi


# Create required directories
if [ ! -e "/var/lib/mysql.backup" ]             # Check Backup Directory exists.
        then
            mkdir -p "/var/lib/mysql.backup"
fi

if [ ! -e "$BACKUPDIR/daily" ]		# Check Daily Directory exists.
	then
	mkdir -p "$BACKUPDIR/daily"
fi

if [ ! -e "$BACKUPDIR/weekly" ]		# Check Weekly Directory exists.
	then
	mkdir -p "$BACKUPDIR/weekly"
fi

if [ ! -e "$BACKUPDIR/monthly" ]	# Check Monthly Directory exists.
	then
	mkdir -p "$BACKUPDIR/monthly"
fi

if [ "$LATEST" = "yes" ]
then
	if [ ! -e "$BACKUPDIR/latest" ]	# Check Latest Directory exists.
	then
		mkdir -p "$BACKUPDIR/latest"
	fi
eval rm -fv "$BACKUPDIR/latest/*"
fi


echo $LOCATION

# Functions


# Database dump function
dbdump () {
    local FN=$FUNCNAME

    if [ "$SEPTABLE" = "yes" ]; then
        TABLENAMES="$(mysql --user="$USERNAME" --password="$PASSWORD" --host="$DBHOST" --batch --skip-column-names -e "show tables" $1| sed 's/ /%/g')"
	for TABLENAME in $TABLENAMES ; do
	   OUTFILENAME=`echo $2 | sed "s~$3~$3.$TABLENAME~"`
           eval $NICE_CMD mysqldump --user="$USERNAME" --password="'$PASSWORD'" --host="$DBHOST" $OPT $1 $TABLENAME > $OUTFILENAME
        done
        eval $NICE_CMD mysqldump --user="$USERNAME" --password="'$PASSWORD'" --host="$DBHOST" $OPT --no-data $1 > $2
    else
    ###
       CNT=0
       while [ $CNT -lt 2 ];do
        CNT=$((CNT+1))
	echo "Base ($1) dump, try $CNT"
	eval $NICE_CMD mysqldump --user="'$USERNAME'" --password="'$PASSWORD'" --host="$DBHOST" $OPT $1 $COMP_CMD > $2$SUFFIX
        DBDUMPRES=$?
        if [ $DBDUMPRES -eq 2 ];then
            if [ "$(tail $LOGERR | grep "crashed")" ];then
		echo "Base ($1) crashed, try $CNT repair "
                eval mysqlcheck --user="'$USERNAME'" --password="'$PASSWORD'" --host="'$DBHOST'" -c -e --auto-repair $1
                REPAIRCODE=$?
                if [ $REPAIRCODE -eq 0 ];then
		    echo "Base ($1) repaired OK, try new dump"
                    exec 2>&7 7>&-
                    eval sed -i '/crashed/d' $LOGERR
                    exec 7>&2 2>$LOGERR
                else
                    CNT=2
                fi
            else
                CNT=2
            fi
        else
	    echo "Base ($1) dump OK"
            CNT=2
        fi
       done
    ###
    fi
    return 0
}

# Database dump function
dbdump_mydumper () {
    local FN=$FUNCNAME

    MYOPT=""
	# Add --ignore-table options to $MYOPT

	if [ -n "$TABLEEXCLUDE" ]; then
	    for table in $TABLEEXCLUDE ; do
		MYOPT="${MYOPT}${table}|"
	    done
	fi
        if [ -n "$DBEXCLUDE" ]; then
            for table in $DBEXCLUDE ; do
                MYOPT="${MYOPT}${table}|"
            done
        fi
        if [ -n "$MYOPT" ]; then
            MYOPT="--regex '^(?!(${MYOPT}mysql.noptable))'"
        fi

    eval $NICE_CMD mydumper --user "$USERNAME" --password "'$PASSWORD'" -c -l 300 --kill-long-queries -s 500000 $MYOPT -o $1 

    if [ $? -gt 0 ]; then 
          echo "Error in mydumper backup stage" >&2
          eval mysql -u root --password="'$PASSWORD'" -e "SHOW FULL PROCESSLIST" | sort -n -k 6 >&2
          return 1
    fi

    /usr/bin/find "$BACKUPDIR/daily" -name "_mydumper*" -type d -mmin +$BACKUP_MINS -print0 | xargs -0 rm -rf
    /usr/bin/find "$BACKUPDIR/weekly" -name "_mydumper*" -type d -mtime +35 -print0 | xargs -0 rm -rf
    /usr/bin/find "$BACKUPDIR/monthly" -name "_mydumper*" -type d -mtime +100 -print0 | xargs -0 rm -rf
    return 0
}

dbdump_h () {
    local FN=$FUNCNAME

    if [ ! -f /usr/bin/innobackupex ]; then
	yum -y install percona-xtrabackup.x86_64
    fi
    mkdir -p $1
    echo Full backup stage started at `date`
    eval $NICE_CMD /usr/bin/innobackupex --user=root --password="'$PASSWORD'" --no-timestamp --rsync --tmpdir=/tmp $1 2>&1
    if [ $? -gt 0 ]; then 
      echo "Error in full backup stage" >&2
    fi
    eval /usr/bin/innobackupex --user=root --password="'$PASSWORD'" --apply-log --tmpdir=/tmp $1 2>&1
    if [ $? -gt 0 ]; then 
      echo "Error in apply log redo stage" >&2
    fi
    echo Full backup stage finished at `date` code $?
return 0
}

dbdump_h_xtra () {
    local FN=$FUNCNAME

    if [ ! -f /usr/bin/innobackupex ]; then
	yum -y install percona-xtrabackup-24.x86_64
    fi
    if [ -f /var/lib/mysql-xtra/xtrabackup_checkpoints ]; then
       if [ -d /var/lib/mysql-xtra.yesterday ]; then
          rm -rf /var/lib/mysql-xtra.yesterday
       fi
       mv /var/lib/mysql-xtra /var/lib/mysql-xtra.yesterday
    fi
	echo Full backup stage started at `date`
	#ionice -c3 
	eval $NICE_CMD /usr/bin/innobackupex --defaults-file=/etc/my.cnf --password="'$PASSWORD'" --no-timestamp  --throttle=40 --rsync /var/lib/mysql-xtra 2>&1
        if [ $? -gt 0 ]; then 
          echo "Error in full backup stage" >&2
        fi
	#ionice -c3 
	eval $NICE_CMD /usr/bin/innobackupex --defaults-file=/etc/my.cnf --apply-log --redo-only --password="'$PASSWORD'" --no-timestamp  --throttle=40 /var/lib/mysql-xtra 2>&1
	if [ $? -gt 0 ]; then 
    	  echo "Error in apply log redo stage" >&2
        fi
	echo Full backup stage finished at `date` code $?
return 0
}

# Compression function plus latest copy
compression () {
    local FN=$FUNCNAME

    if [ "$SEPTABLE" = "yes" ]; then
        TBDIR=`/usr/bin/dirname $2`
        TFNAME=`/bin/basename $2`
	if [ "$COMP" = "gzip" ]; then
    	    TPWD=`pwd`    
            cd $TBDIR
	    $NICE_CMD tar -czvf "$1.tgz" ${TFNAME}*.sql 2>&1
    	    cd $TPWD
    	    SUFFIX=".tgz"
	elif [ "$COMP" = "bzip2" ]; then
    	    TPWD=`pwd`
            cd $TBDIR
	    $NICE_CMD tar -cjvf "$1.tbz2" ${TFNAME}*.sql 2>&1
    	    cd $TPWD
    	    SUFFIX=".tbz2"
    	fi
    	rm -f ${2}*.sql
    fi
    if [ "$LATEST" = "yes" ]; then
	cp $1$SUFFIX "$BACKUPDIR/latest/"
    fi	
    return 0
}


# Compression function plus latest copy
compression_h () {
    local FN=$FUNCNAME

    if [ "$COMP" = "gzip" ]; then
        TPWD=`pwd`
        cd "$1"
        $NICE_CMD tar --remove-files -czvf "$1.tgz" * 2>&1
	cd $TPWD
	rm -rf "$1"
        SUFFIX=".tgz"
    elif [ "$COMP" = "bzip2" ]; then
        TPWD=`pwd`
        cd "$1"
        $NICE_CMD tar --remove-files -cjvf "$1.tbz2" * 2>&1
	cd $TPWD
	rm -rf "$1"
        SUFFIX=".tbz2"
    else
        echo "No compression option set, check advanced settings"
    fi
    if [ "$LATEST" = "yes" ]; then
        cp $1$SUFFIX "$BACKUPDIR/latest/"
    fi
    return 0
}


## rotates monthly backups, set 'keep' to the last n backups to keep
rotateMonthly () {
    local FN=$FUNCNAME

mdbdir="$1"

## set to the number of monthly backups to keep
keep=$BACKUP_MONTH

(cd ${mdbdir}

    totalFilesCount=`/bin/ls -1 | wc -l`

    if [ ${totalFilesCount} -gt ${keep} ]; then
	purgeFilesCount=`expr ${totalFilesCount} - ${keep}`
	purgeFilesList=`/bin/ls -1tr | head -${purgeFilesCount}`

	echo ""
	echo "Rotating monthly: Purging in ${mdbdir}"
	rm -fv ${purgeFilesList} | sed -e 's/^//g'
    fi
)
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

# Add --ignore-table options to $OPT
if [ -n "$TABLEEXCLUDE" ]; then
	for table in $TABLEEXCLUDE ; do
		OPT="${OPT} --ignore-table=${table}"
	done
fi


if [ "$SEPDIR" = "yes" ]; then # Check if CREATE DATABSE should be included in Dump
	if [ "$CREATE_DATABASE" = "no" ]; then
		OPT="$OPT --no-create-db"
	else
		OPT="$OPT --databases"
	fi
else
	OPT="$OPT --databases"
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

# If backing up all DBs on the server
if [ "$DBNAMES" = "all" ]; then
        DBNAMES="$(mysql --user="$USERNAME" --password="$PASSWORD" --host="$DBHOST" --batch --skip-column-names -e "show databases"| sed 's/ /%/g')"

	# If DBs are excluded
	for exclude in $DBEXCLUDE
	do
		DBNAMES=`echo $DBNAMES | sed -r "s/\s+$exclude\s+/ /g; s/^\s*$exclude\s+/ /g; s/\s+$exclude\s*$/ /g"`
	done
        MDBNAMES=$DBNAMES
else
  regexp_exp='\bmysql\b'
  if [[ $DBNAMES =~ $regexp_exp ]]; then
    MDBNAMES=$DBNAMES
  else
    MDBNAMES="mysql $DBNAMES"
  fi
fi

echo ======================================================================
echo AutoMySQLBackup VER $VER
echo http://sourceforge.net/projects/automysqlbackup/
echo 
echo Backup of Database Server - $HOST
echo ======================================================================

if [ "$DO_SQL_DUMP" = "yes" ]; then

echo Backup Start Time `date`
echo ======================================================================

	# Monthly Full Backup of all Databases
	if [ $DOM = "01" ]; then
		for MDB in $MDBNAMES
		do
 			 # Prepare $DB for using
		        MDB="`echo $MDB | sed 's/%/ /g'`"

			if [ ! -e "$BACKUPDIR/monthly/$MDB" ]		# Check Monthly DB Directory exists.
			then
				mkdir -p "$BACKUPDIR/monthly/$MDB"
			fi
			echo Monthly Backup of $MDB...
				dbdump "$MDB" "$BACKUPDIR/monthly/$MDB/${MDB}_$DATE.$M.sql" "$BACKUPDIR/monthly/$MDB/${MDB}"  
				compression "$BACKUPDIR/monthly/$MDB/${MDB}_$DATE.$M.sql" "$BACKUPDIR/monthly/$MDB/${MDB}"
				BACKUPFILES="$BACKUPFILES $BACKUPDIR/monthly/$MDB/${MDB}_$DATE.$M.sql$SUFFIX"
			echo ----------------------------------------------------------------------
			TTT=`expr 33 \* $BACKUP_MONTH`
		        /usr/bin/find "$BACKUPDIR/monthly/$MDB" -name "*.sql.*" -mtime +$TTT -type f -delete

		done
	else

		for DB in $DBNAMES
		do
		# Prepare $DB for using
		DB="`echo $DB | sed 's/%/ /g'`"
	
		# Create Seperate directory for each DB
		if [ ! -e "$BACKUPDIR/daily/$DB" ]		# Check Daily DB Directory exists.
		then
			mkdir -p "$BACKUPDIR/daily/$DB"
		fi
		if [ $BACKUP_DAYS -le 7 ]; then
		    if [ ! -e "$BACKUPDIR/weekly/$DB" ]		# Check Weekly DB Directory exists.
		    then
			mkdir -p "$BACKUPDIR/weekly/$DB"
		    fi
		    # Weekly Backup
		fi
    		if [ $DNOW = $DOWEEKLY -a $BACKUP_DAYS -le 7 ]; then
		    echo Weekly Backup of Database \( $DB \)
		    echo Rotating 5 weeks Backups...
		    if [ "$W" -le 05 ];then
				REMW=`expr 48 + $W`
			elif [ "$W" -lt 15 ];then
				REMW=0`expr $W - 5`
			else
				REMW=`expr $W - 5`
		    fi
		    eval rm -fv "$BACKUPDIR/weekly/$DB/${DB}_week.$REMW.*" 
		    echo
			dbdump "$DB" "$BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.sql" "$BACKUPDIR/weekly/$DB/${DB}"
			compression "$BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.sql" "$BACKUPDIR/weekly/$DB/${DB}"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.sql$SUFFIX"
		    echo ----------------------------------------------------------------------
		# Daily Backup
		else
		    echo Daily Backup of Database \( $DB \)
		    echo Rotating last weeks Backup...
		    /usr/bin/find "$BACKUPDIR/daily/$DB" -name "*.sql.*" -mmin +$BACKUP_MINS -delete
		    echo
			dbdump "$DB" "$BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.sql" "$BACKUPDIR/daily/$DB/${DB}"
			compression "$BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.sql" "$BACKUPDIR/daily/$DB/${DB}"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.sql$SUFFIX"
		    echo ----------------------------------------------------------------------
		fi
		done
	fi
echo Backup End `date`
echo ======================================================================
fi

#### HOT BACKUP
if [ "$DO_HOT_BACKUP" = "yes" ]; then

    echo HOT Backup Start `date`
    echo ======================================================================
    # Monthly HOT Full Backup of all Databases
    if [ $DOM = "01" ]; then
        echo Monthly full Backup of \( $MDBNAMES \)...
        dbdump_h "$BACKUPDIR/monthly/$DATE.$M.snapshot.sql"
        compression_h "$BACKUPDIR/monthly/$DATE.$M.snapshot.sql"
        BACKUPFILES="$BACKUPFILES $BACKUPDIR/monthly/$DATE.$M.snapshot.sql$SUFFIX"
        echo ----------------------------------------------------------------------
	TTT=`expr 33 \* $BACKUP_MONTH`
        /usr/bin/find "$BACKUPDIR/monthly/" -maxdepth 1 -name "*.snapshot.sql.*" -mtime +$TTT -type f -delete
    else
# Weekly Backup
    if [ $DNOW = $DOWEEKLY -a $BACKUP_DAYS -le 7 ]; then
        echo Weekly Backup of Databases \( $DBNAMES \)
        echo
        echo Rotating 5 weeks Backups...
	if [ "$W" -le 05 ];then
                REMW=`expr 48 + $W`
        elif [ "$W" -lt 15 ];then
                REMW=0`expr $W - 5`
        else
	        REMW=`expr $W - 5`
        fi
        eval rm -fv "$BACKUPDIR/weekly/week.$REMW.*"
        echo
        dbdump_h "$BACKUPDIR/weekly/week.$W.$DATE.snapshot.sql"
        compression_h "$BACKUPDIR/weekly/week.$W.$DATE.snapshot.sql"
        BACKUPFILES="$BACKUPFILES $BACKUPDIR/weekly/week.$W.$DATE.snapshot.sql$SUFFIX"
        echo ----------------------------------------------------------------------
# Daily Backup
    else
        echo Daily Backup of Databases \( $DBNAMES \)
        echo
        echo Rotating last weeks Backup...
        /usr/bin/find "$BACKUPDIR/daily/" -maxdepth 1 -name "*.snapshot.sql.*" -mmin +$BACKUP_MINS -type f -delete
        echo
        dbdump_h "$BACKUPDIR/daily/$DATE.$DOW.snapshot.sql"
        compression_h "$BACKUPDIR/daily/$DATE.$DOW.snapshot.sql"
        BACKUPFILES="$BACKUPFILES $BACKUPDIR/daily/$DATE.$DOW.snapshot.sql$SUFFIX"
        echo ----------------------------------------------------------------------
    fi
    fi
    echo Backup End Time `date`
    echo ======================================================================
fi

#### HOT XTRA BACKUP
if [ "$HOT_XTRA_BACKUP" = "yes" ]; then
    dbdump_h_xtra
fi

#### DO_MYDUMPER_BACKUP
if [ "$DO_MYDUMPER_BACKUP" = "yes" ]; then
    # Monthly Full Backup of all Databases
    BACKUPDIRM=$BACKUPDIR/daily/
    if [ $DOM = "01" ]; then
       BACKUPDIRM=$BACKUPDIR/monthly/
    else
      if [ $DNOW = $DOWEEKLY -a $BACKUP_DAYS -le 7 ]; then
        BACKUPDIRM=$BACKUPDIR/weekly/
      fi
    fi
    BACKUPDIRM=${BACKUPDIRM}_mydumper-`date +%F_%R`
    dbdump_mydumper "$BACKUPDIRM"
    if [ $? -gt 0 ]; then
      echo "Error in mydumper backup stage" >&2
    else
      OPT="$OPT --no-data"
      for DB in $DBNAMES
      do
	# Prepare $DB for using
	DB="`echo $DB | sed 's/%/ /g'`"
	dbdump "$DB" "$BACKUPDIRM/$DB-schema.sql"
	compression "$BACKUPDIRM/$DB-schema.sql"
      done
    fi
fi

echo Total disk space used for backup storage..
echo Size - Location
echo `du -hs "$BACKUPDIR"`
echo
echo ======================================================================
echo If you find AutoMySQLBackup valuable please make a donation at
echo http://sourceforge.net/project/project_donations.php?group_id=101066
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

if [[ -f "$LOGERR" ]]; then
    sed -i '/Using a password on the command line interface can be insecure/d' $LOGERR
fi

if [ "$MAILCONTENT" = "files" ]
then
	if [ -s "$LOGERR" ]
	then
		# Include error log if is larger than zero.
		BACKUPFILES="$BACKUPFILES $LOGERR"
		ERRORNOTE="WARNING: Error Reported - "
	fi
	#Get backup size
	ATTSIZE=`du -c $BACKUPFILES | grep "[[:digit:][:space:]]total$" |sed s/\s*total//`
	if [ $MAXATTSIZE -ge $ATTSIZE ]
	then
		BACKUPFILES=`echo "$BACKUPFILES" | sed -e "s# # -a #g"`	#enable multiple attachments
		mutt -s "$ERRORNOTE MySQL Backup Log and SQL Files for $HOST - $DATE" $BACKUPFILES $MAILADDR < $LOGFILE		#send via mutt
	else
		cat "$LOGFILE" | mail -s "WARNING! - MySQL Backup exceeds set maximum attachment size on $HOST - $DATE" $MAILADDR
	fi
elif [ "$MAILCONTENT" = "log" ]
then
	cat "$LOGFILE" | mail -s "MySQL Backup Log for $HOST - $DATE" $MAILADDR
	if [ -s "$LOGERR" ]
		then
			(cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: MySQL Backup error Log for $HOST - $DATE" $MAILADDR
	fi	
elif [ "$MAILCONTENT" = "quiet" ]
then
	if [ -s "$LOGERR" ]
		then
			(cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: MySQL Backup error Log for $HOST - $DATE" $MAILADDR
			cat "$LOGFILE" | mail -s "MySQL Backup Log for $HOST - $DATE" $MAILADDR
	fi
else
	if [ -s "$LOGERR" ]
		then
			cat "$LOGFILE"
			echo
			echo "###### WARNING ######"
			echo "Errors reported during AutoMySQLBackup execution.. Backup failed"
			echo "Error log below.."
			cat "$LOGERR"
	else
		cat "$LOGFILE"
	fi	
fi

if [ -s "$LOGERR" ]
	then
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
