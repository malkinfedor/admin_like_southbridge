#!/bin/sh

CONT="0"
STATUS=0
echo -n "Checking RAID status on "
hostname

    NVOL=`/usr/sbin/sas2ircu 0 DISPLAY | grep "Status of volume" | wc -l`
    NVOLOK=`/usr/sbin/sas2ircu 0 DISPLAY | grep "OKY" | wc -l`

    /usr/sbin/sas2ircu 0 DISPLAY

    [ "$NVOL" -ne "$NVOLOK" ] && STATUS=1

exit $STATUS
