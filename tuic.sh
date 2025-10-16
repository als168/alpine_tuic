#!/bin/sh
# TUIC v5 一键安装脚本 (Alpine Linux, 自动检测二进制 + URL 编码订阅链接)
# 优化版：去掉不稳定代理源，支持 aria2c，多线程下载，改进验证逻辑

set -e

echo "---------------------------------------"
echo " TUIC v5 Alpine Linux 安装脚本 (优化版)"
echo "---------------------------------------"

# ===== 安装依赖 =====
echo "正在安装必要的软件包..."
apk add --no-cache wget curl openssl openrc lsof coreutils jq file >/dev/null
apk add --no-cache aria2 >/dev/null || true

TUIC_BIN="/usr/local/bin/tuic"
TEMP_BIN="/tmp/tuic_temp"

# ===== 检测是否已有 TUIC =====
if [ -x "$TUIC_BIN" ]; then
  echo "检测到已存在 TUIC 二进制，跳过下载步骤"
else
  echo "未检测到 TUIC，开始下载..."

  # 获取最新 tag
  echo "正在获取最新版本信息..."
  TAG=$(curl -s https://api.github.com/repos/tuic-protocol/tuic/releases/latest | jq -r .tag_name)
  if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
    echo "无法获取最新版本信息，使用默认版本 1.0.0"
    TAG="tuic-server-1.0.0"
    VERSION="1.0.0"
  else
    VERSION=${TAG#tuic-server-}
  fi
  echo "检测到最新版本: $VERSION"

  # 拼接文件名和下载地址 (x86_64 架构)
  FILENAME="tuic-server-${VERSION}-x86_64-unknown-linux-musl"
  
  URLS="
  https://github.com/tuic-protocol/tuic/releases/download/$TAG/$FILENAME
  https://mirror.ghproxy.com/https://github.com/tuic-protocol/tuic/releases/download/$TAG/$FILENAME
  "

  SUCCESS=0
  for url in $URLS; do
    echo "尝试下载: $url"
    if command -v aria2c >/dev/null 2>&1; then
      aria2c -x 8 -s 8 -o $TEMP_BIN "$url" || continue
    else
      wget --timeout=30 --tries=3 -O $TEMP_BIN "$url" || continue
    fi

    FILE_SIZE=$(stat -c %s $TEMP_BIN)
    if [ $FILE_SIZE -lt 100000 ]; then
      echo "警告: 文件过小 ($FILE_SIZE 字节)，可能不是有效二进制，尝试下一个源"
      continue
    fi

    FILE_TYPE=$(file $TEMP_BIN)
    echo "文件类型: $FILE_TYPE"
    if echo "$FILE_TYPE" | grep -q "ELF"; then
      echo "✓ 文件验证通过"
      mv $TEMP_BIN $TUIC_BIN
      chmod +x $TUIC_BIN
      SUCCESS=1
      break
    fi
  done

  if [ $SUCCESS -eq 0 ]; then
    echo "❌ 所有下载源均失败，请手动下载 TUIC 二进制"
    exit 1
  fi
fi

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
  read -p "请输入证书域名 (SNI): " FAKE_DOMAIN
  if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "❌ 证书或私钥文件不存在，请检查路径"
    exit 1
  fi
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
ENC_PASS=$(printf '%s' "$PASS" | jq -s -R -r @uri)
ENC_SNI=$(printf '%s' "$FAKE_DOMAIN" | jq -s -R -r @uri)
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
echo "tuic://$UUID:$ENC_PASS@$IP:$PORT?sni=$ENC_SNI&alpn=h3#TUIC节点"
echo "------------------------------------------------------------------------"
