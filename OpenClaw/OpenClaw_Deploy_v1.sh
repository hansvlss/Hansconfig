#!/bin/bash

# =================================================================
# OpenClaw Pro - Ultimate Rigorous Edition (2026)
# Optimization: Auto-Handshake & Trusted Proxy Setup
# Designed for Hans (hanscn.com)
# =================================================================

# 1. 颜色与专业图标定义 (更深邃、更专业的色彩体系)
export TERM=xterm-256color
CHECK="\033[0;32m\xE2\x9C\x94\033[0m"      # 绿色对勾
CROSS="\033[0;31m\xE2\x9C\x98\033[0m"      # 红色叉号
STEP="\033[1;34m\xE2\x9E\x9C\033[0m"       # 蓝色箭头
BOLD="\033[1m"
RED="\033[38;5;196m"
GREEN="\033[38;5;46m"
YELLOW="\033[38;5;226m"
BLUE="\033[38;5;39m"
PURPLE="\033[38;5;129m"
CYAN="\033[38;5;51m"
NC="\033[0m"

# 错误处理函数 (严谨中断)
error_exit() {
    echo -e "\n${CROSS} ${RED}${BOLD}部署中断: $1${NC}"
    echo -e "${YELLOW}诊断建议: $2${NC}"
    echo -e "------------------------------------------------"
    exit 1
}

# 状态显示函数
print_step() { echo -ne "${STEP} ${BOLD}${CYAN}$1...${NC}"; }
print_ok() { echo -e " [ ${CHECK} ]"; }

clear
echo -e "${PURPLE}${BOLD}=================================================================="
echo -e "       OPENCLAW GATEWAY PRO INSTALLER (ULTIMATE EDITION)"
echo -e "==================================================================${NC}"

# 1. 系统环境检索
print_step "正在检索系统网络架构"
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && error_exit "无法抓取内网 IP" "请检查 PVE 网络配置。"
print_ok

# 2. 云端版本嗅探
print_step "正在探测云端最新发行版"
LATEST_VERSION=$(curl -s https://registry.npmmirror.com/openclaw/latest | sed 's/.*"version":"\([^"]*\)".*/\1/')
[ -z "$LATEST_VERSION" ] && LATEST_VERSION="latest"
print_ok
echo -e "${BLUE}${BOLD}▶ 准备部署版本:${NC} ${YELLOW}v${LATEST_VERSION}${NC}"

# 3. 核心依赖部署
print_step "配置 Node.js 22 LTS 运行环境"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl > /dev/null 2>&1
print_ok

print_step "从镜像站拉取并安装 OpenClaw"
npm install -g openclaw@${LATEST_VERSION} --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
print_ok

# 4. 安全配置 (修复 Origin Not Allowed)
print_step "正在生成加密令牌与代理信任配置"
DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
rm -f ~/.openclaw/openclaw.json*
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "trustedProxies": ["127.0.0.1", "::1"],
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
print_ok

# 5. SSL 加密隧道构建
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

# 6. 唤醒网关与真实连通性握手
print_step "唤醒后端进程并关联 Nginx"
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
# 执行 30 次深度握手探测
for i in {1..30}; do
    # 模拟浏览器发起真实的 HTTPS 请求测试连通性
    if curl -s -k --connect-timeout 2 https://127.0.0.1:8888 | grep -q "OpenClaw" > /dev/null; then
        V_DONE=1
        break
    else
        # 如果 502，尝试重启 Nginx 建立握手
        systemctl restart nginx > /dev/null 2>&1
    fi
    echo -ne "\r${STEP} ${BOLD}${CYAN}正在执行 Nginx 隧道最终关联... ($i/30)${NC}"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\r${STEP} ${BOLD}${CYAN}正在执行 Nginx 隧道最终关联...${NC} [ ${CHECK} ]"
else
    error_exit "Nginx 隧道握手超时" "请运行 cat /tmp/openclaw.log 检查后端是否启动成功。"
fi

# 7. 终极 Dashboard 报告 (专业 UI 展示)
echo -e "\n${GREEN}${BOLD}┌────────────────────────────────────────────────────────────┐"
echo -e "│                部署成功 / DEPLOYMENT SUCCESS               │"
echo -e "└────────────────────────────────────────────────────────────┘${NC}"
echo -e "${BOLD}▶ 访问地址:${NC} ${BLUE}https://${USER_IP}:8888${NC}"
echo -e "${BOLD}▶ 登录令牌:${NC} ${YELLOW}${DYNAMIC_TOKEN}${NC}"
echo -e "${BOLD}▶ 软件版本:${NC} ${LATEST_VERSION}"
echo -e "${CYAN}--------------------------------------------------------------${NC}"
echo -e "${BOLD}请按以下步骤完成最终授权：${NC}"
echo -e " 1. 刷新浏览器并输入上方令牌登录"
echo -e " 2. 在终端执行: ${BOLD}openclaw devices list${NC}"
echo -e " 3. 执行授权:   ${BOLD}openclaw devices approve <ID>${NC}"
echo -e "${GREEN}${BOLD}==============================================================${NC}\n"
