#!/bin/bash

export LD_LIBRARY_PATH=/lib:/usr/lib:/lib64:/usr/lib64

LOGFILE=$(mktemp)
LOGERR=$(mktemp)
# IO redirection for logging.
touch "$LOGFILE"
exec 6>&1             # Link file descriptor #6 with stdout.
exec > "$LOGFILE"     # stdout replaced with file $LOGFILE.

touch "$LOGERR"
exec 7>&2             # Link file descriptor #7 with stderr.
exec 2> "$LOGERR"     # stderr replaced with file $LOGERR.


yum makecache 
[ -f /usr/lib/yum-plugins/security.py ] || yum -y install yum-plugin-security

t=$(mktemp)
yum list-security | sed '1,/packages excluded due to repository protections/ d' | head -n-1 >"$t"

if [ -s "$t" ]; then
  ALERT=$(grep "Important/Sec." "$t")
  if [ -n "$ALERT" ]; then
    (echo "Список пакетов с проблемами безопсности, которые необходимо обновить: "; echo -e "$ALERT")| tr -d '\015' | mail -s "HOST_Security_update `hostname`" root@mail.example.com
  fi
  cat "$t" | mail -s "GROUP_yum_list_security `hostname`" root@mail.example.com
fi

if [ -s "$LOGERR" ]; then
    (echo "Ошибка выполенения команды yum:"; echo "Stdout log:" cat "$LOGFILE"; echo "-------"; cat "$t"; echo "-------"; echo "Error log:"; cat "$LOGERR")| tr -d '\015' | mail -s "HOST_yum_error `hostname`" root@mail.example.com
fi

#Clean up IO redirection
exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
exec 2>&7 7>&-      # Restore stderr and close file descriptor #7.

rm -f "$LOGFILE"
rm -f "$LOGERR"
rm -f "$t"
