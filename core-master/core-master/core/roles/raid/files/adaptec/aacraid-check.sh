#!/bin/sh

# don't forget to add /etc/cron.d/raid-check file with the following contents:
# 00 * * * * root /srv/southbridge/bin/aacraid-check.sh

PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

$LOCATION/aacraid-status.sh >/dev/null 2>&1
STATUS=$?

if [ $STATUS -eq 1 ]; then
    $LOCATION/aacraid-status.sh 2>&1 | /bin/mail -s "[alert] `hostname` raid problem" root
fi
