#!/usr/bin/env bash
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: main.sh
# 脚本仓库: https://github.com/zxcvos/Xray-script
# 功能描述: X-UI 项目的主要管理脚本。
#           提供交互式菜单和命令行接口，用于安装、配置、管理 Xray-core
#           和相关服务（如 Nginx, GeoIP, WARP 等），支持多语言。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, jq, cut, sed
# 配置:
#   - ${SCRIPT_CONFIG_DIR}/config.json: 用于读取语言设置 (language) 和脚本配置
#   - ${I18N_DIR}/${lang}.json: 用于读取具体的提示文本 (i18n 数据文件)
#
# Copyright (C) 2025 zxcvos
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

# 定义配置文件和相关目录/脚本的路径
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"              # 主配置文件目录
readonly I18N_DIR="${PROJECT_ROOT}/i18n"                       # 国际化文件目录
readonly CONFIG_DIR="${PROJECT_ROOT}/config"                   # 配置文件目录
readonly MENU_PATH="${CUR_DIR}/menu.sh"                        # 菜单脚本路径
readonly HANDLER_PATH="${CUR_DIR}/handler.sh"                  # 处理器脚本路径
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json" # 脚本主配置文件路径

# --- 全局变量声明 ---
# 声明用于存储语言参数和国际化数据的全局变量
declare LANG_PARAM=''    # (未在脚本中实际使用，可能是预留)
declare I18N_DATA=''     # 存储从 i18n JSON 文件中读取的全部数据
declare SCRIPT_CONFIG='' # 存储脚本配置内容

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
# 函数名称: _error
# 功能描述: 打印错误信息到标准错误输出并退出脚本。
# 参数:
#   $@: 要输出的错误信息文本
# 返回值: 无 (直接打印到标准错误输出 >&2 并退出)
# 退出码: 1
# =============================================================================

function _error() {
    # 打印红色的错误标题（从 i18n 数据获取）
    printf "${RED}[$(echo "$I18N_DATA" | jq -r '.title.error')] ${NC}"
    # 打印传入的错误信息
    printf -- "%s" "$@"
    # 打印换行符
    printf "\n"
    # 退出脚本，错误码为 1
    exit 1
}

# =============================================================================
# 函数名称: exec_menu
# 功能描述: 执行菜单脚本 (menu.sh)，并将菜单脚本的退出码作为返回值。
# 参数:
#   $@: 传递给 menu.sh 脚本的参数
# 返回值: menu.sh 脚本的退出码 (通过 return ${OPTION} 返回)
# =============================================================================

function exec_menu() {
    local OPTION=0 # 初始化局部变量 OPTION 为 0
    # 执行菜单脚本，并传递所有参数
    bash "${MENU_PATH}" "$@"
    # 获取菜单脚本执行后的退出码 ($?)
    OPTION=$?
    # 返回菜单脚本的退出码
    return ${OPTION}
}

# =============================================================================
# 函数名称: exec_handler
# 功能描述: 执行处理器脚本 (handler.sh)。
# 参数:
#   $@: 传递给 handler.sh 脚本的参数
# 返回值: 无 (handler.sh 的退出码即为当前函数的退出码)
# =============================================================================

function exec_handler() {
    # 执行处理器脚本，并传递所有参数
    bash "${HANDLER_PATH}" "$@"
}

