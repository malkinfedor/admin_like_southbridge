#!/bin/sh

# don't forget to add /etc/cron.d/raid-check file with the following contents:
# 00 * * * * root /srv/southbridge/bin/megaraid-check.sh

if [ ! -f /usr/sbin/sas2ircu ]; then
  yum -y install sas2ircu
fi

PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

$LOCATION/sas2raid-status.sh >/dev/null 2>&1
STATUS=$?

if [ $STATUS -eq 1 ]; then
    $LOCATION/sas2raid-status.sh 2>&1 | /bin/mail -s "[alert] `hostname` raid problem" root
fi
