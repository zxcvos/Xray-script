#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: share.sh
# 功能描述: 生成 Xray 服务的客户端配置信息和分享链接 (如 VLESS, Trojan)。
#           根据服务端配置 (Xray 和 Script) 自动提取必要参数，
#           构造多种类型的分享链接 (包括 Reality, XHTTP, mKCP, TLS 等)，
#           并可选地生成二维码。支持多语言。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, jq, curl, qrencode, sed
# 配置:
#   - ${XRAY_CONFIG_PATH}: Xray 服务端配置文件 (用于读取协议、UUID、密码等)
#   - ${SCRIPT_CONFIG_PATH}: 脚本自身配置文件 (用于读取端口、域名、路径等)
#   - ${I18N_DIR}/${lang}.json: 国际化文件 (用于显示多语言提示)
# =============================================================================

# set -Eeuxo pipefail

# --- 环境与常量设置 ---
# 将常用路径添加到 PATH 环境变量，确保脚本能在不同环境中找到所需命令
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

# 定义颜色代码，用于在终端输出带颜色的信息
readonly GREEN='\033[32m'  # 绿色
readonly YELLOW='\033[33m' # 黄色
readonly RED='\033[31m'    # 红色
readonly NC='\033[0m'      # 无颜色（重置）

# 获取当前脚本的目录、文件名（不含扩展名）和项目根目录的绝对路径
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)" # 当前脚本所在目录
readonly CUR_FILE="$(basename "$0" | sed 's/\..*//')"         # 当前脚本文件名 (不含扩展名)
readonly PROJECT_ROOT="$(cd -P -- "${CUR_DIR}/.." && pwd -P)" # 项目根目录

# 定义配置文件和相关目录的路径
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"              # 主配置文件目录
readonly I18N_DIR="${PROJECT_ROOT}/i18n"                       # 国际化文件目录
readonly CONFIG_DIR="${PROJECT_ROOT}/config"                   # 脚本配置文件目录
readonly GENERATE_PATH="${CUR_DIR}/generate.sh"                # 项目中的 generate.sh 脚本路径
readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"    # Xray 服务端配置文件路径
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json" # 脚本主要配置文件路径

# --- 全局变量声明 ---
# 声明用于存储语言参数、国际化数据和配置信息的全局变量
declare LANG_PARAM=''       # (未在脚本中实际使用，可能是预留)
declare I18N_DATA=''        # 存储从 i18n JSON 文件中读取的全部数据
declare -A CLIENT_CONFIG    # 关联数组，存储当前处理的客户端配置片段
declare XRAY_CONFIG         # 存储 Xray 配置文件的全部 JSON 内容
declare SCRIPT_CONFIG       # 存储脚本配置文件的全部 JSON 内容
declare XHTTP_EXTRA         # 存储额外的 XHTTP 下行设置 JSON 字符串
declare XHTTP_EXTRA_ENCODED # 存储经过 URL 编码的 XHTTP_EXTRA 字符串
declare SHARE_LINK          # 存储最终生成的分享链接
# 声明一系列变量用于存储分享链接的各个组成部分，便于拼接不同类型的链接
declare SHARE_LINK_COMPONENT_VLESS   # VLESS 协议的基础部分
declare SHARE_LINK_COMPONENT_TROJAN  # Trojan 协议的基础部分
declare SHARE_LINK_COMPONENT_MKCP    # mKCP 网络传输的参数部分
declare SHARE_LINK_COMPONENT_TLS     # TLS 安全传输的参数部分
declare SHARE_LINK_COMPONENT_REALITY # Reality 安全传输的参数部分
declare SHARE_LINK_COMPONENT_XHTTP   # XHTTP 网络传输的参数部分
declare SHARE_LINK_COMPONENT_FLOW    # Flow 控制参数部分
declare SHARE_LINK_COMPONENT_EXTRA   # 额外参数 (如 downloadSettings) 部分

