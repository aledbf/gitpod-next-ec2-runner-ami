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
		binutils binfmt-support \
		linux-base \
		wireless-regdb \
		util-linux-extra \
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

	cat <<'EOF' >/etc/docker/daemon.json
{
	"debug": false,
	"bip": "172.17.0.1/16",
	"experimental": true,
	"max-concurrent-downloads": 10,
	"max-concurrent-uploads": 10,
	"max-download-attempts": 10,
	"live-restore": false,
	"default-shm-size": "128M",
	"exec-opts": [
		"native.cgroupdriver=systemd"
	],
	"dns-opts": [
		"timeout:5"
	],
	"features": {
    	"containerd-snapshotter": true
  	}
}
EOF

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
	)
	# shellcheck disable=SC2048
	for SERVICE in ${SERVICES_TO_DISABLE[*]}; do
		systemctl stop "${SERVICE}" || true
		systemctl disable "${SERVICE}" || true
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
	# adjust sysctl defaults
	cat <<'EOF' >/etc/sysctl.d/tuning.conf
fs.inotify.max_queued_events=16384

kernel.pid_max=4194304

net.nf_conntrack_max=262144
vm.overcommit_memory=1
vm.panic_on_oom=0

# https://cloud.google.com/compute/docs/troubleshooting/general-tips#communicatewithinternet
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=60
net.ipv4.tcp_keepalive_probes=5

dev.tty.ldisc_autoload=0

# https://nvd.nist.gov/vuln/detail/CVE-2022-4415
fs.suid_dumpable=0

net.ipv4.conf.all.proxy_arp=1
net.ipv4.conf.default.proxy_arp=1
net.ipv4.neigh.default.proxy_delay=0

net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1

# Wait 10 seconds and then reboot
kernel.panic = 10

# Controls the kernel's behaviour when an oops or BUG is encountered
kernel.panic_on_oops = 1

# Allow neighbor cache entries to expire even when the cache is not full
net.ipv4.neigh.default.gc_thresh1 = 0
net.ipv6.neigh.default.gc_thresh1 = 0

# Avoid neighbor table contention in large subnets
net.ipv4.neigh.default.gc_thresh2 = 15360
net.ipv6.neigh.default.gc_thresh2 = 15360
net.ipv4.neigh.default.gc_thresh3 = 16384
net.ipv6.neigh.default.gc_thresh3 = 16384

# Increasing to account for skb structure growth since the 3.4.x kernel series
net.ipv4.tcp_wmem = 4096 20480 4194304

# Bumped the default TTL to 255 (maximum)
net.ipv4.ip_default_ttl = 255

# Enable IPv4 forwarding for container networking.
net.ipv4.conf.all.forwarding = 1

# Enable IPv6 forwarding for container networking.
net.ipv6.conf.all.forwarding = 1

# This is generally considered a safe ephemeral port range
net.ipv4.ip_local_port_range = 32768 60999

# Connection tracking to prevent dropped connections
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_generic_timeout = 120

# Enable loose mode for reverse path filter
net.ipv4.conf.lo.rp_filter = 2

## Kernel hardening settings
## Settings & descriptions sourced from the KSPP wiki, see
## https://kernsec.org/wiki/index.php/Kernel_Self_Protection_Project/Recommended_Settings#sysctls
# Try to keep kernel address exposures out of various /proc files (kallsyms, modules, etc).
kernel.kptr_restrict = 1

# Avoid kernel memory address exposures via dmesg.
kernel.dmesg_restrict = 1

# Disable User Namespaces, as it opens up a large attack surface to unprivileged users.
user.max_user_namespaces = 0

# Turn off unprivileged eBPF access.
kernel.unprivileged_bpf_disabled = 1

# Turn on BPF JIT hardening, if the JIT is enabled.
net.core.bpf_jit_harden = 2

# Increase inotify limits to allow for a greater number of containers
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# Increase virtual memory to allow for larger workloads
vm.max_map_count = 524288
EOF
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
	#sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="systemd.log_level=debug systemd.log_target=console \1"/g' /etc/default/grub
	# Disable dynamic CPU frequency
	# https://github.com/amzn/amzn-drivers/blob/4b1c5029f391810cf06404d5877a05349e8b72a4/kernel/linux/ena/ENA_Linux_Best_Practices.rst#cpu-power-state
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="clocksource=tsc intel_pstate=disable intel_idle.max_cstate=0 processor.max_cstate=0 \1"/g' /etc/default/grub
	# Disable audit events
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="audit=0 \1"/g' /etc/default/grub
	# Quiet boot and systemd console output
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3 \1"/g' /etc/default/grub
	# Disable autodetection of services we don't need
	sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="rd.lvm=0 rd.luks=0 rd.md=0 rd.dm=0 rd.multipath=0 rd.iscsi=0 rd.plymouth=0 rd.udev.log_priority=3 rd.udev.children-max=4 \1"/g' /etc/default/grub

	update-grub
}

function remove_snapd {
	snap remove amazon-ssm-agent
	apt remove -y snapd

	# https://docs.aws.amazon.com/systems-manager/latest/userguide/agent-install-ubuntu-64-snap.html
	wget --quiet https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
	dpkg -i amazon-ssm-agent.deb
	rm amazon-ssm-agent.deb

	systemctl enable amazon-ssm-agent

	# https://bugs.launchpad.net/ubuntu/+source/systemd/+bug/1966203/comments/11
	rm -rf /usr/lib/udev/rules.d/66-snapd-autoimport.rules

	cat <<'EOF' >/etc/amazon/ssm/seelog.xml
<outputs formatid="fmtinfo">
   <console formatid="fmtinfo"/>
   <rollingfile type="size" filename="/var/log/amazon/ssm/amazon-ssm-agent.log" maxsize="30000000" maxrolls="5"/>
   <filter levels="error,critical" formatid="fmterror">
      <rollingfile type="size" filename="/var/log/amazon/ssm/errors.log" maxsize="10000000" maxrolls="5"/>
   </filter>
</outputs>
EOF

}

function systemd_resolved_override {
	mkdir -p /etc/systemd/system/systemd-resolved.service.d
	cat <<'EOF' >/etc/systemd/system/systemd-resolved.service.d/override.conf
[Service]
Environment=SYSTEMD_RESOLVED_SYNTHESIZE_HOSTNAME=0
EOF
}

function network_manager {
	rm -f /lib/systemd/system/systemd-networkd-wait-online.service

	systemctl disable systemd-networkd.service
	systemctl mask systemd-networkd.service

	apt install -y network-manager

	mkdir -p /etc/network/if-up.d /etc/network/if-down.d

	cat <<'EOF' >/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
network: {config: disabled}
EOF

	cat <<'EOF' >/etc/netplan/01-network-manager-all.yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens5:
      dhcp4: true
EOF

	chmod 0600 /etc/netplan/01-network-manager-all.yaml
}

update_apt_sources
install_packages
install_git
install_docker
change_systemd_target
disable_systemd_services
systemd_resolved_override
network_manager
install_nodejs
configure_locales
remove_motd
adjust_sysctl
configure_git
adjust_boot
remove_snapd
