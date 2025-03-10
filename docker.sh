#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian 10+, Ubuntu 20+
# Description:      Script to Docker manage
#
# Copyright (C) 2025 zxcvos
#
# optimized by AI(Qwen2.5-Max-QwQ)
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
#
# docker-install:
#   https://github.com/docker/docker-install
#
# Cloudflare WARP:
#   https://github.com/haoel/haoel.github.io?tab=readme-ov-file#1043-docker-%E4%BB%A3%E7%90%86
#   https://github.com/e7h4n/cloudflare-warp
#
# Cloudreve:
#   https://cloudreve.org

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# 颜色定义
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# 目录
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename $0)"

# 状态打印函数
function print_info() {
  printf "${GREEN}[信息] ${NC}%s\n" "$*"
}

function print_warn() {
  printf "${YELLOW}[警告] ${NC}%s\n" "$*"
}

function print_error() {
  printf "${RED}[错误] ${NC}%s\n" "$*"
  exit 1
}

# 工具函数
function _exists() {
  local cmd="$1"
  if eval type type >/dev/null 2>&1; then
    eval type "$cmd" >/dev/null 2>&1
  elif command >/dev/null 2>&1; then
    command -v "$cmd" >/dev/null 2>&1
  else
    which "$cmd" >/dev/null 2>&1
  fi
  local rt=$?
  return ${rt}
}

function _os() {
  local os=""
  [[ -f "/etc/debian_version" ]] && source /etc/os-release && os="${ID}" && printf -- "%s" "${os}" && return
  [[ -f "/etc/redhat-release" ]] && os="centos" && printf -- "%s" "${os}" && return
}

function _os_full() {
  [[ -f /etc/redhat-release ]] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
  [[ -f /etc/os-release ]] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
  [[ -f /etc/lsb-release ]] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

function _os_ver() {
  local main_ver="$(echo $(_os_full) | grep -oE "[0-9.]+")"
  printf -- "%s" "${main_ver%%.*}"
}

# 检查操作系统
function check_os() {
  [[ -z "$(_os)" ]] && print_error "不支持的操作系统。"
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 20 ]] && print_error "不支持的操作系统，请切换到 Ubuntu 20+ 并重试。"
    ;;
  debian)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 10 ]] && print_error "不支持的操作系统，请切换到 Debian 10+ 并重试。"
    ;;
  centos)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && print_error "不支持的操作系统，请切换到 CentOS 7+ 并重试。"
    ;;
  *)
    print_error "不支持的操作系统。"
    ;;
  esac
}

# 安装 docker
function install_docker() {
  if ! _exists "docker"; then
    wget -O /usr/local/xray-script/install-docker.sh https://get.docker.com
    if [[ "$(_os)" == "centos" && "$(_os_ver)" -eq 8 ]]; then
      sed -i 's|$sh_c "$pkg_manager install -y -q $pkgs"| $sh_c "$pkg_manager install -y -q $pkgs --allowerasing"|' /usr/local/xray-script/install-docker.sh
    fi
    sh /usr/local/xray-script/install-docker.sh --dry-run
    sh /usr/local/xray-script/install-docker.sh
  fi
}

