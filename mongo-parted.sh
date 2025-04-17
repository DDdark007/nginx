# 创建GPT分区表并新建分区（非交互式parted操作）
parted /dev/nvme1n1 --script mklabel gpt
parted /dev/nvme1n1 --script mkpart primary ext4 0% 100%

# 格式化新分区（注意分区号）
mkfs.ext4 -F /dev/nvme1n1p1

# 创建挂载点
mkdir -p /data

# 获取UUID（等待设备识别）
sleep 2
UUID=$(blkid -s UUID -o value /dev/nvme1n1p1)

# 写入fstab（使用分区UUID）
echo "UUID=$UUID /data ext4 defaults 0 0" | tee -a /etc/fstab

# 挂载并验证
mount -a && df -Th /data
