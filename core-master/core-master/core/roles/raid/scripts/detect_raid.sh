#!/bin/sh

if [ `id -u` -ne 0 ];then echo "Not root"; id;  exit; fi

RAID=`cat /proc/scsi/scsi | grep Vendor | grep -v "iLO"  | awk '{ print $2 }' | uniq | egrep -i "LSI|Adaptec|SMC|DELL|HP|AMCC|IBM|Intel|ASR8885"| head -1`
if [ "$RAID" = "IBM" -a "$(lspci | grep -i LSI)" ]; then
  RAID="LSI"
elif [ "$RAID" = "Intel" -a "$(lspci | grep -i LSI)" ]; then
  RAID="LSI"
elif [ "$RAID" = "INTEL" -a "$(lspci | grep -i LSI)" ]; then
  RAID="LSI"
elif [ "$RAID" = "IBM" -a "$(lspci | grep -i Adaptec)" ]; then
  RAID="Adaptec"
elif [ "$RAID" = "ASR8885" -a "$(lspci | grep -i Adaptec)" ]; then
  RAID="Adaptec"
fi

if [ "$RAID" = "LSI" -a `lspci | grep "LSI" | grep "SAS-2" | wc -l` -gt 0 ]; then
  RAID=sas2
fi

if [ -z "$RAID" ];then 
  RAID=`cat /proc/scsi/scsi | grep Vendor | awk '{ print $2 }' | uniq | egrep -v "Optiarc|HL-DT-ST" |head -1` 
fi
if [ "$RAID" = "ATA" -a `cat /proc/mdstat | grep "^md" | wc -l` -gt 0 ]; then
  RAID="md"
fi

if [ -z "$RAID" -a "$(lspci | grep -i RAID | grep -i "Hewlett-Packard")" ]; then
  RAID="HP"
fi

if [ -z "$RAID" ]; then
  RAID="none"
fi

echo $RAID
exit 0

###if [ -z "$RAID" -a "$(lspci | grep -i "Non-Volatile")" -a "$(smartctl --version | grep "smartctl 6.5")" ]; then
#if [ -z "$RAID" -a "$(lspci | grep -i "Non-Volatile")" ]; then
#  RAID="ATA"
#fi
