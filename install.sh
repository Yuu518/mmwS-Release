#!/bin/bash

set -e

GITHUB_REPO="Yuu518/mmwS-Release"
RAW_BASE="${MMW_RAW_BASE:-https://raw.githubusercontent.com/${GITHUB_REPO}/master}"
IMAGE="${MMW_IMAGE:-ghcr.io/yuu518/miaomiaowus}"
INSTALL_DIR="${MMW_DOCKER_DIR:-/opt/miaomiaowus}"
DATABASE_MODE="${MMW_DATABASE_DRIVER:-}"
CONTAINER="miaomiaowus"
PG_CONTAINER="miaomiaowus-postgres"
ENV_FILE="$INSTALL_DIR/.env"
SCRIPT_URL="$RAW_BASE/install.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

outer_tty() {
    local self up ppid dev
    self="$(readlink /proc/$$/fd/2 2>/dev/null)"
    up="$PPID"
    for _ in 1 2 3 4 5 6 7 8; do
        [ -n "$up" ] && [ -d "/proc/$up" ] || return 0
        dev="$(readlink /proc/$up/fd/0 2>/dev/null)"
        case "$dev" in
            /dev/pts/*|/dev/tty[0-9]*|/dev/ttyS*)
                if [ "$dev" != "$self" ] && [ -c "$dev" ] && [ -r "$dev" ]; then
                    printf '%s' "$dev"
                    return 0
                fi
                ;;
        esac
        ppid="$(awk '/^PPid:/{print $2}' "/proc/$up/status" 2>/dev/null)"
        [ "$ppid" = "$up" ] && return 0
        up="$ppid"
    done
    return 0
}

input_unreachable_hint() {
    echo_error "改用下面任一方式:"
    echo_error "  1) sudo bash -c \"\$(curl -fsSL $SCRIPT_URL)\""
    echo_error "  2) curl -fsSL $SCRIPT_URL -o install.sh && sudo bash install.sh"
    echo_error "  3) curl -fsSL $SCRIPT_URL | sudo env MMW_DATABASE_DRIVER=sqlite PORT=11996 bash"
}

read_choice() {
    local prompt="$1" default="$2" value="" status=0
    CHOICE_RESULT="$default"
    { : < /dev/tty; } 2>/dev/null || return 0
    local source_tty="/dev/tty"
    if [ ! -t 0 ] && [ -n "${SUDO_USER:-}" ]; then
        source_tty="$(outer_tty)"
        if [ -z "$source_tty" ]; then
            echo
            echo_error "「curl … | sudo bash」收不到键盘输入。"
            input_unreachable_hint
            exit 1
        fi
    fi
    read -r -t 60 -p "$prompt" value <"$source_tty" || status=$?
    if [ "$status" -gt 128 ]; then
        echo
        echo_error "等待输入超时。"
        input_unreachable_hint
        exit 1
    fi
    CHOICE_RESULT="${value:-$default}"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo_error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

install_docker_engine() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        return
    fi
    echo_info "安装 Docker Engine 与 Compose 插件..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 >/dev/null 2>&1 || \
            DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-plugin >/dev/null 2>&1 || \
            DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-cli docker-compose >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y docker docker-compose-plugin >/dev/null
    elif command -v yum >/dev/null 2>&1; then
        yum install -y docker docker-compose-plugin >/dev/null
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache docker docker-cli-compose >/dev/null
    else
        echo_error "无法自动安装 Docker，请先安装 Docker Engine 和 Compose v2"
        exit 1
    fi
    if command -v systemctl >/dev/null 2>&1; then systemctl enable --now docker; fi
    if command -v rc-service >/dev/null 2>&1; then rc-update add docker default >/dev/null 2>&1 || true; rc-service docker start || true; fi
    docker compose version >/dev/null 2>&1 || { echo_error "Docker Compose v2 安装失败"; exit 1; }
}

random_password() {
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

primary_ip() {
    local ip_addr
    ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip_addr" ] && command -v ip >/dev/null 2>&1; then
        ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')
    fi
    echo "${ip_addr:-127.0.0.1}"
}

env_value() {
    [ -f "$ENV_FILE" ] || return 0
    sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r'
}

set_env_value() {
    if grep -q "^$1=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
    else
        echo "$1=$2" >> "$ENV_FILE"
    fi
}

compose() {
    local profile=()
    if [ "$(env_value MMW_DATABASE_DRIVER)" = "postgres" ]; then
        profile=(--profile postgres)
    fi
    (cd "$INSTALL_DIR" && docker compose "${profile[@]}" "$@")
}

choose_database() {
    case "$DATABASE_MODE" in postgresql|pgsql) DATABASE_MODE="postgres" ;; esac
    if [ -z "$DATABASE_MODE" ]; then
        echo "请选择数据库:"
        echo "  1) SQLite（轻量，无需额外安装）"
        echo "  2) PostgreSQL 18（推荐多服务器/高并发）"
        read_choice '请选择 (1/2，默认 1): ' 1
        case "$CHOICE_RESULT" in
            2|postgres|postgresql|pgsql) DATABASE_MODE="postgres" ;;
            *) DATABASE_MODE="sqlite" ;;
        esac
    fi
    case "$DATABASE_MODE" in sqlite|postgres) ;; *) echo_error "不支持的数据库: $DATABASE_MODE"; exit 1 ;; esac
}

choose_port() {
    local default="${PORT:-$(env_value PORT)}"
    default="${default:-11996}"
    if [ -n "${PORT:-}" ]; then
        PORT_RESULT="$PORT"
    else
        read_choice "请输入面板端口（默认 $default）: " "$default"
        PORT_RESULT="$CHOICE_RESULT"
    fi
    case "$PORT_RESULT" in
        ''|*[!0-9]*) echo_error "端口无效: $PORT_RESULT"; exit 1 ;;
    esac
    if [ "$PORT_RESULT" -lt 1 ] || [ "$PORT_RESULT" -gt 65535 ]; then
        echo_error "端口无效: $PORT_RESULT"
        exit 1
    fi
}

download_compose() {
    echo_info "下载 docker-compose.yml..."
    curl -fsSL --retry 2 "$RAW_BASE/docker-compose.yml" -o "$INSTALL_DIR/docker-compose.yml.tmp"
    mv -f "$INSTALL_DIR/docker-compose.yml.tmp" "$INSTALL_DIR/docker-compose.yml"
}

write_env() {
    local version="${MMW_VERSION:-$(env_value MMW_VERSION)}"
    version="${version:-latest}"
    if [ -f "$ENV_FILE" ]; then
        set_env_value MMW_IMAGE "$IMAGE"
        set_env_value MMW_VERSION "$version"
        set_env_value PORT "$PORT_RESULT"
        return
    fi
    local driver="" host="" port="" name="" user="" password="" sslmode=""
    if [ "$DATABASE_MODE" = "postgres" ]; then
        driver="postgres"; host="postgres"; port="5432"; name="mmw"; user="mmw"
        password="$(random_password)"; sslmode="disable"
    fi
    umask 077
    cat > "$ENV_FILE" <<EOF
MMW_IMAGE=$IMAGE
MMW_VERSION=$version
PORT=$PORT_RESULT
MMW_DATABASE_DRIVER=$driver
MMW_DATABASE_HOST=$host
MMW_DATABASE_PORT=$port
MMW_DATABASE_NAME=$name
MMW_DATABASE_USER=$user
MMW_DATABASE_PASSWORD=$password
MMW_DATABASE_SSLMODE=$sslmode
EOF
    umask 022
    chmod 600 "$ENV_FILE"
}

wait_postgres() {
    echo_info "等待 PostgreSQL 18 就绪..."
    local user name state=""
    user="$(env_value MMW_DATABASE_USER)"
    name="$(env_value MMW_DATABASE_NAME)"
    for _ in $(seq 1 60); do
        state="$(docker inspect -f '{{.State.Status}}' "$PG_CONTAINER" 2>/dev/null || true)"
        case "$state" in
            exited|dead) break ;;
        esac
        if timeout 5 docker exec "$PG_CONTAINER" pg_isready -U "$user" -d "$name" >/dev/null 2>&1; then
            echo
            return 0
        fi
        printf '.'
        sleep 2
    done
    echo
    echo_error "PostgreSQL 未能就绪（容器状态: ${state:-未知}），最近的日志:"
    docker logs --tail 30 "$PG_CONTAINER" 2>&1 || true
    exit 1
}

start_stack() {
    echo_info "拉取镜像 $(env_value MMW_IMAGE):$(env_value MMW_VERSION)..."
    if ! compose pull; then
        echo_error "镜像拉取失败。如果提示 denied / unauthorized，请确认 GHCR 包已设为 Public"
        exit 1
    fi
    if [ "$(env_value MMW_DATABASE_DRIVER)" = "postgres" ]; then
        compose up -d postgres
        wait_postgres
    fi
    compose up -d
}

wait_panel() {
    local port
    port="$(env_value PORT)"
    for _ in $(seq 1 30); do
        if curl -fsS -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; then
            return 0
        fi
        sleep 2
    done
    echo_warn "面板 60 秒内没有响应，请执行 docker logs $CONTAINER 查看日志"
}

show_status() {
    local port
    port="$(env_value PORT)"
    echo ""
    echo "======================================"
    echo_info "妙妙屋 S 面板已就绪"
    echo "======================================"
    echo "📦 镜像: $(env_value MMW_IMAGE):$(env_value MMW_VERSION)"
    echo "💾 目录: $INSTALL_DIR"
    echo "🗄️  数据库: $([ "$(env_value MMW_DATABASE_DRIVER)" = "postgres" ] && echo "PostgreSQL 18" || echo "SQLite")"
    echo "🌐 访问地址: http://$(primary_ip):$port"
    echo ""
    echo "常用命令:"
    echo "  查看日志: docker logs -f $CONTAINER"
    echo "  重启面板: cd $INSTALL_DIR && docker compose restart $CONTAINER"
    echo "  更新版本: curl -fsSL $SCRIPT_URL | sudo bash -s update"
    echo "  卸载面板: curl -fsSL $SCRIPT_URL | sudo bash -s uninstall"
    echo ""
    echo "远程服务器的 box-agent 在面板「服务管理」里添加服务器后，复制安装命令到服务器执行。"
    echo ""
}

install_panel() {
    install_docker_engine
    mkdir -p "$INSTALL_DIR"/{data,subscribes,rule_templates}
    if [ -f "$ENV_FILE" ]; then
        DATABASE_MODE="$(env_value MMW_DATABASE_DRIVER)"
        DATABASE_MODE="${DATABASE_MODE:-sqlite}"
        echo_info "检测到已有安装（$ENV_FILE），沿用数据库: $DATABASE_MODE"
    else
        choose_database
    fi
    if [ "$DATABASE_MODE" = "postgres" ]; then
        mkdir -p "$INSTALL_DIR/postgres-data"
    fi
    choose_port
    download_compose
    write_env
    start_stack
    wait_panel
    show_status
}

update_panel() {
    if [ ! -f "$ENV_FILE" ] || [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        echo_error "未检测到已安装的面板（$INSTALL_DIR），请先执行安装"
        exit 1
    fi
    install_docker_engine
    PORT_RESULT="${PORT:-$(env_value PORT)}"
    PORT_RESULT="${PORT_RESULT:-11996}"
    download_compose
    write_env
    start_stack
    docker image prune -f >/dev/null 2>&1 || true
    wait_panel
    show_status
}

uninstall_panel() {
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        echo_error "未检测到已安装的面板（$INSTALL_DIR）"
        exit 1
    fi
    local keep="${MMW_KEEP_DATA:-}"
    if [ -z "$keep" ]; then
        echo "是否保留数据？"
        echo "  1) 保留 data、订阅、数据库等数据（默认）"
        echo "  2) 全部删除"
        read_choice '请选择 (1/2，默认 1): ' 1
        case "$CHOICE_RESULT" in 2) keep="false" ;; *) keep="true" ;; esac
    fi
    compose down --remove-orphans || true
    if [ "$keep" = "false" ]; then
        rm -rf "$INSTALL_DIR"
        echo_info "面板与全部数据已删除"
    else
        echo_info "面板已停止并移除容器，数据保留在 $INSTALL_DIR"
    fi
}

main() {
    check_root
    case "${1:-install}" in
        install|reinstall) install_panel ;;
        update|upgrade) update_panel ;;
        uninstall|remove) uninstall_panel ;;
        *) echo "用法: install.sh [install|update|uninstall]"; exit 1 ;;
    esac
}

main "$@"
