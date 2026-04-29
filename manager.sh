#!/usr/bin/env bash
#
# AI-Bot macOS manager
#
# ./manager.sh help：显示帮助说明
# ./manager.sh doctor：检查 macOS 本地开发环境
# ./manager.sh update：更新仓库并安装后端、前端、可选 bridge 依赖
# ./manager.sh dev：一键启动后台后端，再前台运行 Flutter macOS
# ./manager.sh app-dev：只启动 Flutter macOS，保留原生热重载
# ./manager.sh server-dev：只前台启动后端
# ./manager.sh server-start：后台启动后端
# ./manager.sh backend-restart：重启后台后端
# ./manager.sh bridge-start：后台启动可选 WhatsApp bridge
# ./manager.sh bridge-dev：前台启动可选 WhatsApp bridge
# ./manager.sh logs [server|bridge]：查看后台日志
# ./manager.sh status：查看后台进程状态
# ./manager.sh stop：停止后台后端和 bridge
# ./manager.sh clean：清理 Flutter 构建、Python 缓存和脚本状态文件
# ./manager.sh build-macos：构建 macOS release 包
# ./manager.sh open-build：打开 macOS 构建产物
# ./manager.sh db-view [port]：在 localhost 打开只读 SQLite 可视化表浏览器
# dev / app-dev 中按 r：Flutter 热重载
# dev / app-dev 中按 R：Flutter 热重启
# dev / app-dev 中按 q：退出 Flutter 会话
# 另开终端执行 ./manager.sh backend-restart：在前端继续运行时单独重启后端
# WhatsApp bridge：可选能力，主链路默认不依赖
# dev 退出后后端仍会保留：需要时用 ./manager.sh stop 停止
# 如果 8765 已有本项目后端在跑：dev 会直接复用，不再误判为启动失败

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"
APP_DIR="$ROOT_DIR/app"
BRIDGE_DIR="$SERVER_DIR/bridge"
STATE_DIR="$ROOT_DIR/.manager"
SERVER_CONFIG_FILE="$SERVER_DIR/config.yaml"

SERVER_VENV_DIR="$SERVER_DIR/.venv"
SERVER_PYTHON="$SERVER_VENV_DIR/bin/python"
DB_VIEWER_SCRIPT="$SERVER_DIR/tools/sqlite_table_viewer.py"
DB_VIEWER_DB_PATH="$SERVER_DIR/workspace/state.sqlite3"
DB_VIEWER_DEFAULT_PORT="8787"
SERVER_PORT="$(awk '
    /^server:[[:space:]]*$/ { in_server=1; next }
    in_server && /^[^[:space:]]/ { exit }
    in_server && $1 == "port:" { print $2; exit }
' "$SERVER_CONFIG_FILE" 2>/dev/null)"
SERVER_PORT="${SERVER_PORT:-8765}"