# =============================================================================
# 函数名称: load_i18n
# 功能描述: 加载国际化 (i18n) 数据。
#           1. 从 config.json 读取语言设置。
#           2. 如果设置为 "auto"，则尝试从系统环境变量 $LANG 推断语言。
#           3. 根据确定的语言，加载对应的 JSON i18n 文件。
#           4. 将文件内容读入全局变量 I18N_DATA。
# 参数: 无
# 返回值: 无 (直接修改全局变量 I18N_DATA)
# 退出码: 如果 i18n 文件不存在，则输出错误信息并退出脚本 (exit 1)
# =============================================================================
function load_i18n() {
    # 从脚本配置文件中读取语言设置
    local lang="$(jq -r '.language' "${SCRIPT_CONFIG_PATH}")"

    # 如果语言设置为 "auto"，则使用系统环境变量 LANG 的第一部分作为语言代码
    if [[ "$lang" == "auto" ]]; then
        lang=$(echo "$LANG" | cut -d'_' -f1)
    fi

    # 构造 i18n 文件的完整路径
    local i18n_file="${I18N_DIR}/${lang}.json"

    # 检查 i18n 文件是否存在
    if [[ ! -f "${i18n_file}" ]]; then
        # 文件不存在时，根据语言输出不同的错误信息
        if [[ "$lang" == "zh" ]]; then
            echo -e "${RED}[错误]${NC} 文件不存在: ${i18n_file}" >&2
        else
            echo -e "${RED}[Error]${NC} File Not Found: ${i18n_file}" >&2
        fi
        # 退出脚本，错误码为 1
        exit 1
    fi

    # 读取 i18n 文件的全部内容到全局变量 I18N_DATA
    I18N_DATA="$(jq '.' "${i18n_file}")"
}

