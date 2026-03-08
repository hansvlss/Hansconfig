#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 开启 OpenClaw 动态令牌全自动部署...${NC}"

# 1. 自动生成随机令牌 (不再固定)
# 生成一个 48 位的随机十六进制字符串
DYNAMIC_TOKEN=$(openssl rand -hex 24)
echo -e "${GREEN}[生成] 本次部署的随机令牌为: ${DYNAMIC_TOKEN}${NC}"

# 2. 获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && echo -e "${RED}无法获取 IP${NC}" && exit 1

# 3. 环境与程序安装 (Node v22)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt update && apt install -y nodejs git build-essential nginx curl
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com

# 4. 写入配置文件 (动态填入生成的令牌)
mkdir -p ~/.openclaw
rm -f ~/.openclaw/openclaw.json*
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { 
      "token": "${DYNAMIC_TOKEN}" 
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

# 5. Nginx SSL 配置 (动态 IP 对齐)
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}"

cat > /etc/nginx/sites-enabled/default <<EOF
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

# 6. 启动与验证重启逻辑
systemctl restart nginx
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 等待端口开启后执行最终关联
for i in {1..20}; do
    if ss -ntlp | grep -q 18789; then
        echo -e "${GREEN}[成功] 网关已就绪！执行最终关联重启...${NC}"
        sleep 2
        systemctl restart nginx
        V_DONE=1
        break
    fi
    echo "等待网关启动... ($i/20)"
    sleep 3
done

# 7. 部署总结
if [ "$V_DONE" == "1" ]; then
    echo -e "${GREEN}================================================"
    echo -e "部署完成！请妥善保存你的登录信息："
    echo -e "访问地址: https://${USER_IP}:8888"
    echo -e "网关令牌: ${DYNAMIC_TOKEN}"
    echo -e "------------------------------------------------"
    echo -e "授权步骤："
    echo -e "1. 浏览器打开地址并输入令牌"
    echo -e "2. 终端运行: openclaw devices list"
    echo -e "3. 终端运行: openclaw devices approve <ID>"
    echo -e "================================================${NC}"
fi
