#!/bin/bash
. /etc/rc.d/init.d/functions
#mysql
MYSQL_HOME=/data
MYSQL_PWD=oNzQsS4Has3GC6PL
MYSQL_PORT=32060
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
slave_parallel_workers = 16 #可以设置为逻辑CPU数量的2倍
innodb_thread_concurrency = 8
binlog_transaction_dependency_tracking = WRITESET
slave_preserve_commit_order = 1
slave_checkpoint_period = 2
replication_optimize_for_static_plugin_config = ON
replication_sender_observe_commit_only = ON

#innodb settings
transaction_isolation = READ-COMMITTED
innodb_buffer_pool_size = 6144M
innodb_buffer_pool_instances = 8
innodb_data_file_path = ibdata1:12M;ibdata2:1G:autoextend
innodb_flush_log_at_trx_commit = 2 #MGR环境中由其他节点提供容错性，可不设置双1以提高本地节点性能
innodb_log_buffer_size = 32M
innodb_log_file_size = 1G #如果线上环境的TPS较高，建议加大至1G以上，如果压力不大可以调小
innodb_log_files_in_group = 3
innodb_max_undo_log_size = 2G
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
innodb_online_alter_log_max_size = 2G
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
  # 检查命令执行状态
    if [ $? -ne 0 ]; then
        echo "启动MySQL服务失败，正在调用失败处理函数..."
        return          # 从当前函数返回，不再继续执行
    fi
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
install_mysql8_el7