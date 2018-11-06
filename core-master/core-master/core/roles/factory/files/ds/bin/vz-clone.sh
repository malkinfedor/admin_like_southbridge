#!/bin/bash

# script to clone an openvz VE

set -e

if [ -z "$2" ]; then
    echo "Usage: $0 <veid> <new-id>"
    exit 1
fi

cfg="/etc/vz/conf/$1.conf"
newcfg="/etc/vz/conf/$2.conf"

if [ ! -e $cfg ]; then 
    echo $cfg not found!
	exit 1
fi

VE_PRIVATE="/vz/private"

VEID=$1
. $cfg
veprivate="$VE_PRIVATE/$1"

VEID=$2
. $cfg
newveprivate="$VE_PRIVATE/$2"

if [ -f $newcfg ]; then 
    echo $newcfg config already exists!
	exit 1
fi

if [ -d $newveprivate ]; then 
    echo $newveprivate dir already exists!
	exit 1
fi

if vzlist | fgrep -w -q $1
then
    vzctl stop $1
fi

echo "Cloning $cfg to $newcfg"
cp -a $cfg $newcfg

echo "Cloning $veprivate to $newveprivate"
mkdir -p $newveprivate
cd $veprivate
tar cf - . | (cd $newveprivate && tar xf -)

echo "Do not forget to edit $newcfg (you need to edit at least HOSTNAME and IP_ADDRESS)"
