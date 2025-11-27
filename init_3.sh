#!/bin/bash
set -e

log_info() {
  echo -e "\n==================== $1 ===================="
}

disable_selinux() {
  log_info "检查 SELinux (AL2023 默认关闭)"
  if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce || true)
    echo "当前 SELinux 状态：$SELINUX_STATUS"

    if [ "$SELINUX_STATUS" != "Disabled" ]; then
      if [ -f /etc/selinux/config ]; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0 || true
        echo "SELinux 已关闭"
      fi
    fi
  else
    echo "SELinux 未启用（正常）"
  fi
}

disable_firewalld() {
  log_info "检查 firewalld"
  if systemctl list-unit-files | grep -q firewalld; then
    systemctl stop firewalld || true
    systemctl disable firewalld || true
    echo "firewalld 已禁用"
  else
    echo "firewalld 未安装（正常）"
  fi
}

set_limits() {
  log_info "设置文件句柄限制"
  cat > /etc/security/limits.d/99-custom.conf <<EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc  65536
* hard nproc  65536
EOF

  cat > /etc/systemd/system.conf.d/99-custom.conf <<EOF
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65536
EOF

  systemctl daemon-reexec
}

setup_pkg() {
  log_info "安装常用工具（dnf）"

  dnf makecache -y

  dnf install -y \
    wget curl vim jq htop \
    net-tools bind-utils lsof \
    chrony fontconfig dejavu-sans-fonts \
    tar unzip
}

setup_time() {
  log_info "配置时间同步（chrony）"

  systemctl enable chronyd
  systemctl restart chronyd

  timedatectl set-timezone Asia/Shanghai
}

optimize_kernel() {
  log_info "内核参数优化"

  SYSCTL_FILE="/etc/sysctl.d/99-performance.conf"
  cat > $SYSCTL_FILE <<'EOF'
# IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# 基础安全
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 反向路径校验
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# TCP 优化
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_max_tw_buckets = 60000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_fastopen = 3

# 缓冲区
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# 连接队列
net.core.somaxconn = 10240
net.core.netdev_max_backlog = 262144

# 端口范围
net.ipv4.ip_local_port_range = 1024 65535

# 文件句柄
fs.file-max = 2097152

# 虚拟内存
vm.swappiness = 10

# TCP keepalive
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6
EOF

  sysctl --system
}

optimize_history() {
  log_info "Shell 审计优化"

  HIST_FILE="/etc/profile.d/history-audit.sh"
  cat > $HIST_FILE <<'EOF'
export HISTSIZE=50000
export HISTFILESIZE=50000

if [ -z "$LOGIN_IP" ]; then
  export LOGIN_IP=$(who -u am i 2>/dev/null | awk '{print $NF}' | tr -d '()')
fi

export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] [$USER] [$LOGIN_IP] "

export PROMPT_COMMAND='
CMD=$(history 1 | { read n line ; echo "$line"; });
logger -p local1.notice -t shell-audit "[$PWD] $CMD"
'
EOF
}

enable_audit_log() {
  log_info "启用审计日志"

  grep -q '^local1.*' /etc/rsyslog.conf || echo 'local1.*    /var/log/cmd.log' >> /etc/rsyslog.conf
  systemctl restart rsyslog
}

main() {
  disable_selinux
  disable_firewalld
  set_limits
  setup_pkg
  setup_time
  optimize_kernel
  optimize_history
  enable_audit_log

  echo -e "\n✅ Amazon Linux 2023 优化完成"
}

main
