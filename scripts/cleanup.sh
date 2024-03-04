#!/bin/bash

set -e

systemctl stop systemd-resolved
systemctl mask systemd-resolved.service

# ensure we use systemd-resolved configuration (DHCP)
rm -f /etc/resolv.conf
ln -s /run/NetworkManager/no-stub-resolv.conf /etc/resolv.conf

rm -f /usr/lib/udev/rules.d/69-bcache.rules

journalctl --rotate || true
journalctl --vacuum-time=1s || true

# cleanup
rm -rf \
	/usr/share/doc/* \
	/run/log/journal/* \
	/var/log/journal/* \
	/var/cache/debconf/* \
	/var/lib/apt/lists/* \
	/var/tmp/* \
	/etc/apparmor.d/usr.lib.snapd.snap-confine.real

apt-get clean -y

sync
