#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "必须以 root 身份运行该脚本"
    exit 1
fi

MYSQL_PORT=32060
MYSQL_PWD="oNzQsS4Has3GC6PL"
DATE=$(date +%Y%m%d%H%M%S)

log_info() {
    echo -e "\n\033[33m========== $1 ==========\033[0m"
}

check_os() {
    . /etc/os-release
    if [[ "${ID:-}" != "amzn" || "${VERSION_ID:-}" != "2023" ]]; then
        echo "只支持 Amazon Linux 2023，当前系统: ${PRETTY_NAME:-unknown}"
        exit 1
    fi
    echo "当前系统: ${PRETTY_NAME}"
    uname -r
}

download_file() {
    local url="$1"
    local dest="${2:-.}"
    wget -q --tries=3 --timeout=20 "$url" -P "$dest" || {
        echo "下载失败: $url"
        exit 1
    }
}

echo_red() {
    echo -e "\033[31m$1\033[0m"
}

install_base_tools() {
    log_info "安装基础依赖"

    dnf clean all -y || true
    dnf makecache -y

    dnf install -y \
        wget jq vim tar unzip zip gzip git \
        gcc gcc-c++ make automake autoconf libtool \
        pcre pcre-devel zlib zlib-devel \
        openssl openssl-devel \
        lsof net-tools bind-utils htop iotop iftop \
        chrony nc telnet tcpdump rsync \
        psmisc procps-ng sysstat \
        fontconfig dejavu-sans-fonts \
        libaio numactl

    systemctl enable --now chronyd || true
    systemctl enable --now sysstat || true
}

install_java17() {
    log_info "部署 JDK 17 最新版"

    # ===== 已安装检测 =====
    if [[ -x /usr/local/java/bin/java ]]; then
        echo_red "检测到已有 Java：/usr/local/java"

        /usr/local/java/bin/java -version || true

        echo_red "跳过安装 JDK17"
        return 0
    fi

    if command -v java &>/dev/null; then
        echo_red "检测到系统已有 Java：$(which java)"
        java -version || true

        echo_red "跳过安装 JDK17"
        return 0
    fi

    local jdk_url="https://corretto.aws/downloads/latest/amazon-corretto-17-x64-linux-jdk.tar.gz"
    local tar_name="amazon-corretto-17-x64-linux-jdk.tar.gz"

    mkdir -p /usr/local/src
    cd /usr/local/src

    rm -f "$tar_name"
    wget -q --tries=3 --timeout=30 "$jdk_url" -O "$tar_name" || {
        echo "下载 JDK17 失败"
        exit 1
    }

    rm -rf /usr/local/java
    tar xf "$tar_name" -C /usr/local/

    local jdk_dir
    jdk_dir=$(find /usr/local -maxdepth 1 -type d -name "amazon-corretto-17*" | head -n 1)

    if [[ -z "$jdk_dir" ]]; then
        echo "未找到解压后的 JDK17 目录"
        exit 1
    fi

    mv "$jdk_dir" /usr/local/java

    cat >/etc/profile.d/java.sh <<'EOF'
export JAVA_HOME=/usr/local/java
export PATH=$JAVA_HOME/bin:$PATH
EOF

    chmod +x /etc/profile.d/java.sh

    ln -sf /usr/local/java/bin/java /usr/bin/java
    ln -sf /usr/local/java/bin/javac /usr/bin/javac
    ln -sf /usr/local/java/bin/jar /usr/bin/jar

    source /etc/profile.d/java.sh

    which java
    java -version
}

