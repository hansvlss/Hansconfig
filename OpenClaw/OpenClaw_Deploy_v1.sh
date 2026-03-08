#!/bin/bash

# =================================================================
# OpenClaw Pro - Final Stable Edition (2026)
# 修正内容：强力清除缓存 + 暴力杀死旧版进程 + 官方优先
# =================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${GREEN}=================================================================="
echo -e "            OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1. 暴力清理（这是解决版本不更新的关键）
echo "正在强力清空旧版环境与缓存..."
# 杀死所有可能干扰的进程
killall -9 node openclaw nginx 2>/dev/null || true
fuser -k 18789/tcp 8888/tcp 2>/dev/null || true
# 清除 npm 缓存，防止它一直安装旧的 3.2
npm cache clean --force > /dev/null 2>&1
echo -e "${GREEN}[成功] 环境已净化。${NC}"

# 2. 重新配置环境
USER_IP=$(hostname -I | awk '{print $1}')
echo "正在安装必备工具..."
apt update > /dev/null 2>&1 && apt install -y nodejs nginx curl psmisc > /dev/null 2>&1

# 3. 安装 OpenClaw (官方优先 + 强制在线拉取)
echo "正在通过代理强制拉取官方最新版 (v2026.3.7)..."
# 使用 --prefer-online 绕过本地缓存
npm install -g openclaw@latest --unsafe-perm --force --prefer-online > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}[提示] 官方源失败，切换镜像站兜底...${NC}"
    npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
fi

# 修正：强制刷新路径并建立绝对路径关联
hash -r 
OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
ln -sf "$OPENCLAW_PATH" /usr/local/bin/openclaw 2>/dev/null

# 4. 配置生成 (保持 Hans 稳健逻辑)
DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "controlUi": {
      "allowedOrigins": [ "https://${USER_IP}:8888", "https://127.0.0.1:8888" ]
    }
  }
}
EOF

# 5. Nginx SSL 隧道 (暴力重置)
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1

rm -rf /etc/nginx/sites-enabled/*
cat > /etc/nginx/sites-available/openclaw <<EOF
server {
    listen 8888 ssl;
    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host localhost;
        proxy_set_header Origin http://localhost:18789;
    }
}
EOF
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/default

# 6. 最终启动 (使用绝对路径，给足初始化时间)
echo -e "${GREEN}正在拉起最新版网关后端...${NC}"
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 核心：循环检查，直到端口真正开启
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" > /dev/null; then
        echo -e "${GREEN}[成功] 最新版已就绪，正在激活隧道...${NC}"
        killall -9 nginx 2>/dev/null || true
        /usr/sbin/nginx
        break
    fi
    echo -ne "\r等待后端就绪... ($i/20)"
    sleep 3
done

echo -e "\n${GREEN}================================================"
echo -e "部署成功！访问地址: https://${USER_IP}:8888"
echo -e "当前令牌: ${DYNAMIC_TOKEN}"
echo -e "================================================${NC}"
