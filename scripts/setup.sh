#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LANGUAGE=en_US.UTF-8

function update_apt_sources {
	cat <<'EOF' >/etc/apt/source.list
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ mantic main restricted universe multiverse
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ mantic-updates main restricted universe multiverse
deb [arch=amd64] http://us.archive.ubuntu.com/ubuntu/ mantic-backports main restricted universe multiverse
deb [arch=amd64] http://security.ubuntu.com/ubuntu mantic-security main restricted universe multiverse
EOF
}

function install_packages {
	apt-get update
	apt-get dist-upgrade -y
	apt-get install -y \
		ca-certificates curl gnupg \
		htop lsof atop \
		net-tools tcpdump wget \
		psmisc file nano \
		git \
		zip unzip bzip2 pigz xz-utils zstd \
		software-properties-common \
		linux-base \
		wireless-regdb \
		util-linux-extra \
		nscd \
		awscli
}

function install_git {
	add-apt-repository -y ppa:git-core/ppa
	# https://github.com/git-lfs/git-lfs/blob/main/INSTALLING.md
	export os=ubuntu
	export dist=jammy
	curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
	apt-get install -y git git-lfs
	git lfs install --system --skip-repo
}

function install_docker {
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	chmod a+r /etc/apt/keyrings/docker.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu mantic stable" | tee /etc/apt/sources.list.d/docker.list

	apt-get update
	apt-get install -y \
		docker-ce \
		docker-ce-cli \
		docker-buildx-plugin \
		docker-compose-plugin

	# avoid nftables issues (docker)
	update-alternatives --set iptables /usr/sbin/iptables-legacy

	cp /tmp/docker-daemon.json /etc/docker/daemon.json

	cat <<'EOF' >>/etc/containerd/config.toml
[plugins]
  [plugins."io.containerd.gc.v1.scheduler"]
    pause_threshold = 0.02
    deletion_threshold = 0
    mutation_threshold = 100
    schedule_delay = "60s"
    # https://github.com/containerd/containerd/blob/main/docs/garbage-collection.md#configuration-parameters
    # the default value is 100ms, meaning the gc will impact the boot performance. Delay the start for five minutes
    startup_delay = "300s"
EOF

	systemctl restart containerd
	systemctl restart docker
}

function change_systemd_target {
	rm -f /etc/systemd/system/default.target
	ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
	# quiet systemd
	sed -i 's/#ShowStatus=yes/ShowStatus=no/' /etc/systemd/system.conf
	# remove any existing seed
	rm -f /var/lib/systemd/random-seed
}

