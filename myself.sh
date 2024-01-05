#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Rocky 8+, Debian10+, Ubuntu20+
# Description:      Script to Xray manage
#
# Copyright (C) 2023 zxcvos
#
# Xray-script: https://github.com/zxcvos/Xray-script
#
# XTLS Official:
#   Xray-core: https://github.com/XTLS/Xray-core
#   REALITY: https://github.com/XTLS/REALITY
#
# Xray examples:
#   XTLS/Xray-examples: https://github.com/XTLS/Xray-examples
#   chika0801/Xray-examples: https://github.com/chika0801/Xray-examples
#
# NGINX:
#   documentation: https://nginx.org/en/linux_packages.html
#   update: https://zhuanlan.zhihu.com/p/193078620
#   gcc: https://github.com/kirin10000/Xray-script
#   brotli: https://www.nodeseek.com/post-37224-1
#   ngx_brotli: https://github.com/google/ngx_brotli
#   config: https://www.digitalocean.com/community/tools/nginx?domains.0.server.wwwSubdomain=true&domains.0.https.hstsPreload=true&domains.0.php.php=false&domains.0.reverseProxy.reverseProxy=true&domains.0.reverseProxy.proxyHostHeader=%24proxy_host&domains.0.routing.root=false&domains.0.logging.accessLogEnabled=false&domains.0.logging.errorLogEnabled=false&global.https.portReuse=true&global.nginx.user=root&global.nginx.clientMaxBodySize=50&global.app.lang=zhCN
#
# Certificate:
#   ACME: https://github.com/acmesh-official/acme.sh
#
# Docker:
#   Manuals: https://docs.docker.com/engine/install/
#   Cloudreve: https://github.com/cloudreve/cloudreve
#   Cloudflare WARP Proxy: https://github.com/haoel/haoel.github.io?tab=readme-ov-file#1043-docker-%E4%BB%A3%E7%90%86
#   e7h4n/cloudflare-warp: https://github.com/e7h4n/cloudflare-warp

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

trap egress EXIT

# color
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# directory
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly TMPFILE_DIR="$(mktemp -d -p "${CUR_DIR}" -t nginxtemp.XXXXXXXX)" || exit 1

# global constant
# nginx
readonly NGINX_PATH="/usr/local/nginx"
readonly NGINX_CONFIG_PATH="${NGINX_PATH}/conf"
readonly NGINX_LOG_PATH="/var/log/nginx"
# ssl
readonly SSL_PATH="${NGINX_CONFIG_PATH}/certs"
readonly WEBROOT_PATH="/var/www/_letsencrypt"
# xray script
readonly XRAY_SCRIPT_PATH="/usr/local/etc/zxcvos_xray_script"
readonly XRAY_CONFIG_MANAGE="${XRAY_SCRIPT_PATH}/xray_config_manage.sh"
# cloudreve
readonly CLOUDREVE_PATH="/usr/local/cloudreve"
# cloudflare-warp
readonly CLOUDFLARE_WARP_PATH="/usr/local/cloudflare_warp"

# global variable
declare domain=""
declare subdomain=""
declare in_uuid=""
declare is_enable_brotli=""

# exit process
function egress() {
  [[ -e "${TMPFILE_DIR}/swap" ]] && swapoff "${TMPFILE_DIR}/swap"
  rm -rf "${TMPFILE_DIR}"
  rm -rf "${CUR_DIR}/tmp.sh"
}

function language() {
  clear
  echo "1.中文"
  echo "2.English"
  read -p "Please choose a language: " lang
  case $lang in
  1)
    show_lang="zh"
    hide_lang="en"
    ;;
  2)
    show_lang="en"
    hide_lang="zh"
    ;;
  *)
    echo -e "${RED}[ERROR] ${NC}Invalid choice"
    exit 1
    ;;
  esac
}

language && sed -e '$a main' -e "s/.*${hide_lang}:.*//g; s/${show_lang}: //" -e '/^function language() {/,/^language/d' "${CUR_DIR}/$0" >"${CUR_DIR}/tmp.sh" && bash "${CUR_DIR}/tmp.sh" || exit 1

# status print
function _info() {
  printf "zh: ${GREEN}[信息] ${NC}"
  printf "en: ${GREEN}[Info] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _warn() {
  printf "zh: ${YELLOW}[警告] ${NC}"
  printf "en: ${YELLOW}[Warn] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _error() {
  printf "zh: ${RED}[错误] ${NC}"
  printf "en: ${RED}[Error] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
  exit 1
}

# tools
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

function _error_detect() {
  local cmd="$1"
  _info "zh: 正在执行命令: ${cmd}"
  _info "en: Executing command: ${cmd}"
  eval ${cmd}
  if [[ $? -ne 0 ]]; then
    _error "zh: 执行命令 (${cmd}) 失败，请检查并重试。"
    _error "en: Execution command (${cmd}) failed, please check it and try again."
  fi
}

function _version_ge() {
  test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

function _install() {
  local packages_name="$@"
  local installed_packages=""
  case "$(_os)" in
  centos)
    if _exists "dnf"; then
      packages_name="dnf-plugins-core epel-release epel-next-release ${packages_name}"
      installed_packages="$(dnf list installed 2>/dev/null)"
      if [[ -n "$(_os_ver)" && "$(_os_ver)" -eq 9 ]]; then
        # Enable EPEL and Remi repositories
        if [[ "${packages_name}" =~ "geoip-devel" ]] && ! echo "${installed_packages}" | grep -iwq "geoip-devel"; then
          dnf update -y
          _error_detect "dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
          _error_detect "dnf install -y https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-9.noarch.rpm"
          _error_detect "dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
          # Enable Remi modular repository
          _error_detect "dnf config-manager --set-enabled remi-modular"
          # Refresh package information
          _error_detect "dnf update --refresh"
          # Install GeoIP-devel, specifying the use of the Remi repository
          dnf update -y
          _error_detect "dnf --enablerepo=remi install -y GeoIP-devel"
        fi
      elif [[ -n "$(_os_ver)" && "$(_os_ver)" -eq 8 ]]; then
        if ! dnf module list 2>/dev/null | grep container-tools | grep -iwq "\[x\]"; then
          _error_detect "dnf module disable -y container-tools"
        fi
      fi
      dnf update -y
      for package_name in ${packages_name}; do
        if ! echo "${installed_packages}" | grep -iwq "${package_name}"; then
          _error_detect "dnf install -y "${package_name}""
        fi
      done
    else
      packages_name="epel-release yum-utils ${packages_name}"
      installed_packages="$(yum list installed 2>/dev/null)"
      yum update -y
      for package_name in ${packages_name}; do
        if ! echo "${installed_packages}" | grep -iwq "${package_name}"; then
          _error_detect "yum install -y "${package_name}""
        fi
      done
    fi
    ;;
  ubuntu | debian)
    apt update -y
    installed_packages="$(apt list --installed 2>/dev/null)"
    for package_name in ${packages_name}; do
      if ! echo "${installed_packages}" | grep -iwq "${package_name}"; then
        _error_detect "apt install -y "${package_name}""
      fi
    done
    ;;
  esac
}

function _systemctl() {
  local cmd="$1"
  local server_name="$2"
  case "${cmd}" in
  start)
    if systemctl -q is-active "${server_name}"; then
      _warn "zh: ${server_name} 服务已经在运行，请不要重复启动。"
      _warn "en: ${server_name} service is already running, please do not start it again."
    else
      _info "zh: 正在启动 ${server_name} 服务。"
      _info "en: Starting the ${server_name} service."
      systemctl -q start "${server_name}"
    fi
    systemctl -q is-enabled ${server_name} || systemctl -q enable "${server_name}"
    ;;
  stop)
    if systemctl -q is-active "${server_name}"; then
      _warn "zh: 正在停止 ${server_name} 服务。"
      _warn "en: Stopping the ${server_name} service."
      systemctl -q stop "${server_name}"
    else
      _warn "zh: ${server_name} 服务未在运行，无需停止。"
      _warn "en: ${server_name} service is not running, no need to stop."
    fi
    systemctl -q is-enabled ${server_name} && systemctl -q disable "${server_name}"
    ;;
  restart)
    if systemctl -q is-active "${server_name}"; then
      _info "zh: 正在重启 ${server_name} 服务。"
      _info "en: Restarting the ${server_name} service."
      systemctl -q restart "${server_name}"
    else
      _info "zh: 正在启动 ${server_name} 服务。"
      _info "en: Starting the ${server_name} service."
      systemctl -q start "${server_name}"
    fi
    systemctl -q is-enabled ${server_name} || systemctl -q enable "${server_name}"
    ;;
  reload)
    if systemctl -q is-active "${server_name}"; then
      _info "zh: 正在重载 ${server_name} 服务。"
      _info "en: Reloading the ${server_name} service."
      systemctl -q reload "${server_name}"
    else
      _info "zh: 正在启动 ${server_name} 服务。"
      _info "en: Starting the ${server_name} service."
      systemctl -q start "${server_name}"
    fi
    systemctl -q is-enabled ${server_name} || systemctl -q enable "${server_name}"
    ;;
  esac
}