install_im_bs_upload_jdk17() {
    log_info "部署 BS_upload_JDK-17"

    # ===== 已安装检测 =====
    if [[ -x /usr/local/jdk17/bin/java ]]; then
        echo_red "检测到已有 Java：/usr/local/jdk17"

        /usr/local/java/bin/java -version || true

        echo_red "跳过安装 JDK17"
        return 0
    fi

    if command -v /usr/local/jdk17/bin/java &>/dev/null; then
        echo_red "检测到系统已有 Java：$(which java)"
        java -version || true

        echo_red "跳过安装 JDK17"
        return 0
    fi

    local jdk_url="https://corretto.aws/downloads/latest/amazon-corretto-17-x64-linux-jdk.tar.gz"
    local tar_name="amazon-corretto-17-x64-linux-jdk.tar.gz"

    mkdir -p /usr/local/src
    cd /usr/local/src

    rm -f "$tar_name"
    wget -q --tries=3 --timeout=30 "$jdk_url" -O "$tar_name" || {
        echo "下载 JDK17 失败"
        exit 1
    }

    tar xf "$tar_name" -C /usr/local/

    local jdk_dir
    jdk_dir=$(find /usr/local -maxdepth 1 -type d -name "amazon-corretto-17*" | head -n 1)

    if [[ -z "$jdk_dir" ]]; then
        echo "未找到解压后的 JDK17 目录"
        exit 1
    fi

    mv "$jdk_dir" /usr/local/jdk17
    # 可根据需要设置环境变量（或独立管理多个JDK）
}

install_java8() {
    log_info "部署 JDK 8"

    # ===== 已安装检测 =====
    if [[ -x /usr/local/java/bin/java ]]; then
        echo_red "检测到已有 Java：/usr/local/java"

        /usr/local/java/bin/java -version || true

        echo_red "跳过安装 JDK8"
        return 0
    fi

    if command -v java &>/dev/null; then
        echo_red "检测到系统已有 Java：$(which java)"
        java -version || true

        echo_red "跳过安装 JDK8"
        return 0
    fi

    # ===== 安装逻辑 =====
    local jdk_url="https://corretto.aws/downloads/resources/8.442.06.1/amazon-corretto-8.442.06.1-linux-x64.tar.gz"
    local tar_name="amazon-corretto-8.442.06.1-linux-x64.tar.gz"

    mkdir -p /usr/local/src
    cd /usr/local/src

    [[ ! -f "$tar_name" ]] && download_file "$jdk_url" /usr/local/src

    rm -rf /usr/local/java

    tar xf "$tar_name" -C /usr/local/

    local jdk_dir
    jdk_dir=$(find /usr/local -maxdepth 1 -type d -name "amazon-corretto-8*" | head -n 1)

    if [[ -z "$jdk_dir" ]]; then
        echo_red "未找到 JDK8 解压目录"
        exit 1
    fi

    mv "$jdk_dir" /usr/local/java

    cat >/etc/profile.d/java.sh <<'EOF'
export JAVA_HOME=/usr/local/java
export PATH=$JAVA_HOME/bin:$PATH
EOF

    chmod +x /etc/profile.d/java.sh
    source /etc/profile.d/java.sh

    ln -sf /usr/local/java/bin/java /usr/bin/java
    ln -sf /usr/local/java/bin/javac /usr/bin/javac
    ln -sf /usr/local/java/bin/jar /usr/bin/jar

    echo "JDK8 安装完成"
    java -version
}

