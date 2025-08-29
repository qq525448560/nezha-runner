#!/bin/bash

# ========== 彩色变量 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INFO_FILE="$HOME/.nezha_agent_info"
WORKDIR="$HOME/nezha-agent"
LOG_FILE="$WORKDIR/agent.log"
PID_FILE="$WORKDIR/agent.pid"
CONFIG_FILE="$WORKDIR/nezha-agent.yaml"

# ========== 参数 -v 查看节点信息 ==========
if [ "$1" = "-v" ]; then
    if [ -f "$INFO_FILE" ]; then
        echo -e "${GREEN}========= 哪吒 Agent 节点信息 =========${NC}"
        cat "$INFO_FILE"
    else
        echo -e "${RED}未找到节点信息文件${NC}"
        echo -e "${YELLOW}请先运行部署脚本安装哪吒 Agent${NC}"
    fi
    exit 0
fi

# ========== 功能函数 ==========
install_agent() {
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || exit 1

    echo -e "${BLUE}请输入哪吒服务端地址 (默认: nz.xmm.asia:8008): ${NC}"
    read -rp "> " NZ_SERVER
    NZ_SERVER=${NZ_SERVER:-"nz.xmm.asia:8008"}

    echo -e "${BLUE}是否启用TLS? (true/false, 默认: false): ${NC}"
    read -rp "> " NZ_TLS
    NZ_TLS=${NZ_TLS:-"false"}

    echo -e "${BLUE}请输入哪吒 Client Secret (默认: 2FIezSjN1tEmZgtM0QhKfBlKsufDvFAT): ${NC}"
    read -rp "> " NZ_CLIENT_SECRET
    NZ_CLIENT_SECRET=${NZ_CLIENT_SECRET:-"2FIezSjN1tEmZgtM0QhKfBlKsufDvFAT"}

    # 写配置文件
    cat > "$CONFIG_FILE" <<EOF
server: "$NZ_SERVER"
client_secret: "$NZ_CLIENT_SECRET"
tls: ${NZ_TLS,,}
EOF
    echo -e "${GREEN}配置文件已生成: $CONFIG_FILE${NC}"

    # 下载二进制
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64) ASSET="nezha-agent_linux_amd64.zip" ;;
        aarch64|arm64) ASSET="nezha-agent_linux_arm64.zip" ;;
        *) ASSET="nezha-agent_linux_amd64.zip" ;;
    esac
    URL="https://github.com/nezhahq/agent/releases/latest/download/$ASSET"

    echo -e "${BLUE}下载 Agent 二进制...${NC}"
    curl -fsSL "$URL" -o agent.zip || { echo -e "${RED}下载失败${NC}"; exit 1; }
    unzip -o agent.zip >/dev/null
    chmod +x nezha-agent

    echo -e "${GREEN}Agent 已下载并解压${NC}"

    # 启动
    nohup ./nezha-agent --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    echo "NZ_SERVER=$NZ_SERVER" > "$INFO_FILE"
    echo "NZ_TLS=$NZ_TLS" >> "$INFO_FILE"
    echo "NZ_CLIENT_SECRET=$NZ_CLIENT_SECRET" >> "$INFO_FILE"

    echo -e "${GREEN}Agent 已启动，PID: $(cat $PID_FILE)${NC}"
    echo -e "${YELLOW}日志文件: $LOG_FILE${NC}"
}

status_agent() {
    if [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE")" >/dev/null 2>&1; then
        echo -e "${GREEN}Agent 正在运行, PID: $(cat $PID_FILE)${NC}"
    else
        echo -e "${RED}Agent 未运行${NC}"
    fi
}

stop_agent() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        rm -f
