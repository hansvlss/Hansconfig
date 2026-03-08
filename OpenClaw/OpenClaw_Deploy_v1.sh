#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> 开始 OpenClaw 自动化部署流程...${NC}"

# 1. 自动获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$USER_IP" ]; then
    echo -e "${RED}[错误] 无法获取系统 IP，请检查网络设置。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 检测到当前 IP 为: ${USER_IP}${NC}"

# 2. 安装 Node.js v22 源
echo "正在配置 Node.js v22 源..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] Node.js 源配置失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] Node.js 源已就绪。${NC}"

# 3. 安装核心依赖
echo "正在安装基础依赖包 (git, build-essential, nginx)..."
apt update && apt install -y nodejs git build-essential python3 make g++ nginx curl
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 基础软件安装失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 系统环境依赖安装完成。${NC}"

# 4. 全局安装 OpenClaw
echo "正在通过 npm 安装 OpenClaw 2026.3.2..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] OpenClaw 安装失败，请检查 npm 权限或网络。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] OpenClaw 程序安装完成。${NC}"

# 5. 写入动态配置文件
echo "正在生成动态配置文件..."
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "token": "1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8"
    },
    "controlUi": {
      "allowedOrigins": [
        "https://${USER_IP}:8888",
        "https://127.0.0.1:8888",
        "http://localhost:18789"
      ]
    }
  }
}
EOF
echo -e "${GREEN}[成功] 配置文件已生成 (IP: ${USER_IP})。${NC}"

# 6. 配置 Nginx SSL 隧道
echo "正在生成自签名 SSL 证书..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}"
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] SSL 证书生成失败。${NC}"
    exit 1
fi

echo "正在配置 Nginx 反向代理..."
cat > /etc/nginx/sites-enabled/default <<EOF
server {
    listen 8888 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host localhost;
        proxy_set_header Origin http://localhost:18789;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

nginx -t && systemctl restart nginx
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] Nginx 配置或启动失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] Nginx SSL 隧道已启动。${NC}"

# 7. 启动 OpenClaw
echo "正在启动 OpenClaw 网关..."
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &
sleep 3

# 检查进程是否存在
ps -ef | grep openclaw | grep -v grep > /dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] OpenClaw 进程未能成功启动，请检查 /tmp/openclaw.log。${NC}"
    exit 1
fi

echo -e "${GREEN}================================================"
echo -e "部署大功告成，Hans！"
echo -e "访问地址: https://${USER_IP}:8888"
echo -e "登录令牌: 1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8"
echo -e "最后一步: 请在终端运行 'openclaw devices list' 并批准你的设备。"
echo -e "================================================${NC}"
