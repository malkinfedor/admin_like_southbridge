#!/bin/sh

# Southbridge hosting management script by Igor Olemskoi <igor@southbridge.ru>

# path
PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"

# functions
generate_password_db() {
    for symbol in {A..Z} {a..z} {0..9}; do SYMBOLS=$SYMBOLS$symbol; done
    SYMBOLS=$SYMBOLS'!@#%&*()?[]{}-+_='
    for i in `seq 1 13`; do PASSWORD=$PASSWORD${SYMBOLS:$(expr $RANDOM % ${#SYMBOLS}):1}; done
    echo $PASSWORD
}

generate_password() {
    cat /dev/urandom | tr -dc A-Za-z0-9 | head -c8
}

ACTION="$1"
FQDN="$2"
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."

# project initialization
if [ "$ACTION" = "init" ]; then
    distcopy() {
        for DISTFILE in *.dist; do
            if [ -f "$DISTFILE" ]; then
                FILE=`echo $DISTFILE | sed -e 's@.dist@@g'`
                cp -i $DISTFILE $FILE
            fi
        done
    }
    cd $LOCATION/skel && distcopy
    cd $LOCATION/etc && distcopy
    exit 1
fi

# read configuration
if [ -f "$LOCATION/etc/admin-bitrix.conf.dist" ]; then
    . "$LOCATION/etc/admin-bitrix.conf.dist"
        if [ -f "$LOCATION/etc/admin-bitrix.conf" ]; then
            . "$LOCATION/etc/admin-bitrix.conf"
        fi
else
    echo "can't load $LOCATION/etc/admin-bitrix.conf.dist, please fetch it from repository"
    exit 0
fi

OS=`uname`
# su suffix
if [ "$OS" = "FreeBSD" ]; then
    ROOT_USERNAME="root"
    ROOT_GROUP="wheel"
    POSTGRESQL_USERNAME="pgsql"
    SED_SUFFIX="-i ''"
else
    ROOT_USERNAME="root"
    ROOT_GROUP="root"
    POSTGRESQL_USERNAME="postgres"
    SED_SUFFIX="-i"
fi

# check if mysql is enabled
if [ ! -f "/root/.mysql" ]; then
    MYSQL_ENABLED="NO"
else
    MYSQL_USERNAME="root"
    MYSQL_PASSWORD=`cat /root/.mysql`
fi

# check if postgresql is enabled
if [ ! -f "/root/.postgresql" ]; then
    POSTGRESQL_ENABLED="NO"
fi

# check if nginx is enabled
if [ ! -d "$NGINX_CONF_PATH" ]; then
    NGINX_ENABLED="NO"
fi

# check if php-fpm is enabled
if [ ! -d "$PHPFPM_CONF_PATH" ]; then
    PHPFPM_ENABLED="NO"
fi


# get IP from command line if it is stated there. if $IP is not entered, DNS zone creation is disabled
if [ ! -z "$3" ]; then
    IP="$3"
fi

# convert fqdn to the database name
DB_NAME=`echo $FQDN | tr . _`
DB_USER=`echo $FQDN | cksum | awk '{print $1}'`

# sed flags
SED_FLAGS="     -e 's@##WWW_PATH##@$WWW_PATH@g' \
                -e 's@##FQDN##@$FQDN@g' \
                -e 's@##NS1_FQDN##@$NS1_FQDN@g' \
                -e 's@##NS2_FQDN##@$NS2_FQDN@g' \
                -e 's@##HOSTMASTER_EMAIL##@$HOSTMASTER_EMAIL@g' \
                -e 's@##IP##@$IP@g' \
                -e 's@##SMTP_FQDN##@$SMTP_FQDN@g' \
                -e 's@##AWSTATS_CONF_PATH##@$AWSTATS_CONF_PATH@g' \
                -e 's@##AWSTATS_DATA_PATH##@$AWSTATS_DATA_PATH@g' \
                $SED_SUFFIX"

# if action is not entered
if [ "$ACTION" != "create" -a "$ACTION" != "remove" -a "$ACTION" != "change_root_pass" -a "$ACTION" != "createdb" -a "$ACTION" != "createfpm" ]; then
    echo "use $0 <init>"
    echo "use $0 <create|createfpm|remove> <fqdn> [ip]"
    echo "use $0 <createdb> <mysql|postgresql> <dbname>"
    echo "use $0 <change_root_pass> <mysql|postgresql>"
    exit 1
fi

### start shared ###
if [ "$ACTION" = "create" ]
then
        if grep -q $FQDN /etc/passwd
        then
                echo "User $FQDN already exist"
                exit 0
        else
                useradd -m -d /srv/www/$FQDN $FQDN
                rm -rf /srv/www/$FQDN
        fi
fi
### end shared ###

# if action "changepass"
if [ "$ACTION" = "change_root_pass" ]; then
    if [ "$FQDN" = "mysql" ]; then
        if [ "$MYSQL_ENABLED" != "NO" ]; then
            PASSWORD=`generate_password`
            mysqladmin -uroot -p`cat /root/.mysql` password "$PASSWORD"
            echo -n $PASSWORD > /root/.mysql; chmod 0600 /root/.mysql; chown $ROOT_USERNAME:$ROOT_GROUP /root/.mysql
            echo "mysql root password successfully changed, please look at /root/.mysql file"
            exit 0
        else
            echo "mysql is not enabled"
            exit 1
        fi
    elif [ "$FQDN" = "postgresql" ]; then
        if [ "$POSTGRESQL_ENABLED" != "NO" ]; then
            PASSWORD=`generate_password`
            psql --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --dbname=postgres --command="ALTER USER root WITH ENCRYPTED PASSWORD '$PASSWORD'"
            echo -n $PASSWORD > /root/.postgresql; chmod 0600 /root/.postgresql; chown $ROOT_USERNAME:$ROOT_GROUP /root/.postgresql
            echo "postgresql root password successfully changed, please look at /root/.postgresql file"
            exit 0
        else
            echo "postgresql is not enabled"
            exit 1
        fi
    else
        echo "no database choosen"
        exit 1
    fi
fi

# if action "createdb"
if [ "$ACTION" = "createdb" ]; then
    DB_NAME=`echo $3 | tr . _`
    DB_USER=`echo $3 | cksum | awk '{print $1}'`
    DB_PASSWORD=`generate_password_db`

    if [ "$FQDN" = "mysql" ]; then
        if [ "$MYSQL_ENABLED" != "NO" ]; then
cat << EOF | mysql -f --default-character-set=utf8 -u$MYSQL_USERNAME -p$MYSQL_PASSWORD
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT USAGE ON *.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;
GRANT USAGE ON *.* TO '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
ALTER DATABASE \`$DB_NAME\` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
EOF
        else
            echo "mysql is not enabled"
            exit 1
        fi
    elif [ "$FQDN" = "postgresql" ]; then
        if [ "$POSTGRESQL_ENABLED" != "NO" ]; then
            createuser --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --no-superuser --no-createdb --no-createrole --encrypted $DB_USER
            createdb --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --encoding=utf-8 --template=template0 --owner=$DB_USER $DB_NAME
            psql --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --dbname=postgres --command="ALTER USER \"$DB_USER\" WITH ENCRYPTED PASSWORD '$DB_PASSWORD'"
        else
            echo "postgresql is not enabled"
            exit 1
        fi
    else
        echo "no database choosen"
        exit 1
    fi

    if [ "$MYSQL_ENABLED" != "NO" -o "$POSTGRESQL_ENABLED" != "NO" ]; then
        echo
        echo "h2. Database"
        echo
        echo "host: localhost"
        echo "database: $DB_NAME"
        echo "username: $DB_USER"
        echo "password: $DB_PASSWORD"
    fi

    exit 0
fi

# if action or fqdn is not entered
if [ -z "$ACTION" -o -z "$FQDN" ]; then
    echo "use $0 <create|createfpm|remove> <fqdn>"
    exit 1
fi

# deny some fqdn names
if [ "$FQDN" = "root" -o "$FQDN" = "mysql" -o "$FQDN" = "redmine" -o "$FQDN" = "pureftpd" -o "$FQDN" = "postgres" -o "$FQDN" = "pgsql" ]; then
    echo "can't create/remove project 'root', 'mysql', 'postgres', 'pgsql', 'redmine' and 'pureftpd', these project names are forbidden."
    exit 1
fi

### Create APACHE config ###
# if action "create"
if [ "$ACTION" = "create" ]; then
    # if fqdn already exists
    if [ -d "$WWW_PATH/$FQDN" -o -f "$APACHE_CONF_PATH/vhosts.d/$FQDN.conf" ]; then
        echo "can't create domain '$FQDN' because it already exists."
        exit 1
    fi

    # check existance of directories
    if [ ! -d "$WWW_PATH" ]; then
        mkdir -p $WWW_PATH
    fi
    if [ -d $AWSTATS_CONF_PATH -a ! -d "$AWSTATS_DATA_PATH" ]; then
        mkdir -p $AWSTATS_DATA_PATH
    fi
    if [ ! -d "$APACHE_CONF_PATH/vhosts.d" ]; then
        mkdir -p $APACHE_CONF_PATH/vhosts.d
    fi

    if [ "$NGINX_ENABLED" != "NO" -a ! -d "$NGINX_CONF_PATH/vhosts.d" ]; then
        mkdir -p $NGINX_CONF_PATH/vhosts.d
    fi

    #mkdir -p $WWW_PATH/$FQDN $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN $WWW_PATH/$FQDN/cron/minutely $WWW_PATH/$FQDN/cron/hourly $WWW_PATH/$FQDN/cron/daily $WWW_PATH/$FQDN/logs/cron $WWW_PATH/$FQDN/htdocs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    mkdir -p $WWW_PATH/$FQDN $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN/logs/cron $WWW_PATH/$FQDN/htdocs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    chmod 777 $WWW_PATH/$FQDN/tmp
    chmod 777 $WWW_PATH/$FQDN/logs/cron
    chown -R $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    chown -R $FQDN:$FQDN $WWW_PATH/$FQDN/htdocs
    #chown -R $FQDN:$FQDN $WWW_PATH/$FQDN/cron

    # crontab
    touch $WWW_PATH/$FQDN/conf/crontab
    chown -R $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/crontab
    ln -s $WWW_PATH/$FQDN/conf/crontab /etc/cron.d/$FQDN

    # apache configuration
    APACHE_VER=`httpd -v | grep 'Apache/2.2' | wc -l`
    if [ $APACHE_VER -gt 0 ]; then
       APACHE_TPL="apache-vhost-bitrix-shared.tpl"
    else
       APACHE_TPL="apache24-vhost-bitrix-shared.tpl"
    fi
    if [ -f "$LOCATION/skel/$APACHE_TPL" ]; then
        cp $LOCATION/skel/$APACHE_TPL $WWW_PATH/$FQDN/conf/apache.conf
    else
        cp $LOCATION/skel/$APACHE_TPL.dist $WWW_PATH/$FQDN/conf/apache.conf
    fi

    eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/apache.conf
    chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/apache.conf
    ln -s $WWW_PATH/$FQDN/conf/apache.conf $APACHE_CONF_PATH/vhosts.d/$FQDN.conf

    # nginx configuration, if enabled
    if [ "$NGINX_ENABLED" != "NO" ]; then
        if [ -f "$LOCATION/skel/nginx-vhost-bitrix.tpl" ]; then
            cp $LOCATION/skel/nginx-vhost-bitrix.tpl $WWW_PATH/$FQDN/conf/nginx.conf
        else
            cp $LOCATION/skel/nginx-vhost-bitrix.tpl.dist $WWW_PATH/$FQDN/conf/nginx.conf
        fi
        eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/nginx.conf
        chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/nginx.conf
        ln -s $WWW_PATH/$FQDN/conf/nginx.conf $NGINX_CONF_PATH/vhosts.d/$FQDN.conf
    fi

    # generate db password
    DB_PASSWORD=`generate_password_db`

    # create mysql database and grant access
    if [ "$MYSQL_ENABLED" != "NO" ]; then
cat << EOF | mysql -f --default-character-set=utf8 -u$MYSQL_USERNAME -p$MYSQL_PASSWORD
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT USAGE ON *.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;
GRANT USAGE ON *.* TO '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
ALTER DATABASE \`$DB_NAME\` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
EOF
    fi

    # create postgresql username and database, grant access
    if [ "$POSTGRESQL_ENABLED" != "NO" ]; then
        createuser --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --no-superuser --no-createdb --no-createrole --encrypted $DB_USER
        createdb --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --encoding=utf-8 --template=template0 --owner=$DB_USER $DB_NAME
        psql --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --dbname=postgres --command="ALTER USER \"$DB_USER\" WITH ENCRYPTED PASSWORD '$DB_PASSWORD'"
    fi

    # write database config file
cat << EOF >$WWW_PATH/$FQDN/conf/database
DB_HOST = localhost
DB_NAME = $DB_NAME
DB_USER = $DB_USER
DB_PASSWORD = $DB_PASSWORD
EOF

    # generate awstats/ftp password
    PASSWORD=`generate_password`

    # awstats configuration
    if [ -d $AWSTATS_CONF_PATH ]; then
        if [ -f "$LOCATION/skel/awstats.tpl" ]; then
            cp $LOCATION/skel/awstats.tpl $AWSTATS_CONF_PATH/awstats.$FQDN.conf
        else
            cp $LOCATION/skel/awstats.tpl.dist $AWSTATS_CONF_PATH/awstats.$FQDN.conf
        fi
        eval sed $SED_FLAGS $AWSTATS_CONF_PATH/awstats.$FQDN.conf

        # create awstats password file
        htpasswd -bc $WWW_PATH/$FQDN/conf/awstats $FQDN $PASSWORD >/dev/null 2>&1
        echo "# awstats password: $PASSWORD" >> $WWW_PATH/$FQDN/conf/awstats
    fi

    # add ftp user
    if [ -f "$PUREFTPD_CONF" ]; then
        if [ "$FTP_QUOTA" = "0" ]; then
            #(echo $PASSWORD; echo $PASSWORD) | pure-pw useradd $FQDN -u $FTP_UID -g $FTP_GID -d $WWW_PATH/$FQDN -m >/dev/null 2>&1
		### start shared ###
		FTP_ITK=$(id $FQDN |sed "s/($FQDN)/ /g" |awk '{print "-" $1 " -" $2}' |sed "s/id=/ /g")
		(echo $PASSWORD; echo $PASSWORD) | pure-pw useradd $FQDN $FTP_ITK -d $WWW_PATH/$FQDN -m >/dev/null         2>&1
		### end shared ###	
        else
            #(echo $PASSWORD; echo $PASSWORD) | pure-pw useradd $FQDN -u $FTP_UID -g $FTP_GID -d $WWW_PATH/$FQDN -N $FTP_QUOTA -m >/dev/null 2>&1
                ### start shared ###
                FTP_ITK=$(id $FQDN |sed "s/($FQDN)/ /g" |awk '{print "-" $1 " -" $2}' |sed "s/id=/ /g")
                (echo $PASSWORD; echo $PASSWORD) | pure-pw useradd $FQDN $FTP_ITK -d $WWW_PATH/$FQDN -N $FTP_QUOTA -m >/dev/null         2>&1
                ### end shared ###
        fi
    fi

    echo
    echo h1. $FQDN
    if [ -d "$AWSTATS_CONF_PATH" ]; then
        echo
        echo "h2. Awstats"
        echo
        echo "url: http://$FQDN/awstats/awstats.pl"
        echo "login: $FQDN"
        echo "password: $PASSWORD"
    fi
    if [ -f "$PUREFTPD_CONF" ]; then
        echo
        echo "h2. FTP"
        echo
        echo "host: $FQDN"
        echo "username: $FQDN"
        echo "password: $PASSWORD"
        echo "ftp url: ftp://$FQDN:$PASSWORD@$FQDN/"
    fi
    if [ "$MYSQL_ENABLED" != "NO" -o "$POSTGRESQL_ENABLED" != "NO" ]; then
        echo
        echo "h2. Database"
        echo
        echo "host: localhost"
        echo "database: $DB_NAME"
        echo "username: $DB_USER"
        echo "password: $DB_PASSWORD"
    fi
    if [ ! -z "$IP" ]; then
        echo
        echo "h2. DNS"
        echo
        echo "ns1: ns1.$HOSTNAME"
        echo "ns2: ns2.$HOSTNAME"
    fi
    echo

    # create dns zone
    if [ ! -z "$IP" ]; then
        if [ ! -d "$NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME" ]; then
            mkdir -p $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME
        fi

        if [ -f "$LOCATION/skel/named.tpl" ]; then
            cp $LOCATION/skel/named.tpl $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN
        else
            cp $LOCATION/skel/named.tpl.dist $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN
        fi
        eval sed $SED_FLAGS $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN

        # append zones config
        echo "include \"$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN\";" >>$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME.conf

        if [ ! -d "$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME" ]; then
            mkdir -p $NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME
        fi

cat << EOF >>$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN
zone "$FQDN" {
    type master;
    file "$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN";
    allow-transfer { $NAMED_ALLOW_TRANSFER_ACLS };
};
EOF
        rndc reload
    fi

    # restart web servers
    apachectl graceful

    if [ "$NGINX_ENABLED" != "NO" ]; then
        killall nginx; service nginx restart
    fi

    exit 0
fi
### Apache
#
#
#
#
### Create PHP-FPM config ###
# if action "createfpm"
if [ "$ACTION" = "createfpm" ]; then
    # if fqdn already exists
    if [ -d "$WWW_PATH/$FQDN" -o -f "$PHPFPM_CONF_PATH/$FQDN.conf" ]; then
        echo "can't create domain '$FQDN' because it already exists."
        exit 1
    fi

    if [ ! -d "$PHPFPM_CONF_PATH" ]; then
        echo "Dir $PHPFPM_CONF_PATH/ not found. Please install php-fpm or check dir."
        exit 1
    fi

    # check existance of directories
    if [ ! -d "$WWW_PATH" ]; then
        mkdir -p $WWW_PATH
    fi
    if [ -d $AWSTATS_CONF_PATH -a ! -d "$AWSTATS_DATA_PATH" ]; then
        mkdir -p $AWSTATS_DATA_PATH
    fi

    if [ "$NGINX_ENABLED" != "NO" -a ! -d "$NGINX_CONF_PATH/vhosts.d" ]; then
        mkdir -p $NGINX_CONF_PATH/vhosts.d
    fi

    #mkdir -p $WWW_PATH/$FQDN $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN $WWW_PATH/$FQDN/cron/minutely $WWW_PATH/$FQDN/cron/hourly $WWW_PATH/$FQDN/cron/daily $WWW_PATH/$FQDN/logs/cron $WWW_PATH/$FQDN/htdocs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    mkdir -p $WWW_PATH/$FQDN $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN/logs/cron $WWW_PATH/$FQDN/htdocs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    chmod 777 $WWW_PATH/$FQDN/tmp
    chmod 777 $WWW_PATH/$FQDN/logs/cron
    chown -R $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    chown -R $FTP_UID:$FTP_GID $WWW_PATH/$FQDN/htdocs
    #chown -R $FTP_UID:$FTP_GID $WWW_PATH/$FQDN/cron

    # crontab
    touch $WWW_PATH/$FQDN/conf/crontab
    chown -R $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/crontab
    ln -s $WWW_PATH/$FQDN/conf/crontab /etc/cron.d/$FQDN

    PHPFPM_TPL="phpfpm-vhost-bitrix-shared.tpl"
    if [ -f "$LOCATION/skel/$PHPFPM_TPL" ]; then
        cp $LOCATION/skel/$PHPFPM_TPL $WWW_PATH/$FQDN/conf/php-fpm.conf
    else
        cp $LOCATION/skel/$PHPFPM_TPL.dist $WWW_PATH/$FQDN/conf/php-fpm.conf
    fi

    eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/php-fpm.conf
    chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/php-fpm.conf
    ln -s $WWW_PATH/$FQDN/conf/php-fpm.conf $PHPFPM_CONF_PATH/$FQDN.conf

    # nginx configuration, if enabled
    if [ "$NGINX_ENABLED" != "NO" ]; then
        if [ -f "$LOCATION/skel/nginx-vhost-bitrix-fpm.tpl" ]; then
            cp $LOCATION/skel/nginx-vhost-bitrix-fpm.tpl $WWW_PATH/$FQDN/conf/nginx.conf
        else
            cp $LOCATION/skel/nginx-vhost-bitrix-fpm.tpl.dist $WWW_PATH/$FQDN/conf/nginx.conf
        fi
        eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/nginx.conf
        chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/nginx.conf
        ln -s $WWW_PATH/$FQDN/conf/nginx.conf $NGINX_CONF_PATH/vhosts.d/$FQDN.conf
    fi

    # generate db password
    DB_PASSWORD=`generate_password_db`

    # create mysql database and grant access
    if [ "$MYSQL_ENABLED" != "NO" ]; then
cat << EOF | mysql -f --default-character-set=utf8 -u$MYSQL_USERNAME -p$MYSQL_PASSWORD
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT USAGE ON *.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;
GRANT USAGE ON *.* TO '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD' WITH MAX_QUERIES_PER_HOUR 0 MAX_CONNECTIONS_PER_HOUR 0 MAX_UPDATES_PER_HOUR 0 MAX_USER_CONNECTIONS 0;
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
ALTER DATABASE \`$DB_NAME\` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
EOF
    fi

    # create postgresql username and database, grant access
    if [ "$POSTGRESQL_ENABLED" != "NO" ]; then
        createuser --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --no-superuser --no-createdb --no-createrole --encrypted $DB_USER
        createdb --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --encoding=utf-8 --template=template0 --owner=$DB_USER $DB_NAME
        psql --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT --dbname=postgres --command="ALTER USER \"$DB_USER\" WITH ENCRYPTED PASSWORD '$DB_PASSWORD'"
    fi

    # write database config file
cat << EOF >$WWW_PATH/$FQDN/conf/database
DB_HOST = localhost
DB_NAME = $DB_NAME
DB_USER = $DB_USER
DB_PASSWORD = $DB_PASSWORD
EOF

    # generate awstats/ftp password
    PASSWORD=`generate_password`

    # awstats configuration
    if [ -d $AWSTATS_CONF_PATH ]; then
        if [ -f "$LOCATION/skel/awstats.tpl" ]; then
            cp $LOCATION/skel/awstats.tpl $AWSTATS_CONF_PATH/awstats.$FQDN.conf
        else
            cp $LOCATION/skel/awstats.tpl.dist $AWSTATS_CONF_PATH/awstats.$FQDN.conf
        fi
        eval sed $SED_FLAGS $AWSTATS_CONF_PATH/awstats.$FQDN.conf

        # create awstats password file
        htpasswd -bc $WWW_PATH/$FQDN/conf/awstats $FQDN $PASSWORD >/dev/null 2>&1
        echo "# awstats password: $PASSWORD" >> $WWW_PATH/$FQDN/conf/awstats
    fi

    # add ftp user
    if [ -f "$PUREFTPD_CONF" ]; then
        if [ "$FTP_QUOTA" = "0" ]; then
            (echo $PASSWORD; echo $PASSWORD) | pure-pw useradd $FQDN -u $FTP_UID -g $FTP_GID -d $WWW_PATH/$FQDN -m >/dev/null 2>&1
        else
            (echo $PASSWORD; echo $PASSWORD) | pure-pw useradd $FQDN -u $FTP_UID -g $FTP_GID -d $WWW_PATH/$FQDN -N $FTP_QUOTA -m >/dev/null 2>&1
        fi
    fi

    echo
    echo h1. $FQDN
    if [ -d "$AWSTATS_CONF_PATH" ]; then
        echo
        echo "h2. Awstats"
        echo
        echo "url: http://$FQDN/awstats/awstats.pl"
        echo "login: $FQDN"
        echo "password: $PASSWORD"
    fi
    if [ -f "$PUREFTPD_CONF" ]; then
        echo
        echo "h2. FTP"
        echo
        echo "host: $FQDN"
        echo "username: $FQDN"
        echo "password: $PASSWORD"
        echo "ftp url: ftp://$FQDN:$PASSWORD@$FQDN/"
    fi
    if [ "$MYSQL_ENABLED" != "NO" -o "$POSTGRESQL_ENABLED" != "NO" ]; then
        echo
        echo "h2. Database"
        echo
        echo "host: localhost"
        echo "database: $DB_NAME"
        echo "username: $DB_USER"
        echo "password: $DB_PASSWORD"
    fi
    if [ ! -z "$IP" ]; then
        echo
        echo "h2. DNS"
        echo
        echo "ns1: ns1.$HOSTNAME"
        echo "ns2: ns2.$HOSTNAME"
    fi
    echo

    # create dns zone
    if [ ! -z "$IP" ]; then
        if [ ! -d "$NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME" ]; then
            mkdir -p $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME
        fi

        if [ -f "$LOCATION/skel/named.tpl" ]; then
            cp $LOCATION/skel/named.tpl $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN
        else
            cp $LOCATION/skel/named.tpl.dist $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN
        fi
        eval sed $SED_FLAGS $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN

        # append zones config
        echo "include \"$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN\";" >>$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME.conf

        if [ ! -d "$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME" ]; then
            mkdir -p $NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME
        fi

cat << EOF >>$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN
zone "$FQDN" {
    type master;
    file "$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN";
    allow-transfer { $NAMED_ALLOW_TRANSFER_ACLS };
};
EOF
        rndc reload
    fi

    # restart web servers
    if [ "$PHPFPM_ENABLED" != "NO" ]; then
        service php-fpm restart
    fi

    if [ "$NGINX_ENABLED" != "NO" ]; then
        killall nginx; service nginx restart
    fi

    exit 0
fi
### PHP-FPM

if [ "$ACTION" = "remove" ]; then
    if [ ! -d "$WWW_PATH/$FQDN" -o ! -f "$APACHE_CONF_PATH/vhosts.d/$FQDN.conf" -o ! -f "$PHPFPM_CONF_PATH/$FQDN.conf" ]; then
        echo "some of components doesn't exists but i'll remove it forcibly"
    fi

    # remove domain's directories and configuration files
    rm -f $APACHE_CONF_PATH/vhosts.d/$FQDN.conf
    if [ -d "$AWSTATS_CONF_PATH" ]; then
        rm -f $AWSTATS_CONF_PATH/awstats.$FQDN.conf
        rm -rf $AWSTATS_DATA_PATH/$FQDN
    fi
    rm -rf $WWW_PATH/$FQDN

    if [ "$NGINX_ENABLED" != "NO" ]; then
        rm -f $NGINX_CONF_PATH/vhosts.d/$FQDN.conf
    fi

    if [ "$PHPFPM_ENABLED" != "NO" ]; then
        rm -f $PHPFPM_CONF_PATH/$FQDN.conf
    fi

    # remove mysql user and database
    if [ "$MYSQL_ENABLED" != "NO" ]; then
cat << EOF | mysql -f -u$MYSQL_USERNAME -p$MYSQL_PASSWORD
DROP USER '$DB_USER'@'localhost';
DROP USER '$DB_USER'@'%';
DROP DATABASE IF EXISTS \`$DB_NAME\`;
EOF
    fi

    # remove ftp user
    if [ -f "$PUREFTPD_CONF" ]; then
        pure-pw userdel $FQDN -m
    fi

    # remove user
    userdel $FQDN

    # remove postgresql username and database
    if [ "$POSTGRESQL_ENABLED" != "NO" ]; then
        dropdb --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT $DB_NAME
        dropuser --username=$POSTGRESQL_USERNAME --port=$POSTGRESQL_PORT $DB_USER
    fi

    # remove dns zone
    if [ -f "$NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN" -o -f "$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN" ]; then
        rm -f $NAMED_PATH/$NAMED_ZONE_RELATIVE_PATH/$NAME/$FQDN
        cat $NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME.conf | grep -v "include \"$NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN\";" > /tmp/$FQDN.conf
        mv -f /tmp/$FQDN.conf $NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME.conf
        rm -f $NAMED_PATH/$NAMED_CONF_RELATIVE_PATH/$NAME/$FQDN
        rndc reload
    fi

    # remove crontab
    rm -f /etc/cron.d/$FQDN

    # restart web servers
    apachectl graceful

    if [ "$PHPFPM_ENABLED" != "NO" ]; then
        service php-fpm restart
    fi

    if [ "$NGINX_ENABLED" != "NO" ]; then
        killall nginx; service nginx restart
    fi

    echo "domain '$FQDN' removed"
    exit 0
fi

exit 1