install_nginx() {
    log_info "部署 Nginx 1.28.0"

    # ===== 已安装检测 =====
    if [[ -x /usr/local/nginx/sbin/nginx ]]; then
        echo_red "检测到已有 /usr/local/nginx/sbin/nginx"

        echo_red "跳过安装 nginx"
        return 0
    fi

    mkdir -p /usr/local/src
    cd /usr/local/src

    download_file "https://nginx.org/download/nginx-1.28.0.tar.gz" /usr/local/src
    download_file "https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz" /usr/local/src

    [[ ! -d ngx_http_geoip2_module ]] && git clone https://github.com/leev/ngx_http_geoip2_module.git
    [[ ! -d ngx_healthcheck_module ]] && git clone https://github.com/zhouchangxun/ngx_healthcheck_module.git
    [[ ! -d GeoLite2 ]] && git clone https://github.com/DDdark007/GeoLite2.git

    rm -rf nginx-1.28.0 libmaxminddb-1.6.0
    tar xf libmaxminddb-1.6.0.tar.gz
    tar xf nginx-1.28.0.tar.gz

    cd /usr/local/src/libmaxminddb-1.6.0
    ./configure
    make -j"$(nproc)"
    make install

    echo "/usr/local/lib" >/etc/ld.so.conf.d/local.conf
    ldconfig

    cd /usr/local/src/nginx-1.28.0
    ./configure \
        --prefix=/usr/local/nginx \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_realip_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_realip_module \
        --with-pcre \
        --http-client-body-temp-path=/tmp \
        --add-module=/usr/local/src/ngx_healthcheck_module \
        --add-module=/usr/local/src/ngx_http_geoip2_module

    make -j"$(nproc)"
    make install

    ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx

    mkdir -p /usr/local/nginx/{geoip,data,conf/ssl,conf/vhost/{web,default},logs}
    mkdir -p /home/upload

    cp -r /usr/local/src/GeoLite2/* /usr/local/nginx/geoip/ 2>/dev/null || true

    if [[ -f /usr/local/nginx/conf/nginx.conf ]]; then
        mv /usr/local/nginx/conf/nginx.conf "/usr/local/nginx/conf/nginx.conf.bak.${DATE}"
    fi

    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/nginx.conf" /usr/local/nginx/conf
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/default.conf" /usr/local/nginx/conf/vhost/default

    /usr/local/nginx/sbin/nginx
    /usr/local/nginx/sbin/nginx -t
    echo "nginx-1.28安装完毕"
}

install_nginxim() {
    install_nginx

    log_info "下载 IM Nginx 配置"

    # ===== 已安装检测 =====
    if [[ -x /usr/local/nginx/data/tio-bs-page ]]; then
        echo_red "检测到已有 tio-bs-page"

        echo_red "跳过下载im-ngx配置文件"
        return 0
    fi

    mkdir -p /usr/local/nginx/data/{tio-bs-page,tio-download,tio-mg-page}
    cd /usr/local/nginx/conf/vhost/web/

    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/admin.conf" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/images_proxy" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/down.conf" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/gateway.conf" .
    download_file "https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/web.conf" .

    /usr/local/nginx/sbin/nginx -t
    /usr/local/nginx/sbin/nginx -s reload
}

install_go_mmproxy() {
    log_info "部署 go-mmproxy"

    # ===== 已安装检测 =====
    if [[ -x /etc/systemd/system/go-mmproxy.service ]]; then
        echo_red "检测到已有 /etc/systemd/system/go-mmproxy.service"

        echo_red "跳过安装 go-mmproxy"
        return 0
    fi

    dnf install -y golang iproute

    export GOPATH=/root/go
    export PATH=$PATH:/root/go/bin

    go install github.com/path-network/go-mmproxy@latest
    cp -f /root/go/bin/go-mmproxy /usr/bin/go-mmproxy

    cat >/etc/systemd/system/go-mmproxy.service <<'EOF'
[Unit]
Description=go-mmproxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=1048576
Restart=always
RestartSec=2

ExecStartPre=/bin/sh -c "ip rule del from 127.0.0.1/8 table 123 2>/dev/null || true"
ExecStartPre=/bin/sh -c "ip route del local 0.0.0.0/0 dev lo table 123 2>/dev/null || true"
ExecStartPre=/bin/sh -c "ip rule add from 127.0.0.1/8 table 123"
ExecStartPre=/bin/sh -c "ip route add local 0.0.0.0/0 dev lo table 123"

ExecStart=/usr/bin/go-mmproxy \
    -4 127.0.0.1:9326 \
    -l 0.0.0.0:39326 \
    -p tcp \
    -listeners 32 \
    -v 1

ExecStopPost=/bin/sh -c "ip rule del from 127.0.0.1/8 table 123 2>/dev/null || true"
ExecStopPost=/bin/sh -c "ip route del local 0.0.0.0/0 dev lo table 123 2>/dev/null || true"

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now go-mmproxy

    systemctl status go-mmproxy --no-pager
}

install_redis() {
    log_info "部署 Redis 6.2.6"

    dnf install -y wget gcc gcc-c++ make tar \
        openssl openssl-devel systemd-devel || {
        echo_red "安装 Redis 编译依赖失败"
        exit 1
    }

    cd /root

    local redis_tar="redis-6.2.6.tar.gz"
    local redis_url="http://download.redis.io/releases/${redis_tar}"

    [[ ! -f "$redis_tar" ]] && download_file "$redis_url" /root

    rm -rf /root/redis-6.2.6
    tar xf "$redis_tar"

    cd /root/redis-6.2.6

    make -j"$(nproc)" BUILD_TLS=yes
    make PREFIX=/usr/local/redis install

    mkdir -p /usr/local/redis/{data,conf,log}
    mkdir -p /run/redis

    cd /usr/local/redis/conf

    if [[ -f redis.conf ]]; then
        cp redis.conf "redis.conf.bak.${DATE}"
    fi

    download_file "https://raw.githubusercontent.com/DDdark007/redis_conf/main/redis.conf" /usr/local/redis/conf
    sed -i 's|^pidfile .*|pidfile /run/redis_6379.pid|' /usr/local/redis/conf/redis.conf

    ln -sf /usr/local/redis/bin/redis-server /usr/bin/redis-server
    ln -sf /usr/local/redis/bin/redis-cli /usr/bin/redis-cli

    cat >/etc/systemd/system/redis.service <<'EOF'
[Unit]
Description=Redis 6.2.6 In-Memory Data Store
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=root
Group=root

ExecStart=/usr/local/redis/bin/redis-server /usr/local/redis/conf/redis.conf
ExecStop=/usr/local/redis/bin/redis-cli -a rlfg04eIFR2F80T7 shutdown

PIDFile=/run/redis_6379.pid

Restart=always
RestartSec=3

LimitNOFILE=1048576
LimitNPROC=65536

PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now redis.service

    sleep 2

    echo -e "\033[33mRedis 部署完成\033[0m"

    systemctl status redis.service --no-pager || true

    echo
    echo "Redis 版本："
    /usr/local/redis/bin/redis-server --version

    echo
    echo "Redis 密码配置："
    grep -E "^[[:space:]]*requirepass" /usr/local/redis/conf/redis.conf || echo "未设置密码"

    echo
    echo "连接测试："
    /usr/local/redis/bin/redis-cli -a rlfg04eIFR2F80T7 -p 6379 ping || true
}

install_mysql84_al2023() {
    log_info "部署 MySQL 8.4 LTS - Amazon Linux 2023"

    MYSQL_PWD="${MYSQL_PWD:-oNzQsS4Has3GC6PL}"
    MYSQL_PORT="${MYSQL_PORT:-32060}"
    MYSQL_ENABLE_NATIVE_PASSWORD="${MYSQL_ENABLE_NATIVE_PASSWORD:-1}"
    DATE="${DATE:-$(date +%Y%m%d%H%M%S)}"

    dnf install -y wget tar perl libaio numactl openssl ncurses-compat-libs

    cd /root

    if ! rpm -qa | grep -q mysql84-community-release; then
        wget -O mysql84-community-release-el9.rpm \
            https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm
        dnf install -y ./mysql84-community-release-el9.rpm
    fi

    dnf module disable mysql -y || true

    dnf install -y \
        mysql-community-server \
        mysql-community-client \
        mysql-community-client-plugins \
        mysql-community-libs

    systemctl stop mysqld 2>/dev/null || true

    mkdir -p /data/datafile /data/log /data/backup /data/tmp
    touch /data/log/mysqld.log /data/log/slow.log

    chown -R mysql:mysql /data
    chmod 755 /data
    chmod 750 /data/datafile /data/log /data/backup
    chmod 1777 /data/tmp
    chmod 640 /data/log/mysqld.log /data/log/slow.log

    rm -f /data/mysql.sock /data/mysql.sock.lock /data/datafile/mysqld.pid

    if [[ -f /etc/my.cnf ]]; then
        cp /etc/my.cnf "/etc/my.cnf.bak.${DATE}"
    fi

    cat >/etc/my.cnf <<EOF
[client]
port = ${MYSQL_PORT}
socket = /data/mysql.sock
default-character-set = utf8mb4

[mysql]
prompt = "\\u@mysqldb \\R:\\m:\\s [\\d]> "
no_auto_rehash
default-character-set = utf8mb4

[mysqld]
user = mysql
port = ${MYSQL_PORT}
bind-address = 0.0.0.0

datadir = /data/datafile
socket = /data/mysql.sock
pid-file = /data/datafile/mysqld.pid
log-error = /data/log/mysqld.log
tmpdir = /data/tmp

skip-name-resolve
lower_case_table_names = 1
default_time_zone = "+8:00"

character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

server_id = 3306

max_connections = 3000
max_connect_errors = 1000000
back_log = 1024

open_files_limit = 65535
table_open_cache = 8192
table_definition_cache = 8192
table_open_cache_instances = 16
thread_cache_size = 256

sql_mode = STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

default_storage_engine = InnoDB

innodb_buffer_pool_size = 10G
innodb_buffer_pool_instances = 8

innodb_redo_log_capacity = 4G
innodb_log_buffer_size = 256M

innodb_flush_log_at_trx_commit = 1
innodb_flush_method = O_DIRECT

innodb_file_per_table = 1
innodb_open_files = 65535

innodb_read_io_threads = 8
innodb_write_io_threads = 8

innodb_io_capacity = 3000
innodb_io_capacity_max = 6000

innodb_page_cleaners = 8
innodb_lru_scan_depth = 2048
innodb_flush_neighbors = 0
innodb_adaptive_hash_index = 0

innodb_lock_wait_timeout = 50
innodb_rollback_on_timeout = 1

tmp_table_size = 256M
max_heap_table_size = 256M

sort_buffer_size = 4M
join_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M

max_allowed_packet = 256M

log_bin = /data/log/mysql-bin
binlog_format = ROW
binlog_row_image = FULL
max_binlog_size = 512M
binlog_expire_logs_seconds = 604800

sync_binlog = 1
binlog_cache_size = 4M
max_binlog_cache_size = 1G

relay_log = /data/log/relay-bin
relay_log_recovery = 1
log_replica_updates = 1

gtid_mode = ON
enforce_gtid_consistency = ON

slow_query_log = 1
slow_query_log_file = /data/log/slow.log
long_query_time = 1
log_queries_not_using_indexes = 0

performance_schema = ON

local_infile = 0
explicit_defaults_for_timestamp = 1

loose-validate_password.policy = LOW
loose-validate_password.length = 8
loose-validate_password.mixed_case_count = 0
loose-validate_password.number_count = 0
loose-validate_password.special_char_count = 0

EOF

    if [[ "${MYSQL_ENABLE_NATIVE_PASSWORD}" == "1" ]]; then
        cat >>/etc/my.cnf <<EOF
mysql_native_password = ON

EOF
    fi

    cat >>/etc/my.cnf <<EOF
[mysqladmin]
socket = /data/mysql.sock
EOF

    mkdir -p /etc/systemd/system/mysqld.service.d

    cat >/etc/systemd/system/mysqld.service.d/override.conf <<EOF
[Service]
LimitNOFILE=65535
LimitNPROC=65535
Restart=always
RestartSec=5
EOF

    systemctl daemon-reload

    echo "检查 MySQL 配置..."
    mysqld --validate-config || {
        echo "my.cnf 配置校验失败"
        exit 1
    }

    echo "启动 MySQL..."
    systemctl enable --now mysqld

    sleep 8

    if ! systemctl is-active mysqld >/dev/null 2>&1; then
        echo "MySQL 启动失败，错误日志如下："
        tail -100 /data/log/mysqld.log || true
        systemctl status mysqld --no-pager || true
        exit 1
    fi

    MYSQL_TEMP_PWD=$(grep "temporary password" /data/log/mysqld.log | tail -1 | awk '{print $NF}' || true)

    if [[ -n "${MYSQL_TEMP_PWD}" ]]; then
        echo "检测到临时密码，开始初始化 root 密码..."

        STRONG_TEMP_PWD="MySQL@2026_${RANDOM}Aa!"

        mysql --connect-expired-password \
            -uroot \
            -p"${MYSQL_TEMP_PWD}" \
            -S /data/mysql.sock \
            -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${STRONG_TEMP_PWD}';"

        mysql -uroot -p"${STRONG_TEMP_PWD}" -S /data/mysql.sock <<EOF
SET GLOBAL validate_password.policy = LOW;
SET GLOBAL validate_password.length = 8;
SET GLOBAL validate_password.mixed_case_count = 0;
SET GLOBAL validate_password.number_count = 0;
SET GLOBAL validate_password.special_char_count = 0;

ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_PWD}';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${MYSQL_PWD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

        if [[ "${MYSQL_ENABLE_NATIVE_PASSWORD}" == "1" ]]; then
            echo "启用 mysql_native_password 兼容老客户端..."

            mysql -uroot -p"${MYSQL_PWD}" -S /data/mysql.sock <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PWD}';
ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PWD}';
FLUSH PRIVILEGES;
EOF
        fi
    else
        echo "未检测到临时密码，可能 MySQL 已初始化过，跳过密码初始化"
    fi

    systemctl restart mysqld

    sleep 3

    if ! systemctl is-active mysqld >/dev/null 2>&1; then
        echo "MySQL 重启失败："
        tail -100 /data/log/mysqld.log || true
        exit 1
    fi

    cat >/tmp/mysql84.log <<EOF
MySQL 版本：MySQL 8.4 LTS
MySQL 端口：${MYSQL_PORT}
MySQL 数据目录：/data/datafile
MySQL 日志目录：/data/log
MySQL socket：/data/mysql.sock
MySQL root 密码：${MYSQL_PWD}
mysql_native_password：${MYSQL_ENABLE_NATIVE_PASSWORD}
EOF

    echo -e "\033[33mMySQL 8.4 LTS 部署完成\033[0m"
    cat /tmp/mysql84.log

    mysql -uroot -p"${MYSQL_PWD}" -S /data/mysql.sock -e "SELECT VERSION();"
}

install_es() {
    log_info "部署 Elasticsearch & Kibana 8.6.2"

    cd /root

    download_file "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.6.2-x86_64.rpm" /root
    download_file "https://artifacts.elastic.co/downloads/kibana/kibana-8.6.2-x86_64.rpm" /root

    dnf install -y /root/elasticsearch-8.6.2-x86_64.rpm
    dnf install -y /root/kibana-8.6.2-x86_64.rpm

    [[ -f /etc/elasticsearch/elasticsearch.yml ]] && mv /etc/elasticsearch/elasticsearch.yml "/etc/elasticsearch/elasticsearch.yml.bak.${DATE}"
    [[ -f /etc/kibana/kibana.yml ]] && mv /etc/kibana/kibana.yml "/etc/kibana/kibana.yml.bak.${DATE}"

    download_file "https://raw.githubusercontent.com/DDdark007/redis_conf/main/elasticsearch.yml" /etc/elasticsearch
    download_file "https://raw.githubusercontent.com/DDdark007/redis_conf/main/kibana.yml" /etc/kibana

    sed -i 's/^##\s*-Xms.*/-Xms2g/' /etc/elasticsearch/jvm.options
    sed -i 's/^##\s*-Xmx.*/-Xmx2g/' /etc/elasticsearch/jvm.options

    systemctl daemon-reload
    systemctl enable --now elasticsearch
    systemctl enable --now kibana

    sleep 10
    curl -s 'http://localhost:9200/_cluster/health?pretty' || true
}

