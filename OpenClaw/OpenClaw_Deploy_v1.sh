#!/bin/bash

# =================================================================
# OpenClaw Pro - Master Self-Healing Edition (2026)
# 核心：暴力自愈启动 + 路径自动修复 + 强制版本更新
# =================================================================

export TERM=xterm-256color
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 显示函数定义
print_step() { echo -ne "\033[1;32m➤\033[0m ${G_NORM}$1...${NC}"; }
print_ok() { echo -e " [ \033[1;32m✔\033[0m ]"; }
error_exit() {
    echo -e "\n${RED}[部署中断]: $1${NC}"
    echo -e "${YELLOW}建议: $2${NC}"
    exit 1
}

clear
echo -e "${G_BOLD}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. 自动获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && error_exit "无法获取 IP" "请检查网卡配置"
echo -e "${G_BOLD}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 系统环境深度净化
print_step "正在安装必备工具 (psmisc/curl)"
apt update > /dev/null 2>&1 && apt install -y psmisc curl nginx nodejs build-essential > /dev/null 2>&1
print_ok

print_step "正在强制清理旧进程与残留端口"
killall -9 node openclaw nginx 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
rm -rf ~/.openclaw/openclaw.json*
print_ok

# 3. 安装最新版 OpenClaw
print_step "配置 Node.js 22 LTS 环境"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
print_ok

print_step "正在拉取 OpenClaw 最新稳定版"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
# 路径自动修复补丁
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null
print_ok

# 4. 写入配置 (含动态令牌与代理信任)
print_step "注入加密令牌与反代信任配置"
DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "trustedProxies": ["127.0.0.1", "::1"],
    "controlUi": {
      "allowedOrigins": [ "https://${USER_IP}:8888", "https://127.0.0.1:8888", "http://localhost:18789" ]
    }
  }
}
EOF
print_ok

# 5. SSL & Nginx 静态构建
print_step "构建 SSL 安全加密隧道"
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
print_ok

# 6. 最终启动与健康检查
print_step "正在启动 OpenClaw 后端服务"
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
for i in {1..20}; do
    # 只要 18789 端口活了，就认为成功
    if ss -lntp | grep -q ":18789" > /dev/null; then
        echo -ne "\r${G_NORM}➤ 后端已就绪，正在强制同步 Nginx 隧道...${NC}"
        # 使用你发现最有效的重启命令
        /usr/sbin/nginx > /dev/null 2>&1 || systemctl restart nginx
        V_DONE=1
        break
    fi
    echo -ne "\r${G_NORM}等待后端初始化中... ($i/20)${NC}"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e " [ ${CHECK} ]"
    echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT SUCCESS               │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo -e "${G_NORM}${BOLD}▶ 访问地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
    echo -e "${G_NORM}${BOLD}▶ 登录令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
    echo -e "${G_NORM}--------------------------------------------------------------"
    echo -e "${G_BOLD}后续操作：${NC}"
    echo -e " 1. 浏览器打开页面并输入令牌登录"
    echo -e " 2. 在终端执行授权: ${G_BOLD}openclaw devices approve <ID>${NC}"
    echo -e "${G_BOLD}==============================================================${NC}\n"
else
    error_exit "网关启动超时" "请查看日志: cat /tmp/openclaw.log"
fi
