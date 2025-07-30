#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: check.sh
# 功能描述: 提供一系列验证函数，用于检查 IP、端口、UUID、密码、路径、Short ID、
#           域名安全性、DNS 解析、Xray 配置/版本以及邮箱地址的有效性。
#           主要用于在配置过程中验证用户输入或系统状态。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, jq, dig, curl, openssl, stdbuf
# 配置:
#   - ${SCRIPT_CONFIG_DIR}/config.json: 用于读取语言设置 (language)
#   - ${I18N_DIR}/${lang}.json: 用于读取具体的提示文本 (i18n 数据文件)
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
readonly CONFIG_DIR="${PROJECT_ROOT}/config"                   # 配置文件目录
readonly CONFIG_XRAY_DIR="${CONFIG_DIR}/xray"                  # Xray 配置文件目录
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json" # 脚本主配置文件路径

# --- 正则表达式常量 ---
# 定义各种数据格式的正则表达式，用于验证输入
readonly DOMAIN_REGEX="^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"                      # 域名
readonly IPV4_REGEX='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' # IPv4
readonly IPV6_REGEX='^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'                                            # IPv6 (简化版)
readonly HEX_REGEX='^[0-9a-fA-F]+$'                                                                         # 十六进制字符串
readonly UUID_REGEX='^[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}$' # UUID
readonly EMAIL_REGEX='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'                                     # 邮箱地址

# --- 全局变量声明 ---
# 声明用于存储语言参数和国际化数据的全局变量
declare LANG_PARAM='' # (未在脚本中实际使用，可能是预留)
declare I18N_DATA=''  # 存储从 i18n JSON 文件中读取的全部数据

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
    # 从配置文件中读取语言设置
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
# 函数名称: _info
# 功能描述: 打印信息级别的提示消息。
# 参数:
#   $1: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function _info() {
    # 从 i18n 数据中读取 "信息" 标题，然后用黄色打印消息
    printf "${YELLOW}[$(echo "$I18N_DATA" | jq -r '.title.info')]${NC} %s\n" "$1" >&2
}

# =============================================================================
# 函数名称: _pass
# 功能描述: 打印成功/通过级别的提示消息。
# 参数:
#   $1: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function _pass() {
    # 从 i18n 数据中读取 "通过" 标题，然后用绿色打印消息
    printf "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.pass')]${NC} %s\n" "$1" >&2
}

# =============================================================================
# 函数名称: _fail
# 功能描述: 打印失败/错误级别的提示消息。
# 参数:
#   $1: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function _fail() {
    # 从 i18n 数据中读取 "失败" 标题，然后用红色打印消息
    printf "${RED}[$(echo "$I18N_DATA" | jq -r '.title.fail')]${NC} %s\n" "$1" >&2
}

# =============================================================================
# 函数名称: _test
# 功能描述: 打印测试/检查过程中的提示消息。
# 参数:
#   $1: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function _test() {
    # 从 i18n 数据中读取 "测试" 标题，然后用黄色打印消息
    printf "${YELLOW}[$(echo "$I18N_DATA" | jq -r '.title.test')]${NC} %s\n" "$1" >&2
}

# =============================================================================
# 函数名称: valid_domain
# 功能描述: 使用正则表达式检查给定字符串是否为有效的域名格式。
# 参数:
#   $1: 待检查的域名字符串 (domain)
# 返回值: 0-有效 1-无效 (直接由 [[ =~ ]] 命令的退出码决定)
# =============================================================================
function valid_domain() {
    local domain="$1" # 获取域名参数

    # 使用正则表达式匹配域名格式，成功匹配返回 0，否则返回 1
    [[ "$domain" =~ $DOMAIN_REGEX ]] && return 0 || return 1
}

