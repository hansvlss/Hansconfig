#!/bin/bash

# =================================================================
# OpenClaw Pro - Ultimate Rigorous Edition (2026.03.08)
# 核心：物理路径强制探测 + 暴力端口释放
# =================================================================

export TERM=xterm-256color
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 显示函数
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

# 2. 暴力环境清理
print_step "清理残留进程与占用端口"
apt update > /dev/null 2>&1
apt install -y psmisc curl gnupg ca-certificates nginx nodejs > /dev/null 2>&1
killall -9 node openclaw nginx 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
rm -rf ~/.openclaw/openclaw.json*
print_ok

# 3. 强制重新安装并锁定位置
print_step "拉取最新版 OpenClaw 并探测物理路径"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1

# 关键：手动定位物理路径，绕过环境变量问题
SEARCH_BIN=$(npm config get prefix)"/bin/openclaw"
if [ ! -f "$SEARCH_BIN" ]; then
    SEARCH_BIN=$(which openclaw 2>/dev/null)
fi
if [ -z "$SEARCH_BIN" ]; then
    SEARCH_BIN="/usr/local/bin/openclaw"
fi
print_ok

# 4. 写入配置 (Hans 稳健版逻辑)
print_step "注入加密令牌与反代白名单"
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

# 5. 构建 Nginx 隧道 (暴力覆盖)
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
print_ok

# 6. 最终拉起 (使用绝对路径)
print_step "正在以物理路径拉起后端进程"
# 用探测到的绝对路径启动，防止 command not found
$SEARCH_BIN gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

V_DONE=0
for i in {1..20}; do
    # 只要 18789 端口在监听，就说明后端活了
    if ss -lntp | grep -q ":18789" > /dev/null; then
        # 强制重启 Nginx
        systemctl restart nginx || /usr/sbin/nginx
        V_DONE=1
        break
    fi
    echo -ne "\r等待后端响应中... ($i/20)"
    sleep 3
done

if [ "$V_DONE" == "1" ]; then
    echo -e " [ ${CHECK} ]"
    echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT SUCCESS               │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo -e "${G_NORM}${BOLD}▶ 访问地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
    echo -e "${G_NORM}${BOLD}▶ 登录令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
    echo -e "${G_NORM}--------------------------------------------------------------"
    echo -e "请直接访问地址并登录。${G_BOLD}Hans 祝你部署顺利！${NC}"
    echo -e "${G_BOLD}==============================================================${NC}\n"
else
    error_exit "网关启动超时" "请手动执行: cat /tmp/openclaw.log 看看具体报错。"
fi
