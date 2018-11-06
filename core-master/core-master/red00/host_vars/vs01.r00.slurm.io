---

roles:
  - init-variables
  - base
  - sudo
  - admin
  - factory
  - postfix
  - nginx
  - php
  - httpd

backup_remote_hosts: ""
server_type: vds
zabbix_server: ""
base_atop_enable: false

admin_allow_auth_keys: true
admin_keys_exclusive: false

admin_iptables_extra_list:
  - "0.0.0.0/0"

...
