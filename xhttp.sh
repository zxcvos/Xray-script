#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian9+, Ubuntu16+
# Description:      Script to Xray manage
#
# Copyright (C) 2024 zxcvos
#
# Xray Official:
#   Xray-core: https://github.com/XTLS/Xray-core
#   REALITY: https://github.com/XTLS/REALITY
#   XHTTP: https://github.com/XTLS/Xray-core/discussions/4113
# Xray-script:
#   https://github.com/zxcvos/Xray-script
# Xray-examples:
#   https://github.com/chika0801/Xray-examples
#   https://github.com/lxhao61/integrated-examples
#   https://github.com/XTLS/Xray-core/discussions/4118
# docker-install:
#   https://github.com/docker/docker-install
# Cloudflare WARP Proxy:
#   https://github.com/haoel/haoel.github.io?tab=readme-ov-file#1043-docker-%E4%BB%A3%E7%90%86
#   https://github.com/e7h4n/cloudflare-warp

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# color
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# directory
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
readonly CUR_FILE="$(basename $0)"

# install option
declare INSTALL_OPTION=''

# specified version
declare SPECIFIED_VERSION=''

# status
declare STATUS=''

# warp
declare WARP=''

# automation
declare IS_AUTO=''

# update config
declare UPDATE_CONFIG=''

# xtls config
declare XTLS_CONFIG='xhttp'

# download url
declare DOWNLOAD_URL=''

# xray port
declare XRAY_PORT=443

# xray uuid
declare XRAY_UUID=''

# fallback uuid
declare FALLBACK_UUID=''

# kcp seed
declare KCP_SEED=''

# trojan password
declare TROJAN_PASSWORD=''

# target domain
declare TARGET_DOMAIN=''

# server names
declare SERVER_NAMES=''

# private key
declare PRIVATE_KEY=''

# public key
declare PUBLIC_KEY=''

# short id
declare SHORT_IDS=''

# xhttp path
declare XHTTP_PATH=''

# share link
declare SHARE_LINK=''

# status print
function _input_tips() {
  printf "${GREEN}[输入提示] ${NC}"
  printf -- "%s" "$@"
}

function _info() {
  printf "${GREEN}[信息] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _warn() {
  printf "${YELLOW}[警告] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _error() {
  printf "${RED}[错误] ${NC}"
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
  _info "${cmd}"
  eval ${cmd}
  if [[ $? -ne 0 ]]; then
    _error "Execution command (${cmd}) failed, please check it and try again."
  fi
}

function _is_digit() {
  local input=${1}
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    return 0
  else
    return 1
  fi
}

function _version_ge() {
  test "$(echo "$@" | tr ' ' '\n' | sort -rV | head -n 1)" == "$1"
}

function _is_tls1_3_h2() {
  local check_url=$(echo $1 | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
  local check_num=$(echo QUIT | stdbuf -oL openssl s_client -connect "${check_url}:443" -tls1_3 -alpn h2 2>&1 | grep -Eoi '(TLSv1.3)|(^ALPN\s+protocol:\s+h2$)|(X25519)' | sort -u | wc -l)
  if [[ ${check_num} -eq 3 ]]; then
    return 0
  else
    return 1
  fi
}

function _is_network_reachable() {
  local url="$1"
  curl -s --head --connect-timeout 5 "$url" > /dev/null
  if [ $? -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

function _install() {
  local packages_name="$@"
  case "$(_os)" in
  centos)
    if _exists "dnf"; then
      dnf update -y
      dnf install -y dnf-plugins-core
      dnf update -y
      for package_name in ${packages_name}; do
        dnf install -y ${package_name}
      done
    else
      yum update -y
      yum install -y epel-release yum-utils
      yum update -y
      for package_name in ${packages_name}; do
        yum install -y ${package_name}
      done
    fi
    ;;
  ubuntu | debian)
    apt update -y
    for package_name in ${packages_name}; do
      apt install -y ${package_name}
    done
    ;;
  esac
}

function _systemctl() {
  local cmd="$1"
  local server_name="$2"
  case "${cmd}" in
  start)
    _info "正在启动 ${server_name} 服务"
    systemctl -q is-active ${server_name} || systemctl -q start ${server_name}
    systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} && _info "已启动 ${server_name} 服务" || _error "${server_name} 启动失败"
    ;;
  stop)
    _info "正在暂停 ${server_name} 服务"
    systemctl -q is-active ${server_name} && systemctl -q stop ${server_name}
    systemctl -q is-enabled ${server_name} && systemctl -q disable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} || _info "已暂停 ${server_name} 服务"
    ;;
  restart)
    _info "正在重启 ${server_name} 服务"
    systemctl -q is-active ${server_name} && systemctl -q restart ${server_name} || systemctl -q start ${server_name}
    systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} && _info "已重启 ${server_name} 服务" || _error "${server_name} 启动失败"
    ;;
  reload)
    _info "正在重载 ${server_name} 服务"
    systemctl -q is-active ${server_name} && systemctl -q reload ${server_name} || systemctl -q start ${server_name}
    systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
    sleep 2
    systemctl -q is-active ${server_name} && _info "已重载 ${server_name} 服务"
    ;;
  dr)
    _info "正在重载 systemd 配置文件"
    systemctl daemon-reload
    ;;
  esac
}

function check_xray_script_version() {
  local url="https://api.github.com/repos/zxcvos/Xray-script/contents"
  local local_size=$(stat -c %s "${CUR_DIR}/${CUR_FILE}")
  local remote_size=$(curl -fsSL "$url" | jq -r '.[] | select(.name == "xhttp.sh") | .size')
  if [[ ${local_size} -ne ${remote_size} ]]; then
    _info '发现有新脚本, 是否更新'
    _input_tips '退出脚本并显示更新命令 [Y/n] '
    read -r is_update_script
    case ${is_update_script} in
    N | n)
      _warn '请及时更新脚本'
      sleep 2
      ;;
    *)
      echo 'wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/xhttp.sh && bash ${HOME}/Xray-script.sh'
      exit 0
      ;;
    esac
  fi
}

function check_os() {
  [[ -z "$(_os)" ]] && _error "Not supported OS"
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 16 ]] && _error "Not supported OS, please change to Ubuntu 16+ and try again."
    ;;
  debian)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 9 ]] && _error "Not supported OS, please change to Debian 9+ and try again."
    ;;
  centos)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && _error "Not supported OS, please change to CentOS 7+ and try again."
    ;;
  *)
    _error "Not supported OS"
    ;;
  esac
}

function install_dependencies() {
  _info "正在下载相关依赖"
  _install "ca-certificates openssl curl wget jq tzdata qrencode"
  case "$(_os)" in
  centos)
    _install "crontabs util-linux iproute procps-ng"
    ;;
  debian | ubuntu)
    _install "cron bsdmainutils iproute2 procps"
    ;;
  esac
}

