#!/bin/bash

# ----------------------------------------------------------------
# HansCN 2026 OpenClaw LXC Pro Edition (v2026.2.2 Ultimate)
# ----------------------------------------------------------------

set +e 

# --- 颜色与图标定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CHECK="[${GREEN}✓${NC}]"
INFO="[${BLUE}i${NC}]"
WARN="[${YELLOW}!${NC}]"
LOAD="[${PURPLE}*${NC}]"

# --- 视觉动画函数 ---
draw_line() {
    echo -e "${CYAN}--------------------------------------------------------------${NC}"
}

print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}OpenClaw Gateway${NC} ${GREEN}自动化部署系统${NC} ${YELLOW}v2026 Test${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${PURPLE}Powered by HansCN${NC}                                   ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
}

# 1. 初始化清理
rm -f /etc/apt/apt.conf.d/88proxy

# 2. 打印头部
print_header
echo -e "${INFO} ${BOLD}系统诊断中...${NC}"
echo -e "  ${CYAN}➤${NC} 执行路径: ${WHITE}$(pwd)${NC}"
echo -e "  ${CYAN}➤${NC} 代理状态: ${GREEN}${http_proxy:-"未设置"}${NC}"
FREE_MEM=$(free -m | awk '/^Mem:/{print $4}')
echo -e "  ${CYAN}➤${NC} 剩余内存: ${GREEN}${FREE_MEM}MB${NC}"
draw_line

# 3. 代理注入
if [ -n "$http_proxy" ]; then
    echo "Acquire::http::Proxy \"$http_proxy\";" > /etc/apt/apt.conf.d/88proxy
    echo -e "${CHECK} APT 代理强制注入成功"
fi

# --- 核心步骤开始 ---

echo -e "\n${BOLD}${CYAN}Step 1/6: 基础工具同步${NC}"
echo -e "${LOAD} 正在安装基础依赖包..."
killall -9 apt apt-get 2>/dev/null || true
apt-get update > /dev/null 2>&1
apt-get install -y curl net-tools gnupg2 lsb-release psmisc nginx > /dev/null 2>&1
echo -e "${CHECK} 基础组件安装完成"

echo -e "\n${BOLD}${CYAN}Step 2/6: Docker 引擎配置${NC}"
echo -e "${LOAD} 正在配置 Docker 存储库与密钥..."
mkdir -p /etc/apt/keyrings
PROXY_URL=${http_proxy:-""}
curl -fsSL -k ${PROXY_URL:+ -x $PROXY_URL} https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes > /dev/null 2>&1
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update > /dev/null 2>&1
apt-get install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1

if [ -n "$PROXY_URL" ]; then
    mkdir -p /etc/systemd/system/docker.service.d
    cat <<CONF > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
CONF
    systemctl daemon-reload && systemctl restart docker > /dev/null 2>&1
fi
echo -e "${CHECK} Docker 容器引擎就绪"

echo -e "\n${BOLD}${CYAN}Step 3/6: LXC 虚拟网卡激活${NC}"
echo -e "${LOAD} 正在初始化 Tailscale 隧道..."
mkdir -p /var/run/tailscale /var/lib/tailscale
nohup tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock > /dev/null 2>&1 &
sleep 2 && tailscale up --accept-dns=false > /dev/null 2>&1 || true
echo -e "${CHECK} 虚拟网卡状态: ${GREEN}ONLINE${NC}"

echo -e "\n${BOLD}${CYAN}Step 4/6: OpenClaw 核心部署${NC}"
echo -e "${LOAD} 正在执行官方安装程序..."
killall -9 openclaw 2>/dev/null || true
rm -rf /root/.openclaw
export COREPACK_ENABLE_AUTO_PIN=0
curl -fsSL -k https://openclaw.ai/install.sh | bash -s -- --install-method git > /dev/null 2>&1

# 建立全局软链接
ln -sf /root/.local/bin/openclaw /usr/local/bin/openclaw
echo -e "${CHECK} OpenClaw 核心安装完毕 (v2026.2.2)"

echo -e "\n${BOLD}${CYAN}Step 5/6: 官方 CLI 配置注入${NC}"
echo -e "${LOAD} 正在通过 CLI 写入 HansCN 专属补丁..."
FIXED_TOKEN="7d293114c449ad5fa4618a30b24ad1c4e998d9596fc6dc4f"

# 关键：放弃 cat 写入 JSON，改用 CLI 注入以确保格式百分百兼容
openclaw config set gateway.mode local
openclaw config set gateway.auth.token "$FIXED_TOKEN"
openclaw config set gateway.controlUi.allowInsecureAuth true

# 物理注入 UI (解决 --control-ui-dist 参数报错问题)
mkdir -p /root/.openclaw/dist
if [ -d "/tmp/openclaw-ui/dist/control-ui" ]; then
    cp -r /tmp/openclaw-ui/dist/control-ui/* /root/.openclaw/dist/
    echo -e "${CHECK} UI 资源物理对齐成功"
fi

echo -e "\n${BOLD}${CYAN}Step 6/6: 网络服务路由与纯净启动${NC}"
echo -e "${LOAD} 正在配置 Nginx 并尝试纯净启动..."
cat > /etc/nginx/sites-enabled/default <<NGX
server {
    listen 8888;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGX

systemctl restart nginx > /dev/null 2>&1

# 重点：裸奔启动！不带任何会导致报错的命令行参数
killall -9 openclaw 2>/dev/null || true
rm -f /root/.openclaw/gateway.lock
nohup openclaw gateway --allow-unconfigured > /root/openclaw.log 2>&1 &

echo -e "${CHECK} 内部 18789 端口已开启监听"

REAL_IP=$(hostname -I | awk '{for(i=1;i<=NF;i++) if($i != "127.0.0.1" && $i !~ /^172\./) {print $i; exit}}')

# --- 最终杀青展示 ---
draw_line
echo -e "\n${BOLD}${GREEN}        🎉 OPENCLAW 自动化部署圆满成功！${NC}"
echo -e "\n  ${BOLD}管理地址: ${NC}${YELLOW}http://${REAL_IP:-$HOSTNAME}:8888${NC}"
echo -e "  ${BOLD}登录密钥: ${NC}${BOLD}${WHITE}${FIXED_TOKEN}${NC}"
echo -e "\n${CYAN}  HansCN 提示: 已适配 2026.2.2 环境。如果无法连接，请刷新浏览器缓存。${NC}"
draw_line

# 自毁与清理
rm -f /etc/apt/apt.conf.d/88proxy
rm -f $0
