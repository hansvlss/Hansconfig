#!/bin/bash

# =====================================================
# HansCN OpenClaw LXC Installer 2026 Stable
# for Debian / Ubuntu / PVE LXC
# =====================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   OpenClaw 2026 LXC 自动部署脚本${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo -e "${YELLOW}STEP 1: 检测系统${NC}"

if [ "$(id -u)" != "0" ]; then
  echo -e "${RED}请使用 root 运行${NC}"
  exit 1
fi

if grep -qa container=lxc /proc/1/environ; then
  echo "检测到 LXC 环境"
else
  echo "未检测到 LXC（也可继续运行）"
fi

echo ""
echo -e "${YELLOW}STEP 2: 更新系统${NC}"

apt update -y
apt install -y curl git sudo

echo ""
echo -e "${YELLOW}STEP 3: 安装 Docker${NC}"

if ! command -v docker &> /dev/null
then
  apt install -y docker.io docker-compose
  systemctl enable docker
  systemctl start docker
else
  echo "Docker 已安装"
fi

echo ""
echo -e "${YELLOW}STEP 4: 检查 Docker${NC}"

docker version

echo ""
echo -e "${YELLOW}STEP 5: 下载 OpenClaw${NC}"

cd /opt

if [ -d "openclaw" ]; then
  echo "检测到旧目录，更新"
  cd openclaw
  git pull
else
  git clone https://github.com/openclaw/openclaw
  cd openclaw
fi

echo ""
echo -e "${YELLOW}STEP 6: 启动 OpenClaw${NC}"

chmod +x docker-setup.sh
./docker-setup.sh

echo ""
echo -e "${YELLOW}STEP 7: 启动容器${NC}"

docker compose up -d

echo ""
IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OpenClaw 已部署成功${NC}"
echo -e "${GREEN}========================================${NC}"

echo ""
echo "访问地址:"
echo "http://$IP:18789"

echo ""
echo "初始化命令:"
echo "cd /opt/openclaw"
echo "docker compose run --rm openclaw-cli onboard"

echo ""
echo "启动 Dashboard:"
echo "docker compose run --rm openclaw-cli dashboard"

echo ""
echo -e "${GREEN}部署完成${NC}"