# =============================================================================
# 函数名称: processes_web_config
# 功能描述: 处理 Web 配置相关的流程。
#           1. 显示 Web 配置菜单。
#           2. 根据用户选择确定 Web 类型 (normal, v3, v4)。
#           3. 根据 is_change 参数决定是仅更改配置还是执行完整安装流程。
# 参数:
#   $1: is_change - 控制流程模式。'y' 表示仅更改 web 配置；
#                   'n' 表示执行完整安装流程 (安装脚本、Nginx、Xray 配置)。
#                   默认为 'y'。
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_web_config() {
    local is_change="${1:-y}" # 获取 is_change 参数，默认为 'y'
    # 显示 Web 配置菜单
    exec_menu '--web'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    local web='normal' # 初始化 web 类型为 'normal'
    # 根据用户选择设置具体的 web 类型
    case ${choose} in
    2) web='v3' ;;     # 选择 2 对应 v3
    3) web='v4' ;;     # 选择 3 对应 v4
    *) web='normal' ;; # 其他情况 (包括 1 和默认) 对应 normal
    esac
    # 如果 is_change 为 'y'，则仅更改 web 配置
    if [[ "${is_change}" == 'y' ]]; then
        exec_handler '--web' "${web}"
    else
        # 如果 is_change 为 'n'，则执行完整安装流程
        exec_handler '--script-config' 'SNI'  # 设置脚本配置为 SNI
        exec_handler '--install'              # 安装核心组件
        exec_handler '--nginx-install'        # 安装 Nginx
        exec_handler '--xray-config' "${web}" # 配置 Xray 使用选定的 web 类型
        exec_handler '--restart'              # 重启 Xray 服务
        exec_handler '--share'                # 显示分享链接
    fi
}

# =============================================================================
# 函数名称: processes_xray_config
# 功能描述: 处理 Xray 配置相关的流程。
#           1. 显示 Xray 配置菜单。
#           2. 根据用户选择确定 XTLS 配置类型 (Vision, mKCP, XHTTP, Trojan, Fallback, SNI)。
#           3. 如果选择了 SNI，则调用 processes_web_config 进行特殊处理。
#           4. 否则，设置脚本配置并执行安装和 Xray 配置。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_xray_config() {
    # 显示 Xray 配置菜单
    exec_menu '--config'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    local XTLS_CONFIG='Vision' # 初始化 XTLS 配置类型为 'Vision'
    # 根据用户选择设置具体的 XTLS 配置类型
    case ${choose} in
    1) XTLS_CONFIG='mKCP' ;;     # 选择 1 对应 mKCP
    3) XTLS_CONFIG='XHTTP' ;;    # 选择 3 对应 XHTTP
    4) XTLS_CONFIG='Trojan' ;;   # 选择 4 对应 Trojan
    5) XTLS_CONFIG='Fallback' ;; # 选择 5 对应 Fallback
    6) XTLS_CONFIG='SNI' ;;      # 选择 6 对应 SNI
    *) XTLS_CONFIG='Vision' ;;   # 其他情况 (包括 2 和默认) 对应 Vision
    esac
    # 如果选择了 SNI 配置
    if [[ "${XTLS_CONFIG}" == 'SNI' ]]; then
        # 调用 processes_web_config 处理 SNI 特殊流程 (不执行完整安装)
        processes_web_config 'n'
    else
        # 对于其他配置类型
        exec_handler '--script-config' "${XTLS_CONFIG}" # 设置脚本配置
        exec_handler '--install'                        # 安装核心组件
        exec_handler '--xray-config'                    # 配置 Xray
        exec_handler '--restart'                        # 重启 Xray 服务
        exec_handler '--share'                          # 显示分享链接
    fi
}

# =============================================================================
# 函数名称: processes_xray
# 功能描述: 处理 Xray 安装相关的流程。
#           1. 显示 Xray 安装菜单。
#           2. 根据用户选择确定 Xray 版本 (release, latest, custom)。
#           3. 根据 is_exec 参数决定是立即安装还是设置版本后进入配置流程。
# 参数:
#   $1: is_exec - 控制流程模式。'y' 表示立即执行安装；
#                 'n' 表示仅设置版本，然后进入 Xray 配置流程。
#                 默认为 'y'。
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_xray() {
    local is_exec="${1:-y}" # 获取 is_exec 参数，默认为 'y'
    local version='release' # 初始化 Xray 版本为 'release'
    # 显示 Xray 安装菜单
    exec_menu '--xray'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择设置具体的 Xray 版本
    case ${choose} in
    1) version='latest' ;;  # 选择 1 对应 latest
    3) version='custom' ;;  # 选择 3 对应 custom
    *) version='release' ;; # 其他情况 (包括 2 和默认) 对应 release
    esac
    # 如果 is_exec 为 'y'，则立即执行安装
    if [[ "${is_exec}" == 'y' ]]; then
        exec_handler '--install' "${version}" 'y' # 安装指定版本的 Xray
    else
        # 如果 is_exec 为 'n'，则仅设置版本，然后进入配置流程
        exec_handler '--version' "${version}" # 设置 Xray 版本
        processes_xray_config                 # 进入 Xray 配置流程
    fi
}

