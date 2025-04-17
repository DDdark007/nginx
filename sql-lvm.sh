# 检查有几个卷
fdisk -l
# 1、安装LVM工具
yum install install lvm2 -y

# 2、创建物理卷
sudo pvcreate /dev/nvme1n1
sudo pvcreate /dev/nvme2n1

# 3、创建一个新的卷组，包含这两个物理卷，这里data-vg是卷组的名字
sudo vgcreate data-vg /dev/nvme1n1 /dev/nvme2n1

# 4、在刚创建的卷组上创建一个逻辑卷 data-lv是逻辑卷的名称
sudo lvcreate -l 100%VG -n data-lv data-vg

# 5、在逻辑卷上创建一个文件系统，例如使用ext4
sudo mkfs.ext4 /dev/data-vg/data-lv

# 6、挂载逻辑卷到目标目录
sudo mkdir -p /data
sudo mount /dev/data-vg/data-lv /data

# 7、自动挂载配置
echo "/dev/data-vg/data-lv /data ext4 defaults 0 0" >> /etc/fstab
df -h