# =============================================================================
# 函数名称: urlencode
# 功能描述: 对输入字符串进行 URL 编码。
#           将非字母数字、非 .~_- 的字符转换为 %XX 格式。
# 参数:
#   $1 (可选): 待编码的字符串。如果不提供，则从标准输入读取。
# 返回值: URL 编码后的字符串 (echo 输出)
# =============================================================================
function urlencode() {
    local input # 声明局部变量存储输入

    # 如果没有传入参数，则从标准输入读取
    if [[ $# -eq 0 ]]; then
        input="$(cat)"
    else
        input="$1" # 否则使用第一个参数作为输入
    fi

    local encoded="" # 声明局部变量存储编码后的结果
    local i c hex    # 声明循环变量和临时变量

    # 遍历输入字符串的每个字符
    for ((i = 0; i < ${#input}; i++)); do
        c="${input:$i:1}" # 获取当前字符

        # 检查字符是否为不需要编码的安全字符
        case $c in
        [a-zA-Z0-9.~_-])
            # 如果是安全字符，则直接追加到结果中
            encoded+="$c"
            ;;
        *)
            # 如果不是安全字符，则进行编码
            # printf -v hex 将字符的 ASCII 码转换为两位十六进制数
            printf -v hex "%02X" "'$c"
            # 将 % 和十六进制数追加到结果中
            encoded+="%$hex"
            ;;
        esac
    done

    # 输出编码后的字符串
    echo "$encoded"
}

# =============================================================================
# 函数名称: cache_json_data
# 功能描述: 将 Xray 和脚本的配置文件内容读取到全局变量中进行缓存，
#           避免重复读取文件，提高脚本执行效率。
# 参数: 无
# 返回值: 无 (直接修改全局变量 XRAY_CONFIG 和 SCRIPT_CONFIG)
# =============================================================================
function cache_json_data() {
    # 读取 Xray 配置文件的完整 JSON 内容到全局变量 XRAY_CONFIG
    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}")"
    # 读取脚本配置文件的完整 JSON 内容到全局变量 SCRIPT_CONFIG
    SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}")"
}

# =============================================================================
# 函数名称: get_common_config
# 功能描述: 从缓存的 Xray 和脚本配置中提取指定 inbound 索引的通用客户端配置参数，
#           并存储到 CLIENT_CONFIG 关联数组中。
# 参数:
#   $1: Xray 配置中 inbound 数组的索引 (inbound_index)
# 返回值: 无 (直接修改全局变量 CLIENT_CONFIG)
# =============================================================================
function get_common_config() {
    local inbound_index=$1 # 获取 inbound 索引参数

    # 获取服务器的公网 IPv4 地址作为远程主机地址
    CLIENT_CONFIG[remote_host]="$(curl -fsSL ipv4.icanhazip.com)"
    # 从脚本配置中获取端口号
    CLIENT_CONFIG[port]="$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.port")"
    # 从脚本配置中获取 Reality 公钥
    CLIENT_CONFIG[public_key]="$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.publicKey")"
    # 从脚本配置中获取配置标签 (tag)
    CLIENT_CONFIG[tag]="$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.tag")"

    # 从 Xray 配置中获取协议类型 (如 vless, trojan)
    CLIENT_CONFIG[protocol]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].protocol? | if . == null then empty else . end')"
    # 从 Xray 配置中获取客户端 UUID (VLESS) 或密码 (Trojan)
    CLIENT_CONFIG[uuid]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].id? | if . == null then empty else . end')"
    # 从 Xray 配置中获取客户端密码 (Trojan)
    CLIENT_CONFIG[password]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].password? | if . == null then empty else . end')"
    # 从 Xray 配置中获取 mKCP 的种子 (seed)
    CLIENT_CONFIG[seed]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.kcpSettings.seed? | if . == null then empty else . end')"
    # 从 Xray 配置中获取网络传输类型 (如 tcp, kcp, xhttp)
    CLIENT_CONFIG[type]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.network? | if . == null then empty else . end')"
    # 从 Xray 配置中获取 Flow 控制参数 (如 xtls-rprx-vision)
    CLIENT_CONFIG[flow]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].settings.clients[0].flow? | if . == null then empty else . end')"
    # 从 Xray 配置中获取安全传输类型 (如 none, tls, reality)
    CLIENT_CONFIG[security]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.security? | if . == null then empty else . end')"
    # 从 Xray 配置中获取 XHTTP 的路径 (path)
    CLIENT_CONFIG[path]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.xhttpSettings.path? | if . == null then empty else . end')"
    # 从 Xray 配置中随机获取一个 Reality 的服务器名称 (serverNames)
    CLIENT_CONFIG[server_name]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" --argjson random "$(bash "${GENERATE_PATH}" '--random')" '.inbounds[$i].streamSettings.realitySettings.serverNames? | if . == null then empty else .[$random % length] end')"
    # 从 Xray 配置中随机获取一个 Reality 的 Short ID (shortIds)
    CLIENT_CONFIG[short_id]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" --argjson random "$(bash "${GENERATE_PATH}" '--random')" '.inbounds[$i].streamSettings.realitySettings.shortIds? | if . == null then empty else .[$random % length] end')"
}

# =============================================================================
# 函数名称: get_tls_down_json
# 功能描述: 生成用于 TLS 下行模式的额外配置 JSON 字符串 (XHTTP_EXTRA)，
#           通常用于 SNI + CDN 的场景。
#           然后对生成的 JSON 进行 URL 编码 (XHTTP_EXTRA_ENCODED)。
# 参数: 无
# 返回值: 无 (直接修改全局变量 XHTTP_EXTRA 和 XHTTP_EXTRA_ENCODED)
# =============================================================================
function get_tls_down_json() {
    # 从脚本配置中获取 CDN 域名作为服务器名称
    local server_name="$(echo "${SCRIPT_CONFIG}" | jq -r ".nginx.cdn")"
    # 从脚本配置中获取 Xray 的路径
    local sni_path="$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.path")"

    # 使用 Here Document 构造 XHTTP 下行设置的 JSON 字符串
    XHTTP_EXTRA=$(
        cat <<EOF
{
    "downloadSettings": {
        "address": "${server_name}",
        "port": 443,
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
            "serverName": "${server_name}",
            "allowInsecure": false,
            "alpn": [
                "h2"
            ],
            "fingerprint": "chrome"
        },
        "xhttpSettings": {
            "host": "${server_name}",
            "path": "${sni_path}",
            "mode": "auto"
        }
    }
}
EOF
    )

    # 将生成的 JSON 字符串通过管道传递给 jq 格式化，再传递给 urlencode 进行编码
    XHTTP_EXTRA_ENCODED=$(echo "${XHTTP_EXTRA}" | jq -r '.' | urlencode)
}

