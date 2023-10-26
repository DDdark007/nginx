# 一、nginx部署
## 安装依赖
```bash
yum -y install gcc gcc-c++ automake pcre pcre-devel zlib zlib-devel openssl openssl-devel git
```
## 编译安装包
```bash
# 1.下载
cd /usr/local/src/
wget https://nginx.org/download/nginx-1.22.0.tar.gz
wget https://github.com/maxmind/libmaxminddb/releases/download/1.6.0/libmaxminddb-1.6.0.tar.gz
git clone https://github.com/leev/ngx_http_geoip2_module.git
git clone https://github.com/zhouchangxun/ngx_healthcheck_module.git
git clone https://github.com/DDdark007/GeoLite2.git
# 2.解压
tar xf libmaxminddb-1.6.0.tar.gz
tar xf nginx-1.22.0.tar.gz
# 3.安装 libmaxminddb
cd libmaxminddb-1.6.0
./configure
make
make install
ldconfig
sh -c "echo /usr/local/lib  >> /etc/ld.so.conf.d/local.conf"
ldconfig

# 4.安装nginx
cd ../nginx-1.22.0

# 以下有两种方法，选其中一种方法即可
# 5.1简易编译
./configure --with-http_ssl_module --with-stream --with-http_realip_module --http-client-body-temp-path=/tmp --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_stub_status_module --with-http_gzip_static_module --with-pcre --with-stream --with-stream_ssl_module --with-stream_realip_module --add-module=/usr/local/src/ngx_healthcheck_module --add-module=/usr/local/src/ngx_http_geoip2_module

make && make install

# 5.1.1 软连接
ln -s /usr/local/nginx/sbin/nginx /usr/bin/
mkdir /usr/local/nginx/{geoip,data}
mkdir /usr/local/nginx/conf/ssl

# 5.1.2 部署geoip2 ip数据库
mv /usr/local/src/GeoLite2/GeoLite2-Country.mmdb /usr/local/nginx/geoip/

mkdir -p /usr/local/nginx/conf/vhost/{web,default}
cd /usr/local/nginx/conf/vhost/default
wget https://raw.githubusercontent.com/DDdark007/nginx/main/default.conf

# 5.1.3 修改配置文件
cd /usr/local/nginx/conf/
mv /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bak
wget  https://raw.githubusercontent.com/DDdark007/nginx/main/nginx.conf

# 以下为第二种方法编译
# 5.2完美编译
./configure \
--prefix=/usr/local/nginx \
--sbin-path=/usr/local/nginx/sbin/nginx \
--conf-path=/usr/local/nginx/conf/nginx.conf \
--error-log-path=/usr/local/nginx/logs/error.log \
--http-log-path=/usr/local/nginx/logs/access.log \
--pid-path=/usr/local/nginx/logs/nginx.pid \
--lock-path=/usr/local/nginx/logs/nginx.lock \
--http-client-body-temp-path=/usr/local/nginx/cache/nginx/client_temp \
--http-proxy-temp-path=/usr/local/nginx/cache/nginx/proxy_temp \
--http-fastcgi-temp-path=/usr/local/nginx/cache/nginx/fastcgi_temp \
--http-uwsgi-temp-path=/usr/local/nginx/cache/nginx/uwsgi_temp \
--http-scgi-temp-path=/usr/local/nginx/cache/nginx/scgi_temp \
--with-http_ssl_module --with-stream --with-http_realip_module --http-client-body-temp-path=/tmp --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_stub_status_module --with-http_gzip_static_module --with-pcre --with-stream --with-stream_ssl_module --with-stream_realip_module --add-module=/usr/local/src/ngx_healthcheck_module --add-module=/usr/local/src/ngx_http_geoip2_module
```

