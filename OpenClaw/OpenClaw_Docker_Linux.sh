#!/bin/bash
# =================================================================
# OpenClaw 2026 官方 Docker 部署 (全环境自适应版)
# =================================================================

TITLE_G="\033[1;32m"
STEP_W="\033[0;37m"
NC="\033[0m"
ARROW="${TITLE_G} ● ${NC}" 

# 【核心配置】请确认你的代理端口
MY_PROXY="http://127.0.0.1:7890"

# --- 进度条函数 ---
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
        echo -e "\033[1;31m报错详情: 请手动尝试执行命令: $cmd\033[0m"
        exit 1
    fi
}

echo -e "\n${TITLE_G}=================================================================="
echo -e "         🦞 OpenClaw 官方 Docker 部署 (Hans 专属定制版)"
echo -e "==================================================================${NC}\n"

# 1. 代理连通性前置检查
printf "${ARROW}${STEP_W}正在检测代理网络 ($MY_PROXY) ...${NC}"
if curl -sx $MY_PROXY --connect-timeout 3 https://www.google.com > /dev/null 2>&1; then
    echo -e " [ ${TITLE_G}可用${NC} ]"
else
    echo -e " [ \033[1;31m不可用\033[0m ]"
    echo -e "⚠️  警告: 检测到代理无法连接 Google，OpenClaw 启动后可能无法对话。"
    read -p "是否继续安装? (y/n): " confirm
    [[ "$confirm" != "y" ]] && exit 1
fi

# 2. 安装 Docker (如果不存在)
if ! command -v docker &> /dev/null; then
    run_with_dots "正在下载并安装 Docker" "curl -fsSL https://get.docker.com | bash"
    systemctl enable --now docker > /dev/null 2>&1
fi

# 3. 配置 Docker 镜像加速与系统代理
# 这里加入了多个国内备用镜像站，防止单个失效
run_with_dots "正在配置 Docker 加速器与系统代理" "
mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  \"registry-mirrors\": [
    \"https://docker.m.daocloud.io\",
    \"https://dockerproxy.com\",
    \"https://mirror.baidubce.com\",
    \"https://docker.nju.edu.cn\"
  ]
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
cat << EOF > /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment=\"HTTP_PROXY=$MY_PROXY\"
Environment=\"HTTPS_PROXY=$MY_PROXY\"
Environment=\"NO_PROXY=localhost,127.0.0.1\"
EOF
systemctl daemon-reload
systemctl restart docker
"

# 4. 清理并拉取镜像
run_with_dots "正在清理旧容器并拉取官方镜像" "
docker rm -f openclaw > /dev/null 2>&1
docker pull openclaw/gateway:latest
"

# 5. 启动容器 (注入代理环境变量)
CLAW_TOKEN=$(openssl rand -hex 16)
run_with_dots "正在启动 OpenClaw 容器" "
docker run -d \
  --name openclaw \
  -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  -e http_proxy='$MY_PROXY' \
  -e https_proxy='$MY_PROXY' \
  --restart always \
  openclaw/gateway:latest
"

# 6. 自动化初始化
run_with_dots "正在初始化官方配置 (Onboard)" "
sleep 5
docker exec openclaw bash -c \"
  printf 'y\n' | openclaw onboard > /dev/null 2>&1
  openclaw config set gateway.mode local
  openclaw config set gateway.auth.token '$CLAW_TOKEN'
\"
"

# 结算单
IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "\n\033[1;34m==================================================================\033[0m"
echo -e "\033[1;32m         🦞 OpenClaw 部署成功！ \033[0m"
echo -e "\033[1;34m==================================================================\033[0m"
echo -e ""
echo -e "   访问地址: \033[1;36mhttp://$IP_ADDR:18789/#token=$CLAW_TOKEN\033[0m"
echo -e ""
echo -e "   代理状态: \033[1;32m已成功注入容器\033[0m"
echo -e "   配置文件: \033[1;37m~/.openclaw (已映射，删除容器不丢失配置)\033[0m"
echo ""
echo -e "\033[1;34m==================================================================\033[0m"
echo -e "   教程参考: \033[4;37mhanscn.com\033[0m | \033[1;35mHans 分享\033[0m"