install_mongodb() {
    log_info "部署 MongoDB 7（tar 版本，兼容 AL2023）"

    MONGO_VERSION="7.0.9"
    MONGO_TAR="mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION}.tgz"

    cd /usr/local/src
    mkdir -p /usr/local/src

    if [[ ! -f "$MONGO_TAR" ]]; then
        wget -q https://fastdl.mongodb.org/linux/${MONGO_TAR} || {
            echo "下载 MongoDB 失败"
            exit 1
        }
    fi

    rm -rf /usr/local/mongodb
    tar xf "$MONGO_TAR"
    mv mongodb-linux-x86_64-ubuntu2204-${MONGO_VERSION} /usr/local/mongodb

    mkdir -p /data/mongodb/{data,logs,pid}

    # 安装命令
    cd /usr/local/src
    wget -O mongosh.tgz https://downloads.mongodb.com/compass/mongosh-2.2.5-linux-x64.tgz
    tar xf mongosh.tgz
    cp mongosh-2.2.5-linux-x64/bin/mongosh /usr/local/mongodb/bin/
    ln -sf /usr/local/mongodb/bin/mongosh /usr/bin/mongosh
    mongosh --version

    cat >/usr/local/mongodb/mongod.conf <<'EOF'
systemLog:
  destination: file
  logAppend: true
  path: /data/mongodb/logs/mongod.log

