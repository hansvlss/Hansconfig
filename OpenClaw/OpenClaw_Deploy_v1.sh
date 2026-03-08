#!/bin/bash

# =================================================================
# OpenClaw Pro - Professional UI Edition (2026.03.08)
# 特点：动态交互反馈、重感图标、核心逻辑 100% 保持 Hans 原版
# =================================================================

# 1. 颜色与重感符号定义
TITLE_G="\033[1;32m"   # 加粗亮绿
STEP_W="\033[0;37m"    # 常规白色
INFO_Y="\033[1;33m"    # 加粗黄色
RED_B="\033[1;31m"     # 加粗红色
NC="\033[0m"           # 重置颜色

CHECK=" ${TITLE_G}✔${NC} "
CROSS=" ${RED_B}✘${NC} "
ARROW="${TITLE_G} ➤ ${NC}"

check_step() {
    if [ $? -ne 0 ]; then
        echo -e "\n${RED_B}[${CROSS}错误] $1 失败了！${NC}"
        echo -e "${RED_B}建议检查：$2${NC}"
        exit 1
    fi
}

clear
echo -e "${TITLE_G}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"
echo ""

# 1. 网络检测阶段
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${INFO_Y}[网络状态]${NC} 当前检测到本地 IP: ${TITLE_G}${USER_IP}${NC}"
echo -e "${STEP_W}------------------------------------------------------------------${NC}"
echo ""

# 2. 初始化系统环境
printf "${ARROW}${STEP_W}初始化系统环境与核心组件...${NC}"
(
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
    apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl psmisc > /dev/null 2>&1
) &
pid=$!
# 动态加载点效果，解决卡死感
while kill -0 $pid 2>/dev/null; do
    printf "${TITLE_G}.${NC}"
    sleep 1
done
wait $pid
if [ $? -eq 0 ]; then printf "\r${ARROW}${STEP_W}初始化系统环境与核心组件...${NC} [${CHECK}]\n"; else printf "\r${ARROW}${STEP_W}初始化系统环境与核心组件...${NC} [${CROSS}]\n"; exit 1; fi
echo ""

# 3. 部署 OpenClaw 核心网关
printf "${ARROW}${STEP_W}部署 OpenClaw 核心网关程序...${NC}"
(
    npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
    hash -r
    ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null
) &
pid=$!
while kill -0 $pid 2>/dev/null; do
    printf "${TITLE_G}.${NC}"
    sleep 1
done
wait $pid
if [ $? -eq 0 ]; then printf "\r${ARROW}${STEP_W}部署 OpenClaw 核心网关程序...${NC} [${CHECK}]\n"; else printf "\r${ARROW}${STEP_W}部署 OpenClaw 核心网关程序...${NC} [${CROSS}]\n"; exit 1; fi
echo ""

# 4. 生成安全配置文件
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
echo -e "${ARROW}${STEP_W}生成安全实例配置文件...${NC} [${CHECK}]"
echo ""

# 5. 构建 SSL 反向代理
printf "${ARROW}${STEP_W}构建 Nginx SSL 安全反向代理...${NC}"
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
printf " [${CHECK}]\n"
echo ""

# 6. 实例化后端服务
echo -e "${ARROW}${STEP_W}实例化 OpenClaw 后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true 

OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &
echo ""

# 7. 状态同步检测
V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e ""
        echo -e "${ARROW}${STEP_W}同步后端状态并激活流量转发...${NC} [${CHECK}]"
        /usr/sbin/nginx -s reload 2>/dev/null || systemctl restart nginx
        V_DONE=1
        break
    fi
    printf "\r${ARROW}${STEP_W}执行网关健康状态同步检测... ($i/20)${NC}"
    sleep 2
done

# 8. 成功面板
if [ "$V_DONE" == "1" ]; then
    echo ""
    echo -e "${TITLE_G}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT READY                 │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${STEP_W}  ▶ 访问地址:${NC} ${TITLE_G}https://${USER_IP}:8888${NC}"
    echo -e "${STEP_W}  ▶ 登录令牌:${NC} ${TITLE_G}${DYNAMIC_TOKEN}${NC}"
    echo ""
    echo -e "${STEP_W}  ----------------------------------------------------------${NC}"
    echo -e "  授权指令: ${TITLE_G}openclaw devices approve <ID>${NC}"
    echo -e "${TITLE_G}==============================================================${NC}\n"
else
    systemctl restart nginx || /usr/sbin/nginx
    echo -e ""
    echo -e "${RED_B}[${CROSS}警告] 网关响应超时，请访问面板手动刷新。${NC}"
fi
