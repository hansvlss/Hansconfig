#!/bin/bash

# =================================================================
# OpenClaw Pro - Master Edition (2026.03.08)
# 修正：精准路径验证 & 自动权限预备
# =================================================================

export TERM=xterm-256color
G_BOLD="\033[1;32m"  # 经典粗体绿
G_NORM="\033[0;32m"  # 常规绿
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

CHECK="${G_BOLD}✔${NC}"
STEP="${G_BOLD}➤${NC}"

error_exit() {
    echo -e "\n${RED}[系统中断]: $1${NC}"
    echo -e "${YELLOW}解决方案: $2${NC}"
    exit 1
}

print_step() { echo -ne "${STEP} ${G_NORM}$1...${NC}"; }
print_ok() { echo -e " [ ${CHECK} ]"; }

clear
echo -e "${G_BOLD}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. 环境清理
print_step "正在执行环境深度净化"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
rm -rf ~/.openclaw/openclaw.json*
print_ok

# 2. 信息检索
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && error_exit "无法抓取 IP" "检查网络"

# 3. 安装流程
print_step "同步 Node.js 22 LTS 与系统组件"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs nginx curl > /dev/null 2>&1
print_ok

print_step "安装 OpenClaw 核心程序"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
print_ok

# 4. 写入配置
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
      "allowedOrigins": ["https://${USER_IP}:8888", "https://127.0.0.1:8888", "http://localhost:18789"]
    }
  }
}
EOF
print_ok

# 5. Nginx SSL
print_step "构建 SSL 安全加密隧道"
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1

cat > /etc/nginx/sites-enabled/default <<EOF
server {
    listen 8888 ssl;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host localhost;
        proxy_set_header Origin http://localhost:18789;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
systemctl restart nginx > /dev/null 2>&1
print_ok

# 6. 精准关联验证
print_step "启动后端并关联 Nginx 隧道"
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
for i in {1..20}; do
    # 修改验证方式：直接探测 HTTP 状态码，只要 Nginx 能转发请求即为成功
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k https://127.0.0.1:8888/__openclaw__/canvas/)
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "101" ]; then
        V_DONE=1
        break
    fi
    systemctl restart nginx > /dev/null 2>&1
    echo -ne "\r${STEP} ${G_NORM}等待后端响应中... ($i/20)${NC}"
    sleep 3
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\r${STEP} ${G_NORM}隧道最终关联验证成功！${NC} [ ${CHECK} ]"
else
    error_exit "握手超时" "后端已启动但 Nginx 无法访问。请尝试手动运行: systemctl restart nginx"
fi

# 7. 结果面板
echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
echo -e "│                部署成功 / DEPLOYMENT SUCCESS               │"
echo -e "└────────────────────────────────────────────────────────────┘${NC}"
echo -e "${G_NORM}${BOLD}▶ 地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
echo -e "${G_NORM}${BOLD}▶ 令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
echo -e "${G_NORM}--------------------------------------------------------------"
echo -e "${G_BOLD}现在请执行以下操作完成授权：${NC}"
echo -e " 1. 浏览器访问上方地址，输入令牌后点击连接"
echo -e " 2. 回到此终端查看待批准设备："
openclaw devices list | grep -A 5 "Pending"
echo -e " 3. 执行: ${G_BOLD}openclaw devices approve <ID>${NC}"
echo -e "${G_BOLD}==============================================================${NC}\n"
