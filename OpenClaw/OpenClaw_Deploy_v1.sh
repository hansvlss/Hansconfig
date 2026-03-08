#!/bin/bash

# =================================================================
# OpenClaw Pro - Stable Green Edition (2026)
# 核心：保留 Hans 最稳的逻辑，仅增强 UI 视觉与路径自愈
# =================================================================

# 定义经典绿色配色
G_BOLD="\033[1;32m"
G_NORM="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# 中文错误处理函数 (保持你最喜欢的 check_step)
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

# 1. 自动获取当前 IP
USER_IP=$(hostname -I | awk '{print $1}')
[ -z "$USER_IP" ] && echo -e "${RED}[错误] 无法获取 IP，请检查网卡。${NC}" && exit 1
echo -e "${G_BOLD}[成功] 当前检测到 IP: ${USER_IP}${NC}"

# 2. 配置 Node.js v22 环境
echo -e "${G_NORM}➤ 正在配置 Node.js v22 构建环境...${NC}"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - > /dev/null 2>&1
check_step "Node.js 源配置" "请检查网络是否能连接到 nodesource.com"

# 3. 安装依赖包
echo -e "${G_NORM}➤ 正在补齐系统组件 (git, nginx, nodejs)...${NC}"
apt update > /dev/null 2>&1 && apt install -y nodejs git build-essential nginx curl > /dev/null 2>&1
check_step "系统软件安装" "请尝试运行 'apt update' 查看是否有软件源报错"

# 4. 安装 OpenClaw (含路径自动修复)
echo -e "${G_NORM}➤ 正在从镜像站安装 OpenClaw 2026.3.2...${NC}"
npm install -g openclaw@2026.3.2 --unsafe-perm --force --registry=https://registry.npmmirror.com > /dev/null 2>&1
check_step "OpenClaw 程序安装" "请检查磁盘空间或 npm 镜像连接"

# 关键补丁：确保 openclaw 命令全局可用
ln -sf $(npm config get prefix)/bin/openclaw /usr/local/bin/openclaw 2>/dev/null

# 5. 写入配置文件 (动态令牌)
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
echo -e "${G_BOLD}[成功] 安全配置文件已动态生成。${NC}"

# 6. 配置 Nginx HTTPS 隧道
echo -e "${G_NORM}➤ 正在构建 SSL 加密隧道...${NC}"
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=CN/ST=GD/L=GZ/O=Hans/CN=${USER_IP}" > /dev/null 2>&1
check_step "SSL 证书生成" "请检查 openssl 是否正确安装"

# 强制清理冲突并写入配置
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
check_step "Nginx 语法检查" "手动运行 'nginx -t' 查看第几行报错"

# 暴力重启 Nginx 确保生效
killall -9 nginx 2>/dev/null || true
/usr/sbin/nginx || systemctl restart nginx
check_step "Nginx 隧道激活" "请检查 8888 端口是否被占用"

# 7. 启动并执行健康检查
echo -e "${G_NORM}➤ 正在唤醒 OpenClaw 后端服务...${NC}"
killall -9 openclaw 2>/dev/null || true
openclaw gateway run --allow-unconfigured > /tmp/openclaw.log 2>&1 &

# 循环检查 (保持你的 15 次重试逻辑)
V_DONE=0
for i in {1..15}; do
    if curl -s http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null; then
        echo -e "${G_BOLD}[成功] 网关已就绪！执行最终隧道关联...${NC}"
        /usr/sbin/nginx -s reload 2>/dev/null || systemctl restart nginx
        V_DONE=1
        break
    fi
    echo -e "${G_NORM}正在等待后端响应... ($i/15)${NC}"
    sleep 2
done

if [ "$V_DONE" == "1" ]; then
    echo -e "\n${G_BOLD}┌────────────────────────────────────────────────────────────┐"
    echo -e "│                部署成功 / DEPLOYMENT SUCCESS               │"
    echo -e "└────────────────────────────────────────────────────────────┘${NC}"
    echo -e "${G_NORM}${BOLD}▶ 访问地址:${NC} ${G_BOLD}https://${USER_IP}:8888${NC}"
    echo -e "${G_NORM}${BOLD}▶ 登录令牌:${NC} ${G_BOLD}${DYNAMIC_TOKEN}${NC}"
    echo -e "${G_NORM}--------------------------------------------------------------"
    echo -e "${G_BOLD}后续操作：${NC}"
    echo -e " 1. 浏览器打开页面并输入令牌登录"
    echo -e " 2. 在终端执行授权: ${G_BOLD}openclaw devices approve <ID>${NC}"
    echo -e "${G_BOLD}==============================================================${NC}\n"
else
    echo -e "${RED}[错误] 网关启动超时，请查看日志: cat /tmp/openclaw.log${NC}"
fi
