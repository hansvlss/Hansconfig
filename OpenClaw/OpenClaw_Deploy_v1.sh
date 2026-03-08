#!/bin/bash

# =================================================================
# OpenClaw Pro - Dynamic UI Edition (2026.03.08)
# 特点：动态跳动进度条、重感图标、核心逻辑 100% 保持 Hans 原版
# =================================================================

# 1. 颜色与重感符号定义
TITLE_G="\033[1;32m"   # 加粗亮绿
STEP_W="\033[0;37m"    # 常规白色
INFO_Y="\033[1;33m"    # 加粗黄色
RED_B="\033[1;31m"     # 加粗红色
NC="\033[0m"           # 重置颜色

# 增强版图标
CHECK=" ${TITLE_G}✔${NC} "
CROSS=" ${RED_B}✘${NC} "
ARROW="${TITLE_G} ● ${NC}"  # 按照你的样式改为圆点

# 2. 核心：动态跳动显示函数 (仅修改 UI 展示方式)
run_with_dots() {
    local message=$1
    local cmd=$2
    printf "${ARROW}${STEP_W}${message}${NC}"
    eval "$cmd" > /dev/null 2>&1 &
    local pid=$!
    local dots=""
    while kill -0 $pid 2>/dev/null; do
        dots="${dots}."
        if [ ${#dots} -gt 3 ]; then dots=""; fi
        # 使用 \r 覆盖当前行末尾，实现原地跳动
        printf "\r${ARROW}${STEP_W}${message}%-3s${NC}" "$dots"
        sleep 0.5
    done
    wait $pid
    if [ $? -eq 0 ]; then
        printf "\r${ARROW}${STEP_W}${message} ...${NC} [ ${TITLE_G}完成${NC} ]\n"
    else
        printf "\r${ARROW}${STEP_W}${message} ...${NC} [ ${RED_B}失败${NC} ]\n"
        exit 1
    fi
}

check_step() {
    if [ $? -ne 0 ]; then
        echo -e "\n${RED_B}[${CROSS}错误] $1 失败了！${NC}"
        echo -e "${RED_B}建议检查：$2${NC}"
        exit 1
    fi
}

clear
echo -e "${TITLE_G}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署 system (2026)"
echo -e "==================================================================${NC}"
echo ""

# 0. 系统准入检查模块
echo -ne "${ARROW}${STEP_W}正在校验操作系统兼容性...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS=$(uname -s)
fi

# 只允许 debian 和 ubuntu 运行
if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    echo -e " [ ${TITLE_G}通过: ${NAME}${NC} ]"
else
    echo -e " [ ${RED_B}拒绝: ${OS}${NC} ]"
    echo -e "\n${RED_B}--------------------------------------------------------------"
    echo -e "[致命错误] 当前脚本仅支持 Debian 或 Ubuntu 系统！"
    echo -e "检测到系统为: ${OS}，为了安全，脚本已自动停止。"
    echo -e "--------------------------------------------------------------${NC}"
    exit 1
fi
echo ""

# 1. 网络检测阶段
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${INFO_Y}[网络状态]${NC} 当前检测到本地 IP: ${TITLE_G}${USER_IP}${NC}"
echo -e "${STEP_W}------------------------------------------------------------------${NC}"
echo ""

# 2. 安装准备阶段
run_with_dots "初始化系统环境与核心组件" "curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && apt update && apt install -y nodejs git build-essential nginx curl psmisc"
echo ""

# 3. 程序安装阶段
run_with_dots "部署OpenClaw核心网关程序" "npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com && hash -r && ln -sf \$(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw"
echo ""

# 4. 配置生成阶段
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
echo -e "${ARROW}${STEP_W}生成安全实例配置文件 ...${NC} [ ${TITLE_G}完成${NC} ]"
echo ""

# 5. Nginx 配置阶段
echo -ne "${ARROW}${STEP_W}构建 Nginx SSL 安全反向代理 ...${NC}"
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
echo -e " [ ${TITLE_G}完成${NC} ]"
echo ""

# 6. 后端启动阶段
echo -e "${ARROW}${STEP_W}正在唤醒 实例化 OpenClaw 后端服务 ...${NC} [ ${TITLE_G}完成${NC} ]"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true 

OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &
echo ""

# 7. 探测阶段
V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e ""
        echo -e "${ARROW}${STEP_W}同步后端状态并激活流量转发 ...${NC} [ ${TITLE_G}完成${NC} ]"
        /usr/sbin/nginx -s reload 2>/dev/null || systemctl restart nginx
        V_DONE=1
        break
    fi
    echo -ne "\r${ARROW}${STEP_W}执行网关健康状态同步检测 ... ($i/20)${NC}"
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
    echo -e "${RED_B}[${CROSS}警告] 响应缓慢，如遇 502 请稍后手动刷新尝试。${NC}"
fi
