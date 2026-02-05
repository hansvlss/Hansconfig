cat > hans_init.sh << 'EOF'
#!/bin/bash
# HansCN 2026 OpenClaw Bootloader (Minimalist Pro UI)

GREEN='\033[0;32m'
BOLD_GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${CYAN}------------------------------------------------------------${NC}"
echo -e "  ${WHITE}${BOLD}HansCN OpenClaw 智能引导程序${NC} ${YELLOW}v2026${NC}"
echo -e "  ${CYAN}自愈逻辑已激活 - 适配 Debian 12 纯净版${NC}"
echo -e "${CYAN}------------------------------------------------------------${NC}"

check_net() {
    timeout 2 bash -c "cat < /dev/tcp/deb.debian.org/80" &> /dev/null
    return $?
}

echo -en "\n${WHITE}●${NC} 正在检测系统网络环境... "
if check_net; then
    echo -e "[ ${GREEN}已联网${NC} ]"
else
    echo -e "[ ${RED}未连接${NC} ]"
    
    # --- 极简交互区：去掉所有线条 ---
    echo -e "\n${YELLOW}${BOLD}NETWORK CONFIGURATION${NC}"
    echo -e "${CYAN}检测到环境受限，请配置本地代理补丁：${NC}"
    
    # 纯文字引导，不带任何线条
    echo -en "\n  ${WHITE}请输入代理 IP 地址${NC}: "
    read PROXY_IP
    PROXY_IP=${PROXY_IP:-"192.168.1.30"}
    
    echo -en "  ${WHITE}请输入代理端口号码${NC}: "
    read PROXY_PORT
    PROXY_PORT=${PROXY_PORT:-"7890"}
    
    # 物理注入逻辑 (保持不变)
    export http_proxy="http://${PROXY_IP}:${PROXY_PORT}"
    export https_proxy="http://${PROXY_IP}:${PROXY_PORT}"
    mkdir -p /etc/apt/apt.conf.d/
    echo "Acquire::http::Proxy \"http://${PROXY_IP}:${PROXY_PORT}\";" > /etc/apt/apt.conf.d/88proxy
    
    echo -e "\n${BOLD_GREEN}✔ 环境补丁注入成功: ${WHITE}$PROXY_IP:$PROXY_PORT${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
fi

# --- 核心逻辑 ---
echo -en "\n${WHITE}●${NC} 正在补齐核心组件 (curl)... "
apt-get update > /dev/null 2>&1
apt-get install -y curl > /dev/null 2>&1
echo -e "[ ${GREEN}DONE${NC} ]"

TIMESTAMP=$(date +%s)
REMOTE_SCRIPT="https://raw.githubusercontent.com/hansvlss/Hansconfig/main/OpenClaw/OpenClaw_Deploy_v1.sh"
echo -en "${WHITE}●${NC} 同步 GitHub 核心脚本... "
curl -sSL -k -H "Cache-Control: no-cache" "${REMOTE_SCRIPT}?t=$TIMESTAMP" -o OpenClaw_Deploy_v1.sh
echo -e "[ ${GREEN}DONE${NC} ]"

if [ -s "OpenClaw_Deploy_v1.sh" ]; then
    chmod +x OpenClaw_Deploy_v1.sh
    ./OpenClaw_Deploy_v1.sh
fi
EOF
chmod +x hans_init.sh
./hans_init.sh
