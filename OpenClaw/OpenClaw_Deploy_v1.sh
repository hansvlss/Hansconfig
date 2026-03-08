#!/bin/bash
# OpenClaw 2026.3.2 PVE/CT 环境从零开始一键部署脚本

# 1. 系统环境更新
apt update && apt install -y curl openssl nginx psmisc

# 2. 安装 Node.js 20.x 运行环境
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# 3. 从零安装 OpenClaw (核心安装代码)
# --unsafe-perm 确保在容器内拥有足够的权限
npm install -g openclaw --unsafe-perm

# 4. 生成自签名证书 (提供 HTTPS 环境)
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key \
  -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/OU=IT/CN=localhost"

# 5. 写入 2026 版兼容性配置 (加入信任代理与白名单)
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "trustedProxies": ["127.0.0.1"],
    "controlUi": {
      "allowedOrigins": [
        "https://localhost:8888",
        "https://127.0.0.1:8888",
        "https://$(hostname -I | awk '{print $1}'):8888"
      ]
    }
  }
}
EOF

# 6. 配置 Nginx SSL 隧道 (解决 identity 报错的关键)
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

# 7. 重启服务
nginx -t && systemctl restart nginx
killall -9 openclaw 2>/dev/null || true

# 8. 最终输出引导
echo "------------------------------------------------"
echo "✅ OpenClaw 部署成功！"
echo "1. 执行命令启动网关: openclaw gateway run --allow-unconfigured &"
echo "2. 浏览器 HTTPS 访问: https://$(hostname -I | awk '{print $1}'):8888"
echo "3. 登录令牌(Token): \$(grep '"token"' ~/.openclaw/openclaw.json | awk -F'"' '{print $4}')"
echo "4. ⚠️ 务必在终端执行 openclaw devices approve <ID> 完成配对！"
echo "------------------------------------------------"
