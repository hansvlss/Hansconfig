#!/bin/bash

# =================================================================
# OpenClaw Pro - Final Stable Edition (2026.03.08)
# 修正内容：解决 Nginx 启动过快导致的 502 报错
# 特点：只优化 UI 视觉，核心逻辑 0 改动
# =================================================================

# 定义经典绿色配色
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 定义统一的打勾和箭头符号
CHECK="${G_BOLD}✔${NC}"
STEP="${G_BOLD}➤${NC}"

# 中文错误处理函数 (保持原版原样)
check_step() {
    if [ $? -ne 0 ]; then
        echo -e "\n${RED}[错误] $1 失败了！${NC}"
        echo -e "${YELLOW}建议检查：$2${NC}"
        exit 1
    fi
}

clear
echo -e "${G_BOLD}=================================================================="
echo -e "           OpenClaw 网关专家级全自动部署系统 (2026)"
echo -e "==================================================================${NC}"

# 1-5 步保持你最稳的逻辑 (IP 获取、Node 安装、NPM 安装、配置生成)
USER_IP=$(hostname -I | awk '{print $1}')
echo -e "${G_BOLD}[成功] 当前检测到 IP: ${USER_IP}${NC}"

echo -e "${G_NORM}➤ 正在配置环境与安装程序...${NC}"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl psmisc > /dev/null 2>&1

echo -e "${G_NORM}➤ 正在从镜像站拉取 OpenClaw 程序...${NC}"
npm install -g openclaw@latest --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
# 修正：安装后强制刷新系统路径缓存
hash -r
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null

DYNAMIC_TOKEN=$(openssl rand -hex 24)
mkdir -p ~/.openclaw
rm -f ~/.openclaw/openclaw.json*
cat > ~/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": { "token": "${DYNAMIC_TOKEN}" },
    "controlUi": {
      "allowedOrigins": [ "https://${USER_IP}:8888", "https://127.0.0.1:8888", "http://localhost:18789" ]
    }
  }
}
EOF
echo -e "${G_BOLD}[成功] 配置文件已动态生成。${NC}"

# 6. 配置 Nginx SSL (仅写入配置，暂不强制重启)
echo -e "${G_NORM}➤ 正在配置 Nginx HTTPS 隧道...${NC}"
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1

rm -rf /etc/nginx/sites-enabled/*
cat > /etc/nginx/sites-available/openclaw <<EOF
server {
    listen 8888 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    location / {
        proxy_pass http://127.0.0.1:18789;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host localhost;
        proxy_set_header Origin http://localhost:18789;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
ln -sf /etc/nginx/sites-available/openclaw /etc/nginx/sites-enabled/default
nginx -t > /dev/null 2>&1
check_step "Nginx 语法检查" "手动运行 'nginx -t' 查看报错"

# 7. 核心修正：先启网关，后启 Nginx
echo -e "${G_NORM}➤ 正在唤醒 OpenClaw 后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
fuser -k 18789/tcp 2>/dev/null || true 

# 使用物理绝对路径拉起，防止 11fa 节点 command not found
OPENCLAW_PATH=$(npm config get prefix)/bin/openclaw
$OPENCLAW_PATH gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 关键验证循环 (逻辑原样保留)
V_DONE=0
for i in {1..20}; do
    if ss -lntp | grep -q ":18789" || curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${G_BOLD}  ${CHECK} 网关后端已就绪，正在激活 Nginx 隧道关联...${NC}"
        # 这里执行你发现“运行了就正常”的命令
        /usr/sbin/nginx -s reload 2>/dev/null || systemctl restart nginx
        V_DONE=1
        break
    fi
    echo -e "${G_NORM}等待后端响应中... ($i/20)${NC}"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT READY                 │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo -e "${G_NORM}${BOLD}▶ 访问地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
    echo -e "${G_NORM}${BOLD}▶ 登录令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
    echo -e "${G_NORM}--------------------------------------------------------------"
    echo -e "授权指令 (请复制执行): ${G_BOLD}openclaw devices approve <ID>${NC}"
    echo -e "${G_BOLD}==============================================================${NC}\n"
else
    # 失败时尝试最后拉起一次 Nginx 以便用户排查 (逻辑原样保留)
    systemctl restart nginx || /usr/sbin/nginx
    echo -e "${RED}[警告] 启动较慢，如页面 502 请稍后手动刷新尝试。${NC}"
fi
