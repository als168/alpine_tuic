#!/bin/sh
set -e

TUIC_BIN="/usr/local/bin/tuic"
CERT_DIR="/etc/tuic"
CONFIG_FILE="$CERT_DIR/config.json"
SERVICE_FILE="/etc/init.d/tuic"

# ===== 管理菜单 =====
if [ -x "$TUIC_BIN" ]; then
  echo "---------------------------------------"
  echo " 检测到已安装 TUIC v5"
  echo "---------------------------------------"
  echo "请选择操作:"
  echo "1) 修改端口"
  echo "2) 卸载 TUIC"
  echo "3) 退出"
  read -p "请输入选项 [1-3]: " choice

  case "$choice" in
    1)
      read -p "请输入新的端口号: " NEW_PORT
      [ -z "$NEW_PORT" ] && echo "❌ 端口不能为空" && exit 1
      sed -i "s/\"server\": \".*\"/\"server\": \"[::]:$NEW_PORT\"/" "$CONFIG_FILE"
      echo "端口已修改为 $NEW_PORT"
      rc-service tuic restart
      echo "✅ TUIC 已重启"
      exit 0
      ;;
    2)
      echo "正在卸载 TUIC..."
      rc-service tuic stop || true
      rc-update del tuic default || true
      rm -f "$TUIC_BIN" "$SERVICE_FILE"
      rm -rf "$CERT_DIR"
      echo "✅ TUIC 已卸载完成"
      exit 0
      ;;
    3) echo "已退出"; exit 0 ;;
    *) echo "无效选项"; exit 1 ;;
  esac
fi

# ===== 安装流程 =====
echo "---------------------------------------"
echo " TUIC v5 Alpine Linux 安装脚本 "
echo "---------------------------------------"

apk add --no-cache wget curl openssl openrc lsof coreutils jq file >/dev/null
apk add --no-cache aria2 >/dev/null || true

# ===== 下载 TUIC 二进制 =====
TAG=$(curl -s https://api.github.com/repos/tuic-protocol/tuic/releases/latest | jq -r .tag_name)
[ -z "$TAG" ] || [ "$TAG" = "null" ] && TAG="tuic-server-1.0.0"
VERSION=${TAG#tuic-server-}
FILENAME="tuic-server-${VERSION}-x86_64-unknown-linux-musl"

URLS="
https://github.com/tuic-protocol/tuic/releases/download/$TAG/$FILENAME
https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/$TAG/$FILENAME
"

SUCCESS=0
for url in $URLS; do
  echo "尝试下载: $url"
  rm -f /tmp/tuic_temp*
  wget --timeout=30 --tries=3 -O /tmp/tuic_temp "$url" || continue
  FILE_TYPE=$(file /tmp/tuic_temp)
  if echo "$FILE_TYPE" | grep -q "ELF"; then
    mv /tmp/tuic_temp $TUIC_BIN
    chmod +x $TUIC_BIN
    SUCCESS=1
    break
  fi
done
[ $SUCCESS -eq 0 ] && echo "❌ 下载失败" && exit 1

# ===== 证书处理 =====
mkdir -p $CERT_DIR
read -p "请输入证书 (.crt) 文件绝对路径 (回车则生成自签证书): " CERT_PATH
if [ -z "$CERT_PATH" ]; then
  read -p "请输入伪装域名 (默认 www.bing.com): " FAKE_DOMAIN
  [ -z "$FAKE_DOMAIN" ] && FAKE_DOMAIN="www.bing.com"
  openssl req -x509 -newkey rsa:2048 -nodes -keyout $CERT_DIR/key.pem -out $CERT_DIR/cert.pem -days 365 \
    -subj "/CN=$FAKE_DOMAIN"
  CERT_PATH="$CERT_DIR/cert.pem"
  KEY_PATH="$CERT_DIR/key.pem"
else
  read -p "请输入私钥 (.key) 文件绝对路径: " KEY_PATH
  read -p "请输入证书域名 (SNI): " FAKE_DOMAIN
fi

# ===== 生成配置 =====
UUID=$(cat /proc/sys/kernel/random/uuid)
PASS=$(openssl rand -base64 16)
[ -z "$FAKE_DOMAIN" ] && FAKE_DOMAIN="www.bing.com"

read -p "请输入 TUIC 端口 (默认 28543): " PORT
[ -z "$PORT" ] && PORT=28543

# ===== 拥塞算法选择 =====
echo "请选择拥塞控制算法:"
echo "1) bbr (推荐: 丢包多/跨境线路)"
echo "2) cubic (推荐: 稳定小鸡/低丢包环境)"
read -p "请输入选项 [1-2] (默认 1): " CC_CHOICE
case "$CC_CHOICE" in
  2) CC_ALGO="cubic" ;;
  *) CC_ALGO="bbr" ;;
