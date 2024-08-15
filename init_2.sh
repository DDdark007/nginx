#关闭selinux
selinuxset() 
{
	selinux_status=`grep "SELINUX=disabled" /etc/sysconfig/selinux | wc -l`
	echo "========================禁用SELINUX========================"
	if [ $selinux_status -eq 0 ];then
		sed  -i "s#SELINUX=enforcing#SELINUX=disabled#g" /etc/sysconfig/selinux
		setenforce 0
		echo '#grep SELINUX=disabled /etc/sysconfig/selinux'
		grep SELINUX=disabled /etc/sysconfig/selinux
		echo '#getenforce'
		getenforce
	else
		echo 'SELINUX已处于关闭状态'
		echo '#grep SELINUX=disabled /etc/sysconfig/selinux'
                grep SELINUX=disabled /etc/sysconfig/selinux
                echo '#getenforce'
                getenforce
	fi
		action "完成禁用SELINUX" /bin/true
	echo "==========================================================="
	sleep 2
}
#关闭firewalld
firewalldset()
{
	echo "=======================禁用firewalld========================"
	systemctl stop firewalld.service &> /dev/null
	echo '#firewall-cmd  --state'
	systemctl disable firewalld.service &> /dev/null
	echo '#systemctl list-unit-files | grep firewalld'
	systemctl list-unit-files | grep firewalld
	action "完成禁用firewalld，生产环境下建议启用！" /bin/true
	echo "==========================================================="
	sleep 5
}
#修改文件描述符
limitset()
{
	echo "======================修改文件描述符======================="
	echo '* - nofile 65535'>/etc/security/limits.conf
	echo '* - nproc 65536'>>/etc/security/limits.conf
	echo '*    soft nofile 1048576'>>/etc/security/limits.conf
	echo '*    hard nofile 1048576'>>/etc/security/limits.conf
	ulimit -SHn 65535
	echo "#cat /etc/security/limits.conf"
	cat /etc/security/limits.conf
	echo "#ulimit -Sn ; ulimit -Hn"
	ulimit -Sn ; ulimit -Hn
	action "完成修改文件描述符" /bin/true
	echo "==========================================================="
	sleep 2
}
#安装常用工具及修改yum源
yumset() {
    echo "=================安装常用工具及修改yum源==================="
    yum install wget -y &> /dev/null
    if [ $? -eq 0 ]; then
        #cd /etc/yum.repos.d/
        #\cp CentOS-Base.repo CentOS-Base.repo.$(date +%F)
        ping -c 1 mirrors.aliyun.com &> /dev/null
        if [ $? -eq 0 ]; then
            # 根据操作系统决定如何配置EPEL源
            #!/bin/bash
	    # 获取操作系统信息
	    OS_INFO=$(cat /etc/os-release)

	    # 检测是否为CentOS 7
	    if echo "$OS_INFO" | grep -q -i "centos" && echo "$OS_INFO" | grep -q "VERSION_ID=\"7\""; then
    	    # 如果系统是CentOS 7
            	echo "检测到CentOS 7系统，配置CentOS的EPEL源"
    		wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo &> /dev/null
    		yum install epel-release -y &> /dev/null
	    else
    		# 如果系统不是CentOS 7
    		echo "未检测到CentOS 7系统，假定为Amazon Linux系统，配置Amazon Linux的EPEL源"
    		amazon-linux-extras install epel -y &> /dev/null
	    fi
            yum clean all &> /dev/null
            yum makecache &> /dev/null
        else
            echo "无法连接到网络"
            exit $?
        fi
    else
        echo "wget安装失败"
        exit $?
    fi
    yum -y install ntpdate lsof net-tools telnet vim lrzsz tree nmap nc sysstat bind-utils htop &> /dev/null
    echo "完成安装常用工具及修改yum源"
    echo "==========================================================="
    sleep 2
}
#设置时间同步
ntpdateset()
{
	echo "=======================设置时间同步========================"
	yum -y install ntpdate &> /dev/null
	if [ $? -eq 0 ];then
		/usr/sbin/ntpdate time.windows.com
		echo "*/5 * * * * /usr/sbin/ntpdate ntp.aliyun.com &>/dev/null" >> /var/spool/cron/root
	else
		echo "ntpdate安装失败"
		exit $?
	fi
	action "完成设置时间同步" /bin/true
	echo "==========================================================="
	sleep 2
}
#优化系统内核
kernelset()
{
	echo "======================优化系统内核========================="
	chk_nf=`cat /etc/sysctl.conf | grep conntrack |wc -l`
	if [ $chk_nf -eq 0 ];then
		cat >>/etc/sysctl.conf<<EOF
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
net.ipv4.tcp_mem = 6177504 8236672 16777216
net.ipv4.tcp_rmem = 4096 873800 16777216
net.ipv4.tcp_wmem = 4096 873800 16777216
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
	else
		echo "优化项已存在。"
	fi
	action "内核调优完成" /bin/true
	echo "==========================================================="
	sleep 2
}
#history优化
historyset()
{
	echo "========================history优化========================"
	chk_his=`cat /etc/profile | grep HISTTIMEFORMAT |wc -l`
	if [ $chk_his -eq 0 ];then
		cat >> /etc/profile <<'EOF'
#设置history格式
export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] [`whoami`] [`who am i|awk '{print $NF}'|sed -r 's#[()]##g'`]: "
#记录shell执行的每一条命令
export PROMPT_COMMAND='\
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
	else
		echo "优化项已存在。"
	fi
	action "完成history优化" /bin/true
	echo "==========================================================="
	sleep 2
}
selinuxset
firewalldset
limitset
yumset
ntpdateset
kernelset
historyset