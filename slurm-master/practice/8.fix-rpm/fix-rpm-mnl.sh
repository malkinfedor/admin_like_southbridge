#!/bin/bash

LOCATION="/srv/southbridge"

if pidof -x $(basename $0) > /dev/null; then
  for p in $(pidof -x $(basename $0)); do
  if [ $p -ne $$ ]; then
    echo "Script $0 is already running: exiting"
    exit
  fi
  done
fi
                        
if [ -f "$LOCATION/etc/fix-rpm.conf.dist" ]; then
  . "$LOCATION/etc/fix-rpm.conf.dist"
  if [ -f "$LOCATION/etc/fix-rpm.conf" ]; then
    . "$LOCATION/etc/fix-rpm.conf"
  fi
  if [ -f "$LOCATION/etc/fix-rpm.local.conf" ]; then
    . "$LOCATION/etc/fix-rpm.local.conf"
  fi
fi

if [ -z "$EXCLUDE_PACKET" ]; then
  EXCLUDE_PACKET="kernel|openssl|mysql|Percona|postgresql|mongo|redis|nginx|httpd|python|php|npm|node|ruby|jdk|java|jre|couchbase|sphinx|perl"
fi
if [ -z "$EXCLUDE_FILE" ]; then
  EXCLUDE_FILE='/usr/sbin/apachectl|python|\.pyc$| /lib/udev|igb.ko|/usr/bin/rake|/usr/bin/rdoc|/usr/bin/ri|/usr/local/psa/|/usr/lib64/plesk'
fi
                                              
SLOGFILE="/var/log/rpmcheck.log"
LOGFILE="/tmp/1rpmcheck.log"
HN=`hostname`

touch $SLOGFILE
### check rpm function

function rpm-Va {
rm -f /tmp/arr
rm -f /tmp/arr_pp1
rm -f /tmp/arr_pp2
rm -f /tmp/arr_pp3

rpm -Va --noscripts >/tmp/arr_pp1 2>&1

cat /tmp/arr_pp1 | grep -ivP "^\..\." | grep -v "^missing" | \
  grep -P "^\S+?\s+?\/" | \
  grep -iP "/bin|/sbin|/lib64| /lib| /usr/lib|/boot|/libexec|/dev| /sys" | \
  grep -v "prelink" | grep -ivP "$EXCLUDE_FILE" > /tmp/arr_pp2
if [ -s /tmp/arr_pp2 ]; then
  cat /tmp/arr_pp2 | rpm -qf `awk '{print $2}'` 2>&1 | \
    grep -v "rpm: no arguments given for query" >/tmp/arr_pp3
  if [ -s /tmp/arr_pp3 ]; then
    cat /tmp/arr_pp3 |  grep -ivP "$EXCLUDE_PACKET" | sort -u >/tmp/arr
    UNIQ_ARR=`cat /tmp/arr | tr "\n" " "`
  else 
    UNIQ_ARR=""
  fi
else 
  UNIQ_ARR=""
fi
}

function OutNoPacket {
  if [ -s /tmp/arr_pp2 ]; then
    echo "*****************************"
    echo "*** Everything looks fine ***"
    echo "*****************************"
    echo "Please fix the following packet and files manually (if they are)"
    echo "Packet:"
    cat /tmp/arr_pp3 | sort -u
    echo
    echo "Files:"
    cat /tmp/arr_pp2
    SUBJ="CHECK $1"
  else 
    SUBJ="FINE $1"
  fi
}

function ReinstallPacket {
  echo
  echo "************************************"
  echo "*** Reinstalling packages step $1 ***"
  echo "************************************"
  echo "Files:"
  cat /tmp/arr_pp2
  echo
  echo "/usr/bin/yum reinstall  ${UNIQ_ARR}"
  echo
  /usr/bin/yum reinstall ${UNIQ_ARR}
  echo
}

function UpdatePacket {
    echo "************************************************************"
    echo "*** Updating packages, that cannot be reinstalled step $1 ***"
    echo "************************************************************"
    echo "Files:"
    cat /tmp/arr_pp2
    echo
    echo "/usr/bin/yum update ${UNIQ_ARR}"
    echo
    /usr/bin/yum update ${UNIQ_ARR}
    echo
    echo "Please fix the following files manually (if they are)"
    echo
}

me=`basename "$0"`

TP=`ps ax | grep " $me " | grep -v "$BASHPID" | grep -v grep | wc -l`

if [ $TP -gt 0 ]; then
  echo "$me alredy running. Exit"
  exit
fi

# Rebuild database
#rpm --rebuilddb
# Update prelink
/usr/sbin/prelink -av -mR > /dev/null 2>&1

rpm-Va
if [ -z "${UNIQ_ARR}" ]; then
  OutNoPacket ok
else
  /usr/bin/yum clean all 
  ReinstallPacket 1
  rpm-Va
  if [ -z "${UNIQ_ARR}" ]; then
    OutNoPacket reinstall1
  else
    UpdatePacket 1
    rpm-Va
    if [ -z "${UNIQ_ARR}" ]; then
      OutNoPacket update1
    else
      ReinstallPacket 2
      rpm-Va
      if [ -z "${UNIQ_ARR}" ]; then
         OutNoPacket reinstall2
      else
        UpdatePacket 2
        rpm-Va
        if [ -z "${UNIQ_ARR}" ]; then
          OutNoPacket update2
        else
          echo "****************************************************************"
          echo "****************************************************************"
          echo "Please fix the following packet and files manually (if they are)"
          echo "Packet:"
          cat /tmp/arr_pp3 | sort -u
          echo
          echo "Files:"
	  cat /tmp/arr_pp2
	  SUBJ="SERVER CHECK"
	fi
      fi
    fi
  fi
fi