esac
echo "已选择拥塞算法: $CC_ALGO"

cat > $CONFIG_FILE <<EOF
{
  "server": "[::]:$PORT",
  "users": {
    "$UUID": "$PASS"
  },
  "certificate": "$CERT_PATH",
  "private_key": "$KEY_PATH",
  "alpn": ["h3"],
  "congestion_control": "$CC_ALGO"
}
EOF

# ===== OpenRC 服务 =====
cat > $SERVICE_FILE <<'EOF'
#!/sbin/openrc-run
description="TUIC v5 Service"
command="/usr/local/bin/tuic"
command_args="--config /etc/tuic/config.json"
command_background="yes"
pidfile="/run/tuic.pid"
depend() { need net; }
EOF

chmod +x $SERVICE_FILE
rc-update add tuic default
rc-service tuic restart

# ===== 获取公网 IP =====
IPV4=$(wget -qO- -T 5 ipv4.icanhazip.com)
IPV6=$(wget -qO- -T 5 ipv6.icanhazip.com)
[ -n "$IPV6" ] && IP6_URI="[$IPV6]"

# ===== URI 编码 =====
ENC_PASS=$(printf '%s' "$PASS" | jq -s -R -r @uri)
ENC_SNI=$(printf '%s' "$FAKE_DOMAIN" | jq -s -R -r @uri)

# ===== 输出单节点链接（带算法参数） =====
LINK_FILE="$CERT_DIR/tuic-links.txt"
echo "------------------------------------------------------------------------"
echo "UUID: $UUID"
echo "密码: $PASS"
echo "SNI: $FAKE_DOMAIN"
echo "端口: $PORT"
echo "拥塞算法: $CC_ALGO"
{
  echo "UUID: $UUID"
  echo "密码: $PASS"
  echo "SNI: $FAKE_DOMAIN"
  echo "端口: $PORT"
  echo "拥塞算法: $CC_ALGO"
} > $LINK_FILE

if [ -n "$IPV4" ]; then
  LINK4="tuic://$UUID:$ENC_PASS@$IPV4:$PORT?sni=$ENC_SNI&alpn=h3&congestion_control=$CC_ALGO#TUIC-IPv4-$CC_ALGO"
  echo "单节点链接 (IPv4): $LINK4"
  echo "$LINK4" >> $LINK_FILE
fi

if [ -n "$IPV6" ]; then
  LINK6="tuic://$UUID:$ENC_PASS@$IP6_URI:$PORT?sni=$ENC_SNI&alpn=h3&congestion_control=$CC_ALGO#TUIC-IPv6-$CC_ALGO"
  echo "单节点链接 (IPv6): $LINK6"
  echo "$LINK6" >> $LINK_FILE
fi

echo "------------------------------------------------------------------------"
echo "所有链接已保存到: $LINK_FILE"

# 在 root 目录下创建软链接，方便快速访问
ln -sf $LINK_FILE /root/tuic-links.txt
echo "快捷访问: ~/tuic-links.txt"

# ===== 生成 v2rayN 节点配置 =====
V2RAYN_FILE="$CERT_DIR/v2rayn-tuic.json"
cat > $V2RAYN_FILE <<EOF
{
  "protocol": "tuic",
  "tag": "TUIC-$CC_ALGO",
  "settings": {
    "server": "${IPV4:-$IPV6}",
    "server_port": $PORT,
    "uuid": "$UUID",
    "password": "$PASS",
    "congestion_control": "$CC_ALGO",
    "alpn": ["h3"],
    "sni": "$FAKE_DOMAIN",
    "udp_relay_mode": "native",
    "disable_sni": false,
    "reduce_rtt":
