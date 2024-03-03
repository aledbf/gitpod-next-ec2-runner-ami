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

journalctl --flush --rotate --vacuum-time=1s
journalctl --user --flush --rotate --vacuum-time=1s
