#!/bin/bash

# =================================================================
# OpenClaw Pro - Hardcore Edition (2026.03)
# 逻辑：只管安装，不管检查，强制重启 Nginx
# =================================================================

export TERM=xterm-256color
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
NC="\033[0m"

echo -e "${G_BOLD}=================================================================="
echo -e "           OpenClaw 网关极简部署工具 (强制重启模式)"
echo -e "==================================================================${NC}"

# 1. 环境净化
echo -ne "➤ 正在清理旧进程..."
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
rm -rf ~/.openclaw/openclaw.json*
echo -e " [ OK ]"

# 2. 获取 IP
USER_IP=$(hostname -I | awk '{print $1}')

# 3. 安装 (使用镜像站 & 自动修复路径)
echo -ne "➤ 正在同步组件与安装核心..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs nginx curl > /dev/null 2>&1
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
# 修复可能存在的路径问题
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null
echo -e " [ OK ]"

# 4. 写入配置 (含代理信任)
echo -ne "➤ 正在注入令牌与安全配置..."
DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "trustedProxies": ["127.0.0.1", "::1"],
    "controlUi": {
      "allowedOrigins": ["https://${USER_IP}:8888", "https://127.0.0.1:8888", "http://localhost:18789"]
    }
  }
}
EOF
echo -e " [ OK ]"

# 5. SSL & Nginx 静态构建
echo -ne "➤ 正在构建 SSL 隧道..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1

rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/openclaw <<EOF
server {
    listen 8888 ssl;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host localhost;
        proxy_set_header Origin http://localhost:18789;
    }
}
EOF
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/default
echo -e " [ OK ]"

# 6. 启动后端 & 强制重启 Nginx (你要的命令)
echo -ne "➤ 正在拉起服务并强制同步 Nginx..."
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &
sleep 5
# 执行你认为最有效的命令
systemctl restart nginx || service nginx restart
echo -e " [ OK ]"

# 7. 结果面板
echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
echo -e "│                部署完成 / DEPLOYMENT READY                 │"
echo -e "└────────────────────────────────────────────────────────────┘${NC}"
echo -e "${G_NORM}▶ 地址: ${G_BOLD}https://${USER_IP}:8888${NC}"
echo -e "${G_NORM}▶ 令牌: ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
echo -e "${G_NORM}--------------------------------------------------------------"
echo -e "请直接访问页面并使用 ${G_BOLD}openclaw devices approve <ID>${NC} 授权。"
echo -e "${G_BOLD}==============================================================${NC}\n"
