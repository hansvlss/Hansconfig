#!/bin/bash

# 颜色与提示定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 中文错误处理函数
check_step() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] $1 失败了！${NC}"
        echo -e "${RED}建议检查：$2${NC}"
        exit 1
    fi
}

echo -e "${GREEN}>>> 开启 OpenClaw 零起点全自动部署 (含中文错误反馈)...${NC}"

# 1. 自动获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && echo -e "${RED}[错误] 无法获取 IP，请检查网卡。${NC}" && exit 1
echo -e "${GREEN}[成功] 当前 IP: ${USER_IP}${NC}"

# 2. 配置 Node.js v22 环境
echo "正在配置 Node.js v22 环境..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
check_step "Node.js 源配置" "请检查网络是否能连接到 nodesource.com"

# 3. 安装依赖包
echo "正在安装基础工具 (git, nginx, nodejs)..."
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl > /dev/null 2>&1
check_step "系统软件安装" "请尝试运行 'apt update' 查看是否有软件源报错"

# 4. 安装 OpenClaw
echo "正在安装 OpenClaw 2026.3.2..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
check_step "OpenClaw 程序安装" "请检查磁盘空间或 npm 镜像连接"

# 5. 写入配置文件 (动态令牌)
DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
rm -f ~/.openclaw/openclaw.json*
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
echo -e "${GREEN}[成功] 配置文件已生成。${NC}"

# 6. 配置 Nginx SSL (修复版：强制清理冲突)
echo "正在配置 Nginx HTTPS 隧道..."
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1
check_step "SSL 证书生成" "请检查 openssl 是否正确安装"

# 关键修复：先清理旧配置，确保证书定义在 server 块内
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
check_step "Nginx 语法检查" "可能是证书路径错误，请手动运行 'nginx -t' 查看第几行报错"

systemctl restart nginx
check_step "Nginx 服务启动" "请检查 8888 端口是否被占用 (lsof -i:8888)"

# 7. 启动并健康检查
echo -e "${GREEN}正在启动网关...${NC}"
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 循环检查
V_DONE=0
for i in {1..15}; do
    if curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${GREEN}[成功] 网关已就绪！执行最终关联...${NC}"
        systemctl restart nginx
        V_DONE=1
        break
    fi
    echo "等待网关中... ($i/15)"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "${GREEN}================================================"
    echo -e "部署成功！访问地址: https://${USER_IP}:8888"
    echo -e "登录令牌: ${DYNAMIC_TOKEN}"
    echo -e "------------------------------------------------"
    echo -e "后续步骤："
    echo -e "1. 浏览器打开页面并输入令牌"
    echo -e "2. 终端运行: openclaw devices list"
    echo -e "3. 终端运行: openclaw devices approve <查到的ID>"
    echo -e "================================================${NC}"
else
    echo -e "${RED}[错误] 网关启动超时，请查看日志: cat /tmp/openclaw.log${NC}"
fi
