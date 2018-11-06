<?php
$cfg['blowfish_secret'] = '{{ ansible_fqdn | to_uuid | password_hash('sha512')}}';
?>
