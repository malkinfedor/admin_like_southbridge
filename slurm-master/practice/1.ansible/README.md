# Руководство к практике

## Установка Ansible

Ansible уже установлен на adminbox, проверить можно командой:

```
# ssh red00@sbox.slurm.io

[red00@sbox.slurm.io ~]$ ansible --version
ansible 2.6.2
  config file = /etc/ansible/ansible.cfg
  configured module search path = [u'/home/red00/.ansible/plugins/modules', u'/usr/share/ansible/plugins/modules']
  ansible python module location = /usr/lib/python2.7/site-packages/ansible
  executable location = /usr/bin/ansible
  python version = 2.7.5 (default, Jul 13 2018, 13:06:57) [GCC 4.8.5 20150623 (Red Hat 4.8.5-28)]
```

На каждый сервер открыт доступ по root с паролем который вы получили по почте.

**Для работы нам потребуется склонировать к себе репозиторий с Ansible:**

```
cd ~
git clone git@gitlab.slurm.io:red/core.git
```

## Основные файлы и каталог

- Инвентарный файл (список серверов которыми будем управлять): `~/core/red00/hosts`
- Файлы с переменными групп:  `~/core/red00/group_vars`
- Файлы с переменными хостов: `~/core/red00/host_vars`
- Каталог для ролей: `~/core/core/roles`
- Каталог с шаблонами плейбуков: `~/core/core/plays`
- Плейбуки: `~/core/*.yml`

## Примеры запуска команд

### Важно

Перед началом работы перейдите в каталог core: `cd ~/core`

Запуск модуля

```
ansible [group_name] -m module_name
```

Примеры запуска модулей

```
[red00@sbox.slurm.io ~]$ cd core/

[red00@sbox.slurm.io ~/core]$ ansible -i ~/core/red00/hosts red00 -m ping -k -u root
SSH password: 
vs03.r00.slurm.io | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}
vs01.r00.slurm.io | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}
vs02.r00.slurm.io | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}

[red00@sbox.slurm.io ~/core]$ ansible -i ~/core/red00/hosts red00 -m setup -k -u root
SSH password: 
vs01.r00.slurm.io | SUCCESS => {
    "ansible_facts": {
        "ansible_all_ipv4_addresses": [
            "188.246.229.3", 
            "172.20.0.2"
        ], 
...
```

# Первичная настройка сервера

**За основу взято имя пользователя `red00`. У вас будет свой логин, поэтому везде вместо 00 подставляем свой номер.**

Для проведения базовой настройки серверов мы подготовили набор скриптов и ролей которые будут выполнять данную настройку, что нужно сделать для того что выполнить настройку

1. Подготовить inventory файл и файл с переменными группы

```
vi ~/core/red00/hosts
```

В файле вы увидите следующее содержимое:

```
[red00]
vs01.r00.slurm.io               ansible_host=172.20.0.2
vs02.r00.slurm.io               ansible_host=172.20.0.3
vs03.r00.slurm.io               ansible_host=172.20.0.4
```

Его нужно исправить в соответсвии с вашими данными, например если ваш логин `red12` hosts файл после внесения изменений должен выглядеть следующим образом:

```
[red12]
vs01.r12.slurm.io               ansible_host=172.20.12.2
vs02.r12.slurm.io               ansible_host=172.20.12.3
vs03.r12.slurm.io               ansible_host=172.20.12.4
```

Переименовываем файл с переменными хостов в каталоге `~/core/red00/host_vars/*`. Пример:

```
mv ~/core/red00/host_vars/vs01.r00.slurm.io ~/core/red00/host_vars/vs01.r12.slurm.io
mv ~/core/red00/host_vars/vs02.r00.slurm.io ~/core/red00/host_vars/vs02.r12.slurm.io
mv ~/core/red00/host_vars/vs03.r00.slurm.io ~/core/red00/host_vars/vs03.r12.slurm.io
```

Также потербуется изменить файл с групповыми переменными:

```
vi ~/core/red00/group_vars/all
```

Было:

```
base_etc_hosts_local:
  - { ipaddr: '172.20.0.2', host: 'vs01' }
  - { ipaddr: '172.20.0.3', host: 'vs02' }
  - { ipaddr: '172.20.0.4', host: 'vs03' }

base_etc_hosts_common:
  - { ipaddr: '172.20.100.50', fqdn: 'sbox.slurm.io' }
  - { ipaddr: '172.20.100.51', fqdn: 'gitlab.slurm.io' }
  - { ipaddr: '172.20.100.52', fqdn: 'runner.slurm.io' }
```

Стало:

```
base_etc_hosts_local:
  - { ipaddr: '172.20.12.2', host: 'vs01' }
  - { ipaddr: '172.20.12.3', host: 'vs02' }
  - { ipaddr: '172.20.12.4', host: 'vs03' }

base_etc_hosts_common:
  - { ipaddr: '172.20.100.50', fqdn: 'sbox.slurm.io' }
  - { ipaddr: '172.20.100.51', fqdn: 'gitlab.slurm.io' }
  - { ipaddr: '172.20.100.52', fqdn: 'runner.slurm.io' }
```

