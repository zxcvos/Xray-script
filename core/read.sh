#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: read.sh
# 功能描述: 根据传入的参数，从国际化 (i18n) 配置文件中读取对应的提示信息，
#           并从标准输入读取用户输入，返回用户输入的内容。
#           主要用于交互式配置脚本，提供多语言支持。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, jq, cut, sed
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
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json" # 脚本主要配置文件路径

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
# 函数名称: read_input
# 功能描述: 根据类型和消息内容，在终端打印格式化的提示信息。
# 参数:
#   $1: 类型 (type) - "config" 或 "rule"，决定提示信息的颜色和标题前缀
#   $2: 消息内容 (msg) - 具体的提示文本
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function read_input() {
    local type="$1"      # 获取类型参数
    local color="$GREEN" # 默认颜色为绿色
    # 从 i18n 数据中读取 "配置" 的标题
    local title="$(echo "$I18N_DATA" | jq -r '.title.config')"

    # 如果类型是 "rule"
    if [[ "$type" == "rule" ]]; then
        color="$YELLOW" # 设置颜色为黄色
        # 从 i18n 数据中读取 "路由规则" 的标题
        title="$(echo "$I18N_DATA" | jq -r '.title.route')"
    fi

    local msg="$2" # 获取消息内容参数

    # 如果类型是 "rule"，在消息后追加 "(可设置多个值)" 的提示
    if [[ "$type" == "rule" ]]; then
        msg="$msg ($(echo "$I18N_DATA" | jq -r '.title.multiple_values'))"
    fi

    # 使用指定颜色和标题打印提示信息到标准错误输出
    printf "${color}[${title}]${NC} ${msg} " >&2
}

# --- 参数映射表 ---
# 定义一个关联数组，将命令行选项映射到配置文件中的 JSON 路径。
# 键是命令行选项，值是用逗号分隔的类型和字段名。
# 类型用于 read_input 函数区分提示样式，字段名用于从 i18n 文件获取具体文本。
declare -A param_map=(
    ["--version"]="config,version"
    ["--rules"]="config,rules"
    ["--block-bt"]="config,block_bt"
    ["--block-cn"]="config,block_cn"
    ["--block-ad"]="config,block_ad"
    ["--auto-geo"]="config,auto_geo"
    ["--port"]="config,port"
    ["--uuid"]="config,uuid"
    ["--fallback"]="config,fallback"
    ["--seed"]="config,seed"
    ["--password"]="config,password"
    ["--target"]="config,target"
    ["--domain"]="config,domain"
    ["--cdn"]="config,cdn"
    ["--email"]="config,email"
    ["--short"]="config,short"
    ["--path"]="config,path"
    ["--warp-ip"]="rule,warp_ip"
    ["--warp-domain"]="rule,warp_domain"
    ["--block-ip"]="rule,block_ip"
    ["--block-domain"]="rule,block_domain"
)

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。
#           1. 加载国际化数据。
#           2. 检查传入的第一个参数是否在预定义的参数映射表中。
#           3. 如果存在，则解析其对应的类型和字段。
#           4. 从 i18n 数据中获取该字段的提示文本。
#           5. 对于特定参数 (--short)，额外打印一条提示信息。
#           6. 调用 read_input 显示提示。
#           7. 从标准输入读取用户输入并输出。
# 参数:
#   $1: 命令行选项 (例如 --port, --uuid)
#   $@: 剩余参数 (此脚本中未使用)
# 返回值: 用户输入的内容 (echo 输出)
# =============================================================================
function main() {
    # 加载国际化数据
    load_i18n

    # 检查传入的第一个参数是否存在于参数映射表中，如果不存在则直接返回
    [[ -z "${param_map[$1]}" ]] && return

    # 使用 IFS (Internal Field Separator) 将映射表中的值分割为 type 和 field
    IFS=',' read -r type field <<<"${param_map[$1]}"

    # 构造 i18n 文件中的键名 (例如: read.port, read.uuid)
    local key="${CUR_FILE}.${field}"

    # 从 i18n 数据中读取该键对应的提示文本
    local prompt=""
    prompt="$(echo "$I18N_DATA" | jq -r ".$key")"

    # 对于 --short 参数，额外打印一条关于 Short ID 格式的提示
    if [[ "$1" == "--short" ]]; then
        echo -e "${YELLOW}[$(echo "$I18N_DATA" | jq -r '.title.tip')]${NC} $(echo "$I18N_DATA" | jq -r '.read.short_id_tip')" >&2
    fi

    # 调用 read_input 函数显示提示信息
    read_input "$type" "$prompt"

    # 从标准输入读取一行用户输入
    read -r input

    # 输出用户输入的内容
    echo "$input"
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
