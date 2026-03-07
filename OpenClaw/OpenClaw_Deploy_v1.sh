#!/bin/bash

set -e

echo "==============================="
echo "OpenClaw Auto Install Script"
echo "Debian 12 / PVE LXC"
echo "==============================="

echo "STEP 1: 更新系统"
apt update -y

echo "STEP 2: 安装依赖"
apt install -y \
curl \
git \
ca-certificates \
docker.io \
docker-compose

echo "STEP 3: 启动 Docker"
systemctl enable docker
systemctl restart docker

echo "Docker version:"
docker --version
docker-compose version

echo "STEP 4: 下载 OpenClaw"

cd /opt

if [ -d "openclaw" ]; then
    rm -rf openclaw
fi

git clone https://github.com/openclaw/openclaw.git

echo "STEP 5: 进入 docker 目录"

cd /opt/openclaw/docker

echo "STEP 6: 拉取镜像"

docker-compose pull

echo "STEP 7: 启动服务"

docker-compose up -d

echo "==============================="
echo "OpenClaw 已启动"
echo "==============================="

IP=$(hostname -I | awk '{print $1}')

echo "访问地址:"
echo "http://$IP:3000"

echo ""
echo "查看容器状态:"
docker ps
