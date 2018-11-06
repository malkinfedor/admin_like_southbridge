#!/bin/sh

# Southbridge hosting management script by Igor Olemskoi <igor@southbridge.ru> v 1.2

# path
PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"

# functions
generate_password() {
    cat /dev/urandom | tr -dc A-Za-z0-9 | head -c8
}

generate_mysql_password() {
    chars='@#$%&_+='
    { </dev/urandom LC_ALL=C grep -ao '[A-Za-z0-9]' \
            | head -n$((RANDOM % 8 + 9))
        echo ${chars:$((RANDOM % ${#chars})):1}   # Random special char.
    } \
        | shuf \
        | tr -d '\n'
}

create_ftpuser() {
    www_path=$1
    username=$2
    password=$3

    if [ "$FTP_QUOTA" = "0" ]; then
        (echo $password; echo $password) | pure-pw useradd $username -u $FTP_UID -g $FTP_GID -d $www_path -m >/dev/null 2>&1
    else
        (echo $password; echo $password) | pure-pw useradd $username -u $FTP_UID -g $FTP_GID -d $www_path -N $FTP_QUOTA -m >/dev/null 2>&1
    fi

    echo
    echo "h2. FTP"
    echo
    echo "host: $FQDN"
    echo "username: $username"
    echo "password: $password"
    echo "ftp url: ftp://$username:$password@$FQDN/"
}

ssl_certificate_print_manual() {
    echo "Please add manually to nginx config:"
    echo
    echo "include letsencrypt.conf;"
    echo
    echo "Reload nginx:"
    echo "  service nginx reload"
    echo "Issue certificate by command:"
    echo "  sudo -u letsencrypt certbot-auto --config /etc/letsencrypt/configs/$FQDN.conf --no-self-upgrade certonly"
    echo
    echo "And enable SSL for web site in nginx config:"
    echo
    echo "listen 443 ssl;"
    echo "ssl_certificate     /etc/letsencrypt/live/$FQDN/fullchain.pem;"
    echo "ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;"
}

ssl_certificate() {
  SUBDOMAIN=`echo $FQDN | grep -o "\." | wc -l`
  if [ ! -f /usr/bin/certbot-auto ]; then
     echo "Installing letsencrypt packet"
     yum -y install letsencrypt
  fi
  if ! id -u letsencrypt >/dev/null 2>&1; then
     echo "Error! No user letsencypt. Please install packet letsencrypt manually"
     exit
  fi
  if [ ! -f "/etc/letsencrypt/configs/$FQDN.conf" -a $SUBDOMAIN -eq 1 ]; then
    if [ -f "$LOCATION/skel/letsencrypt.tpl" ]; then
      cp $LOCATION/skel/letsencrypt.tpl /etc/letsencrypt/configs/$FQDN.conf
    else
      cp $LOCATION/skel/letsencrypt.tpl.dist /etc/letsencrypt/configs/$FQDN.conf
    fi
    eval sed $SED_FLAGS /etc/letsencrypt/configs/$FQDN.conf
  else
    if [ -f "$LOCATION/skel/letsencrypt_subdomain.tpl" ]; then
      cp $LOCATION/skel/letsencrypt_subdomain.tpl /etc/letsencrypt/configs/$FQDN.conf
    else
      cp $LOCATION/skel/letsencrypt_subdomain.tpl.dist /etc/letsencrypt/configs/$FQDN.conf
    fi
    eval sed $SED_FLAGS /etc/letsencrypt/configs/$FQDN.conf
  fi
  if [ ! -f "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" ]; then
    echo "====================================================================="
    echo "Nginx config for site $FQDN no found"
    echo "File not found: $NGINX_CONF_PATH/vhosts.d/$FQDN.conf"
    echo
    ssl_certificate_print_manual
    exit
  fi
  # try find server_name;
echo "  grep -A 1-iP \"[^#]*server_name.*\s$FQDN\" $NGINX_CONF_PATH/vhosts.d/$FQDN.conf";
  nginx_config_found=`grep -iP "[^#]*server_name.*$FQDN" $NGINX_CONF_PATH/vhosts.d/$FQDN.conf | wc -l`
  if [ $nginx_config_found -eq 0 ]; then
    echo "====================================================================="
    echo "Not found 'server_name $FQDN;' in nginx config $NGINX_CONF_PATH/vhosts.d/$FQDN.conf"
    ssl_certificate_print_manual
    exit
  fi
  nginx_config_dubl=`grep -A 1 -iP "[^#]*server_name.*$FQDN" $NGINX_CONF_PATH/vhosts.d/$FQDN.conf | grep 'include letsencrypt.conf;' | wc -l`
  if [ $nginx_config_dubl -gt 0 ]; then
    echo "====================================================================="
    echo "letsencrypt certificate already configured"
    exit
  fi
  # try to change nginx config
  echo "Backup nginx config to: $NGINX_CONF_PATH/vhosts.d/$FQDN.conf.ssl.backup1"
  cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.ssl.backup1"
  sed "/[^#]*server_name.*\s$FQDN/a \ \ \ \ include letsencrypt.conf;" "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.sed"
  cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.sed" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf"
  rm -f "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.sed"
  if [ -f /usr/sbin/nginx ]; then
   RSTN=`/usr/sbin/nginx -t 2>&1 | grep "syntax is ok" | wc -l`
     if [ $RSTN -ne 1 ]; then
       echo "Nginx config check error. Try to restore config from backup"
       echo "Bad config: $NGINX_CONF_PATH/vhosts.d/$FQDN.conf.bad"
       cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.bad"
       cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.ssl.backup1" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf"
       exit
     fi
  else 
    echo "/usr/sbin/nginx not found"
    exit
  fi
  echo "Reload nginx...."
  service nginx reload
  echo "Issue certifivate ...."
  echo "Please agree Terms of Service"
  echo "====================================================================="
  sudo -u letsencrypt certbot-auto --config /etc/letsencrypt/configs/$FQDN.conf --no-self-upgrade certonly
  ssl_result=$?
  if [ $ssl_result -ne 0 ]; then 
    echo "====================================================================="
    echo "Error occured. Please try manually"
    echo "  sudo -u letsencrypt certbot-auto --config /etc/letsencrypt/configs/$FQDN.conf --no-self-upgrade certonly"
    exit
  fi
  echo "Backup nginx config to: $NGINX_CONF_PATH/vhosts.d/$FQDN.conf.ssl.backup2"
  cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.ssl.backup2"
  sed "/[^#]*server_name.*\s$FQDN/a \
\ \ \ \ listen 443 ssl;\\n\
\ \ \ \ ssl_certificate     /etc/letsencrypt/live/$FQDN/fullchain.pem;\\n\
\ \ \ \ ssl_certificate_key /etc/letsencrypt/live/$FQDN/privkey.pem;\\n\
" "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.sed"

  cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.sed" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf"
  rm -f "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.sed"
  RSTN=`/usr/sbin/nginx -t 2>&1 | grep "syntax is ok" | wc -l`
  if [ $RSTN -ne 1 ]; then
       echo "Nginx config check error. Try to restore config from backup"
       echo "Bad config: $NGINX_CONF_PATH/vhosts.d/$FQDN.conf.bad"
       cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.bad"
       cat "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf.ssl.backup2" > "$NGINX_CONF_PATH/vhosts.d/$FQDN.conf"
       exit
  fi
  echo "Reload nginx...."
  service nginx reload
  echo "Certificate for $FQDN issued"
  echo "All done..."
  exit
}

create_apache_configs() {
    # check existance of directories
    if [ ! -d "$APACHE_CONF_PATH/vhosts.d" ]; then
    mkdir -p $APACHE_CONF_PATH/vhosts.d
    fi

    # apache configuration
    APACHE_VER=`httpd -v | grep 'Apache/2.2' | wc -l`
    if [ $APACHE_VER -gt 0 ]; then 
       APACHE_TPL="apache-vhost.tpl"
    else
       APACHE_TPL="apache24-vhost.tpl"
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
    if [ -f "$LOCATION/skel/nginx-vhost.tpl" ]; then
        cp $LOCATION/skel/nginx-vhost.tpl $WWW_PATH/$FQDN/conf/nginx.conf
    else
        cp $LOCATION/skel/nginx-vhost.tpl.dist $WWW_PATH/$FQDN/conf/nginx.conf
    fi
    eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/nginx.conf
    chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/nginx.conf
    ln -s $WWW_PATH/$FQDN/conf/nginx.conf $NGINX_CONF_PATH/vhosts.d/$FQDN.conf
    fi
}

create_fpm_configs() {
    # php-fpm configuration
    FPM_TPL="php-fpm-pool.tpl"
    if [ -f "$LOCATION/skel/$FPM_TPL" ]; then
    cp $LOCATION/skel/$FPM_TPL $WWW_PATH/$FQDN/conf/php-fpm.conf
    else
    cp $LOCATION/skel/$FPM_TPL.dist $WWW_PATH/$FQDN/conf/php-fpm.conf
    fi

    eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/php-fpm.conf
    chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/php-fpm.conf
    ln -s $WWW_PATH/$FQDN/conf/php-fpm.conf $FPM_CONF_PATH/$FQDN.conf

    # nginx configuration
    if [ -f "$LOCATION/skel/nginx-vhost-fpm.tpl" ]; then
        cp $LOCATION/skel/nginx-vhost-fpm.tpl $WWW_PATH/$FQDN/conf/nginx.conf
    else
        cp $LOCATION/skel/nginx-vhost-fpm.tpl.dist $WWW_PATH/$FQDN/conf/nginx.conf
    fi

    eval sed $SED_FLAGS $WWW_PATH/$FQDN/conf/nginx.conf
    chown $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/nginx.conf
    ln -s $WWW_PATH/$FQDN/conf/nginx.conf $NGINX_CONF_PATH/vhosts.d/$FQDN.conf
}

reload_fpm_configs() {
    if [ -f /usr/sbin/php-fpm ]; then
        RSTN=`/usr/sbin/php-fpm -t 2>&1 | grep 'test is successful' | wc -l`
        if [ $RSTN -ne 1 ]; then
            echo "php-fpm config check error. Service don't reloaded."
        else
            service php-fpm reload
        fi
    else 
        echo "/usr/sbin/php-fpm not found"
    fi
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
if [ -f "$LOCATION/etc/admin.conf.dist" ]; then
    . "$LOCATION/etc/admin.conf.dist"
    if [ -f "$LOCATION/etc/admin.conf" ]; then
        . "$LOCATION/etc/admin.conf"
    fi
else
    echo "can't load $LOCATION/etc/admin.conf.dist, please fetch it from repository"
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
if [ ! -d "$APACHE_CONF_PATH" ]; then
    APACHE_ENABLED="NO"
fi

# check if php-fpm is enabled
if [ ! -d "$FPM_CONF_PATH" ]; then
    FPM_ENABLED="NO"
fi

# get IP from command line if it is stated there. if $IP is not entered, DNS zone creation is disabled
if [ ! -z "$3" ]; then
    IP="$3"
fi

# convert fqdn to the database name
DB_NAME=`echo $FQDN | tr . _`
DB_USER=`echo $FQDN | cksum | awk '{print $1}'`

# sed flags
SED_FLAGS=" -e 's@##WWW_PATH##@$WWW_PATH@g' \
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
if [ "$ACTION" != "create" \
    -a "$ACTION" != "remove" \
    -a "$ACTION" != "change_root_pass" \
    -a "$ACTION" != "createdb" \
    -a "$ACTION" != "ssl" \
    -a "$ACTION" != "create_ftp_user" ]; then
    echo "use $0 <init>"
    echo "use $0 <create|remove> <fqdn> [ip]"
    echo "use $0 <createdb> <mysql|postgresql> <dbname>"
    echo "use $0 <change_root_pass> <mysql|postgresql>"
    echo "use $0 <create_ftp_user> <fqdn> <user_name>"
    echo "use $0 <ssl> <fqdn>"
    exit 1
fi

if [ "$ACTION" = "ssl" ]; then
  ssl_certificate
  exit
fi

# if action "changepass"
if [ "$ACTION" = "change_root_pass" ]; then
    if [ "$FQDN" = "mysql" ]; then
    if [ "$MYSQL_ENABLED" != "NO" ]; then
        PASSWORD=`generate_mysql_password`
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
    DB_PASSWORD=`generate_password`

    if [ "$FQDN" = "mysql" ]; then
    DB_PASSWORD=`generate_mysql_password`
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
    echo "use $0 <create|remove> <fqdn>"
    exit 1
fi

# deny some fqdn names
if [ "$FQDN" = "root" -o "$FQDN" = "mysql" -o "$FQDN" = "redmine" -o "$FQDN" = "pureftpd" -o "$FQDN" = "postgres" -o "$FQDN" = "pgsql" ]; then
    echo "can't create/remove project 'root', 'mysql', 'postgres', 'pgsql', 'redmine' and 'pureftpd', these project names are forbidden."
    exit 1
fi

# if action "create"
if [ "$ACTION" = "create" ]; then

    # if fqdn already exists
    if [ -d "$WWW_PATH/$FQDN" -o -f "$APACHE_CONF_PATH/vhosts.d/$FQDN.conf" -o -f "$FPM_CONF_PATH/$FQDN.conf" ]; then
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

    if [ "$NGINX_ENABLED" != "NO" -a ! -d "$NGINX_CONF_PATH/vhosts.d" ]; then
    mkdir -p $NGINX_CONF_PATH/vhosts.d
    fi

    mkdir -p $WWW_PATH/$FQDN $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN/logs/cron $WWW_PATH/$FQDN/htdocs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    chmod 777 $WWW_PATH/$FQDN/tmp
    chmod 777 $WWW_PATH/$FQDN/logs/cron
    chown -R $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/logs $WWW_PATH/$FQDN/tmp $WWW_PATH/$FQDN/conf
    chown -R $FTP_UID:$FTP_GID $WWW_PATH/$FQDN/htdocs

    # crontab
    touch $WWW_PATH/$FQDN/conf/crontab
    chown -R $ROOT_USERNAME:$ROOT_GROUP $WWW_PATH/$FQDN/conf/crontab
    ln -s $WWW_PATH/$FQDN/conf/crontab /etc/cron.d/$FQDN

    # select type configs: apache or php-fpm. And run creation.
    if [ "$FPM_ENABLED" = "NO" ]; then
      create_apache_configs
    else
      create_fpm_configs
    fi

    # generate db password
    DB_PASSWORD=`generate_password`

    # create mysql database and grant access
    if [ "$MYSQL_ENABLED" != "NO" ]; then
    DB_PASSWORD=`generate_mysql_password`
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
        tmp_ftpcmdout=`mktemp`
    create_ftpuser $WWW_PATH/$FQDN $FQDN $PASSWORD > $tmp_ftpcmdout
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
    cat $tmp_ftpcmdout
    rm -f $tmp_ftpcmdout
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
    if [ "$FPM_ENABLED" = "NO" ]; then
      apachectl graceful
    else
      reload_fpm_configs
    fi

    if [ "$NGINX_ENABLED" != "NO" ]; then
    killall nginx; service nginx restart
    fi

    exit 0
fi

if [ "$ACTION" = "remove" ]; then
    if [ ! -d "$WWW_PATH/$FQDN" -o ! -f "$APACHE_CONF_PATH/vhosts.d/$FQDN.conf" ]; then
    echo "some of components doesn't exists but i'll remove it forcibly"
    fi

    # remove domain's directories and configuration files
    rm -f $APACHE_CONF_PATH/vhosts.d/$FQDN.conf
    if [ -d "$AWSTATS_CONF_PATH" ]; then
    rm -f $AWSTATS_CONF_PATH/awstats.$FQDN.conf
    rm -rf $AWSTATS_DATA_PATH/$FQDN
    fi
    rm -rf $WWW_PATH/$FQDN

    rm -f $FPM_CONF_PATH/$FQDN.conf

    if [ "$NGINX_ENABLED" != "NO" ]; then
    rm -f $NGINX_CONF_PATH/vhosts.d/$FQDN.conf
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
    if [ "$APACHE_ENABLED" != "NO" ]; then
    apachectl graceful
    fi

    if [ "$FPM_ENABLED" != "NO" ]; then
      reload_fpm_configs
    fi

    if [ "$NGINX_ENABLED" != "NO" ]; then
    killall nginx; service nginx restart
    fi

    echo "domain '$FQDN' removed"
    exit 0
fi

if [ "$ACTION" = "create_ftp_user" ]; then

    test $# -eq 3 || { echo "Wrong usage! Use $0 <create_ftp_user> <fqdn> <user_name>"; exit 1; }

    PASSWORD=`generate_password`

    tmp_ftpcmdout=`mktemp`
    create_ftpuser $WWW_PATH/$FQDN $3 $PASSWORD > $tmp_ftpcmdout
    cat $tmp_ftpcmdout
    rm -f $tmp_ftpcmdout
fi

exit 1
