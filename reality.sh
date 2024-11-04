#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian9+, Ubuntu16+
# Description:      Script to Xray manage
#
# Copyright (C) 2023 zxcvos
#
# Xray-script: https://github.com/zxcvos/Xray-script
# Xray-core: https://github.com/XTLS/Xray-core
# REALITY: https://github.com/XTLS/REALITY
# Xray-examples: https://github.com/chika0801/Xray-examples
# Docker cloudflare-warp: https://github.com/e7h4n/cloudflare-warp
# Cloudflare Warp: https://github.com/haoel/haoel.github.io#943-docker-%E4%BB%A3%E7%90%86

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# color
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# config manage
readonly xray_config_manage='/usr/local/etc/xray-script/xray_config_manage.sh'

declare domain
declare domain_path
declare new_port

# status print
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

function _is_tlsv1_3_h2() {
  local check_url=$(echo $1 | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
  local check_num=$(echo QUIT | stdbuf -oL openssl s_client -connect "${check_url}:443" -tls1_3 -alpn h2 2>&1 | grep -Eoi '(TLSv1.3)|(^ALPN\s+protocol:\s+h2$)|(X25519)' | sort -u | wc -l)
  if [[ ${check_num} -eq 3 ]]; then
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

function _print_list() {
  local p_list=($@)
  for ((i = 1; i <= ${#p_list[@]}; i++)); do
    hint="${p_list[$i - 1]}"
    echo -e "${GREEN}${i}${NC}) ${hint}"
  done
}

function select_data() {
  local data_list=($(awk -v FS=',' '{for (i=1; i<=NF; i++) arr[i]=$i} END{for (i in arr) print arr[i]}' <<<"${1}"))
  local index_list=($(awk -v FS=',' '{for (i=1; i<=NF; i++) arr[i]=$i} END{for (i in arr) print arr[i]}' <<<"${2}"))
  local result_list=()
  if [[ ${#index_list[@]} -ne 0 ]]; then
    for i in "${index_list[@]}"; do
      if _is_digit "${i}" && [ ${i} -ge 1 ] && [ ${i} -le ${#data_list[@]} ]; then
        i=$((i - 1))
        result_list+=("${data_list[${i}]}")
      fi
    done
  else
    result_list=("${data_list[@]}")
  fi
  if [[ ${#result_list[@]} -eq 0 ]]; then
    result_list=("${data_list[@]}")
  fi
  echo "${result_list[@]}"
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
    _print_list "${dest_list[@]}"
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
        _warn "\"${domain}\" 不支持 TLSv1.3 或 h2 ，亦或者 Client Hello 不是 X25519"
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
      read -p "请选择要使用的 serverName ，用英文逗号分隔， 默认全选: " pick_num
      sns=$(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"$(echo ${sns} | jq -r -c '.[]')")" "${pick_num}" | jq -R -c 'split(" ")')
      _info "如果有更多的 serverNames 请在 /usr/local/etc/xray-script/config.json 中自行编辑"
    else
      pick_dest="${dest_list[${pick} - 1]}"
    fi
    read -r -p "是否使用 dest: \"${pick_dest}\" [y/n] " is_dest
    prompt="请选择你的 dest, 当前默认使用 \"${cur_dest}\", 自填选 0: "
    echo -e "-------------------------------------------"
  done
  _info "正在修改配置"
  [[ "${domain_path}" != "" ]] && pick_dest="${pick_dest}${domain_path}"
  if echo ${pick_dest} | grep -q '/$'; then
    pick_dest=$(echo ${pick_dest} | sed -En 's|/+$||p')
  fi
  [[ "${sns}" != "" ]] && jq --argjson sn "{\"${pick_dest}\": ${sns}}" '.xray.serverNames += $sn' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
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
      new_port=${cur_port}
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

function read_uuid() {
  _info '自定义输入的 uuid ，如果不是标准格式，将会使用 xray uuid -i "自定义字符串" 进行 UUIDv5 映射后填入配置'
  read -p "请输入自定义 UUID, 默认则自动生成: " in_uuid
}

# check os
function check_os() {
  [[ -z "$(_os)" ]] && _error "Not supported OS"
  case "$(_os)" in
  ubuntu)
    [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 16 ]]  && _error "Not supported OS, please change to Ubuntu 16+ and try again."
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
  _install "ca-certificates openssl curl wget jq tzdata"
  case "$(_os)" in
  centos)
    _install "crontabs util-linux iproute procps-ng"
    ;;
  debian | ubuntu)
    _install "cron bsdmainutils iproute2 procps"
    ;;
  esac
}

function install_update_xray() {
  _info "正在安装或更新 Xray"
  _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --beta'
  jq --arg ver "$(xray version | head -n 1 | cut -d \( -f 1 | grep -Eoi '[0-9.]*')" '.xray.version = $ver' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  wget -O /usr/local/etc/xray-script/update-dat.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/update-dat.sh
  chmod a+x /usr/local/etc/xray-script/update-dat.sh
  (crontab -l 2>/dev/null; echo "30 22 * * * /usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1") | awk '!x[$0]++' | crontab -
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
  "${xray_config_manage}" --path ${HOME}/config.json --download
  local xray_x25519=$(xray x25519)
  local xs_private_key=$(echo ${xray_x25519} | awk '{print $3}')
  local xs_public_key=$(echo ${xray_x25519} | awk '{print $6}')
  # Xray-script config.json
  jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
  # Xray-core config.json
  "${xray_config_manage}" --path ${HOME}/config.json -p ${new_port}
  "${xray_config_manage}" --path ${HOME}/config.json -u ${in_uuid}
  "${xray_config_manage}" --path ${HOME}/config.json -d "$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json | grep -Eoi '([a-zA-Z0-9](\-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}')"
  "${xray_config_manage}" --path ${HOME}/config.json -sn "$(jq -c -r '.xray | .serverNames[.dest] | .[]' /usr/local/etc/xray-script/config.json | tr '\n' ',')"
  "${xray_config_manage}" --path ${HOME}/config.json -x "${xs_private_key}"
  "${xray_config_manage}" --path ${HOME}/config.json -rsid
  mv -f ${HOME}/config.json /usr/local/etc/xray/config.json
  _systemctl "restart" "xray"
}

function tcp2raw() {
  local current_xray_version=$(xray version | awk '$1=="Xray" {print $2}')
  local tcp2raw_xray_version='24.9.30'
  if _version_ge "${current_xray_version}" "${tcp2raw_xray_version}"; then
    sed -i 's/"network": "tcp"/"network": "raw"/' /usr/local/etc/xray/config.json
    _systemctl "restart" "xray"
  fi
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
  [[ "${xs_spiderX}" == "${xs_spiderX##*/}" ]] && xs_spiderX='"/"' || xs_spiderX="\"/${xs_spiderX#*/}"
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
  read -p "是否生成分享链接[y/n]: " is_show_share_link
  echo
  if [[ ${is_show_share_link} =~ ^[Yy]$ ]]; then
    show_share_link
  else
    echo -e "------------------------------------------"
    echo -e "${RED}此脚本仅供交流学习使用，请勿使用此脚本行违法之事。${NC}"
    echo -e "${RED}网络非法外之地，行非法之事，必将接受法律制裁。${NC}"
    echo -e "------------------------------------------"
  fi
}

function show_share_link() {
  local sl=""
  # share lnk contents
  local sl_host=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
  local sl_inbound=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality")' /usr/local/etc/xray/config.json)
  local sl_port=$(echo ${sl_inbound} | jq -r '.port')
  local sl_protocol=$(echo ${sl_inbound} | jq -r '.protocol')
  local sl_ids=$(echo ${sl_inbound} | jq -r '.settings.clients[] | .id')
  local sl_public_key=$(jq -r '.xray.publicKey' /usr/local/etc/xray-script/config.json)
  local sl_serverNames=$(echo ${sl_inbound} | jq -r '.streamSettings.realitySettings.serverNames[]')
  local sl_shortIds=$(echo ${sl_inbound} | jq '.streamSettings.realitySettings.shortIds[]')
  # share link fields
  local sl_uuid=""
  local sl_security='security=reality'
  local sl_flow='flow=xtls-rprx-vision'
  local sl_fingerprint='fp=chrome'
  local sl_publicKey="pbk=${sl_public_key}"
  local sl_sni=""
  local sl_shortId=""
  local sl_spiderX='spx=%2F'
  local sl_descriptive_text='VLESS-XTLS-uTLS-REALITY'
  # select show
  _print_list "${sl_ids[@]}"
  read -p "请选择生成分享链接的 UUID ，用英文逗号分隔， 默认全选: " pick_num
  sl_id=($(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"${sl_ids[@]}")" "${pick_num}"))
  _print_list "${sl_serverNames[@]}"
  read -p "请选择生成分享链接的 serverName ，用英文逗号分隔， 默认全选: " pick_num
  sl_serverNames=($(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"${sl_serverNames[@]}")" "${pick_num}"))
  _print_list "${sl_shortIds[@]}"
  read -p "请选择生成分享链接的 shortId ，用英文逗号分隔， 默认全选: " pick_num
  sl_shortIds=($(select_data "$(awk 'BEGIN{ORS=","} {print}' <<<"${sl_shortIds[@]}")" "${pick_num}"))
  echo -e "--------------- share link ---------------"
  for sl_id in "${sl_ids[@]}"; do
    sl_uuid="${sl_id}"
    for sl_serverName in "${sl_serverNames[@]}"; do
      sl_sni="sni=${sl_serverName}"
      echo -e "---------- serverName ${sl_sni} ----------"
      for sl_shortId in "${sl_shortIds[@]}"; do
        [[ "${sl_shortId//\"/}" != "" ]] && sl_shortId="sid=${sl_shortId//\"/}" || sl_shortId=""
        sl="${sl_protocol}://${sl_uuid}@${sl_host}:${sl_port}?${sl_security}&${sl_flow}&${sl_fingerprint}&${sl_publicKey}&${sl_sni}&${sl_spiderX}&${sl_shortId}"
        echo "${sl%&}#${sl_descriptive_text}"
      done
      echo -e "------------------------------------------------"
    done
  done
  echo -e "------------------------------------------"
  echo -e "${RED}此脚本仅供交流学习使用，请勿使用此脚本行违法之事。${NC}"
  echo -e "${RED}网络非法外之地，行非法之事，必将接受法律制裁。${NC}"
  echo -e "------------------------------------------"
}

function menu() {
  check_os
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
  echo -e "${GREEN}108.${NC} 刷新已有的 shortIds"
  echo -e "${GREEN}109.${NC} 追加自定义的 shortIds"
  echo -e "${GREEN}110.${NC} 使用 WARP 分流，开启 OpenAI"
  echo -e "----------------- 其他选项 ----------------"
  echo -e "${GREEN}201.${NC} 更新至最新稳定版内核"
  echo -e "${GREEN}202.${NC} 卸载多余内核"
  echo -e "${GREEN}203.${NC} 修改 ssh 端口"
  echo -e "${GREEN}204.${NC} 网络连接优化"
  echo -e "-------------------------------------------"
  echo -e "${RED}0.${NC} 退出"
  read -rp "Choose: " idx
  ! _is_digit "${idx}" && _error "请输入正确的选项值"
  if [[ ! -d /usr/local/etc/xray-script && (${idx} -ne 0 && ${idx} -ne 1 && ${idx} -lt 201) ]]; then
    _error "未使用 Xray-script 进行安装"
  fi
  if [ -d /usr/local/etc/xray-script ] && ([ ${idx} -gt 102 ] || [ ${idx} -lt 111 ]); then
    wget -qO ${xray_config_manage} https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/xray_config_manage.sh
    chmod a+x ${xray_config_manage}
  fi
  case "${idx}" in
  1)
    if [[ ! -d /usr/local/etc/xray-script ]]; then
      mkdir -p /usr/local/etc/xray-script
      wget -O /usr/local/etc/xray-script/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/config.json
      wget -O ${xray_config_manage} https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/xray_config_manage.sh
      chmod a+x ${xray_config_manage}
      install_dependencies
      install_update_xray
      local xs_port=$(jq '.xray.port' /usr/local/etc/xray-script/config.json)
      read_port "xray config 配置默认使用: ${xs_port}" "${xs_port}"
      read_uuid
      select_dest
      config_xray
      tcp2raw
      show_config
    fi
    ;;
  2)
    _info "判断 Xray 是否用新版本"
    local current_xray_version="$(jq -r '.xray.version' /usr/local/etc/xray-script/config.json)"
    local latest_xray_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name ' | cut -d v -f 2)"
    if _version_ge "${latest_xray_version}" "${current_xray_version}"; then
      _info "检测到有新版可用"
      install_update_xray
      tcp2raw
    else
      _info "当前已是最新版本: ${current_xray_version}"
    fi
    ;;
  3)
    purge_xray
    [[ -f /usr/local/etc/xray-script/sysctl.conf.bak ]] && mv -f /usr/local/etc/xray-script/sysctl.conf.bak /etc/sysctl.conf && _info "已还原网络连接设置"
    rm -rf /usr/local/etc/xray-script
    if docker ps | grep -q cloudflare-warp; then
      _info '正在停止 cloudflare-warp'
      docker container stop cloudflare-warp
      docker container rm cloudflare-warp
    fi
    if docker images | grep -q e7h4n/cloudflare-warp; then
      _info '正在卸载 cloudflare-warp'
      docker image rm e7h4n/cloudflare-warp
    fi
    rm -rf ${HOME}/.warp
    _info 'Docker 请自行卸载'
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
    [[ -f /usr/local/etc/xray-script/traffic.sh ]] || wget -O /usr/local/etc/xray-script/traffic.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/traffic.sh
    bash /usr/local/etc/xray-script/traffic.sh
    ;;
  103)
    read_uuid
    _info "正在修改用户 id"
    "${xray_config_manage}" -u ${in_uuid}
    _info "已成功修改用户 id"
    _systemctl "restart" "xray"
    show_config
    ;;
  104)
    _info "正在修改 dest 与 serverNames"
    select_dest
    "${xray_config_manage}" -d "$(jq -r '.xray.dest' /usr/local/etc/xray-script/config.json | grep -Eoi '([a-zA-Z0-9](\-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}')"
    "${xray_config_manage}" -sn "$(jq -c -r '.xray | .serverNames[.dest] | .[]' /usr/local/etc/xray-script/config.json | tr '\n' ',')"
    _info "已成功修改 dest 与 serverNames"
    _systemctl "restart" "xray"
    show_config
    ;;
  105)
    _info "正在修改 x25519 key"
    local xray_x25519=$(xray x25519)
    local xs_private_key=$(echo ${xray_x25519} | awk '{print $3}')
    local xs_public_key=$(echo ${xray_x25519} | awk '{print $6}')
    # Xray-script config.json
    jq --arg privateKey "${xs_private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    jq --arg publicKey "${xs_public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    # Xray-core config.json
    "${xray_config_manage}" -x "${xs_private_key}"
    _info "已成功修改 x25519 key"
    _systemctl "restart" "xray"
    show_config
    ;;
  106)
    _info "shortId 值定义: 接受一个十六进制数值 ，长度为 2 的倍数，长度上限为 16"
    _info "shortId 列表默认为值为[\"\"]，若有此项，客户端 shortId 可为空"
    read -p "请输入自定义 shortIds 值，多个值以英文逗号进行分隔: " sid_str
    _info "正在修改 shortIds"
    "${xray_config_manage}" -sid "${sid_str}"
    _info "已成功修改 shortIds"
    _systemctl "restart" "xray"
    show_config
    ;;
  107)
    local xs_port=$(jq '.inbounds[] | select(.tag == "xray-script-xtls-reality") | .port' /usr/local/etc/xray/config.json)
    read_port "当前 xray 监听端口为: ${xs_port}" "${xs_port}"
    if [[ "${new_port}" && ${new_port} -ne ${xs_port} ]]; then
      "${xray_config_manage}" -p ${new_port}
      _info "当前 xray 监听端口已修改为: ${new_port}"
      _systemctl "restart" "xray"
      show_config
    fi
    ;;
  108)
    _info "正在修改 shortIds"
    "${xray_config_manage}" -rsid
    _info "已成功修改 shortIds"
    _systemctl "restart" "xray"
    show_config
    ;;
  109)
    until [ ${#sid_str} -gt 0 ] && [ ${#sid_str} -le 16 ] && [ $((${#sid_str} % 2)) -eq 0 ]; do
      _info "shortId 值定义: 接受一个十六进制数值 ，长度为 2 的倍数，长度上限为 16"
      read -p "请输入自定义 shortIds 值，不能为空，多个值以英文逗号进行分隔: " sid_str
    done
    _info "正在添加自定义 shortIds"
    "${xray_config_manage}" -asid "${sid_str}"
    _info "已成功添加自定义 shortIds"
    _systemctl "restart" "xray"
    show_config
    ;;
  110)
    if ! _exists "docker"; then
      read -r -p "脚本使用 Docker 进行 WARP 管理，是否安装 Docker [y/n] " is_docker
      if [[ ${is_docker} =~ ^[Yy]$ ]]; then
        curl -fsSL -o /usr/local/etc/xray-script/install-docker.sh https://get.docker.com
        if [[ "$(_os)" == "centos" && "$(_os_ver)" -eq 8 ]]; then
          sed -i 's|$sh_c "$pkg_manager install -y -q $pkgs"| $sh_c "$pkg_manager install -y -q $pkgs --allowerasing"|' /usr/local/etc/xray-script/install-docker.sh
        fi
        sh /usr/local/etc/xray-script/install-docker.sh --dry-run
        sh /usr/local/etc/xray-script/install-docker.sh
      else
        _warn "取消分流操作"
        exit 0
      fi
    fi
    if docker ps | grep -q cloudflare-warp; then
      _info "WARP 已开启，请勿重复设置"
    else
      _info "正在获取并启动 cloudflare-warp 镜像"
      docker run -v $HOME/.warp:/var/lib/cloudflare-warp:rw --restart=always --name=cloudflare-warp e7h4n/cloudflare-warp
      _info "正在配置 routing"
      local routing='{"type":"field","domain":["domain:ipinfo.io","domain:ip.sb","geosite:openai"],"outboundTag":"warp"}'
      _info "正在配置 outbounds"
      local outbound=$(echo '{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"172.17.0.2","port":40001}]}}' | jq -c --arg addr "$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cloudflare-warp)" '.settings.servers[].address = $addr')
      jq --argjson routing "${routing}" '.routing.rules += [$routing]' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
      jq --argjson outbound "${outbound}" '.outbounds += [$outbound]' /usr/local/etc/xray/config.json >/usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray/config.json
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
      [[ -f /usr/local/etc/xray-script/sysctl.conf.bak ]] || cp -af /etc/sysctl.conf /usr/local/etc/xray-script/sysctl.conf.bak
      wget -O /etc/sysctl.conf https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/sysctl.conf
      sysctl -p
    fi
    ;;
  0)
    exit 0
    ;;
  *)
    _error "请输入正确的选项值"
    ;;
  esac
}

[[ $EUID -ne 0 ]] && _error "This script must be run as root"

menu
