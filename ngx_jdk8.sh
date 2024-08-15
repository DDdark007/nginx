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
	ln -s /usr/local/java/bin/* /usr/bin/
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
 	cd /usr/local/nginx/conf/vhost/web/
 	wget https://raw.githubusercontent.com/DDdark007/nginx/main/admin.conf
 	wget https://raw.githubusercontent.com/DDdark007/nginx/main/down.conf
 	wget https://raw.githubusercontent.com/DDdark007/nginx/main/gateway.conf
 	wget https://raw.githubusercontent.com/DDdark007/nginx/main/web.conf
  
	#添加开机自启
	chmod +x /etc/rc.d/rc.local
	echo nginx >> /etc/rc.local

 	# 添加toa模块
  	uname -r
	yum install -y kernel-devel-`uname -r`

	wget http://toa.hk.ufileos.com/linux_toa.tar.gz
	tar -zxvf linux_toa.tar.gz
	cd linux_toa
	make
	mv toa.ko /lib/modules/`uname -r`/kernel/net/netfilter/ipvs/toa.ko
	insmod /lib/modules/`uname -r`/kernel/net/netfilter/ipvs/toa.ko
	lsmod |grep toa
}
install_java8
install_nginx