function install_docker() {
  if ! _exists "docker"; then
    wget --no-check-certificate -O /usr/local/xray-script/install-docker.sh https://get.docker.com
    if [[ "$(_os)" == "centos" && "$(_os_ver)" -eq 8 ]]; then
      sed -i 's|$sh_c "$pkg_manager install -y -q $pkgs"| $sh_c "$pkg_manager install -y -q $pkgs --allowerasing"|' /usr/local/xray-script/install-docker.sh
    fi
    sh /usr/local/xray-script/install-docker.sh --dry-run
    sh /usr/local/xray-script/install-docker.sh
  fi
}

function build_cloudflare_warp() {
  if [[ "${WARP}" -ne 1 && ! -d /usr/local/xray-script/warp ]]; then
    _info '正在构建 WARP Proxy 镜像'
    mkdir -p /usr/local/xray-script/warp
    mkdir -p ${HOME}/.warp
    _error_detect "wget --no-check-certificate -O /usr/local/xray-script/warp/Dockerfile https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudflare-warp/Dockerfile"
    _error_detect "wget --no-check-certificate -O /usr/local/xray-script/warp/startup.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/cloudflare-warp/startup.sh"
    cd /usr/local/xray-script/warp
    docker build -t xray-script-warp .
  fi
}

function get_random_number() {
  local custom_min=${1}
  local custom_max=${2}
  if ((custom_min > custom_max)); then
    _error "错误：最小值不能大于最大值。"
  fi
  local random_number=$(od -vAn -N2 -i /dev/urandom | awk '{print int($1 % ('$custom_max' - '$custom_min') + '$custom_min')}')
  echo $random_number
}

function get_random_port() {
  local random_number=$(get_random_number 1025 65536)
  echo $random_number
}

function validate_hex_input() {
  local input=$1
  if [[ $input =~ ^[0-9a-f]+$ ]] && ((${#input} % 2 == 0)) && ((${#input} <= 16)); then
    return 0
  else
    return 1
  fi
}

function check_xray_version_is_exists() {
  local xray_version_url="https://github.com/XTLS/Xray-core/releases/tag/v${1##*v}"
  local status_code=$(curl -o /dev/null -s -w '%{http_code}\n' "$xray_version_url")
  if [[ "$status_code" = "404" ]]; then
    _error "无法找到该版本: $1"
  fi
}

function enable_warp() {
  if [[ "${WARP}" -ne 1 ]]; then
    _info '正在开启 WARP Proxy 容器'
    docker run -v "${HOME}/.warp":/var/lib/cloudflare-warp:rw --restart=always --name=xray-script-warp xray-script-warp
    local outbounds='[{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"172.17.0.2","port":40001}]}}]'
    jq --argjson outbounds $outbounds '.outbounds += $outbounds' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq --argjson warp 1 '.warp = $warp' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
}

function disable_warp() {
  if [[ "${WARP}" -eq 1 ]]; then
    _info '正在关闭 WARP Proxy 容器'
    docker stop xray-script-warp
    docker rm xray-script-warp
    docker image rm xray-script-warp
    rm -rf /usr/local/xray-script/warp
    rm -rf ${HOME}/.warp
    jq '.outbounds |= map(select(.tag != "warp"))' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq '.routing.rules |= map(select(.outboundTag != "warp"))' /usr/local/etc/xray/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/etc/xray/config.json
    jq --argjson warp 0 '.warp = $warp' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
}

function enable_cron() {
  if ! [[ -f /usr/local/xray-script/update-dat.sh ]]; then
    wget --no-check-certificate -O /usr/local/xray-script/update-dat.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/update-dat.sh
    chmod a+x /usr/local/xray-script/update-dat.sh
    (
      crontab -l 2>/dev/null
      echo "30 6 * * * /usr/local/xray-script/update-dat.sh >/dev/null 2>&1"
    ) | awk '!x[$0]++' | crontab -
    /usr/local/xray-script/update-dat.sh
  fi
}

function disable_cron() {
  if [[ -f /usr/local/xray-script/update-dat.sh ]]; then
    crontab -l | grep -v "/usr/local/xray-script/update-dat.sh >/dev/null 2>&1" | crontab -
    rm -rf /usr/local/xray-script/update-dat.sh
  fi
}

# 添加规则的函数
function add_rule() {
  local CONFIG_FILE='/usr/local/etc/xray/config.json'
  local TMP_FILE='/usr/local/xray-script/tmp.json'
  local rule_tag=$1
  local domain_or_ip=$2
  local value=$(echo "$3" | tr ',' '\n' | jq -R . | jq -s .)
  local outboundTag=$4
  local position=$5   # 插入位置参数，可以是 "before" 或 "after"
  local target_tag=$6 # 目标 ruleTag，指定插入位置的 ruleTag

  # 读取原始的 rules 数组
  local current_rules=$(jq '.routing.rules' "$CONFIG_FILE")

  # 检查 ruleTag 是否已经存在
  local existing_rule=$(echo "$current_rules" | jq -r --arg ruleTag "$rule_tag" '.[] | select(.ruleTag == $ruleTag)')
  if [[ "$existing_rule" ]]; then
    # 如果 ruleTag 已存在，添加到 domain 或 ip 数组
    if [[ "$domain_or_ip" == "domain" ]]; then
      jq --arg ruleTag "$rule_tag" --argjson value "$value" '.routing.rules |= map(if .ruleTag == $ruleTag then .domain += $value | .domain |= unique else . end)' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
    elif [[ "$domain_or_ip" == "ip" ]]; then
      jq --arg ruleTag "$rule_tag" --argjson value "$value" '.routing.rules |= map(if .ruleTag == $ruleTag then .ip += $value | .ip |= unique else . end)' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
    fi
  else
    # 如果 ruleTag 不存在，创建新的规则
    new_rule="[{\"ruleTag\":\"$rule_tag\",\"$domain_or_ip\":$value,\"outboundTag\":\"$outboundTag\"}]"

    # 如果提供了 target_tag 和 position
    if [[ -n "$target_tag" ]]; then
      # 查找目标 ruleTag 是否存在
      local target_rule=$(echo "$current_rules" | jq -r --arg ruleTag "$target_tag" '.[] | select(.ruleTag == $ruleTag)')

      if [[ "$target_rule" ]]; then
        # 获取目标 ruleTag 的位置
        local target_index=$(echo "$current_rules" | jq -r --arg ruleTag "$target_tag" 'to_entries | map(select(.value.ruleTag == $ruleTag)) | .[0].key')
        if [[ "$position" == "before" ]]; then
          # 插入到 target_tag 前
          jq --argjson target_index $target_index --argjson new_rule "$new_rule" '.routing.rules |= .[:$target_index] + $new_rule + .[$target_index:]' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
        elif [[ "$position" == "after" ]]; then
          # 插入到 target_tag 后
          jq --argjson target_index $((target_index + 1)) --argjson new_rule "$new_rule" '.routing.rules |= .[:$target_index] + $new_rule + .[$target_index:]' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
        else
          # 如果 position 不是 "before" 或 "after"，则追加到末尾
          jq --argjson new_rule "$new_rule" '.routing.rules += $new_rule' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
        fi
      else
        # 如果 target_tag 不存在，则追加到末尾
        jq --argjson new_rule "$new_rule" '.routing.rules += $new_rule' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
      fi
    else
      if [[ -n "$position" && "$position" -ge 0 ]]; then
        # 如果提供了插入位置并且位置有效（大于等于0），插入到该位置
        jq --argjson position $position --argjson new_rule "$new_rule" '.routing.rules |= .[:$position] + $new_rule + .[$position:]' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
      else
        # 如果没有提供位置或位置无效，则追加到末尾
        jq --argjson new_rule "$new_rule" '.routing.rules += $new_rule' "$CONFIG_FILE" >"$TMP_FILE" && mv -f "$TMP_FILE" "$CONFIG_FILE"
      fi
    fi
  fi
}

function add_rule_warp_ip() {
  if [[ "${WARP}" -eq 1 ]]; then
    _warn '默认使用该功能的用户知道添加 rule 的相关规则'
    _info '支持逗号分隔的多个值'
    _input_tips '请输入分流到 WARP 的 ip: '
    read -r rule_warp_ip
    if [[ -n "$rule_warp_ip" ]]; then
      add_rule "warp-ip" "ip" "$rule_warp_ip" "warp" "before" "ad-domain"
    fi
  else
    _error '请开启 WARP Proxy 在进行分流操作'
  fi
}

function add_rule_warp_domain() {
  if [[ "${WARP}" -eq 1 ]]; then
    _warn '默认使用该功能的用户知道添加 rule 的相关规则'
    _info '支持逗号分隔的多个值'
    _input_tips '请输入分流到 WARP 的 domain: '
    read -r rule_warp_domain
    if [[ -n "$rule_warp_domain" ]]; then
      add_rule "warp-domain" "domain" "$rule_warp_domain" "warp" "before" "ad-domain"
    fi
  else
    _error '请开启 WARP Proxy 在进行分流操作'
  fi
}

function add_rule_block_ip() {
  _warn '默认使用该功能的用户知道添加 rule 的相关规则'
  _info '支持逗号分隔的多个值'
  _input_tips '请输入需要屏蔽 ip: '
  read -r rule_block_ip
  if [[ -n "$rule_block_ip" ]]; then
    add_rule "block-ip" "ip" "$rule_block_ip" "block" "after" "private-ip"
  fi
}

function add_rule_block_domain() {
  _warn '默认使用该功能的用户知道添加 rule 的相关规则'
  _info '支持逗号分隔的多个值'
  _input_tips '请输入需要屏蔽 domain: '
  read -r rule_domain_domain
  if [[ -n "$rule_domain_domain" ]]; then
    add_rule "block-domain" "domain" "$rule_domain_domain" "block" "after" "private-ip"
  fi
}

function add_rule_block_bt() {
  if [[ ${is_block_bt} =~ ^[Yy]$ ]]; then
    add_rule "bt" "protocol" "bittorrent" "block" 1
  fi
}

function add_rule_block_cn_ip() {
  if [[ ${is_block_cn_ip} =~ ^[Yy]$ ]]; then
    add_rule "cn-ip" "ip" "geoip:cn" "block" "after" "private-ip"
  fi
}

function add_rule_block_ads() {
  if [[ ${is_block_ads} =~ ^[Yy]$ ]]; then
    add_rule "ad-domain" "domain" "geosite:category-ads-all" "block"
  fi
}

function add_update_geodata() {
  if [[ ${is_update_geodata} =~ ^[Yy]$ ]]; then
    enable_cron
  fi
}

function read_block_bt() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_block_bt='Y'
  else
    _input_tips '是否开启 bittorrent 屏蔽 [y/N] '
    read -r is_block_bt
  fi
}

function read_block_cn_ip() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_block_cn_ip='Y'
  else
    _input_tips '是否开启国内 ip 屏蔽 [y/N] '
    read -r is_block_cn_ip
  fi
}

function read_block_ads() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_block_ads='Y'
  else
    _input_tips '是否开启广告屏蔽 [y/N] '
    read -r is_block_ads
  fi
}

