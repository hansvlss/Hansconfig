#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 开启 OpenClaw 2026 终极一键部署...${NC}"

# 1. 动态获取当前局域网 IP
USER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$USER_IP" ]; then
    echo -e "${RED}[错误] 无法获取系统 IP。${NC}"
    exit 1
fi

# 2. 配置 Node.js v22 环境与安装基础依赖
echo "正在安装 Node.js v22 及编译工具..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt update && apt install -y nodejs git build-essential python3 make g++ nginx curl

# 3. 安装 OpenClaw 主程序
echo "正在安装 OpenClaw 2026.3.2..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com

# 4. 写入配置文件 (确保格式完全适配 2026 版本)
mkdir -p ~/.openclaw
rm -f ~/.openclaw/openclaw.json*
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8" },
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

# 5. 配置 Nginx SSL 与反向代理
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}"

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
    }
}
EOF

# 6. 启动网关服务 (以后台模式运行)
echo -e "${GREEN}正在启动网关并执行健康检查循环...${NC}"
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 7. 关键步骤：死等网关端口响应，成功后再激活 Nginx
V_CHECK=0
for i in {1..20}; do
    if ss -ntlp | grep -q 18789; then
        echo -e "${GREEN}[成功] 网关已在 18789 端口响应！执行最终 Nginx 关联...${NC}"
        sleep 2
        nginx -t && systemctl restart nginx
        V_CHECK=1
        break
    fi
    echo "等待网关就绪中... ($i/20)"
    sleep 3
done

if [ "$V_CHECK" -eq 0 ]; then
    echo -e "${RED}[错误] 验证超时，请手动查看日志: cat /tmp/openclaw.log${NC}"
    exit 1
fi

echo -e "${GREEN}================================================"
echo -e "部署完成！浏览器现在可以正常打开了。"
echo -e "访问地址: https://${USER_IP}:8888"
echo -e "登录令牌: 1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8"
echo -e "------------------------------------------------"
echo -e "重要：如果网页提示 Pairing，请立即在终端执行授权："
echo -e "1. openclaw devices list"
echo -e "2. openclaw devices approve <查到的ID>"
echo -e "================================================${NC}"