# check os
function check_os() {
  [[ -z "$(_os)" ]] && _error "zh: 不支持的操作系统。"
  [[ -z "$(_os)" ]] && _error "en: Not supported OS."
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 20 ]] && _error "zh: 不支持的操作系统，请切换到 Ubuntu 20+ 并重试。"
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 20 ]] && _error "en: Not supported OS, please change to Ubuntu 20+ and try again."
    ;;
  debian)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 10 ]] && _error "zh: 不支持的操作系统，请切换到 Debian 10+ 并重试。"
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 10 ]] && _error "en: Not supported OS, please change to Debian 10+ and try again."
    ;;
  centos)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && _error "zh: 不支持的操作系统，请切换到 CentOS 7+ 并重试。"
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && _error "en: Not supported OS, please change to CentOS 7+ and try again."
    ;;
  *)
    _error "zh: 不支持的操作系统。"
    _error "en: Not supported OS."
    ;;
  esac
}

# swap
function swap_on() {
  local mem=${1}
  if [[ ${mem} -ne '0' ]]; then
    if dd if=/dev/zero of="${TMPFILE_DIR}/swap" bs=1M count=${mem} 2>&1; then
      chmod 0600 "${TMPFILE_DIR}/swap"
      mkswap "${TMPFILE_DIR}/swap"
      swapon "${TMPFILE_DIR}/swap"
    fi
  fi
}

# check dns resolution
check_dns_resolution() {
  local domain=$1
  local expected_ipv4="$(ip -4 addr show | grep -wv "lo\|host" | grep -w "inet" | grep -w "scope global*\|link*" | awk -F " " '{for (i=2;i<=NF;i++)printf("%s ", $i);print ""}' | awk '{print $1}' | head -n 1 | cut -d'/' -f1)"
  local expected_ipv6="$(ip -6 addr show | grep -wv "lo" | grep -wv "link\|host" | grep -w "inet6" | grep "scope" | grep "global" | awk -F " " '{for (i=2;i<=NF;i++)printf("%s ", $i);print ""}' | awk '{print $1}' | head -n 1 | cut -d'/' -f1)"
  local resolved=0
  # Use the dig command to query the domain's DNS resolution records
  local actual_ipv4="$(dig +short "${domain}")"
  local actual_ipv6="$(dig +short AAAA "${domain}")"
  # Check if the resolved IPv4 matches the expected IPv4
  if [[ "${actual_ipv4}" =~ "${expected_ipv4}" ]]; then
    _info "zh: 域名 ${domain} 的 IPv4 地址正确解析为 ${expected_ipv4}。"
    _info "en: IPv4 for domain ${domain} is correctly resolved to ${expected_ipv4}."
    resolved=1
  else
    _warn "zh: 域名 ${domain} 的 IPv4 地址未解析为期望的 IP。实际 IP: ${actual_ipv4}。"
    _warn "en: IPv4 for domain ${domain} is not resolved to the expected IP. Actual IP: ${actual_ipv4}."
  fi
  # Check if the resolved IP matches the expected IPv6
  if [[ "${actual_ipv6}" =~ "${expected_ipv6}" ]]; then
    _info "zh: 域名 ${domain} 的 IPv6 地址正确解析为 ${expected_ipv6}。"
    _info "en: IPv6 for domain ${domain} is correctly resolved to ${expected_ipv6}."
    resolved=1
  else
    _warn "zh: 域名 ${domain} 的 IPv6 地址未解析为期望的 IP。实际 IP: ${actual_ipv6}。"
    _warn "en: IPv6 for domain ${domain} is not resolved to the expected IP. Actual IP: ${actual_ipv6}."
  fi
  # If neither IPv4 nor IPv6 resolution was successful, report an error
  if [[ ${resolved} -eq 0 ]]; then
    _error "zh: 域名 ${domain} 未解析为期望的 IPv4 或 IPv6。"
    _error "en: Domain ${domain} does not resolved to either the expected IPv4 or IPv6."
  fi
}

# firewall
function firewall_manage() {
  case "$(_os)" in
  centos)
    read -p "zh: 是否启用防火墙 (y|n)? " is_turn_on
    read -p "en: Whether to turn on the firewall (y|n)? " is_turn_on
    if [[ "${is_turn_on}" =~ ^[Yy]$ ]]; then
      _systemctl start firewalld
    else
      _systemctl stop firewalld
    fi
    if systemctl is-active --quiet firewalld && firewall-cmd --state | grep -Eqw "^running"; then
      _info "zh: 防火墙已启用。"
      _info "en: Firewall is now enabled."
    else
      _warn "zh: 防火墙已停用。"
      _warn "en: Firewall is now disabled."
    fi
    ;;
  debian | ubuntu)
    ufw enable
    if systemctl is-active --quiet ufw && ufw status | grep -qw active; then
      _info "zh: 防火墙已启用。"
      _info "en: Firewall is now enabled."
    else
      _warn "zh: 防火墙已停用。"
      _warn "en: Firewall is now disabled."
    fi
    ;;
  esac
}

function firewall_pass() {
  local action="$1"
  local port="$2"
  local udp="$3"
  # Check if UFW is active
  if systemctl is-active --quiet ufw && ufw status | grep -qw active; then
    case "${action}" in
    allow)
      ufw allow "${port}"
      _info "zh: 已允许端口 ${port}。"
      _info "en: Port ${port} has been allowed."
      ;;
    remove)
      ufw delete allow "${port}"
      _warn "zh: 已移除允许端口 ${port}。"
      _warn "en: Allowed port ${port} has been removed."
      ;;
    esac
  # Check if Firewalld is active
  elif systemctl is-active --quiet firewalld && firewall-cmd --state | grep -Eqw "^running"; then
    case "${action}" in
    allow)
      firewall-cmd --zone=public --add-port="${port}"/tcp --permanent
      [[ "${udp}" ]] && firewall-cmd --zone=public --add-port="${port}"/udp --permanent
      _info "zh: 已允许端口 ${port}。"
      _info "en: Port ${port} has been allowed."
      ;;
    remove)
      firewall-cmd --zone=public --remove-port="${port}"/tcp --permanent
      [[ "${udp}" ]] && firewall-cmd --zone=public --remove-port="${port}"/udp --permanent
      _warn "zh: 已移除允许端口 ${port}。"
      _warn "en: Allowed port ${port} has been removed."
      ;;
    esac
    firewall-cmd --reload
  fi
}

# backup file
function backup_files() {
  local backup_dir="$1"
  local current_date="$(date +%F)"
  for file in "${backup_dir}/"*; do
    if [[ -f "$file" ]]; then
      local file_name="$(basename "$file")"
      local backup_file="${backup_dir}/${file_name}_${current_date}"
      mv "$file" "$backup_file"
      echo "zh: 备份: ${file} -> ${backup_file}。"
      echo "en: Backup: ${file} -> ${backup_file}."
    fi
  done
}

# reboot
function reboot_os() {
  echo
  _info "zh: 系统需要重新启动。"
  _info "en: The system needs to reboot."
  read -p "zh: 是否要重新启动系统？ [y/N] " is_reboot
  read -p "en: Do you want to restart the system? [y/N] " is_reboot
  if [[ "${is_reboot}" =~ ^[Yy]$ ]]; then
    reboot
  else
    _info "zh: 已取消重新启动..."
    _info "en: Reboot has been canceled..."
    exit 0
  fi
}

# read domain
function read_domain() {
  echo -e "zh: --------------------请选择域名解析--------------------"
  echo -e "en: --------------------Please Choose Domain Resolution--------------------"
  echo -e "zh:  选项 1 是使用 xray 前置。选项 2,3 使用 Nginx 进行 SNI 分流"
  echo -e "en:  Option 1 uses Xray as a frontend. Options 2 and 3 utilize Nginx for SNI traffic shunting"
  echo
  echo -e "zh:  仅为了偷自己证书，而且没有其他需求推荐使用 1"
  echo -e "en:  If you do not have a normal website, use option 1"
  echo -e "zh:  如果自己有网站正常使用推荐使用选项 2,3"
  echo -e "en:  If you have a normal website, use options 2 or 3"
  echo
  echo -e "zh:  1. 主域名 和 www.主域名"
  echo -e "en:  1. 主域名 和 www.主域名"
  echo -e "zh:     如: 123.com 和 www.123.com"
  echo -e "en:     Example: 123.com and www.123.com"
  echo -e "zh:  2. 使用 SNI 分流到 drive.主域名"
  echo -e "en:  2. Use SNI to Redirect to drive subdomain"
  echo -e "zh:     如: drive.123.com"
  echo -e "en:     Example: drive.123.com"
  echo -e "zh:  3. 使用 SNI 分流到 pan.主域名"
  echo -e "en:  3. Use SNI to Redirect to pan subdomain"
  echo -e "zh:     如: pan.123.com"
  echo -e "en:     Example: pan.123.com"
  echo
  read -p "zh: 请选择: " choice_domain
  read -p "en: Please choose: " choice_domain
  ((choice_domain < 1 || choice_domain > 3)) && _error "zh: 无效的选择。"
  ((choice_domain < 1 || choice_domain > 3)) && _error "en: Invalid choice."
  local is_domain="n"
  local check_domain=""
  until [[ "${is_domain}" =~ ^[Yy]$ ]]; do
    echo 'zh: 请输入主域名(前面不带"www."、"drive."、".pan"、"http://"或"https://")'
    echo 'en: Please enter the main domain (without "www.", "drive.", ".pan", "http://", or "https://")'
    read -p "zh: 输入域名: " domain
    read -p "en: Enter the domain: " domain
    check_domain="$(echo ${domain} | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)"
    read -p "zh: 确认域名: \"${check_domain}\" [y/N] " is_domain
    read -p "en: Confirm the domain: \"${check_domain}\" [y/N] " is_domain
  done
  domain="${check_domain}"
  case "${choice_domain}" in
  1)
    subdomain="www.${domain}"
    ;;
  2)
    subdomain="drive.${domain}"
    ;;
  3)
    subdomain="pan.${domain}"
    ;;
  esac
}

