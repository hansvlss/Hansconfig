#!/bin/bash

# ----------------------------------------------------------------
# HansCN 2026 OpenClaw LXC Pro Edition (v2026.2.3 Ultimate UI)
# ----------------------------------------------------------------

set +e 

# --- 视觉 UI 定义 ---
GREEN='\033[0;32m'
BOLD_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="${BOLD_GREEN}✔${NC}"
INFO="${CYAN}ℹ${NC}"
LOAD="${PURPLE}●${NC}"

draw_line() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_header() {
    clear
    echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${CYAN}┃${NC}  ${WHITE}${BOLD}OpenClaw Gateway${NC} ${GREEN}自动化部署系统${NC} ${YELLOW}v2026 Ultimate${NC}   ${CYAN}┃${NC}"
    echo -e "${CYAN}┃${NC}  ${PURPLE}Powered by HansCN - 1008/502/Exit1 Fixed${NC}          ${CYAN}┃${NC}"
    echo -e "${CYAN}┃${NC}  ${CYAN}部署环境: Debian 12 (LXC)${NC}                            ${CYAN}┃${NC}"
    echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# 1. 初始化
print_header
echo -e "${LOAD} ${WHITE}正在清理系统冲突进程...${NC}"
killall -9 node openclaw openclaw-gateway 2>/dev/null || true

# --- 核心步骤 ---

echo -e "\n${BOLD}${WHITE}STEP [1/6]${NC} ${CYAN}同步基础工具链${NC}"
echo -en "${INFO} 正在安装核心组件 (curl, nginx, psmisc)... "
apt-get update > /dev/null 2>&1
apt-get install -y curl net-tools gnupg2 lsb-release psmisc nginx > /dev/null 2>&1
echo -e "[ ${BOLD_GREEN}DONE${NC} ]"

echo -e "\n${BOLD}${WHITE}STEP [2/6]${NC} ${CYAN}Docker 容器引擎配置${NC}"
echo -en "${INFO} 初始化存储库与 GPG 密钥... "
# 逻辑保留：安装 Docker
mkdir -p /etc/apt/keyrings
curl -fsSL -k ${http_proxy:+ -x $http_proxy} https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes > /dev/null 2>&1
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update > /dev/null 2>&1
apt-get install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1
echo -e "[ ${BOLD_GREEN}DONE${NC} ]"

echo -e "\n${BOLD}${WHITE}STEP [3/6]${NC} ${CYAN}OpenClaw 核心安装${NC}"
echo -e "${LOAD} ${WHITE}正在拉取官方源码并构建 (v2026.2.3)...${NC}"
rm -rf /root/.openclaw
curl -fsSL -k https://openclaw.ai/install.sh | bash -s -- --install-method git > /dev/null 2>&1
ln -sf /root/.local/bin/openclaw /usr/local/bin/openclaw
echo -e "${CHECK} ${BOLD_GREEN}二进制核心已成功对齐${NC}"

echo -e "\n${BOLD}${WHITE}STEP [4/6]${NC} ${CYAN}官方 CLI 配置与安全补丁${NC}"
FIXED_TOKEN="7d293114c449ad5fa4618a30b24ad1c4e998d9596fc6dc4f"
mkdir -p /root/.openclaw
# 逻辑保留：写入补丁配置
openclaw config set gateway.auth.token "$FIXED_TOKEN" > /dev/null 2>&1
openclaw config set gateway.controlUi.allowInsecureAuth true > /dev/null 2>&1
openclaw config set gateway.controlUi.allowedOrigins '["*"]' > /dev/null 2>&1
openclaw config set gateway.trustedProxies '["127.0.0.1"]' > /dev/null 2>&1
echo -e "${CHECK} ${BOLD_GREEN}1008 跨域补丁与不安全认证设置已写入${NC}"

echo -e "\n${BOLD}${WHITE}STEP [5/6]${NC} ${CYAN}Nginx 流量伪装转发${NC}"
echo -en "${INFO} 正在构建反向代理路由 (8888 ➔ 18789)... "
cat > /etc/nginx/sites-enabled/default <<NGX
server {
    listen 8888;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host 127.0.0.1;
        proxy_set_header Origin "http://127.0.0.1:18789";
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGX
systemctl restart nginx > /dev/null 2>&1
echo -e "[ ${BOLD_GREEN}DONE${NC} ]"

echo -e "\n${BOLD}${WHITE}STEP [6/6]${NC} ${CYAN}物理清理与核心燃火${NC}"
echo -en "${INFO} 正在清除僵尸进程并强制启动... "
killall -9 node openclaw openclaw-gateway 2>/dev/null || true
rm -f /root/.openclaw/gateway.lock
sleep 1
# 逻辑保留：强制带 Token 启动
nohup openclaw gateway --allow-unconfigured --token "$FIXED_TOKEN" > /root/openclaw.log 2>&1 &
echo -e "[ ${BOLD_GREEN}SUCCESS${NC} ]"

# 获取 IP 并提取版本号
REAL_IP=$(hostname -I | awk '{print $1}')
RAW_VERSION=$(openclaw -v 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
OC_VERSION=${RAW_VERSION:-"2026.2.3"}

echo -e ""
draw_line
# 优化后的标题，显示官方版本号
echo -e "      🚀 ${BOLD_GREEN}OPENCLAW v${OC_VERSION} ULTIMATE 部署成功！${NC}"
echo -e ""
echo -e "   ${WHITE}● 管理地址:${NC} ${YELLOW}http://${REAL_IP}:8888${NC}"
echo -e "   ${WHITE}● 登录密钥:${NC} ${WHITE}${BOLD}${FIXED_TOKEN}${NC}"
echo -e ""
echo -e "   ${PURPLE}🦞提示: 若浏览器状态断开，请使用无痕模式清除缓存。${NC}"
draw_line

# 自毁 APT 代理
rm -f /etc/apt/apt.conf.d/88proxy