# =============================================================================
# 函数名称: get_reality_down_json
# 功能描述: 生成用于 Reality 下行模式的额外配置 JSON 字符串 (XHTTP_EXTRA)，
#           通常用于 SNI + Reality 的场景。
#           然后对生成的 JSON 进行 URL 编码 (XHTTP_EXTRA_ENCODED)。
# 参数: 无
# 返回值: 无 (直接修改全局变量 XHTTP_EXTRA 和 XHTTP_EXTRA_ENCODED)
# =============================================================================
function get_reality_down_json() {
    local inbound_index=1 # 指定要读取的 inbound 索引 (通常为 fallback inbound)

    # 从脚本配置中获取主域名作为服务器名称
    local server_name="$(echo "${SCRIPT_CONFIG}" | jq -r ".nginx.domain")"
    # 从脚本配置中获取 Reality 公钥
    local public_key="$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.publicKey")"
    # 从脚本配置中获取 Xray 路径
    local sni_path="$(echo "${SCRIPT_CONFIG}" | jq -r ".xray.path")"
    # 从 Xray 配置中随机获取一个 Reality 的 Short ID
    local short_id="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" --argjson random "$(bash "${GENERATE_PATH}" '--random')" '.inbounds[$i].streamSettings.realitySettings.shortIds | .[$random % length?]')"

    # 使用 Here Document 构造 Reality 下行设置的 JSON 字符串
    XHTTP_EXTRA=$(
        cat <<EOF
{
    "downloadSettings": {
        "address": "${server_name}",
        "port": 443,
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
            "show": false,
            "serverName": "${server_name}",
            "fingerprint": "chrome",
            "publicKey": "${public_key}",
            "shortId": "${short_id}",
            "spiderX": "/"
        },
        "xhttpSettings": {
            "host": "",
            "path": "${sni_path}",
            "mode": "auto"
        }
    }
}
EOF
    )

    # 将生成的 JSON 字符串通过管道传递给 jq 格式化，再传递给 urlencode 进行编码
    XHTTP_EXTRA_ENCODED=$(echo "${XHTTP_EXTRA}" | jq -r '.' | urlencode)
}

# =============================================================================
# 函数名称: show_client_config
# 功能描述: 在终端打印格式化的客户端配置信息。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG)
# 返回值: 无 (直接打印到标准输出)
# =============================================================================
function show_client_config() {
    # 使用 Here Document 打印客户端配置的标题和各项参数
    cat <<EOF
------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.client")(${CLIENT_CONFIG[tag]}) ------------------
address          : ${CLIENT_CONFIG[remote_host]}
port             : ${CLIENT_CONFIG[port]}
protocol         : ${CLIENT_CONFIG[protocol]}
uuid             : ${CLIENT_CONFIG[uuid]}
password(trojan) : ${CLIENT_CONFIG[password]}
seed(mKCP)       : ${CLIENT_CONFIG[seed]}
flow             : ${CLIENT_CONFIG[flow]}
network          : ${CLIENT_CONFIG[type]}
security         : ${CLIENT_CONFIG[security]}
ServerName       : ${CLIENT_CONFIG[server_name]}
path             : ${CLIENT_CONFIG[path]}
Fingerprint      : chrome
PublicKey        : ${CLIENT_CONFIG[public_key]}
ShortId          : ${CLIENT_CONFIG[short_id]}
SpiderX          : /
EOF
}

