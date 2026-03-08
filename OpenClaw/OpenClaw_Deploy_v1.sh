#!/bin/bash

# =================================================================
# OpenClaw Pro - Final Stable Edition (2026)
# 修正内容：官方优先/镜像兜底逻辑 + 路径强制刷新
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
echo -e "            OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. 获取网络信息
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 安装环境与必备工具
echo "正在配置环境与安装程序..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl psmisc > /dev/null 2>&1

# 3. 安装 OpenClaw (官方优先，镜像兜底)
echo "正在尝试从官方源安装 OpenClaw..."
npm install -g openclaw@2026.3.2 --unsafe-perm --force > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}[提示] 官方源连接失败，正在切换至镜像站进行二次尝试...${NC}"
    npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
    check_step "OpenClaw 程序安装" "请检查磁盘空间或网络代理设置"
else
    echo -e "${GREEN}[成功] 已通过官方源完成安装。${NC}"
fi

# 关键：安装后强制刷新系统路径缓存
hash -r 
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null

# 4. 写入配置文件
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

# 5. 配置 Nginx SSL (保持原版逻辑)
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

# 6. 核心启动逻辑 (使用绝对路径启动)
echo -e "${GREEN}正在启动网关后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true 

# 使用物理绝对路径拉起，防止 11fa 节点 command not found
OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 7. 验证循环与 502 修复
V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${GREEN}[成功] 网关后端已就绪，正在激活 Nginx 隧道关联...${NC}"
        killall -9 nginx 2>/dev/null || true
        /usr/sbin/nginx || systemctl restart nginx
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
    echo -e "================================================${NC}"
else
    # 超时兜底强制重启 Nginx
    killall -9 nginx 2>/dev/null || true
    /usr/sbin/nginx
    echo -e "${RED}[警告] 后端启动较慢，请稍后手动刷新。${NC}"
fi
