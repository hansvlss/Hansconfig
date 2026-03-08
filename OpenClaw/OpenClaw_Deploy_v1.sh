#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 开启 OpenClaw 2026.3.2 零起点全自动部署...${NC}"

# 1. 动态获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$USER_IP" ]; then
    echo -e "${RED}[错误] 无法获取系统 IP，请检查网卡配置。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 配置 Node.js v22 环境 (强制要求 v22.12+)
echo "正在配置 Node.js v22 源..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] NodeSource 源配置失败。${NC}"
    exit 1
fi

# 3. 安装系统核心依赖
echo "正在安装 git, build-essential, nginx, nodejs..."
apt update && apt install -y nodejs git build-essential python3 make g++ nginx curl
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 系统依赖包安装失败。${NC}"
    exit 1
fi
echo -e "${GREEN}[成功] 系统环境准备就绪。${NC}"

# 4. 全局安装 OpenClaw
echo "正在通过 npmmirror 安装 OpenClaw..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] OpenClaw 程序安装失败。${NC}"
    exit 1
fi

# 5. 生成动态配置文件
echo "正在清理并写入新版 openclaw.json..."
rm -rf ~/.openclaw/openclaw.json* mkdir -p ~/.openclaw
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

# 6. 配置 Nginx SSL 隧道
echo "正在生成自签名 SSL 证书 (10年有效期)..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}"

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

# 7. 启动并执行智能健康检查
echo -e "${GREEN}正在启动 OpenClaw 并等待服务就绪...${NC}"
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 循环检测服务响应，最多等待 30 秒
MAX_RETRIES=15
for ((i=1; i<=MAX_RETRIES; i++)); do
    # 通过 curl 请求内部接口确认服务是否活了
    if curl -s --connect-timeout 2 http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${GREEN}[成功] 网关已在 18789 端口正式就绪！${NC}"
        # 此时后端已稳，重启 Nginx 建立最终握手
        systemctl restart nginx
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo -e "${RED}[错误] 网关未能及时启动。请运行 'cat /tmp/openclaw.log' 查看原因。${NC}"
        exit 1
    fi
    echo "等待网关启动中... ($i/$MAX_RETRIES)"
    sleep 2
done

echo -e "${GREEN}================================================"
echo -e "部署大功告成，Hans！"
echo -e "访问地址: https://${USER_IP}:8888"
echo -e "登录令牌: 1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8"
echo -e "------------------------------------------------"
echo -e "最后必做：请在浏览器打开地址后，回到终端执行授权："
echo -e "1. openclaw devices list"
echo -e "2. openclaw devices approve <你的ID>"
echo -e "================================================${NC}"
