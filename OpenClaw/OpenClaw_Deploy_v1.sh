#!/bin/bash
# 1. 环境大洗牌：强制安装 Node v22 和所有编译依赖
echo "正在安装 Node.js v22 和基础编译工具..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt update && apt install -y nodejs git build-essential python3 make g++ nginx curl

# 2. 暴力安装 OpenClaw (使用国内镜像加速，防止卡顿)
echo "正在从 npmmirror 下载并安装 OpenClaw..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com

# 3. 预设配置文件：适配 2026.3.2 的 auth.token 格式和 IP 白名单
echo "正在写入配置文件..."
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
        "https://192.168.1.35:8888",
        "https://127.0.0.1:8888",
        "http://localhost:18789"
      ]
    }
  }
}
EOF

# 4. Nginx SSL 隧道配置：解决浏览器 Secure Context 限制
echo "正在配置 Nginx HTTPS 隧道..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/OU=IT/CN=192.168.1.35"

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

# 5. 启动服务并检查
systemctl restart nginx
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

echo "------------------------------------------------"
echo "部署完成！你的 192.168.1.35 节点已上线。"
echo "请访问: https://192.168.1.35:8888"
echo "令牌: 1f9a2cadac65c3f5db8eceb1b462c0b28fa05066606cc6d8"
echo "别忘了运行 'openclaw devices approve <ID>' 批准你的浏览器！"
echo "------------------------------------------------"
