#!/bin/bash
# HansCN OpenClaw Installer (稳定版)

GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m'

echo -e "\n${WHITE}==============================${NC}"
echo -e "${WHITE}   🦞 OpenClaw 安装程序${NC}"
echo -e "${WHITE}==============================${NC}\n"

# =========================
# 基础组件
# =========================
echo -e "${WHITE}● 安装基础依赖...${NC}"
apt-get update
apt-get install -y curl git build-essential

# =========================
# Node.js 20（稳定）
# =========================
echo -e "${WHITE}● 安装 Node.js 20...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash
apt-get install -y nodejs

node -v
npm -v

# =========================
# 安装 OpenClaw
# =========================
echo -e "\n${WHITE}● 安装 OpenClaw（核心步骤）...${NC}"
npm install -g openclaw@latest

if [ $? -ne 0 ]; then
    echo -e "\n${RED}❌ 安装失败${NC}"
    echo -e "${RED}👉 90%原因：代理没生效${NC}"
    exit 1
fi

# =========================
# 初始化
# =========================
echo -e "\n${WHITE}● 初始化 OpenClaw...${NC}"
printf 'y\n' | openclaw onboard

openclaw config set gateway.mode local
openclaw config set gateway.port 18789
openclaw config set gateway.bind loopback

# =========================
# 完成
# =========================
echo -e "\n${GREEN}🚀 OpenClaw 安装完成！${NC}"
echo -e "启动：openclaw gateway"
echo -e "访问：http://localhost:18789"