Также подставляем вместо 0, наш номер.

2. Добавить свой ключ и пароль в роль создания пользователя

Сначала нужно сгененрировать пароль. Сгенерировать хэш пароля можно с помощью утилиты doveadm из пакета dovecot. Запускаете команду, вводите ваш пароль, на выходе получаете хэш пароля:

```
[red00@sbox.slurm.io ~]$ doveadm pw -s SHA512-CRYPT
Enter new password: 
Retype new password: 
{SHA512-CRYPT}$6$quUrHEFoSi80bXtd$0rjjBWFhLpGYC48WeHFwPweVTDUSYRKCF9utzCUMeUbYKPtu4YwzxDpm5j.N3lD81fg7j.qkC2aYzl1rgPuZk1
```

Полученный хэш нужно занести в файл с переменными роли `admin`:

```
vi ~/core/core/roles/admin/defaults/main.yml
```

Было:

```
...
  - { name: red00,
      password: "$6$wmc79ML./i7BMgsj$7mBevxeeL9XDcmD1h2OARPg1s5h2Nf2E9TirTQpemqFwrmIlLeubAC/oG5HuXEhFcJ5HqrsWefxVu9iPJvXn90",
      comment: "red00" }
...
```

Стало:

```
  - { name: red12,
      password: "$6$quUrHEFoSi80bXtd$0rjjBWFhLpGYC48WeHFwPweVTDUSYRKCF9utzCUMeUbYKPtu4YwzxDpm5j.N3lD81fg7j.qkC2aYzl1rgPuZk1",
      comment: "red12" }
```

Также для дальнейшего удобства пользования необходимо добавить ваш ключ в роль, которая при первичной настройке пропишет ваш публичный ключ вашему пользователю:

Ещё раз напоминаю что вместо `red00` подставляем своего пользователя

```
[red00@sbox.slurm.io ~]$ mkdir -p ~/core/core/roles/admin/files/home/red00/.ssh
[red00@sbox.slurm.io ~]$ cat ~/.ssh/id_rsa.pub > ~/core/core/roles/admin/files/home/red00/.ssh/authorized_keys
```

3. Запустить процесс настройки сервера

```
[red00@sbox.slurm.io ~]$ cd ~/core/
[red00@sbox.slurm.io ~/core]$ ./ds-init.sh red00 -k
```

Ключ `-k` означает что авторизоваться необходимо по паролю который вы получили по почте и использовали для авторизации на adminbox.

После того как процесс полностью отработает вы должны увидеть следующее:

```
TASK [restart server] ******************************************************************************************************************************************
changed: [vs01.r00.slurm.io]
changed: [vs02.r00.slurm.io]
changed: [vs03.r00.slurm.io]

PLAY RECAP *****************************************************************************************************************************************************
vs01.r00.slurm.io          : ok=213  changed=103  unreachable=0    failed=0   
vs02.r00.slurm.io          : ok=157  changed=72   unreachable=0    failed=0   
vs03.r00.slurm.io          : ok=157  changed=72   unreachable=0    failed=0 
```

Если `failed=0` значит все прошло успешно, серверы настроены и были перезагружены, проверим что это действительно так:

```
[red00@sbox.slurm.io ~/core]$ ssh vs01.r00.slurm.io
The authenticity of host 'vs01.r00.slurm.io (172.20.0.2)' can't be established.
ECDSA key fingerprint is SHA256:I9bMVDMrIZuLccWTn5q6X38/NMhb3jpXo3izDNV7cd8.
ECDSA key fingerprint is MD5:af:b0:e5:e5:76:ff:8a:f7:19:25:3a:64:cd:25:c9:73.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added 'vs01.r00.slurm.io,172.20.0.2' (ECDSA) to the list of known hosts.
[red00@vs01.r00.slurm.io ~]$ sudo -s
[root@vs01.r00.slurm.io /home/red00]# uptime
 15:24:19 up 1 min,  1 user,  load average: 0.55, 0.22, 0.08
 ```

# Эмуляция периодического запуска ансибля.

```
[red00@sbox.slurm.io ~/core]$ 
[red00@sbox.slurm.io ~/core]$ cd ~/core/
[red00@sbox.slurm.io ~/core]$ ./play.sh red00
* INFO: run ansible-playbook for 'red00'. Log: '/home/red00/core/logs/red00/2018-10-14_15:32:17.log'

PLAY [all] *****************************************************************************************************************************************************

TASK [Gathering Facts] *****************************************************************************************************************************************
ok: [vs02.r00.slurm.io]
ok: [vs03.r00.slurm.io]
ok: [vs01.r00.slurm.io]

TASK [init-variables : Compare hostname with inventory] ********************************************************************************************************
skipping: [vs01.r00.slurm.io]
```

Данная команда выполняет один из плейбуков: `~/core/*.yml` без первички. Ее безболезнено можно запускать сколько угодно раз для поддержания описанного состояния сервера, или например для применения изменений после внесения правок в роли.

