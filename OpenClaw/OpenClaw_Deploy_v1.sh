#!/bin/bash

# =================================================================
# OpenClaw Pro - Universal Deployment Script (2026)
# Feature: Proxy-Aware & Auto-Failover Registry
# Designed for Hans (hanscn.com)
# =================================================================

# 1. 颜色与图标定义
export TERM=xterm-256color
CHECK="\033[0;32m\xE2\x9C\x94\033[0m"
CROSS="\033[0;31m\xE2\x9C\x98\033[0m"
STEP="\033[1;36m\xE2\x9E\x9C\033[0m"
BOLD="\033[1m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"

error_exit() {
    echo -e "\n${CROSS} ${RED}${BOLD}部署中断: $1${NC}"
    echo -e "${YELLOW}诊断建议: $2${NC}"
    echo -e "------------------------------------------------"
    exit 1
}

print_step() { echo -ne "${STEP} ${BOLD}$1...${NC}"; }
print_ok() { echo -e " [ ${CHECK} ]"; }

clear
echo -e "${BLUE}${BOLD}================================================================"
echo -e "       OPENCLAW GATEWAY PRO INSTALLER (AUTO-FAILOVER)"
echo -e "================================================================${NC}"

# 1. 系统检测
print_step "正在检索系统网络信息"
USER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$USER_IP" ]; then error_exit "无法抓取内网 IP" "请检查网络配置。"; fi
print_ok

# 2. 智能仓库探测 (官方优先 -> 镜像回退)
print_step "正在探测最佳安装仓库源"
if curl -s --connect-timeout 5 https://registry.npmjs.org/openclaw > /dev/null; then
    REGISTRY="https://registry.npmjs.org"
    REPO_NAME="官方仓库"
else
    REGISTRY="https://registry.npmmirror.com"
    REPO_NAME="阿里云镜像 (自动回退)"
fi

# 获取版本号
LATEST_VERSION=$(curl -s ${REGISTRY}/openclaw/latest | sed 's/.*"version":"\([^"]*\)".*/\1/')
[ -z "$LATEST_VERSION" ] && LATEST_VERSION="latest"
print_ok
echo -e "${BLUE}${BOLD}▶ 部署版本:${NC} ${YELLOW}v${LATEST_VERSION}${NC} ${BLUE}(源: ${REPO_NAME})${NC}"

# 3. 环境配置 (Node.js v22 LTS)
print_step "配置 Node.js 运行环境"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
if [ $? -ne 0 ]; then error_exit "Node.js 源同步失败" "请检查代理是否允许访问 nodesource.com。"; fi
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl > /dev/null 2>&1
print_ok

# 4. 程序安装 (智能双源熔断)
print_step "正在拉取 OpenClaw 核心程序"
# 优先使用探测出的 REGISTRY
npm install -g openclaw@${LATEST_VERSION} --unsafe-perm --force --registry=${REGISTRY} > /dev/null 2>&1

# 如果第一遍失败了，强制切到镜像再试一次
if [ $? -ne 0 ]; then
    echo -ne "\n${YELLOW}${STEP} 官方源安装受阻，尝试备用镜像...${NC}"
    npm install -g openclaw@${LATEST_VERSION} --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
fi

if [ $? -ne 0 ]; then error_exit "程序安装失败" "官方与镜像源均无法连接，请检查代理规则。"; fi
print_ok

# 5. 自动配置 (保持核心逻辑)
print_step "正在生成加密令牌与本地配置"
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
print_ok

# 6. SSL 加密隧道构建
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
systemctl restart nginx > /dev/null 2>&1
print_ok

# 7. 唤醒网关与健康检查
print_step "初始化后端进程并关联 Nginx"
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
for i in {1..20}; do
    if curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        systemctl restart nginx > /dev/null 2>&1
        V_DONE=1
        break
    fi
    sleep 2
done
[ "$V_DONE" == "0" ] && error_exit "网关响应超时" "检查 /tmp/openclaw.log"
print_ok

# 8. 总结报告
echo -e "\n${GREEN}${BOLD}==================== 部署成功 SUCCESS ====================${NC}"
echo -e "${BOLD}▶ 访问地址:${NC} ${BLUE}https://${USER_IP}:8888${NC}"
echo -e "${BOLD}▶ 登录令牌:${NC} ${YELLOW}${DYNAMIC_TOKEN}${NC}"
echo -e "${BOLD}▶ 当前版本:${NC} ${LATEST_VERSION}"
echo -e "--------------------------------------------------------"
echo -e "${BOLD}后续关键操作：${NC}"
echo -e " 1. 浏览器打开页面并使用令牌登录"
echo -e " 2. 在终端执行: ${BOLD}openclaw devices list${NC}"
echo -e " 3. 执行授权:   ${BOLD}openclaw devices approve <ID>${NC}"
echo -e "${GREEN}${BOLD}========================================================${NC}\n"