function disable_systemd_services {
	# Disable services that can impact the VM during the start or could trigger unattended actions.
	# This is discouraged in everyday situations, but by using the cluster autoscaler the node
	# rotation removes any benefit.
	SERVICES_TO_DISABLE=(
		apport-autoreport.service
		apport.service
		apt-daily-upgrade.service
		apt-daily-upgrade.timer
		apt-daily.service
		apt-daily.timer
		atop.service
		atopacct.service
		autofs.service
		bluetooth.target
		console-setup.service
		crond.service
		e2scrub_reap.service
		fstrim.service
		keyboard-setup
		man-db.service
		man-db.timer
		motd-news.service
		motd-news.timer
		netplan-ovs-cleanup.service
		syslog.service
		systemd-journal-flush
		systemd-pcrphase.service
		ua-messaging.service
		ua-messaging.timer
		ua-reboot-cmds.service
		ua-timer.service
		ua-timer.timer
		ubuntu-advantage.service
		unattended-upgrades.service
		vgauth.service
		open-vm-tools.service
		wpa_supplicant.service
		lvm2-monitor.service
	)
	# shellcheck disable=SC2048
	for SERVICE in ${SERVICES_TO_DISABLE[*]}; do
		systemctl stop "${SERVICE}" >/dev/null 2>&1 || true
		systemctl disable "${SERVICE}" >/dev/null 2>&1 || true
		systemctl mask "${SERVICE}" >/dev/null 2>&1 || true
	done

	rm -f /etc/systemd/system/timers.target.wants/*
	rm -f /etc/systemd/system/sysinit.target.wants/atop*
	rm -f /var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/e2scrub_reap.service
	rm -f /etc/systemd/system/multi-user.target.wants/e2scrub_reap.service
	rm -f /usr/lib/systemd/system/e2scrub_reap.service
}

function install_nodejs {
	NODE_MAJOR=20
	mkdir -p /etc/apt/keyrings
	curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
	echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" >/etc/apt/sources.list.d/nodesource.list

	apt update
	apt-get install -y nodejs

	npm install -g @devcontainers/cli

	rm -rf /usr/include/node/openssl/archs/{aix64-gcc-as,BSD-x86,BSD-x86_64,darwin64-arm64-cc,darwin64-x86_64-cc,darwin-i386-cc,linux32-s390x,linux64-loongarch64,linux64-mips64,linux64-riscv64,linux64-s390x,linux-armv4,linux-ppc64le,solaris64-x86_64-gcc,solaris-x86-gcc,VC-WIN32}
	rm -rf /usr/share/doc/nodejs
}

function configure_locales {
	rm -rf /usr/share/locale/*
	ln -s /etc/locale.alias /usr/share/locale/locale.alias
	localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
}

function remove_motd {
	# Remove MOTD
	rm -f /etc/update-motd.d/*
	ln -fs /dev/null /run/motd.dynamic
}

function adjust_sysctl {
	cp /tmp/sysctl.conf /etc/sysctl.d/tuning.conf
}

function configure_git {
	cat <<'EOF' >/etc/gitconfig
[safe]
directory = *
EOF
}

function adjust_boot {
	# Enable cgroups2
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all \1"/g' /etc/default/grub
	# Enable systemd debug logs
	# sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="systemd.log_level=debug systemd.log_target=console \1"/g' /etc/default/grub
	# Quiet boot and systemd console output
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 \1"/g' /etc/default/grub
	# Disable dynamic CPU frequency
	# https://github.com/amzn/amzn-drivers/blob/4b1c5029f391810cf06404d5877a05349e8b72a4/kernel/linux/ena/ENA_Linux_Best_Practices.rst#cpu-power-state
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="clocksource=tsc intel_pstate=disable intel_idle.max_cstate=0 processor.max_cstate=0 \1"/g' /etc/default/grub
	# Disable audit events
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="audit=0 \1"/g' /etc/default/grub
	# Disable autodetection of services we don't need
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="rd.lvm=0 rd.luks=0 rd.md=0 rd.dm=0 rd.multipath=0 rd.iscsi=0 rd.plymouth=0 rd.udev.log_priority=3 udev.children-max=255 rd.udev.children-max=255 nolvm rd.plymouth=0 plymouth.enable=0 \1"/g' /etc/default/grub

	update-grub
}

function remove_snapd {
	snap list --all | awk '/disabled/{print $1, $3}' |
		while read -r snapname revision; do
			snap remove "$snapname" --revision="$revision"
		done

	apt autoremove --yes --purge snapd
	apt-mark hold snapd
	rm -rf /root/snap

	# https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-ubuntu-64-snap.html
	wget --quiet https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
	dpkg -i amazon-ssm-agent.deb
	rm amazon-ssm-agent.deb

	# https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1966203/comments/11
	rm -rf /usr/lib/udev/rules.d/66-snapd-autoimport.rules

	cp /tmp/seelog.xml /etc/amazon/ssm/seelog.xml

	systemctl enable amazon-ssm-agent
}

function network_manager {
	rm -f /lib/systemd/system/systemd-networkd-wait-online.service
	systemctl disable systemd-networkd.service
	systemctl mask systemd-networkd.service
	apt install -y network-manager
	mkdir -p /etc/network/if-up.d /etc/network/if-down.d

	cat <<'EOF' >/etc/netplan/01-network-manager-all.yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens5:
      dhcp4: true
EOF

	chmod 0600 /etc/netplan/01-network-manager-all.yaml

	cat <<'EOF' >/etc/network/interfaces
auto lo
iface lo inet loopback
EOF
}

function adjust_timesync {
	cp /tmp/chrony.conf /etc/chrony/chrony.conf
}

function disable_apparmor {
	systemctl stop apparmor
	systemctl disable apparmor
}

function adjust_journald {
	cat <<'EOF' >/etc/systemd/journald.conf
[Journal]
Storage=volatile
SystemMaxUse=50M
MaxFileSec=1year
ForwardToSyslog=no
EOF
}

function remove_plymouth {
	apt-get purge -y plymouth
}

function cloud_init {
	cp /tmp/cloud-init.cfg /etc/cloud/cloud.cfg
}

function remove_openscsi {
	apt-get purge -y open-iscsi
}

update_apt_sources
install_packages
install_git
install_docker
change_systemd_target
disable_systemd_services
network_manager
install_nodejs
configure_locales
remove_motd
adjust_sysctl
configure_git
adjust_boot
remove_snapd
adjust_timesync
disable_apparmor
adjust_journald
remove_plymouth
cloud_init
remove_openscsi
