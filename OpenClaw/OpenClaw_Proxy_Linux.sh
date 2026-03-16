#!/bin/bash
# =================================================================
# OpenClaw 2026 官方原版部署脚本 - Hans (hanscn.com) 专用版
# 环境要求：必须具备全局代理或位于海外网络
# =================================================================

# 1. 样式定义
TITLE_G="\033[1;32m"
STEP_W="\033[0;37m"
NC="\033[0m"
ARROW="${TITLE_G} ● ${NC}" 

# 2. 动态跳动圆点函数
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

# 3. 预设参数
CLAW_USER="claw"
SSH_PASSWORD="claw"
CLAW_TOKEN=$(openssl rand -hex 16)

# --- 预处理：清理残留，确保官方源纯净 ---
killall apt apt-get dpkg 2>/dev/null
rm -rf /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
rm -f /etc/apt/sources.list.d/nodesource.list

# --- 开始展示 (沉浸式执行) ---
echo -e "\n${TITLE_G}=================================================================="
echo -e "           🦞 OpenClaw 网关自动部署脚本 (官方原版模式)"
echo -e "==================================================================${NC}\n"

# 4. 环境安装逻辑 (全官方链路)
run_with_dots "正在同步系统仓库 (Official)" "apt update -y"

run_with_dots "正在配置 NodeSource 22 官方源" "
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
"

run_with_dots "正在安装 Node.js 22 & 核心组件" "apt install -y nodejs git sudo build-essential psmisc openssl"

run_with_dots "正在配置用户权限与安全策略" "
if ! id $CLAW_USER &>/dev/null; then
    useradd -m -s /bin/bash $CLAW_USER
    echo $CLAW_USER:$SSH_PASSWORD | chpasswd
    echo '$CLAW_USER ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi
chown -R $CLAW_USER:$CLAW_USER /home/$CLAW_USER
"

run_with_dots "正在从 NPM 官方下载 OpenClaw" "
sudo -i -u $CLAW_USER bash << EOF
# 官方环境无需设置任何镜像前缀
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
# 强制指定官方源
npm config set registry https://registry.npmjs.org
export PATH=\"\\\$HOME/.npm-global/bin:\\\$PATH\"
npm install -g openclaw@latest --unsafe-perm
printf 'y\n' | ~/.npm-global/bin/openclaw onboard
~/.npm-global/bin/openclaw config set gateway.mode local
~/.npm-global/bin/openclaw config set gateway.port 18789
~/.npm-global/bin/openclaw config set gateway.bind loopback
~/.npm-global/bin/openclaw config set gateway.auth.token '$CLAW_TOKEN'
EOF
"

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

# 5. 结果展示
IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m         🦞 OpenClaw 2026 部署成功 (官方版) \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "\033[1;33m[1. SSH 登录凭证]\033[0m"
echo -e "   用户名: \033[1;37m$CLAW_USER\033[0m"
echo -e "   密  码: \033[1;32m$SSH_PASSWORD\033[0m"
echo -e ""
echo -e "\033[1;33m[2. SSH 隧道指令 (在 PC/Mac 执行)]\033[0m"
echo -e "   \033[1;37mssh -N -L 18789:127.0.0.1:18789 $CLAW_USER@$IP_ADDR\033[0m"
echo -e ""
echo -e "\033[1;33m[3. Dashboard 访问地址]\033[0m"
echo -e "   \033[1;36mhttp://localhost:18789/#token=$CLAW_TOKEN\033[0m"
echo -e ""
echo "🚀 启动命令: openclaw gateway start"
echo ""
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "   更多教程: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 官方路线版\033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
