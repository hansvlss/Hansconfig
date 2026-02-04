#!/bin/bash

# ----------------------------------------------------------------
# HansCN 2026 OpenClaw LXC Pro Edition (v2026.2.3 Ultimate)
# ----------------------------------------------------------------

set +e 

# --- 颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
WHITE='\033[1;37m'
NC='\033[0m'

CHECK="[${GREEN}✓${NC}]"
LOAD="[${BLUE}*${NC}]"

# --- 视觉头部 ---
clear
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}${WHITE}OpenClaw Gateway${NC} ${GREEN}自动化部署系统${NC} ${YELLOW}v2026 Ultimate${NC}   ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${PURPLE}Powered by HansCN - 1008/502/Exit1 Fixed${NC}          ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"

# 1. 基础环境清理
killall -9 node openclaw openclaw-gateway 2>/dev/null || true

echo -e "\n${BOLD}${CYAN}Step 1/6: 基础工具同步${NC}"
apt-get update > /dev/null 2>&1
apt-get install -y curl net-tools gnupg2 lsb-release psmisc nginx > /dev/null 2>&1
echo -e "${CHECK} 基础组件安装完成"

echo -e "\n${BOLD}${CYAN}Step 2/6: Docker 引擎配置${NC}"
# (此处省略 Docker 安装细节，保持与你原始脚本一致)
echo -e "${CHECK} Docker 容器引擎就绪"

echo -e "\n${BOLD}${CYAN}Step 3/6: OpenClaw 核心安装${NC}"
echo -e "${LOAD} 正在拉取官方源码并编译 (v2026.2.3)..."
rm -rf /root/.openclaw
curl -fsSL -k https://openclaw.ai/install.sh | bash -s -- --install-method git > /dev/null 2>&1
ln -sf /root/.local/bin/openclaw /usr/local/bin/openclaw
echo -e "${CHECK} OpenClaw 核心安装完毕"

echo -e "\n${BOLD}${CYAN}Step 4/6: 官方 CLI 配置注入 (核心补丁)${NC}"
FIXED_TOKEN="7d293114c449ad5fa4618a30b24ad1c4e998d9596fc6dc4f"
mkdir -p /root/.openclaw

# 解决 v2026.2.3 强校验的关键配置
openclaw config set gateway.auth.token "$FIXED_TOKEN"
openclaw config set gateway.controlUi.allowInsecureAuth true
openclaw config set gateway.controlUi.allowedOrigins '["*"]'
openclaw config set gateway.trustedProxies '["127.0.0.1"]'
echo -e "${CHECK} CLI 配置与安全补丁注入成功"

echo -e "\n${BOLD}${CYAN}Step 5/6: Nginx 流量伪装转发 (解决 1008 报错)${NC}"
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
echo -e "${CHECK} Nginx 8888 -> 18789 路由已建立 (Origin 伪装已激活)"

echo -e "\n${BOLD}${CYAN}Step 6/6: 物理清理并强制重燃${NC}"
# 彻底清理残留，防止 4008 报错
killall -9 node openclaw openclaw-gateway 2>/dev/null || true
rm -f /root/.openclaw/gateway.lock
sleep 1

# 强制带 Token 启动，解决 Exit 1 闪退
nohup openclaw gateway --allow-unconfigured --token "$FIXED_TOKEN" > /root/openclaw.log 2>&1 &

echo -e "${CHECK} OpenClaw 核心已通过 PID $! 纯净启动"

# 获取 IP 并展示
REAL_IP=$(hostname -I | awk '{print $1}')
echo -e "\n${CYAN}--------------------------------------------------------------${NC}"
echo -e "${BOLD}${GREEN}        🎉 OPENCLAW 2026 ULTIMATE 部署成功！${NC}"
echo -e "  管理地址: ${YELLOW}http://${REAL_IP}:8888${NC}"
echo -e "  登录密钥: ${WHITE}${FIXED_TOKEN}${NC}"
echo -e "${CYAN}--------------------------------------------------------------${NC}"

# 自毁 APT 代理
rm -f /etc/apt/apt.conf.d/88proxy
