#!/bin/bash
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_IF="wg0"
WG_CONF="${WG_DIR}/${WG_IF}.conf"
CLIENT_DIR="${WG_DIR}/clients"
STATE_FILE="${CLIENT_DIR}/clients.csv"
LOG_FILE="/var/log/wireguard-connections.log"
LOGGER_SCRIPT="/usr/local/sbin/wg-logger.sh"
LOGGER_SERVICE="/etc/systemd/system/wg-logger.service"
LOGROTATE_CONF="/etc/logrotate.d/wireguard-connection"

# ✅ 统一端口（你选择 443）
WG_PORT=443

###############################################
# 内核转发模块
###############################################
enable_ip_forward() {
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
    echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
    echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf
}

###############################################
# WireGuard VPN 专用 sysctl 优化（完整）
optimize_sysctl() {
cat > /etc/sysctl.d/99-wireguard-tuning.conf <<'EOF'
# =============================
# WireGuard VPN 系统优化
# =============================

# 1. 启用 IPv4 转发
net.ipv4.ip_forward = 1

# 2. 禁用 rp_filter（AWS 必须）
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

# 3. 提升队列长度（UDP/WG 非常重要）
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096

# 4. 提升 UDP buffer（WireGuard 高速传输优化）
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# 5. 提高 conntrack 限制（防止高并发 drop）
net.netfilter.nf_conntrack_max = 262144

# 6. 减少 TIME_WAIT 对系统的影响
net.ipv4.tcp_tw_reuse = 1

# 7. 禁止 ICMP redirect（安全强化）
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 8. BBR + FQ（如果系统支持）
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

sysctl --system >/dev/null 2>&1 || true
echo "✅ 已应用 WireGuard VPN sysctl 优化"
}

###############################################
# 获取出口网卡
###############################################
get_uplink_iface() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}'
}

###############################################
# 自动 MTU
###############################################
calc_mtu() {
    local dev="$1"
    local base=$(cat /sys/class/net/${dev}/mtu)
    local mtu=$(( base - 80 ))
    (( mtu < 1280 )) && mtu=1280
    echo "$mtu"
}

###############################################
# 自动 IP 分配
###############################################
next_free_ip() {
    used=$( { awk -F',' '{print $2}' "$STATE_FILE" 2>/dev/null || true; } | sed 's#/32##' )

    for i in $(seq 2 254); do
        ip="10.8.0.${i}"
        if ! echo "$used" | grep -qw "$ip"; then
            echo "$ip"
            return
        fi
    done
}

