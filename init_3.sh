#!/bin/bash
set -e

log() {
  echo -e "\n==================== $1 ===================="
}

# 1. 基础检测
log "System Check"
OS=$(grep '^ID=' /etc/os-release | cut -d= -f2)
if [[ "$OS" != "amzn" ]]; then
  echo "This script is for Amazon Linux only!"
  exit 1
fi

# 2. SELinux
log "SELinux"
getenforce || echo "SELinux disabled by default"

# 3. 防火墙
log "Firewalld"
if systemctl list-unit-files | grep -qw firewalld; then
  systemctl disable --now firewalld || true
fi

# 4. 文件句柄
log "Limits"
cat >/etc/security/limits.d/99-performance.conf<<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65536
* hard nproc  65536
EOF

# 5. 基础工具安装
log "DNF Tools Install"
dnf clean all
dnf makecache
dnf install -y \
  wget curl jq vim tar unzip lsof net-tools bind-utils htop chrony

# 6. Chrony 时钟
log "Time Sync"
systemctl enable --now chronyd
timedatectl set-timezone Asia/Shanghai

# 7. 内核参数调优
log "Kernel Sysctl tuning"
cat >/etc/sysctl.d/99-performance.conf<<EOF
fs.file-max = 2097152
kernel.pid_max = 4194304

net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.core.netdev_max_backlog = 262144
net.core.somaxconn = 65535

net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mem  = 8388608 12582912 16777216

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_mtu_probing = 1

net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 600000

net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_max_orphans = 262144

net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.overcommit_memory = 1

# Conntrack (容器/EKS推荐)
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
EOF

sysctl --system

# 8. SSH 优化（仅增强连接，不破坏安全）
log "SSH Optimization"
sed -i 's/^#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/^UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
systemctl restart sshd

# 9. History 审计增强
log "Shell History Harden"
cat >>/etc/profile<<'EOF'

export HISTSIZE=100000
export HISTFILESIZE=200000
export PROMPT_COMMAND='{ msg=$(history 1); logger -t bash_cmd "$USER $msg"; }'
EOF

# 10. 完成
log "Init Completed"
echo "AL2023 optimization done ✅"