# =============================================================================
# 函数名称: get_share_link_component
# 功能描述: 根据当前 CLIENT_CONFIG 中的参数，生成分享链接的各个组成部分。
#           这些组件可以被后续的特定链接生成函数组合使用。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG)
# 返回值: 无 (直接修改一系列 SHARE_LINK_COMPONENT_* 全局变量)
# =============================================================================
function get_share_link_component() {
    # 生成 VLESS 协议基础链接部分 (协议://UUID@地址:端口?网络类型=...)
    SHARE_LINK_COMPONENT_VLESS="${CLIENT_CONFIG[protocol]}://${CLIENT_CONFIG[uuid]}@${CLIENT_CONFIG[remote_host]}:${CLIENT_CONFIG[port]}?type=${CLIENT_CONFIG[type]}"
    # 生成 Trojan 协议基础链接部分 (协议://密码@地址:端口?网络类型=...)
    SHARE_LINK_COMPONENT_TROJAN="${CLIENT_CONFIG[protocol]}://${CLIENT_CONFIG[password]}@${CLIENT_CONFIG[remote_host]}:${CLIENT_CONFIG[port]}?type=${CLIENT_CONFIG[type]}"
    # 生成 mKCP 网络传输参数部分 (&seed=...)
    SHARE_LINK_COMPONENT_MKCP="&seed=${CLIENT_CONFIG[seed]}"
    # 生成 TLS 安全传输参数部分 (&security=tls&sni=...&alpn=h2&fp=chrome)
    SHARE_LINK_COMPONENT_TLS="&security=${CLIENT_CONFIG[security]}&sni=${CLIENT_CONFIG[server_name]}&alpn=h2&fp=chrome"
    # 生成 Reality 安全传输参数部分 (&security=reality&sni=...&pbk=...&sid=...&spx=%2F&fp=chrome)
    SHARE_LINK_COMPONENT_REALITY="&security=${CLIENT_CONFIG[security]}&sni=${CLIENT_CONFIG[server_name]}&pbk=${CLIENT_CONFIG[public_key]}&sid=${CLIENT_CONFIG[short_id]}&spx=%2F&fp=chrome"
    # 生成 XHTTP 网络传输路径参数部分 (&path=...), 注意去除路径开头的 '/'
    SHARE_LINK_COMPONENT_XHTTP="&path=%2F${CLIENT_CONFIG[path]#/}"
    # 生成 Flow 控制参数部分 (&flow=...)
    SHARE_LINK_COMPONENT_FLOW="&flow=${CLIENT_CONFIG[flow]}"
    # 生成额外参数部分 (&extra=...), 使用之前编码好的 XHTTP_EXTRA_ENCODED
    SHARE_LINK_COMPONENT_EXTRA="&extra=${XHTTP_EXTRA_ENCODED}"
}

# =============================================================================
# 函数名称: get_mkcp_share_link
# 功能描述: 为 mKCP 网络传输类型生成完整的分享链接。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG)
# 返回值: 无 (直接修改全局变量 SHARE_LINK)
# =============================================================================
function get_mkcp_share_link() {
    # 获取分享链接的各个组件
    get_share_link_component
    # 将 VLESS 基础部分和 mKCP 参数部分拼接成完整链接
    SHARE_LINK="${SHARE_LINK_COMPONENT_VLESS}${SHARE_LINK_COMPONENT_MKCP}"
}