function read_update_geodata() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    is_update_geodata='Y'
  else
    _input_tips '是否开启 geodata 自动更新功能 [y/N] '
    read -r is_update_geodata
  fi
}

function read_port() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info '端口范围是 1-65535 之间的数字, 如果不在范围内, 则使用默认生成'
  _input_tips '请输入自定义 port (默认自动生成): '
  read -r in_port
}

function read_uuid() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info '自定义输入的 uuid ，如果不是标准格式，将会使用 xray uuid -i "自定义字符串" 进行 UUIDv5 映射后填入配置'
  _input_tips '请输入自定义 UUID (默认自动生成): '
  read -r in_uuid
}

function read_seed() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _input_tips '请输入自定义 seed (默认自动生成): '
  read -r in_seed
}

function read_password() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _input_tips '请输入自定义 password (默认自动生成): '
  read -r in_password
}

function read_domain() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info "如果输入的自定义域名在 serverNames.json 存在对应的 key , 则代表使用该数据"
  until [[ ${is_domain} =~ ^[Yy]$ ]]; do
    _input_tips '请输入自定义域名 (默认自动生成): '
    read -r in_domain
    if [[ -z "${in_domain}" ]]; then
      break
    fi
    check_domain=$(echo ${in_domain} | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
    if ! _is_network_reachable "${check_domain}"; then
      _warn "\"${check_domain}\" 无法连接"
      continue
    fi
    if ! _is_tls1_3_h2 "${check_domain}"; then
      _warn "\"${check_domain}\" 不支持 TLSv1.3 或 h2 ，亦或者 Client Hello 不是 X25519"
      _info "如果你明确知道 \"${check_domain}\" 支持 TLSv1.3(h2), X25519, 可能是识别错误, 可选择直接跳过检查"
      _input_tips '是否明确确认支持 [y/N] '
      read -r is_support
      if [[ ${is_support} =~ ^[Yy]$ ]]; then
        break
      else
        continue
      fi
    fi
    is_domain='Y'
  done
  in_domain=${check_domain}
}

function read_short_ids() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _info 'shortId 内容为 0 到 f, 长度为 2 的倍数，长度上限为 16'
  _info '如果输入值为 0 到 8, 则自动生成对 0-16 长度的 shortId'
  _info '支持逗号分隔的多个值'
  _input_tips '请输入自定义 shortId (默认自动生成): '
  read -r in_short_id
}

