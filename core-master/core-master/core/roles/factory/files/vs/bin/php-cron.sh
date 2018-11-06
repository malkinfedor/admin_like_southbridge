#!/bin/sh

LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."

# read configuration
if [ -f "$LOCATION/etc/admin.conf.dist" ]; then
    . "$LOCATION/etc/admin.conf.dist"
    if [ -f "$LOCATION/etc/admin.conf" ]; then
        . "$LOCATION/etc/admin.conf"
    fi
else
    echo "can't load $LOCATION/etc/admin.conf.dist, please fetch it from repository"
    exit 1
fi
                                        
if [ "$1" != "minutely" -a "$1" != "hourly" -a "$1" != "daily" ]; then
  echo "Usage: $0 minutely|hourly|daily"
  exit 1
fi

CRON_INTERVAL=$1

COUNT=`ls -laF $WWW_PATH | wc -l`
if [ "$COUNT" -lt "4" ]; then
    exit
fi

if [ "$2" = "" ]; then 
  OLDDIR=`pwd -P`
  cd $WWW_PATH
  PROJECT_LIST=`/usr/bin/find * -maxdepth 0 -type d | sed 's/\(.*\)\/cron\/.*/\1/'`
  if [ "$?" != "0" ]; then
#    echo "Directory cron not found in projects"
    exit 0
  fi
  cd $OLDDIR
  for PRJ in $PROJECT_LIST ; do
    if [ -d "$WWW_PATH/$PRJ/cron/$CRON_INTERVAL" ]; then
	TTTT=`/usr/bin/find $WWW_PATH/$PRJ/cron/$CRON_INTERVAL/*.php 2>&1 >/dev/null`
	if [ "$?" = "0" ]; then
	    $0 $CRON_INTERVAL $PRJ &
	fi
    fi
  done
fi

if [ "$2" != "" ]; then
#  echo "Second stage $2" >l
  cd $WWW_PATH/$2
  PHPSCRIPTS=`/usr/bin/find cron/$1/*.php`
  if [ "$?" = "0" ]; then
    for PHPSCR in $PHPSCRIPTS ; do
      echo `date +"%F %T"`" $PHPSCR" >> $WWW_PATH/$2/logs/cron/$1.log
      cd $WWW_PATH/$2 && /usr/bin/php --define memory_limit=512M -q $PHPSCR >> $WWW_PATH/$2/logs/cron/$1.log 2>&1
    done
  fi
fi

exit 0
