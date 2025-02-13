#!/bin/bash
. /etc/rc.d/init.d/functions
#mysql
MYSQL_PWD=oNzQsS4Has3GC6PL
mycnfid=1
function install_java8()
{
	echo -e "\033[33m***************************************************自动部署JDK-8**************************************************\033[0m"
	wget https://corretto.aws/downloads/latest/amazon-corretto-8-x64-linux-jdk.tar.gz
 	tar xf amazon-corretto-8-x64-linux-jdk.tar.gz -C /usr/local/
	mv /usr/local/amazon-corretto-8.432.06.1-linux-x64/ /usr/local/java
	cat >> /etc/profile <<EOF
JAVA_HOME=/usr/local/java
PATH=$PATH:$JAVA_HOME/bin
EOF
	source /etc/profile
	ln -s /usr/local/java/bin/* /usr/bin/
	which java
	java -version
}
function install_java11()
{
	echo -e "\033[33m***************************************************自动部署JDK-11**************************************************\033[0m"
	wget https://corretto.aws/downloads/resources/11.0.26.4.1/amazon-corretto-11.0.26.4.1-linux-x64.tar.gz
	tar xf amazon-corretto-11.0.26.4.1-linux-x64.tar.gz -C /usr/local/
	mv /usr/local/amazon-corretto-11.0.26.4.1-linux-x64 /usr/local/java
	cat >> /etc/profile <<EOF
JAVA_HOME=/usr/local/java
PATH=$PATH:$JAVA_HOME/bin
EOF
	source /etc/profile
	ln -s /usr/local/java/bin/* /usr/bin/
	which java
	java -version
}
function install_im_bs_upload_jdk17()
{
	echo -e "\033[33m***************************************************自动部署JDK-17**************************************************\033[0m"
	wget https://corretto.aws/downloads/latest/amazon-corretto-17-x64-linux-jdk.tar.gz
	tar xf amazon-corretto-17-x64-linux-jdk.tar.gz
	mv amazon-corretto-17.0.13.11.1-linux-x64 /usr/local/jdk17
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
	wget https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/default.conf
	
	#修改配置文件
	cd /usr/local/nginx/conf/
	mv /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bak
 	wget  https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/nginx.conf
 	cd /usr/local/nginx/conf/vhost/web/
 	wget https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/admin.conf
 	wget https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/down.conf
 	wget https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/gateway.conf
 	wget https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/web.conf
  
	#添加开机自启
	chmod +x /etc/rc.d/rc.local
	echo /usr/local/nginx/sbin/nginx >> /etc/rc.local

 	# 添加toa模块
  	uname -r
	yum install -y kernel-devel-`uname -r`
  cd /opt
	wget http://toa.hk.ufileos.com/linux_toa.tar.gz
	tar -zxvf linux_toa.tar.gz
	cd linux_toa
	make
	mv toa.ko /lib/modules/`uname -r`/kernel/net/netfilter/ipvs/toa.ko
	insmod /lib/modules/`uname -r`/kernel/net/netfilter/ipvs/toa.ko
	lsmod |grep toa
}
function install_im_go_mmproxy()
{
	echo -e "\033[33m***************************************************自动部署go-mmproxy**************************************************\033[0m"
	yum update -y
	amazon-linux-extras install epel -y
	yum install golang -y
	go install github.com/path-network/go-mmproxy@latest
	cp -r /root/go/bin/go-mmproxy /usr/bin/
cat >> /etc/systemd/system/go-mmproxy.service << EOF
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

systemctl start go-mmproxy.service
systemctl status go-mmproxy.service
systemctl enable go-mmproxy.service

netstat -tnlp | grep 39326
}
function install_mysql8_el7()
{

  echo ""
  echo -e "\033[33m***************************************************自动部署mysql8.0**************************************************\033[0m"
  #建用户及目录
  groupadd -r mysql && useradd -r -g mysql mysql -d /home/mysql -m
  mkdir -vp /data/datafile &&  mkdir -vp /data/log &&  mkdir -vp /data/backup
  chown -R mysql:mysql /data && chmod -R 755 /data

  #关闭selinux
  setenforce 0
  sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

  #下载包
  if [ -f /opt/mysql-8.2.0-1.el7.x86_64.rpm-bundle.tar ];then
      echo "*****存在mysql8安装包，无需下载*****"
  else
      ping -c 4 google.com >/dev/null 2>&1
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
if [ "$mycnfid" -eq 1 ]; then
    # 如果mycnfid等于1，使用配置文件1
    wget -O /etc/my.cnf https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/sql45g.conf
else
    # 如果mycnfid不等于1，使用配置文件2
    wget -O /etc/my.cnf https://raw.githubusercontent.com/DDdark007/nginx/refs/heads/main/allconf/sql6g.conf
fi

  #启动数据库
  systemctl start mysqld.service
  # 检查命令执行状态
    if [ $? -ne 0 ]; then
        echo "启动MySQL服务失败，正在调用失败处理函数..."
        return          # 从当前函数返回，不再继续执行
    fi
  systemctl enable mysqld.service
  sleep 3
  MYSQL_TEMP_PWD=$(grep "temporary password" /data/log/mysqld.log|cut -d "@" -f 2|awk '{print $2}')
  MYSQL_TEMP_PWD_old=0AQGW6sGTLx#
  #mysql 8密码策略validate_password_policy 变为validate_password.policy
  #MYSQL 8.0内新增加mysql_native_password函数，通过更改这个函数密码来进行远程连接
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_TEMP_PWD}" -e "alter user 'root'@'localhost' identified by '${MYSQL_TEMP_PWD_old}';" --connect-expired-password
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_TEMP_PWD_old}" -e "set global validate_password.policy=0" --connect-expired-password
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_TEMP_PWD_old}" -e "alter user 'root'@'localhost' identified by '${MYSQL_PWD}';"  --connect-expired-password
  mysql -hlocalhost  -P${MYSQL_PORT}  -uroot -p"${MYSQL_PWD}" -e "use mysql;select host,user from user;update user set host='%' where user='root';flush privileges;select host,user from user;"  --connect-expired-password
  echo -e "\033[33m************************************************完成mysql8.0数据库部署***********************************************\033[0m"
cat > /tmp/mysql8.log  << EOF
mysql安装目录：/data
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
echo "mongod --config /usr/local/mongodb/config/mongodb.conf" >> /etc/rc.local

# 启动 MongoDB 服务
    mongod --config /usr/local/mongodb/config/mongodb.conf

    # 等待一段时间，确保 MongoDB 启动完成
    sleep 5

    # 创建 root 用户
    echo "Creating root user..."
    mongosh --port 27017 <<EOF
    use admin
    db.createRole({
      role: "root",
      privileges: [],
      roles: ["root"]
    });
    db.createUser({
      user: "root",
      pwd: "5bPoMu3tFdnrQQ90",
      roles: [{role: "root", db: "admin"}]
    });
EOF
    echo "MongoDB root user created successfully."
}
function install_danji()
{
	install_java8
	install_im_bs_upload_jdk17
	install_nginx
	install_im_go_mmproxy
	install_mysql8_el7
	install_redis
	install_es
	install_mangodb

}
install_java8
#install_java11
install_im_bs_upload_jdk17
install_nginx
install_im_go_mmproxy
install_mysql8_el7
install_redis
install_es
install_mangodb
#install_danji