# =============================================================================
# 函数名称: processes_full_installation
# 功能描述: 处理一键安装相关的流程。
#           1. 显示一键安装菜单。
#           2. 根据用户选择决定是执行快速安装 Vision 还是进入详细 Xray 安装流程。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_full_installation() {
    # 显示一键安装菜单
    exec_menu '--full'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择执行不同操作
    case ${choose} in
    2)
        # 选择 2：进入详细的 Xray 安装流程 (不立即执行安装)
        processes_xray 'n'
        ;;
    *)
        # 其他情况 (包括 1 和默认)：执行快速安装 Vision
        exec_handler '--quick' 'Vision'
        ;;
    esac
}

# =============================================================================
# 函数名称: processes_routing
# 功能描述: 处理路由规则配置相关的流程。
#           1. 显示路由规则菜单。
#           2. 根据用户选择执行不同的路由配置操作 (WARP, Block IP/Domain, WARP IP/Domain)。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_routing() {
    # 显示路由规则菜单
    exec_menu '--route'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择执行不同的路由配置操作
    case ${choose} in
    1) exec_handler '--warp' ;;                     # 选择 1：配置 WARP
    2) exec_handler '--reset-warp' ;;               # 选择 2：重置 WARP
    3) exec_handler '--routing' 'block' 'ip' ;;     # 选择 3：配置阻止 IP 规则
    4) exec_handler '--routing' 'block' 'domain' ;; # 选择 4：配置阻止 Domain 规则
    5) exec_handler '--routing' 'warp' 'ip' ;;      # 选择 5：配置 WARP IP 规则
    6) exec_handler '--routing' 'warp' 'domain' ;;  # 选择 6：配置 WARP Domain 规则
    *) exit 0 ;;                                    # 其他情况：退出脚本
    esac
    exec_handler '--restart' # 重启 Xray 服务
}

# =============================================================================
# 函数名称: processes_sni_config
# 功能描述: 处理 SNI 配置相关的流程。
#           1. 检查当前 Xray 配置是否为 SNI 模式，如果不是则报错退出。
#           2. 显示 SNI 配置菜单。
#           3. 根据用户选择执行不同的 SNI 相关操作 (更改域名/CDN, 更新 Nginx, 配置 Cron, Web 配置, 重置 V3)。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# 退出码: 如果当前配置不是 SNI，则调用 _error 退出脚本 (exit 1)
# =============================================================================

function processes_sni_config() {
    # 从配置文件中读取当前 Xray 的 tag
    local tag="$(jq -r '.xray.tag' "${SCRIPT_CONFIG_PATH}")"
    # 检查 tag 是否为 'sni' (不区分大小写)，如果不是则调用 _error 函数报错退出
    [[ "${tag,,}" == 'sni' ]] || _error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.not_support")"
    # 显示 SNI 配置菜单
    exec_menu '--sni'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择执行不同的 SNI 相关操作
    case ${choose} in
    1) exec_handler '--change-domain' 'domain' ;; # 选择 1：更改域名
    2) exec_handler '--change-domain' 'cdn' ;;    # 选择 2：更改 CDN
    3) exec_handler '--nginx-update' ;;           # 选择 3：更新 Nginx 配置
    4) exec_handler '--nginx-cron' ;;             # 选择 4：配置 Nginx Cron 任务
    5) processes_web_config ;;                    # 选择 5：进入 Web 配置流程
    6) exec_handler '--v3-reset' ;;               # 选择 6：重置 V3 配置
    *) exit 0 ;;                                  # 其他情况：退出脚本
    esac
}

