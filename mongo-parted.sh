#!/bin/bash
set -euo pipefail

DEVICE="/dev/nvme1n1"
MOUNT_POINT="/data"

echo ">>> 检查设备是否存在: $DEVICE"
if [ ! -b "$DEVICE" ]; then
    echo "ERROR: 设备 $DEVICE 不存在，退出。"
    exit 1
fi

echo ">>> 检查是否为系统盘"
ROOT_DISK=$(lsblk -no PKNAME $(df / | tail -1 | awk '{print $1}'))
if [[ "$ROOT_DISK" == "$(basename $DEVICE)" ]]; then
    echo "ERROR: $DEVICE 是系统盘！禁止初始化。"
    exit 1
fi

echo ">>> 创建挂载目录（如果不存在）: $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

PARTITION="${DEVICE}p1"

echo ">>> 检查分区是否已存在: $PARTITION"
if [ ! -b "$PARTITION" ]; then
    echo ">>> 创建 GPT 分区表 + 分区"
    parted "$DEVICE" --script mklabel gpt
    parted "$DEVICE" --script mkpart primary ext4 1MiB 100%
    partprobe "$DEVICE"
    sleep 2
else
    echo ">>> 已存在分区，跳过创建步骤。"
fi

echo ">>> 检查分区是否已格式化"
FSTYPE=$(blkid -o value -s TYPE "$PARTITION" || true)
if [ -z "$FSTYPE" ]; then
    echo ">>> 分区未格式化，执行 mkfs.ext4"
    mkfs.ext4 -F "$PARTITION"
else
    echo ">>> 分区已格式化为 $FSTYPE，跳过 mkfs"
fi

echo ">>> 获取 UUID"
UUID=$(blkid -s UUID -o value "$PARTITION")

echo ">>> 写入 /etc/fstab（若不存在）"
FSTAB_ENTRY="UUID=${UUID} ${MOUNT_POINT} ext4 defaults,nofail,x-systemd.device-timeout=10s 0 2"

if grep -q "$UUID" /etc/fstab; then
    echo ">>> fstab 中已存在此 UUID，跳过写入"
else
    echo "$FSTAB_ENTRY" >> /etc/fstab
    echo ">>> 已追加到 /etc/fstab"
fi

echo ">>> 挂载所有文件系统"
mount -a

echo ">>> 确认挂载结果:"
df -Th "$MOUNT_POINT"

echo ">>> 完成"
