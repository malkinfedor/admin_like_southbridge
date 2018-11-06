# BOOTSTRAP-OS

Roles is:

- Bootstrap Ubuntu, Debian, CentOS or RedHat
- Remove require tty for pipelining
- Assign inventory name to unconfigured hostnames
- Install basic software which needs on every server
- Install additional software, example:

```
  vars:
    debian_additional_software:
      - cowsay
```

# OS Family

**Debian**: Debian, Ubuntu
**RedHat**: RedHat, CentOS
