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
      cacheSizeGB: 6   # 设置 WiredTiger 缓存大小为 4GB
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

# 启动 MongoDB 服务
    #mongod --config /usr/local/mongodb/config/mongodb.conf

    # 设置变量
MONGODB_CONF="/usr/local/mongodb/config/mongodb.conf"
SERVICE_FILE="/etc/systemd/system/mongod.service"
MONGODB_USER="mongodb"
MONGODB_GROUP="mongodb"

# 创建 Systemd 服务单元文件
echo "Creating MongoDB service file..."

cat <<EOF | sudo tee $SERVICE_FILE
[Unit]
Description=MongoDB Database Service
After=network.target

[Service]
User=$MONGODB_USER
Group=$MONGODB_GROUP
ExecStart=/usr/bin/mongod --config $MONGODB_CONF
PIDFile=/var/run/mongodb/mongod.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 设置 MongoDB 配置文件和相关目录的权限
echo "Setting permissions for MongoDB directories..."
sudo chown -R $MONGODB_USER:$MONGODB_GROUP /usr/local/mongodb/

# 重新加载 Systemd 配置
echo "Reloading Systemd daemon..."
sudo systemctl daemon-reload

# 启动并启用 MongoDB 服务
echo "Starting and enabling MongoDB service..."
sudo systemctl start mongod
sudo systemctl enable mongod

# 检查服务状态
echo "Checking MongoDB service status..."
sudo systemctl status mongod

echo "MongoDB has been configured to start on boot."


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
install_mangodb