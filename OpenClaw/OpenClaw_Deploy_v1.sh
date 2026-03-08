#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 开启 OpenClaw 零起点全自动部署 (2026.3.2)...${NC}"

# 1. 动态获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$USER_IP" ]; then
    echo -e "${RED}[错误] 无法获取系统 IP，请检查网卡配置。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 配置 Node.js v22 环境 (OpenClaw 强需求)
echo "正在安装 Node.js v22 源..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] NodeSource 源配置失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] Node.js v22 源配置完成。${NC}"

# 3. 安装系统核心依赖
echo "正在安装 git, build-essential, nginx, nodejs..."
apt update && apt install -y nodejs git build-essential python3 make g++ nginx curl
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 系统依赖包安装失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 系统环境准备就绪。${NC}"

# 4. 全局安装 OpenClaw 程序
echo "正在从 npmmirror 下载安装 OpenClaw..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] OpenClaw 程序安装失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] OpenClaw 主程序安装完成。${NC}"

# 5. 生成动态配置文件
echo "正在写入 openclaw.json 配置文件..."
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
echo -e "${GREEN}[成功] 配置文件已生成。${NC}"

# 6. 配置 Nginx SSL 隧道
echo "正在生成 10 年期自签名证书..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}"
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] SSL 证书生成失败。${NC}"
    exit 1
fi

echo "正在应用 Nginx 反向代理配置..."
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
    echo -e "${RED}[错误] Nginx 配置错误。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] Nginx 隧道配置完成。${NC}"

# 7. 启动服务并执行二次重启检查
echo "正在启动 OpenClaw 并进行端口就绪检查..."
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 等待网关完全开启监听
MAX_WAIT=10
for ((i=1; i<=MAX_WAIT; i++)); do
    if ss -ntlp | grep -q 18789; then
        echo -e "${GREEN}[成功] 检测到网关已在 18789 端口响应！${NC}"
        echo "正在执行 Nginx 最终握手重启..."
        systemctl restart nginx
        break
    fi
    [ $i -eq $MAX_WAIT ] && echo -e "${RED}[错误] 网关未能在 10s 内启动，请检查 /tmp/openclaw.log${NC}" && exit 1
    echo "等待中... ($i/$MAX_WAIT)"
    sleep 2
done

echo -e "${GREEN}================================================"
echo -e "恭喜 Hans，部署全部完成！"
echo -e "访问地址: https://${USER_IP}:8888"
echo -e "登录令牌: 1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8"
echo -e "------------------------------------------------"
echo -e "最后必做：请在终端输入以下命令完成设备授权："
echo -e "1. openclaw devices list"
echo -e "2. openclaw devices approve <你的ID>"
echo -e "================================================${NC}"
