#!/bin/bash
# =================================================================
# OpenClaw 2026 官方版 (方案二：全流程隔离 & 软链接同步版)
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

CLAW_USER="claw"
SSH_PASSWORD="claw"
CLAW_TOKEN=$(openssl rand -hex 16)

# 自动获取当前环境的代理
CURRENT_PROXY=$(env | grep -iE '^http_proxy=|^https_proxy=' | head -1 | cut -d'=' -f2)

if [[ "$CURRENT_PROXY" == *"PROXY_IP"* ]]; then
    echo -e "${ARROW}检测到错误代理格式，自动修复..."
    PROXY_IP=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_IP:-")[^"]+')
    PROXY_PORT=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_PORT:-")[^"]+')
    CURRENT_PROXY="http://${PROXY_IP}:${PROXY_PORT}"
fi

echo -e "\n${TITLE_G}=================================================================="
echo -e "           🦞 OpenClaw 网关自动部署 (方案二：全隔离同步版)"
echo -e "==================================================================${NC}\n"

run_with_dots "正在同步系统仓库" "apt update -y"
run_with_dots "正在配置 NodeSource 22 官方源" "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"
run_with_dots "正在安装 Node.js 22 & 基础组件" "apt install -y nodejs git sudo build-essential psmisc openssl"

# -----------------------------------------------------------------
# 1. 配置用户及预设权限 (Root 开路)
# -----------------------------------------------------------------
run_with_dots "正在预设 Claw 用户目录权限" "
if ! id $CLAW_USER &>/dev/null; then
    useradd -m -s /bin/bash $CLAW_USER
    echo $CLAW_USER:$SSH_PASSWORD | chpasswd
    echo '$CLAW_USER ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi
mkdir -p /home/$CLAW_USER/.openclaw
mkdir -p /home/$CLAW_USER/.npm-global
chown -R 1000:1000 /home/$CLAW_USER
chmod 755 /home/$CLAW_USER
"

# -----------------------------------------------------------------
# 2. 纯净隔离安装 (Claw 进场)
# -----------------------------------------------------------------
echo -ne "${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (隔离模式)...${NC}"

sudo -i -u $CLAW_USER CURRENT_PROXY="$CURRENT_PROXY" CLAW_TOKEN="$CLAW_TOKEN" bash << 'EOF' &
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global' --silent
git config --global url."https://github.com/".insteadOf "git@github.com:"

if [ ! -z "$CURRENT_PROXY" ]; then
    export HTTP_PROXY="$CURRENT_PROXY"
    export HTTPS_PROXY="$CURRENT_PROXY"
    npm config set proxy "$CURRENT_PROXY"
    npm config set https-proxy "$CURRENT_PROXY"
fi

# 安装至 claw 自己的目录
npm install -g openclaw@latest --unsafe-perm --registry=https://registry.npmjs.org --silent > /dev/null 2>&1

# 在 claw 家目录下初始化
export PATH="$HOME/.npm-global/bin:$PATH"
printf 'y\n' | ~/.npm-global/bin/openclaw onboard > /dev/null 2>&1
~/.npm-global/bin/openclaw config set gateway.mode local > /dev/null 2>&1
~/.npm-global/bin/openclaw config set gateway.port 18789 > /dev/null 2>&1
~/.npm-global/bin/openclaw config set gateway.bind loopback > /dev/null 2>&1
~/.npm-global/bin/openclaw config set gateway.auth.token $CLAW_TOKEN > /dev/null 2>&1
EOF

# 旋转进度条
NPMPID=$!
while kill -0 $NPMPID 2>/dev/null; do
    for i in "/" "-" "\\" "|"; do
        printf "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (隔离模式)... [ $i ]${NC}"
        sleep 0.2
    done
done
wait $NPMPID

if [ $? -eq 0 ]; then
    echo -e "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (隔离模式) ...${NC} [ ${TITLE_G}完成${NC} ]"
else
    echo -e "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (隔离模式) ...${NC} [ \033[1;31m失败\033[0m ]"
    exit 1
fi

# -----------------------------------------------------------------
# 3. 创建 Systemd 服务 (必须由 Root 执行)
# -----------------------------------------------------------------
run_with_dots "正在创建 Systemd 后台服务" "
cat << SERVICE > /etc/systemd/system/openclaw.service
[Unit]
Description=OpenClaw Gateway (Isolation Mode)
After=network.target

[Service]
Type=simple
User=$CLAW_USER
Environment=\"PATH=/home/$CLAW_USER/.npm-global/bin:/usr/local/bin:/usr/bin:/bin\"
WorkingDirectory=/home/$CLAW_USER
ExecStart=/home/$CLAW_USER/.npm-global/bin/openclaw gateway
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable openclaw > /dev/null 2>&1
"

# -----------------------------------------------------------------
# 4. 🛡️ 终极权限确权 & 软链接同步 (解决 root 修改没反应的核心)
# -----------------------------------------------------------------
run_with_dots "正在进行最终权限校准与同步" "
    systemctl stop openclaw > /dev/null 2>&1
    
    # 强制修正所有权
    chown -R 1000:1000 /home/$CLAW_USER
    chmod 755 /home/$CLAW_USER
    chmod 666 /home/$CLAW_USER/.openclaw/openclaw.json
    
    # 全局命令链接
    ln -sf /home/$CLAW_USER/.npm-global/bin/openclaw /usr/local/bin/openclaw
    
    # 【绝招】让 Root 的配置目录直接指向 Claw 的配置目录
    # 这样你在 Root 敲 openclaw configure，改的就是网页用的那个 JSON！
    rm -rf /root/.openclaw
    ln -sf /home/$CLAW_USER/.openclaw /root/.openclaw
    
    systemctl daemon-reload
    systemctl start openclaw
"

# -----------------------------------------------------------------
# 5. 结算单准备 (实时获取数据)
# -----------------------------------------------------------------
IP_ADDR=$(hostname -I | awk '{print $1}')
# 必须从 claw 的实际配置文件里读 Token
REAL_TOKEN=$(grep -oP '"token":\s*"\K[^"]+' /home/$CLAW_USER/.openclaw/openclaw.json)

# -----------------------------------------------------------------
# 6. 打印 Hans 原创结算单 UI
# -----------------------------------------------------------------
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m           🦞 OpenClaw 2026 部署成功 (官方直连版) \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "    用户名: \033[1;37m$CLAW_USER\033[0m  密码: \033[1;32m$SSH_PASSWORD\033[0m"
echo -e ""
echo -e "\033[1;33m[2. SSH 隧道指令 (在你的 Mac/PC 执行)]\033[0m"
echo -e "    \033[1;37mssh -N -L 18789:127.0.0.1:18789 $CLAW_USER@$IP_ADDR\033[0m"
echo -e ""
echo -e "\033[1;33m[3. Dashboard 浏览器访问]\033[0m"
echo -e "    \033[1;36mhttp://localhost:18789/#token=$REAL_TOKEN\033[0m"
echo -e ""
echo "🚀 启动命令: openclaw gateway start"
echo ""
echo "🚀 重启命令: openclaw gateway restart"
echo ""
echo "🔧 常用命令:"
echo "    openclaw status          # 查看状态"
echo "    openclaw configure       # 交互式配置"
echo "    openclaw models list     # 查看可用模型"
echo "    openclaw logs            # 查看日志"
echo ""
echo "📚 文档: https://docs.openclaw.ai"
echo "💡 后续需手动配置API密钥和消息通道"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "    更多教程/源码: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 分享\033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