storage:
  dbPath: /data/mongodb/data
  wiredTiger:
    engineConfig:
      cacheSizeGB: 8
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

processManagement:
  fork: false

net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 10000

security:
  authorization: enabled

operationProfiling:
  mode: slowOp
  slowOpThresholdMs: 100
EOF

    cat >/etc/systemd/system/mongod.service <<'EOF'
[Unit]
Description=MongoDB
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/mongodb/bin/mongod --config /usr/local/mongodb/mongod.conf
Restart=always
RestartSec=5

LimitNOFILE=1048576
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now mongod

    sleep 5

    /usr/local/mongodb/bin/mongosh <<EOF
use admin
db.createUser({
  user: "root",
  pwd: "5bPoMu3tFdnrQQ90",
  roles: [{role: "root", db: "admin"}]
})
EOF

    echo "MongoDB 安装完成"
}

usage() {
    echo -e "用法: bash al2023-install.sh [command]

支持命令：
  install_base       -> 安装基础工具
  install_jdk17      -> 安装 JDK17
  install_jdk8       -> 安装 JDK8 到 /usr/local/java8
  install_nginxd     -> 安装标准 Nginx
  install_nginxall   -> 安装 JDK8/JDK17 + Nginx IM配置 + go-mmproxy
  install_mmproxy    -> 安装 go-mmproxy
  install_rds        -> 安装 Redis
  install_rds_es     -> 安装 Redis + Elasticsearch
  install_sql        -> MySQL 提示说明
  install_mongo      -> MongoDB 提示说明
"
}

main() {
    check_os

    case "${1:-}" in
        install_base)
            install_base_tools
            ;;
        install_jdk17)
            install_base_tools
            install_java17
            ;;
        install_jdk8)
            install_base_tools
            install_java8
            ;;
        install_nginxd)
            install_base_tools
            install_nginx
            ;;
        install_nginxall)
            install_base_tools
            install_java8
            install_im_bs_upload_jdk17
            install_nginxim
            install_go_mmproxy
            ;;
        install_mmproxy)
            install_base_tools
            install_go_mmproxy
            ;;
        install_rds)
            install_base_tools
            install_redis
            ;;
        install_rds_es)
            install_base_tools
            install_redis
            install_es
            ;;
        install_sql)
            install_mysql84_al2023
            ;;
        install_mongo)
            install_mongodb
            ;;
        *)
            usage
            exit 1
            ;;
    esac

    echo -e "\n\033[32m[$(date +'%H:%M:%S')] 执行完成\033[0m"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

main "$@"
