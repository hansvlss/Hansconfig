#!/bin/bash
# =================================================================
# OpenClaw 2026 官方版 (全 Root 模式 - 彻底告别权限问题)
# =================================================================

TITLE_G="\033[1;32m"
STEP_W="\033[0;37m"
NC="\033[0m"
ARROW="${TITLE_G} ● ${NC}" 

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
        printf "\r${ARROW}${STEP_W}${message}%-3s${NC}" "$dots"
        sleep 0.5
    done
    wait $pid
    if [ $? -eq 0 ]; then
        printf "\r${ARROW}${STEP_W}${message} ...${NC} [ ${TITLE_G}完成${NC} ]\n"
    else
        printf "\r${ARROW}${STEP_W}${message} ...${NC} [ \033[1;31m失败\033[0m ]\n"
        exit 1
    fi
}

# 预设 Token
CLAW_TOKEN=$(openssl rand -hex 16)

# 自动获取当前环境代理
CURRENT_PROXY=$(env | grep -iE '^http_proxy=|^https_proxy=' | head -1 | cut -d'=' -f2)
if [[ "$CURRENT_PROXY" == *"PROXY_IP"* ]]; then
    PROXY_IP=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_IP:-")[^"]+')
    PROXY_PORT=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_PORT:-")[^"]+')
    CURRENT_PROXY="http://${PROXY_IP}:${PROXY_PORT}"
fi

echo -e "\n${TITLE_G}=================================================================="
echo -e "           🦞 OpenClaw 网关自动部署 (Root 纯净模式)"
echo -e "==================================================================${NC}\n"

# 1. 基础环境安装
run_with_dots "正在同步系统仓库" "apt update -y"
run_with_dots "正在配置 NodeSource 22 官方源" "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"
run_with_dots "正在安装 Node.js 22 & 基础组件" "apt install -y nodejs git build-essential psmisc openssl"

# 2. OpenClaw 安装 (直接由 Root 执行)
echo -ne "${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (Root 模式)...${NC}"

# 注入代理并安装
(
    if [ ! -z "$CURRENT_PROXY" ]; then
        export HTTP_PROXY="$CURRENT_PROXY"
        export HTTPS_PROXY="$CURRENT_PROXY"
        npm config set proxy "$CURRENT_PROXY"
        npm config set https-proxy "$CURRENT_PROXY"
    fi
    npm install -g openclaw@latest --unsafe-perm --registry=https://registry.npmjs.org --silent > /dev/null 2>&1
) &

# 进度条逻辑
NPMPID=$!
while kill -0 $NPMPID 2>/dev/null; do
    for i in "/" "-" "\\" "|"; do
        printf "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (Root 模式)... [ $i ]${NC}"
        sleep 0.2
    done
done
wait $NPMPID
echo -e "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (Root 模式) ...${NC} [ ${TITLE_G}完成${NC} ]"

# 3. 初始化配置 (直接在 /root 下)
run_with_dots "正在初始化网关配置" "
    # 清理旧的残余配置
    rm -rf /root/.openclaw
    # 初始化
    printf 'y\n' | openclaw onboard
    openclaw config set gateway.mode local
    openclaw config set gateway.port 18789
    openclaw config set gateway.bind loopback
    openclaw config set gateway.auth.token $CLAW_TOKEN
"

# 4. 创建 Systemd 服务 (使用 Root 身份运行)
run_with_dots "正在配置后台守护进程" "
cat << SERVICE > /etc/systemd/system/openclaw.service
[Unit]
Description=OpenClaw Gateway (Root Mode)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=$(which openclaw) gateway
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now openclaw
"

# 5. 结算单准备
IP_ADDR=$(hostname -I | awk '{print $1}')
REAL_TOKEN=$(grep -oP '"token":\s*"\K[^"]+' /root/.openclaw/openclaw.json)

# 6. 打印结算单 (保留 Hans 原创格式)
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m           🦞 OpenClaw 2026 部署成功 (Root 暴力版) \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "    运行身份: \033[1;37mRoot\033[0m  (不再有权限烦恼)"
echo -e ""
echo -e "\033[1;33m[1. SSH 隧道指令]\033[0m"
echo -e "    \033[1;37mssh -N -L 18789:127.0.0.1:18789 root@$IP_ADDR\033[0m"
echo -e ""
echo -e "\033[1;33m[2. Dashboard 浏览器访问]\033[0m"
echo -e "    \033[1;36mhttp://localhost:18789/#token=$REAL_TOKEN\033[0m"
echo -e ""
echo "🚀 管理命令: openclaw configure (实时生效)"
echo "🚀 重启服务: systemctl restart openclaw"
echo ""
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "    更多教程: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 分享\033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
