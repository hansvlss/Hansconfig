#!/bin/bash
# =================================================================
# OpenClaw 2026 官方 Docker 版 (环境自适应 & 代理注入版)
# =================================================================

TITLE_G="\033[1;32m"
STEP_W="\033[0;37m"
NC="\033[0m"
ARROW="${TITLE_G} ● ${NC}" 

# 【配置区】请确认你的代理地址
MY_PROXY="http://127.0.0.1:7890"

# --- 进度条函数 (已补回) ---
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
        exit 1
    fi
}

CONTAINER_NAME="openclaw"
CLAW_TOKEN=$(openssl rand -hex 16)
IP_ADDR=$(hostname -I | awk '{print $1}')

echo -e "\n${TITLE_G}=================================================================="
echo -e "         🦞 OpenClaw 官方 Docker 部署 (正式修正版)"
echo -e "==================================================================${NC}\n"

# 1. 检查并安装 Docker
if ! command -v docker &> /dev/null; then
    run_with_dots "正在安装 Docker 基础环境" "curl -fsSL https://get.docker.com | bash"
    run_with_dots "正在启动 Docker 服务" "systemctl enable --now docker"
fi

# 2. 配置 Docker 系统代理 (确保拉取镜像不超时)
run_with_dots "正在配置 Docker 系统代理" "
mkdir -p /etc/systemd/system/docker.service.d
cat << EOF > /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment=\"HTTP_PROXY=$MY_PROXY\"
Environment=\"HTTPS_PROXY=$MY_PROXY\"
EOF
systemctl daemon-reload
systemctl restart docker
"

# 3. 停止并拉取官方镜像
run_with_dots "正在清理旧容器并拉取官方镜像" "
docker rm -f $CONTAINER_NAME > /dev/null 2>&1
docker pull openclaw/gateway:latest
"

# 4. 运行容器 (注入容器内代理)
run_with_dots "正在启动 OpenClaw 容器" "
docker run -d \
  --name $CONTAINER_NAME \
  -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  -e http_proxy='$MY_PROXY' \
  -e https_proxy='$MY_PROXY' \
  --restart always \
  openclaw/gateway:latest
"

# 5. 自动化初始化
run_with_dots "正在执行官方 onboard 初始化" "
sleep 5
docker exec $CONTAINER_NAME bash -c \"
  printf 'y\n' | openclaw onboard > /dev/null 2>&1
  openclaw config set gateway.mode local
  openclaw config set gateway.auth.token '$CLAW_TOKEN'
\"
"

# 结算单
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m         🦞 OpenClaw 官方 Docker 部署成功！ \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "   管理后台: \033[1;36mhttp://$IP_ADDR:18789/#token=$CLAW_TOKEN\033[0m"
echo -e ""
echo -e "   代理设置: \033[1;33m$MY_PROXY\033[0m (已注入系统与容器)"
echo -e "   持久化目录: \033[1;37m~/.openclaw\033[0m"
echo ""
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "   更多教程: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 分享\033[0m"