# read uuid
function read_uuid() {
  _info "zh: 输入一个自定义 UUID。如果不符合标准格式，将使用 xray uuid -i \"自定义字符串\" 生成 UUIDv5 并填充配置。"
  _info "en: Enter a custom UUID. If it's not in standard format, xray uuid -i \"custom string\" will be used to generate a UUIDv5 and fill in the configuration."
  read -p "zh: 输入一个自定义 UUID，或按 Enter 生成默认 UUID: " in_uuid
  read -p "en: Enter a custom UUID, or press Enter to generate a default one: " in_uuid
}

# enable brotli
function enable_brotli() {
  read -p "zh: 确认启用 Nginx 的 Brotli [y/N] " is_enable_brotli
  read -p "en: Confirm enabling Brotli for Nginx [y/N] " is_enable_brotli
}

# validate port
function validate_port() {
  local port=$1
  if [[ ! "${port}" =~ ^[0-9]+$ ]]; then
    _error "zh: 无效的端口号。请输入有效的数字。"
    _error "en: Invalid port number. Please enter a valid numeric value."
  elif ((port < 1 || port > 65535)); then
    _error "zh: 端口号范围 1 到 65535 之间。"
    _error "en: Port number should be between 1 and 65535."
  fi
}

# docker management
function docker_manage() {
  _systemctl start docker
  local cmd="$1"
  local container_name="$2"
  local container="$(docker ps -q --filter "name=${container_name}")"
  case "${cmd}" in
  start)
    if [[ "${container}" ]]; then
      _warn "zh: ${container_name} 已经在运行，请不要重复启动。"
      _warn "en: ${container_name} is already running, please do not start it again."
    else
      _info "zh: 正在启动 ${container_name} 容器。"
      _info "en: Starting the ${container_name} container."
      docker start "${container_name}"
    fi
    ;;
  stop)
    if [[ "${container}" ]]; then
      _warn "zh: 正在停止 ${container_name} 容器。"
      _warn "en: Stopping the ${container_name} container."
      docker stop "${container_name}"
    else
      _warn "zh: ${container_name} 未在运行，无需停止。"
      _warn "en: ${container_name} is not running, no need to stop."
    fi
    ;;
  restart)
    if [[ "${container}" ]]; then
      _info "zh: 正在重启 ${container_name} 容器。"
      _info "en: Restarting the ${container_name} container."
      docker restart "${container_name}"
    else
      _info "zh: 正在启动 ${container_name} 容器。"
      _info "en: Starting the ${container_name} container."
      docker start "${container_name}"
    fi
    ;;
  rmi)
    _warn "zh: 停止并删除 ${container_name} 容器，且删除 ${container_name} 容器镜像。"
    _warn "en: Stop and remove the containers, and delete the container images."
    docker stop "${container_name}"
    docker rm -f -v "${container_name}"
    docker rmi -f "${container_name}"
    ;;
  esac
}

# docker compose management
function docker_compose_manage() {
  _systemctl start docker
  local cmd="$1"
  local container="$(docker compose ps -q)"
  case "${cmd}" in
  start)
    if [[ "${container}" ]]; then
      _warn "zh: 已经在运行，请不要重复启动。"
      _warn "en: Already running, please do not start again."
    else
      _info "zh: 正在启动 ${PWD} 中的 docker-compose.yaml 配置。"
      _info "en: Starting the docker-compose.yaml configuration in ${PWD}."
      docker compose up -d
    fi
    ;;
  stop)
    if [[ "${container}" ]]; then
      _warn "zh: 正在停止 ${PWD} 中的 docker-compose.yaml 配置。"
      _warn "en: Stopping the docker-compose.yaml configuration in ${PWD}."
      docker compose down
    else
      _warn "zh: 未在运行，无需停止。"
      _warn "en: Not running, no need to stop."
    fi
    ;;
  restart)
    if [[ "${container}" ]]; then
      _info "zh: 正在重启 ${PWD} 中的 docker-compose.yaml 配置。"
      _info "en: Restarting the docker-compose.yaml configuration in ${PWD}."
      docker compose restart
    else
      _info "zh: 正在启动 ${PWD} 中的 docker-compose.yaml 配置。"
      _info "en: Starting the docker-compose.yaml configuration in ${PWD}."
      docker compose up -d
    fi
    ;;
  rmi)
    _warn "zh: 停止并删除容器，并删除容器镜像。"
    _warn "en: Stop and remove the containers, and delete the container images."
    docker compose down --rmi all
    ;;
  esac
}

# dependencies
function compile_dependencies() {
  # general
  _install ca-certificates curl wget gcc make git openssl tzdata
  case "$(_os)" in
  centos)
    # toolchains
    _install gcc-c++ perl-IPC-Cmd perl-Getopt-Long perl-Data-Dumper
    # dependencies
    _install pcre2-devel zlib-devel libxml2-devel libxslt-devel gd-devel geoip-devel perl-ExtUtils-Embed gperftools-devel perl-devel brotli-devel
    if ! perl -e "use FindBin" &>/dev/null; then
      _install perl-FindBin
    fi
    ;;
  debian | ubuntu)
    # toolchains
    _install g++ perl-base perl
    # dependencies
    _install libpcre2-dev zlib1g-dev libxml2-dev libxslt1-dev libgd-dev libgeoip-dev libgoogle-perftools-dev libperl-dev libbrotli-dev
    ;;
  esac
}

function other_dependencies() {
  _install jq
  case "$(_os)" in
  centos)
    _install crontabs util-linux iproute procps-ng bind-utils firewalld
    ;;
  debian | ubuntu)
    _install cron bsdmainutils iproute2 procps dnsutils ufw
    ;;
  esac
}

function script_dependencies() {
  _info "zh: 正在安装工具链和依赖项。"
  _info "en: Installing toolchains and dependencies."
  compile_dependencies
  other_dependencies
}

# cflags
function gen_cflags() {
  cflags=('-g0' '-O3')
  if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-reuse"; then
    cflags+=('-fstack-reuse=all')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fdwarf2\\-cfi\\-asm"; then
    cflags+=('-fdwarf2-cfi-asm')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fplt"; then
    cflags+=('-fplt')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-ftrapv"; then
    cflags+=('-fno-trapv')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fexceptions"; then
    cflags+=('-fno-exceptions')
  elif gcc -v --help 2>&1 | grep -qw "\\-fhandle\\-exceptions"; then
    cflags+=('-fno-handle-exceptions')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-funwind\\-tables"; then
    cflags+=('-fno-unwind-tables')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fasynchronous\\-unwind\\-tables"; then
    cflags+=('-fno-asynchronous-unwind-tables')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-check"; then
    cflags+=('-fno-stack-check')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-clash\\-protection"; then
    cflags+=('-fno-stack-clash-protection')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-protector"; then
    cflags+=('-fno-stack-protector')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fcf\\-protection="; then
    cflags+=('-fcf-protection=none')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fsplit\\-stack"; then
    cflags+=('-fno-split-stack')
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-fsanitize"; then
    >temp.c
    if gcc -E -fno-sanitize=all temp.c >/dev/null 2>&1; then
      cflags+=('-fno-sanitize=all')
    fi
    rm temp.c
  fi
  if gcc -v --help 2>&1 | grep -qw "\\-finstrument\\-functions"; then
    cflags+=('-fno-instrument-functions')
  fi
}