###############################################
# ✅ 安装日志系统（公网 IP 已修复解析）
###############################################
install_logger() {

cat > "$LOGGER_SCRIPT" <<'EOF'
#!/bin/bash
WG_IF="wg0"
LOG_FILE="/var/log/wireguard-connections.log"
STATE_FILE="/etc/wireguard/clients/clients.csv"

touch "$LOG_FILE"

while true; do
    now=$(date "+%Y-%m-%d %H:%M:%S")
    full=$(wg show "$WG_IF" | sed 's/\r//')

    while IFS=',' read -r name ip pub; do
        [[ -z "$name" ]] && continue

        # 匹配 peer 行
        peer_line=$(printf "%s\n" "$full" | grep -n "peer: $pub" | cut -d: -f1)

        if [[ -z "$peer_line" ]]; then
            echo "$now - USER: $name ($ip) - STATUS: disconnected" >> "$LOG_FILE"
            continue
        fi

        # 取 peer block
        block=$(printf "%s\n" "$full" | sed -n "${peer_line},/transfer/p")

        endpoint=$(printf "%s\n" "$block" | awk -F': ' '/endpoint:/ {print $2}')
        handshake=$(printf "%s\n" "$block" | awk -F': ' '/latest handshake/ {print $2}')
        transfer=$(printf "%s\n" "$block" | awk -F': ' '/transfer:/ {print $2}')

        if [[ -n "$handshake" ]]; then
            echo "$now - USER: $name ($ip) - ENDPOINT: $endpoint - HANDSHAKE: $handshake - TRAFFIC: $transfer" >> "$LOG_FILE"
        else
            echo "$now - USER: $name ($ip) - ENDPOINT: $endpoint - STATUS: no-handshake" >> "$LOG_FILE"
        fi

    done < "$STATE_FILE"

    sleep 10
done
EOF

chmod +x "$LOGGER_SCRIPT"

cat > "$LOGGER_SERVICE" <<EOF
[Unit]
Description=WireGuard Logger
After=network.target
[Service]
ExecStart=$LOGGER_SCRIPT
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wg-logger
systemctl restart wg-logger

cat > "$LOGROTATE_CONF" <<EOF
$LOG_FILE {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
}

###############################################
# ✅ 创建客户端配置
###############################################
create_client() {
    local name="$1"
    local ip="$2"

    PRIV=$(wg genkey)
    PUB=$(echo "$PRIV" | wg pubkey)
    SERVER_PUB=$(cat "$WG_DIR/server_public.key")
    SERVER_IP=$(curl -s ifconfig.me)

mkdir -p "$CLIENT_DIR/$name"

cat > "$CLIENT_DIR/$name/$name.conf" <<EOF
[Interface]
PrivateKey = $PRIV
Address = $ip/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    echo "$name,$ip,$PUB" >> "$STATE_FILE"

    wg set "$WG_IF" peer "$PUB" allowed-ips "$ip/32"

    echo ""
    echo "✅ 新客户端创建成功：$name"
    echo "📄 配置文件路径：$CLIENT_DIR/$name/$name.conf"
    echo "🌐 VPN IP：$ip"
    echo "🔌 端口：$WG_PORT（统一端口）"
    echo ""
    echo "📱 扫描二维码："
    qrencode -t UTF8 < "$CLIENT_DIR/$name/$name.conf"
    echo ""
}

###############################################
# ✅ 删除客户端
###############################################
remove_client() {
    read -rp "输入要删除的客户端：" name

    line=$(grep "^$name," "$STATE_FILE" || true)
    [[ -z "$line" ]] && { echo "❌ 未找到客户端：$name"; exit 1; }

    pub=$(echo "$line" | cut -d',' -f3)

    wg set wg0 peer "$pub" remove || true
    sed -i "/^$name,/d" "$STATE_FILE"
    rm -rf "$CLIENT_DIR/$name"

    echo "✅ 已成功删除客户端：$name"
    exit 0
}

###############################################
# ✅ 自动启用 BBR（安装时自动执行）
###############################################
enable_bbr() {
cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

sysctl --system >/dev/null 2>&1 || true
}

###############################################
# ✅ 安装 WireGuard（统一端口：443）
###############################################
install_wireguard() {
    optimize_sysctl
    amazon-linux-extras install -y epel
    yum install -y wireguard-tools wireguard-dkms qrencode

    mkdir -p "$CLIENT_DIR"
    touch "$STATE_FILE"

    enable_bbr

    SERVER_PRIV=$(wg genkey)
    SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)

    echo "$SERVER_PRIV" > "$WG_DIR/server_private.key"
    echo "$SERVER_PUB" > "$WG_DIR/server_public.key"

    UP_IF=$(get_uplink_iface)
    MTU=$(calc_mtu "$UP_IF")

cat > "$WG_CONF" <<EOF
[Interface]
Address = 10.8.0.1/24
PrivateKey = $SERVER_PRIV
MTU = $MTU
ListenPort = $WG_PORT
SaveConfig = true
EOF

    chmod 600 "$WG_CONF"

    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0

    # ✅ 默认客户端
    create_client "default" "10.8.0.2"

    enable_ip_forward
    install_logger
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -A FORWARD -o wg0 -j ACCEPT

    SERVER_IP=$(curl -s ifconfig.me)

    echo ""
    echo "✅✅✅ WireGuard 部署完成 ✅✅✅"
    echo ""
    echo "============ 服务器信息 ============"
    echo "🌐 公网 IP：$SERVER_IP"
    echo "🛜 出口网卡：$UP_IF"
    echo "📌 MTU：$MTU"
    echo "🔐 服务端公钥：$SERVER_PUB"
    echo "🎯 监听端口：$WG_PORT（统一端口）"
    echo "⚡ 已启用加速：BBR + FQ"
    echo ""
    echo "============ 默认客户端信息 ============"
    echo "📄 配置文件路径：/etc/wireguard/clients/default/default.conf"
    echo "🔌 使用端口：$WG_PORT"
    qrencode -t UTF8 < /etc/wireguard/clients/default/default.conf
    echo ""
    echo "============ 日志系统 =============="
    echo "📁 日志文件：$LOG_FILE"
    echo "🔄 自动切割：/etc/logrotate.d/wireguard-connection"
    echo "📡 日志服务：wg-logger（公网 IP 解析版）"
    echo ""
    exit 0
}

###############################################
# ✅ 添加客户端（执行完直接退出）
###############################################
add_client() {
    read -rp "输入客户端名称：" name
    ip=$(next_free_ip)
    create_client "$name" "$ip"
    exit 0
}

# 卸载
uninstall_wireguard() {
    echo "🟡 正在卸载 WireGuard 整个程序…"

    # 停止日志服务
    systemctl stop wg-logger 2>/dev/null || true
    systemctl disable wg-logger 2>/dev/null || true
    rm -f /etc/systemd/system/wg-logger.service
    rm -f /usr/local/sbin/wg-logger.sh
    rm -f /etc/logrotate.d/wireguard-connection

    # 停止 WireGuard 接口
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl disable wg-quick@wg0 2>/dev/null || true

    # 删除 WireGuard 配置目录
    rm -rf /etc/wireguard

    # 删除日志
    rm -f /var/log/wireguard-connections.log

    # 卸载 WireGuard 程序包
    yum remove -y wireguard-tools wireguard-dkms 2>/dev/null || true

    # 强制删除 wg0 接口（如果还存在）
    ip link del wg0 2>/dev/null || true

    echo ""
    echo "✅✅✅ WireGuard 已完全卸载 ✅✅✅"
    echo "✅ 所有客户端（default/wg1/...）已删除"
    echo "✅ 所有密钥已删除"
    echo "✅ 所有日志 + logger 服务已删除"
    echo "✅ WireGuard 程序已从系统移除"
    echo "✅ 不会残留任何配置文件"
    echo ""
    echo "系统已恢复到未安装 WireGuard 的状态。"
    echo ""
    exit 0
}

###############################################
# ✅ 菜单
###############################################
menu() {
    echo "=========== WireGuard VPS 管理 =========="
    echo "1) 安装 WireGuard（端口 443）"
    echo "2) 添加客户端"
    echo "3) 删除客户端（删除单个 peer）"
    echo "4) 卸载 WireGuard（整个程序 + 全部配置）"
    echo "0) 退出"
    echo "==========================================="
    read -rp "选择：" c

    case "$c" in
        1) install_wireguard ;;
        2) add_client ;;
        3) remove_client ;;         # 删除单个账号
        4) uninstall_wireguard ;;   # ✅ 完整卸载整个 WG 程序
        0) exit 0 ;;
        *) echo "无效选项"; exit 1 ;;
    esac
}

menu