function read_path() {
  if [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
    return
  fi
  _input_tips '请输入自定义 path (默认自动生成): '
  read -r in_path
}

function generate_port() {
  local input=${1}
  if ! _is_digit "${input}" || [[ ${input} -lt 1 || ${input} -gt 65535 ]]; then
    case ${XTLS_CONFIG} in
    mkcp) input=$(get_random_port) ;;
    *) input=443 ;;
    esac
  fi
  echo ${input}
}

function generate_uuid() {
  local input="${1}"
  local uuid=""
  if [[ -z "${input}" ]]; then
    uuid=$(xray uuid)
  elif printf "%s" "${input}" | grep -Eq '^[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}$'; then
    uuid="${input}"
  else
    uuid=$(xray uuid -i "${input}")
  fi
  echo "${uuid}"
}

function generate_password() {
  local seed="${1}"
  local length="${2}"
  if [[ -z "${length}" ]]; then
    length=16
  fi
  if [[ -z "${seed}" ]]; then
    seed=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*()_+-=' | head -c $length)
  fi
  echo "${seed}"
}

function generate_target() {
  local target=${1}
  if [[ -z "${target}" ]]; then
    local length=$(jq -r '. | length' /usr/local/xray-script/serverNames.json)
    local random_number=$(get_random_number 0 ${length})
    target=$(jq '. | keys | .[]' /usr/local/xray-script/serverNames.json | shuf | jq -s -r --argjson i ${random_number} '.[$i]')
  fi
  jq --arg target "${target}" '.target = $target' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  echo "${target}:443"
}

function generate_server_names() {
  local target=${1%:443}
  local local_target=$(jq --arg key  "${target}" '. | has($key)' /usr/local/xray-script/serverNames.json)
  if [[ "${local_target}" == "false" ]]; then
    local all_sns=$(xray tls ping ${target} | sed -n '/with SNI/,$p' | sed -En 's/\[(.*)\]/\1/p' | sed -En 's/Allowed domains:\s*//p' | jq -R -c 'split(" ")' | jq --arg sni "${target}" '. += [$sni]')
    local sns=$(echo ${all_sns} | jq 'map(select(test("^[^*]+$"; "g")))' | jq -c 'map(select(test("^((?!cloudflare|akamaized|edgekey|edgesuite|cloudfront|azureedge|msecnd|edgecastcdn|fastly|googleusercontent|kxcdn|maxcdn|stackpathdns|stackpathcdn|policy|privacy).)*$"; "ig")))' | jq 'unique')
  fi
  jq --arg key "${target}" --argjson serverNames "${sns}" '
  if . | has($key) then
    .
  else
    . += { ($key): $serverNames }
  end
' /usr/local/xray-script/serverNames.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/serverNames.json
  local server_names="$(jq --arg key "${target}" '.[$key]' /usr/local/xray-script/serverNames.json)"
  echo "${server_names}"
}

function generate_xray_x25519() {
  local xray_x25519=$(xray x25519)
  PRIVATE_KEY=$(echo ${xray_x25519} | awk '{print $3}')
  PUBLIC_KEY=$(echo ${xray_x25519} | awk '{print $6}')
  jq --arg privateKey "${PRIVATE_KEY}" '.privateKey = $privateKey' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  jq --arg publicKey "${PUBLIC_KEY}" '.publicKey = $publicKey' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
}

function generate_short_id() {
  local input=$1
  local trimmed_input=$(echo "$input" | xargs)
  if [[ $trimmed_input =~ ^[0-8]$ ]]; then
    echo "$(openssl rand -hex ${trimmed_input})"
  elif validate_hex_input "$trimmed_input"; then
    echo "$trimmed_input"
  else
    _error "'$trimmed_input' 不是有效的输入。"
  fi
}

function generate_short_ids() {
  IFS=',' read -r -a inputs <<<"$1"
  result=()
  if [[ -z "$inputs" ]]; then
    inputs=(4 8)
  fi
  for input in "${inputs[@]}"; do
    short_id=$(generate_short_id "$input")
    result+=("$short_id")
  done
  local short_ids=$(printf '%s\n' "${result[@]}" | jq -R . | jq -s .)
  echo "${short_ids}"
}

function generate_path() {
  local input="${1}"
  if [[ -z "${input}" ]]; then
    local package_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    local service_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    local method_name=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    echo "/${package_name}.${service_name}.${method_name}"
  else
    echo "/${input#/}"
  fi
}

function get_xray_config_data() {
  if [[ "${STATUS}" -ne 1 ]]; then
    read_block_bt
    read_block_cn_ip
    read_block_ads
    read_update_geodata
  fi
  read_port
  XRAY_PORT=$(generate_port "${in_port}")
  _info "port: ${XRAY_PORT}"
  jq --argjson port "${XRAY_PORT}" '.port = $port' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  read_uuid
  XRAY_UUID="$(generate_uuid "${in_uuid}")"
  _info "UUID: ${XRAY_UUID}"
  jq --arg uuid "${XRAY_UUID}" '.uuid = $uuid' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  case ${XTLS_CONFIG} in
  mkcp)
    read_seed
    KCP_SEED="$(generate_password "${in_seed}")"
    _info "seed: ${KCP_SEED}"
    jq --arg seed "${KCP_SEED}" '.kcp = $seed' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  trojan)
    read_password
    TROJAN_PASSWORD="$(generate_password "${in_password}")"
    _info "password: ${TROJAN_PASSWORD}"
    jq --arg trojan "${TROJAN_PASSWORD}" '.trojan = $trojan' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  fallback)
    _info "设置 fallback UUID"
    read_uuid
    FALLBACK_UUID="$(generate_uuid "${in_uuid}")"
    _info "fallback UUID: ${FALLBACK_UUID}"
    jq --arg uuid "${FALLBACK_UUID}" '.fallback = $uuid' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  esac
  case ${XTLS_CONFIG} in
  xhttp | trojan | fallback)
    read_path
    XHTTP_PATH="$(generate_path "${in_path}")"
    _info "path: ${XHTTP_PATH}"
    jq --arg path "${XHTTP_PATH}" '.path = $path' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  esac
  case ${XTLS_CONFIG} in
  xhttp | vision | trojan | fallback)
    read_domain
    TARGET_DOMAIN="$(generate_target "${in_domain}")"
    _info "target: ${TARGET_DOMAIN}"
    SERVER_NAMES="$(generate_server_names "${TARGET_DOMAIN}")"
    _info "server names: ${SERVER_NAMES}"
    generate_xray_x25519
    read_short_ids
    SHORT_IDS="$(generate_short_ids "${in_short_id}")"
    _info "shortIds: ${SHORT_IDS}"
    _info "private key: ${PRIVATE_KEY}"
    _info "public key: ${PUBLIC_KEY}"
    jq --argjson shortIds "${SHORT_IDS}" '.shortIds = $shortIds' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
    ;;
  esac
}