# =============================================================================
# 函数名称: get_vision_share_link
# 功能描述: 为 Vision (XTLS) + Reality 网络传输类型生成完整的分享链接。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG)
# 返回值: 无 (直接修改全局变量 SHARE_LINK)
# =============================================================================
function get_vision_share_link() {
    # 获取分享链接的各个组件
    get_share_link_component
    # 将 VLESS 基础部分、Reality 安全参数和 Flow 控制参数拼接成完整链接
    SHARE_LINK="${SHARE_LINK_COMPONENT_VLESS}${SHARE_LINK_COMPONENT_REALITY}${SHARE_LINK_COMPONENT_FLOW}"
}

# =============================================================================
# 函数名称: get_xhttp_share_link
# 功能描述: 为 XHTTP + Reality 网络传输类型生成完整的分享链接。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG 和 XHTTP_EXTRA)
# 返回值: 无 (直接修改全局变量 SHARE_LINK)
# =============================================================================
function get_xhttp_share_link() {
    # 获取分享链接的各个组件
    get_share_link_component
    # 将 VLESS 基础部分、Reality 安全参数和 XHTTP 路径参数拼接成完整链接
    SHARE_LINK="${SHARE_LINK_COMPONENT_VLESS}${SHARE_LINK_COMPONENT_REALITY}${SHARE_LINK_COMPONENT_XHTTP}"
}

# =============================================================================
# 函数名称: get_trojan_share_link
# 功能描述: 为 Trojan + Reality 网络传输类型生成完整的分享链接。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG 和 XHTTP_EXTRA)
# 返回值: 无 (直接修改全局变量 SHARE_LINK)
# =============================================================================
function get_trojan_share_link() {
    # 获取分享链接的各个组件
    get_share_link_component
    # 将 Trojan 基础部分、Reality 安全参数和 XHTTP 路径参数拼接成完整链接
    SHARE_LINK="${SHARE_LINK_COMPONENT_TROJAN}${SHARE_LINK_COMPONENT_REALITY}${SHARE_LINK_COMPONENT_XHTTP}"
}

# =============================================================================
# 函数名称: get_fallback_xhttp_share_link
# 功能描述: 为 fallback inbound (通常是 index 1) 生成 XHTTP + Reality 分享链接。
#           这个函数会重新从 Xray 配置中读取 fallback inbound 的安全、服务器名和 Short ID。
# 参数: 无
# 返回值: 无 (直接修改全局变量 CLIENT_CONFIG 和 SHARE_LINK)
# =============================================================================
function get_fallback_xhttp_share_link() {
    local inbound_index=1 # 指定 fallback inbound 的索引

    # 从 Xray 配置中重新读取 fallback inbound 的安全类型
    CLIENT_CONFIG[security]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" '.inbounds[$i].streamSettings.security? | if . == null then empty else . end')"
    # 从 Xray 配置中重新随机读取 fallback inbound 的服务器名称
    CLIENT_CONFIG[server_name]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" --argjson random "$(bash "${GENERATE_PATH}" '--random')" '.inbounds[$i].streamSettings.realitySettings.serverNames | .[$random % length?]')"
    # 从 Xray 配置中重新随机读取 fallback inbound 的 Short ID
    CLIENT_CONFIG[short_id]="$(echo "${XRAY_CONFIG}" | jq -r --argjson i "${inbound_index}" --argjson random "$(bash "${GENERATE_PATH}" '--random')" '.inbounds[$i].streamSettings.realitySettings.shortIds | .[$random % length?]')"

    # 调用通用的 XHTTP 链接生成函数
    get_xhttp_share_link
}