## 编辑子配置文件(根据自行情况修改配置文件)
```bash
cat >> /usr/local/nginx/conf/vhost/web/web.conf << EOF
server {
    listen     80;
    server_name 20.205.56.98 20.205.124.60;
    charset utf-8;
    access_log logs/web.log access;

    location / {
    root /usr/local/nginx/data/web/dist;
    index index.html index.htm index.php pc.html;
    try_files $uri $uri/ /index.html;
    limit_rate 10M;
    proxy_set_header Host      $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#    if ($allowed_country = no) {
#      root /usr/local/nginx/data/limit403;
#    }
  }
}
EOF
```
## 简单反代配置
```bash
server {
    listen     80;
    server_name kefu.aipaykefu.com;
    location / {
        proxy_pass http://127.0.0.1:8035;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# 接口网关反向代理配置
cat >> /usr/local/nginx/conf/vhost/api/api.conf << EOF
upstream gamegw{
    server 20.205.56.98:80;
}

server {
    listen    80;
    #listen     443 ssl http2;
    server_name  20.205.124.60;
    access_log logs/api.log access;
    access_log  logs/api-json.log  json;
    client_max_body_size 200m;

    #ssl_certificate /usr/local/nginx/conf/ssl/xxx.com.crt;
    #ssl_certificate_key /usr/local/nginx/conf/ssl/xxx.com.key;


    location /{
    
        # http request header param
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $real_ip;
    
        # websocket request header param
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    
        # websocket xieyi
        proxy_http_version 1.1;
    
        # timeout
        proxy_connect_timeout 300;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    
        proxy_pass http://gamegw;
        proxy_next_upstream error timeout invalid_header http_503 http_504;
    }
   #if ($allowed_country = no) {
   #   return 403;
   # }
}
EOF

#添加开机自启
chmod +x /etc/rc.d/rc.local
echo nginx >> /etc/rc.local

#在server_name 处添加域名 不需要的域名删除
#没有添加域名在配置文件中 会403 配置文件在 /usr/local/nginx/conf/vhost/default/default.conf

#先以添加虚拟机目录为
/usr/local/nginx/conf/vhost/api
/usr/local/nginx/conf/vhost/web

#如还需添加请在 nginx.conf内添加一行配置文件
```
# 二、基操
## 用户认证
```bash
# 命令行
htpasswd -bc /usr/local/nginx/auth/passwd admin 123456

vim /usr/local/nginx/conf/vhost/www.conf 
server {  
        listen   80;   
        server_name www.com;     
        index  index.html index.htm; 
        root /www;   
location / { 
         auth_basic "test"; 
         auth_basic_user_file /usr/local/nginx/auth/passwd; 
} 
```
## 日志切割脚本
```bash
#!/bin/bash

#set the path to nginx log files
log_files_path="/usr/local/nginx/logs/"
log_files_dir=${log_files_path}$(date -d "yesterday" +"%Y")/$(date -d "yesterday" +"%m")
#set nginx log files you want to cut
log_files_name=(gamefile)
#set the path to nginx.
nginx_sbin="/usr/local/nginx/sbin/nginx"
#Set how long you want to save
save_days=10

############################################
#Please do not modify the following script #
############################################
mkdir -p $log_files_dir

log_files_num=${#log_files_name[@]}

#cut nginx log files
for((i=0;i<$log_files_num;i++));do
mv ${log_files_path}${log_files_name[i]}.log ${log_files_dir}/${log_files_name[i]}_$(date -d "yesterday" +"%Y%m%d").log
done

#delete 30 days ago nginx log files
find $log_files_path -mtime +$save_days -exec rm -rf {} \; 

$nginx_sbin -s reload
```
## nginx跨域解决
```bash
location / {
        # 跨域设置
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
        add_header 'Access-Control-Allow-Credentials' 'true'; 
        if ( $request_method = 'OPTIONS' ) { return 200; }
 }
```
## nginx 301跳转
```bash
#nginx if判断匹配
#如果访问时这个URL不是一下IP返回403
set $flag 0;
if ($document_uri ~ chuhzg19tvgabxmaslkdsalkdjl/login.html) {
    set $flag "${flag}1";
}
if ($remote_addr !~ ^(183.56.212.99|103.179.242.35|16.163.246.137)) {
    set $flag "${flag}2";
}
if ($flag = "012") {
   return 403;
}

# 空目录跳转首页
try_files $uri $uri/ /index.html;

# 匹配开头为xxx参数的URL和 以 yyy开头的url
if ($uri !~ (/Pay_.*\.html|/Public/*)) {
                return 403;
}

# 匹配url进行跳转
location ~ /benefit_detail {
    if ($args ~* "slug=bankofchina-20170320") {
            rewrite ^/benefit_detail /boc? permanent;
        }
    try_files $uri $uri/ /index.php?$query_string;
}

# 常见跳转事例
rewrite ^/connect$ http://connect.myweb.com permanent;
rewrite ^/connect/(.*)$ http://connect.myweb.com/$1 permanent;

# http跳转https
if ($scheme = http ) {
return 301 https://$host$request_uri;
}
```
## websocket服务的配置
```bash
# 例如
location /chat/ {
    proxy_pass http://backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```