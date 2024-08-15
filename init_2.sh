#!/bin/bash

# 禁用SELINUX
disable_selinux() {
    echo "========================禁用SELINUX========================"
    if grep -q "SELINUX=disabled" /etc/sysconfig/selinux; then
        echo 'SELINUX已处于关闭状态'
    else
        sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/sysconfig/selinux
        setenforce 0
        echo 'SELINUX已禁用'
    fi
    grep SELINUX=disabled /etc/sysconfig/selinux
    getenforce
    echo "==========================================================="
    sleep 2
}

# 禁用firewalld
disable_firewalld() {
    echo "=======================禁用firewalld========================"
    systemctl stop firewalld.service &> /dev/null
    systemctl disable firewalld.service &> /dev/null
    echo "firewalld状态：$(systemctl is-active firewalld)"
    echo "firewalld已禁用"
    echo "==========================================================="
    sleep 2
}

# 修改文件描述符限制
set_limits() {
    echo "======================修改文件描述符======================="
    cat <<EOF > /etc/security/limits.conf
*    soft nofile 1048576
*    hard nofile 1048576
*    soft nproc 65536
*    hard nproc 65536
EOF
    ulimit -SHn 1048576
    echo "文件描述符限制已修改"
    ulimit -Sn ; ulimit -Hn
    echo "==========================================================="
    sleep 2
}

# 安装常用工具及修改YUM源
setup_yum() {
    echo "=================安装常用工具及修改YUM源==================="
    yum install -y wget &> /dev/null
    if [ $? -eq 0 ]; then
        if ping -c 1 mirrors.aliyun.com &> /dev/null; then
            OS_INFO=$(cat /etc/os-release)
            if echo "$OS_INFO" | grep -q "CentOS Linux 7"; then
                echo "检测到CentOS 7系统，配置CentOS的EPEL源"
                wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo &> /dev/null
                yum install -y epel-release &> /dev/null
            else
                echo "检测到非CentOS 7系统，配置Amazon Linux的EPEL源"
                amazon-linux-extras install -y epel &> /dev/null
            fi
            yum clean all &> /dev/null
            yum makecache &> /dev/null
        else
            echo "无法连接到网络"
            exit 1
        fi
    else
        echo "wget安装失败"
        exit 1
    fi
    yum install -y ntpdate lsof net-tools vim htop &> /dev/null
    echo "已完成常用工具的安装"
    echo "==========================================================="
    sleep 2
}

# 设置时间同步
set_ntp() {
    echo "=======================设置时间同步========================"
    yum install -y ntpdate &> /dev/null
    if [ $? -eq 0 ]; then
        ntpdate time.windows.com
        echo "*/5 * * * * /usr/sbin/ntpdate ntp.aliyun.com &>/dev/null" >> /var/spool/cron/root
        echo "时间同步已设置"
    else
        echo "ntpdate安装失败"
        exit 1
    fi
    echo "==========================================================="
    sleep 2
}

# 优化系统内核参数
optimize_kernel() {
    echo "======================优化系统内核========================="
    cat <<EOF >> /etc/sysctl.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
kernel.sysrq = 0
kernel.core_uses_pid = 1
net.ipv4.tcp_syncookies = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
net.ipv4.tcp_max_tw_buckets = 60000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.core.somaxconn = 10240
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 262144
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 30
fs.file-max = 2097152
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
vm.swappiness = 10
EOF
    sysctl -p
    echo "内核优化完成"
    echo "==========================================================="
    sleep 2
}

# 优化命令历史记录
optimize_history() {
    echo "========================history优化========================"
    if ! grep -q "HISTTIMEFORMAT" /etc/profile; then
        cat <<'EOF' >> /etc/profile
# 设置history格式
export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] [`whoami`] [`who am i | awk '{print $NF}' | sed -r 's#[()]##g'`]: "
# 记录shell执行的每一条命令
export PROMPT_COMMAND='
if [ -z "$OLD_PWD" ];then
    export OLD_PWD=$PWD;
fi;
if [ ! -z "$LAST_CMD" ] && [ "$(history 1)" != "$LAST_CMD" ]; then
    logger -t `whoami`_shell_dir "[$OLD_PWD]$(history 1)";
fi;
export LAST_CMD="$(history 1)";
export OLD_PWD=$PWD;'
EOF
        source /etc/profile
        echo "history优化已完成"
    else
        echo "history已优化"
    fi
    echo "==========================================================="
    sleep 2
}

# 执行所有优化配置
disable_selinux
disable_firewalld
set_limits
setup_yum
set_ntp
optimize_kernel
optimize_history

echo "系统优化已完成！"