#!/bin/sh

# Southbridge PostgreSQL backup script by Igor Olemskoi <igor@southbridge.ru> (based on AutoMySQLBackup)

PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
DATE=`date +%Y-%m-%d_%Hh%Mm`				# Datestamp e.g 2002-09-21
DOW=`date +%A`						# Day of the week e.g. Monday
DNOW=`date +%u`						# Day number of the week 1 to 7 where 1 represents Monday
DOM=`date +%d`						# Date of the Month e.g. 27
M=`date +%B`						# Month e.g January
W=`date +%V`						# Week Number e.g 37
VER=0.1							# Version Number
HOST=`hostname`
LOGFILE=$BACKUPDIR/$HOST-`date +%s`.log			# Logfile Name
LOGERR=$BACKUPDIR/ERRORS_$HOST-`date +%s`.log		# Logfile Name
BACKUPFILES=""
OPT="--encoding=utf-8 --clean --no-owner"		# OPT string for use with pg_dump ( see man pg_dump )
PORT="5432"						# Port

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."

# "

if [ -f "$LOCATION/etc/postgresql-backup.conf.dist" ]; then
    . "$LOCATION/etc/postgresql-backup.conf.dist"
    if [ -f "$LOCATION/etc/postgresql-backup.conf" ]; then
	. "$LOCATION/etc/postgresql-backup.conf"
    fi
    if [ -f "$LOCATION/etc/postgresql-backup.local.conf" ]; then
	. "$LOCATION/etc/postgresql-backup.local.conf"
    fi
else
    echo "postgresql-backup.conf not found"
    exit 0
fi

if pidof -x $(basename $0) > /dev/null; then
  for p in $(pidof -x $(basename $0)); do
    if [ $p -ne $$ ]; then
      ALERT=${HOST}$'\n'"Script $0 is already running: exiting"
      echo "$ALERT" | mail -s "ERRORS REPORTED: PostgreSQL Backup error Log $HOST" root
      exit
    fi
  done
fi

DBEXCLUDE+=" template0 template1"

if [ ! "$BACKUP_DAYS" ];
    then
        BACKUP_DAYS=7
fi

if [ 0$BACKUP_DAYS -eq 0 ]; then
    echo "$HOST Warning. BACKUP_DAYS in config set to 0. Force change to BACKUP_DAYS=1" | mail -s "ERRORS REPORTED: PostgreSQL Backup error Log $HOST" root
    BACKUP_DAYS=1
fi
BACKUP_MINS=$(( $BACKUP_DAYS * 24 * 60 + 12 * 60 ))

if [ ! "$BACKUP_MONTHLY" ];
    then
        BACKUP_MONTHLY=3
fi

if [ ! "$NICE" ]; then
  NICE=20
fi
if [ -x /usr/bin/nice ]; then
  NICE_CMD="/usr/bin/nice -n $NICE"
else
  NICE_CMD=""
fi

if [ ! "$DO_SQL_DUMP" ];
    then
        DO_SQL_DUMP="no"
fi
if [ ! "$DO_HOT_BACKUP" ];
    then
        DO_HOT_BACKUP="no"
fi

if [ ! "$DO_CUSTOM_DUMP" ];
    then
        DO_CUSTOM_DUMP="yes"
fi
if [ ! "$DO_DBALL_DUMP" ];
    then
        DO_DBALL_DUMP="no"
fi
if [ ! "$DBALLNAME" ];
    then
        DBALLNAME="_dball"
fi

# Create required directories
if [ ! -e "/var/lib/pgsql.backup" ]             # Check Backup Directory exists.
        then
        mkdir -p "/var/lib/pgsql.backup"
fi

if [ ! -e "$BACKUPDIR" ]		# Check Backup Directory exists.
	then
	mkdir -p "$BACKUPDIR"
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

# IO redirection for logging.
touch $LOGFILE
exec 6>&1           # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > $LOGFILE     # stdout replaced with file $LOGFILE.
touch $LOGERR
exec 7>&2           # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> $LOGERR     # stderr replaced with file $LOGERR.


# Functions

