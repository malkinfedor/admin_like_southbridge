#!/bin/sh

/srv/southbridge/bin/mysql-backup.sh
tar --exclude=/opt/redmine/files --exclude=/opt/redmine/log -f /tmp/redmine-backup-`date +%s`.tar -c /opt/redmine
exit

cd /opt/redmine
rm -f Gemfile.lock

git fetch --all -t
git pull

chown -R root:root /opt/redmine
chown -R redmine:redmine files log tmp public/plugin_assets config/initializers/secret_token.rb config/database.yml
chmod 755 files log tmp public/plugin_assets

bundle install --without development test sqlite postgresql --path vendor/bundle
bundle exec rake db:migrate RAILS_ENV="production"
bundle exec rake redmine:plugins:migrate RAILS_ENV="production"
bundle exec rake tmp:cache:clear
bundle exec rake tmp:sessions:clear

#/etc/init.d/redmine upgrade
#([ -f /opt/redmine/tmp/pids/unicorn.pid ] && kill -USR2 `cat /opt/redmine/tmp/pids/unicorn.pid`)
/etc/init.d/redmine stop
sleep 3
/etc/init.d/redmine start
