# admin

Роль для управления пользователями на серверах (они же админы). Создаёт пользователей, удаляет их, управляет паролями и SSH-ключами. Также управляет цепочкой правил iptables "SB.ssh", которая ограничивает возможность подключения к 22-му порту.

## Описание переменных

```yaml
users:
  - { name: string, password: "string", comment: "string string" } # Описание пользователя: ник (логин),
                                                                   # пароль, фамилия и имя

deleted_users: # Список выбывших
  - string

admin_allow_auth_keys: bool # default: false :Позволять ли SSH-ключи, при false трёт ключи из 
                            # ~/.ssh/authorized_keys (OBSOLETED!)
admin_iptables_enable: bool # default: true :Управление SB.ssh
admin_keys_exclusive: bool # default: true :Позволять ли наличие более одного ключа 
                           # в ~/.ssh/authorized_keys. По-умолчанию разрешён только один ключ

admin_iptables_extra_list: # Список доп. адресов, с которых разрешено соединение к 22-му порту
  - ipv4

admin_ssh_iptables_add_hosts: # OBSOLETED, replaced by admin_iptables_extra_list
  - ipv4
```

## Советы

Сгенерировать хеш пароля можно с помощью утилиты doveadm из пакета dovecot

doveadm pw -s SHA512-CRYPT

## Зависимости

Импортирует роль sudo

