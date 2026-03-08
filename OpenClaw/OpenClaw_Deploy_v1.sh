#!/bin/bash

# =================================================================
# OpenClaw Pro - Final Stable Edition (2026)
# 修正内容：解决 Nginx 启动过快导致的 502 报错
# =================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_step() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] $1 失败了！${NC}"
        echo -e "${RED}建议检查：$2${NC}"
        exit 1
    fi
}

clear
echo -e "${GREEN}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1-5 步保持你最稳的逻辑 (IP 获取、Node 安装、NPM 安装、配置生成)
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}[成功] 当前检测到 IP: ${USER_IP}${NC}"

echo "正在配置环境与安装程序..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl > /dev/null 2>&1
apt update && apt install -y psmisc
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null

DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "controlUi": {
      "allowedOrigins": [ "https://${USER_IP}:8888", "https://127.0.0.1:8888", "http://localhost:18789" ]
    }
  }
}
EOF

# 6. 配置 Nginx SSL (仅写入配置，暂不强制重启)
echo "正在配置 Nginx HTTPS 隧道..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1

rm -rf /etc/nginx/sites-enabled/*
cat > /etc/nginx/sites-available/openclaw <<EOF
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
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/default
nginx -t > /dev/null 2>&1
check_step "Nginx 语法检查" "手动运行 'nginx -t' 查看报错"

# 7. 核心修正：先启网关，后启 Nginx
echo -e "${GREEN}正在启动网关后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
# 暴力清除残留端口占用
fuser -k 18789/tcp 2>/dev/null || true 
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 关键验证循环
V_DONE=0
for i in {1..20}; do
    # 增加探测深度：直接检查 18789 端口是否已经开始监听
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${GREEN}[成功] 网关后端已就绪，正在激活 Nginx 隧道关联...${NC}"
        # 这里执行你发现“运行了就正常”的命令
        systemctl restart nginx || service nginx restart
        V_DONE=1
        break
    fi
    echo "等待网关响应中... ($i/20)"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\n${GREEN}================================================"
    echo -e "部署成功！访问地址: https://${USER_IP}:8888"
    echo -e "登录令牌: ${DYNAMIC_TOKEN}"
    echo -e "------------------------------------------------"
    echo -e "后续操作："
    echo -e "1. 浏览器打开并输入令牌登录"
    echo -e "2. 终端授权: openclaw devices approve <ID>"
    echo -e "================================================${NC}"
else
    # 失败时尝试最后拉起一次 Nginx 以便用户排查
    systemctl restart nginx
    echo -e "${RED}[警告] 网关响应缓慢，已强制重启 Nginx，如仍有 502 请稍后刷新。${NC}"
fi
