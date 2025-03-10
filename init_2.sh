#!/bin/bash

# 统一日志输出函数
log_info() {
  echo -e "\n==================== $1 ===================="
}

disable_selinux() {
  log_info "禁用SELINUX"
  local selinux_conf="/etc/sysconfig/selinux"
  if grep -q "^SELINUX=disabled" "$selinux_conf"; then
    echo "SELINUX已处于关闭状态"
  else
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' "$selinux_conf"
    setenforce 0 || true
    echo "SELINUX已禁用"
  fi
  grep "^SELINUX=" "$selinux_conf" || true
  getenforce || true
}

disable_firewalld() {
  log_info "禁用firewalld"
  systemctl stop firewalld.service &>/dev/null || true
  systemctl disable firewalld.service &>/dev/null || true
  echo "firewalld状态：$(systemctl is-active firewalld || echo 'inactive')"
  echo "firewalld已禁用"
}

set_limits() {
  log_info "修改文件描述符限制"
  cat <<EOF > /etc/security/limits.conf
*    soft nofile 1048576
*    hard nofile 1048576
*    soft nproc 65536
*    hard nproc 65536
EOF
  ulimit -SHn 1048576
  echo "文件描述符限制已修改: soft=$(ulimit -Sn) hard=$(ulimit -Hn)"
}

setup_yum() {
  log_info "安装常用工具及修改YUM源"
  # 确保 wget 存在
  if ! command -v wget &>/dev/null; then
    yum install -y wget &>/dev/null || { echo "wget安装失败"; exit 1; }
  fi

  # 检查网络连通性
  if ! ping -c 1 -W 1 mirrors.aliyun.com &>/dev/null; then
    echo "无法连接到网络" >&2
    exit 1
  fi

  local os_info
  os_info=$(grep '^NAME=' /etc/os-release || true)
  if echo "$os_info" | grep -q "CentOS Linux 7"; then
    echo "检测到CentOS 7系统，配置CentOS的EPEL源"
    wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo &>/dev/null
    yum install -y epel-release &>/dev/null
  else
    echo "检测到非CentOS 7系统，配置Amazon Linux 2的EPEL源"
    amazon-linux-extras install -y epel &>/dev/null
  fi

  yum clean all &>/dev/null
  yum makecache fast &>/dev/null

  yum install -y ntpdate lsof net-tools vim htop &>/dev/null
  echo "常用工具安装完成"
}

set_ntp() {
  log_info "设置时间同步"
  if ! command -v ntpdate &>/dev/null; then
    yum install -y ntpdate &>/dev/null || { echo "ntpdate安装失败"; exit 1; }
  fi
  # 优先使用 time.windows.com ，如失败则使用阿里云NTP
  ntpdate time.windows.com &>/dev/null || ntpdate ntp.aliyun.com &>/dev/null
  # 避免重复添加定时任务
  if ! grep -q "ntpdate ntp.aliyun.com" /var/spool/cron/root 2>/dev/null; then
    echo "*/5 * * * * /usr/sbin/ntpdate ntp.aliyun.com &>/dev/null" >> /var/spool/cron/root
  fi
  echo "时间同步已设置"
}

optimize_kernel() {
  log_info "优化系统内核参数"
  local sysctl_conf="/etc/sysctl.conf"
  # 检查是否已配置优化参数，避免重复追加
  if ! grep -q "net.ipv6.conf.all.disable_ipv6" "$sysctl_conf"; then
    cat <<'EOF' >> "$sysctl_conf"
# 禁用IPv6（若不使用IPv6）
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# ICMP和路由安全设置
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 反向路径过滤及禁止源路由
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# 系统安全和核心转储设置
kernel.sysrq = 0
kernel.core_uses_pid = 1

# TCP连接优化
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_tw_buckets = 60000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1

# TCP缓冲区设置（最小、默认、最大）
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# 本地端口范围扩展
net.ipv4.ip_local_port_range = 1024 65535

# TCP孤儿套接字及SYN backlog设置
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 1

# 网络核心参数设置
net.core.somaxconn = 10240
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 262144

# IPC与共享内存设置
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296

# 文件描述符最大数
fs.file-max = 2097152

# 虚拟内存交换策略
vm.swappiness = 10
EOF
  fi
  sysctl -p &>/dev/null
  echo "内核参数优化完成"
}

optimize_history() {
  log_info "优化命令历史记录"
  local profile_file="/etc/profile"
  if ! grep -q "HISTTIMEFORMAT" "$profile_file"; then
    cat <<'EOF' >> "$profile_file"

# 为每个登录会话记录IP
if [ -z "$LOGIN_IP" ]; then
    export LOGIN_IP=$(who am i | awk '{print $NF}' | sed -r 's/[()]//g')
fi

# 设置历史命令格式，包含时间、用户、登录IP
if [ -z "$HISTTIMEFORMAT_SET" ]; then
    export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] [$(whoami)] [$LOGIN_IP]: "
    export HISTTIMEFORMAT_SET=1
fi

# 记录shell执行的每条命令及目录变更
if [ -z "$PROMPT_COMMAND_SET" ]; then
    export PROMPT_COMMAND='
    if [ -z "$OLD_PWD" ]; then
        export OLD_PWD=$PWD;
    fi;
    if [ ! -z "$LAST_CMD" ] && [ "$(history 1)" != "$LAST_CMD" ]; then
        logger -t "$(whoami)_shell_dir" "[$OLD_PWD]$(history 1)";
    fi;
    export LAST_CMD="$(history 1)";
    export OLD_PWD=$PWD;'
    export PROMPT_COMMAND_SET=1
fi
EOF
    # 使配置立即生效
    source "$profile_file"
    echo "history配置已添加"
  else
    echo "history优化项已存在"
  fi
}

# 主流程调用各项优化配置
disable_selinux
disable_firewalld
set_limits
setup_yum
set_ntp
optimize_kernel
optimize_history

echo -e "\n系统优化已完成！"
