#!/bin/bash
# =================================================================
# OpenClaw 2026 官方原版部署脚本 - Hans (官方增强版)
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
        # 失败时不直接退出，给个提示
        echo -e "${RED_B}详情：建议检查代理是否支持长连接，或手动运行 npm install -g openclaw 尝试。${NC}"
        exit 1
    fi
}

CLAW_USER="claw"
SSH_PASSWORD="claw"
CLAW_TOKEN=$(openssl rand -hex 16)

# 预处理
killall apt apt-get dpkg 2>/dev/null
rm -rf /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
rm -f /etc/apt/sources.list.d/nodesource.list

echo -e "\n${TITLE_G}=================================================================="
echo -e "           🦞 OpenClaw 网关自动部署 (官方直连增强版)"
echo -e "==================================================================${NC}\n"

run_with_dots "正在同步系统仓库" "apt update -y"

run_with_dots "正在配置 NodeSource 22 官方源" "
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
"

run_with_dots "正在安装 Node.js 22 & 核心组件" "apt install -y nodejs git sudo build-essential psmisc openssl"

run_with_dots "正在配置用户权限" "
if ! id $CLAW_USER &>/dev/null; then
    useradd -m -s /bin/bash $CLAW_USER
    echo $CLAW_USER:$SSH_PASSWORD | chpasswd
    echo '$CLAW_USER ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi
chown -R $CLAW_USER:$CLAW_USER /home/$CLAW_USER
"

# 🛠️ 针对 NPM 官方下载失败的重点修复
run_with_dots "正在从 NPM 官方安装 OpenClaw" "
sudo -i -u $CLAW_USER bash << EOF
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
# 强制官方源并增加重试次数
npm config set registry https://registry.npmjs.org
npm config set fetch-retries 5
npm config set fetch-retry-mintimeout 20000
npm config set fetch-retry-maxtimeout 120000

export PATH=\"\\\$HOME/.npm-global/bin:\\\$PATH\"
# 增加 --prefer-online 确保不从可能损坏的本地缓存读取
npm install -g openclaw@latest --unsafe-perm --prefer-online

# 写入配置
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

IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m         🦞 OpenClaw 2026 部署成功 (官方直连) \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "   用户名: \033[1;37m$CLAW_USER\033[0m  密码: \033[1;32m$SSH_PASSWORD\033[0m"
echo -e "   地址: \033[1;36mhttp://localhost:18789/#token=$CLAW_TOKEN\033[0m"
echo -e ""
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "   更多教程: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 官方稳定版\033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
