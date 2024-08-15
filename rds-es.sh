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
install_redis
install_es