# source compile
function source_compile() {
  cd "${TMPFILE_DIR}"
  # version
  _info "zh: 检索 Nginx 和 OpenSSL 的最新版本。"
  _info "en: Retrieve the latest versions of Nginx and OpenSSL."
  local nginx_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/nginx/nginx/tags | grep 'name' | cut -d\" -f4 | grep 'release' | head -1 | sed 's/release/nginx/')"
  local openssl_version="openssl-$(wget -qO- --no-check-certificate https://api.github.com/repos/openssl/openssl/tags | grep 'name' | cut -d\" -f4 | grep -Eoi '^openssl-([0-9]\.?){3}$' | head -1)"
  # gcc
  gen_cflags
  # nginx
  _info "zh: 下载最新版本的 Nginx。"
  _info "en: Download the latest versions of Nginx."
  _error_detect "curl -fsSL -o ${nginx_version}.tar.gz https://nginx.org/download/${nginx_version}.tar.gz"
  tar -zxf "${nginx_version}.tar.gz"
  # openssl
  _info "zh: 下载最新版本的 OpenSSL。"
  _info "en: Download the latest versions of OpenSSL."
  _error_detect "curl -fsSL -o ${openssl_version}.tar.gz https://github.com/openssl/openssl/archive/${openssl_version#*-}.tar.gz"
  tar -zxf "${openssl_version}.tar.gz"
  if [[ "${is_enable_brotli}" =~ ^[Yy]$ ]]; then
    # brotli
    _info "zh: 检出最新的 ngx_brotli 并构建依赖项。"
    _info "en: Checkout the latest ngx_brotli and build the dependencies."
    _error_detect "git clone https://github.com/google/ngx_brotli && cd ngx_brotli && git submodule update --init"
    cd "${TMPFILE_DIR}"
  fi
  # configure
  cd "${nginx_version}"
  sed -i "s/OPTIMIZE[ \\t]*=>[ \\t]*'-O'/OPTIMIZE          => '-O3'/g" src/http/modules/perl/Makefile.PL
  sed -i 's/NGX_PERL_CFLAGS="$CFLAGS `$NGX_PERL -MExtUtils::Embed -e ccopts`"/NGX_PERL_CFLAGS="`$NGX_PERL -MExtUtils::Embed -e ccopts` $CFLAGS"/g' auto/lib/perl/conf
  sed -i 's/NGX_PM_CFLAGS=`$NGX_PERL -MExtUtils::Embed -e ccopts`/NGX_PM_CFLAGS="`$NGX_PERL -MExtUtils::Embed -e ccopts` $CFLAGS"/g' auto/lib/perl/conf
  if [[ "${is_enable_brotli}" =~ ^[Yy]$ ]]; then
    ./configure --prefix="${NGINX_PATH}" --user=root --group=root --with-threads --with-file-aio --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_auth_request_module --with-http_random_index_module --with-http_secure_link_module --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-http_perl_module=dynamic --with-mail=dynamic --with-mail_ssl_module --with-stream --with-stream_ssl_module --with-stream_realip_module --with-stream_geoip_module=dynamic --with-stream_ssl_preread_module --with-google_perftools_module --add-module="../ngx_brotli" --with-compat --with-cc-opt="${cflags[*]}" --with-openssl="../${openssl_version}" --with-openssl-opt="${cflags[*]}"
  else
    ./configure --prefix="${NGINX_PATH}" --user=root --group=root --with-threads --with-file-aio --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_auth_request_module --with-http_random_index_module --with-http_secure_link_module --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-http_perl_module=dynamic --with-mail=dynamic --with-mail_ssl_module --with-stream --with-stream_ssl_module --with-stream_realip_module --with-stream_geoip_module=dynamic --with-stream_ssl_preread_module --with-google_perftools_module --with-compat --with-cc-opt="${cflags[*]}" --with-openssl="../${openssl_version}" --with-openssl-opt="${cflags[*]}"
  fi
  _info "zh: 申请 512MB 虚拟内存。"
  _info "en: Allocating 512MB of swap memory."
  swap_on 512
  # compile
  _info "zh: 编译 Nginx。"
  _info "en: Compiling Nginx."
  _error_detect "make -j$(nproc)"
}

# install by source
function source_install() {
  source_compile
  _info "zh: 安装 Nginx。"
  _info "en: Installing Nginx."
  make install
  ln -sf "${NGINX_PATH}/sbin/nginx" /usr/sbin/nginx
}

