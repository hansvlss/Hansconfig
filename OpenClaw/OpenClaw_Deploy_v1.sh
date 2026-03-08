#!/bin/bash

# =================================================================
# OpenClaw Pro - Master Edition (2026)
# 风格：经典黑客绿 & 严谨逻辑
# =================================================================

# 1. 颜色与图标定义 (经典绿色体系)
export TERM=xterm-256color
G_BOLD="\033[1;32m"  # 粗体绿
G_NORM="\033[0;32m"  # 常规绿
RED="\033[0;31m"     # 错误红
YELLOW="\033[1;33m"  # 警告黄
NC="\033[0m"         # 重置

CHECK="${G_BOLD}✔${NC}"
STEP="${G_BOLD}➤${NC}"

# 错误处理函数
error_exit() {
    echo -e "\n${RED}[部署中断]: $1${NC}"
    echo -e "${YELLOW}建议方案: $2${NC}"
    echo -e "------------------------------------------------"
    exit 1
}

print_step() { echo -ne "${STEP} ${G_NORM}$1...${NC}"; }
print_ok() { echo -e " [ ${CHECK} ]"; }

clear
echo -e "${G_BOLD}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. 环境深度清理 (解决超时关键)
print_step "正在执行环境深度净化 (清理残留进程)"
killall -9 openclaw 2>/dev/null || true
# 强行释放端口占用
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
rm -rf ~/.openclaw/openclaw.json*
print_ok

# 2. 系统信息检索
print_step "正在检索系统网络架构"
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && error_exit "无法抓取内网 IP" "请检查 PVE 网络配置。"
print_ok

# 3. 核心依赖安装
print_step "配置 Node.js 22 LTS 运行环境"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl > /dev/null 2>&1
print_ok

print_step "正在同步云端 OpenClaw 核心程序"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
print_ok

# 4. 安全配置 (解决 Origin Not Allowed)
print_step "正在注入加密令牌与代理信任配置"
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
      "allowedOrigins": [
        "https://${USER_IP}:8888",
        "https://127.0.0.1:8888"
      ]
    }
  }
}
EOF
print_ok

# 5. SSL & Nginx 隧道构建
print_step "正在构建 SSL 安全加密隧道"
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
systemctl restart nginx > /dev/null 2>&1
print_ok

# 6. 最终关联验证 (3秒间隔，确保稳定)
print_step "唤醒后端进程并执行隧道握手"
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
for i in {1..20}; do
    # 模拟真实 HTTPS 请求探测
    if curl -s -k --connect-timeout 2 https://127.0.0.1:8888 | grep -q "OpenClaw" > /dev/null; then
        V_DONE=1
        break
    else
        systemctl restart nginx > /dev/null 2>&1
        echo -ne "\r${STEP} ${G_NORM}等待后端响应中... ($i/20)${NC}"
        sleep 3
    fi
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\r${STEP} ${G_NORM}隧道最终关联验证成功！${NC} [ ${CHECK} ]"
else
    error_exit "隧道握手超时" "请运行 cat /tmp/openclaw.log 检查后端是否启动成功。"
fi

# 7. 终极 Dashboard 报告 (经典绿色)
echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
echo -e "│                部署成功 / DEPLOYMENT SUCCESS               │"
echo -e "└────────────────────────────────────────────────────────────┘${NC}"
echo -e "${G_NORM}${BOLD}▶ 访问地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
echo -e "${G_NORM}${BOLD}▶ 登录令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
echo -e "${G_NORM}--------------------------------------------------------------"
echo -e "${G_BOLD}后续关键操作：${NC}"
echo -e " 1. 刷新浏览器并输入上方令牌登录"
echo -e " 2. 在终端执行: ${G_BOLD}openclaw devices list${NC}"
echo -e " 3. 执行授权:   ${G_BOLD}openclaw devices approve <ID>${NC}"
echo -e "${G_BOLD}==============================================================${NC}\n"