SERVER_PID_FILE="$STATE_DIR/server.pid"
BRIDGE_PID_FILE="$STATE_DIR/bridge.pid"
SERVER_LOG_FILE="$STATE_DIR/server.log"
BRIDGE_LOG_FILE="$STATE_DIR/bridge.log"

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}AI-Bot macOS Manager${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${CYAN}→ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

usage() {
    cat <<EOF
AI-Bot macOS manager

Commands:
  help                Show this help
  doctor              Check local macOS dev prerequisites
  update              Git pull (when clean) + Python deps + Flutter deps + optional bridge deps
  dev                 Start backend in background, then run Flutter macOS in foreground
  app-dev             Run Flutter desktop app only: flutter run -d macos
  server-dev          Run backend only in foreground
  server-start        Start backend in background
  backend-restart     Restart background backend
  bridge-start        Start optional WhatsApp bridge in background
  bridge-dev          Run optional WhatsApp bridge in foreground
  logs [server|bridge]
                      Tail background service logs (default: server)
  status              Show background process status
  stop                Stop background backend and bridge
  clean               Clean Flutter build files, Python caches, and manager pid/log files
  build-macos         Build Flutter macOS release app
  open-build          Open the macOS build output folder or app bundle
  db-view [port]      Open a read-only SQLite table viewer at localhost

Hot reload / hot restart:
  During \`./manager.sh dev\` or \`./manager.sh app-dev\`:
    r   Flutter hot reload
    R   Flutter hot restart
    q   Quit Flutter session

Backend restart while Flutter keeps running:
  Open another terminal, then run:
    ./manager.sh backend-restart
EOF
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

require_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "未找到命令: $cmd"
        if [ -n "$hint" ]; then
            print_info "$hint"
        fi
        exit 1
    fi
}

ensure_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        print_error "这个脚本当前只为 macOS 本地开发和构建准备。"
        exit 1
    fi
}

read_pid() {
    local pid_file="$1"
    if [ ! -f "$pid_file" ]; then
        return 1
    fi
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
        rm -f "$pid_file"
        return 1
    fi
    echo "$pid"
}

is_pid_running() {
    local pid_file="$1"
    local pid
    pid="$(read_pid "$pid_file" || true)"
    if [ -z "${pid:-}" ]; then
        return 1
    fi
    if kill -0 "$pid" >/dev/null 2>&1; then
        return 0
    fi
    rm -f "$pid_file"
    return 1
}

get_pid_command() {
    local pid="$1"
    ps -p "$pid" -o command= 2>/dev/null || true
}

get_pid_cwd() {
    local pid="$1"
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}

find_listening_pid_on_server_port() {
    lsof -t -nP -iTCP:"$SERVER_PORT" -sTCP:LISTEN 2>/dev/null | head -1
}

is_compatible_backend_pid() {
    local pid="$1"
    local cmd cwd

    cmd="$(get_pid_command "$pid")"
    cwd="$(get_pid_cwd "$pid")"

    [[ "$cmd" == *"main.py"* ]] && [[ "$cwd" == "$SERVER_DIR" ]]
}

adopt_existing_backend_on_port() {
    local pid cmd cwd

    pid="$(find_listening_pid_on_server_port)"
    if [ -z "${pid:-}" ]; then
        return 1
    fi

    cmd="$(get_pid_command "$pid")"
    cwd="$(get_pid_cwd "$pid")"

    if is_compatible_backend_pid "$pid"; then
        ensure_state_dir
        echo "$pid" >"$SERVER_PID_FILE"
        print_info "检测到端口 $SERVER_PORT 上已有本项目后端，检查健康状态"
        if wait_for_server_ready false; then
            print_info "检测到端口 $SERVER_PORT 上已有本项目后端，直接复用 (pid: $pid)"
            return 0
        fi
        print_error "端口 $SERVER_PORT 上的本项目后端未进入 ready，当前不复用该进程"
        return 3
    fi

    print_error "端口 $SERVER_PORT 已被其他进程占用，无法自动启动后端"
    print_info "占用进程 pid: $pid"
    if [ -n "$cmd" ]; then
        print_info "占用命令: $cmd"
    fi
    if [ -n "$cwd" ]; then
        print_info "占用目录: $cwd"
    fi
    print_info "请先释放端口，或改 server/config.yaml 里的 port"
    return 2
}

stop_pid_file() {
    local pid_file="$1"
    local label="$2"
    local pid

    pid="$(read_pid "$pid_file" || true)"
    if [ -z "${pid:-}" ]; then
        print_info "$label 未在后台运行"
        return 0
    fi

    if ! kill -0 "$pid" >/dev/null 2>&1; then
        rm -f "$pid_file"
        print_info "$label 的 pid 文件已过期，已清理"
        return 0
    fi

    print_info "正在停止 $label (pid: $pid)"
    kill "$pid" >/dev/null 2>&1 || true

    local i
    for i in 1 2 3 4 5; do
        if ! kill -0 "$pid" >/dev/null 2>&1; then
            rm -f "$pid_file"
            print_success "$label 已停止"
            return 0
        fi
        sleep 1
    done

    print_warning "$label 未在预期时间内退出，发送强制结束信号"
    kill -9 "$pid" >/dev/null 2>&1 || true
    rm -f "$pid_file"
    print_success "$label 已强制停止"
}

ensure_server_venv() {
    require_cmd python3 "请先安装可用的 Python 3。"
    if [ ! -x "$SERVER_PYTHON" ]; then
        print_info "server/.venv 不存在，正在创建虚拟环境"
        (
            cd "$SERVER_DIR"
            python3 -m venv .venv
        )
        print_success "已创建 $SERVER_VENV_DIR"
    fi
}

update_repo() {
    require_cmd git "请先安装 git。"
    if [ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null || true)" ]; then
        print_warning "当前仓库有未提交修改，跳过 git pull，避免覆盖本地工作。"
        return 0
    fi

    print_info "正在执行 git pull --ff-only"
    git -C "$ROOT_DIR" pull --ff-only
    print_success "仓库更新完成"
}

update_server_deps() {
    ensure_server_venv
    print_info "正在安装/更新 Python 依赖"
    "$SERVER_PYTHON" -m pip install --upgrade pip
    "$SERVER_PYTHON" -m pip install -r "$SERVER_DIR/requirements.txt"
    print_success "Python 依赖已更新"
}

update_app_deps() {
    require_cmd flutter "请先安装 Flutter，并确保 flutter 在 PATH 中。"
    ensure_macos
    print_info "正在执行 flutter pub get"
    (
        cd "$APP_DIR"
        flutter pub get
    )
    print_success "Flutter 依赖已更新"
}

update_bridge_deps() {
    if [ ! -f "$BRIDGE_DIR/package.json" ]; then
        print_warning "未找到 bridge/package.json，跳过 bridge 安装"
        return 0
    fi

    if ! command -v npm >/dev/null 2>&1; then
        print_warning "未找到 npm，跳过可选 WhatsApp bridge 依赖安装"
        return 0
    fi

    print_info "正在安装可选 WhatsApp bridge 依赖"
    (
        cd "$BRIDGE_DIR"
        npm install
        npm run build
    )
    print_success "可选 WhatsApp bridge 依赖已更新"
}

append_log_banner() {
    local log_file="$1"
    local label="$2"
    ensure_state_dir
    {
        echo ""
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== $label ====="
    } >>"$log_file"
}

server_health_url() {
    echo "http://127.0.0.1:$SERVER_PORT/api/health"
}

fetch_server_health() {
    local url="$1"

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 2 "$url"
        return $?
    fi

    python3 - "$url" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
with urllib.request.urlopen(url, timeout=2) as response:
    sys.stdout.write(response.read().decode("utf-8"))
PY
}

summarize_server_health() {
    local payload="$1"
    python3 -c '
import json
import sys

payload = json.loads(sys.argv[1])
ready = "true" if payload.get("ready") is True else "false"
phase = str(payload.get("startup_phase") or "")
port = payload.get("server_port")
print("{}|{}|{}".format(ready, phase, "" if port is None else port))
' "$payload"
}

wait_for_server_ready() {
    local cleanup_on_failure="${1:-true}"
    local url body summary ready phase port
    local max_attempts=30

    url="$(server_health_url)"
    print_info "正在等待后端健康检查 ready=true: $url"

    local attempt
    for attempt in $(seq 1 "$max_attempts"); do
        if ! is_pid_running "$SERVER_PID_FILE"; then
            print_error "后端进程已退出，未进入 ready 状态"
            print_error "最近日志如下："
            tail -n 40 "$SERVER_LOG_FILE" 2>/dev/null || true
            print_info "如缺依赖，先运行: ./manager.sh update"
            return 1
        fi

        body="$(fetch_server_health "$url" 2>/dev/null || true)"
        if [ -n "${body:-}" ]; then
            summary="$(summarize_server_health "$body" 2>/dev/null || true)"
            if [ -n "${summary:-}" ]; then
                IFS='|' read -r ready phase port <<<"$summary"
                if [ "$ready" = "true" ]; then
                    print_success "后端已就绪 (pid: $(read_pid "$SERVER_PID_FILE"))"
                    if [ -n "${phase:-}" ]; then
                        print_info "健康阶段: $phase"
                    fi
                    print_info "日志文件: $SERVER_LOG_FILE"
                    return 0
                fi
            fi
        fi

        sleep 1
    done

    print_error "后端未在预期时间内进入 ready 状态"
    if [ "$cleanup_on_failure" = "true" ]; then
        if is_pid_running "$SERVER_PID_FILE"; then
            print_warning "正在停止未就绪的后端进程"
            stop_pid_file "$SERVER_PID_FILE" "后端"
        else
            rm -f "$SERVER_PID_FILE"
        fi
    fi
    print_error "最近日志如下："
    tail -n 40 "$SERVER_LOG_FILE" 2>/dev/null || true
    print_info "如缺依赖，先运行: ./manager.sh update"
    return 1
}

spawn_server_process() {
    append_log_banner "$SERVER_LOG_FILE" "server start"
    print_info "正在后台启动后端"
    (
        cd "$SERVER_DIR"
        nohup env PYTHONUNBUFFERED=1 "$SERVER_PYTHON" main.py >>"$SERVER_LOG_FILE" 2>&1 &
        echo $! >"$SERVER_PID_FILE"
    )
}

start_server_background() {
    ensure_state_dir
    ensure_server_venv

    if is_pid_running "$SERVER_PID_FILE"; then
        print_info "后端已在后台运行 (pid: $(read_pid "$SERVER_PID_FILE"))，检查健康状态"
        if wait_for_server_ready false; then
            return 0
        fi
        print_error "后端进程存在但尚未 ready；请检查日志或执行 ./manager.sh backend-restart"
        return 1
    fi

    if adopt_existing_backend_on_port; then
        return 0
    else
        local adopt_status=$?
        if [ "$adopt_status" -eq 2 ] || [ "$adopt_status" -eq 3 ]; then
            return 1
        fi
    fi

    spawn_server_process
    wait_for_server_ready true
}

start_bridge_background() {
    ensure_state_dir
    require_cmd node "请先安装 Node.js 20+。"
    require_cmd npm "请先安装 npm。"

    if [ ! -f "$BRIDGE_DIR/package.json" ]; then
        print_error "未找到 $BRIDGE_DIR/package.json"
        exit 1
    fi

    if is_pid_running "$BRIDGE_PID_FILE"; then
        print_info "bridge 已在后台运行 (pid: $(read_pid "$BRIDGE_PID_FILE"))"
        print_info "日志文件: $BRIDGE_LOG_FILE"
        return 0
    fi

    if [ ! -d "$BRIDGE_DIR/node_modules" ]; then
        print_info "bridge 尚未安装依赖，先执行 npm install"
        (
            cd "$BRIDGE_DIR"
            npm install
        )
    fi

    if [ ! -f "$BRIDGE_DIR/dist/index.js" ]; then
        print_info "bridge 尚未构建，先执行 npm run build"
        (
            cd "$BRIDGE_DIR"
            npm run build
        )
    fi

    append_log_banner "$BRIDGE_LOG_FILE" "bridge start"
    print_info "正在后台启动可选 WhatsApp bridge"
    (
        cd "$BRIDGE_DIR"
        nohup node dist/index.js >>"$BRIDGE_LOG_FILE" 2>&1 &
        echo $! >"$BRIDGE_PID_FILE"
    )

    sleep 2
    if is_pid_running "$BRIDGE_PID_FILE"; then
        print_success "bridge 已启动 (pid: $(read_pid "$BRIDGE_PID_FILE"))"
        print_info "日志文件: $BRIDGE_LOG_FILE"
        return 0
    fi

    print_error "bridge 启动失败，最近日志如下："
    tail -n 40 "$BRIDGE_LOG_FILE" 2>/dev/null || true
    return 1
}

is_valid_port_number() {
    local value="$1"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        return 1
    fi
    return 0
}

run_server_foreground() {
    ensure_server_venv
    print_info "正在前台启动后端"
    (
        cd "$SERVER_DIR"
        exec env PYTHONUNBUFFERED=1 "$SERVER_PYTHON" main.py
    )
}

run_bridge_foreground() {
    require_cmd node "请先安装 Node.js 20+。"
    require_cmd npm "请先安装 npm。"
    if [ ! -d "$BRIDGE_DIR/node_modules" ] || [ ! -f "$BRIDGE_DIR/dist/index.js" ]; then
        print_info "bridge 依赖或构建不存在，先执行 npm install && npm run build"
        (
            cd "$BRIDGE_DIR"
            npm install
            npm run build
        )
    fi

    print_info "正在前台启动可选 WhatsApp bridge"
    (
        cd "$BRIDGE_DIR"
        exec node dist/index.js
    )
}

run_app_foreground() {
    ensure_macos
    require_cmd flutter "请先安装 Flutter，并确保 flutter 在 PATH 中。"
    print_info "正在前台启动 Flutter macOS"
    print_info "热重载: r | 热重启: R | 退出: q"
    (
        cd "$APP_DIR"
        exec flutter run -d macos
    )
}

show_status() {
    print_header
    local server_pid=""
    if is_pid_running "$SERVER_PID_FILE"; then
        server_pid="$(read_pid "$SERVER_PID_FILE")"
    else
        server_pid="$(find_listening_pid_on_server_port || true)"
        if [ -n "${server_pid:-}" ] && ! is_compatible_backend_pid "$server_pid"; then
            server_pid=""
        fi
    fi

    if [ -n "${server_pid:-}" ]; then
        print_success "后端运行中 (pid: $server_pid)"
        print_info "日志: $SERVER_LOG_FILE"
    else
        print_info "后端未在后台运行"
    fi

    if is_pid_running "$BRIDGE_PID_FILE"; then
        print_success "bridge 运行中 (pid: $(read_pid "$BRIDGE_PID_FILE"))"
        print_info "日志: $BRIDGE_LOG_FILE"
    else
        print_info "bridge 未在后台运行"
    fi
}

tail_logs() {
    local target="${1:-server}"
    local log_file

    case "$target" in
        server)
            log_file="$SERVER_LOG_FILE"
            ;;
        bridge)
            log_file="$BRIDGE_LOG_FILE"
            ;;
        *)
            print_error "未知日志目标: $target"
            exit 1
            ;;
    esac

    if [ ! -f "$log_file" ]; then
        print_error "日志文件不存在: $log_file"
        exit 1
    fi

    print_info "正在跟随日志: $log_file"
    tail -n 120 -f "$log_file"
}

clean_project() {
    print_header
    if command -v flutter >/dev/null 2>&1; then
        print_info "正在执行 flutter clean"
        (
            cd "$APP_DIR"
            flutter clean
        )
    else
        print_warning "未找到 flutter，跳过 flutter clean"
    fi

    print_info "正在清理 Python 缓存与 manager 状态文件"
    find "$SERVER_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true
    rm -rf "$ROOT_DIR/.pytest_cache" "$STATE_DIR"
    print_success "清理完成"
}

build_macos_release() {
    ensure_macos
    require_cmd flutter "请先安装 Flutter，并确保 flutter 在 PATH 中。"
    print_header
    print_info "正在构建 macOS release"
    (
        cd "$APP_DIR"
        flutter pub get
        flutter build macos --release
    )
    print_success "macOS release 构建完成"
}

open_build_output() {
    ensure_macos
    local release_dir="$APP_DIR/build/macos/Build/Products/Release"
    local app_bundle

    if [ ! -d "$release_dir" ]; then
        print_error "未找到构建目录: $release_dir"
        print_info "请先运行: ./manager.sh build-macos"
        exit 1
    fi

    app_bundle="$(find "$release_dir" -maxdepth 1 -name '*.app' | head -1)"
    if [ -n "${app_bundle:-}" ] && [ -d "$app_bundle" ]; then
        print_info "正在打开构建产物: $app_bundle"
        open "$app_bundle"
        return 0
    fi

    print_info "未找到 .app 包，改为打开构建目录"
    open "$release_dir"
}

run_db_viewer() {
    ensure_server_venv

    local port="${1:-$DB_VIEWER_DEFAULT_PORT}"
    if ! is_valid_port_number "$port"; then
        print_error "db-view 端口无效: $port"
        print_info "示例: ./manager.sh db-view 8787"
        exit 1
    fi

    if [ ! -f "$DB_VIEWER_DB_PATH" ]; then
        print_error "未找到 SQLite 数据库: $DB_VIEWER_DB_PATH"
        print_info "请先启动后端，或确认数据库已经生成。"
        exit 1
    fi

    if ! command -v open >/dev/null 2>&1; then
        print_warning "未找到 open 命令，将只启动本地浏览器服务，不自动打开网页"
        "$SERVER_PYTHON" "$DB_VIEWER_SCRIPT" \
            --db "$DB_VIEWER_DB_PATH" \
            --host 127.0.0.1 \
            --port "$port"
        return 0
    fi

    print_info "正在启动只读 SQLite 表浏览器"
    print_info "数据库: $DB_VIEWER_DB_PATH"
    print_info "地址: http://127.0.0.1:$port/"
    "$SERVER_PYTHON" "$DB_VIEWER_SCRIPT" \
        --db "$DB_VIEWER_DB_PATH" \
        --host 127.0.0.1 \
        --port "$port" \
        --open-browser
}

doctor() {
    print_header
    print_info "项目根目录: $ROOT_DIR"
    print_info "系统: $(uname -s) $(uname -m)"

    if [ "$(uname -s)" = "Darwin" ]; then
        print_success "当前是 macOS"
    else
        print_warning "当前不是 macOS，Flutter macOS 相关命令不可用"
    fi

    if command -v git >/dev/null 2>&1; then
        print_success "git: $(command -v git)"
    else
        print_warning "git 未安装"
    fi

    if command -v python3 >/dev/null 2>&1; then
        print_success "python3: $(command -v python3)"
    else
        print_warning "python3 未安装"
    fi

    if [ -x "$SERVER_PYTHON" ]; then
        print_success "server venv: $SERVER_PYTHON"
    else
        print_warning "server/.venv 尚未创建"
    fi

    if command -v flutter >/dev/null 2>&1; then
        print_success "flutter: $(command -v flutter)"
    else
        print_warning "flutter 未安装"
    fi

    if command -v xcodebuild >/dev/null 2>&1; then
        print_success "xcodebuild: $(command -v xcodebuild)"
    else
        print_warning "xcodebuild 未安装，macOS 构建不可用"
    fi

    if command -v node >/dev/null 2>&1; then
        print_success "node: $(command -v node)"
    else
        print_warning "node 未安装（可选 bridge 将不可用）"
    fi

    if command -v npm >/dev/null 2>&1; then
        print_success "npm: $(command -v npm)"
    else
        print_warning "npm 未安装（可选 bridge 将不可用）"
    fi
}

command_help() {
    print_header
    usage
}

command_update() {
    print_header
    update_repo
    update_server_deps
    update_app_deps
    update_bridge_deps
    print_success "update 完成"
}

command_dev() {
    print_header
    start_server_background
    print_info "后端已准备就绪，开始启动 Flutter macOS"
    print_info "如果需要重启后端，请另开一个终端执行: ./manager.sh backend-restart"
    run_app_foreground
}

command_server_start() {
    print_header
    start_server_background
}

command_backend_restart() {
    print_header
    if ! is_pid_running "$SERVER_PID_FILE"; then
        if adopt_existing_backend_on_port; then
            print_info "已接管现有后端进程，准备重启"
        fi
    fi
    stop_pid_file "$SERVER_PID_FILE" "后端"
    start_server_background
}

command_bridge_start() {
    print_header
    start_bridge_background
}

command_stop() {
    print_header
    stop_pid_file "$BRIDGE_PID_FILE" "bridge"
    stop_pid_file "$SERVER_PID_FILE" "后端"
}

COMMAND="${1:-help}"
TARGET="${2:-}"

case "$COMMAND" in
    help|-h|--help)
        command_help
        ;;
    doctor)
        doctor
        ;;
    update)
        command_update
        ;;
    dev)
        command_dev
        ;;
    app-dev)
        print_header
        run_app_foreground
        ;;
    server-dev)
        print_header
        run_server_foreground
        ;;
    server-start)
        command_server_start
        ;;
    backend-restart)
        command_backend_restart
        ;;
    bridge-start)
        command_bridge_start
        ;;
    bridge-dev)
        print_header
        run_bridge_foreground
        ;;
    logs)
        tail_logs "$TARGET"
        ;;
    status)
        show_status
        ;;
    stop)
        command_stop
        ;;
    clean)
        clean_project
        ;;
    build-macos)
        build_macos_release
        ;;
    open-build)
        open_build_output
        ;;
    db-view)
        print_header
        run_db_viewer "$TARGET"
        ;;
    *)
        print_error "未知命令: $COMMAND"
        echo ""
        usage
        exit 1
        ;;
esac
