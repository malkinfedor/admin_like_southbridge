#!/bin/sh

IP=$1
if [ -n "$IP" ];then
    if [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];then
        sed -i "/$IP/d" /etc/hosts.deny
        sed -i "/$IP/d" /var/lib/denyhosts/hosts-valid
        sed -i "/$IP/d" /var/lib/denyhosts/hosts
        sed -i "/$IP/d" /var/lib/denyhosts/hosts-root
        sed -i "/$IP/d" /var/lib/denyhosts/hosts-restricted
        sed -i "/$IP/d" /var/lib/denyhosts/users-hosts
        echo $IP remove from Denyhosts
    else
        echo "This is not IP" 
    fi
else
    echo "IP is empty" 
fi
