#!/bin/sh

bootdev=`mount | grep 'on /boot type' | awk '{print $1}'`
if [ -z "$bootdev" ]; then
  bootdev=`mount | grep 'on / type' | awk '{print $1}'`
fi

echo "Boot detected at $bootdev"
if [[ "$bootdev" =~ /dev/(md[0-9]+) ]]; then
  grubinstall=""
  if [ -f /boot/grub/stage2 -a -x /sbin/grub-install ]; then
    grubinstall='/sbin/grub-install'
    diskname="sd[a-z]"
    echo "Grub detected..."
  fi
  if [ -f /boot/grub2/grub.cfg -a -x /sbin/grub2-install ]; then
###  if [ -f /boot/grub/grub.cfg ]; then
    grubinstall='/sbin/grub2-install'
    diskname="sd[a-z]|nvme[0-9]n1"
    echo "Grub2 detected..."
  fi
  if [ -z "$grubinstall" ]; then
     echo "ERROR: Grub not found"
     exit 1
  fi
  bootmd=${BASH_REMATCH[1]}
  disks=`cat /proc/mdstat | grep "^$bootmd"`
  echo $disks
  echo
  if ! [[ "$disks" =~ " active " ]]; then
    echo "ERROR: $bootdev is not active"
    exit 1
  fi
  if ! [[ "$disks" =~ " raid1 " ]]; then
    echo "ERROR: not a raid1"
    exit 1
  fi
  for d in $disks; do 
    if [[ "$d" =~ ($diskname)(p?[0-9]+) ]]; then 
echo "    $grubinstall /dev/${BASH_REMATCH[1]}"
      $grubinstall /dev/${BASH_REMATCH[1]}
    fi 
  done
else 
  echo "No softraid"
fi
exit 0