# =============================================================================
# 函数名称: resolve_domain
# 功能描述: 使用 dig 命令尝试解析域名，检查是否有有效的 IP 地址记录。
# 参数:
#   $1: 待解析的域名 (domain)
# 返回值: 0-解析成功 1-解析失败或无记录
# =============================================================================
function resolve_domain() {
    # 使用 dig +short 命令解析域名，并将输出通过管道传递给 grep
    # 如果 grep 能在输出中找到至少一个 '.' 字符（通常是 IP 地址的一部分），则返回 0
    # 否则返回 1
    if dig +short "$1" | grep -q '.'; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# 函数名称: dns_resolution
# 功能描述: 检查给定域名是否解析为当前服务器的 IP 地址。
#           分别检查 IPv4 和 IPv6 地址。
# 参数:
#   $1: 待检查的域名 (domain)
# 返回值: 0-至少有一个 IP 匹配 1-都不匹配
# =============================================================================
function dns_resolution() {
    local domain=$1 # 获取域名参数

    # 获取当前服务器的公网 IPv4 和 IPv6 地址
    local expected_ipv4="$(curl -fsSL ipv4.icanhazip.com)"
    local expected_ipv6="$(curl -fsSL ipv6.icanhazip.com)"

    local resolved=0 # 初始化标志变量，表示是否匹配

    # 解析域名的 IPv4 和 IPv6 记录
    local actual_ipv4="$(dig +short "${domain}")"
    local actual_ipv6="$(dig +short AAAA "${domain}")"

    # 检查解析到的 IPv4 是否包含服务器的 IPv4
    if [[ ${actual_ipv4} =~ ${expected_ipv4} ]]; then resolved=1; fi
    # 检查解析到的 IPv6 是否包含服务器的 IPv6
    if [[ ${actual_ipv6} =~ ${expected_ipv6} ]]; then resolved=1; fi

    # 根据 resolved 标志返回结果
    [[ ${resolved} -eq 1 ]]
}

# =============================================================================
# 函数名称: test_tcp_connection
# 功能描述: 测试到指定主机和端口的 TCP 连接是否可达。
#           利用 bash 内建的 /dev/tcp 特性。
# 参数:
#   $1: 主机名或 IP 地址 (host)
#   $2: 端口号 (port)
# 返回值: 0-连接成功 1-连接失败 (由 /dev/tcp 操作的退出码决定)
# =============================================================================
function test_tcp_connection() {
    # 尝试打开到 host:port 的 TCP 连接，将输出重定向到 /dev/null
    # 成功则返回 0，失败（如连接被拒绝、超时）则返回非 0
    echo >/dev/tcp/"$1"/"$2" 2>/dev/null
    return $? # 返回上一条命令的退出码
}

# =============================================================================
# 函数名称: get_tls_info
# 功能描述: 使用 openssl s_client 命令获取指定域名的 TLS 信息。
# 参数:
#   $1: 域名 (domain)
# 返回值: TLS 连接的详细信息 (echo 输出)
# 注意: 会过滤掉空字节 (\0)
# =============================================================================
function get_tls_info() {
    # 向域名的 443 端口发起 TLS 1.3 连接请求，并指定 ALPN 为 h2
    # 使用 echo QUIT 发送退出命令，stdbuf -oL 确保输出行缓冲
    # 2>&1 将错误输出合并到标准输出，tr -d '\0' 过滤掉空字节
    echo QUIT | stdbuf -oL openssl s_client -connect "${1}:443" -tls1_3 -alpn h2 2>&1 | tr -d '\0'
}

# =============================================================================
# 函数名称: check_ip
# 功能描述: 验证 IP 地址是否符合 IPv4 或 IPv6 格式。
# 参数:
#   $1: 待检查的 IP 地址 (ip)
# 返回值: 0-有效 1-无效 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_ip() {
    local ip="$1" # 获取 IP 地址参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.ip.check")${ip}"

    # 使用正则表达式检查 IPv4 格式
    if [[ "$ip" =~ $IPV4_REGEX ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.ip.ipv4_valid")$ip"
        return 0
    # 使用正则表达式检查 IPv6 格式
    elif [[ "$ip" =~ $IPV6_REGEX ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.ip.ipv6_valid")$ip"
        return 0
    else
        # 如果都不匹配，则为无效 IP
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.ip.invalid")$ip"
        return 1
    fi
}

# =============================================================================
# 函数名称: check_port
# 功能描述: 验证端口号是否在有效范围内 (1-65535)。
# 参数:
#   $1: 待检查的端口号 (port)
# 返回值: 0-有效或为空 1-无效 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_port() {
    local port="$1" # 获取端口号参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.port.check")${port}"

    # 如果端口为空，则认为是有效的（可能表示使用默认值）
    if [[ -z "${port}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.port.empty")"
    # 检查端口号是否在 1-65535 范围内
    elif ((port < 65535 && port > 1)); then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.port.valid")$port"
    else
        # 如果超出范围，则为无效
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.port.range_error")$port"
        return 1
    fi
    return 0
}

# =============================================================================
# 函数名称: check_uuid
# 功能描述: 验证 UUID 是否符合标准格式。
#           注意：此函数的逻辑似乎与注释描述有出入，它将空 UUID 和非标准格式视为 "pass"。
# 参数:
#   $1: 待检查的 UUID 字符串 (uuid)
# 返回值: 总是返回 0 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_uuid() {
    local uuid="$1" # 获取 UUID 参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.uuid.check")${uuid}"

    # 如果 UUID 为空，则认为是有效的（可能表示使用默认值或自动生成）
    if [[ -z "${uuid}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.uuid.empty")"
    # 如果 UUID 不符合标准格式，则认为是有效的字符串（可能表示使用普通字符串）
    elif ! [[ "$uuid" =~ $UUID_REGEX ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.uuid.string")$uuid"
    else
        # 如果符合标准格式，则为有效 UUID
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.uuid.valid")$uuid"
    fi
    return 0
}

# =============================================================================
# 函数名称: check_password
# 功能描述: 验证密码是否符合基本安全要求（非空、无空格、长度>=8）。
# 参数:
#   $1: 待检查的密码 (password)
# 返回值: 0-有效 1-无效 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_password() {
    local password="$1" # 获取密码参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.password.check")${password}"

    # 如果密码为空，则认为无效
    if [[ -z "${password}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.password.empty")"
        return 0
    fi

    # 检查密码中是否包含空格
    if [[ "${password}" =~ *\ * ]]; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.password.space_error")$password"
        return 1
    fi

    # 检查密码长度是否小于 8
    if ((${#password} < 8)); then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.password.length_error")$password"
        return 1
    fi

    # 如果所有检查都通过，则密码有效
    _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.password.valid")$password"
    return 0
}

# =============================================================================
# 函数名称: check_path
# 功能描述: 验证路径字符串是否符合 URL 路径格式要求。
# 参数:
#   $1: 待检查的路径字符串 (path)
# 返回值: 0-有效 1-无效 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_path() {
    local path="$1" # 获取路径参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.check")${path}"

    # 如果路径为空，则认为是有效的（可能表示使用根路径）
    if [[ -z "${path}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.empty")"
        return 0
    fi

    # 检查路径中是否包含空格
    if [[ "${path}" =~ *\ * ]]; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.space_error")$path"
        return 1
    fi

    # 检查路径长度是否超过 128
    if ((${#path} > 128)); then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.length_error")$path"
        return 1
    fi

    # 检查路径是否包含不允许的字符（只允许字母、数字、下划线、斜杠、点、连字符）
    if [[ "${path}" =~ [^a-zA-Z0-9_/.\-] ]]; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.char_error")$path"
        return 1
    fi

    # 检查路径是否包含连续的斜杠
    if [[ "${path}" =~ // ]]; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.double_slash_error")$path"
        return 1
    fi

    # 如果所有检查都通过，则路径有效
    _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.path.valid")$path"
    return 0
}

# =============================================================================
# 函数名称: check_short_id
# 功能描述: 验证 Short ID 是否符合要求（空、单数字、或有效的十六进制字符串）。
# 参数:
#   $1: 待检查的 Short ID (short_id)
# 返回值: 0-有效 1-无效 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_short_id() {
    local short_id="$1" # 获取 Short ID 参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.short.check")${short_id}"

    # 如果 Short ID 为空，则认为是有效的
    if [[ -z "${short_id}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.short.empty")"
        return 0
    fi

    # 如果 Short ID 是 0-8 的单个数字，则认为是有效的（表示生成指定长度的 ID）
    if [[ ${short_id} =~ ^[0-8]$ ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.short.digit")$short_id"
        return 0
    fi

    # 检查 Short ID 的长度是否为奇数或超过 16
    if ((${#short_id} % 2 != 0 || ${#short_id} > 16)); then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.short.length_error")$short_id"
        return 1
    fi

    # 检查 Short ID 是否为有效的十六进制字符串
    if ! [[ "${short_id}" =~ $HEX_REGEX ]]; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.short.hex_error")$short_id"
        return 1
    fi

    # 如果所有检查都通过，则 Short ID 有效
    _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.short.valid")$short_id"
    return 0
}

# =============================================================================
# 函数名称: check_domain_security
# 功能描述: 全面检查域名的安全性，包括格式、解析、TCP 连接和 TLS 信息。
# 参数:
#   $1: 待检查的域名 (domain)
# 返回值: 0-安全检查通过 1-安全检查失败 (并打印详细的检查过程和结果到 >&2)
# =============================================================================
function check_domain_security() {
    local domain="$1" # 获取域名参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.security_check")${domain}"

    # 如果域名为空，则认为是有效的（可能表示不使用域名）
    if [[ -z "${domain}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.empty")"
        return 0
    fi

    # 检查域名格式是否有效
    if ! valid_domain "$domain"; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.format_error")$domain"
        return 1
    fi

    # 测试域名解析
    _test "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.resolve")${domain}"
    if ! resolve_domain "$domain"; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.resolve_fail")$domain"
        return 1
    fi

    # 测试到域名 443 端口的 TCP 连接
    _test "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tcp.connect_check"): ${domain}:443"
    if ! test_tcp_connection "$domain" 443; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tcp.connect_fail" | sed "s/\${domain}/${domain}/")"
        return 1
    fi

    # 获取域名的 TLS 信息
    _test "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tls.info"): ${domain}"
    local tls_info
    tls_info=$(get_tls_info "$domain")

    # 检查是否支持 TLS 1.3
    if ! echo "$tls_info" | grep -q "TLSv1.3"; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tls.error")"
        return 1
    else
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tls.pass")"
    fi

    # 检查是否使用 X25519 密钥交换算法
    if echo "$tls_info" | grep -q "X25519"; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tls.key_exchange_pass")"
    else
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.tls.key_exchange_warn")$domain"
        return 1
    fi

    # 如果所有检查都通过，则域名安全检查通过
    _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.security_pass" | sed "s/\${domain}/${domain}/")"
    return 0
}

# =============================================================================
# 函数名称: check_dns_resolution
# 功能描述: 检查域名是否解析为当前服务器的 IP 地址。
# 参数:
#   $1: 待检查的域名 (domain)
# 返回值: 0-DNS 解析正确 1-DNS 解析错误 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_dns_resolution() {
    local domain="$1" # 获取域名参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.dns.check_start")${domain}"

    # 检查域名格式是否有效
    if ! valid_domain "$domain"; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.format_error")$domain"
        return 1
    fi

    # 测试域名解析
    _test "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.domain.resolve"): ${domain}"
    if ! dns_resolution "$domain"; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.dns.resolution_fail")$domain"
        return 1
    fi

    # 如果解析正确，则检查通过
    _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.dns.check_pass" | sed "s/\${domain}/${domain}/")"
    return 0
}

# =============================================================================
# 函数名称: check_xray_config_exists
# 功能描述: 检查指定名称的 Xray 配置文件是否存在。
# 参数:
#   $1: 配置文件名（不含扩展名）(SCRIPT_FILE)
# 返回值: 0-文件存在 1-文件不存在 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_xray_config_exists() {
    local SCRIPT_FILE="$1" # 获取配置文件名参数
    # 构造完整的配置文件路径
    local CONFIG_FILE="${CONFIG_XRAY_DIR}/${SCRIPT_FILE}.json"

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config.check")${CONFIG_FILE}"

    # 检查文件是否存在
    if [[ -f "${CONFIG_FILE}" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config.exist")${CONFIG_FILE}"
        return 0
    else
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config.not_exist")${CONFIG_FILE}"
        return 1
    fi
}

# =============================================================================
# 函数名称: check_xray_version_exists
# 功能描述: 通过访问 GitHub Releases 页面检查指定的 Xray 版本是否存在。
# 参数:
#   $1: Xray 版本号 (version)
# 返回值: 0-版本存在 1-版本不存在 (并打印相应的提示信息到 >&2)
# =============================================================================
function check_xray_version_exists() {
    local version="$1" # 获取版本号参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.version.check")v${version}"

    # 构造 GitHub Releases 页面的 URL
    local version_url="https://github.com/XTLS/Xray-core/releases/tag/v${version#*v}"

    # 使用 curl 获取页面的 HTTP 状态码
    local status_code=$(curl -L -o /dev/null -s -w '%{http_code}\n' "$version_url")

    # 检查状态码是否为 200 (OK)
    if [[ "$status_code" == "200" ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.version.exist")${version}"
        return 0
    else
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.version.not_exist")${version}"
        return 1
    fi
}

# =============================================================================
# 函数名称: validate_email
# 功能描述: 验证邮箱地址格式是否正确。
# 参数:
#   $1: 待验证的邮箱地址 (email)
# 返回值: 0-格式正确 1-格式错误或为空 (并打印相应的提示信息到 >&2)
# =============================================================================
function validate_email() {
    local email="$1" # 获取邮箱地址参数

    # 打印正在检查的信息
    _info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.email.check")${email}"

    # 如果邮箱地址为空，则认为无效
    if [[ -z "${email}" ]]; then
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.email.empty")"
        return 1
    fi

    # 使用正则表达式检查邮箱格式
    if [[ "$email" =~ $EMAIL_REGEX ]]; then
        _pass "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.email.valid")$email"
        return 0
    else
        _fail "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.email.format_error")$email"
        return 1
    fi
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。根据传入的第一个参数 (option)
#           调用相应的检查函数并输出结果。
# 参数:
#   $1: 操作选项 (e.g., --ip, --port, --uuid 等)
#   $@: 剩余参数，传递给被调用的具体函数
# 返回值: 无 (调用具体函数并输出其结果到 >&2)
# 退出码: 如果选项无效，则输出错误信息并退出脚本 (exit 1)
# =============================================================================
function main() {
    # 加载国际化数据
    load_i18n

    local option="$1" # 获取第一个参数作为操作选项
    shift             # 移除第一个参数，剩下的参数留给具体函数处理

    # 使用 case 语句根据选项调用对应的函数
    # 所有函数的输出都重定向到标准错误输出 >&2，这样标准输出可以用于返回结果
    case "${option}" in
    --ip) check_ip "$@" >&2 ;;                    # 检查 IP 地址
    --port) check_port "$@" >&2 ;;                # 检查端口
    --uuid) check_uuid "$@" >&2 ;;                # 检查 UUID
    --password) check_password "$@" >&2 ;;        # 检查密码
    --path) check_path "$@" >&2 ;;                # 检查路径
    --short) check_short_id "$@" >&2 ;;           # 检查 Short ID
    --domain) check_domain_security "$@" >&2 ;;   # 检查域名安全性
    --dns) check_dns_resolution "$@" >&2 ;;       # 检查 DNS 解析
    --tag) check_xray_config_exists "$@" >&2 ;;   # 检查 Xray 配置文件
    --xray) check_xray_version_exists "$@" >&2 ;; # 检查 Xray 版本
    --email) validate_email "$@" >&2 ;;           # 验证邮箱
    esac
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