function get_xtls_download_url() {
  local url="https://api.github.com/repos/zxcvos/Xray-script/contents/XTLS"
  DOWNLOAD_URL=$(curl -fsSL "$url" | jq -r --arg target "${XTLS_CONFIG}" '.[] | select((.name | ascii_downcase | sub("\\.json$"; "")) == $target) | .download_url')
}

function set_mkcp_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg seed "${KCP_SEED}" '.inbounds[1].streamSettings.kcpSettings.seed = $seed' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_mkcp_data() {
  # -- protocol --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- uuid --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- remote_host --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- port --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- type --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- seed --
  local seed=$(jq -r '.inbounds[1].streamSettings.kcpSettings.seed' /usr/local/etc/xray/config.json)
  # -- tag --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- SHARE_LINK --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&seed=${seed}#${tag}"
}

function set_vision_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_vision_data() {
  # -- protocol --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- uuid --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- remote_host --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- port --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- type --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- flow --
  local flow=$(jq -r '.inbounds[1].settings.clients[0].flow' /usr/local/etc/xray/config.json)
  # -- security --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- serverName --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- public_key --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- shortId --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- tag --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- SHARE_LINK --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&flow=${flow}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&spx=%2F&fp=chrome#${tag}"
}

function set_xhttp_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[1].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_xhttp_data() {
  # -- protocol --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- uuid --
  local uuid=$(jq -r '.inbounds[1].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- remote_host --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- port --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- type --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- security --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- serverName --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- public_key --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- shortId --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- path --
  local path=$(jq -r '.inbounds[1].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- tag --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- SHARE_LINK --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
}

function set_trojan_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg password "${TROJAN_PASSWORD}" '.inbounds[1].settings.clients[0].password = $password' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[1].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_trojan_data() {
  # -- protocol --
  local protocol=$(jq -r '.inbounds[1].protocol' /usr/local/etc/xray/config.json)
  # -- password --
  local password=$(jq -r '.inbounds[1].settings.clients[0].password' /usr/local/etc/xray/config.json)
  # -- remote_host --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- port --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- type --
  local type=$(jq -r '.inbounds[1].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- security --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- serverName --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- public_key --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- shortId --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- path --
  local path=$(jq -r '.inbounds[1].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- tag --
  local tag=$(jq -r '.tag' /usr/local/xray-script/config.json)
  # -- SHARE_LINK --
  SHARE_LINK="${protocol}://${password}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
}

function set_fallback_data() {
  jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg target "${TARGET_DOMAIN}" '.inbounds[1].streamSettings.realitySettings.target = $target' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg uuid "${FALLBACK_UUID}" '.inbounds[2].settings.clients[0].id = $uuid' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  jq --arg path "${XHTTP_PATH}" '.inbounds[2].streamSettings.xhttpSettings.path = $path' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
}

function get_fallback_xhttp_data() {
  # -- protocol --
  local protocol=$(jq -r '.inbounds[2].protocol' /usr/local/etc/xray/config.json)
  # -- uuid --
  local uuid=$(jq -r '.inbounds[2].settings.clients[0].id' /usr/local/etc/xray/config.json)
  # -- remote_host --
  local remote_host=$(curl -fsSL ipv4.icanhazip.com)
  # -- port --
  local port=$(jq -r '.inbounds[1].port' /usr/local/etc/xray/config.json)
  # -- type --
  local type=$(jq -r '.inbounds[2].streamSettings.network' /usr/local/etc/xray/config.json)
  # -- security --
  local security=$(jq -r '.inbounds[1].streamSettings.security' /usr/local/etc/xray/config.json)
  # -- serverName --
  local server_names_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames | length' /usr/local/etc/xray/config.json)
  local server_names_random=$(get_random_number 0 ${server_names_length})
  local server_name=$(jq '.inbounds[1].streamSettings.realitySettings.serverNames | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${server_names_random} '.[$i]')
  # -- public_key --
  local public_key=$(jq -r '.publicKey' /usr/local/xray-script/config.json)
  # -- shortId --
  local short_ids_length=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
  local short_ids_random=$(get_random_number 0 ${short_ids_length})
  local short_id=$(jq '.inbounds[1].streamSettings.realitySettings.shortIds | .[]' /usr/local/etc/xray/config.json | shuf | jq -s -r --argjson i ${short_ids_random} '.[$i]')
  # -- path --
  local path=$(jq -r '.inbounds[2].streamSettings.xhttpSettings.path' /usr/local/etc/xray/config.json)
  # -- tag --
  local tag='fallback_xhttp'
  # -- SHARE_LINK --
  SHARE_LINK="${protocol}://${uuid}@${remote_host}:${port}?type=${type}&security=${security}&sni=${server_name}&pbk=${public_key}&sid=${short_id}&path=%2F${path#/}&spx=%2F&fp=chrome#${tag}"
}

function set_routing_and_outbounds() {
  if [[ "${STATUS}" -eq 1 ]]; then
    local routing=$(jq -r '.' /usr/local/xray-script/routing.json)
    jq --argjson routing "${routing}" '.routing = $routing' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  else
    jq --argjson status 1 '.status = $status' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  fi
  if [[ "${WARP}" -eq 1 ]]; then
    local outbounds='[{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"172.17.0.2","port":40001}]}}]'
    jq --argjson outbounds $outbounds '.outbounds += $outbounds' /usr/local/xray-script/xtls.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/xtls.json
  fi
}

function setup_xray_config_data() {
  get_xtls_download_url
  wget --no-check-certificate -O /usr/local/xray-script/xtls.json ${DOWNLOAD_URL}
  case ${XTLS_CONFIG} in
  mkcp) set_mkcp_data ;;
  vision) set_vision_data ;;
  xhttp) set_xhttp_data ;;
  trojan) set_trojan_data ;;
  fallback) set_fallback_data ;;
  esac
  set_routing_and_outbounds
  mv -f /usr/local/xray-script/xtls.json /usr/local/etc/xray/config.json
  add_rule_block_bt
  add_rule_block_cn_ip
  add_rule_block_ads
  add_update_geodata
  restart_xray
}

function setup_xray_config() {
  get_xray_config_data
  setup_xray_config_data
}

function install_xray() {
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root ${INSTALL_OPTION}'
}

function purge_xray() {
  disable_warp
  disable_cron
  rm -rf /usr/local/xray-script
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge'
}

function start_xray() {
  _systemctl start xray
}

function stop_xray() {
  _systemctl stop xray
}

function restart_xray() {
  _systemctl restart xray
}

