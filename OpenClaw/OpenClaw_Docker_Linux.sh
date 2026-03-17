#!/bin/bash
# =================================================================
# OpenClaw 2026 官方 Docker 版 (代理优化 & 自动初始化)
# =================================================================

TITLE_G="\033[1;32m"
STEP_W="\033[0;37m"
NC="\033[0m"
ARROW="${TITLE_G} ● ${NC}" 

# 【手动配置区】请填入你的代理地址
MY_PROXY="http://127.0.0.1:7890" # 改成你实际的代理 IP 和端口

CONTAINER_NAME="openclaw"
CLAW_TOKEN=$(openssl rand -hex 16)
IP_ADDR=$(hostname -I | awk '{print $1}')

echo -e "\n${TITLE_G}=================================================================="
echo -e "         🦞 OpenClaw 官方 Docker 部署 (代理直连版)"
echo -e "==================================================================${NC}\n"

# 1. 检查并配置 Docker 代理 (确保能拉取官方镜像)
if [ ! -d "/etc/systemd/system/docker.service.d" ]; then
    run_with_dots "正在配置 Docker 系统级代理" "
    mkdir -p /etc/systemd/system/docker.service.d
    cat << EOF > /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment=\"HTTP_PROXY=$MY_PROXY\"
Environment=\"HTTPS_PROXY=$MY_PROXY\"
EOF
    systemctl daemon-reload
    systemctl restart docker
    "
fi

# 2. 停止旧容器
docker rm -f $CONTAINER_NAME > /dev/null 2>&1

# 3. 运行容器 (注入环境变量，确保 OpenClaw 内部能上外网)
echo -e "${ARROW}${STEP_W}正在拉取官方镜像并启动...${NC}"
docker run -d \
  --name $CONTAINER_NAME \
  -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  -e http_proxy="$MY_PROXY" \
  -e https_proxy="$MY_PROXY" \
  --restart always \
  openclaw/gateway:latest

# 4. 自动化初始化配置
echo -e "${ARROW}${STEP_W}正在执行官方 onboard 初始化...${NC}"
sleep 5
docker exec $CONTAINER_NAME bash -c "
  printf 'y\n' | openclaw onboard > /dev/null 2>&1
  openclaw config set gateway.mode local
  openclaw config set gateway.auth.token '$CLAW_TOKEN'
"

# 结算单
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m         🦞 OpenClaw 官方版部署成功！ \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "   管理后台: \033[1;36mhttp://$IP_ADDR:18789/#token=$CLAW_TOKEN\033[0m"
echo -e ""
echo -e "\033[1;33m[ 代理状态 ]\033[0m 已自动注入 $MY_PROXY"
echo -e "\033[1;33m[ 官方源码 ]\033[0m https://github.com/openclaw/openclaw"
echo ""
echo -e "\033[1;34m==================================================================\033[0m"
