#!/bin/sh
# TUIC v5 一键安装脚本 (仅适用于 Alpine Linux, 使用 musl 构建)

set -e

echo "---------------------------------------"
echo " TUIC v5 Alpine Linux 安装脚本"
echo "---------------------------------------"

# ===== 安装依赖 =====
echo "正在安装必要的软件包..."
apk add --no-cache wget curl openssl openrc lsof coreutils >/dev/null

# ===== 下载 TUIC (musl 版本) =====
echo "正在下载 TUIC 最新版 (musl 构建)..."
TUIC_BIN="/usr/local/bin/tuic"
URLS="
https://github.com/tuic-protocol/tuic/releases/latest/download/tuic-server-x86_64-unknown-linux-musl
https://ghproxy.com/https://github.com/tuic-protocol/tuic/releases/latest/download/tuic-server-x86_64-unknown-linux-musl
https://download.fastgit.org/tuic-protocol/tuic/releases/latest/download/tuic-server-x86_64-unknown-linux-musl
"

SUCCESS=0
for url in $URLS; do
  echo "尝试下载: $url"
  if wget --timeout=30 --tries=2 --show-progress -O $TUIC_BIN "$url"; then
    SUCCESS=1
    break
  fi
done

if [ $SUCCESS -eq 0 ]; then
  echo "❌ 所有下载源均失败，请检查网络环境。"
  exit 1
fi

chmod +x $TUIC_BIN

# ===== 证书处理 =====
CERT_DIR="/etc/tuic"
mkdir -p $CERT_DIR

read -p "请输入证书 (.crt) 文件绝对路径 (回车则生成自签证书): " CERT_PATH
if [ -z "$CERT_PATH" ]; then
  read -p "请输入用于自签证书的伪装域名 (默认 www.bing.com): " FAKE_DOMAIN
  [ -z "$FAKE_DOMAIN" ] && FAKE_DOMAIN="www.bing.com"
  echo "正在生成自签证书..."
  openssl req -x509 -newkey rsa:2048 -nodes -keyout $CERT_DIR/key.pem -out $CERT_DIR/cert.pem -days 365 \
    -subj "/CN=$FAKE_DOMAIN"
  CERT_PATH="$CERT_DIR/cert.pem"
  KEY_PATH="$CERT_DIR/key.pem"
else
  read -p "请输入私钥 (.key) 文件绝对路径: " KEY_PATH
fi

# ===== 生成 UUID 和密码 =====
UUID=$(cat /proc/sys/kernel/random/uuid)
PASS=$(openssl rand -base64 16)

read -p "请输入 TUIC 端口 (默认 28543): " PORT
[ -z "$PORT" ] && PORT=28543

# ===== 写配置文件 =====
CONFIG_FILE="$CERT_DIR/config.json"
cat > $CONFIG_FILE <<EOF
{
  "server": "[::]:$PORT",
  "users": {
    "$UUID": "$PASS"
  },
  "certificate": "$CERT_PATH",
  "private_key": "$KEY_PATH",
  "alpn": ["h3"],
  "congestion_control": "bbr"
}
EOF

echo "配置文件已生成: $CONFIG_FILE"

# ===== OpenRC 服务 =====
SERVICE_FILE="/etc/init.d/tuic"
cat > $SERVICE_FILE <<'EOF'
#!/sbin/openrc-run
description="TUIC v5 Service"

command="/usr/local/bin/tuic"
command_args="--config /etc/tuic/config.json"
command_background="yes"
pidfile="/run/tuic.pid"

depend() {
    need net
}
EOF

chmod +x $SERVICE_FILE
rc-update add tuic default
rc-service tuic restart

# ===== 输出订阅链接 =====
IP=$(wget -qO- ipv4.icanhazip.com || wget -qO- ipv6.icanhazip.com)
echo "------------------------------------------------------------------------"
echo " TUIC 安装和配置完成！"
echo "------------------------------------------------------------------------"
echo "服务器地址: $IP"
echo "端口: $PORT"
echo "UUID: $UUID"
echo "密码: $PASS"
echo "SNI: $FAKE_DOMAIN"
echo "证书路径: $CERT_PATH"
echo "私钥路径: $KEY_PATH"
echo "------------------------------------------------------------------------"
echo "订阅链接 (TUIC V5):"
echo "tuic://$UUID:$PASS@$IP:$PORT?sni=$FAKE_DOMAIN&alpn=h3#TUIC节点"
echo "------------------------------------------------------------------------"