function view_xray_config() {
  _info "根据已有配置文件, 随机获取 serverName 和 shortId 自动生成分享链接与二维码"
  XTLS_CONFIG=$(jq -r '.tag' /usr/local/xray-script/config.json)
  case ${XTLS_CONFIG} in
  mkcp) get_mkcp_data ;;
  vision) get_vision_data ;;
  xhttp) get_xhttp_data ;;
  trojan) get_trojan_data ;;
  fallback)
    get_vision_data
    _info "分享链接: ${SHARE_LINK}"
    echo ${SHARE_LINK} | qrencode -t ansiutf8
    get_fallback_xhttp_data
    ;;
  esac
  _info "分享链接: ${SHARE_LINK}"
  echo ${SHARE_LINK} | qrencode -t ansiutf8
}

function view_xray_traffic() {
  [[ -f /usr/local/xray-script/traffic.sh ]] || wget --no-check-certificate -O /usr/local/xray-script/traffic.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/traffic.sh
  bash /usr/local/xray-script/traffic.sh
}

function installation_processes() {
  _input_tips '请选择操作: '
  read -r choose
  case ${choose} in
  2) IS_AUTO='N' ;;
  *) IS_AUTO='Y' ;;
  esac
}

function xray_installation_processes() {
  _input_tips '请选择操作: '
  read -r choose
  case ${choose} in
  1) INSTALL_OPTION="--version $(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name')" ;;
  3)
    _input_tips '自选版本(e.g. v1.0.0): '
    read -r specified_version
    check_xray_version_is_exists "${specified_version}"
    SPECIFIED_VERSION="${specified_version}"
    INSTALL_OPTION="--version v${SPECIFIED_VERSION##*v}"
    ;;
  *) INSTALL_OPTION='' ;;
  esac
}

function config_processes() {
  _input_tips '请选择操作: '
  read -r choose
  case ${choose} in
  1)
    UPDATE_CONFIG='Y'
    if [[ "${STATUS}" -eq 1 ]]; then
      _input_tips '是否使用全新的配置 [y/N] '
      read -r is_new_config
      if [[ ${is_new_config} =~ ^[Yy]$ ]]; then
        STATUS=0
      fi
    fi
    xray_config_management
    ;;
  2)
    install_docker
    build_cloudflare_warp
    enable_warp
    ;;
  3) disable_warp ;;
  4) enable_cron ;;
  5) disable_cron ;;
  6) add_rule_warp_ip ;;
  7) add_rule_warp_domain ;;
  8) add_rule_block_ip ;;
  9) add_rule_block_domain ;;
  *) exit ;;
  esac
}

function xray_config_processes() {
  _input_tips '请选择操作: '
  read -r choose
  case ${choose} in
  1) XTLS_CONFIG='mkcp' ;;
  2) XTLS_CONFIG='vision' ;;
  4) XTLS_CONFIG='trojan' ;;
  5) XTLS_CONFIG='fallback' ;;
  *) XTLS_CONFIG='xhttp' ;;
  esac
  jq --arg tag "${XTLS_CONFIG}" '.tag = $tag' /usr/local/xray-script/config.json >/usr/local/xray-script/tmp.json && mv -f /usr/local/xray-script/tmp.json /usr/local/xray-script/config.json
  if [[ "${STATUS}" -eq 1 ]]; then
    rm -rf /usr/local/xray-script/routing.json
    jq -r '.routing' /usr/local/etc/xray/config.json >/usr/local/xray-script/routing.json
  fi
}

function main_processes() {
  _input_tips '请选择操作: '
  read -r choose

  if ! [[ -d /usr/local/xray-script ]]; then
    install_dependencies
    mkdir -p /usr/local/xray-script
    wget --no-check-certificate -q -O /usr/local/xray-script/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/refs/heads/main/XTLS/config.json
    wget --no-check-certificate -q -O /usr/local/xray-script/serverNames.json https://raw.githubusercontent.com/zxcvos/Xray-script/refs/heads/main/XTLS/serverNames.json
  fi
  STATUS=$(jq -r '.status' /usr/local/xray-script/config.json)
  WARP=$(jq -r '.warp' /usr/local/xray-script/config.json)

  case ${choose} in
  1)
    installation_management
    if ! [[ ${IS_AUTO} =~ ^[Yy]$ ]]; then
      xray_installation_management
      xray_config_management
    fi
    install_xray
    setup_xray_config
    view_xray_config
    ;;
  2)
    xray_installation_management
    install_xray
    ;;
  3)
    disable_cron
    disable_warp
    purge_xray
    ;;
  4) start_xray ;;
  5) stop_xray ;;
  6) restart_xray ;;
  7) view_xray_config ;;
  8) view_xray_traffic ;;
  9)
    config_management
    if [[ ${UPDATE_CONFIG} =~ ^[Yy]$ ]]; then
      setup_xray_config
      view_xray_config
    else
      restart_xray
    fi
    ;;
  *) exit ;;
  esac
}

