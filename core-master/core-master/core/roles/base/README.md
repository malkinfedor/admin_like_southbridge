## base

### Variables

```yaml
base_ifcfg_line: # Добавить или удалить переменные в /etc/sysconfig/network-scripts/ifcfg-<dev>.
  - dev: "device_name" # ...Default: not defined
    variables:
      - { key: "VAR_NAME", value: "value"[, state: bool] }
      - ...

base_ipv4_forward_enable: bool # Включить "net.ipv4.ip_forward" (vds и vs), default: false

base_static_route: # Добавить статичные маршруты в /etc/sysconfig/network-scripts/route-<dev>,
  - dev: "device_name" # ...а также "на лету" в таблицу маршрутизации (или удалить их)
    routes:
      - { dest: "CIDR", gw: "ipv4_address"[, state: bool] }
      - ...
```

### Dependencies

* `init-variables` (вызывается автоматически через include_role)

### Tags

`atop`, `hosts`, `ifcfg`, `iptables`, `journald`, `ntp`, `resolvconf`, `sysctl`
