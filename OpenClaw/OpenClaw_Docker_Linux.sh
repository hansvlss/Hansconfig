#!/bin/bash
# OpenClaw_Docker_Linux.sh (托管在 GitHub)

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
    printf " [ 完成 ]\n"
}

# 1. 安装 Docker
if ! command -v docker &> /dev/null; then
    run_with_dots "正在安装 Docker" "curl -fsSL https://get.docker.com | bash"
fi

# 2. 配置 Docker 系统代理 (让 Daemon 能拉取镜像)
run_with_dots "正在配置 Docker 系统代理" "
mkdir -p /etc/systemd/system/docker.service.d
cat << EOF > /etc/systemd/system/docker.service.d/proxy.conf
[Service]
Environment=\"HTTP_PROXY=$FULL_PROXY\"
Environment=\"HTTPS_PROXY=$FULL_PROXY\"
EOF
systemctl daemon-reload && systemctl restart docker
"

# 3. 部署容器
CLAW_TOKEN=$(openssl rand -hex 16)
run_with_dots "正在拉取并启动 OpenClaw" "
docker rm -f openclaw > /dev/null 2>&1
docker run -d --name openclaw -p 18789:18789 \
  -v ~/.openclaw:/root/.openclaw \
  -e http_proxy='$FULL_PROXY' -e https_proxy='$FULL_PROXY' \
  --restart always openclaw/gateway:latest
"

# 4. 初始化
sleep 5
docker exec openclaw bash -c "printf 'y\n' | openclaw onboard > /dev/null 2>&1 && openclaw config set gateway.mode local && openclaw config set gateway.auth.token '$CLAW_TOKEN'" > /dev/null

echo -e "\n\033[1;32mOpenClaw 部署成功！\033[0m"
echo -e "管理地址: http://$(hostname -I | awk '{print $1}'):18789/#token=$CLAW_TOKEN"