function print_banner() {
  case $(($(get_random_number 0 100) % 2)) in
  0) echo "IBtbMDsxOzM1Ozk1bV8bWzA7MTszMTs5MW1fG1swbSAgIBtbMDsxOzMyOzkybV9fG1swbSAgG1swOzE7MzQ7OTRtXxtbMG0gICAgG1swOzE7MzE7OTFtXxtbMG0gICAbWzA7MTszMjs5Mm1fG1swOzE7MzY7OTZtX18bWzA7MTszNDs5NG1fXxtbMDsxOzM1Ozk1bV9fG1swbSAgIBtbMDsxOzMzOzkzbV8bWzA7MTszMjs5Mm1fXxtbMDsxOzM2Ozk2bV9fG1swOzE7MzQ7OTRtX18bWzBtICAgG1swOzE7MzE7OTFtXxtbMDsxOzMzOzkzbV9fG1swOzE7MzI7OTJtX18bWzBtICAKIBtbMDsxOzMxOzkxbVwbWzBtIBtbMDsxOzMzOzkzbVwbWzBtIBtbMDsxOzMyOzkybS8bWzBtIBtbMDsxOzM2Ozk2bS8bWzBtIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAbWzA7MTszMzs5M218G1swbSAbWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18XxtbMDsxOzM0Ozk0bV8bWzBtICAgG1swOzE7MzE7OTFtX18bWzA7MTszMzs5M218G1swbSAbWzA7MTszMjs5Mm18XxtbMDsxOzM2Ozk2bV8bWzBtICAgG1swOzE7MzU7OTVtX18bWzA7MTszMTs5MW18G1swbSAbWzA7MTszMzs5M218G1swbSAgG1swOzE7MzI7OTJtXxtbMDsxOzM2Ozk2bV8bWzBtIBtbMDsxOzM0Ozk0bVwbWzBtIAogIBtbMDsxOzMyOzkybVwbWzBtIBtbMDsxOzM2Ozk2bVYbWzBtIBtbMDsxOzM0Ozk0bS8bWzBtICAbWzA7MTszNTs5NW18G1swbSAbWzA7MTszMTs5MW18G1swOzE7MzM7OTNtX18bWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18G1swbSAgICAbWzA7MTszNTs5NW18G1swbSAbWzA7MTszMTs5MW18G1swbSAgICAgICAbWzA7MTszNDs5NG18G1swbSAbWzA7MTszNTs5NW18G1swbSAgICAbWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18XxtbMDsxOzM0Ozk0bV8pG1swbSAbWzA7MTszNTs5NW18G1swbQogICAbWzA7MTszNjs5Nm0+G1swbSAbWzA7MTszNDs5NG08G1swbSAgIBtbMDsxOzMxOzkxbXwbWzBtICAbWzA7MTszMjs5Mm1fXxtbMG0gIBtbMDsxOzM0Ozk0bXwbWzBtICAgIBtbMDsxOzMxOzkxbXwbWzBtIBtbMDsxOzMzOzkzbXwbWzBtICAgICAgIBtbMDsxOzM1Ozk1bXwbWzBtIBtbMDsxOzMxOzkxbXwbWzBtICAgIBtbMDsxOzM2Ozk2bXwbWzBtICAbWzA7MTszNDs5NG1fG1swOzE7MzU7OTVtX18bWzA7MTszMTs5MW0vG1swbSAKICAbWzA7MTszNDs5NG0vG1swbSAbWzA7MTszNTs5NW0uG1swbSAbWzA7MTszMTs5MW1cG1swbSAgG1swOzE7MzM7OTNtfBtbMG0gG1swOzE7MzI7OTJtfBtbMG0gIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAgIBtbMDsxOzMzOzkzbXwbWzBtIBtbMDsxOzMyOzkybXwbWzBtICAgICAgIBtbMDsxOzMxOzkxbXwbWzBtIBtbMDsxOzMzOzkzbXwbWzBtICAgIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAgICAKIBtbMDsxOzM0Ozk0bS8bWzA7MTszNTs5NW1fLxtbMG0gG1swOzE7MzE7OTFtXBtbMDsxOzMzOzkzbV9cG1swbSAbWzA7MTszMjs5Mm18G1swOzE7MzY7OTZtX3wbWzBtICAbWzA7MTszNTs5NW18XxtbMDsxOzMxOzkxbXwbWzBtICAgIBtbMDsxOzMyOzkybXwbWzA7MTszNjs5Nm1ffBtbMG0gICAgICAgG1swOzE7MzM7OTNtfBtbMDsxOzMyOzkybV98G1swbSAgICAbWzA7MTszNTs5NW18XxtbMDsxOzMxOzkxbXwbWzBtICAgICAKCkNvcHlyaWdodCAoQykgenhjdm9zIHwgaHR0cHM6Ly9naXRodWIuY29tL3p4Y3Zvcy9YcmF5LXNjcmlwdAoK" | base64 --decode ;;
  1) echo "IBtbMDsxOzM0Ozk0bV9fG1swbSAgIBtbMDsxOzM0Ozk0bV9fG1swbSAgG1swOzE7MzQ7OTRtXxtbMG0gICAgG1swOzE7MzQ7OTRtXxtbMG0gICAbWzA7MzRtX19fX19fXxtbMG0gICAbWzA7MzRtX19fG1swOzM3bV9fX18bWzBtICAgG1swOzM3bV9fX19fG1swbSAgCiAbWzA7MTszNDs5NG1cG1swbSAbWzA7MTszNDs5NG1cG1swbSAbWzA7MTszNDs5NG0vG1swbSAbWzA7MTszNDs5NG0vG1swbSAbWzA7MzRtfBtbMG0gG1swOzM0bXwbWzBtICAbWzA7MzRtfBtbMG0gG1swOzM0bXwbWzBtIBtbMDszNG18X18bWzBtICAgG1swOzM3bV9ffBtbMG0gG1swOzM3bXxfXxtbMG0gICAbWzA7MzdtX198G1swbSAbWzA7MzdtfBtbMG0gIBtbMDsxOzMwOzkwbV9fG1swbSAbWzA7MTszMDs5MG1cG1swbSAKICAbWzA7MzRtXBtbMG0gG1swOzM0bVYbWzBtIBtbMDszNG0vG1swbSAgG1swOzM0bXwbWzBtIBtbMDszNG18X198G1swbSAbWzA7MzdtfBtbMG0gICAgG1swOzM3bXwbWzBtIBtbMDszN218G1swbSAgICAgICAbWzA7MzdtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfF9fKRtbMG0gG1swOzE7MzA7OTBtfBtbMG0KICAgG1swOzM0bT4bWzBtIBtbMDszNG08G1swbSAgIBtbMDszN218G1swbSAgG1swOzM3bV9fG1swbSAgG1swOzM3bXwbWzBtICAgIBtbMDszN218G1swbSAbWzA7MzdtfBtbMG0gICAgICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gIBtbMDsxOzM0Ozk0bV9fXy8bWzBtIAogIBtbMDszN20vG1swbSAbWzA7MzdtLhtbMG0gG1swOzM3bVwbWzBtICAbWzA7MzdtfBtbMG0gG1swOzM3bXwbWzBtICAbWzA7MzdtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzQ7OTRtfBtbMG0gICAgG1swOzE7MzQ7OTRtfBtbMG0gG1swOzE7MzQ7OTRtfBtbMG0gICAgIAogG1swOzM3bS9fLxtbMG0gG1swOzM3bVxfXBtbMG0gG1swOzE7MzA7OTBtfF98G1swbSAgG1swOzE7MzA7OTBtfF98G1swbSAgICAbWzA7MTszMDs5MG18X3wbWzBtICAgICAgIBtbMDsxOzM0Ozk0bXxffBtbMG0gICAgG1swOzE7MzQ7OTRtfF8bWzA7MzRtfBtbMG0gICAgIAoKQ29weXJpZ2h0IChDKSB6eGN2b3MgfCBodHRwczovL2dpdGh1Yi5jb20venhjdm9zL1hyYXktc2NyaXB0Cgo=" | base64 --decode ;;
  esac
}

function print_script_status() {
  local xray_version="${RED}未安装${NC}"
  local script_xray_config="${RED}未配置${NC}"
  local warp_status="${RED}未启动${NC}"
  if _exists "xray"; then
    xray_version="${GREEN}v$(xray version | awk '$1=="Xray" {print $2}')${NC}"
    if _exists "jq" && [[ -d /usr/local/xray-script ]]; then
      case $(jq -r '.tag' /usr/local/xray-script/config.json) in
      fallback) script_xray_config='VLESS+Vision+REALITY+XHTTP' ;;
      *) script_xray_config=$(jq -r '.inbounds[1].tag' /usr/local/etc/xray/config.json) ;;
      esac
      script_xray_config="${GREEN}${script_xray_config}${NC}"
    fi
  fi
  if _exists "docker" && docker ps | grep -q xray-script-warp; then
    warp_status="${GREEN}已启动${NC}"
  fi
  echo -e "-------------------------------------------"
  echo -e "Xray       : ${xray_version}"
  echo -e "CONFIG     : ${script_xray_config}"
  echo -e "WARP Proxy : ${warp_status}"
  echo -e "-------------------------------------------"
  echo
}

