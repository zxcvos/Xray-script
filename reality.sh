#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian10+, Ubuntu16+
# Description:      Script to Xray manage
#
# Copyright (C) 2023 zxcvos
#
# Xray-script: https://github.com/zxcvos/Xray-script
# Xray-core: https://github.com/XTLS/Xray-core
# REALITY: https://github.com/XTLS/REALITY
# Xray-examples: https://github.com/chika0801/Xray-examples
#

readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

declare domain
declare domain_path
declare new_port

function _info() {
  printf "${GREEN}[信息] ${NC}"
  printf -- "%s" "$1"
  printf "\n"
}

function _warn() {
  printf "${YELLOW}[警告] ${NC}"
  printf -- "%s" "$1"
  printf "\n"
}

function _error() {
  printf "${RED}[错误] ${NC}"
  printf -- "%s" "$1"
  printf "\n"
  exit 1
}

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
  [ -f "/etc/debian_version" ] && source /etc/os-release && os="${ID}" && printf -- "%s" "${os}" && return
  [ -f "/etc/redhat-release" ] && os="centos" && printf -- "%s" "${os}" && return
}

function _os_full() {
  [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
  [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
  [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

function _os_ver() {
  local main_ver="$(echo $(_os_full) | grep -oE "[0-9.]+")"
  printf -- "%s" "${main_ver%%.*}"
}

function _error_detect() {
  local cmd="$1"
  _info "${cmd}"
  eval ${cmd}
  if [ $? -ne 0 ]; then
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

function _is_tlsv1_3_h2() {
  local check_url=$(echo $1 | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
  local check_num=$(wget -qO- "https://${check_url}" | stdbuf -oL openssl s_client -connect "${check_url}:443" -tls1_3 -alpn h2 2>&1 | grep -Eoi '(TLSv1.3)|(^ALPN\s+protocol:\s+h2$)' | sort -u | wc -l)
  if [[ ${check_num} -eq 2 ]]; then
    return 0
  else
    return 1
  fi
}

function _install_update() {
  local package_name="$@"
  case "$(_os)" in
  centos)
    if _exists "yum"; then
      yum update -y
      _error_detect "yum install -y epel-release yum-utils"
      yum update -y
      _error_detect "yum install -y ${package_name}"
    elif _exists "dnf"; then
      dnf update -y
      _error_detect "dnf install -y dnf-plugins-core"
      dnf update -y
      _error_detect "dnf install -y ${package_name}"
    fi
    ;;
  ubuntu | debian)
    apt update -y
    _error_detect "apt install -y ${package_name}"
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
    systemctl -q is-active ${server_name} && _info "已启动 ${server_name} 服务"
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
    systemctl -q is-active ${server_name} && _info "已重启 ${server_name} 服务"
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

function _print_list() {
  local p_list=($@)
  for ((i = 1; i <= ${#p_list[@]}; i++)); do
    hint="${p_list[$i - 1]}"
    echo -e "${GREEN}${i}${NC}) ${hint}"
  done
}

function select_dest() {
  local dest_list=($(jq '.xray.serverNames | keys_unsorted' /usr/local/etc/xray-script/config.json | grep -Eoi '".*"' | sed -En 's|"(.*)"|\1|p'))
  local cur_dest=$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json)
  local pick_dest=""
  local all_sns=""
  local sns=""
  local prompt="请选择你的 dest, 当前默认使用 \"${cur_dest}\", 自填选 0: "
  until [[ ${is_dest} =~ ^[Yy]$ ]]; do
    echo -e "---------------- dest 列表 -----------------"
    _print_list ${dest_list[@]}
    read -p "${prompt}" pick
    if [[ "${pick}" == "" && "${cur_dest}" != "" ]]; then
      pick_dest=${cur_dest}
      break
    fi
    if ! _is_digit "${pick}" || [[ "${pick}" -lt 0 || "${pick}" -gt ${#dest_list[@]} ]]; then
      prompt="输入错误, 请输入 0-${#dest_list[@]} 之间的数字: "
      continue
    fi
    if [[ "${pick}" == "0" ]]; then
      _warn "如果输入列表中已有域名将会导致 serverNames 被修改"
      _warn "使用自填域名时，请确保该域名在国内的连通性"
      read_domain
      _info "正在检查 \"${domain}\" 是否支持 TLSv1.3 与 h2"
      if ! _is_tlsv1_3_h2 "${domain}"; then
        _warn "\"${domain}\" 不支持 TLSv1.3 与 h2"
        continue
      fi
      _info "\"${domain}\" 支持 TLSv1.3 与 h2"
      _info "正在获取 Allowed domains"
      pick_dest=${domain}
      all_sns=$(xray tls ping ${pick_dest} | sed -n '/with SNI/,$p' | sed -En 's/\[(.*)\]/\1/p' | sed -En 's/Allowed domains:\s*//p' | jq -R -c 'split(" ")' | jq --arg sni "${pick_dest}" '. += [$sni]')
      sns=$(echo ${all_sns} | jq 'map(select(test("^[^*]+$"; "g")))' | jq -c 'map(select(test("^((?!cloudflare|akamaized|edgekey|edgesuite|cloudfront|azureedge|msecnd|edgecastcdn|fastly|googleusercontent|kxcdn|maxcdn|stackpathdns|stackpathcdn).)*$"; "ig")))')
      _info "过滤通配符前的 SNI"
      _print_list $(echo ${all_sns} | jq -r '.[]')
      _info "过滤通配符后的 SNI"
      _print_list $(echo ${sns} | jq -r '.[]')
      _info "如果有更多的 serverNames 请在 /usr/local/etc/xray-script/config.json 中自行编辑"
    else
      pick_dest="${dest_list[${pick} - 1]}"
    fi
    read -r -p "是否使用 dest: \"${pick_dest}\" [y/n] " is_dest
    prompt="请选择你的 dest, 当前默认使用 \"${cur_dest}\", 自填选 0: "
    echo -e "-------------------------------------------"
  done
  _info "正在修改配置"
  [ "${domain_path}" != "" ] && pick_dest="${pick_dest}${domain_path}"
  if echo ${pick_dest} | grep -q '/$'; then
    pick_dest=$(echo ${pick_dest} | sed -En 's|/+$||p')
  fi
  [ "${sns}" != "" ] && jq --argjson sn "{\"${pick_dest}\": ${sns}}" '.xray.serverNames += $sn' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  jq --arg dest "${pick_dest}" '.xray.dest = $dest' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
}

function read_domain() {
  until [[ ${is_domain} =~ ^[Yy]$ ]]; do
    read -p "请输入域名：" domain
    check_domain=$(echo ${domain} | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
    read -r -p "请确认域名: \"${check_domain}\" [y/n] " is_domain
  done
  domain_path=$(echo "${domain}" | sed -En "s|.*${check_domain}(/.*)?|\1|p")
  domain=${check_domain}
}

function read_port() {
  local prompt="${1}"
  local cur_port="${2}"
  until [[ ${is_port} =~ ^[Yy]$ ]]; do
    echo "${prompt}"
    read -p "请输入自定义的端口(1-65535), 默认不修改: " new_port
    if [[ "${new_port}" == "" || ${new_port} -eq ${cur_port} ]]; then
      _info "不修改，继续使用原端口: ${cur_port}"
      break
    fi
    if ! _is_digit "${new_port}" || [[ ${new_port} -lt 1 || ${new_port} -gt 65535 ]]; then
      prompt="输入错误, 端口范围是 1-65535 之间的数字"
      continue
    fi
    read -r -p "请确认端口: \"${new_port}\" [y/n] " is_port
    prompt="${1}"
  done
}

function check_os() {
  [ -z "$(_os)" ] && _error "Not supported OS"
  case "$(_os)" in
  ubuntu)
    [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 16 ] && _error "Not supported OS, please change to Ubuntu 16+ and try again."
    ;;
  debian)
    [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 10 ] && _error "Not supported OS, please change to Debian 10+ and try again."
    ;;
  centos)
    [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 7 ] && _error "Not supported OS, please change to CentOS 7+ and try again."
    ;;
  *)
    _error "Not supported OS"
    ;;
  esac
}

function install_dependencies() {
  _info "正在下载相关依赖"
  _install_update "ca-certificates openssl lsb-release curl wget jq tzdata"
  case "$(_os)" in
  centos)
    _install_update "crontabs util-linux iproute procps-ng"
    ;;
  debian | ubuntu)
    _install_update "cron bsdmainutils iproute2 procps"
    ;;
  esac
}

function install_update_xray() {
  _info "正在安装或更新 Xray"
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --beta'
  jq --arg ver "$(xray version | head -n 1 | cut -d \( -f 1 | grep -Eoi '[0-9.]*')" '.xray.version = $ver' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  wget -O /usr/local/etc/xray-script/update-dat.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/update-dat.sh
  chmod a+x /usr/local/etc/xray-script/update-dat.sh
  crontab -l | {
    cat
    echo "30 22 * * * /usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1"
  } | uniq | crontab -
  /usr/local/etc/xray-script/update-dat.sh
}

function purge_xray() {
  _info "正在卸载 Xray"
  crontab -l | grep -v "/usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1" | crontab -
  _systemctl "stop" "xray"
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
  rm -rf /etc/systemd/system/xray.service
  rm -rf /etc/systemd/system/xray@.service
  rm -rf /usr/local/bin/xray
  rm -rf /usr/local/etc/xray
  rm -rf /usr/local/share/xray
  rm -rf /var/log/xray
}

function service_xray() {
  _info "正在配置 xray.service"
  wget -O ${HOME}/xray.service https://raw.githubusercontent.com/zxcvos/Xray-script/main/service/xray.service
  mv -f ${HOME}/xray.service /etc/systemd/system/xray.service
  _systemctl dr
}

function config_xray() {
  _info "正在配置 xray config.json"
  wget -O ${HOME}/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/VLESS-XTLS-uTLS-REALITY/server.json
  local xray_x25519=$(xray x25519)
  local xs_private_key=$(echo ${xray_x25519} | awk '{print $3}')
  local xs_public_key=$(echo ${xray_x25519} | awk '{print $6}')
  local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' ${HOME}/config.json)
  local xs_dest=$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json)
  local xs_serverNames=$(jq -c '.xray | .serverNames[.dest]' /usr/local/etc/xray-script/config.json)
  # Xray-script config.json
  jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  # Xray-core config.json
  # id
  c_len=$(echo "${xs_inbound}" | jq '.settings.clients | length')
  for i in $(seq 1 ${c_len}); do
    xs_inbound=$(echo "${xs_inbound}" | jq --argjson i $((${i} - 1)) --arg uuid "$(cat /proc/sys/kernel/random/uuid)" '.settings.clients[$i].id = $uuid')
  done
  # dest
  xs_inbound=$(echo "${xs_inbound}" | jq --arg dest ${xs_dest%%/*}:443 '.streamSettings.realitySettings.dest = $dest')
  # serverNames
  xs_inbound=$(echo "${xs_inbound}" | jq --argjson sn ${xs_serverNames} '.streamSettings.realitySettings.serverNames = $sn')
  # privateKey
  xs_inbound=$(echo "${xs_inbound}" | jq --arg privateKey "${xs_private_key}" '.streamSettings.realitySettings.privateKey = $privateKey')
  # shortIds
  s_len=$(echo "${xs_inbound}" | jq '.streamSettings.realitySettings.shortIds | length')
  for i in $(seq 1 ${s_len}); do
    sId_len=$(echo "${xs_inbound}" | jq --argjson i $((${i} - 1)) '.streamSettings.realitySettings.shortIds[$i] | length')
    sId=$(head -c 20 /dev/urandom | md5sum | head -c ${sId_len})
    xs_inbound=$(echo "${xs_inbound}" | jq --argjson i $((${i} - 1)) --arg shortId "${sId}" '.streamSettings.realitySettings.shortIds[$i] = $shortId')
  done
  xs_inbound=$(echo "${xs_inbound}" | jq -c '.')
  local xs_inbounds=$(jq -c --argjson inbound ${xs_inbound} '.inbounds | map(if .tag == "xray-script-xtls-reality" then . = $inbound else . end)' ${HOME}/config.json)
  jq --argjson inbounds ${xs_inbounds} '.inbounds = $inbounds' ${HOME}/config.json >${HOME}/new.json && mv -f ${HOME}/new.json ${HOME}/config.json
  mv -f ${HOME}/config.json /usr/local/etc/xray/config.json
  _systemctl "restart" "xray"
}

function show_config() {
  local IPv4=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
  local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
  local xs_port=$(echo ${xs_inbound} | jq '.port')
  local xs_protocol=$(echo ${xs_inbound} | jq '.protocol')
  local xs_ids=$(echo ${xs_inbound} | jq '.settings.clients[] | .id' | tr '\n' ',')
  local xs_public_key=$(jq '.xray.publicKey' /usr/local/etc/xray-script/config.json)
  local xs_serverNames=$(echo ${xs_inbound} | jq '.streamSettings.realitySettings.serverNames[]' | tr '\n' ',')
  local xs_shortIds=$(echo ${xs_inbound} | jq '.streamSettings.realitySettings.shortIds[]' | tr '\n' ',')
  local xs_spiderX=$(jq '.xray.dest' /usr/local/etc/xray-script/config.json)
  [ "${xs_spiderX}" == "${xs_spiderX##*/}" ] && xs_spiderX='"/"' || xs_spiderX="\"/${xs_spiderX#*/}"
  echo -e "-------------- client config --------------"
  echo -e "address     : \"${IPv4}\""
  echo -e "port        : ${xs_port}"
  echo -e "protocol    : ${xs_protocol}"
  echo -e "id          : ${xs_ids%,}"
  echo -e "flow        : \"xtls-rprx-vision\""
  echo -e "network     : \"tcp\""
  echo -e "TLS         : \"reality\""
  echo -e "SNI         : ${xs_serverNames%,}"
  echo -e "Fingerprint : \"chrome\""
  echo -e "PublicKey   : ${xs_public_key}"
  echo -e "ShortId     : ${xs_shortIds%,}"
  echo -e "SpiderX     : ${xs_spiderX}"
  echo -e "------------------------------------------"
  echo -e "${RED}此脚本仅供交流学习使用，请勿使用此脚本行违法之事。${NC}"
  echo -e "${RED}网络非法外之地，行非法之事，必将接受法律制裁。${NC}"
  echo -e "------------------------------------------"
}

function menu() {
  clear
  echo -e "--------------- Xray-script ---------------"
  echo -e " Version      : ${GREEN}v2023-03-15${NC}(${RED}beta${NC})"
  echo -e " Description  : Xray 管理脚本"
  echo -e "----------------- 装载管理 ----------------"
  echo -e "${GREEN}1.${NC} 安装"
  echo -e "${GREEN}2.${NC} 更新"
  echo -e "${GREEN}3.${NC} 卸载"
  echo -e "----------------- 操作管理 ----------------"
  echo -e "${GREEN}4.${NC} 启动"
  echo -e "${GREEN}5.${NC} 停止"
  echo -e "${GREEN}6.${NC} 重启"
  echo -e "----------------- 配置管理 ----------------"
  echo -e "${GREEN}101.${NC} 查看配置"
  echo -e "${GREEN}102.${NC} 信息统计"
  echo -e "${GREEN}103.${NC} 修改 id"
  echo -e "${GREEN}104.${NC} 修改 dest"
  echo -e "${GREEN}105.${NC} 修改 x25519 key"
  echo -e "${GREEN}106.${NC} 修改 shortIds"
  echo -e "${GREEN}107.${NC} 修改 xray 监听端口"
  echo -e "----------------- 其他选项 ----------------"
  echo -e "${GREEN}201.${NC} 更新至最新稳定版内核"
  echo -e "${GREEN}202.${NC} 卸载多余内核"
  echo -e "${GREEN}203.${NC} 修改 ssh 端口"
  echo -e "${GREEN}204.${NC} 网络连接优化"
  echo -e "-------------------------------------------"
  echo -e "${RED}0.${NC} 退出"
  read -rp "Choose: " idx
  if [[ ! -d /usr/local/etc/xray-script && (${idx} -ne 0 && ${idx} -ne 1 && ${idx} -lt 201) ]]; then
    _error "未使用 Xray-script 进行安装"
  fi
  case "${idx}" in
  1)
    if [ ! -d /usr/local/etc/xray-script ]; then
      mkdir -p /usr/local/etc/xray-script
      wget -O /usr/local/etc/xray-script/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/config.json
      local xs_port=$(jq '.xray.port' /usr/local/etc/xray-script/config.json)
      read_port "xray config 配置默认使用: ${xs_port}" "${xs_port}"
      select_dest
      install_dependencies
      install_update_xray
      config_xray
      show_config
    fi
    ;;
  2)
    _info "判断 Xray 是否用新版本"
    local current_xray_version="$(jq -r '.xray.version' /usr/local/etc/xray-script/config.json)"
    local latest_xray_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name ' | cut -d v -f 2)"
    if [ "${latest_xray_version}" != "${current_xray_version}" ] && _version_ge "${latest_xray_version}" "${current_xray_version}"; then
      _info "检测到有新版可用"
      install_update_xray
    else
      _info "当前已是最新版本: ${current_xray_version}"
    fi
    ;;
  3)
    purge_xray
    [ -f /usr/local/etc/xray-script/sysctl.conf.bak ] && mv -f /usr/local/etc/xray-script/sysctl.conf.bak /etc/sysctl.conf && _info "已还原网络连接设置"
    rm -rf /usr/local/etc/xray-script
    _info "已经完成卸载"
    ;;
  4)
    _systemctl "start" "xray"
    ;;
  5)
    _systemctl "stop" "xray"
    ;;
  6)
    _systemctl "restart" "xray"
    ;;
  101)
    show_config
    ;;
  102)
    [ -f /usr/local/etc/xray-script/traffic.sh ] || wget -O /usr/local/etc/xray-script/traffic.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/traffic.sh
    bash /usr/local/etc/xray-script/traffic.sh
    ;;
  103)
    _info "正在修改用户 id"
    local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
    # Xray-core config.json
    # id
    c_len=$(echo "${xs_inbound}" | jq '.settings.clients | length')
    for i in $(seq 1 ${c_len}); do
      xs_inbound=$(echo "${xs_inbound}" | jq --argjson i $((${i} - 1)) --arg uuid "$(cat /proc/sys/kernel/random/uuid)" '.settings.clients[$i].id = $uuid')
    done
    xs_inbound=$(echo "${xs_inbound}" | jq -c '.')
    local xs_inbounds=$(jq -c --argjson inbound ${xs_inbound} '.inbounds | map(if .tag == "xray-script-xtls-reality" then . = $inbound else . end)' /usr/local/etc/xray/config.json)
    jq --argjson inbounds ${xs_inbounds} '.inbounds = $inbounds' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
    _info "已成功修改用户 id"
    _systemctl "restart" "xray"
    show_config
    ;;
  104)
    _info "正在修改 dest 与 serverNames"
    select_dest
    local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
    local xs_dest=$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json)
    local xs_serverNames=$(jq -c '.xray | .serverNames[.dest]' /usr/local/etc/xray-script/config.json)
    # Xray-core config.json
    # dest
    xs_inbound=$(echo "${xs_inbound}" | jq --arg dest ${xs_dest%%/*}:443 '.streamSettings.realitySettings.dest = $dest')
    # serverNames
    xs_inbound=$(echo "${xs_inbound}" | jq --argjson sn ${xs_serverNames} '.streamSettings.realitySettings.serverNames = $sn')
    xs_inbound=$(echo "${xs_inbound}" | jq -c '.')
    local xs_inbounds=$(jq -c --argjson inbound ${xs_inbound} '.inbounds | map(if .tag == "xray-script-xtls-reality" then . = $inbound else . end)' /usr/local/etc/xray/config.json)
    jq --argjson inbounds ${xs_inbounds} '.inbounds = $inbounds' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
    _info "已成功修改 dest 与 serverNames"
    _systemctl "restart" "xray"
    show_config
    ;;
  105)
    _info "正在修改 x25519 key"
    local xray_x25519=$(xray x25519)
    local xs_private_key=$(echo ${xray_x25519} | awk '{print $3}')
    local xs_public_key=$(echo ${xray_x25519} | awk '{print $6}')
    local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
    # Xray-script config.json
    jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    # Xray-core config.json
    # privateKey
    xs_inbound=$(echo "${xs_inbound}" | jq --arg privateKey "${xs_private_key}" '.streamSettings.realitySettings.privateKey = $privateKey')
    xs_inbound=$(echo "${xs_inbound}" | jq -c '.')
    local xs_inbounds=$(jq -c --argjson inbound ${xs_inbound} '.inbounds | map(if .tag == "xray-script-xtls-reality" then . = $inbound else . end)' /usr/local/etc/xray/config.json)
    jq --argjson inbounds ${xs_inbounds} '.inbounds = $inbounds' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
    _info "已成功修改 x25519 key"
    _systemctl "restart" "xray"
    show_config
    ;;
  106)
    _info "正在修改 shortIds"
    local xs_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
    # Xray-core config.json
    # shortIds
    local s_len=$(echo "${xs_inbound}" | jq '.streamSettings.realitySettings.shortIds | length')
    for i in $(seq 1 ${s_len}); do
      sId_len=$(echo "${xs_inbound}" | jq --argjson i $((${i} - 1)) '.streamSettings.realitySettings.shortIds[$i] | length')
      sId=$(head -c 20 /dev/urandom | md5sum | head -c ${sId_len})
      xs_inbound=$(echo "${xs_inbound}" | jq --argjson i $((${i} - 1)) --arg shortId "${sId}" '.streamSettings.realitySettings.shortIds[$i] = $shortId')
    done
    xs_inbound=$(echo "${xs_inbound}" | jq -c '.')
    local xs_inbounds=$(jq -c --argjson inbound ${xs_inbound} '.inbounds | map(if .tag == "xray-script-xtls-reality" then . = $inbound else . end)' /usr/local/etc/xray/config.json)
    jq --argjson inbounds ${xs_inbounds} '.inbounds = $inbounds' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
    _info "已成功修改 shortIds"
    _systemctl "restart" "xray"
    show_config
    ;;
  107)
    local xs_port=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .port' /usr/local/etc/xray/config.json)
    read_port "当前 xray 监听端口为: ${xs_port}" "${xs_port}"
    if [[ "${new_port}" && ${new_port} -ne ${xs_port} ]]; then
      sed -i "s/${xs_port}/${new_port}/" /usr/local/etc/xray/config.json
      _info "当前 xray 监听端口已修改为: ${new_port}"
      _systemctl "restart" "xray"
      show_config
    fi
    ;;
  201)
    bash <(wget -qO- https://raw.githubusercontent.com/zxcvos/system-automation-scripts/main/update-kernel.sh)
    ;;
  202)
    bash <(wget -qO- https://raw.githubusercontent.com/zxcvos/system-automation-scripts/main/remove-kernel.sh)
    ;;
  203)
    local ssh_port=$(sed -En "s/^[#pP].*ort\s*([0-9]*)$/\1/p" /etc/ssh/sshd_config)
    read_port "当前 ssh 连接端口为: ${ssh_port}" "${ssh_port}"
    if [[ "${new_port}" && ${new_port} -ne ${ssh_port} ]]; then
      sed -i "s/^[#pP].*ort\s*[0-9]*$/Port ${new_port}/" /etc/ssh/sshd_config
      systemctl restart sshd
      _info "当前 ssh 连接端口已修改为: ${new_port}"
    fi
    ;;
  204)
    read -r -p "是否选择网络连接优化 [y/n] " is_opt
    if [[ ${is_opt} =~ ^[Yy]$ ]]; then
      [ -f /usr/local/etc/xray-script/sysctl.conf.bak ] || cp -af /etc/sysctl.conf /usr/local/etc/xray-script/sysctl.conf.bak
      wget -O /etc/sysctl.conf https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/sysctl.conf
      sysctl -p
    fi
    ;;
  0)
    exit 0
    ;;
  esac
}

[[ $EUID -ne 0 ]] && _error "This script must be run as root"

menu
