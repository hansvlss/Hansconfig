#!/bin/bash

# ----------------------------------------------------------------
# OpenClaw LXC Native Pro Edition (v2026.4 Native)
# ----------------------------------------------------------------

set -e

# --- 颜色定义 ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}开始部署 OpenClaw Native 模式 (PVE LXC 优化版)...${NC}"

# 1. 环境准备 (清理旧 Docker 冲突)
docker rm -f openclaw-gateway 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

# 2. 安装 Node.js 与基础依赖
echo -e "${YELLOW}STEP [1/4] 安装原生环境 (Node.js v20)...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs nginx psmisc build-essential > /dev/null

# 3. 安装 OpenClaw CLI
echo -e "${YELLOW}STEP [2/4] 安装官方核心组件...${NC}"
npm install -g @openclaw/cli

# 4. 初始化配置 (跳过交互，静默创建)
echo -e "${YELLOW}STEP [3/4] 初始化 Workspace...${NC}"
mkdir -p /root/.openclaw/workspace
# 强制创建基础配置文件，防止 502
cat > /root/.openclaw/config.yaml <<EOF
gateway:
  port: 18789
  bind: 127.0.0.1
  auth:
    mode: token
    token: "7d293114c449ad5fa4618a30b24ad1c4e998d9596fc6dc4f"
EOF

# 5. 配置 Systemd 守护进程 (这是最稳的方法)
echo -e "${YELLOW}STEP [4/4] 注入 Systemd 动力源...${NC}"
cat > /etc/systemd/system/openclaw.service <<EOF
[Unit]
Description=OpenClaw Gateway Native Service
After=network.target

[Service]
Type=simple
User=root
Environment=OPENCLAW_WORKSPACE=/root/.openclaw/workspace
ExecStart=/usr/bin/openclaw dashboard --port 18789 --addr 127.0.0.1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

# 6. Nginx 修正版转发
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
        proxy_cache_bypass \$http_upgrade;
    }
}
NGX

systemctl restart nginx

# 获取 IP
REAL_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "🚀  ${GREEN}OpenClaw Native 部署成功！${NC}"
echo -e "🔗  管理地址: ${YELLOW}http://${REAL_IP}:8888${NC}"
echo -e "🔑  登录密钥: ${WHITE}7d293114c449ad5fa4618a30b24ad1c4e998d9596fc6dc4f${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
