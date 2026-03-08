#!/bin/bash

# =================================================================
# OpenClaw Pro - Professional UI Edition (2026.03.08)
# 特点：动态安装进度、专业视觉反馈、Hans 稳健核心逻辑
# =================================================================

# 定义专业终端配色
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 动态进度显示函数：消除卡死感
show_progress() {
    local pid=$1
    local message=$2
    local delay=0.5
    local dots=""
    while [ "$(ps -p $pid -o state= 2>/dev/null)" ]; do
        dots="${dots}."
        if [ ${#dots} -gt 3 ]; then dots=""; fi
        printf "\r${G_NORM}➤ ${message}%-3s${NC}" "$dots"
        sleep $delay
    done
    printf "\r${G_NORM}➤ ${message}...${NC} [ ${G_BOLD}✔${NC} ]\n"
}

check_step() {
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}[错误] $1 失败了！${NC}"
        echo -e "${YELLOW}建议检查：$2${NC}"
        exit 1
    fi
}

clear
echo -e "${G_BOLD}=================================================================="
echo -e "            OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. IP 获取
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${G_BOLD}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 安装环境 (增加动态进度)
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl psmisc > /dev/null 2>&1 &
show_progress $! "正在配置环境与安装必备工具"

# 3. 安装程序 (官方优先/镜像兜底 + 强制路径)
echo -ne "${G_NORM}➤ 正在尝试从官方源拉取最新 OpenClaw...${NC}"
npm install -g openclaw@latest --unsafe-perm --force --prefer-online > /dev/null 2>&1 &
pid=$!
while [ "$(ps -p $pid -o state= 2>/dev/null)" ]; do sleep 1; done
if [ $? -ne 0 ]; then
    printf "\r${G_NORM}➤ 官方源超时，切换镜像站兜底...${NC}"
    npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1 &
    show_progress $! "正在从镜像站同步 OpenClaw"
else
    printf " [ ${G_BOLD}✔${NC} ]\n"
fi

# 关键：路径自愈
hash -r
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null

# 4. 写入配置
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
echo -e "${G_NORM}➤ 注入加密令牌与反代白名单...${NC} [ ${G_BOLD}✔${NC} ]"

# 5. SSL & Nginx 隧道 (增加动态显示)
printf "${G_NORM}➤ 正在构建 SSL 安全加密隧道...${NC}"
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
printf " [ ${G_BOLD}✔${NC} ]\n"

# 6. 后端启动 (核心修正版逻辑)
echo -e "${G_NORM}➤ 正在唤醒 OpenClaw 后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true 

OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 7. 最终关联检测
V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${G_NORM}➤ 网关后端已就绪，正在激活 Nginx 隧道...${NC} [ ${G_BOLD}✔${NC} ]"
        killall -9 nginx 2>/dev/null || true
        /usr/sbin/nginx || systemctl restart nginx
        V_DONE=1
        break
    fi
    printf "\r${G_NORM}➤ 等待后端响应中... ($i/20)${NC}"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT READY                 │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo -e "${G_NORM}${G_BOLD}▶ 访问地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
    echo -e "${G_NORM}${G_BOLD}▶ 登录令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
    echo -e "${G_NORM}--------------------------------------------------------------"
    echo -e "授权指令 (请复制执行): ${G_BOLD}openclaw devices approve <ID>${NC}"
    echo -e "${G_BOLD}==============================================================${NC}\n"
else
    # 失败兜底
    killall -9 nginx 2>/dev/null || true
    /usr/sbin/nginx
    echo -e "${RED}[警告] 启动缓慢，请访问地址手动刷新。${NC}"
fi
