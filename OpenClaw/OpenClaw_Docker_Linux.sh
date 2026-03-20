#!/bin/bash
# =================================================================
# OpenClaw 2026 官方版 (Claw 进门 + Root 运行版)
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

# 预设参数
CLAW_USER="claw"
CLAW_PASS="claw"
CLAW_TOKEN=$(openssl rand -hex 16)

# 自动获取当前环境代理
CURRENT_PROXY=$(env | grep -iE '^http_proxy=|^https_proxy=' | head -1 | cut -d'=' -f2)
if [[ "$CURRENT_PROXY" == *"PROXY_IP"* ]]; then
    PROXY_IP=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_IP:-")[^"]+')
    PROXY_PORT=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_PORT:-")[^"]+')
    CURRENT_PROXY="http://${PROXY_IP}:${PROXY_PORT}"
fi

echo -e "\n${TITLE_G}=================================================================="
echo -e "           🦞 OpenClaw 网关自动部署 (SSH 兼容隔离版)"
echo -e "==================================================================${NC}\n"

# 1. 基础环境安装
run_with_dots "正在同步系统仓库" "apt update -y"
run_with_dots "正在配置 NodeSource 22 官方源" "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"
run_with_dots "正在安装 Node.js 22 & 基础组件" "apt install -y nodejs git build-essential psmisc openssl sudo"

# 2. 🛡️ 创建 SSH 专用用户并开启权限
run_with_dots "正在配置 SSH 登录用户 (claw)" "
    # 创建用户并设密码
    if ! id $CLAW_USER &>/dev/null; then
        useradd -m -s /bin/bash $CLAW_USER
    fi
    echo \"$CLAW_USER:$CLAW_PASS\" | chpasswd
    
    # 赋予 sudo 权限 (方便登录后 sudo -i)
    echo '$CLAW_USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-openclaw
    
    # 强制开启 SSH 密码登录
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart ssh
"

# 3. OpenClaw 安装 (直接由 Root 执行)
echo -ne "${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (Root 核心)...${NC}"
(
    if [ ! -z "$CURRENT_PROXY" ]; then
        export HTTP_PROXY="$CURRENT_PROXY"
        export HTTPS_PROXY="$CURRENT_PROXY"
        npm config set proxy "$CURRENT_PROXY"
        npm config set https-proxy "$CURRENT_PROXY"
    fi
    npm install -g openclaw@latest --unsafe-perm --registry=https://registry.npmjs.org --silent > /dev/null 2>&1
) &

NPMPID=$!
while kill -0 $NPMPID 2>/dev/null; do
    for i in "/" "-" "\\" "|"; do
        printf "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (Root 核心)... [ $i ]${NC}"
        sleep 0.2
    done
done
wait $NPMPID
echo -e "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (Root 核心) ...${NC} [ ${TITLE_G}完成${NC} ]"

# 4. 初始化配置 (直接在 /root 下)
run_with_dots "正在初始化网关配置" "
    rm -rf /root/.openclaw
    printf 'y\n' | openclaw onboard
    openclaw config set gateway.mode local
    openclaw config set gateway.port 18789
    openclaw config set gateway.bind loopback
    openclaw config set gateway.auth.token $CLAW_TOKEN
"

# 5. 创建 Systemd 服务 (使用 Root 身份运行)
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

# 6. 结算单准备
IP_ADDR=$(hostname -I | awk '{print $1}')
REAL_TOKEN=$(grep -oP '"token":\s*"\K[^"]+' /root/.openclaw/openclaw.json)

# 7. 打印结算单 (Hans 原创格式)
# echo -e "\n\033[1;34m==================================================================\033[0m"
# echo -e "\033[1;32m           🦞 OpenClaw 2026 部署成功 (SSH 安全增强版) \033[0m"
# echo -e "\033[1;34m==================================================================\033[0m"
# echo -e ""
# echo -e "    SSH 用户: \033[1;37m$CLAW_USER\033[0m  密码: \033[1;32m$CLAW_PASS\033[0m"
# echo -e "    运行身份: \033[1;37mRoot\033[0m (配置文件在 /root/.openclaw)"
# echo -e ""
# echo -e "\033[1;33m[1. SSH 隧道指令 (在 Mac 执行)]\033[0m"
# echo -e "    \033[1;37mssh -N -L 18789:127.0.0.1:18789 $CLAW_USER@$IP_ADDR\033[0m"
# echo -e ""
# echo -e "\033[1;33m[2. Dashboard 浏览器访问]\033[0m"
# echo -e "    \033[1;36mhttp://localhost:18789/#token=$REAL_TOKEN\033[0m"
# echo -e ""
# echo "🚀 维护技巧: SSH 进去后敲 'sudo -i' 即可获得最高管理权限"
# echo "🚀 管理命令: openclaw configure"
# echo ""
# echo -e "\033[1;34m==================================================================\033[0m"
# echo -e "    更多教程: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 分享\033[0m"
# echo -e "\033[1;34m==================================================================\033[0m"


echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m           🦞 OpenClaw 2026 部署成功 (Root 暴力版) \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "   SSH 用户: \033[1;37m$CLAW_USER\033[0m  密码: \033[1;32m$SSH_PASSWORD\033[0m"
echo -e ""
echo -e "\033[1;33m[2. SSH 隧道指令 (在你的 Mac/PC 执行)]\033[0m"
echo -e "   \033[1;37mssh -N -L 18789:127.0.0.1:18789 $CLAW_USER@$IP_ADDR\033[0m"
echo -e ""
echo -e "\033[1;33m[3. Dashboard 浏览器访问]\033[0m"
echo -e "   \033[1;36mhttp://localhost:18789/#token=$FINAL_TOKEN\033[0m"
echo -e ""
echo "🚀 启动命令: openclaw gateway start"
echo ""
echo "🚀 重启命令: openclaw gateway restart"
echo ""
echo "🔧 常用命令:"
echo "   openclaw status          # 查看状态"
echo "   openclaw configure       # 交互式配置"
echo "   openclaw models list     # 查看可用模型"
echo "   openclaw logs            # 查看日志"
echo ""
echo "📚 文档: https://docs.openclaw.ai"
echo "💡 后续需手动配置API密钥和消息通道"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "   更多教程/源码: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 分享\033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
