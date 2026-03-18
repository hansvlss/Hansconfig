#!/bin/bash
# =================================================================
# OpenClaw 2026 官方版 (环境自适应 & 代理注入版)
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

# 自动获取当前环境的代理 (核心补丁)
CURRENT_PROXY=$(env | grep -iE '^http_proxy=|^https_proxy=' | head -1 | cut -d'=' -f2)

# ✅ 如果检测到错误格式（你现在这种），自动修正
if [[ "$CURRENT_PROXY" == *"PROXY_IP"* ]]; then
    echo -e "${ARROW}检测到错误代理格式，自动修复..."

    PROXY_IP=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_IP:-")[^"]+')
    PROXY_PORT=$(echo $CURRENT_PROXY | grep -oP '(?<=PROXY_PORT:-")[^"]+')

    CURRENT_PROXY="http://${PROXY_IP}:${PROXY_PORT}"
fi

echo -e "\n${TITLE_G}=================================================================="
echo -e "           🦞 OpenClaw 网关自动部署 (官方直连增强版)"
echo -e "==================================================================${NC}\n"

run_with_dots "正在同步系统仓库" "apt update -y"
run_with_dots "正在配置 NodeSource 22 官方源" "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"
run_with_dots "正在安装 Node.js 22 & 基础组件" "apt install -y nodejs git sudo build-essential psmisc openssl"
run_with_dots "正在配置用户权限" "
if ! id $CLAW_USER &>/dev/null; then
    useradd -m -s /bin/bash $CLAW_USER
    echo $CLAW_USER:$SSH_PASSWORD | chpasswd
    echo '$CLAW_USER ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi
chown -R $CLAW_USER:$CLAW_USER /home/$CLAW_USER
"

# 🛠️ 核心修正：直接把代理注入到 npm install 命令中
echo -ne "${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (强制代理模式)...${NC}"

# 如果检测到环境中有代理，则注入给 npm
sudo -i -u $CLAW_USER CURRENT_PROXY="$CURRENT_PROXY" bash << EOF > /dev/null 2>&1 &
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
git config --global url."https://github.com/".insteadOf "git@github.com:"
# 这里的 \$PROXY_CMD 会确保 claw 用户也能用到代理
# 如果有代理 → 用环境变量注入（官方方式）
if [ ! -z "$CURRENT_PROXY" ]; then
    export HTTP_PROXY="$CURRENT_PROXY"
    export HTTPS_PROXY="$CURRENT_PROXY"
fi

npm install -g openclaw@latest --unsafe-perm --registry=https://registry.npmjs.org
# 写入配置
export PATH="\$HOME/.npm-global/bin:\$PATH"
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
        printf "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (强制代理模式)... [ $i ]${NC}"
        sleep 0.2
    done
done
wait $NPMPID

if [ $? -eq 0 ]; then
    echo -e "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (强制代理模式) ...${NC} [ ${TITLE_G}完成${NC} ]"
else
    echo -e "\r${ARROW}${STEP_W}正在从 NPM 官方下载 OpenClaw (强制代理模式) ...${NC} [ \033[1;31m失败\033[0m ]"
    exit 1
fi

run_with_dots "正在创建 Systemd 后台服务" "
cat << SERVICE > /etc/systemd/system/openclaw.service
[Unit]
Description=OpenClaw Gateway
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
systemctl restart openclaw
"
ln -sf /home/claw/.npm-global/bin/openclaw /usr/local/bin/openclaw
ln -sf /home/claw/.openclaw /root/.openclaw
sudo chown -R 1000:1000 /home/claw/.openclaw

# 结算单
IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m         🦞 OpenClaw 2026 部署成功 (官方直连版) \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "   用户名: \033[1;37m$CLAW_USER\033[0m  密码: \033[1;32m$SSH_PASSWORD\033[0m"
echo -e ""
echo -e "\033[1;33m[2. SSH 隧道指令 (在你的 Mac/PC 执行)]\033[0m"
echo -e "   \033[1;37mssh -N -L 18789:127.0.0.1:18789 $CLAW_USER@$IP_ADDR\033[0m"
echo -e ""
echo -e "\033[1;33m[3. Dashboard 浏览器访问]\033[0m"
echo -e "   \033[1;36mhttp://localhost:18789/#token=$CLAW_TOKEN\033[0m"
echo -e ""
echo "🚀 启动命令: openclaw gateway start"
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
