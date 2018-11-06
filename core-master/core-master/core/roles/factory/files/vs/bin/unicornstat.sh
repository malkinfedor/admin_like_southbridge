#!/bin/bash

TOTAL=0
WORK=0

MASTER_PID=`ps ax | grep -E "unicorn.* master" | grep -v grep | cut -f 1 -d '?'`

W1=`ps w --ppid $MASTER_PID |  grep -E "unicorn.* worker" | cut -f 1 -d '?'`

for WPID in $W1 ; do
  CCPU=`cat /proc/$WPID/stat | awk '{print $14+$15}'`
  BEFORE_CPU[$WPID]=$CCPU
  TOTAL=$(($TOTAL+1))
done
      
sleep 1
      
for WPID in $W1 ; do
  CCPU=`cat /proc/$WPID/stat | awk '{print $14+$15}'`
  CCPU=$(($CCPU-${BEFORE_CPU[$WPID]}))
  if [ $CCPU -gt 0 ]; then
    WORK=$(($WORK+1))
  fi
done

echo "$TOTAL
$WORK" > /tmp/unicorn.stat
