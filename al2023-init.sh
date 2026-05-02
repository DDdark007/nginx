#!/bin/bash
set -euo pipefail

log() {
  echo -e "\n==================== $1 ===================="
}

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 用户执行"
    exit 1
  fi
}

check_os() {
  log "System Check"

  if [ ! -r /etc/os-release ]; then
    echo "/etc/os-release 不存在，无法判断系统类型"
    exit 1
  fi

  . /etc/os-release

  if [[ "${ID:-}" != "amzn" || "${VERSION_ID:-}" != "2023" ]]; then
    echo "This script is for Amazon Linux 2023 only!"
    echo "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
  fi

  echo "Detected OS: ${PRETTY_NAME}"
  uname -a
}

disable_selinux() {
  log "SELinux"

  if command -v getenforce &>/dev/null; then
    getenforce || true
  else
    echo "SELinux tools not installed"
  fi

  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config || true
    echo "SELinux config set to disabled"
  else
    echo "/etc/selinux/config not found"
  fi
}

disable_firewalld() {
  log "Firewalld"

  if systemctl list-unit-files | grep -qw firewalld; then
    systemctl disable --now firewalld || true
    echo "firewalld disabled"
  else
    echo "firewalld not installed"
  fi
}

set_limits() {
  log "Limits"

  cat >/etc/security/limits.d/99-performance.conf <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65536
* hard nproc  65536
root soft nofile 1048576
root hard nofile 1048576
root soft nproc  65536
root hard nproc  65536
EOF

  mkdir -p /etc/systemd/system.conf.d /etc/systemd/user.conf.d

  cat >/etc/systemd/system.conf.d/99-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
EOF

  cat >/etc/systemd/user.conf.d/99-limits.conf <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
EOF

  systemctl daemon-reexec || true

  echo "limits configured"
}

install_tools() {
  log "Install Basic Tools"

  dnf clean all -y || true
  dnf makecache -y

  dnf install -y \
    wget jq vim tar unzip zip gzip \
    lsof net-tools bind-utils htop iotop iftop \
    chrony nc telnet tcpdump rsync \
    psmisc procps-ng sysstat

  systemctl enable --now sysstat || true
}

config_time() {
  log "Time / Timezone"

  timedatectl set-timezone Asia/Shanghai
  systemctl enable --now chronyd
  timedatectl
}

optimize_sysctl() {
  log "Kernel Sysctl Tuning"

  cat >/etc/sysctl.d/99-performance.conf <<'EOF'
############################
# File / Process
############################
fs.file-max = 2097152
fs.nr_open = 2097152
kernel.pid_max = 4194304

############################
# Network Core
############################
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 262144
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864

############################
# TCP Buffer
############################
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

############################
# TCP Basic
############################
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_mtu_probing = 1

############################
# TCP Backlog / SYN
############################
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_abort_on_overflow = 0

############################
# TCP TIME_WAIT
############################
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 600000

############################
# Local Port
############################
net.ipv4.ip_local_port_range = 10000 65535

############################
# KeepAlive
############################
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

############################
# Orphan Socket
############################
net.ipv4.tcp_max_orphans = 262144

############################
# ICMP
############################
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

############################
# Virtual Memory
############################
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.overcommit_memory = 1

############################
# Conntrack
############################
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
EOF

  modprobe nf_conntrack || true
  sysctl --system
}

optimize_ssh() {
  log "SSH Optimization"

  if [ -f /etc/ssh/sshd_config ]; then
    grep -q '^UseDNS' /etc/ssh/sshd_config \
      && sed -i 's/^UseDNS.*/UseDNS no/' /etc/ssh/sshd_config \
      || echo 'UseDNS no' >>/etc/ssh/sshd_config

    sshd -t && systemctl restart sshd
    echo "sshd optimized"
  fi
}

optimize_history() {
  log "Shell History"

  cat >/etc/profile.d/history-audit.sh <<'EOF'
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTTIMEFORMAT="[%F %T] "

export PROMPT_COMMAND='history -a; msg=$(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//"); logger -t bash_cmd "$USER@$HOSTNAME [$PWD] $msg"'
EOF

  chmod +x /etc/profile.d/history-audit.sh
  echo "history audit configured"
}

disable_unneeded_services() {
  log "Disable Unneeded Services"

  for svc in postfix rpcbind; do
    if systemctl list-unit-files | grep -qw "$svc"; then
      systemctl disable --now "$svc" || true
      echo "$svc disabled"
    fi
  done
}

show_result() {
  log "Result"

  echo "OS:"
  cat /etc/os-release | grep -E 'PRETTY_NAME|VERSION_ID'

  echo
  echo "Kernel:"
  uname -r

  echo
  echo "Open files:"
  ulimit -n || true

  echo
  echo "Timezone:"
  timedatectl | grep "Time zone" || true

  echo
  echo "Important sysctl:"
  sysctl net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.ip_local_port_range fs.file-max vm.swappiness
}

main() {
  check_root
  check_os
  disable_selinux
  disable_firewalld
  set_limits
  install_tools
  config_time
  optimize_sysctl
  optimize_ssh
  optimize_history
  disable_unneeded_services
  show_result

  log "Init Completed"
  echo "Amazon Linux 2023 kernel 6.1 optimization done."
  echo "建议重启一次服务器，使 limits / kernel / systemd 配置完全生效。"
}

main "$@"
