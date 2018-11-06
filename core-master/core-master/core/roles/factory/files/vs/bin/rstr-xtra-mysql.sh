#!/bin/sh

#
# please remove # comment to restore innodb XTRA backup
#

#/usr/bin/innobackupex --defaults-file=/etc/my.cnf --password=`cat /root/.mysql` --apply-log /var/lib/mysql-xtra
#/usr/bin/innobackupex --defaults-file=/etc/my.cnf --password=`cat /root/.mysql` --copy-back /var/lib/mysql-xtra
chown -R mysql:mysql /var/lib/mysql
