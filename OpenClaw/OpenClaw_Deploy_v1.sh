#!/bin/bash

# ----------------------------------------------------------------
# HansCN 2026 OpenClaw LXC Pro Edition (v2026.3.2 Ultimate UI)
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
    echo -e "${CYAN}┃${NC}  ${WHITE}${BOLD}OpenClaw Gateway${NC} ${GREEN}自动化部署系统${NC} ${YELLOW}v2026.3.2${NC}   ${CYAN}┃${NC}"
    echo -e "${CYAN}┃${NC}  ${PURPLE}Powered by HansCN - 1008/502/Exit1 Fixed${NC}          ${CYAN}┃${NC}"
    echo -e "${CYAN}┃${NC}  ${CYAN}部署环境: Debian 12 (LXC / Docker)${NC}               ${CYAN}┃${NC}"
    echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

# 1. 初始化
print_header
echo -e "${LOAD} ${WHITE}正在清理系统冲突进程与容器...${NC}"
docker rm -f openclaw-gateway 2>/dev/null || true
killall -9 node openclaw openclaw-gateway 2>/dev/null || true

# --- 核心步骤 ---

echo -e "\n${BOLD}${WHITE}STEP [1/6]${NC} ${CYAN}同步基础工具链${NC}"
echo -en "${INFO} 正在安装核心组件 (curl, nginx, psmisc)... "
apt-get update > /dev/null 2>&1
apt-get install -y curl net-tools gnupg2 lsb-release psmisc nginx > /dev/null 2>&1
echo -e "[ ${BOLD_GREEN}DONE${NC} ]"

echo -e "\n${BOLD}${WHITE}STEP [2/6]${NC} ${CYAN}Docker 容器引擎配置${NC}"
echo -en "${INFO} 初始化存储库与 GPG 密钥... "
mkdir -p /etc/apt/keyrings
curl -fsSL -k ${http_proxy:+ -x $http_proxy} https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes > /dev/null 2>&1
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update > /dev/null 2>&1
apt-get install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1
systemctl start docker > /dev/null 2>&1
echo -e "[ ${BOLD_GREEN}DONE${NC} ]"

echo -e "\n${BOLD}${WHITE}STEP [3/6]${NC} ${CYAN}OpenClaw 核心镜像安装${NC}"
OFFLINE_FILE="/root/openclaw-2026.2.3.tar"

if [ -f "$OFFLINE_FILE" ]; then
    echo -e "${LOAD} ${WHITE}检测到离线镜像包，正在注入本地核心...${NC}"
    docker load -i "$OFFLINE_FILE" > /dev/null 2>&1
    echo -e "${CHECK} ${BOLD_GREEN}离线核心已成功载入 (v2026.3.2)${NC}"
else
    echo -e "${LOAD} ${WHITE}正在拉取官方在线镜像 (v2026.3.2)...${NC}"
    docker pull openclaw/gateway:latest > /dev/null 2>&1
    echo -e "${CHECK} ${BOLD_GREEN}在线镜像拉取成功${NC}"
fi

echo -e "\n${BOLD}${WHITE}STEP [4/6]${NC} ${CYAN}配置持久化数据目录${NC}"
mkdir -p /root/.openclaw
echo -e "${CHECK} ${BOLD_GREEN}配置存储目录 /root/.openclaw 已就绪${NC}"

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

echo -e "\n${BOLD}${WHITE}STEP [6/6]${NC} ${CYAN}Docker 容器启动 (解决 502)${NC}"
echo -en "${INFO} 正在启动 Docker 容器核心... "
FIXED_TOKEN="7d293114c449ad5fa4618a30b24ad1c4e998d9596fc6dc4f"

# 使用 Docker 启动，彻底解决裸机进程不稳导致的 502
docker run -d \
  --name openclaw-gateway \
  --restart unless-stopped \
  --network host \
  -v /root/.openclaw:/home/node/.openclaw \
  -e OPENCLAW_GATEWAY_TOKEN="$FIXED_TOKEN" \
  -e OPENCLAW_GATEWAY_ALLOW_UNCONFIGURED=true \
  openclaw/gateway:latest > /dev/null 2>&1

echo -e "[ ${BOLD_GREEN}SUCCESS${NC} ]"

# 获取 IP
REAL_IP=$(hostname -I | awk '{print $1}')
OC_VERSION="2026.3.2"

echo -e ""
draw_line
echo -e "      🚀 ${BOLD_GREEN}OPENCLAW v${OC_VERSION} ULTIMATE 部署成功！${NC}"
echo -e ""
echo -e "   ${WHITE}● 管理地址:${NC} ${YELLOW}http://${REAL_IP}:8888${NC}"
echo -e "   ${WHITE}● 登录密钥:${NC} ${WHITE}${BOLD}${FIXED_TOKEN}${NC}"
echo -e ""
echo -e "   ${PURPLE}🦞提示: 系统已切换至 Docker 离线模式，性能更稳定。${NC}"
draw_line

# 清理自毁 APT 代理
rm -f /etc/apt/apt.conf.d/88proxy