# update by source
function source_update() {
  # latest verions
  _info "zh: 检索 Nginx 和 OpenSSL 的最新版本。"
  _info "en: Retrieve the latest versions of Nginx and OpenSSL."
  local latest_nginx_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/nginx/nginx/tags | grep 'name' | cut -d\" -f4 | grep 'release' | head -1 | sed 's/release/nginx/')"
  local latest_openssl_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/openssl/openssl/tags | grep 'name' | cut -d\" -f4 | grep -Eoi '^openssl-([0-9]\.?){3}$' | head -1)"
  # current version
  _info "zh: 读取 Nginx 和 OpenSSL 的当前版本。"
  _info "en: Retrieve the current versions of Nginx and OpenSSL."
  local current_version_nginx="$(nginx -V 2>&1 | grep "^nginx version:.*" | cut -d / -f 2)"
  local current_version_openssl="$(nginx -V 2>&1 | grep "^built with OpenSSL" | awk '{print $4}')"
  # compare
  _info "zh: 判断是否需要更新。"
  _info "en: Determine if an update is needed."
  if _version_ge "${latest_nginx_version#*-}" "${current_version_nginx}" || _version_ge "${latest_openssl_version#*-}" "${current_version_openssl}"; then
    source_compile
    _info "zh: 更新 Nginx。"
    _info "en: Updating Nginx."
    mv "${NGINX_PATH}/sbin/nginx" "${NGINX_PATH}/sbin/nginx_$(date +%F)"
    backup_files "${NGINX_PATH}/modules"
    cp objs/nginx "${NGINX_PATH}/sbin/"
    cp objs/*.so "${NGINX_PATH}/modules/"
    ln -sf "${NGINX_PATH}/sbin/nginx" /usr/sbin/nginx
    if systemctl is-active --quiet nginx; then
      kill -USR2 $(cat /run/nginx.pid)
      if [[ -e "/run/nginx.pid.oldbin" ]]; then
        kill -WINCH $(cat /run/nginx.pid.oldbin)
        kill -HUP $(cat /run/nginx.pid.oldbin)
        kill -QUIT $(cat /run/nginx.pid.oldbin)
      else
        _info "zh: 未找到旧的 Nginx 进程。跳过后续步骤。"
        _info "en: Old Nginx process not found. Skipping further steps."
      fi
    fi
    return 0
  fi
  return 1
}

# purge
function purge_nginx() {
  _systemctl stop nginx
  _warn "zh: 卸载 Nginx。"
  _warn "en: Purging Nginx."
  rm -rf "${NGINX_PATH}"
  rm -rf /usr/sbin/nginx
  rm -rf /etc/systemd/system/nginx.service
  rm -rf "${NGINX_LOG_PATH}"
  systemctl daemon-reload
}

function systemctl_config_nginx() {
  cat >/etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/bin/rm -rf /dev/shm/nginx
ExecStartPre=/bin/mkdir /dev/shm/nginx
ExecStartPre=/bin/chmod 711 /dev/shm/nginx
ExecStartPre=/bin/mkdir /dev/shm/nginx/tcmalloc
ExecStartPre=/bin/chmod 0777 /dev/shm/nginx/tcmalloc
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
ExecStopPost=/bin/rm -rf /dev/shm/nginx
TimeoutStopSec=5
KillMode=mixed
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

function config_nginx() {
  _info "创建 Nginx 相关目录"
  mkdir -vp "${NGINX_LOG_PATH}"
  mkdir -vp "${NGINX_CONFIG_PATH}/conf.d"
  cd "${NGINX_CONFIG_PATH}"
  _info "zh: 通过压缩配置的 base64 字符串生成 nginxconfig.io-example.com.tar.gz。"
  _info "en: Generating nginxconfig.io-example.com.tar.gz from the compressed and base64-encoded configuration string."
  echo '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' | base64 --decode | tee "${NGINX_CONFIG_PATH}/nginxconfig.io-example.com.tar.gz" >/dev/null
  tar -xzvf nginxconfig.io-example.com.tar.gz | xargs chmod 0644
  _error_detect "curl -fsSL -o "${NGINX_CONFIG_PATH}/nginx.conf" "https://raw.githubusercontent.com/zxcvos/Xray-script/main/nginx/conf/nginx.conf""
  _error_detect "curl -fsSL -o "${NGINX_CONFIG_PATH}/sites-available/example.com.conf" "https://raw.githubusercontent.com/zxcvos/Xray-script/main/nginx/conf/sites-available/example.com.conf""
  _error_detect "curl -fsSL -o "${NGINX_CONFIG_PATH}/conf.d/restrict.conf" "https://raw.githubusercontent.com/zxcvos/Xray-script/main/nginx/conf/conf.d/restrict.conf""
  _error_detect "curl -fsSL -o "${NGINX_CONFIG_PATH}/nginxconfig.io/limit.conf" "https://raw.githubusercontent.com/zxcvos/Xray-script/main/nginx/conf/nginxconfig.io/limit.conf""
  case "${choice_domain}" in
  1)
    sed -i "/^stream {/,/^http {/s|^|#|" "${NGINX_CONFIG_PATH}/nginx.conf"
    sed -i "/^#http {/s|^#||" "${NGINX_CONFIG_PATH}/nginx.conf"
    sed -i "s|default_backend|cloudreve|" "${NGINX_CONFIG_PATH}/conf.d/restrict.conf"
    sed -i "s|domain|${domain} ${subdomain}|g" "${NGINX_CONFIG_PATH}/sites-available/example.com.conf"
    sed -i "s|; # proxy_protocol;| proxy_protocol;|g" "${NGINX_CONFIG_PATH}/sites-available/example.com.conf"
    sed -i "s|# real_ip_header|real_ip_header|g" "${NGINX_CONFIG_PATH}/sites-available/example.com.conf"
    ;;
  2 | 3)
    sed -i "s|example.com|${subdomain}|g" "${NGINX_CONFIG_PATH}/nginx.conf"
    sed -i "s|domain|${subdomain}|g" "${NGINX_CONFIG_PATH}/sites-available/example.com.conf"
    ;;
  esac
  sed -i "s|certs/example.com|certs/${subdomain}|g" "${NGINX_CONFIG_PATH}/sites-available/example.com.conf"
  sed -i "s|.example.com|.${domain}|g" "${NGINX_CONFIG_PATH}/sites-available/example.com.conf"
  sed -i "s|max-age=31536000|max-age=63072000|" "${NGINX_CONFIG_PATH}/nginxconfig.io/security.conf"
  rm -rf "${NGINX_CONFIG_PATH}/sites-enabled/example.com.conf"
  mv "${NGINX_CONFIG_PATH}/sites-available/example.com.conf" "${NGINX_CONFIG_PATH}/sites-available/${subdomain}.conf"
  ln -sf "${NGINX_CONFIG_PATH}/sites-available/${subdomain}.conf" "${NGINX_CONFIG_PATH}/sites-enabled/${subdomain}.conf"
  if [[ ! "${is_enable_brotli}" =~ ^[Yy]$ ]]; then
    # disable brotli
    _warn "zh: 禁用 brotli 配置。"
    _warn "en: Disabling the brotli configuration."
    sed -i "/^brotli/,/^brotli_types/s/^/#/" "${NGINX_CONFIG_PATH}/nginxconfig.io/general.conf"
  fi
}

# install
function install_acme_sh() {
  _info "zh: 安装 acme.sh。"
  _info "en: Installing acme.sh."
  curl https://get.acme.sh | sh
  ${HOME}/.acme.sh/acme.sh --upgrade --auto-upgrade
  ${HOME}/.acme.sh/acme.sh --set-default-ca --server letsencrypt
}

# update
function update_acme_sh() {
  _info "zh: 更新 acme.sh。"
  _info "en: Updating acme.sh."
  ${HOME}/.acme.sh/acme.sh --upgrade
}

# purge
function purge_acme_sh() {
  _warn "zh: 卸载 acme.sh。"
  _warn "en: Purging acme.sh."
  ${HOME}/.acme.sh/acme.sh --upgrade --auto-upgrade 0
  ${HOME}/.acme.sh/acme.sh --uninstall
  rm -rf "${HOME}/.acme.sh"
  rm -rf "${WEBROOT_PATH}"
  rm -rf "${SSL_PATH}"
}

# issue
function issue_cert() {
  local issue_domain
  case "${choice_domain}" in
  1)
    issue_domain=(${domain} ${subdomain})
    ;;
  2 | 3)
    issue_domain=(${subdomain})
    ;;
  esac
  [[ -d "${WEBROOT_PATH}" ]] || mkdir -vp "${WEBROOT_PATH}"
  [[ -d "${SSL_PATH}/${subdomain}" ]] || mkdir -vp "${SSL_PATH}/${subdomain}"

  _info "zh: 备份 nginx.conf 文件。"
  _info "en: Backing up the nginx.conf file."
  mv "${NGINX_CONFIG_PATH}/nginx.conf" "${NGINX_CONFIG_PATH}/nginx.conf.bak"
  _info "zh: 创建用于申请证书的 nginx.conf 文件。"
  _info "en: Creating the nginx.conf file for certificate issuance."
  cat >"${NGINX_CONFIG_PATH}/nginx.conf" <<EOF
user                 root;
pid                  /run/nginx.pid;
worker_processes     1;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        location ^~ /.well-known/acme-challenge/ {
            root ${WEBROOT_PATH};
        }
    }
}
EOF
  _info "zh: 检测并重载新的配置文件。"
  _info "en: Checking and reloading the new configuration file."
  if systemctl is-active --quiet nginx; then
    nginx -t && systemctl reload nginx
  else
    nginx -t && systemctl start nginx
  fi

  _info "zh: 请求颁发 ECC 证书。"
  _info "en: Requesting ECC certificate issuance."
  ${HOME}/.acme.sh/acme.sh --issue $(printf -- " -d %s" "${issue_domain[@]}") \
    --webroot ${WEBROOT_PATH} \
    --keylength ec-256 \
    --accountkeylength ec-256 \
    --server letsencrypt \
    --ocsp

  if [[ $? -ne 0 ]]; then
    ${HOME}/.acme.sh/acme.sh --issue $(printf -- " -d %s" "${issue_domain[@]}") \
      --webroot ${WEBROOT_PATH} \
      --keylength ec-256 \
      --accountkeylength ec-256 \
      --server letsencrypt \
      --ocsp \
      --debug
    _info "zh: 将备份的 nginx.conf 复原。"
    _info "en: Restoring the backed-up nginx.conf."
    mv -f "${NGINX_CONFIG_PATH}/nginx.conf.bak" "${NGINX_CONFIG_PATH}/nginx.conf"
    _error "zh: ECC 证书请求失败。"
    _error "en: ECC certificate request failed."
  fi

  _info "zh: 将备份的 nginx.conf 复原。"
  _info "en: Restoring the backed-up nginx.conf."
  mv -f "${NGINX_CONFIG_PATH}/nginx.conf.bak" "${NGINX_CONFIG_PATH}/nginx.conf"
  _info "zh: 检测并重载新的配置文件。"
  _info "en: Checking and reloading the new configuration file."
  nginx -t && systemctl reload nginx

  _info "zh: 安装证书到目录: ${SSL_PATH}/${subdomain}。"
  _info "en: Installing the certificate to the directory: ${SSL_PATH}/${subdomain}."
  ${HOME}/.acme.sh/acme.sh --install-cert --ecc $(printf -- " -d %s" "${issue_domain[@]}") \
    --key-file "${SSL_PATH}/${subdomain}/privkey.pem" \
    --fullchain-file "${SSL_PATH}/${subdomain}/fullchain.pem" \
    --reloadcmd "nginx -t && systemctl reload nginx"
}

# stop renew
function stop_renew_cert() {
  local issue_domain
  case "${choice_domain}" in
  1)
    issue_domain=(${domain} "www.${domain}")
    ;;
  2)
    issue_domain=("drive.${domain}")
    ;;
  3)
    issue_domain=("pan.${domain}")
    ;;
  esac
  ${HOME}/.acme.sh/acme.sh --remove $(printf -- " -d %s" "${issue_domain[@]}") --ecc
}

# install or update
function install_update_xray() {
  _info "zh: 安装/更新 Xray。"
  _info "en: Installing/Updating Xray."
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --beta'
  if [[ ! -f "${XRAY_SCRIPT_PATH}/update_dat.sh" ]]; then
    _info "zh: 下载 update_dat.sh"
    _info "en: Downloading update_dat.sh."
    _error_detect "curl -fsSL -o ${XRAY_SCRIPT_PATH}/update_dat.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/update-dat.sh"
    chmod a+x ${XRAY_SCRIPT_PATH}/update_dat.sh
    _info "zh: 设置 geo 文件定时更新任务。"
    _info "en: Setting up crontab task for updating geo files."
    (
      crontab -l 2>/dev/null
      echo "30 6 * * * ${XRAY_SCRIPT_PATH}/update_dat.sh >/dev/null 2>&1"
    ) | awk '!x[$0]++' | crontab -
  fi
  _info "zh: 安装/更新完成 Xray，后更新 geo 文件。"
  _info "en: Installation/Update of Xray completed, updating geo files afterwards."
  ${XRAY_SCRIPT_PATH}/update_dat.sh
}

# purge
function purge_xray() {
  _systemctl stop xray
  crontab -l | grep -v "${XRAY_SCRIPT_PATH}/update_dat.sh >/dev/null 2>&1" | crontab -
  _warn "zh: 卸载 Xray。"
  _warn "en: Purging Xray."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
  rm -rf /etc/systemd/system/xray.service
  rm -rf /etc/systemd/system/xray@.service
  rm -rf /usr/local/bin/xray
  rm -rf /usr/local/etc/xray
  rm -rf /usr/local/share/xray
  rm -rf /var/log/xray
  rm -rf "${XRAY_SCRIPT_PATH}"
  systemctl daemon-reload
}

function systemctl_config_xray() {
  cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
#CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
#NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

function config_xray() {
  _info "zh: 下载 Xray 的配置文件 config.json。"
  _info "en: Download the Xray configuration file config.json."
  _error_detect 'curl -fsSL -o /usr/local/etc/xray/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/VLESS-XTLS-uTLS-REALITY/myself.json'
  # x25519
  _info "zh: 使用 xray x25519 生成配对的公私钥。"
  _info "en: Generate paired public and private keys using xray x25519."
  local xray_x25519="$(xray x25519)"
  local xs_private_key="$(echo ${xray_x25519} | awk '{print $3}')"
  local xs_public_key="$(echo ${xray_x25519} | awk '{print $6}')"
  # Xray-core config.json
  _info "zh: 修改 config.json 的 uuid、privateKey、serverNames、shortIds。"
  _info "en: Modify uuid, privateKey, serverNames, and shortIds in config.json."
  ${XRAY_CONFIG_MANAGE} -u ${in_uuid}
  ${XRAY_CONFIG_MANAGE} -x "${xs_private_key}"
  case "${choice_domain}" in
  1)
    sed -i "s|\"listen\": \"/dev/shm/nginx/raw.sock\",|\"port\": 443,|" /usr/local/etc/xray/config.json
    sed -i "s|\"xver\": 0,|\"xver\": 2,|" /usr/local/etc/xray/config.json
    ${XRAY_CONFIG_MANAGE} --not-validate -sn "${domain},www.${domain}"
    ;;
  2)
    ${XRAY_CONFIG_MANAGE} --not-validate -sn "drive.${domain}"
    ;;
  3)
    ${XRAY_CONFIG_MANAGE} --not-validate -sn "pan.${domain}"
    ;;
  esac
  sed -i "s|\"2\"|\"$(openssl rand -hex 1)\"|; s|\"4\"|\"$(openssl rand -hex 2)\"|; s|\"8\"|\"$(openssl rand -hex 4)\"|; s|\"16\"|\"$(openssl rand -hex 8)\"|" /usr/local/etc/xray/config.json
  # Xray-script config.json
  local uuid="$(jq -r '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .settings.clients[] | select(.email == "vless@xtls.reality") | .id' /usr/local/etc/xray/config.json)"
  local serverNames="$(jq -c '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .streamSettings.realitySettings.serverNames' /usr/local/etc/xray/config.json)"
  local shortIds="$(jq -c '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .streamSettings.realitySettings.shortIds' /usr/local/etc/xray/config.json)"
  jq --arg id "${uuid}" '.xray.id = $id' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --argjson serverNames "${serverNames}" '.xray.serverNames = $serverNames' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --argjson shortIds "${shortIds}" '.xray.shortIds = $shortIds' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
}

# install
function install_xray_config_manage() {
  _info "zh: 下载 xray_config_manage.sh。"
  _info "en: Downloading xray_config_manage.sh."
  _error_detect "curl -fsSL -o ${XRAY_CONFIG_MANAGE} https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/xray_config_manage.sh"
  chmod a+x "${XRAY_CONFIG_MANAGE}"
}

# install
function install_docker() {
  _info "zh: 安装 Docker。"
  _info "en: Installing Docker."
  _error_detect "curl -fsSL -o ${XRAY_SCRIPT_PATH}/install-docker.sh https://get.docker.com"
  if [[ "$(_os)" == "centos" ]]; then
    sed -i 's/centos|/centos|rocky|/' ${XRAY_SCRIPT_PATH}/install-docker.sh
    sed -i 's|repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"|repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE" \n[[ "$lsb_dist" == "rocky" ]] \&\& repo_file_url="$DOWNLOAD_URL/linux/centos/$REPO_FILE"\n|' ${XRAY_SCRIPT_PATH}/install-docker.sh
    if [[ "$(_os_ver)" -eq 8 ]]; then
      sed -i 's|$sh_c "$pkg_manager install -y -q $pkgs"| $sh_c "$pkg_manager install -y -q $pkgs --allowerasing"|' ${XRAY_SCRIPT_PATH}/install-docker.sh
    fi
  fi
  _error_detect "sh ${XRAY_SCRIPT_PATH}/install-docker.sh --dry-run"
  _error_detect "sh ${XRAY_SCRIPT_PATH}/install-docker.sh"
}

# install
function install_cloudreve() {
  _info "zh: 创建 cloudreve 相关目录。"
  _info "en: Creating directories for cloudreve."
  mkdir -vp "${CLOUDREVE_PATH}" &&
    mkdir -vp "${CLOUDREVE_PATH}/cloudreve/{uploads,avatar}" &&
    touch "${CLOUDREVE_PATH}/cloudreve/conf.ini" &&
    touch "${CLOUDREVE_PATH}/cloudreve/cloudreve.db" &&
    mkdir -vp "${CLOUDREVE_PATH}/aria2/config" &&
    mkdir -vp "${CLOUDREVE_PATH}/data/aria2" &&
    chmod -R 777 "${CLOUDREVE_PATH}/data/aria2"
  _info "zh: 下载管理 cloudreve 的 docker-compose.yaml。"
  _info "en: Downloading docker-compose.yaml for managing cloudreve."
  _error_detect "curl -fsSL -o ${CLOUDREVE_PATH}/docker-compose.yaml https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudreve/docker-compose.yaml"
  cd "${CLOUDREVE_PATH}"
  docker_compose_manage start
  _info "zh: 等待 cloudreve 启动。"
  _info "en: Waiting for cloudreve to start."
  sleep 5
  _info "zh: 获取 cloudreve 版本号，初始账号，初始密码。"
  _info "en: Getting the version, initial username, and initial password of cloudreve."
  local cloudreve_version="$(docker logs cloudreve | grep -Eoi "v[0-9]+.[0-9]+.[0-9]+" | cut -c2-)"
  local cloudreve_username="$(docker logs cloudreve | grep Admin | awk '{print $NF}' | head -1)"
  local cloudreve_password="$(docker logs cloudreve | grep Admin | awk '{print $NF}' | tail -1)"
  jq --arg version "${cloudreve_version}" '.cloudreve.version = $version' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg username "${cloudreve_username}" '.cloudreve.username = $username' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg password "${cloudreve_password}" '.cloudreve.password = $password' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  _info "zh: 下载 cloudreve_watchtower.sh。"
  _info "en: Downloading cloudreve_watchtower.sh."
  _error_detect "curl -fsSL -o ${XRAY_SCRIPT_PATH}/cloudreve_watchtower.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudreve/watchtower.sh"
  chmod a+x ${XRAY_SCRIPT_PATH}/cloudreve_watchtower.sh
  _info "zh: 设置 cloudreve 版本号定时记录任务。"
  _info "en: Setting up crontab task to record cloudreve version."
  (
    crontab -l 2>/dev/null
    echo "0 7 * * * ${XRAY_SCRIPT_PATH}/cloudreve_watchtower.sh ${XRAY_SCRIPT_PATH} >/dev/null 2>&1"
  ) | awk '!x[$0]++' | crontab -
}

# purge
function purge_cloudreve() {
  _warn "zh: 停止 Cloudreve。"
  _warn "en: Stopping Cloudreve."
  cd "${CLOUDREVE_PATH}"
  _info "zh: 删除 cloudreve 版本号定时记录任务。"
  _info "en: Delete crontab task to record cloudreve version."
  crontab -l | grep -v "${XRAY_SCRIPT_PATH}/cloudreve_watchtower.sh ${XRAY_SCRIPT_PATH} >/dev/null 2>&1" | crontab -
  _warn "zh: 卸载 Cloudreve。"
  _warn "en: Purging Cloudreve."
  docker_compose_manage rmi
  cd "${HOME}"
  rm -rf "${CLOUDREVE_PATH}"
}

# install
function install_cloudflare_warp() {
  _info "zh: 创建 cloudflare-warp 相关目录。"
  _info "en: Creating directories for cloudflare_warp."
  mkdir -vp "${CLOUDFLARE_WARP_PATH}"
  mkdir -vp "${HOME}/.warp"
  _info "zh: 下载构建 cloudflare-warp 镜像的 Dockerfile 和 startup.sh。"
  _info "en: Downloading Dockerfile and startup.sh for building the cloudflare-warp image."
  _error_detect "curl -fsSL -o ${CLOUDFLARE_WARP_PATH}/Dockerfile https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudflare-warp/Dockerfile"
  _error_detect "curl -fsSL -o ${CLOUDFLARE_WARP_PATH}/startup.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudflare-warp/startup.sh"
  cd "${CLOUDFLARE_WARP_PATH}"
  _info "zh: 构建自定义 cloudflare-warp 镜像。"
  _info "en: Building the custom cloudflare-warp image."
  docker build -t cloudflare-warp .
  _info "zh: 运行 cloudflare-warp 镜像。"
  _info "en: Running the cloudflare-warp image."
  docker run -v "${HOME}/.warp":/var/lib/cloudflare-warp:rw --restart=always --name=cloudflare-warp cloudflare-warp
}

# purge
function purge_cloudflare_warp() {
  _warn "zh: 卸载 cloudflare-warp。"
  _warn "en: Purging cloudflare-warp."
  cd "${HOME}"
  docker_manage rmi cloudflare-warp
  rm -rf "${CLOUDFLARE_WARP_PATH}"
  rm -rf "${HOME}/.warp"
}

check_os

function update_versions_info() {
  local nginx_version="$(nginx -V 2>&1 | grep "^nginx version:.*" | cut -d / -f 2)"
  local openssl_version="$(nginx -V 2>&1 | grep "^built with OpenSSL" | awk '{print $4}')"
  local brotli="$([[ "${is_enable_brotli}" =~ ^[Yy]$ ]] && echo 1 || echo 0)"
  local xray_version="$(xray version | awk 'NR == 1 {print $2}')"
  jq --arg version "${nginx_version}" '.nginx.version = $version' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg version "${openssl_version}" '.nginx.openssl = $version' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --argjson brotli "${brotli}" '.nginx.brotli = $brotli' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg version "${xray_version}" '.xray.version = $version' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
}

# 1.install
function install() {
  if [[ -f "${XRAY_SCRIPT_PATH}/config.json" ]]; then
    read -p "zh: 是否重新安装 [y/N] " is_reinstall
    read -p "en: Do you want to reinstall [y/N] " is_reinstall
    [[ "${is_reinstall}" =~ ^[Yy]$ ]] || exit
  fi
  # Get variable
  read_domain
  read_uuid
  enable_brotli
  # Dependencies
  mkdir -vp "${XRAY_SCRIPT_PATH}"
  script_dependencies
  # Check dns
  case "${choice_domain}" in
  1)
    check_dns_resolution "${domain}"
    check_dns_resolution "${subdomain}"
    ;;
  2)
    check_dns_resolution "${subdomain}"
    ;;
  3)
    check_dns_resolution "${subdomain}"
    ;;
  esac
  # Script config
  _error_detect "curl -fsSL -o ${XRAY_SCRIPT_PATH}/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/myself.json"
  # Firewall
  firewall_manage
  firewall_pass allow "$(sed -En "s/^[#pP].*ort\s*([0-9]*)$/\1/p" /etc/ssh/sshd_config)"
  firewall_pass allow "$(jq -r '.nginx.http' ${XRAY_SCRIPT_PATH}/config.json)" "tcp&udp"
  firewall_pass allow "$(jq -r '.nginx.https' ${XRAY_SCRIPT_PATH}/config.json)" "tcp&udp"
  # Docker
  install_docker
  install_cloudreve
  install_cloudflare_warp
  # Xray
  install_update_xray
  install_xray_config_manage
  systemctl_config_xray
  config_xray
  # Nginx
  source_install
  systemctl_config_nginx
  config_nginx
  # acme
  install_acme_sh
  issue_cert
  # Xray-script config.json
  update_versions_info
  jq --argjson type "${choice_domain}" '.domain.type = $type' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg domain "${domain}" '.domain.name = $domain' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  # Run service
  stop
  start
  # View config
  view_config
}

# 1.update
function update() {
  # Get variable
  enable_brotli
  # dependencies
  script_dependencies
  # acme
  update_acme_sh
  # Xray
  install_update_xray
  # Nginx
  if source_update; then
    if [[ ! "${is_enable_brotli}" =~ ^[Yy]$ ]]; then
      # disable brotli
      _warn "zh: 禁用 brotli 配置。"
      _warn "en: Disabling the brotli configuration."
      sed -i "/^brotli/,/^brotli_types/s/^/#/" "${NGINX_CONFIG_PATH}/nginxconfig.io/general.conf"
    else
      sed -i "/^#brotli/,/^#brotli_types/s/^#//" "${NGINX_CONFIG_PATH}/nginxconfig.io/general.conf"
    fi
  fi
  # Xray-script config.json
  update_versions_info
}

# 3.uninstall
function uninstall() {
  domain="$(jq -r '.domain.name' ${XRAY_SCRIPT_PATH}/config.json)"
  choice_domain="$(jq -r '.domain.type' ${XRAY_SCRIPT_PATH}/config.json)"
  # stop serivce
  stop
  # acme
  stop_renew_cert
  purge_acme_sh
  # Nginx
  purge_nginx
  # Xray
  purge_xray
  # Docker
  purge_cloudreve
  purge_cloudflare_warp
}

# 4.start
function start() {
  # Docker
  docker_manage start cloudflare-warp
  cd "${CLOUDREVE_PATH}"
  docker_compose_manage start
  _info "zh: 设置 cloudreve 版本号定时记录任务。"
  _info "en: Setting up crontab task to record cloudreve version."
  (
    crontab -l 2>/dev/null
    echo "0 7 * * * ${XRAY_SCRIPT_PATH}/cloudreve_watchtower.sh ${XRAY_SCRIPT_PATH} >/dev/null 2>&1"
  ) | awk '!x[$0]++' | crontab -
  # Nginx
  _systemctl start nginx
  # Xray
  _systemctl start xray
}

# 5.stop
function stop() {
  # Nginx
  _systemctl stop nginx
  # Xray
  _systemctl stop xray
  # Docker
  docker_manage stop cloudflare-warp
  cd "${CLOUDREVE_PATH}"
  docker_compose_manage stop
  _info "zh: 删除 cloudreve 版本号定时记录任务。"
  _info "en: Delete crontab task to record cloudreve version."
  crontab -l | grep -v "${XRAY_SCRIPT_PATH}/cloudreve_watchtower.sh ${XRAY_SCRIPT_PATH} >/dev/null 2>&1" | crontab -
}

# 6.restart
function restart() {
  # Docker
  docker_manage restart cloudflare-warp
  cd "${CLOUDREVE_PATH}"
  docker_compose_manage restart
  # Nginx
  _systemctl restart nginx
  # Xray
  _systemctl restart xray
}

# 101.view config
function view_config() {
  local cloudreve_username="$(jq -r '.cloudreve.username' ${XRAY_SCRIPT_PATH}/config.json)"
  local cloudreve_password="$(jq -r '.cloudreve.password' ${XRAY_SCRIPT_PATH}/config.json)"
  local IPv4="$(wget -qO- -t1 -T2 ipv4.icanhazip.com)"
  local xs_port="$(jq -r '.nginx.https' ${XRAY_SCRIPT_PATH}/config.json)"
  local xs_id="$(jq -r '.xray.id' ${XRAY_SCRIPT_PATH}/config.json)"
  local xs_public_key="$(jq -r '.xray.publicKey' ${XRAY_SCRIPT_PATH}/config.json)"
  local xs_server_names="$(jq -r '.xray.serverNames | join(" ")' ${XRAY_SCRIPT_PATH}/config.json)"
  local xs_shortId="$(jq -r '.xray.shortIds[]' ${XRAY_SCRIPT_PATH}/config.json | shuf -n 1)"
  echo -e "--------------   cloudreve   --------------"
  echo -e "username    : ${cloudreve_username}"
  echo -e "password    : ${cloudreve_password}"
  echo -e "-------------- client config --------------"
  echo -e "address     : ${IPv4}"
  echo -e "port        : ${xs_port}"
  echo -e "protocol    : vless"
  echo -e "id          : ${xs_id}"
  echo -e "flow        : xtls-rprx-vision"
  echo -e "network     : tcp"
  echo -e "TLS         : reality"
  echo -e "SNI         : ${xs_server_names}"
  echo -e "Fingerprint : chrome"
  echo -e "PublicKey   : ${xs_public_key}"
  echo -e "ShortId     : ${xs_shortId}"
  echo -e "SpiderX     : /"
  echo -e "------------------------------------------"
  _info "zh: ShortId 是从已有的数据中随机获取，所以可能每次不同。"
  _info "en: ShortId is randomly selected from existing data, so it may be different each time."
  echo -e "------------------------------------------"
  read -p "zh: 是否生成分享链接[y/N] " is_show_share_link
  read -p "en: Generate sharing link? [y/N] " is_show_share_link
  if [[ "${is_show_share_link}" =~ ^[Yy]$ ]]; then
    local sl=""
    for xs_server_name in ${xs_server_names}; do
      [[ "${xs_shortId}" != "" ]] && xs_shortId="sid=${xs_shortId}"
      sl="vless://${xs_id}@${IPv4}:${xs_port}?security=reality&flow=xtls-rprx-vision&fp=chrome&pbk=${xs_public_key}&sni=${xs_server_name}&spx=%2F&${xs_shortId}"
      echo "${sl%&}#${xs_server_name}"
    done
  fi
  echo -e "------------------------------------------"
  echo -e "zh: ${RED}此脚本仅供交流学习使用，请勿使用此脚本行违法之事。${NC}"
  echo -e "en: ${RED}This script is for educational purposes only.${NC}"
  echo -e "zh: ${RED}网络非法外之地，行非法之事，必将接受法律制裁。${NC}"
  echo -e "en: ${RED}Do not use it for illegal activities.${NC}"
  echo -e "------------------------------------------"
}

# 102.change xray uuid
function change_xray_uuid() {
  read_uuid
  # Xray-core config.json
  ${XRAY_CONFIG_MANAGE} -u ${in_uuid}
  # Xray-script config.json
  local uuid="$(jq -r '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .settings.clients[] | select(.email == "vless@xtls.reality") | .id' /usr/local/etc/xray/config.json)"
  jq --arg id "${uuid}" '.xray.id = $id' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  _systemctl restart xray
  view_config
}

# 103.change xray x25519
function change_xray_x25519() {
  # x25519
  _info "zh: 使用 xray x25519 生成配对的公私钥。"
  _info "en: Generate paired public and private keys using xray x25519."
  local xray_x25519="$(xray x25519)"
  local xs_private_key="$(echo ${xray_x25519} | awk '{print $3}')"
  local xs_public_key="$(echo ${xray_x25519} | awk '{print $6}')"
  # Xray-core config.json
  ${XRAY_CONFIG_MANAGE} -x "${xs_private_key}"
  # Xray-script config.json
  jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' "${XRAY_SCRIPT_PATH}/config.json" >"${XRAY_SCRIPT_PATH}/tmp.json" && mv -f "${XRAY_SCRIPT_PATH}/tmp.json" "${XRAY_SCRIPT_PATH}/config.json"
  _systemctl restart xray
  view_config
}

# 201.update kernel
function update_kernel() {
  bash <(wget -qO- https://raw.githubusercontent.com/zxcvos/system-automation-scripts/main/update-kernel.sh)
}

# 202.remove kernel
function remove_kernel() {
  bash <(wget -qO- https://raw.githubusercontent.com/zxcvos/system-automation-scripts/main/remove-kernel.sh)
}

# 203.change ssh port
function change_ssh_port() {
  local ssh_config="/etc/ssh/sshd_config"
  local current_port="$(sed -En "s/^[#pP].*ort\s*([0-9]*)$/\1/p" "${ssh_config}")"
  _info "zh: 当前 SSH 连接端口为 ${current_port}"
  _info "en: Current SSH connection port is ${current_port}"
  read -p "zh: 请输入新的 SSH 端口号: " new_port
  read -p "en: Enter the new SSH port: " new_port
  validate_port "${new_port}"
  cp "${ssh_config}" "${ssh_config}.bak"
  sed -i "s/^[#pP].*ort\s*[0-9]*$/Port ${new_port}/" "${ssh_config}"
  if systemctl restart sshd; then
    firewall_pass allow "${new_port}"
    firewall_pass remove "${current_port}"
    _info "zh: 当前 SSH 端口已修改为 ${new_port}"
    _info "en: Current SSH port has been changed to ${new_port}"
  else
    mv "${ssh_config}.bak" "${ssh_config}"
    _error "zh: 无法重启 SSH 服务，请手动检查。"
    _error "en: Failed to restart SSH service. Please check manually."
  fi
}

# 204.Optimize Kernel Parameters
function optimize_kernel_parameters() {
  read -p "zh: 是否选择内核参数调优 [y/N] " is_opt
  read -p "en: Optimize kernel parameters? [y/N] " is_opt
  if [[ "${is_opt}" =~ ^[Yy]$ ]]; then
    # limits
    if [ -f /etc/security/limits.conf ]; then
      LIMIT='1048576'
      sed -i '/^\(\*\|root\)[[:space:]]*\(hard\|soft\)[[:space:]]*\(nofile\|memlock\)/d' /etc/security/limits.conf
      echo -ne "*\thard\tmemlock\t${LIMIT}\n*\tsoft\tmemlock\t${LIMIT}\nroot\thard\tmemlock\t${LIMIT}\nroot\tsoft\tmemlock\t${LIMIT}\n*\thard\tnofile\t${LIMIT}\n*\tsoft\tnofile\t${LIMIT}\nroot\thard\tnofile\t${LIMIT}\nroot\tsoft\tnofile\t${LIMIT}\n\n" >>/etc/security/limits.conf
    fi
    if [ -f /etc/systemd/system.conf ]; then
      sed -i 's/#\?DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/system.conf
    fi
    # systemd-journald
    sed -i 's/^#\?Storage=.*/Storage=volatile/' /etc/systemd/journald.conf
    sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=8M/' /etc/systemd/journald.conf
    sed -i 's/^#\?RuntimeMaxUse=.*/RuntimeMaxUse=8M/' /etc/systemd/journald.conf
    systemctl restart systemd-journald
    # sysctl
    _error_detect "curl -fsSL -o /etc/sysctl.d/99-sysctl.conf https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/sysctl.conf"
    sysctl -p
  fi
}

