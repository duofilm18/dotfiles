#!/bin/bash
# install-docker.sh - 在 WSL 安裝 Docker Engine
set -e

echo "📦 安裝 Docker Engine..."

# 安裝必要套件
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# 加入 Docker 官方 GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 加入 Docker repo
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安裝 Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 讓使用者不用 sudo 就能用 docker
sudo usermod -aG docker $USER

# 啟動 Docker
sudo service docker start

echo ""
echo "✅ Docker 安裝完成！"
echo ""
echo "⚠️  請執行以下指令讓群組生效："
echo "   newgrp docker"
echo ""
echo "或重新開啟終端機"
