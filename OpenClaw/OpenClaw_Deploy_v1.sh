#!/bin/bash

# =================================================================
# OpenClaw Pro - Hans Stable Edition (2026.03.08)
# 特点：暴力重启、强制路径、没有任何花哨检查
# =================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 开启 OpenClaw 强力部署 (基于 Hans 最稳逻辑)...${NC}"

# 1. 物理清理 (防止端口占用)
killall -9 node openclaw nginx 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
rm -rf ~/.openclaw/openclaw.json*

# 2. 强制安装 Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs nginx psmisc curl > /dev/null 2>&1

# 3. 强制路径修复 (解决 command not found 的核心)
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
# 不管系统环境如何，强制把命令映射到系统最核心目录
NPM_BIN=$(npm config get prefix)/bin/openclaw
ln -sf "$NPM_BIN" /usr/local/bin/openclaw
ln -sf "$NPM_BIN" /usr/bin/openclaw

# 4. 写入配置
USER_IP=$(hostname -I | awk '{print $1}')
DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "controlUi": {
      "allowedOrigins": [ "https://${USER_IP}:8888", "https://127.0.0.1:8888" ]
    }
  }
}
EOF

# 5. SSL & Nginx (强制清理并重置)
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1

rm -rf /etc/nginx/sites-enabled/*
cat > /etc/nginx/sites-available/openclaw <<EOF
server {
    listen 8888 ssl;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host localhost;
    }
}
EOF
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/default

# 6. 暴力拉起并强制重启
echo -e "${GREEN}正在拉起服务...${NC}"
# 直接用绝对路径启动，彻底避开 command not found
/usr/local/bin/openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &
# 强制等待，不搞复杂的探测，给 LXC 充足响应时间
sleep 10 
systemctl restart nginx || /usr/sbin/nginx
echo -e "${GREEN}================================================"
echo -e "部署完成！地址: https://${USER_IP}:8888"
echo -e "登录令牌: ${DYNAMIC_TOKEN}"
echo -e "================================================${NC}"