# 获取 Docker 容器 IP
function get_container_ip() {
  docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

# 构建 WARP 镜像
function build_warp() {
  if ! docker images --format "{{.Repository}}" | grep -q xray-script-warp; then
    print_info '正在构建 WARP 镜像'
    mkdir -p /usr/local/xray-script/warp
    mkdir -p ${HOME}/.warp
    wget -O /usr/local/xray-script/warp/Dockerfile https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudflare-warp/Dockerfile || print_error "WARP Dockerfile 下载失败"
    wget -O /usr/local/xray-script/warp/startup.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudflare-warp/startup.sh || print_error "WARP startup.sh 下载失败"
    docker build -t xray-script-warp /usr/local/xray-script/warp || print_error "WARP 镜像构建失败"
  fi
}

# 启动 WARP 容器
function enable_warp() {
  if ! docker ps --format "{{.Names}}" | grep -q "^xray-script-warp\$"; then
    print_info '正在开启 WARP 容器'
    docker run -d --restart=always --name=xray-script-warp -v "${HOME}/.warp":/var/lib/cloudflare-warp:rw xray-script-warp || print_error "WARP 容器启动失败"
    # 更新配置
    local container_ip=$(get_container_ip xray-script-warp)
    local socks_config='[{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"'"${container_ip}"'","port":40001}]}}]'
    jq --argjson socks_config $socks_config '.outbounds += $socks_config' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq --argjson warp 1 '.warp = $warp' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    print_info "WARP 容器已启用 (IP: ${container_ip})"
  fi
}

# 禁用 WARP 容器
function disable_warp() {
  if docker ps --format "{{.Names}}" | grep -q "^xray-script-warp\$"; then
    print_warn '正在停止 WARP 容器'
    docker stop xray-script-warp
    docker rm xray-script-warp
    docker image rm xray-script-warp
    rm -rf /usr/local/xray-script/warp
    rm -rf ${HOME}/.warp
    # 清理配置
    jq 'del(.outbounds[] | select(.tag == "warp")) | del(.routing.rules[] | select(.outboundTag == "warp"))' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq --argjson warp 0 '.warp = $warp' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    print_info "WARP 容器已停止"
  fi
}

# 安装 Cloudreve
function install_cloudreve() {
  if ! docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    print_info "创建 Cloudreve 相关目录。"
    mkdir -vp /usr/local/cloudreve &&
      mkdir -vp /usr/local/cloudreve/cloudreve/{uploads,avatar} &&
      touch /usr/local/cloudreve/cloudreve/conf.ini &&
      touch /usr/local/cloudreve/cloudreve/cloudreve.db &&
      mkdir -vp /usr/local/cloudreve/aria2/config &&
      mkdir -vp /usr/local/cloudreve/data/aria2 &&
      chmod -R 777 /usr/local/cloudreve/data/aria2
    print_info "下载管理 Cloudreve 的 docker-compose.yaml。"
    wget -O /usr/local/cloudreve/docker-compose.yaml https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudreve/docker-compose.yaml
    print_info "启动 Cloudreve 服务"
    cd /usr/local/cloudreve
    docker compose up -d
    sleep 5
  fi
}

# 获取 Cloudreve 信息
function get_cloudreve_info() {
  if docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    local cloudreve_version="$(docker logs cloudreve | grep -Eoi "v[0-9]+.[0-9]+.[0-9]+" | cut -c2-)"
    local cloudreve_username="$(docker logs cloudreve | grep Admin | awk '{print $NF}' | head -1)"
    local cloudreve_password="$(docker logs cloudreve | grep Admin | awk '{print $NF}' | tail -1)"
    jq --arg version "${cloudreve_version}" '.cloudreve.version = $version' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    jq --arg username "${cloudreve_username}" '.cloudreve.username = $username' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    jq --arg password "${cloudreve_password}" '.cloudreve.password = $password' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
}

# 重置 Cloudreve 信息
function reset_cloudreve_info() {
  if docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    print_info "正在重置 Cloudreve 信息"
    cd /usr/local/cloudreve
    docker compose down
    rm -rf /usr/local/cloudreve/cloudreve/cloudreve.db
    touch /usr/local/cloudreve/cloudreve/cloudreve.db
    docker compose up -d
    sleep 5
    get_cloudreve_info
  fi
}

# 卸载 cloudreve
function purge_cloudreve() {
  if docker ps --format "{{.Names}}" | grep -q "^cloudreve\$"; then
    print_warn "停止 Cloudreve 服务"
    cd /usr/local/cloudreve
    docker compose down
    cd ${HOME}
    rm -rf /usr/local/cloudreve
  fi
}

# 显示帮助信息
function show_help() {
  cat <<EOF
用法: $0 [选项]

选项:
  --enable-warp           启用 Cloudflare WARP 代理
  --disable-warp          禁用 Cloudflare WARP 代理
  --install-cloudreve     安装 Cloudreve 网盘服务
  --reset-cloudreve       重置 Cloudreve 管理员信息
  --purge-cloudreve       卸载 Cloudreve 并删除数据
  -h, --help              显示帮助信息
EOF
  exit 0
}

# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
  --enable-warp)
    action="enable_warp"
    ;;
  --disable-warp)
    action="disable_warp"
    ;;
  --install-cloudreve)
    action="install_cloudreve"
    ;;
  --reset-cloudreve)
    action="reset_cloudreve_info"
    ;;
  --purge-cloudreve)
    action="purge_cloudreve"
    ;;
  -h | --help)
    show_help
    ;;
  *)
    print_error "无效选项: '$1'。使用 '$0 -h/--help' 查看用法信息。"
    ;;
  esac
  shift
done

check_os
install_docker

# 执行操作
case "${action}" in
enable_warp)
  build_warp
  enable_warp
  ;;
disable_warp) disable_warp ;;
install_cloudreve)
  install_cloudreve
  get_cloudreve_info
  ;;
reset_cloudreve_info) reset_cloudreve_info ;;
purge_cloudreve) purge_cloudreve ;;
esac
