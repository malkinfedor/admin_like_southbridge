#!/bin/sh

CONT="a0"
STATUS=0
echo -n "Checking RAID status on "
hostname

cd /tmp

for a in $CONT; do
    NAME=`/usr/sbin/megacli -AdpAllInfo -$a |grep "Product Name" | cut -d: -f2`
    echo "Controller $a: $NAME"

    LD=`/usr/sbin/megacli -LDInfo  -Lall -a0 | grep -E "^Virtual|^State|^RAID"`
    echo
    echo "Logical disk state:"
    echo "$LD"
    echo

    noonline=`/usr/sbin/megacli PDList -$a | grep Online | wc -l`
    echo "No of Physical disks online : $noonline"

    DEGRADED=`/usr/sbin/megacli -AdpAllInfo -a0  |grep "Degrade"`
    echo $DEGRADED

    NUM_DEGRADED=`echo $DEGRADED |cut -d" " -f3`
    [ "$NUM_DEGRADED" -ne 0 ] && STATUS=1
    FAILED=`/usr/sbin/megacli -AdpAllInfo -a0  |grep "Failed Disks"`
    echo $FAILED

    NUM_FAILED=`echo $FAILED |cut -d" " -f4`
    [ "$NUM_FAILED" -ne 0 ] && STATUS=1
done

rm CmdTool.log MegaSAS.log

exit $STATUS
