#!/bin/bash
# =================================================================
# OpenClaw 2026 远程部署脚本 (由 boot.sh 自动调用)
# =================================================================

# 接收 boot.sh 传过来的参数
PROXY_IP=$1
PROXY_PORT=$2
FULL_PROXY="http://${PROXY_IP}:${PROXY_PORT}"

# --- 进度条函数 ---
run_with_dots() {
    local message=$1; local cmd=$2
    printf " ● ${message}"
    eval "$cmd" > /dev/null 2>&1 &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do printf "."; sleep 0.5; done
    wait $pid
    if [ $? -eq 0 ]; then printf " [ 完成 ]\n"; else printf " [ 失败 ]\n"; exit 1; fi
}

# 1. 安装 Docker (如果不存在)
if ! command -v docker &> /dev/null; then
    run_with_dots "正在安装 Docker 基础环境" "curl -fsSL https://get.docker.com | bash"
    systemctl enable --now docker > /dev/null 2>&1
fi

# 2. 配置 Docker 系统代理 (让 Daemon 能拉取官方镜像)
run_with_dots "正在配置 Docker 系统级代理" "
mkdir -p /etc/systemd/system/docker.service.d
cat << EOF > /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment=\"HTTP_PROXY=$FULL_PROXY\"
Environment=\"HTTPS_PROXY=$FULL_PROXY\"
Environment=\"NO_PROXY=localhost,127.0.0.1\"
EOF
systemctl daemon-reload && systemctl restart docker
"

# 3. 部署 OpenClaw 容器
CLAW_TOKEN=$(openssl rand -hex 16)
run_with_dots "正在拉取并启动 OpenClaw 官方镜像" "
docker rm -f openclaw > /dev/null 2>&1
docker run -d --name openclaw -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  -e http_proxy='$FULL_PROXY' -e https_proxy='$FULL_PROXY' \
  --restart always openclaw/gateway:latest
"

# 4. 自动化配置 (Onboard)
run_with_dots "正在执行官方初始化配置" "
sleep 5
docker exec openclaw bash -c \"printf 'y\n' | openclaw onboard > /dev/null 2>&1 && openclaw config set gateway.mode local && openclaw config set gateway.auth.token '$CLAW_TOKEN'\"
"

# 结算单
IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "\n\033[1;32m✔ OpenClaw 部署成功！\033[0m"
echo -e "------------------------------------------------------------"
echo -e "管理地址: \033[1;36mhttp://$IP_ADDR:18789/#token=$CLAW_TOKEN\033[0m"
echo -e "代理路径: \033[1;33m$FULL_PROXY\033[0m"
echo -e "------------------------------------------------------------"
