Observium - Network Management and Monitoring
=============================================

`Observium`_ is an autodiscovering SNMP based network monitoring
platform written in PHP which includes support for a wide range of
network hardware and operating systems including Cisco, Windows, Linux,
HP, Dell, FreeBSD, Juniper, Brocade, Netscaler, NetApp and many more.

This appliance includes all the standard features in `TurnKey Core`_,
and on top of that:

- Observium configurations:

    - Installed from upstream source code to /opt/observium.
    - Includes all recommended packages including libvirt for virtual
      machine monitoring.
    - Includes recommended cronjob for discovery and polling.

- SSL support out of the box.
- `Adminer`_ administration frontend for MySQL (listening on port
  12322 - uses SSL).
- Postfix MTA (bound to localhost) to allow sending of email (e.g.,
  password recovery).
- All secrets will be regenerated during installation / firstboot
  (security).
- Webmin modules for configuring Apache2, PHP, MySQL and Postfix.

Note: Due to security concerns, adding devices from the webUI is NOT enabled.
      Please add new devices manually via the CLI. Alternatively, if you are
      not concerned with the potential security risk, adding devices from the
      webUI may be enabled - please see `#488(comment)`_.

Credentials *(passwords set at first boot)*
-------------------------------------------

-  Webmin, SSH, MySQL: username **root**
-  Adminer: username **adminer**
-  Observium: username **admin**


.. _Observium: http://www.observium.org
.. _TurnKey Core: https://www.turnkeylinux.org/core
.. _Adminer: http://www.adminer.org/
.. _#488(comment): https://github.com/turnkeylinux/tracker/issues/488#issuecomment-153762770