function installation_management() {
  clear
  echo -e "----------------- 安装流程 ----------------"
  echo -e "${GREEN}1.${NC} 全自动(${GREEN}默认${NC})"
  echo -e "${GREEN}2.${NC} 自定义"
  echo -e "-------------------------------------------"
  echo -e "1.稳定版, XHTTP, 屏蔽 bt, cn, 广告, 开启 geodata 自动更新"
  echo -e "2.自选版本,自选配置"
  echo -e "-------------------------------------------"
  installation_processes
}

function xray_installation_management() {
  clear
  echo -e "----------------- 装载管理 ----------------"
  echo -e "${GREEN}1.${NC} 最新本"
  echo -e "${GREEN}2.${NC} 稳定本(${GREEN}默认${NC})"
  echo -e "${GREEN}3.${NC} 自选版"
  echo -e "-------------------------------------------"
  echo -e "1.最新版包含了 ${YELLOW}pre-release${NC} 版本"
  echo -e "2.稳定版为最新发布的${YELLOW}非 pre-release${NC} 版本"
  echo -e "3.自选版可能存在${RED}配置不兼容${NC}问题，请自行解决"
  echo -e "-------------------------------------------"
  xray_installation_processes
}

function config_management() {
  clear
  echo -e "----------------- 管理配置 ----------------"
  echo -e "${GREEN}1.${NC} 更新配置"
  echo -e "${GREEN}2.${NC} 开启 WARP Proxy"
  echo -e "${GREEN}3.${NC} 关闭 WARP Proxy"
  echo -e "${GREEN}4.${NC} 开启 geodata 自动更新"
  echo -e "${GREEN}5.${NC} 关闭 geodata 自动更新"
  echo -e "${GREEN}6.${NC} 添加 WARP ip 分流"
  echo -e "${GREEN}7.${NC} 添加 WARP domain 分流"
  echo -e "${GREEN}8.${NC} 添加屏蔽 ip 分流"
  echo -e "${GREEN}9.${NC} 添加屏蔽 domain 分流"
  echo -e "-------------------------------------------"
  echo -e "1.更新配置功能为整个配置的更新, 如果想要单独修改自行修改配置文件"
  echo -e "2-3.WARP Proxy 功能通过 Docker 部署, 开启时自动安装 Docker"
  echo -e "2-3.WARP Proxy 详情 https://github.com/haoel/haoel.github.io?tab=readme-ov-file#1043-docker-%E4%BB%A3%E7%90%86"
  echo -e "2-3.每次成功开启 WARP Proxy 都会重新申请 WARP 账号, ${RED}频繁操作可能导致 IP 被 Cloud­flare 拉黑${NC}"
  echo -e "4-5.geodata 由 https://github.com/Loyalsoldier/v2ray-rules-dat 提供"
  echo -e "6.(${RED}需要开启 WARP${NC})添加关于 ip 的 WARP 分流, 相关分流添加在 ruleTag 为 warp-ip 中"
  echo -e "7.(${RED}需要开启 WARP${NC})添加关于 domain 的 WARP 分流, 相关分流添加在 ruleTag 为 warp-domain 中"
  echo -e "8.添加关于 ip 的屏蔽分流, 相关分流添加在 ruleTag 为 block-ip 中"
  echo -e "9.添加关于 domain 的屏蔽分流, 相关分流添加在 ruleTag 为 block-domain 中"
  echo -e "-------------------------------------------"
  config_processes
}

function xray_config_management() {
  clear
  echo -e "----------------- 更新配置 ----------------"
  echo -e "${GREEN}1.${NC} VLESS+mKCP+seed"
  echo -e "${GREEN}2.${NC} VLESS+Vision+REALITY"
  echo -e "${GREEN}3.${NC} VLESS+XHTTP+REALITY(${GREEN}默认${NC})"
  echo -e "${GREEN}4.${NC} Trojan+XHTTP+REALITY"
  echo -e "${GREEN}5.${NC} VLESS+Vision+REALITY+VLESS+XHTTP+REALITY"
  echo -e "-------------------------------------------"
  echo -e "1.mKCP ${YELLOW}牺牲带宽${NC}来${GREEN}降低延迟${NC}。传输同样的内容，${RED}mKCP 一般比 TCP 消耗更多的流量${NC}"
  echo -e "2.XTLS(Vision) ${GREEN}解决 TLS in TLS 问题${NC}"
  echo -e "3.XHTTP ${GREEN}全场景通吃${NC}的时代正式到来(详情: https://github.com/XTLS/Xray-core/discussions/4113)"
  echo -e "3.1.XHTTP 默认有多路复用，${GREEN}延迟比 Vision 低${NC}但${YELLOW}多线程测速不如它${NC}"
  echo -e "3.2.${RED}此外 v2rayN&G 客户端有全局 mux.cool 设置，用 XHTTP 前记得关闭，不然连不上新版 Xray 服务端${NC}"
  echo -e "4.VLESS 替换为 Trojan"
  echo -e "5.利用 VLESS+Vision+REALITY 回落 VLESS+XHTTP ${GREEN}共用 443 端口${NC}"
  echo -e "-------------------------------------------"
  xray_config_processes
}

function main() {
  check_os
  check_xray_script_version
  clear
  print_banner
  print_script_status
  echo -e "--------------- Xray-script ---------------"
  echo -e " Version      : ${GREEN}v2024-12-31${NC}"
  echo -e " Description  : Xray 管理脚本"
  echo -e "----------------- 装载管理 ----------------"
  echo -e "${GREEN}1.${NC} 完整安装"
  echo -e "${GREEN}2.${NC} 仅安装/更新"
  echo -e "${GREEN}3.${NC} 卸载"
  echo -e "----------------- 操作管理 ----------------"
  echo -e "${GREEN}4.${NC} 启动"
  echo -e "${GREEN}5.${NC} 停止"
  echo -e "${GREEN}6.${NC} 重启"
  echo -e "----------------- 配置管理 ----------------"
  echo -e "${GREEN}7.${NC} 分享链接与二维码"
  echo -e "${GREEN}8.${NC} 信息统计"
  echo -e "${GREEN}9.${NC} 管理配置"
  echo -e "-------------------------------------------"
  echo -e "${RED}0.${NC} 退出"
  main_processes
}

[[ $EUID -ne 0 ]] && _error "请使用 root 权限运行该脚本"

main
