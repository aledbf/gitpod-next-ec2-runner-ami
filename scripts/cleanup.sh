#!/bin/bash

set -e

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

# disable docker service and rely on the docker socket for activation
systemctl disable docker.service

systemctl stop systemd-resolved
systemctl mask systemd-resolved.service

# ensure we use systemd-resolved configuration (DHCP)
rm -f /etc/resolv.conf

ln -s /run/NetworkManager/no-stub-resolv.conf /etc/resolv.conf

journalctl --rotate || true
journalctl --vacuum-time=1s || true

rm -rf /var/log/journal/*

sync
