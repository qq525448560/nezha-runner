set -eu

# 默认值（可在运行时通过环境变量覆盖）
: "${NZ_SERVER:=nz.xmm.asia:8008}"
: "${NZ_TLS:=false}"
: "${NZ_CLIENT_SECRET:=2FIezSjN1tEmZgtM0QhKfBlKsufDvFAT}"
# 重启间隔（秒）
: "${RESTART_DELAY:=5}"

INSTALL_URL="https://raw.githubusercontent.com/nezhahq/scripts/main/agent/install.sh"
TMPDIR="$(mktemp -d)"
CWD="$(pwd)"
CONFIG_FILE="$CWD/nezha-agent.yaml"
LOG_FILE="$CWD/agent.log"
PID_FILE="$CWD/agent.pid"
BINARY_PATH="$CWD/nezha-agent"

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "工作目录: $CWD"
echo "临时目录: $TMPDIR"
echo "NZ_SERVER=$NZ_SERVER NZ_TLS=$NZ_TLS"

echo
echo "1) 下载 install.sh ..."
curl -fsSL "$INSTALL_URL" -o "$TMPDIR/agent.sh" || {
  echo "下载 install.sh 失败。"
  # 继续回退流程
}
chmod +x "$TMPDIR/agent.sh" 2>/dev/null || true

echo
echo "2) 尝试以环境变量运行 install.sh（若无权限会失败）"
set +e
if [ -x "$TMPDIR/agent.sh" ]; then
  env NZ_SERVER="$NZ_SERVER" NZ_TLS="$NZ_TLS" NZ_CLIENT_SECRET="$NZ_CLIENT_SECRET" "$TMPDIR/agent.sh"
  RC=$?
else
  RC=1
fi
set -e

if [ $RC -eq 0 ]; then
  echo "install.sh 执行成功。"
  exit 0
fi

echo
echo "install.sh 失败（退出码 $RC 或无可执行脚本）。回退到直接运行 nezha-agent 二进制。"

# 选择平台二进制（zip）
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ASSET="nezha-agent_linux_amd64.zip" ;;
  aarch64|arm64) ASSET="nezha-agent_linux_arm64.zip" ;;
  *) 
    echo "无法识别架构: $ARCH，尝试使用 amd64 二进制。"
    ASSET="nezha-agent_linux_amd64.zip"
    ;;
esac

RELEASE_URL="https://github.com/nezhahq/agent/releases/latest/download/$ASSET"
echo "下载二进制: $RELEASE_URL"
curl -fsSL "$RELEASE_URL" -o "$TMPDIR/$ASSET" || {
  echo "下载二进制失败：$RELEASE_URL"
  exit 1
}

echo "解压..."
if command -v unzip >/dev/null 2>&1; then
  unzip -o "$TMPDIR/$ASSET" -d "$TMPDIR"
elif python3 -c 'import zipfile,sys; sys.exit(0)' 2>/dev/null; then
  python3 - <<PY -c
import zipfile, sys
zipf = "$TMPDIR/$ASSET"
zipfile.ZipFile(zipf).extractall("$TMPDIR")
PY
else
  echo "系统上没有 unzip，也无法用 python 解压，请安装 unzip 或 python。"
  exit 1
fi

# 找可执行文件
BINARY="$(find "$TMPDIR" -type f -name 'nezha-agent*' -perm /111 | head -n1 || true)"
if [ -z "$BINARY" ]; then
  echo "未找到 nezha-agent 可执行文件，列出 $TMPDIR 内容供调试："
  ls -la "$TMPDIR"
  exit 1
fi

cp "$BINARY" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
echo "已准备好 $BINARY_PATH"

# 生成配置文件（使用 client_secret 字段）
cat > "$CONFIG_FILE" <<EOF
server: "$NZ_SERVER"
client_secret: "$NZ_CLIENT_SECRET"
tls: ${NZ_TLS,,}
EOF
echo "已生成配置文件: $CONFIG_FILE"

# supervisor 函数（负责循环重启并处理信号）
run_supervisor() {
  echo "[$(date --iso-8601=seconds)] supervisor start" >> "$LOG_FILE"
  CHILD_PID=0

  _on_term() {
    echo "[$(date --iso-8601=seconds)] supervisor received signal, stopping..." >> "$LOG_FILE"
    if [ "$CHILD_PID" -ne 0 ]; then
      kill "$CHILD_PID" 2>/dev/null || true
      wait "$CHILD_PID" 2>/dev/null || true
    fi
    # remove pid file
    [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
    exit 0
  }

  trap _on_term TERM INT

  while true; do
    echo "[$(date --iso-8601=seconds)] starting nezha-agent --config $CONFIG_FILE" >> "$LOG_FILE"
    # 启动 agent（前台），子进程为 $!
    "$BINARY_PATH" --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
    CHILD_PID=$!
    # 将 child 的退出码和信息记录
    wait "$CHILD_PID"
    EXIT_CODE=$?
    echo "[$(date --iso-8601=seconds)] nezha-agent exited with code $EXIT_CODE" >> "$LOG_FILE"

    # 如果 supervisor 收到 SIGTERM，trap 会退出
    echo "[$(date --iso-8601=seconds)] will restart after ${RESTART_DELAY}s" >> "$LOG_FILE"
    sleep "$RESTART_DELAY"
  done
}

# 启动 supervisor 到后台，并把 supervisor PID 写入 agent.pid
nohup bash -c 'run_supervisor' > /dev/null 2>&1 &

# But above nohup won't see run_supervisor function. Start a subshell that exports the function.
# So use a temporary wrapper file to run the supervisor function in background.
WRAPPER="$TMPDIR/supervisor.sh"
cat > "$WRAPPER" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
# load variables from environment
BINARY_PATH="$1"
CONFIG_FILE="$2"
LOG_FILE="$3"
RESTART_DELAY="$4"

_on_term() {
  echo "[$(date --iso-8601=seconds)] supervisor received signal, stopping..." >> "$LOG_FILE"
  if [ -n "${CHILD_PID-}" ] && [ "${CHILD_PID:-0}" -ne 0 ]; then
    kill "${CHILD_PID}" 2>/dev/null || true
    wait "${CHILD_PID}" 2>/dev/null || true
  fi
  [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
  exit 0
}
trap _on_term TERM INT

while true; do
  echo "[$(date --iso-8601=seconds)] starting nezha-agent --config $CONFIG_FILE" >> "$LOG_FILE"
  "$BINARY_PATH" --config "$CONFIG_FILE" >> "$LOG_FILE" 2>&1 &
  CHILD_PID=$!
  wait "$CHILD_PID"
  EXIT_CODE=$?
  echo "[$(date --iso-8601=seconds)] nezha-agent exited with code $EXIT_CODE" >> "$LOG_FILE"
  echo "[$(date --iso-8601=seconds)] will restart after ${RESTART_DELAY}s" >> "$LOG_FILE"
  sleep "${RESTART_DELAY}"
done
WRAP
chmod +x "$WRAPPER"

nohup "$WRAPPER" "$BINARY_PATH" "$CONFIG_FILE" "$LOG_FILE" "$RESTART_DELAY" >> /dev/null 2>&1 &
SUP_PID=$!
# write supervisor PID
echo "$SUP_PID" > "$PID_FILE"
echo "supervisor started, PID=$SUP_PID (watches $BINARY_PATH)."
echo "日志: $LOG_FILE  PID 文件: $PID_FILE"
echo "停止: kill $SUP_PID"