# Database dump function
dbdump () {
     DBTEMP=$1
     OUTTEMP=$2
     TBLEX=""
     if [ -n "$TABLEEXCLUDE" ]; then
        for table in $TABLEEXCLUDE ; do
	    arrIN=(${table//./ })
    	    if [ x${arrIN[0]} == x$DBTEMP ]; then
              if [ -z "${arrIN[2]}" ]; then
                TBLEX="${TBLEX} -T ${arrIN[1]}"
              else
                TBLEX="${TBLEX} -T ${arrIN[1]}.${arrIN[2]}"
              fi
    	    fi
        done
     fi
                                
    pg_dump --username=$POSTGRESQL_USERNAME --port=$PORT $OPT $TBLEX $DBTEMP > $OUTTEMP
    return 0
}

dbdump_roles () {
    OUTTEMP=$1
    $NICE_CMD pg_dumpall --username=$POSTGRESQL_USERNAME --port=$PORT --roles-only > $OUTTEMP
    chmod 600 $OUTTEMP
    return 0
}

dbdump_all () {
    OUTTEMP=$1
    $NICE_CMD pg_dumpall --username=$POSTGRESQL_USERNAME --port=$PORT --clean --if-exists > $OUTTEMP
    chmod 600 $OUTTEMP
    return 0
}

dbdump_h () {
    $NICE_CMD rsync -aH --delete --numeric-ids /var/lib/pgsql/ /var/lib/pgsql.backup
    $NICE_CMD psql -U $POSTGRESQL_USERNAME --port $PORT -c "SELECT pg_start_backup('base_backup');"
    rsync -aH --delete --numeric-ids /var/lib/pgsql/ /var/lib/pgsql.backup
    $NICE_CMD psql -U $POSTGRESQL_USERNAME --port $PORT -c "SELECT pg_stop_backup();"
    return 0
}

# Compression function plus latest copy
SUFFIX=""
compression () {
if [ "$COMP" = "gzip" ]; then
	gzip -f "$1"
	echo
	echo Backup Information for "$1"
	$NICE_CMD gzip -l "$1.gz"
	SUFFIX=".gz"
elif [ "$COMP" = "bzip2" ]; then
	echo Compression information for "$1.bz2"
	$NICE_CMD bzip2 -f -v $1 2>&1
	SUFFIX=".bz2"
else
	echo "No compression option set, check advanced settings"
fi
if [ "$LATEST" = "yes" ]; then
	cp $1$SUFFIX "$BACKUPDIR/latest/"
fi	
return 0
}

compression_h () {
if [ "$COMP" = "gzip" ]; then
        TPWD=`pwd`
        cd /var/lib/pgsql.backup
        $NICE_CMD tar -czvf "$1.tgz" . 2>&1
        cd $TPWD
        SUFFIX=".tgz"
elif [ "$COMP" = "bzip2" ]; then
        TPWD=`pwd`
        cd /var/lib/pgsql.backup
        $NICE_CMD tar -cjvf "$1.tbz2" . 2>&1
        cd $TPWD
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

mdbdir="$1"

## set to the number of monthly backups to keep
keep=$BACKUP_MONTHLY

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

# If backing up all DBs on the server
if [ "$DBNAMES" = "all" ]; then
	DBNAMES="`psql --username=$POSTGRESQL_USERNAME --tuples-only --list --port=$PORT | awk {'print $1'} | grep -v ":" | grep -v "|"`"

	# If DBs are excluded
	for exclude in $DBEXCLUDE
	do
		DBNAMES=`echo $DBNAMES | sed -r "s/\s+$exclude\s+/ /g; s/^\s*$exclude\s+/ /g; s/\s+$exclude\s*$/ /g"`
	done

        MDBNAMES=$DBNAMES
fi
	
echo ======================================================================
echo AutoPostgreSQLBackup VER $VER
echo 
echo Backup of Database Server - $HOST
echo ======================================================================

if [ "$DO_SQL_DUMP" = "yes" -o "$DO_CUSTOM_DUMP" = "yes" -o "$DO_DBALL_DUMP" = "yes" ]; then
echo Backup Start Time `date`
echo ======================================================================
  for DB in $DBNAMES
  do
	# Prepare $DB for using
	DB="`echo $DB | sed 's/%/ /g'`"

    # Monthly Full Backup of all Databases
	if [ $DOM = "01" ]; then
		find "$BACKUPDIR/monthly" -name "_roles*.sql" -mtime +200 -delete
		dbdump_roles "$BACKUPDIR/monthly/_roles_$DATE.$M.sql"
		if [ ! -e "$BACKUPDIR/monthly/$DB" ]		# Check Monthly DB Directory exists.
		then
			mkdir -p "$BACKUPDIR/monthly/$DB"
		fi
		echo Monthly Backup of $DB...
		if [ "$DO_CUSTOM_DUMP" = "yes" ]; then
			SOPT=$OPT
			OPT="$OPT --format=c -Z 9"
			dbdump "$DB" "$BACKUPDIR/monthly/$DB/${DB}_$DATE.$M.pgdmp"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/monthly/$DB/${DB}_$DATE.$M.pgdmp"
			OPT=$SOPT
		elif [ "$DO_SQL_DUMP" = "yes" ]; then
			dbdump "$DB" "$BACKUPDIR/monthly/$DB/${DB}_$DATE.$M.sql"
			compression "$BACKUPDIR/monthly/$DB/${DB}_$DATE.$M.sql"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/monthly/$DB/${DB}_$DATE.$M.sql$SUFFIX"
		elif [ "$DO_DBALL_DUMP" = "yes" ]; then
			dbdump_all "$BACKUPDIR/monthly/${DBALLNAME}_$DATE.$M.sql"
			compression "$BACKUPDIR/monthly/${DBALLNAME}_$DATE.$M.sql"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/monthly/${DBALLNAME}_$DATE.$M.sql$SUFFIX"
		fi
                # Delete old backups
                rotateMonthly $BACKUPDIR/monthly/$DB
    # Weekly Backup
	elif [ $DNOW = $DOWEEKLY -a $BACKUP_DAYS -le 7 ]; then
		find "$BACKUPDIR/weekly" -name "_roles*.sql" -mtime +48 -delete
		dbdump_roles "$BACKUPDIR/weekly/_roles_$DATE.$W.sql"
    		if [ ! -e "$BACKUPDIR/weekly/$DB" ]		# Check Weekly DB Directory exists.
			then
			mkdir -p "$BACKUPDIR/weekly/$DB"
		fi	
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
		if [ "$DO_CUSTOM_DUMP" = "yes" ]; then
			SOPT=$OPT
			OPT="$OPT --format=c -Z 9"
			dbdump "$DB" "$BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.pgdmp"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.pgdmp"
			OPT=$SOPT
		elif [ "$DO_SQL_DUMP" = "yes" ]; then
			dbdump "$DB" "$BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.sql"
			compression "$BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.sql"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/weekly/$DB/${DB}_week.$W.$DATE.sql$SUFFIX"
		elif [ "$DO_DBALL_DUMP" = "yes" ]; then
			eval rm -fv "$BACKUPDIR/weekly/${DBALLNAME}_week.$REMW.*" 
			dbdump_all "$BACKUPDIR/weekly/${DBALLNAME}_week.$W.$DATE.sql"
			compression "$BACKUPDIR/weekly/${DBALLNAME}_week.$W.$DATE.sql"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/weekly/${DBALLNAME}_week.$W.$DATE.sql$SUFFIX"
		fi
	
	# Daily Backup
	else
	# Create Separate directory for each DB
		find "$BACKUPDIR/daily" -name "_roles*.sql" -mmin +$BACKUP_MINS -delete
		dbdump_roles "$BACKUPDIR/daily/_roles_$DATE.$DOW.sql"
		if [ ! -e "$BACKUPDIR/daily/$DB" ]; then	# Check Daily DB Directory exists.
			mkdir -p "$BACKUPDIR/daily/$DB"
		fi
		echo Daily Backup of Database \( $DB \)
		echo Rotating last weeks Backup...
		find "$BACKUPDIR/daily/$DB" -name "*.sql.*" -mmin +$BACKUP_MINS -delete
		find "$BACKUPDIR/daily/$DB" -name "*.pgdmp" -mmin +$BACKUP_MINS -delete
		echo
		if [ "$DO_CUSTOM_DUMP" = "yes" ]; then
			SOPT=$OPT
			OPT="$OPT --format=c -Z 9"
			dbdump "$DB" "$BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.pgdmp"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.pgdmp"
			OPT=$SOPT
		elif [ "$DO_SQL_DUMP" = "yes" ]; then
			dbdump "$DB" "$BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.sql"
			compression "$BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.sql"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/daily/$DB/${DB}_$DATE.$DOW.sql$SUFFIX"
		elif [ "$DO_DBALL_DUMP" = "yes" ]; then
			find "$BACKUPDIR/daily/" -name "${DBALLNAME}*.sql.*" -mmin +$BACKUP_MINS -delete
			dbdump_all "$BACKUPDIR/daily/${DBALLNAME}_$DATE.$DOW.sql"
			compression "$BACKUPDIR/daily/${DBALLNAME}_$DATE.$DOW.sql"
			BACKUPFILES="$BACKUPFILES $BACKUPDIR/daily/${DBALLNAME}_$DATE.$DOW.sql"
		fi
	fi
	echo ----------------------------------------------------------------------

  done
echo Backup End `date`
fi

###########################3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3
###########################3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3
###########################3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3##############3
if [ "$DO_HOT_BACKUP" = "yes" -a "$DO_SQL_DUMP" != "yes" -a "$DO_CUSTOM_DUMP" != "yes" -a "$DO_DBALL_DUMP" != "yes" ]; then

echo Backup Start Time `date`
echo ======================================================================
# Monthly Full Backup of all Databases
    if [ $DOM = "01" ]; then
        if [ ! -e "$BACKUPDIR/monthly" ]                # Check Monthly DB Directory exists.
        then
            mkdir -p "$BACKUPDIR/monthly"
	fi
        echo Monthly Backup of $DB...
            dbdump_h "ALL" "$BACKUPDIR/monthly/HOT_$DATE.$M"
            BACKUPFILES="$BACKUPFILES $BACKUPDIR/monthly/HOT_$DATE.$M$SUFFIX"
    # Weekly Backup
    elif [ $DNOW = $DOWEEKLY -a $BACKUP_DAYS -le 7 ]; then
        echo Weekly Backup of Database
        echo Rotating 5 weeks Backups...
        if [ "$W" -le 05 ];then
                REMW=`expr 48 + $W`
        elif [ "$W" -lt 15 ];then
            REMW=0`expr $W - 5`
        else
                REMW=`expr $W - 5`
        fi
        eval rm -fv "$BACKUPDIR/weekly/HOT_week.$REMW.*"
        echo
            dbdump_h "$DB" "$BACKUPDIR/weekly/HOT_week.$W.$DATE"
            BACKUPFILES="$BACKUPFILES $BACKUPDIR/weekly/HOT_week.$W.$DATE$SUFFIX"
    # Daily Backup  
    else
        echo Daily Backup of Database
        echo Rotating last weeks Backup...
        find "$BACKUPDIR/daily" -name "*HOT_*" -mmin +$BACKUP_MINS -delete
        echo
        echo
        dbdump_h "$DB" "$BACKUPDIR/daily/HOT_$DATE.$DOW"
            BACKUPFILES="$BACKUPFILES $BACKUPDIR/daily/HOT_$DATE.$DOW$SUFFIX"
    fi    
    echo ----------------------------------------------------------------------
fi

echo Backup End `date`    
echo ======================================================================
echo Total disk space used for backup storage..
echo Size - Location
echo `du -hs "$BACKUPDIR"`
echo
echo ======================================================================

#Clean up IO redirection
exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
exec 1>&7 7>&-      # Restore stdout and close file descriptor #7.

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
		mutt -s "$ERRORNOTE PostgreSQL Backup Log and SQL Files for $HOST - $DATE" $BACKUPFILES $MAILADDR < $LOGFILE		#send via mutt
	else
		cat "$LOGFILE" | mail -s "WARNING! - PostgreSQL Backup exceeds set maximum attachment size on $HOST - $DATE" $MAILADDR
	fi
elif [ "$MAILCONTENT" = "log" ]
then
	cat "$LOGFILE" | mail -s "PostgreSQL Backup Log for $HOST - $DATE" $MAILADDR
	if [ -s "$LOGERR" ]
		then
			(cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: PostgreSQL Backup error Log for $HOST - $DATE" $MAILADDR
	fi	
elif [ "$MAILCONTENT" = "quiet" ]
then
	if [ -s "$LOGERR" ]
		then
			(cat "$LOGERR";echo "stdout log:" ; cat "$LOGFILE") | mail -s "ERRORS REPORTED: PostgreSQL Backup error Log for $HOST - $DATE" $MAILADDR
			cat "$LOGFILE" | mail -s "PostgreSQL Backup Log for $HOST - $DATE" $MAILADDR
	fi
else
	if [ -s "$LOGERR" ]
		then
			cat "$LOGFILE"
			echo
			echo "###### WARNING ######"
			echo "Errors reported during AutoPostgreSQLBackup execution.. Backup failed"
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

# Clean up Logfile
eval rm -f "$LOGFILE"
eval rm -f "$LOGERR"

exit $STATUS