# =============================================================================
# 函数名称: processes_language
# 功能描述: 处理语言设置相关的流程。
#           1. 显示语言设置菜单。
#           2. 根据用户选择设置不同的语言（zh: 中文，en: 英语）。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_language() {
    # 显示语言设置菜单
    exec_menu '--language'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择设置不同的语言
    case ${choose} in
    2) LANG_PARAM="en" ;; # 选择英文
    *) LANG_PARAM="zh" ;; # 默认中文
    esac
    # 更新配置文件中的语言设置
    SCRIPT_CONFIG="$(jq --arg language "${LANG_PARAM}" '.language = $language' "${SCRIPT_CONFIG_PATH}")"
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
    bash "${CUR_DIR}/${CUR_FILE}.sh" && exit 0
}

# =============================================================================
# 函数名称: processes_config
# 功能描述: 处理主配置管理相关的流程。
#           1. 显示主配置管理菜单。
#           2. 根据用户选择进入不同的子流程 (Xray 配置, 路由规则, SNI 配置, GeoData Cron)。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_config() {
    # 显示主配置管理菜单
    exec_menu '--management'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择进入不同的子流程
    case ${choose} in
    1) processes_xray_config ;;         # 选择 1：进入 Xray 配置流程
    2) processes_routing ;;             # 选择 2：进入路由规则配置流程
    3) processes_sni_config ;;          # 选择 3：进入 SNI 配置流程
    4) exec_handler '--geodata-cron' ;; # 选择 4：配置 GeoData Cron 任务
    5) processes_language ;;            # 选择 5：设置语言
    *) exit 0 ;;                        # 其他情况：退出脚本
    esac
}

# =============================================================================
# 函数名称: processes_index
# 功能描述: 处理脚本主界面的流程。
#           1. 显示 Banner、状态和主菜单。
#           2. 根据用户选择执行不同的主操作 (一键安装, Xray 安装, 卸载, 启动, 停止, 重启, 分享链接, 流量统计, 配置管理)。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function processes_index() {
    # 显示 Banner
    exec_menu '--banner'
    # 显示状态信息
    exec_menu '--status'
    # 显示主菜单
    exec_menu '--index'
    # 获取菜单选择的退出码 (代表用户选择)
    local choose=$(echo $?)
    # 根据用户选择执行不同的主操作
    case ${choose} in
    1) processes_full_installation ;; # 选择 1：进入一键安装流程
    2) processes_xray ;;              # 选择 2：进入 Xray 安装流程
    3) exec_handler '--purge' ;;      # 选择 3：卸载
    4) exec_handler '--start' ;;      # 选择 4：启动服务
    5) exec_handler '--stop' ;;       # 选择 5：停止服务
    6) exec_handler '--restart' ;;    # 选择 6：重启服务
    7) exec_handler '--share' ;;      # 选择 7：显示分享链接
    8) exec_handler '--traffic' ;;    # 选择 8：显示流量统计
    9) processes_config ;;            # 选择 9：进入配置管理流程
    *) exit 0 ;;                      # 其他情况：退出脚本
    esac
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。
#           1. 加载国际化数据。
#           2. 检查传入的第一个参数 ($1)。
#           3. 如果是特定的快速配置参数 (--vision, --xhttp, --fallback)，则直接执行快速安装。
#           4. 否则，进入主索引流程 (processes_index)。
# 参数:
#   $1: 命令行选项 (例如 --vision, --xhttp, --fallback)
#   $2: 传递给 processes_index 的第二个参数 (如果主流程被调用)
# 返回值: 无 (通过调用其他函数和脚本执行操作)
# =============================================================================

function main() {
    # 加载国际化数据
    load_i18n
    # 将第一个参数转换为小写进行匹配
    case "${1,,}" in
    # 如果参数是 --vision，则执行快速安装 Vision
    --vision) exec_handler '--quick' 'Vision' ;;
    # 如果参数是 --xhttp，则执行快速安装 XHTTP
    --xhttp) exec_handler '--quick' 'XHTTP' ;;
    # 如果参数是 --fallback，则执行快速安装 Fallback
    --fallback) exec_handler '--quick' 'Fallback' ;;
    # 对于其他参数，进入主索引流程，并将第二个参数传递给它
    *) processes_index "$2" ;;
    esac
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