function main() {
  clear
  echo -e "zh: --------------- Xray-script ---------------"
  echo -e "en: --------------- Xray-script ---------------"
  echo -e "zh:  Version      : ${GREEN}v2023-12-31${NC}(${RED}beta${NC})"
  echo -e "en:  Version      : ${GREEN}v2023-12-31${NC}(${RED}beta${NC})"
  echo -e "zh:  Title        : Xray 管理脚本"
  echo -e "en:  Title        : Xray Management Script"
  echo -e "zh:  Description  : Xray 前置或 Nginx 分流"
  echo -e "en:  Description  : Xray frontend or Nginx SNI shunting"
  echo -e "zh:               : reality dest 目标为自建伪装站"
  echo -e "en:               : reality dest points to a self-built camouflage site"
  echo -e "zh: ----------------- 装载管理 ----------------"
  echo -e "en: ----------------- Installation Management ----------------"
  echo -e "zh: ${GREEN}1.${NC} 安装"
  echo -e "en: ${GREEN}1.${NC} Install"
  echo -e "zh: ${GREEN}2.${NC} 更新"
  echo -e "en: ${GREEN}2.${NC} Update"
  echo -e "zh: ${GREEN}3.${NC} 卸载"
  echo -e "en: ${GREEN}3.${NC} Uninstall"
  echo -e "zh: ----------------- 操作管理 ----------------"
  echo -e "en: ----------------- Operation Management ----------------"
  echo -e "zh: ${GREEN}4.${NC} 启动"
  echo -e "en: ${GREEN}4.${NC} Start"
  echo -e "zh: ${GREEN}5.${NC} 停止"
  echo -e "en: ${GREEN}5.${NC} Stop"
  echo -e "zh: ${GREEN}6.${NC} 重启"
  echo -e "en: ${GREEN}6.${NC} Restart"
  echo -e "zh: ----------------- 配置管理 ----------------"
  echo -e "en: ----------------- Configuration Management ----------------"
  echo -e "zh: ${GREEN}101.${NC} 查看配置"
  echo -e "en: ${GREEN}101.${NC} View Configuration"
  echo -e "zh: ${GREEN}102.${NC} 修改 id"
  echo -e "en: ${GREEN}102.${NC} Change xray uuid"
  echo -e "zh: ${GREEN}103.${NC} 修改 x25519"
  echo -e "en: ${GREEN}103.${NC} Change xray x25519"
  echo -e "zh: ----------------- 其他选项 ----------------"
  echo -e "en: ----------------- Other Options ----------------"
  echo -e "zh: ${GREEN}201.${NC} 更新至最新稳定版内核"
  echo -e "en: ${GREEN}201.${NC} Update to Latest Stable Kernel"
  echo -e "zh: ${GREEN}202.${NC} 卸载多余内核"
  echo -e "en: ${GREEN}202.${NC} Remove Extra Kernels"
  echo -e "zh: ${GREEN}203.${NC} 修改 ssh 端口"
  echo -e "en: ${GREEN}203.${NC} Change SSH Port"
  echo -e "zh: ${GREEN}204.${NC} 内核参数调优"
  echo -e "en: ${GREEN}204.${NC} Optimize Kernel Parameters"
  echo -e "zh: -------------------------------------------"
  echo -e "en: -------------------------------------------"
  echo -e "zh: ${RED}0.${NC} 退出"
  echo -e "en: ${RED}0.${NC} Exit"

  read -p "zh: 请选择操作: " choice
  read -p "en: Choose an action: " choice

  if [[ ${choice} -gt 1 && ${choice} -lt 201 && ! -f "${XRAY_SCRIPT_PATH}/config.json" ]]; then
    _error "zh: 请先使用脚本进行安装。"
    _error "en: Please install using the script first."
  fi

  case ${choice} in
  1) install ;;
  2) update ;;
  3) uninstall ;;
  4) start ;;
  5) stop ;;
  6) restart ;;
  101) view_config ;;
  102) change_xray_uuid ;;
  103) change_xray_x25519 ;;
  201) update_kernel ;;
  202) remove_kernel ;;
  203) change_ssh_port ;;
  204) optimize_kernel_parameters ;;
  0) exit ;;
  *)
    _error "zh: 无效的选择。"
    _error "en: Invalid choice."
    ;;
  esac
}