# =============================================================================
# 函数名称: get_sni_tls_share_link
# 功能描述: 为 SNI + TLS 网络传输类型生成完整的分享链接。
#           通常用于通过 CDN 域名访问的场景。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG 和 SCRIPT_CONFIG)
# 返回值: 无 (直接修改全局变量 CLIENT_CONFIG 和 SHARE_LINK)
# =============================================================================
function get_sni_tls_share_link() {
    # 设置安全类型为 tls
    CLIENT_CONFIG[security]="tls"
    # 从脚本配置中读取 CDN 域名作为服务器名称
    CLIENT_CONFIG[server_name]="$(echo "${SCRIPT_CONFIG}" | jq -r ".nginx.cdn")"
    # 将远程主机地址也设置为 CDN 域名
    CLIENT_CONFIG[remote_host]="$(echo "${SCRIPT_CONFIG}" | jq -r ".nginx.cdn")"

    # 获取分享链接的各个组件
    get_share_link_component
    # 将 VLESS 基础部分、TLS 安全参数和 XHTTP 路径参数拼接成完整链接
    SHARE_LINK="${SHARE_LINK_COMPONENT_VLESS}${SHARE_LINK_COMPONENT_TLS}${SHARE_LINK_COMPONENT_XHTTP}"
}

# =============================================================================
# 函数名称: get_sni_tls_down_share_link
# 功能描述: 为 SNI + TLS + 下行模式 (带 extra 参数) 生成完整的分享链接。
# 参数: 无 (直接使用全局变量 XHTTP_EXTRA)
# 返回值: 无 (直接修改全局变量 SHARE_LINK)
# =============================================================================
function get_sni_tls_down_share_link() {
    # 首先获取 fallback 的 XHTTP 链接 (基础部分)
    get_fallback_xhttp_share_link
    # 在基础链接后追加额外的下行参数部分
    SHARE_LINK="${SHARE_LINK}${SHARE_LINK_COMPONENT_EXTRA}"
}

# =============================================================================
# 函数名称: get_sni_reality_down_share_link
# 功能描述: 为 SNI + Reality + 下行模式 (带 extra 参数) 生成完整的分享链接。
# 参数: 无 (直接使用全局变量 XHTTP_EXTRA)
# 返回值: 无 (直接修改全局变量 SHARE_LINK)
# =============================================================================
function get_sni_reality_down_share_link() {
    # 首先获取 SNI + TLS 的链接 (基础部分)
    get_sni_tls_share_link
    # 在基础链接后追加额外的下行参数部分
    SHARE_LINK="${SHARE_LINK}${SHARE_LINK_COMPONENT_EXTRA}"
}

