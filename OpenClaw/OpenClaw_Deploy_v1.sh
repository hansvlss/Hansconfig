#!/bin/bash

# =================================================================
# OpenClaw Pro - Professional High-Contrast UI (2026.03.08)
# 特点：高对比度配色、失败必红、核心逻辑 0 改动
# =================================================================

# 重新定义更符合人体工程学的配色
TITLE_G="\033[1;32m"   # 加粗绿 (用于标题和成功勾选)
STEP_W="\033[0;37m"    # 常规白 (用于正文步骤，不累眼)
INFO_Y="\033[1;33m"    # 加粗黄 (用于重要提示)
RED_B="\033[1;31m"     # 加粗红 (故障专用)
NC="\033[0m"           # 重置

CHECK="${TITLE_G}✔${NC}"
CROSS="${RED_B}✘${NC}"

# 报错函数：保持失败变红逻辑
report_status() {
    if [ $? -eq 0 ]; then
        echo -e " [ ${CHECK} ]"
    else
        echo -e " [ ${CROSS} ]"
        echo -e "${RED_B}--------------------------------------------------------------"
        echo -e "[致命错误] $1 失败了！"
        echo -e "排查建议: $2${NC}"
        echo -e "${RED_B}--------------------------------------------------------------${NC}"
        exit 1
    fi
}

clear
echo -e "${TITLE_G}=================================================================="
echo -e "            OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. IP 获取
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${INFO_Y}[网络状态]${NC} 当前检测到 IP: ${USER_IP}"

# 2. 安装环境 (正文用白色，结果用绿色)
echo -ne "${STEP_W}➤ 正在配置环境与安装必备工具...${NC}"
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl psmisc > /dev/null 2>&1
report_status "基础环境安装" "请检查网络或 APT 源"

# 3. 安装程序 (核心逻辑保持 1.81 节点稳健版)
echo -ne "${STEP_W}➤ 正在尝试从镜像站拉取 OpenClaw 程序...${NC}"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
hash -r
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null
report_status "OpenClaw 程序下载" "请检查 NPM 镜像站连通性"

# 4. 生成配置
echo -ne "${STEP_W}➤ 正在生成加密令牌与反代白名单...${NC}"
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
report_status "配置文件生成" "权限检查"

# 5. SSL & Nginx
echo -ne "${STEP_W}➤ 正在构建 SSL 安全加密隧道...${NC}"
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
nginx -t > /dev/null 2>&1
report_status "Nginx SSL 配置" "检查 SSL 证书"

# 6. 后端启动
echo -e "${STEP_W}➤ 正在唤醒 OpenClaw 后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true 
OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 7. 最终探测
V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${STEP_W}➤ 网关后端已就绪，激活隧道...${NC} [ ${CHECK} ]"
        /usr/sbin/nginx -s reload 2>/dev/null || systemctl restart nginx
        V_DONE=1
        break
    fi
    echo -ne "\r${STEP_W}正在同步网关状态... ($i/20)${NC}"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\n${TITLE_G}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT READY                 │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo -e "${STEP_W}▶ 访问地址:${NC} ${TITLE_G}https://${USER_IP}:8888${NC}"
    echo -e "${STEP_W}▶ 登录令牌:${NC} ${TITLE_G}${DYNAMIC_TOKEN}${NC}"
    echo -e "${STEP_W}--------------------------------------------------------------"
    echo -e "授权指令: ${TITLE_G}openclaw devices approve <ID>${NC}"
    echo -e "${TITLE_G}==============================================================${NC}\n"
else
    echo -e "${RED_B}[警告] 网关响应超时，请检查 18789 端口。${NC}"
fi
