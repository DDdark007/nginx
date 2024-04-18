#!/bin/bash
. /etc/rc.d/init.d/functions
#mysql
MYSQL_HOME=/data
MYSQL_PWD=Top123456
MYSQL_PORT=32060
function install_java8()
{
	echo -e "\033[33m***************************************************自动部署JDK-8**************************************************\033[0m"
	wget --no-check-certificate --no-cookies --header "Cookie: oraclelicense=accept-securebackup-cookie"  http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.tar.gz
	tar xf jdk-8u131-linux-x64.tar.gz -C /usr/local/
	mv /usr/local/jdk1.8.0_131/ /usr/local/java
	cat >> /etc/profile <<EOF
JAVA_HOME=/usr/local/java
PATH=$PATH:$JAVA_HOME/bin
EOF
	source /etc/profile
	ln -s /usr/local/java/bin/java /usr/bin/
	which java
	java -version
}
function install_java11()
{
	echo -e "\033[33m***************************************************自动部署JDK-11**************************************************\033[0m"
	wget https://corretto.aws/downloads/latest/amazon-corretto-11-x64-linux-jdk.tar.gz
	tar xf amazon-corretto-11-x64-linux-jdk.tar.gz -C /usr/local/
	mv /usr/local/amazon-corretto-11.0.18.10.1-linux-x64 /usr/local/java
	cat >> /etc/profile <<EOF
JAVA_HOME=/usr/local/java
PATH=$PATH:$JAVA_HOME/bin
EOF
	source /etc/profile
	ln -s /usr/local/java/bin/java /usr/bin/
	which java
	java -version
}
# nginx
function install_nginx()
{
	echo -e "\033[33m***************************************************自动部署nginx-1.22.0**************************************************\033[0m"
	#安装依赖
	yum -y install wget gcc gcc-c++ automake pcre pcre-devel zlib zlib-devel openssl openssl-devel git

	#下载需要编译安装的包
	cd /usr/local/src/
	wget https://nginx.org/download/nginx-1.22.0.tar.gz
	wget https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz
	git clone https://github.com/leev/ngx_http_geoip2_module.git
	git clone https://github.com/zhouchangxun/ngx_healthcheck_module.git
	git clone https://github.com/DDdark007/GeoLite2.git

	#解压
	tar xf libmaxminddb-1.6.0.tar.gz
	tar xf nginx-1.22.0.tar.gz
	 
	#安装 libmaxminddb
	cd libmaxminddb-1.6.0
	./configure
	make
	make install
	ldconfig
	sh -c "echo /usr/local/lib  >> /etc/ld.so.conf.d/local.conf"
	ldconfig
	 
	#安装nginx
	cd ../nginx-1.22.0
	# 简易编译
	./configure --with-http_ssl_module --with-stream --with-http_realip_module --http-client-body-temp-path=/tmp --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_stub_status_module --with-http_gzip_static_module --with-pcre --with-stream --with-stream_ssl_module --with-stream_realip_module --add-module=/usr/local/src/ngx_healthcheck_module --add-module=/usr/local/src/ngx_http_geoip2_module
	make && make install

	#软连接
	ln -s /usr/local/nginx/sbin/nginx /usr/bin/
	mkdir -vp /usr/local/nginx/{geoip,data/{tio-bs-page,tio-download,tio-mg-page}}
	mkdir -v /usr/local/nginx/conf/ssl
	mkdir -v /home/upload/

	#部署geoip2 ip数据库
	mv /usr/local/src/GeoLite2/* /usr/local/nginx/geoip/
	
	mkdir -p /usr/local/nginx/conf/vhost/{web,default}
	cd /usr/local/nginx/conf/vhost/default
	wget https://raw.githubusercontent.com/DDdark007/nginx/main/default.conf
	
	#修改配置文件
	cd /usr/local/nginx/conf/
	mv /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bak
 	wget  https://raw.githubusercontent.com/DDdark007/nginx/main/nginx.conf
  
	#添加开机自启
	chmod +x /etc/rc.d/rc.local
	echo nginx >> /etc/rc.local
	echo -e "\e[1;31m 自行上传tio-nginx-conf.tar.gz文件 \e[0m"
}

function install_mysql8_el7()
{

  echo ""
  echo -e "\033[33m***************************************************自动部署mysql8.0**************************************************\033[0m"
  #建用户及目录
  groupadd -r mysql && useradd -r -g mysql mysql -d /home/mysql -m
  mkdir -vp $MYSQL_HOME/datafile &&  mkdir -vp $MYSQL_HOME/log &&  mkdir -vp $MYSQL_HOME/backup
  chown -R mysql:mysql $MYSQL_HOME && chmod -R 755 $MYSQL_HOME

  #关闭selinux
  setenforce 0
  sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

  #下载包
  if [ -f /opt/mysql-8.2.0-1.el7.x86_64.rpm-bundle.tar ];then
      echo "*****存在mysql8安装包，无需下载*****"
  else
      ping -c 4 app.fslgz.com >/dev/null 2>&1
      if [ $? -eq 0 ];then
  wget https://downloads.mysql.com/archives/get/p/23/file/mysql-8.2.0-1.el7.x86_64.rpm-bundle.tar -P /opt/
      else
        echo "please download mysql8 package manual !"
    exit $?
      fi
  fi

  #配yum安装mysql依赖包
  rpm -qa|grep libaio-devel
  if [ $? -eq 1 ];then
    yum install -y gcc gcc-c++ openssl openssl-devel libaio libaio-devel  ncurses  ncurses-devel &>/dev/null
    action "***************安装mysql依赖包完成***************" /bin/true
    else
      action "****************已安装mysql依赖包****************" /bin/false
  fi

  #安装mysql8.0
  ps -ef|grep mysqld |grep -v grep | grep root
  if [ $? -eq 0 ] ;then
     echo "*****************已存在mysql进程*****************"
     exit $?
  else
   # 卸载 mysql
     rpm -qa|grep mysql|xargs -i rpm -e --nodeps {}
     # uninstall mariadb-libs
     rpm -qa|grep mariadb|xargs -i rpm -e --nodeps {}
     # 安装mysql
     action "***************开始安装mysql数据库***************" /bin/true
     cd /opt
     tar -xvf mysql-8.2.0-1.el7.x86_64.rpm-bundle.tar -C /opt/  &>/dev/null
     yum install *.rpm -y
     cd /root/
  fi

  #配置my.cnf
  cp /etc/my.cnf /etc/my.cnf_${DATE}bak &>/dev/null
cat << EOF > /etc/my.cnf
[client]
port	= ${MYSQL_PORT}

[mysql]
prompt = "\u@mysqldb \R:\m:\s [\d]> "
no_auto_rehash
loose-skip-binary-as-hex

[mysqld]
user	= mysql
port	= ${MYSQL_PORT}
bind_address=0.0.0.0
lower_case_table_names=1
skip-name-resolve
sql_mode=STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
#主从复制或MGR集群中，server_id记得要不同
#另外，实例启动时会生成 auto.cnf，里面的 server_uuid 值也要不同
#server_uuid的值还可以自己手动指定，只要符合uuid的格式标准就可以
server_id = 3306
datadir	= ${MYSQL_HOME}/datafile
character_set_server = UTF8MB4
skip_name_resolve = 1
#若你的MySQL数据库主要运行在境外，请务必根据实际情况调整本参数
default_time_zone = "+8:00"
#启用admin_port，连接数爆满等紧急情况下给管理员留个后门
admin_address = '127.0.0.1'
admin_port = 33062

default_authentication_plugin=mysql_native_password
#performance setttings
lock_wait_timeout = 3600
open_files_limit    = 65535
back_log = 1024
max_connections = 1000
max_connect_errors = 1000000
table_open_cache = 1024
table_definition_cache = 1024
thread_stack = 512K
sort_buffer_size = 16M
join_buffer_size = 8M
read_buffer_size = 8M
read_rnd_buffer_size = 16M
bulk_insert_buffer_size = 64M
thread_cache_size = 768
interactive_timeout = 36000
wait_timeout = 36000
tmp_table_size = 64M
max_heap_table_size = 128M

#log settings
log_timestamps = SYSTEM
log_output=table,File
log_error = ${MYSQL_HOME}/log/mysqld.log
log_error_verbosity = 3
slow_query_log = 1
log_slow_extra = 1
slow_query_log_file = ${MYSQL_HOME}/log/slow.log
long_query_time = 10
log_queries_not_using_indexes = 1
log_throttle_queries_not_using_indexes = 60
min_examined_row_limit = 100
log_slow_admin_statements = 1
log_slow_slave_statements = 1
log_bin = ${MYSQL_HOME}/log/mysql-bin.log
binlog_format = ROW
sync_binlog = 0 #MGR环境中由其他节点提供容错性，可不设置双1以提高本地节点性能
binlog_cache_size = 4M
max_binlog_cache_size = 2G
max_binlog_size = 1G
binlog_rows_query_log_events = 1
binlog_expire_logs_seconds = 604800
#MySQL 8.0.22前，想启用MGR的话，需要设置binlog_checksum=NONE才行
binlog_checksum = none
gtid_mode = OFF
enforce_gtid_consistency = OFF

#myisam settings
key_buffer_size = 512M
myisam_sort_buffer_size = 64M

#replication settings
relay_log_recovery = 1
slave_parallel_type = LOGICAL_CLOCK
slave_parallel_workers = 32 #可以设置为逻辑CPU数量的2倍
innodb_thread_concurrency = 16
binlog_transaction_dependency_tracking = WRITESET
slave_preserve_commit_order = 1
slave_checkpoint_period = 2
replication_optimize_for_static_plugin_config = ON
replication_sender_observe_commit_only = ON

#innodb settings
transaction_isolation = READ-COMMITTED
innodb_buffer_pool_size = 22528M
innodb_buffer_pool_instances = 8
innodb_data_file_path = ibdata1:12M;ibdata2:1G:autoextend
innodb_flush_log_at_trx_commit = 2 #MGR环境中由其他节点提供容错性，可不设置双1以提高本地节点性能
innodb_log_buffer_size = 32M
innodb_log_file_size = 1G #如果线上环境的TPS较高，建议加大至1G以上，如果压力不大可以调小
innodb_log_files_in_group = 3
innodb_max_undo_log_size = 4G
# 根据您的服务器IOPS能力适当调整
# 一般配普通SSD盘的话，可以调整到 10000 - 20000
# 配置高端PCIe SSD卡的话，则可以调整的更高，比如 50000 - 80000
innodb_io_capacity = 10000
innodb_io_capacity_max = 20000
innodb_open_files = 65535
innodb_flush_method = O_DIRECT
innodb_lru_scan_depth = 4000
innodb_lock_wait_timeout = 10
innodb_rollback_on_timeout = 1
innodb_print_all_deadlocks = 1
innodb_online_alter_log_max_size = 4G
innodb_print_ddl_logs = 1
innodb_status_file = 1
#注意: 开启 innodb_status_output & innodb_status_output_locks 后, 可能会导致log_error文件增长较快
innodb_status_output = 0
innodb_status_output_locks = 1
innodb_sort_buffer_size = 67108864
innodb_adaptive_hash_index = OFF
#提高索引统计信息精确度
innodb_stats_persistent_sample_pages = 500

#innodb monitor settings
innodb_monitor_enable = "module_innodb"
innodb_monitor_enable = "module_server"
innodb_monitor_enable = "module_dml"
innodb_monitor_enable = "module_ddl"
innodb_monitor_enable = "module_trx"
innodb_monitor_enable = "module_os"
innodb_monitor_enable = "module_purge"
innodb_monitor_enable = "module_log"
innodb_monitor_enable = "module_lock"
innodb_monitor_enable = "module_buffer"
innodb_monitor_enable = "module_index"
innodb_monitor_enable = "module_ibuf_system"
innodb_monitor_enable = "module_buffer_page"
#innodb_monitor_enable = "module_adaptive_hash"

#pfs settings
performance_schema = 1
#performance_schema_instrument = '%memory%=on'
loose-performance_schema_instrument = '%lock%=on'
skip_ssl

[mysqldump]
quick
EOF

  #启动数据库
  systemctl start mysqld.service
  systemctl enable mysqld.service
  sleep 3
  MYSQL_TEMP_PWD=$(grep "temporary password" ${MYSQL_HOME}/log/mysqld.log|cut -d "@" -f 2|awk '{print $2}')
  MYSQL_TEMP_PWD_old=0AQGW6sGTLx#
  #mysql 8密码策略validate_password_policy 变为validate_password.policy
  #MYSQL 8.0内新增加mysql_native_password函数，通过更改这个函数密码来进行远程连接
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_TEMP_PWD}" -e "alter user 'root'@'localhost' identified by '${MYSQL_TEMP_PWD_old}';" --connect-expired-password
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_TEMP_PWD_old}" -e "set global validate_password.policy=0" --connect-expired-password
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_TEMP_PWD_old}" -e "alter user 'root'@'localhost' identified by '${MYSQL_PWD}';"  --connect-expired-password
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_PWD}" -e "use mysql;select host,user from user;update user set host='%' where user='root';flush privileges;select host,user from user;"  --connect-expired-password
  echo -e "\033[33m************************************************完成mysql8.0数据库部署***********************************************\033[0m"
cat > /tmp/mysql8.log  << EOF
mysql安装目录：${MYSQL_HOME}
mysql版本：Mysql-8.0
mysql端口：${MYSQL_PORT}
mysql密码：${MYSQL_PWD}
EOF
  cat /tmp/mysql8.log
  echo -e "\e[1;31m 以上信息保存在/tmp/mysql8.log文件下 \e[0m"
  echo -e "\033[33m*********************************************************************************************************************\033[0m"
  echo ""
  sleep 3
}
function install_redis()
{
	# 安装依赖
	yum -y install wget gcc gcc-c++ automake pcre pcre-devel zlib zlib-devel openssl openssl-devel git

	cd

	# 下载redis编译包
	wget http://download.redis.io/releases/redis-6.2.6.tar.gz

	# 解压
	tar xf redis-6.2.6.tar.gz
	cd redis-6.2.6

	# 编译
	make && make PREFIX=/usr/local/redis install
	mkdir /usr/local/redis/{data,conf,log} -p
	cd /usr/local/redis/conf
	wget https://raw.githubusercontent.com/DDdark007/redis_conf/main/redis.conf

	ln -s /usr/local/redis/bin/redis-server /usr/bin/
	ln -s /usr/local/redis/bin/redis-cli /usr/bin/

	# 启动
	redis-server /usr/local/redis/conf/redis.conf
	echo "redis-server /usr/local/redis/conf/redis.conf" >> /etc/rc.local
	echo -e "\033[33m************************************************完成redis6.2数据库部署***********************************************\033[0m"
	echo "redis密码"
	cat -n /usr/local/redis/conf/redis.conf | grep requirepass | grep -Ev "#"
	echo -e "\033[33m*******************************************************************************************************************\033[0m"
}
function install_es()
{
	cd
	wget https://artifacts.elastic.co/downloads/kibana/kibana-8.6.2-x86_64.rpm
	wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.6.2-x86_64.rpm
	yum install elasticsearch-8.6.2-x86_64.rpm -y
	yum install kibana-8.6.2-x86_64.rpm -y
	mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.ymlbak
	cd /etc/elasticsearch/
	wget https://raw.githubusercontent.com/DDdark007/redis_conf/main/elasticsearch.yml
	cd /etc/kibana
	mv kibana.yml kibana.ymlbak
	wget https://raw.githubusercontent.com/DDdark007/redis_conf/main/kibana.yml
	systemctl start kibana elasticsearch
	systemctl enable kibana elasticsearch
	curl -XGET 'http://localhost:9200/_cluster/health?pretty'
}
function install_mangodb()
{
	# 下载并解压 MongoDB
wget https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-rhel70-7.0.1.tgz
tar xf mongodb-linux-x86_64-rhel70-7.0.1.tgz
mv mongodb-linux-x86_64-rhel70-7.0.1 /usr/local/mongodb

# 创建配置和数据目录
mkdir -p /usr/local/mongodb/config /data/mongodb/{logs,data,pid}
cat << EOF > /usr/local/mongodb/config/mongodb.conf
storage:
  dbPath: /data/mongodb/data

# 设置 MongoDB 实例的最大内存限制（以 GB 为单位）
systemLog:
  destination: file
  logAppend: true
  path: /data/mongodb/logs/mongodb.log

processManagement:
  fork: true
  pidFilePath: /data/mongodb/pid/mongodb.pid  # 指定 PID 文件路径

# 配置 WiredTiger 存储引擎
storage:
  engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 16   # 设置 WiredTiger 缓存大小为 4GB
    collectionConfig:
      blockCompressor: snappy  # 使用 Snappy 压缩算法
# 安全配置（可选）
security:
  authorization: enabled
net:
  port: 27017
  bindIp: 0.0.0.0
  maxIncomingConnections: 10000
EOF

# 配置环境变量
echo "export MONGODB_HOME=/usr/local/mongodb" >> /etc/profile
echo "export PATH=\${MONGODB_HOME}/bin:\$PATH" >> /etc/profile

# 下载命令行界面命令
wget https://downloads.mongodb.com/compass/mongosh-1.6.0-linux-x64.tgz
tar xf mongosh-1.6.0-linux-x64.tgz
cp -r mongosh-1.6.0-linux-x64/bin/mongosh /usr/local/mongodb/bin/
source /etc/profile

# 启动
mongod --config /usr/local/mongodb/config/mongodb.conf
}
install_java8
#install_java11
install_nginx
install_mysql8_el7
install_redis
install_es
install_mangodb