# =============================================================================
# 函数名称: show_config
# 功能描述: 打印完整的客户端配置信息、额外配置 (如果有的话)、
#           最终的分享链接以及对应的二维码。
# 参数: 无 (直接使用全局变量 CLIENT_CONFIG, XHTTP_EXTRA, SHARE_LINK, I18N_DATA)
# 返回值: 无 (直接打印到标准输出)
# =============================================================================
function show_config() {
    # 在分享链接末尾追加标签作为锚点 (例如 #my_tag)
    SHARE_LINK="${SHARE_LINK}#${CLIENT_CONFIG[tag]}"

    # 显示客户端配置信息
    show_client_config

    # 如果存在额外配置 (XHTTP_EXTRA)，则显示它
    if [[ "${XHTTP_EXTRA}" ]]; then
        echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.extra") ------------------"
        # 使用 jq 格式化输出额外配置的 JSON
        echo "${XHTTP_EXTRA}" | jq -r '.'
    fi

    # 显示分享链接
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.link") ------------------"
    echo -e "${SHARE_LINK}"

    # 显示分享链接的二维码 (需要 qrencode 命令)
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.qr") ------------------"
    echo -e "${SHARE_LINK}" | qrencode -t ansiutf8

    # 打印分隔线结束
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: show_fallback_config
# 功能描述: 为 "fallback" 配置模式生成并显示多组客户端配置和链接。
#           包括 fallback 的 Vision 链接和 XHTTP 链接。
# 参数: 无
# 返回值: 无 (调用其他函数进行显示)
# =============================================================================
function show_fallback_config() {
    # 设置第一个配置的标签为 'fallbak_vision_reality'
    CLIENT_CONFIG[tag]='fallbak_vision_reality'
    # 生成 Vision 分享链接
    get_vision_share_link
    # 显示第一个配置
    show_config

    # 重新获取第二个 inbound (index 2) 的通用配置
    get_common_config 2
    # 设置第二个配置的标签为 'fallbak_xhttp_reality'
    CLIENT_CONFIG[tag]='fallbak_xhttp_reality'
    # 生成 fallback 的 XHTTP 分享链接
    get_fallback_xhttp_share_link
}

# =============================================================================
# 函数名称: show_sni_config
# 功能描述: 为 "sni" 配置模式生成并显示多组客户端配置和链接。
#           包括 SNI Vision, SNI XHTTP, SNI TLS Down, SNI XHTTP CDN, SNI Reality Down。
# 参数: 无
# 返回值: 无 (调用其他函数进行显示)
# =============================================================================
function show_sni_config() {
    # 设置第一个配置的标签为 'sni_vision_reality'
    CLIENT_CONFIG[tag]='sni_vision_reality'
    # 生成 Vision 分享链接
    get_vision_share_link
    # 显示第一个配置
    show_config

    # 重新获取第二个 inbound (index 2) 的通用配置
    get_common_config 2
    # 设置第二个配置的标签为 'sni_xhttp_reality'
    CLIENT_CONFIG[tag]='sni_xhttp_reality'
    # 生成 fallback 的 XHTTP 分享链接
    get_fallback_xhttp_share_link
    # 显示第二个配置
    show_config

    # 重新获取第二个 inbound (index 2) 的通用配置
    get_common_config 2
    # 设置第三个配置的标签为 'sni_tls_down'
    CLIENT_CONFIG[tag]='sni_tls_down'
    # 生成 TLS 下行的额外配置
    get_tls_down_json
    # 生成 SNI TLS Down 分享链接
    get_sni_tls_down_share_link
    # 显示第三个配置
    show_config

    # 重新获取第二个 inbound (index 2) 的通用配置
    get_common_config 2
    # 设置第四个配置的标签为 'sni_xhttp_cdn'
    CLIENT_CONFIG[tag]='sni_xhttp_cdn'
    # 清空额外配置
    XHTTP_EXTRA=""
    # 生成 SNI TLS 分享链接
    get_sni_tls_share_link
    # 显示第四个配置
    show_config

    # 重新获取第二个 inbound (index 2) 的通用配置
    get_common_config 2
    # 设置第五个配置的标签为 'sni_reality_down'
    CLIENT_CONFIG[tag]='sni_reality_down'
    # 生成 Reality 下行的额外配置
    get_reality_down_json
    # 生成 SNI Reality Down 分享链接
    get_sni_reality_down_share_link
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。
#           1. 加载国际化数据。
#           2. 缓存配置文件数据。
#           3. 获取第一个 inbound (index 1) 的通用配置。
#           4. 根据脚本配置中的 tag 值，选择相应的链接生成函数。
#           5. 调用 show_config 显示最终结果。
# 参数:
#   $@: 所有命令行参数 (此脚本中未使用)
# 返回值: 无 (协调调用其他函数完成整个流程)
# =============================================================================
function main() {
    # 加载国际化数据
    load_i18n

    # 缓存 Xray 和脚本配置数据
    cache_json_data

    # 获取第一个 inbound (index 1) 的通用配置
    get_common_config 1

    # 根据脚本配置中的 tag (转换为小写) 选择不同的处理分支
    case "$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag | ascii_downcase')" in
    mkcp) get_mkcp_share_link ;;      # mKCP 模式
    xhttp) get_xhttp_share_link ;;    # XHTTP 模式
    trojan) get_trojan_share_link ;;  # Trojan 模式
    fallback) show_fallback_config ;; # Fallback 模式
    sni) show_sni_config ;;           # SNI 模式
    *) get_vision_share_link ;;       # 默认为 Vision 模式
    esac

    # 显示最终的配置和链接信息 (重定向到标准错误输出 >&2，虽然不太常见)
    show_config >&2
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
