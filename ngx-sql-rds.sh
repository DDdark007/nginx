#!/bin/bash

# 检查是否以 root 身份运行
if [[ $EUID -ne 0 ]]; then
    echo "必须以 root 身份运行该脚本."
    exit 1
fi

# 全局变量设置
MYSQL_PWD="oNzQsS4Has3GC6PL"
MYSQL_PORT=32060
mycnfid=1
DATE=$(date +%Y%m%d%H%M%S)

# 统一日志输出函数
log_info() {
    echo -e "\n\033[33m========== $1 ==========\033[0m"
}

# 通用下载函数（带重试及错误检查）
download_file() {
    local url=$1
    local dest=${2:-.}
    wget -q "$url" -P "$dest" || { echo "下载 $url 失败"; exit 1; }
}

#############################################
# Java 安装相关
#############################################

install_java8() {
    log_info "部署 JDK-8"
    local jdk_url="https://corretto.aws/downloads/resources/8.442.06.1/amazon-corretto-8.442.06.1-linux-x64.tar.gz"
    local tar_name="amazon-corretto-8.442.06.1-linux-x64.tar.gz"
    # 如文件不存在则下载
    [[ ! -f $tar_name ]] && download_file "$jdk_url"
    tar xf "$tar_name" -C /usr/local/
    # 移动或覆盖安装目录
    mv -f /usr/local/amazon-corretto-8.442.06.1-linux-x64/ /usr/local/java
    # 添加环境变量到 /etc/profile（避免重复添加）
    if ! grep -q "JAVA_HOME=/usr/local/java" /etc/profile; then
        cat >> /etc/profile <<EOF

# Java 8 环境变量设置
export JAVA_HOME=/usr/local/java
export PATH=\$PATH:\$JAVA_HOME/bin
EOF
    fi
    source /etc/profile
    ln -sf /usr/local/java/bin/* /usr/bin/
    which java && java -version
}

install_java11() {
    log_info "部署 JDK-11"
    local jdk_url="https://corretto.aws/downloads/resources/11.0.26.4.1/amazon-corretto-11.0.26.4.1-linux-x64.tar.gz"
    local tar_name="amazon-corretto-11.0.26.4.1-linux-x64.tar.gz"
    [[ ! -f $tar_name ]] && download_file "$jdk_url"
    tar xf "$tar_name" -C /usr/local/
    mv -f /usr/local/amazon-corretto-11.0.26.4.1-linux-x64 /usr/local/java
    if ! grep -q "JAVA_HOME=/usr/local/java" /etc/profile; then
        cat >> /etc/profile <<EOF

# Java 11 环境变量设置
export JAVA_HOME=/usr/local/java
export PATH=\$PATH:\$JAVA_HOME/bin
EOF
    fi
    source /etc/profile
    ln -sf /usr/local/java/bin/* /usr/bin/
    which java && java -version
}

install_im_bs_upload_jdk17() {
    log_info "部署 JDK-17"
    local jdk_url="https://corretto.aws/downloads/resources/17.0.14.7.1/amazon-corretto-17.0.14.7.1-linux-x64.tar.gz"
    local tar_name="amazon-corretto-17.0.14.7.1-linux-x64.tar.gz"
    [[ ! -f $tar_name ]] && download_file "$jdk_url"
    tar xf "$tar_name"
    mv -f amazon-corretto-17.0.14.7.1-linux-x64 /usr/local/jdk17
    # 可根据需要设置环境变量（或独立管理多个JDK）
}

#############################################
# NGINX 安装及配置
#############################################

install_nginx() {
    log_info "部署 NGINX-1.22.0"
    # 安装依赖包
    yum -y install wget gcc gcc-c++ automake pcre pcre-devel zlib zlib-devel openssl openssl-devel git || { echo "安装依赖失败"; exit 1; }

    # 确保源码目录存在
    mkdir -p /usr/local/src
    cd /usr/local/src

    # 下载 NGINX 及所需模块源码包
    download_file "https://nginx.org/download/nginx-1.22.0.tar.gz"
    download_file "https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz"
    [[ ! -d ngx_http_geoip2_module ]] && git clone https://github.com/leev/ngx_http_geoip2_module.git
    [[ ! -d ngx_healthcheck_module ]] && git clone https://github.com/zhouchangxun/ngx_healthcheck_module.git
    [[ ! -d GeoLite2 ]] && git clone https://github.com/DDdark007/GeoLite2.git

    # 解压源码包
    tar xf libmaxminddb-1.6.0.tar.gz
    tar xf nginx-1.22.0.tar.gz

    # 安装 libmaxminddb
    cd libmaxminddb-1.6.0
    ./configure && make && make install
    ldconfig
    echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf
    ldconfig

    # 编译安装 NGINX
    cd ../nginx-1.22.0
    ./configure --with-http_ssl_module --with-stream --with-http_realip_module \
      --http-client-body-temp-path=/tmp \
      --with-http_v2_module --with-http_stub_status_module --with-http_gzip_static_module \
      --with-pcre --with-stream_ssl_module --with-stream_realip_module \
      --add-module=/usr/local/src/ngx_healthcheck_module --add-module=/usr/local/src/ngx_http_geoip2_module
    make && make install

    # 建立软连接及目录结构
    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx
    mkdir -p /usr/local/nginx/{geoip,data/{tio-bs-page,tio-download,tio-mg-page},conf/ssl}
    mkdir -p /home/upload/
    # 部署 GeoIP2 数据库（将 GeoLite2 中内容复制过去）
    cp -r /usr/local/src/GeoLite2/* /usr/local/nginx/geoip/ 2>/dev/null || true

    mkdir -p /usr/local/nginx/conf/vhost/{web,default}
    cd /usr/local/nginx/conf/vhost/default
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/default.conf" .

    cd /usr/local/nginx/conf/
    [[ -f nginx.conf ]] && mv nginx.conf nginx.conf.bak.$DATE
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/nginx.conf" .
    cd /usr/local/nginx/conf/vhost/web/
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/admin.conf" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/down.conf" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/gateway.conf" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/web.conf" .

    # 添加开机自启（将 nginx 加入 /etc/rc.local）
    chmod +x /etc/rc.d/rc.local
    if ! grep -q "/usr/local/nginx/sbin/nginx" /etc/rc.d/rc.local; then
        echo "/usr/local/nginx/sbin/nginx" >> /etc/rc.d/rc.local
    fi

    # 添加 TOA 模块（需安装内核开发包）
    uname -r
    yum install -y "kernel-devel-$(uname -r)"
    cd /opt
    download_file "http://toa.hk.ufileos.com/linux_toa.tar.gz"
    tar -zxvf linux_toa.tar.gz
    cd linux_toa
    make
    mv toa.ko /lib/modules/$(uname -r)/kernel/net/netfilter/ipvs/toa.ko
    insmod /lib/modules/$(uname -r)/kernel/net/netfilter/ipvs/toa.ko
    lsmod | grep toa
}

#############################################
# go-mmproxy 部署（基于 go 安装）
#############################################

install_im_go_mmproxy() {
    log_info "部署 go-mmproxy"
    yum update -y
    amazon-linux-extras install epel -y
    yum install -y golang || { echo "安装 golang 失败"; exit 1; }
    # 使用 go 安装最新版本
    su - root -c "go install github.com/path-network/go-mmproxy@latest"
    # 默认 go 安装路径为 /root/go/bin/
    cp -f /root/go/bin/go-mmproxy /usr/bin/
    # 创建 systemd 服务
    cat > /etc/systemd/system/go-mmproxy.service << 'EOF'
[Unit]
Description=go-mmproxy service
After=network.target

[Service]
Type=simple
User=root
LimitNOFILE=65535
ExecStartPost=/sbin/ip rule add from 127.0.0.1/8 iif lo table 123
ExecStartPost=/sbin/ip route add local 0.0.0.0/0 dev lo table 123
ExecStart=/usr/bin/go-mmproxy -4 127.0.0.1:9326 -l 0.0.0.0:39326
ExecStopPost=/sbin/ip rule del from 127.0.0.1/8 iif lo table 123
ExecStopPost=/sbin/ip route del local 0.0.0.0/0 dev lo table 123
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl start go-mmproxy.service
    systemctl enable go-mmproxy.service
    netstat -tnlp | grep 39326 || echo "go-mmproxy 可能未正常启动"
}

#############################################
# MySQL 8 安装及配置（适用于 EL7）
#############################################

install_mysql8_el7() {
    log_info "部署 MySQL 8.0"
    # 创建 mysql 用户及目录
    groupadd -r mysql 2>/dev/null || true
    useradd -r -g mysql mysql -d /home/mysql -m 2>/dev/null || true
    mkdir -p /data/{datafile,log,backup}
    chown -R mysql:mysql /data
    chmod -R 755 /data

    # 关闭 SELinux
    setenforce 0 || true
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

    # 下载 MySQL 安装包（如果不存在则下载）
    cd /opt
    local mysql_tar="mysql-8.2.0-1.el7.x86_64.rpm-bundle.tar"
    if [[ ! -f $mysql_tar ]]; then
        if ping -c 4 google.com &>/dev/null; then
            download_file "https://downloads.mysql.com/archives/get/p/23/file/$mysql_tar" "/opt"
        else
            echo "无法连接网络，请手动下载 MySQL 包！"
            exit 1
        fi
    else
        echo "MySQL 安装包已存在，跳过下载"
    fi

    # 安装依赖包（若尚未安装）
    if ! rpm -qa | grep -q libaio-devel; then
        yum install -y gcc gcc-c++ openssl openssl-devel libaio libaio-devel ncurses ncurses-devel &>/dev/null
        action "安装 MySQL 依赖包完成" /bin/true
    else
        action "MySQL 依赖包已安装" /bin/true
    fi

    # 检查是否已有 mysqld 进程在运行
    if pgrep mysqld &>/dev/null; then
        echo "检测到已有 mysqld 进程，跳过安装 MySQL"
        return
    fi

    # 卸载可能冲突的 mysql 或 mariadb 组件
    rpm -qa | grep mysql | xargs -r rpm -e --nodeps
    rpm -qa | grep mariadb | xargs -r rpm -e --nodeps

    # 解包并安装 MySQL
    tar -xf "$mysql_tar" -C /opt/
    yum install -y /opt/*.rpm
    cd ~

    # 备份原有 my.cnf 文件
    [[ -f /etc/my.cnf ]] && cp /etc/my.cnf /etc/my.cnf.bak.$DATE

    # 根据 mycnfid 选择配置文件
    if [ "$mycnfid" -eq 1 ]; then
        download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/sql45g.conf" /etc
        mv /etc/sql45g.conf /etc/my.cnf
    else
        download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/sql6g.conf" /etc
        mv /etc/sql6g.conf /etc/my.cnf
    fi

    # 启动 MySQL 服务
    systemctl start mysqld.service
    if ! systemctl is-active mysqld.service &>/dev/null; then
        echo "启动 MySQL 服务失败"
        return
    fi
    systemctl enable mysqld.service
    sleep 3

    # 从日志中获取临时密码，并更新密码及相关配置
    MYSQL_TEMP_PWD=$(grep "temporary password" /data/log/mysqld.log | tail -1 | awk '{print $NF}')
    local new_temp_pwd="0AQGW6sGTLx#"
    mysql -hlocalhost -P${MYSQL_PORT} -uroot -p"${MYSQL_TEMP_PWD}" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${new_temp_pwd}';"
    mysql -hlocalhost -P${MYSQL_PORT} -uroot -p"${new_temp_pwd}" --connect-expired-password -e "SET GLOBAL validate_password.policy=0;"
    mysql -hlocalhost -P${MYSQL_PORT} -uroot -p"${new_temp_pwd}" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_PWD}';"
    mysql -hlocalhost -P${MYSQL_PORT} -uroot -p"${MYSQL_PWD}" --connect-expired-password -e "USE mysql; UPDATE user SET host='%' WHERE user='root'; FLUSH PRIVILEGES;"
    echo -e "\033[33mMySQL 8.0 部署完成\033[0m"
    cat > /tmp/mysql8.log <<EOF
MySQL 安装目录：/data
MySQL 版本：MySQL 8.0
MySQL 端口：${MYSQL_PORT}
MySQL 密码：${MYSQL_PWD}
EOF
    echo "MySQL 安装信息保存在 /tmp/mysql8.log"
    sleep 3
}

#############################################
# Redis 安装及配置
#############################################

install_redis() {
    log_info "部署 Redis 6.2.6"
    yum -y install wget gcc gcc-c++ automake pcre pcre-devel zlib zlib-devel openssl openssl-devel git
    cd /root
    local redis_tar="redis-6.2.6.tar.gz"
    [[ ! -f $redis_tar ]] && download_file "http://download.redis.io/releases/$redis_tar"
    tar xf "$redis_tar"
    cd redis-6.2.6
    make && make PREFIX=/usr/local/redis install
    mkdir -p /usr/local/redis/{data,conf,log}
    cd /usr/local/redis/conf
    download_file "https://raw.githubusercontent.com/DDdark007/redis_conf/main/redis.conf"
    ln -sf /usr/local/redis/bin/redis-server /usr/bin/redis-server
    ln -sf /usr/local/redis/bin/redis-cli /usr/bin/redis-cli
    # 启动 Redis 并添加开机自启
    redis-server /usr/local/redis/conf/redis.conf &
    if ! grep -q "redis-server /usr/local/redis/conf/redis.conf" /etc/rc.d/rc.local; then
        echo "redis-server /usr/local/redis/conf/redis.conf" >> /etc/rc.d/rc.local
    fi
    echo -e "\033[33mRedis 部署完成\033[0m"
    echo "Redis 密码配置："
    grep -E "^[[:space:]]*requirepass" /usr/local/redis/conf/redis.conf || echo "未设置密码"
}

#############################################
# Elasticsearch 与 Kibana 部署
#############################################

install_es() {
    log_info "部署 Elasticsearch & Kibana 8.6.2"
    cd /root
    download_file "https://artifacts.elastic.co/downloads/kibana/kibana-8.6.2-x86_64.rpm"
    download_file "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.6.2-x86_64.rpm"
    yum install -y elasticsearch-8.6.2-x86_64.rpm
    yum install -y kibana-8.6.2-x86_64.rpm
    # 替换配置文件
    [[ -f /etc/elasticsearch/elasticsearch.yml ]] && mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak.$DATE
    cd /etc/elasticsearch/
    download_file "https://raw.githubusercontent.com/DDdark007/redis_conf/main/elasticsearch.yml" .
    cd /etc/kibana
    [[ -f kibana.yml ]] && mv kibana.yml kibana.yml.bak.$DATE
    download_file "https://raw.githubusercontent.com/DDdark007/redis_conf/main/kibana.yml" .
    systemctl daemon-reload
    systemctl start elasticsearch kibana
    systemctl enable elasticsearch kibana
    # 检查集群状态
    curl -XGET 'http://localhost:9200/_cluster/health?pretty'
}

#############################################
# MongoDB 部署及配置
#############################################

install_mangodb() {
    log_info "部署 MongoDB 7.0.1"
    cd /root
    local mongo_tar="mongodb-linux-x86_64-rhel70-7.0.1.tgz"
    [[ ! -f $mongo_tar ]] && download_file "https://fastdl.mongodb.org/linux/$mongo_tar"
    tar xf "$mongo_tar"
    mv -f mongodb-linux-x86_64-rhel70-7.0.1 /usr/local/mongodb
    # 创建配置与数据目录
    mkdir -p /usr/local/mongodb/config /data/mongodb/{logs,data,pid}
    cat <<'EOF' > /usr/local/mongodb/config/mongodb.conf
# MongoDB 配置文件
storage:
  dbPath: /data/mongodb/data
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 16
    collectionConfig:
      blockCompressor: snappy

systemLog:
  destination: file
  logAppend: true
  path: /data/mongodb/logs/mongodb.log

processManagement:
  fork: true
  pidFilePath: /data/mongodb/pid/mongodb.pid

net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 10000

# 可选安全设置
security:
  authorization: enabled
EOF
    # 配置环境变量
    if ! grep -q "MONGODB_HOME=/usr/local/mongodb" /etc/profile; then
        cat >> /etc/profile <<EOF

# MongoDB 环境变量设置
export MONGODB_HOME=/usr/local/mongodb
export PATH=\$PATH:\$MONGODB_HOME/bin
EOF
    fi
    source /etc/profile
    # 下载 mongosh 客户端（可选）
    cd /root
    local mongosh_tar="mongosh-1.6.0-linux-x64.tgz"
    [[ ! -f $mongosh_tar ]] && download_file "https://downloads.mongodb.com/compass/$mongosh_tar"
    tar xf "$mongosh_tar"
    cp -f mongosh-1.6.0-linux-x64/bin/mongosh /usr/local/mongodb/bin/
    # 添加开机自启
    if ! grep -q "mongod --config /usr/local/mongodb/config/mongodb.conf" /etc/rc.d/rc.local; then
        echo "mongod --config /usr/local/mongodb/config/mongodb.conf" >> /etc/rc.d/rc.local
    fi
    # 启动 MongoDB
    mongod --config /usr/local/mongodb/config/mongodb.conf &
    sleep 5
    # 创建 root 用户
    echo "Creating MongoDB root user..."
    mongosh --port 27017 <<EOF
use admin
db.createUser({
  user: "root",
  pwd: "5bPoMu3tFdnrQQ90",
  roles: [{role: "root", db: "admin"}]
});
EOF
    echo "MongoDB root 用户创建成功."
}

#############################################
# 主安装函数（可集中调用所有服务安装）
#############################################

install_danji() {
    install_java8
    # install_java11  # 根据需要启用
    install_im_bs_upload_jdk17
    install_nginx
    install_im_go_mmproxy
    install_mysql8_el7
    install_redis
    install_es
    install_mangodb
}

#############################################
# 执行各项安装
#############################################

install_java8
# install_java11  # 如需安装 Java 11 可取消注释
install_im_bs_upload_jdk17
install_nginx
install_im_go_mmproxy
install_mysql8_el7
install_redis
install_es
install_mangodb
# 或者直接调用 install_danji 来一键部署所有服务
# install_danji

echo -e "\n\033[32m所有组件部署完成！\033[0m"
