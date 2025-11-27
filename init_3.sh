#!/bin/bash
set -euo pipefail

log() {
  echo -e "\n==================== $1 ===================="
}

check_os() {
  log "System Check"

  if [ -r /etc/os-release ]; then
    # 通过 source 方式读取，避免引号问题
    . /etc/os-release
  else
    echo "/etc/os-release 不存在，无法判断系统类型"
    exit 1
  fi

  # 只允许 Amazon Linux 2023
  if [[ "${ID:-}" != "amzn" || "${VERSION_ID:-}" != "2023" ]]; then
    echo "This script is for Amazon Linux 2023 only! Detected: ${PRETTY_NAME:-unknown}"
    exit 1
  fi

  echo "Detected OS: ${PRETTY_NAME}"
}

disable_selinux() {
  log "SELinux"
  if command -v getenforce &>/dev/null; then
    getenforce || true
  else
    echo "SELinux 工具不存在（AL2023 默认未启用 SELinux）"
  fi

  if [ -f /etc/selinux/config ]; then
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config || true
  fi
}

disable_firewalld() {
  log "Firewalld"
  if systemctl list-unit-files | grep -qw firewalld; then
    systemctl disable --now firewalld || true
    echo "firewalld 已关闭"
  else
    echo "firewalld 未安装（正常）"
  fi
}

set_limits() {
  log "Limits (nofile / nproc)"
  cat >/etc/security/limits.d/99-performance.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65536
* hard nproc  65536
EOF
  echo "limits 已写入 /etc/security/limits.d/99-performance.conf"
}

install_tools() {
  log "DNF Tools Install"
  dnf clean all -y
  dnf makecache -y

  # 不再安装 curl，避免和 curl-minimal 冲突
  dnf install -y \
    wget jq vim tar unzip \
    lsof net-tools bind-utils htop chrony
}

config_time() {
  log "Time / Timezone"
  timedatectl set-timezone Asia/Shanghai
  systemctl enable --now chronyd
  timedatectl
}

optimize_sysctl() {
  log "Kernel Sysctl tuning"

  cat >/etc/sysctl.d/99-performance.conf <<'EOF'
############################
# 基础内核资源
############################
fs.file-max = 2097152
kernel.pid_max = 4194304

############################
# 网络队列与缓存
############################
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 65535

############################
# TCP 内存与缓冲区
############################
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mem  = 8388608 12582912 16777216

############################
# TCP 行为调优
############################
net.ipv4.tcp_syncookies       = 1
net.ipv4.tcp_timestamps       = 1
net.ipv4.tcp_sack             = 1
net.ipv4.tcp_window_scaling   = 1
net.ipv4.tcp_no_metrics_save  = 1
net.ipv4.tcp_mtu_probing      = 1

############################
# TIME_WAIT / 回收
############################
net.ipv4.tcp_tw_reuse     = 1
net.ipv4.tcp_fin_timeout  = 15
net.ipv4.tcp_max_tw_buckets = 600000

############################
# 并发连接 & backlog
############################
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_syn_retries     = 2
net.ipv4.tcp_synack_retries  = 2

############################
# 本地端口范围
############################
net.ipv4.ip_local_port_range = 10000 65535

############################
# 孤儿连接控制
############################
net.ipv4.tcp_max_orphans = 262144

############################
# ICMP 与安全
############################
net.ipv4.icmp_echo_ignore_broadcasts     = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

############################
# KeepAlive
############################
net.ipv4.tcp_keepalive_time   = 60
net.ipv4.tcp_keepalive_intvl  = 10
net.ipv4.tcp_keepalive_probes = 6

############################
# 虚拟内存
############################
vm.swappiness              = 10
vm.dirty_ratio             = 20
vm.dirty_background_ratio  = 10
vm.overcommit_memory       = 1

############################
# Conntrack（容器/EKS 节点建议）
############################
net.netfilter.nf_conntrack_max                    = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
EOF

  sysctl --system
}

optimize_ssh() {
  log "SSH Optimization"
  if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config || true
    sed -i 's/^UseDNS yes/UseDNS no/' /etc/ssh/sshd_config || true
    systemctl restart sshd || true
  fi
}

optimize_history() {
  log "Shell History & Audit"
  if ! grep -q "bash_cmd" /etc/profile 2>/dev/null; then
    cat >>/etc/profile <<'EOF'

# 扩展历史记录与简单审计
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTTIMEFORMAT="[%F %T] $(whoami) "

PROMPT_COMMAND='{ msg=$(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//"); logger -t bash_cmd "$USER@$HOSTNAME [$PWD] $msg"; }'
EOF
  fi
}

main() {
  check_os
  disable_selinux
  disable_firewalld
  set_limits
  install_tools
  config_time
  optimize_sysctl
  optimize_ssh
  optimize_history

  log "Init Completed"
  echo "Amazon Linux 2023 optimization done ✅"
}

main
