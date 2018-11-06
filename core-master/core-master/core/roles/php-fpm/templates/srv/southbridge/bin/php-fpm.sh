#!/bin/sh

OS7=`cat /etc/redhat-release | grep "CentOS Linux release 7" | wc -l`

function start() {
  if [ $OS7 -gt 0 ]; then
    systemctl start php-fpm >/dev/null 2>&1
  else
    service php-fpm start >/dev/null 2>&1
  fi
}

function stop() {
  killall php-fpm
}

if [ "$1" == "start" ]; then
  stop
  sleep 1
  start
fi


if [ "$1" == "stop" ]; then
  stop
fi
