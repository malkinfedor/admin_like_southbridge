#!/bin/sh

raid_type=$1

if [ -z "$raid_type" ]; then
  echo "Usage: smartd.sh [raid_type]"
  exit 1
fi

function get_smart_disk() {
local disk=$1
disksmart=0
disksmart=`smartctl -a $disk | grep -P "SMART support is:\s+Available - device has SMART capability" | wc -l`
}

smartctlmode=""
new_conf=`mktemp`
error_result=`mktemp`
case $raid_type in
  Adaptec|sas2)
    for d in `/bin/ls -1 /dev/sg*`; do
      get_smart_disk $d
      if [ $disksmart -gt 0 ]; then 
        result=`smartctl --smart=on --offlineauto=on --saveauto=on $d`
        code=$?
	if [ $code -gt 0 ]; then
	  # Try to set smartctl mode without errors
	  code2=`echo $result | grep "Error SMART Enable Automatic Offline failed"|wc -l`
          if [ $code2 -eq 0 ]; then
             smartctlmode=$smartctlmode" --offlineauto=on "
          fi
	  code2=`echo $result | grep "Enable autosave (clear GLTSD bit) failed"|wc -l`
          if [ $code2 -eq 0 ]; then
             smartctlmode=$smartctlmode" --saveauto=on "
          fi
          result=`smartctl --smart=on $smartctlmode $d`
          code=$?
          if [ $code -gt 0 ]; then
            echo $result >> $error_result
          fi
        fi
        echo "$d -d scsi -U + -C + -H -m root" >> $new_conf
      fi
    done
  ;;

  HP)
    maindisk=1
    hpssacli controller all show config |grep -P "logicaldrive|physicaldrive" | while read line; do
#echo $line
      if [[ $line =~ logicaldrive ]]; then
        diskletter=`/bin/ls -1 /dev/sd[a-z] | head -n $maindisk | tail -n -1`
        maindisk=$(( $maindisk + 1 ))
      fi
      if [[ $line =~ physicaldrive.*:bay\ ([0-9]+), ]]; then
        d="/dev/sg0 -d sat+cciss,"$((${BASH_REMATCH[1]} - 1 ))
        if [ `grep "d cciss,${BASH_REMATCH[1]} " "$new_conf" | wc -l` -eq 0 ]; then
          get_smart_disk "$d"
          if [ $disksmart -gt 0 ]; then 
            result=`smartctl --smart=on --offlineauto=on --saveauto=on $d`
            code=$?
    	    if [ $code -gt 0 ]; then
	      # Try to set smartctl mode without errors
	      code2=`echo $result | grep "Error SMART Enable Automatic Offline failed"|wc -l`
              if [ $code2 -eq 0 ]; then
                smartctlmode=$smartctlmode" --offlineauto=on "
              fi
              result=`smartctl --smart=on --saveauto=on $smartctlmode $d`
              code=$?
              if [ $code -gt 0 ]; then
                echo $result >> $error_result
              fi
            fi
            echo "$d -U + -C + -m root -T permissive" >> $new_conf
          fi
        fi
      fi
    done
  ;;

  LSI)
    maindisk=1
    megacli -ldpdinfo -a0 |grep -P "Virtual Drive:|Device Id:" | while read line; do
      if [[ $line =~ Virtual ]]; then
        diskletter=`/bin/ls -1 /dev/sd[a-z] | head -n $maindisk | tail -n -1`
        maindisk=$(( $maindisk + 1 ))
      fi
      if [[ $line =~ Device\ Id:\ ([0-9]+) ]]; then
        d=$diskletter" -d megaraid,"${BASH_REMATCH[1]}
        if [ `grep "d megaraid,${BASH_REMATCH[1]} " "$new_conf" | wc -l` -eq 0 ]; then
          get_smart_disk "$d"
          if [ $disksmart -gt 0 ]; then 
            result=`smartctl --smart=on --offlineauto=on --saveauto=on $d`
            code=$?
    	    if [ $code -gt 0 ]; then
	      # Try to set smartctl mode without errors
	      code2=`echo $result | grep "Error SMART Enable Automatic Offline failed"|wc -l`
              if [ $code2 -eq 0 ]; then
                smartctlmode=$smartctlmode" --offlineauto=on "
              fi
              result=`smartctl --smart=on --saveauto=on $smartctlmode $d`
              code=$?
              if [ $code -gt 0 ]; then
                echo $result >> $error_result
              fi
            fi
            echo "$d -U + -C + -H -m root" >> $new_conf
          fi
        fi
      fi
    done
  echo "DEVICESCAN -U + -C + -H -m root" > $new_conf
  ;;

  md)
    for d in `/bin/ls -1 /dev/sd[a-z]`; do
      get_smart_disk "$d"
      if [ $disksmart -gt 0 ]; then 
        result=`smartctl --smart=on --offlineauto=on --saveauto=on $d`
        code=$?
        if [ $code -gt 0 ]; then
          codessd=`echo $result | grep "Error SMART Enable Automatic Offline failed"|wc -l`
          if [ $codessd -gt 0 ]; then
            result=`smartctl --smart=on --saveauto=on $d`
            code=$?
          fi
          if [ $code -gt 0 ]; then
            echo $result >> $error_result
          fi
        fi
        echo "$d -U + -C + -H -m root" >> $new_conf
      fi
    done
  echo "DEVICESCAN -U + -C + -H -m root" > $new_conf
  ;;

esac

##cat "$new_conf"
if [ -f /etc/smartd.conf ]; then
 currconf=/etc/smartd.conf
else
 currconf=/etc/smartmontools/smartd.conf
fi
difres=`diff $currconf $new_conf`
if [ -n "$difres" ]; then
  mv -f $currconf $currconf.bak
  mv -f "$new_conf" $currconf
  echo "changed"
  exit 0
fi

if [ -s "$error_result" ]; then
  cat $error_result
  exit 1
fi

rm "$new_conf"
rm "$error_result"
echo "Ok"
exit 0

