#!/bin/bash

# =================================================================
# OpenClaw Pro - Master Self-Healing Edition (2026.03.08)
# 核心：Node 环境强力校验 + 暴力路径修复
# =================================================================

export TERM=xterm-256color
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

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

# 1. IP 获取
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${G_BOLD}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 系统深度净化
print_step "安装必备工具并清理环境"
apt update > /dev/null 2>&1
apt install -y psmisc curl gnupg ca-certificates nginx build-essential > /dev/null 2>&1
killall -9 node openclaw nginx 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
print_ok

# 3. 强制 Node.js 安装与校验
print_step "部署 Node.js 22 LTS 核心环境"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt install -y nodejs > /dev/null 2>&1
# 关键步骤：刷新环境变量并校验
hash -r
if ! command -v npm &> /dev/null; then
    # 如果还是不行，尝试手动修复链接
    ln -sf /usr/bin/npm /usr/local/bin/npm 2>/dev/null
    if ! command -v npm &> /dev/null; then
        error_exit "Node.js 环境部署失败" "npm 命令依然不可用，请手动运行 apt install -y nodejs"
    fi
fi
print_ok

# 4. OpenClaw 安装 (使用绝对路径)
print_step "拉取 OpenClaw 最新稳定版"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
# 建立绝对路径软链接
NPM_BIN_PATH=$(npm config get prefix)/bin/openclaw
ln -sf "$NPM_BIN_PATH" /usr/local/bin/openclaw
print_ok

# 5. 配置生成 (保持稳健逻辑)
print_step "注入加密令牌与反代配置"
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

# 6. Nginx SSL 隧道
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
    }
}
EOF
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/default
/usr/sbin/nginx -t > /dev/null 2>&1
print_ok

# 7. 启动并执行健康检查
print_step "启动后端服务并同步隧道"
# 使用绝对路径启动，防止环境干扰
OPENCLAW_EXEC=$(command -v openclaw)
$OPENCLAW_EXEC gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" > /dev/null; then
        # 强制重启 Nginx 建立关联
        /usr/sbin/nginx > /dev/null 2>&1 || systemctl restart nginx
        V_DONE=1
        break
    fi
    echo -ne "\r等待后端就绪... ($i/20)"
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
    echo -e "请在浏览器打开地址并登录，完成后回到此终端授权设备。"
    echo -e "${G_BOLD}==============================================================${NC}\n"
else
    error_exit "网关启动超时" "请查看日志内容: cat /tmp/openclaw.log"
fi
