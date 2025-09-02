#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: handler.sh
# 功能描述: X-UI 项目的处理器脚本。
#           负责执行具体的操作，如安装/卸载 Xray/Nginx、配置文件生成、
#           启动/停止服务、管理 Docker 容器、处理路由规则等。
#           由 main.sh 调用，根据传入参数执行相应功能。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, jq, curl, systemctl, crontab, sed, awk, grep, cut, tr
# 配置:
#   - ${SCRIPT_CONFIG_DIR}/config.json: 读取和写入脚本配置 (如版本、域名、密钥等)
#   - ${I18N_DIR}/${lang}.json: 用于读取具体的提示文本 (i18n 数据文件)
#   - ${CONFIG_DIR}/xray/*.json: 读取 Xray 配置模板
#   - ${CONFIG_DIR}/nginx/conf/*: 读取 Nginx 配置模板
#   - /usr/local/etc/xray/config.json: 读取和写入 Xray 最终配置文件
#   - /usr/local/nginx/conf/*: 读取和写入 Nginx 最终配置文件
#   - ${HOME}/.acme.sh/: 读取和写入 SSL 证书相关文件
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

# 定义项目内相关目录和脚本的路径
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script" # 主配置文件目录
readonly I18N_DIR="${PROJECT_ROOT}/i18n"          # 国际化文件目录
readonly CONFIG_DIR="${PROJECT_ROOT}/config"      # 配置文件目录
readonly SERVICE_DIR="${PROJECT_ROOT}/service"    # 服务管理脚本目录
readonly TOOL_DIR="${PROJECT_ROOT}/tool"          # 工具脚本目录
readonly SCRIPT_XRAY_DIR="${CONFIG_DIR}/xray"     # Xray 配置模板目录
readonly NGINX_CONFIG_DIR="/usr/local/nginx/conf" # Nginx 配置目录 (目标路径)
# 定义项目内子脚本的路径
readonly GENERATE_PATH="${CUR_DIR}/generate.sh" # 生成器脚本
readonly CHECK_PATH="${CUR_DIR}/check.sh"       # 检查器脚本
readonly SHARE_PATH="${CUR_DIR}/share.sh"       # 分享链接生成脚本
readonly READ_PATH="${CUR_DIR}/read.sh"         # 用户输入读取脚本
readonly NGINX_PATH="${SERVICE_DIR}/nginx.sh"   # Nginx 服务管理脚本
readonly SSL_PATH="${SERVICE_DIR}/ssl.sh"       # SSL 证书管理脚本
readonly DOCKER_PATH="${SERVICE_DIR}/docker.sh" # Docker 容器管理脚本
readonly TRAFFIC_PATH="${TOOL_DIR}/traffic.sh"  # 流量统计脚本
readonly GEODATA_PATH="${TOOL_DIR}/geodata.sh"  # GeoData 更新脚本
# 定义外部配置文件和脚本的路径
readonly XRAY_CONFIG_PATH="/usr/local/etc/xray/config.json"    # Xray 最终配置文件路径
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json" # 脚本主配置文件路径
readonly ACME_PATH="${HOME}/.acme.sh/acme.sh"                  # ACME.sh 脚本路径

# --- 全局变量声明 ---
# 声明用于存储配置数据和国际化数据的全局变量
declare SCRIPT_CONFIG="$(jq '.' "${SCRIPT_CONFIG_PATH}")" # 存储从 config.json 读取的脚本配置
declare XRAY_CONFIG=""                                    # 存储 Xray 配置 (通常在运行时加载)
declare LANG_PARAM=''                                     # (未在脚本中实际使用，可能是预留)
declare I18N_DATA=''                                      # 存储从 i18n JSON 文件中读取的全部数据
# 声明一个关联数组，用于在脚本运行时临时存储用户输入的配置数据
declare -A CONFIG_DATA # 用于临时存储用户输入的配置数据

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
    printf "${RED}[$(echo "$I18N_DATA" | jq -r '.title.error')] ${NC}" >&2
    # 打印传入的错误信息
    printf -- "%s" "$@" >&2
    # 打印换行符
    printf "\n" >&2
    # 退出脚本，错误码为 1
    exit 1
}

# =============================================================================
# 函数名称: exec_generate
# 功能描述: 执行 generate.sh 脚本，用于生成 UUID、密码、密钥等。
# 参数:
#   $@: 传递给 generate.sh 脚本的参数
# 返回值: generate.sh 脚本的输出 (echo 输出)
# =============================================================================
function exec_generate() {
    # 执行 generate.sh 脚本，并传递所有参数
    bash "${GENERATE_PATH}" "$@"
}

# =============================================================================
# 函数名称: exec_docker
# 功能描述: 执行 docker.sh 脚本，用于管理 Docker 相关操作。
#           如果执行失败，则退出当前脚本。
# 参数:
#   $@: 传递给 docker.sh 脚本的参数
# 返回值: 无 (docker.sh 的退出码即为当前函数的退出码)
# 退出码: 如果 docker.sh 执行失败 (返回非 0)，则当前脚本也退出 (|| exit 1)
# =============================================================================
function exec_docker() {
    # 执行 docker.sh 脚本，并传递所有参数
    # 如果 docker.sh 返回非 0 状态码，则当前脚本也退出
    bash "${DOCKER_PATH}" "$@" || exit 1
}

# =============================================================================
# 函数名称: exec_ssl
# 功能描述: 执行 ssl.sh 脚本，用于管理 SSL 证书相关操作。
# 参数:
#   $@: 传递给 ssl.sh 脚本的参数
# 返回值: ssl.sh 脚本的退出码 (通过 return $? 返回)
# =============================================================================
function exec_ssl() {
    # 执行 ssl.sh 脚本，并传递所有参数
    bash "${SSL_PATH}" "$@"
    return $?
}

# =============================================================================
# 函数名称: exec_check
# 功能描述: 执行 check.sh 脚本，用于验证输入或配置的有效性。
# 参数:
#   $@: 传递给 check.sh 脚本的参数
# 返回值: check.sh 脚本的退出码 (通过 return $? 返回)
# =============================================================================
function exec_check() {
    # 执行 check.sh 脚本，并传递所有参数
    bash "${CHECK_PATH}" "$@"
    # 返回 check.sh 脚本的退出码
    return $?
}

# =============================================================================
# 函数名称: cmd_exists
# 功能描述: 检查系统中是否存在指定的命令。
# 参数:
#   $1: 要检查的命令名称
# 返回值: 无 (通过 return $rt 返回检查结果)
# 退出码: 0 (命令存在), 非 0 (命令不存在)
# =============================================================================
function cmd_exists() {
    local cmd="$1" # 获取要检查的命令名称
    local rt=0     # 初始化返回码为 0 (表示存在)
    # 尝试使用不同的方法检查命令是否存在
    if eval type type >/dev/null 2>&1; then
        # 使用 type 命令检查
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        # 使用 command -v 命令检查
        command -v "$cmd" >/dev/null 2>&1
    else
        # 使用 which 命令检查
        which "$cmd" >/dev/null 2>&1
    fi
    # 获取检查命令的退出码
    rt=$?
    # 返回检查结果
    return ${rt}
}

# =============================================================================
# 函数名称: exec_read
# 功能描述: 执行 read.sh 脚本读取用户输入，并进行验证。
#           1. 调用 read.sh 获取用户输入。
#           2. 根据输入类型，调用 check.sh 进行验证。
#           3. 对于特定输入（如 short），进行特殊处理和验证。
#           4. 将验证通过的输入存储到 CONFIG_DATA 关联数组中。
# 参数:
#   $1: 配置项名称 (对应 read.sh 的参数，如 port, uuid, domain 等)
# 返回值: 无 (直接修改全局变量 CONFIG_DATA)
# =============================================================================
function exec_read() {
    local opt="$1"  # 获取配置项名称
    local flag=true # 初始化循环标志为 true
    local result    # 声明用于存储 read.sh 输出的局部变量
    # 循环直到输入有效 (flag 为 false)
    while ${flag}; do
        # 调用 read.sh 脚本获取用户输入
        result="$(bash "${READ_PATH}" "--${opt}")"
        # 根据配置项名称进行特定验证
        case "${opt}" in
        version)
            # 验证 Xray 版本
            exec_check '--xray' "${result}" || continue
            ;;
        email)
            # 验证邮箱地址
            exec_check '--email' "${result}" || continue
            ;;
        block-bt | block-cn | block-ad)
            # 为阻止选项设置默认值 'Y'
            result="${result:-Y}"
            ;;
        rules)
            # 为规则选项设置默认值 'N'
            result="${result:-N}"
            ;;
        port)
            # 验证端口号
            exec_check '--port' "${result}" || continue
            ;;
        uuid | fallback)
            # 验证 UUID (fallback 也使用 uuid 验证)
            exec_check '--uuid' "${result}"
            ;;
        seed | password)
            # 验证密码或种子
            exec_check '--password' "${result}" || continue
            ;;
        target)
            # 验证目标域名
            exec_check '--domain' "${result}" || continue
            ;;
        domain | cdn)
            # 验证域名或 CDN 域名
            exec_check '--dns' "${result}" || continue
            # 如果是 'domain' 选项，同时设置 CONFIG_DATA['target']
            [[ "$1" == 'domain' ]] && CONFIG_DATA['target']="${result}"
            ;;
        short)
            # 特殊处理 Short IDs
            # 如果输入为空，进行验证 (可能是检查默认值)
            [[ -z "${result}" ]] && exec_check '--short' "${result}" && break
            # 将逗号分隔的输入分割成数组
            IFS=',' read -r -a values <<<"${result}"
            # 遍历每个 Short ID 进行验证
            for value in "${values[@]}"; do
                if exec_check '--short' "${value}"; then
                    # 验证通过则追加到 CONFIG_DATA['short_ids']
                    CONFIG_DATA['short_ids']="${CONFIG_DATA['short_ids']} ${value}"
                fi
            done
            ;;
        path)
            # 验证路径
            exec_check '--path' "${result}" || continue
            ;;
        esac
        # 输入验证通过，设置 flag 为 false 退出循环
        flag=false
    done
    # 将最终的用户输入结果存储到 CONFIG_DATA 关联数组中
    CONFIG_DATA["$1"]="${result}"
}

# =============================================================================
# 函数名称: reset_json_fields
# 功能描述: 重置 JSON 对象中指定键下的字段值。
#           1. 如果指定了目标键 ($2)，则只重置该键下的字段。
#           2. 如果未指定目标键，则重置整个 JSON 对象的字段。
#           3. 保留指定的字段 ($3, $4, ...) 不变，其他字段根据类型重置为空值。
# 参数:
#   $1: 原始 JSON 字符串
#   $2: 目标键名 (例如 'xray' 或 'nginx')，如果为 "null" 则重置整个对象
#   $@: (从 $3 开始) 需要保留的字段名列表
# 返回值: 重置后的 JSON 字符串 (echo 输出)
# =============================================================================
function reset_json_fields() {
    local raw_json="$1"   # 获取原始 JSON 字符串
    local target_key="$2" # 获取目标键名
    # 移除前两个参数，剩下的就是需要保留的字段名
    shift 2
    local keep_fields=("$@") # 获取需要保留的字段名数组
    # 将保留字段名数组转换为 jq 可用的 JSON 数组
    local jq_keep=$(printf '%s\n' "${keep_fields[@]}" | jq -R . | jq -s .)
    # 使用 jq 脚本进行重置操作
    raw_json=$(echo "${raw_json}" | jq --arg key "${target_key}" --argjson keep "$jq_keep" '
        # 定义递归函数 clear_recursive，用于清空值
        def clear_recursive:
            if type == "object" then with_entries(.value |= clear_recursive)
            elif type == "array" then map(clear_recursive) | unique
            elif type == "number" then 0
            elif type == "boolean" then false
            else ""
            end;
        # 定义函数 exec_clear，用于判断字段是否需要保留
        def exec_clear:
            if .key | IN($keep[]) then .
            else .value |= clear_recursive
            end;
        # 根据是否指定了目标键来决定重置范围
        if $key != "null" then .[$key] |= with_entries(exec_clear)
        else . |= with_entries(exec_clear)
        end
    ')
    # 输出重置后的 JSON 字符串
    echo "${raw_json}"
}

# =============================================================================
# 函数名称: add_rule
# 功能描述: 在 Xray 配置的 routing.rules 中添加或更新路由规则。
#           1. 检查是否存在具有相同 ruleTag 的规则。
#           2. 如果存在且是 domain 或 ip 规则，则追加新值。
#           3. 如果不存在，则创建新规则。
#           4. 新规则可以插入到指定位置或相对于其他规则的位置。
#           5. 更新后的配置写入 XRAY_CONFIG_PATH 文件。
# 参数:
#   $1: rule_tag - 规则标签 (ruleTag)，用于唯一标识规则
#   $2: domain_or_ip - 规则类型 ("domain" 或 "ip")
#   $3: value - 要添加的值 (可以是逗号分隔的多个值)
#   $4: outboundTag - 出站标签 (例如 "block", "warp")
#   $5: position - (可选) 插入位置或相对于 target_tag 的位置 ("before", "after", 数字索引)
#   $6: target_tag - (可选) 用于定位插入位置的参考规则标签
# 返回值: 无 (直接修改 XRAY_CONFIG_PATH 文件)
# =============================================================================
function add_rule() {
    local rule_tag=$1     # 获取规则标签
    local domain_or_ip=$2 # 获取规则类型 (domain/ip)
    # 将逗号分隔的值转换为 JSON 数组
    local value=$(echo "$3" | tr ',' '\n' | jq -R | jq -s)
    local outboundTag=$4 # 获取出站标签
    local position=$5    # 获取插入位置参数
    local target_tag=$6  # 获取目标规则标签参数
    # 如果 XRAY_CONFIG 未初始化，则从文件加载
    XRAY_CONFIG="${XRAY_CONFIG:-$(jq '.' "${XRAY_CONFIG_PATH}")}"
    # 检查是否存在具有相同 ruleTag 的规则
    local existing_rule=$(echo "${XRAY_CONFIG}" | jq -r --arg ruleTag "${rule_tag}" '.routing.rules[] | select(.ruleTag == $ruleTag)')
    # 如果规则已存在
    if [[ "${existing_rule}" ]]; then
        # 如果是 domain 规则
        if [[ "${domain_or_ip}" == "domain" ]]; then
            # 将新值追加到现有 domain 数组并去重
            XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg ruleTag "${rule_tag}" --argjson value "${value}" '.routing.rules |= map(if .ruleTag == $ruleTag then .domain += $value | .domain |= unique else . end)')"
        # 如果是 ip 规则
        elif [[ "${domain_or_ip}" == "ip" ]]; then
            # 将新值追加到现有 ip 数组并去重
            XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg ruleTag "${rule_tag}" --argjson value "${value}" '.routing.rules |= map(if .ruleTag == $ruleTag then .ip += $value | .ip |= unique else . end)')"
        fi
    else
        # 规则不存在，创建新的规则 JSON 对象
        local new_rule="[{\"ruleTag\":\"${rule_tag}\",\"${domain_or_ip}\":${value},\"outboundTag\":\"${outboundTag}\"}]"
        # 如果指定了 target_tag
        if [[ -n "${target_tag}" ]]; then
            # 检查 target_tag 对应的规则是否存在
            local target_rule=$(echo "${XRAY_CONFIG}" | jq -r --arg ruleTag "${target_tag}" '.routing.rules[] | select(.ruleTag == $ruleTag)')
            if [[ "${target_rule}" ]]; then
                # 获取 target_tag 对应规则的索引
                local target_index=$(echo "${XRAY_CONFIG}" | jq -r --arg ruleTag "${target_tag}" '.routing.rules | to_entries | map(select(.value.ruleTag == $ruleTag)) | .[0].key')
                # 根据 position 参数决定插入位置
                if [[ "${position}" == "before" ]]; then
                    # 插入到 target_tag 规则之前
                    XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson target_index "${target_index}" --argjson new_rule "${new_rule}" '.routing.rules |= .[:$target_index] + $new_rule + .[$target_index:]')"
                elif [[ "${position}" == "after" ]]; then
                    # 插入到 target_tag 规则之后
                    XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson target_index $((target_index + 1)) --argjson new_rule "${new_rule}" '.routing.rules |= .[:$target_index] + $new_rule + .[$target_index:]')"
                else
                    # 默认追加到末尾
                    XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson new_rule "${new_rule}" '.routing.rules += $new_rule')"
                fi
            else
                # target_tag 规则不存在，追加到末尾
                XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson new_rule "${new_rule}" '.routing.rules += $new_rule')"
            fi
        else
            # 未指定 target_tag
            # 如果指定了数字位置
            if [[ -n "${position}" && "${position}" -ge 0 ]]; then
                # 插入到指定索引位置
                XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson position "${position}" --argjson new_rule "${new_rule}" '.routing.rules |= .[:$position] + $new_rule + .[$position:]')"
            else
                # 默认追加到末尾
                XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson new_rule "${new_rule}" '.routing.rules += $new_rule')"
            fi
        fi
    fi
    # 将更新后的 Xray 配置写入文件
    echo "${XRAY_CONFIG}" >"${XRAY_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_routing
# 功能描述: 处理路由规则配置的处理器。
#           1. 检查 WARP 状态是否满足配置要求。
#           2. 调用 exec_read 读取用户输入的规则值。
#           3. 调用 add_rule 将规则添加到 Xray 配置中。
# 参数:
#   $1: rule_type - 规则类型 ("block" 或 "warp")
#   $2: rule_target - 规则目标 ("ip" 或 "domain")
# 返回值: 无 (通过调用其他函数执行操作)
# 退出码: 如果 WARP 状态不满足要求，则调用 _error 退出脚本 (exit 1)
# =============================================================================
function handler_routing() {
    # 从脚本配置中读取 WARP 状态
    local WARP_STATUS="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp')"
    local rule_type="$1"                         # 获取规则类型 (block/warp)
    local rule_target="$2"                       # 获取规则目标 (ip/domain)
    local rule_tag="${rule_type}-${rule_target}" # 构造规则标签
    # 检查 WARP 状态是否满足配置要求
    # 如果是 warp 规则但 WARP 未启用，则报错
    if [[ "${rule_type}" == 'warp' && ${WARP_STATUS} -ne 1 ]]; then
        _error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.warp.status")"
    fi
    # 调用 exec_read 读取用户输入的规则值
    exec_read "${rule_tag}"
    # 调用 add_rule 将规则添加到 Xray 配置中
    add_rule "${rule_tag}" "${rule_target}" "${XRAY_CONFIG[${rule_tag}]}" "${rule_type}"
}

# =============================================================================
# 函数名称: handler_reset_script_config
# 功能描述: 重置脚本配置文件 (config.json) 中指定部分的字段。
#           1. 根据目标配置部分 (xray/nginx) 调用 reset_json_fields。
#           2. 保留特定字段不变，其他字段清空。
#           3. 将重置后的配置写回 SCRIPT_CONFIG_PATH 文件。
# 参数:
#   $1: TARGET_CONFIG - 目标配置部分 ("xray" 或 "nginx")，默认为 "xray"
# 返回值: 无 (直接修改 SCRIPT_CONFIG 全局变量和 SCRIPT_CONFIG_PATH 文件)
# =============================================================================
function handler_reset_script_config() {
    local TARGET_CONFIG="${1:-xray}" # 获取目标配置部分，默认为 xray
    # 根据目标配置部分调用 reset_json_fields 进行重置
    case "${TARGET_CONFIG,,}" in
    xray)
        # 重置 xray 部分，保留 version, warp, rules 字段
        SCRIPT_CONFIG=$(reset_json_fields "${SCRIPT_CONFIG}" 'xray' 'version' 'warp' 'rules')
        ;;
    nginx)
        # 重置 nginx 部分，保留 version, ca 字段
        SCRIPT_CONFIG=$(reset_json_fields "${SCRIPT_CONFIG}" 'nginx' 'version' 'ca')
        ;;
    esac
    # 将重置后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_script_config
# 功能描述: 处理并更新脚本配置文件 (config.json)。
#           1. 打印配置更新提示。
#           2. 调用 handler_reset_script_config 重置配置。
#           3. 从 CONFIG_DATA 中获取或生成配置值。
#           4. 根据配置标签 (tag) 更新不同的字段。
#           5. 将更新后的配置写回 SCRIPT_CONFIG_PATH 文件。
# 参数:
#   $1: CONFIG_TAG - 配置标签 (例如 Vision, XHTTP, SNI 等)，默认从 CONFIG_DATA 获取
# 返回值: 无 (直接修改 SCRIPT_CONFIG 全局变量和 SCRIPT_CONFIG_PATH 文件)
# =============================================================================
function handler_script_config() {
    # 打印绿色的配置更新提示
    echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.config')]${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.script.config_update")" >&2
    # 重置脚本配置 (默认重置 xray 部分)
    handler_reset_script_config
    # 从 CONFIG_DATA 或生成器获取配置值
    # 获取配置标签
    local CONFIG_TAG="${1:-${CONFIG_DATA['tag']}}"
    # 获取规则状态
    local XRAY_RULES_STATUS="${CONFIG_DATA['rules']}"
    # 获取 block bt 状态
    local XRAY_RULES_BT="${CONFIG_DATA['block-bt']}"
    # 获取 block cn 状态
    local XRAY_RULES_CN="${CONFIG_DATA['block-cn']}"
    # 获取 block ad 状态
    local XRAY_RULES_AD="${CONFIG_DATA['block-ad']}"
    # 获取端口，默认 443
    local XRAY_PORT="${CONFIG_DATA['port']:-443}"
    # 获取或生成 UUID
    local XRAY_UUID="$(exec_generate '--uuid' ${CONFIG_DATA['uuid']})"
    # 获取或生成 Fallback UUID
    local FALLBACK_UUID="${CONFIG_DATA['fallback']:-$(exec_generate '--uuid')}"
    # 获取或生成 Trojan 密码
    local TROJAN_PASSWORD="${CONFIG_DATA['password']:-$(exec_generate '--password')}"
    # 获取或生成 mKCP Seed
    local KCP_SEED="${CONFIG_DATA['seed']:-$(exec_generate '--password')}"
    # 获取或生成 XHTTP 路径
    local XHTTP_PATH="${CONFIG_DATA['path']:-$(exec_generate '--path')}"
    # 获取或生成目标域名
    local TARGET_DOMAIN="${CONFIG_DATA['target']:-$(exec_generate '--target')}"
    # 生成服务器名称列表
    local SERVER_NAMES="$(exec_generate '--server-names' "${TARGET_DOMAIN}")"
    # 获取 CDN 域名
    local CDN_DOMAIN="${CONFIG_DATA['cdn']}"
    # 获取或生成 Short IDs
    local SHORT_IDS="$(exec_generate '--short-ids' ${CONFIG_DATA['short_ids']:-'8 8'})"
    # 获取 CA 邮箱
    local CA_EMAIL="${CONFIG_DATA['email']}"
    # 更新脚本配置中的规则状态
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg reset "${XRAY_RULES_STATUS,,}" ' if $reset != "n" then .xray.rules.reset = 1 else .xray.rules.reset = 0 end ')"
    # 更新脚本配置中的 block bt 状态
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg bt "${XRAY_RULES_BT,,}" ' if $bt != "n" then .xray.rules.bt = 1 else .xray.rules.bt = 0 end ')"
    # 更新脚本配置中的 block cn 状态
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg cn "${XRAY_RULES_CN,,}" ' if $cn != "n" then .xray.rules.cn = 1 else .xray.rules.cn = 0 end ')"
    # 更新脚本配置中的 block ad 状态
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg ad "${XRAY_RULES_AD,,}" ' if $ad != "n" then .xray.rules.ad = 1 else .xray.rules.ad = 0 end ')"
    # 根据配置标签更新特定字段
    case "${CONFIG_TAG,,}" in
    trojan)
        # 更新 Trojan 密码
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg password "${TROJAN_PASSWORD}" '.xray.trojan = $password')"
        ;;
    mkcp | vision | xhttp | fallback | sni)
        # 更新 UUID
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg uuid "${XRAY_UUID}" '.xray.uuid = $uuid')"
        ;;
    esac
    # 根据配置标签更新特定字段 (第二部分)
    case "${CONFIG_TAG,,}" in
    fallback)
        # 更新 Fallback UUID
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg uuid "${FALLBACK_UUID}" '.xray.fallback = $uuid')"
        ;;
    mkcp)
        # 为 mKCP 生成随机端口并更新 Seed
        XRAY_PORT="$(exec_generate '--port')"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg seed "${KCP_SEED}" '.xray.kcp = $seed')"
        ;;
    sni)
        # 更新 Fallback UUID
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg uuid "${FALLBACK_UUID}" '.xray.fallback = $uuid')"
        # 为 SNI 更新 CA 邮箱、域名和 CDN
        [[ -n "${CA_EMAIL}" ]] && SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg ca "${CA_EMAIL}" '.nginx.ca = $ca')"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg domain "${TARGET_DOMAIN}" '.nginx.domain = $domain')"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg cdn "${CDN_DOMAIN}" '.nginx.cdn = $cdn')"
        ;;
    esac
    # 根据配置标签更新特定字段 (第三部分)
    case "${CONFIG_TAG,,}" in
    xhttp | trojan | fallback | sni)
        # 更新路径
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg path "${XHTTP_PATH}" '.xray.path = $path')"
        ;;
    esac
    # 根据配置标签更新特定字段 (第四部分)
    case "${CONFIG_TAG,,}" in
    vision | xhttp | trojan | fallback | sni)
        # 更新目标域名、服务器名称和 Short IDs
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg target "${TARGET_DOMAIN}" '.xray.target = $target')"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson serverNames "${SERVER_NAMES}" '.xray.serverNames = $serverNames')"
        SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson shortIds "${SHORT_IDS}" '.xray.shortIds = $shortIds')"
        ;;
    esac
    # 更新配置标签和端口
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg tag "${CONFIG_TAG}" '.xray.tag = $tag')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson port "${XRAY_PORT}" '.xray.port = $port')"
    # 将更新后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_x25519_config
# 功能描述: 处理并更新脚本配置文件 (config.json)。
#           1. 获取 X25519 密钥对。
#           2. 将 X25519 密钥对写入 SCRIPT_CONFIG_PATH 文件。
# 参数: 无
# 返回值: 无 (直接修改 SCRIPT_CONFIG 全局变量和 SCRIPT_CONFIG_PATH 文件)
# =============================================================================
function handler_x25519_config() {
    # 打印绿色的配置更新提示
    echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.config')]${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.script.config_update")" >&2
    # 生成 X25519 密钥对
    local X25519="$(exec_generate '--x25519')"
    # 提取私钥
    local PRIVATE_KEY="$(echo "${X25519}" | awk -F, '{print $1}')"
    # 提取公钥
    local PUBLIC_KEY="$(echo "${X25519}" | awk -F, '{print $2}')"
    # 提取 Hash32
    local HASH32="$(echo "${X25519}" | awk -F, '{print $3}')"
    # 输出显示 x25519 密钥对
    echo -e "${GREEN}[Private Key]${NC} "${PRIVATE_KEY}"" >&2
    echo -e "${GREEN}[Public Key]${NC} "${PUBLIC_KEY}"" >&2
    echo -e "${GREEN}[Hash32]${NC} "${HASH32}"" >&2
    # 更新脚本配置中的私钥和公钥，以及哈希值
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg privateKey "${PRIVATE_KEY}" '.xray.privateKey = $privateKey')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg publicKey "${PUBLIC_KEY}" '.xray.publicKey = $publicKey')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg hash32 "${HASH32}" '.xray.hash32 = $hash32')"
    # 将更新后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_xray_config
# 功能描述: 处理并更新 Xray 核心配置文件 (/usr/local/etc/xray/config.json)。
#           1. 打印配置更新提示。
#           2. 从脚本配置中读取各项参数。
#           3. 加载对应配置标签的模板文件。
#           4. 根据配置标签和参数替换模板中的占位符。
#           5. 处理路由规则 (保留当前规则或重置并添加默认规则)。
#           6. 将更新后的配置写回 XRAY_CONFIG_PATH 和 SCRIPT_CONFIG_PATH 文件。
# 参数: 无
# 返回值: 无 (直接修改 XRAY_CONFIG 全局变量和 XRAY_CONFIG_PATH/SCRIPT_CONFIG_PATH 文件)
# =============================================================================
function handler_xray_config() {
    # 打印绿色的 Xray 配置更新提示
    echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.config')]${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray.config_update")" >&2
    # 从脚本配置中读取各项参数
    local CONFIG_TAG="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag')"                # 获取配置标签
    local XRAY_PORT="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.port')"                # 获取端口
    local XRAY_UUID="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.uuid')"                # 获取 UUID
    local FALLBACK_UUID="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.fallback')"        # 获取 Fallback UUID
    local TROJAN_PASSWORD="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.trojan')"        # 获取 Trojan 密码
    local KCP_SEED="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.kcp')"                  # 获取 mKCP Seed
    local TARGET_DOMAIN="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.target')"          # 获取目标域名
    local SERVER_NAMES="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.serverNames')"      # 获取服务器名称
    local PRIVATE_KEY="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.privateKey')"        # 获取私钥
    local SHORT_IDS="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.shortIds')"            # 获取 Short IDs
    local XHTTP_PATH="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.path')"               # 获取路径
    local XRAY_RULES_STATUS="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.rules.reset')" # 获取规则状态
    local XRAY_RULES_BT="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.rules.bt')"        # 获取 bt 规则状态
    local XRAY_RULES_CN="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.rules.cn')"        # 获取 cn 规则状态
    local XRAY_RULES_AD="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.rules.ip')"        # 获取 ad 规则状态
    local XRAY_RULES="$(echo "${SCRIPT_CONFIG}" | jq -r '.rules')"                   # 获取路由规则
    # 加载对应配置标签的 Xray 配置模板
    XRAY_CONFIG="$(jq '.' ${SCRIPT_XRAY_DIR}/${CONFIG_TAG}.json)"
    # 如果配置标签不是 sni，则更新端口
    if [[ "${CONFIG_TAG,,}" != 'sni' ]]; then
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson port "${XRAY_PORT}" '.inbounds[1].port = $port')"
    fi
    # 根据配置标签更新特定字段 (第一部分)
    case "${CONFIG_TAG,,}" in
    mkcp | vision | xhttp | fallback | sni)
        # 更新客户端 UUID
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg uuid "${XRAY_UUID}" '.inbounds[1].settings.clients[0].id = $uuid')"
        ;;
    trojan)
        # 更新 Trojan 客户端密码
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg password "${TROJAN_PASSWORD}" '.inbounds[1].settings.clients[0].password = $password')"
        ;;
    esac
    # 根据配置标签更新特定字段 (第二部分)
    case "${CONFIG_TAG,,}" in
    mkcp)
        # 更新 mKCP Seed
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg seed "${KCP_SEED}" '.inbounds[1].streamSettings.kcpSettings.seed = $seed')"
        ;;
    vision | xhttp | trojan | fallback | sni)
        # 如果不是 sni 配置，更新 Reality 目标
        if [[ "${CONFIG_TAG,,}" != 'sni' ]]; then
            XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg target "${TARGET_DOMAIN}:443" '.inbounds[1].streamSettings.realitySettings.target = $target')"
        fi
        # 更新 Reality 服务器名称、私钥和 Short IDs
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson serverNames "${SERVER_NAMES}" '.inbounds[1].streamSettings.realitySettings.serverNames = $serverNames')"
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg privateKey "${PRIVATE_KEY}" '.inbounds[1].streamSettings.realitySettings.privateKey = $privateKey')"
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson shortIds "${SHORT_IDS}" '.inbounds[1].streamSettings.realitySettings.shortIds = $shortIds')"
        ;;
    esac
    # 根据配置标签更新特定字段 (第三部分)
    case "${CONFIG_TAG,,}" in
    xhttp | trojan)
        # 更新 XHTTP 路径
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg path "${XHTTP_PATH}" '.inbounds[1].streamSettings.xhttpSettings.path = $path')"
        ;;
    fallback | sni)
        # 更新 Fallback 客户端 UUID 和 XHTTP 路径
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg uuid "${FALLBACK_UUID}" '.inbounds[2].settings.clients[0].id = $uuid')"
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --arg path "${XHTTP_PATH}" '.inbounds[2].streamSettings.xhttpSettings.path = $path')"
        ;;
    esac
    # 处理路由规则
    case "${XRAY_RULES_STATUS}" in
    0)
        # 保留当前路由规则
        XRAY_CONFIG="$(echo "${XRAY_CONFIG}" | jq --argjson rules "${XRAY_RULES}" '.routing.rules = $rules')"
        ;;
    1)
        # 重置并添加默认路由规则
        [[ "${XRAY_RULES_BT}" -eq 1 ]] && add_rule "bt" "protocol" "bittorrent" "block" 1
        [[ "${XRAY_RULES_CN}" -eq 1 ]] && add_rule "cn-ip" "ip" "geoip:cn" "block" "after" "private-ip"
        [[ "${XRAY_RULES_AD}" -eq 1 ]] && add_rule "ad-domain" "domain" "geosite:category-ads-all" "block"
        ;;
    esac
    # 获取更新后的路由规则
    XRAY_RULES="$(echo "${XRAY_CONFIG}" | jq '.routing.rules')"
    # 更新脚本配置中的路由规则
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --argjson rules "${XRAY_RULES}" '.rules = $rules')"
    # 将更新后的脚本配置和 Xray 配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
    echo "${XRAY_CONFIG}" >"${XRAY_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_read_xray_config
# 功能描述: 读取 Xray 配置所需的用户输入。
#           1. 验证配置标签的有效性。
#           2. 根据脚本配置决定是否需要读取规则相关输入。
#           3. 根据配置标签读取对应的各项配置参数。
# 参数:
#   $1: CONFIG_TAG - 配置标签 (例如 Vision, XHTTP, SNI 等)
# 返回值: 无 (直接修改 CONFIG_DATA 全局关联数组)
# 退出码: 如果配置标签无效，则退出脚本 (exit 1)
# =============================================================================
function handler_read_xray_config() {
    local CONFIG_TAG="${1}" # 获取配置标签
    # 验证配置标签的有效性，无效则退出
    if ! exec_check '--tag' "${CONFIG_TAG}"; then
        exit 1
    fi
    # 将配置标签存储到 CONFIG_DATA
    CONFIG_DATA['tag']="${CONFIG_TAG}"
    # 检查脚本配置中的规则状态，如果是 current 或 reset 则读取规则输入
    if echo "${SCRIPT_CONFIG}" | jq -r '.xray.rules.reset' | grep -Eq '^(0|1)$'; then
        exec_read 'rules'
    fi
    # 如果规则状态不是 'n'，则读取阻止选项
    if [[ "${CONFIG_DATA['rules'],,}" != 'n' ]]; then
        exec_read 'block-bt'
        exec_read 'block-cn'
        exec_read 'block-ad'
    fi
    # 读取端口
    exec_read 'port'
    # 根据配置标签读取特定参数 (第一部分)
    case "${CONFIG_TAG,,}" in
    trojan) exec_read 'password' ;;                             # 读取 Trojan 密码
    mkcp | vision | xhttp | fallback | sni) exec_read 'uuid' ;; # 读取 UUID
    esac
    # 根据配置标签读取特定参数 (第二部分)
    case "${CONFIG_TAG,,}" in
    fallback | sni) exec_read 'fallback' ;; # 读取 Fallback UUID
    mkcp) exec_read 'seed' ;;               # 读取 mKCP Seed
    esac
    # 根据配置标签读取特定参数 (第三部分)
    case "${CONFIG_TAG,,}" in
    vision | xhttp | trojan | fallback) exec_read 'target' ;; # 读取目标域名
    sni)
        # 为 SNI 配置读取域名和 CDN
        local CA_EMAIL="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.ca')"
        # 如果 CA 邮箱为空，则读取邮箱
        [[ -z "${CA_EMAIL}" ]] && exec_read 'email'
        exec_read 'domain' # 读取域名
        exec_read 'cdn'    # 读取 CDN
        ;;
    esac
    # 根据配置标签读取特定参数 (第四部分)
    case "${CONFIG_TAG,,}" in
    vision | xhttp | trojan | fallback | sni) exec_read 'short' ;; # 读取 Short IDs
    esac
    # 根据配置标签读取特定参数 (第五部分)
    case "${CONFIG_TAG,,}" in
    xhttp | trojan | fallback | sni) exec_read 'path' ;; # 读取路径
    esac
}

# =============================================================================
# 函数名称: handler_sni_config
# 功能描述: 处理 SNI 配置相关的特殊操作。
#           1. 根据当前配置标签决定是否需要停止相关服务。
#           2. 如果是 SNI 配置，则调用 handler_web 配置 Web 服务。
# 参数:
#   $1: web - Web 服务类型 (normal, v3, v4)
# 返回值: 无 (通过调用其他函数执行操作)
# =============================================================================
function handler_sni_config() {
    # 从脚本配置中读取当前配置标签
    local CONFIG_TAG="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag')"
    local web="${1}" # 获取 Web 服务类型参数
    # 根据当前配置标签执行不同操作
    case "${CONFIG_TAG,,}" in
    mkcp | vision | xhttp | trojan | fallback)
        # 对于非 SNI 配置，停止 Cloudreve 和 Nginx 服务
        handler_cloudreve_v3 'stop'
        handler_cloudreve_v4 'stop'
        handler_nginx_stop
        ;;
    sni)
        # 为域名和 CDN 配置 Nginx 和 SSL
        handler_change_domain 'domain' 'n'
        handler_change_domain 'cdn' 'n'
        # 对于 SNI 配置，调用 handler_web 配置 Web 服务
        handler_web "${web}"
        ;;
    esac
}

# =============================================================================
# 函数名称: handler_xray_version
# 功能描述: 处理 Xray 版本配置。
#           1. 根据输入参数确定 Xray 版本。
#           2. 从 GitHub API 获取最新版本或自定义版本。
#           3. 将版本信息更新到脚本配置中。
# 参数:
#   $1: xray_version - 版本指定 ("latest", "custom", 或具体版本号)，默认为 release
# 返回值: 无 (直接修改 CONFIG_DATA 和 SCRIPT_CONFIG 全局变量)
# =============================================================================
function handler_xray_version() {
    local xray_version="$1" # 获取版本指定参数
    # 根据版本指定参数确定具体版本
    case "${xray_version,,}" in
    latest)
        # 获取最新的 Xray 版本
        CONFIG_DATA['version']="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name')"
        ;;
    custom)
        # 读取用户自定义的版本
        exec_read 'version'
        ;;
    *)
        # 获取最新的 release 版本
        CONFIG_DATA['version']="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.tag_name')"
        ;;
    esac
    # 更新脚本配置中的 Xray 版本
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg xray "${CONFIG_DATA['version']}" '.xray.version = $xray')"
    # 将更新后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_install
# 功能描述: 安装 Xray 核心。
#           1. 确定要安装的 Xray 版本。
#           2. 检查系统中是否已安装 Xray。
#           3. 如果未安装或强制安装，则从 Xray-install 脚本安装。
# 参数:
#   $1: xray_version - (可选) 要安装的 Xray 版本
#   $2: force_install - (可选) 是否强制安装 ('y' 表示强制)，默认为 'n'
# 返回值: 无 (通过调用外部脚本执行安装)
# =============================================================================
function handler_install() {
    local xray_version="$1"       # 获取版本参数
    local force_install="${2:-n}" # 获取强制安装参数，默认为 'n'
    # 如果提供了版本参数，则处理版本配置
    if [[ -n "${xray_version}" ]]; then
        handler_xray_version "${xray_version}"
    else
        # 否则从脚本配置中读取版本
        CONFIG_DATA['version']="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.version')"
    fi
    # 检查 Xray 命令是否存在，或是否强制安装
    if ! cmd_exists 'xray' || [[ "${force_install}" != n ]]; then
        # 调用 Xray-install 脚本进行安装
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --version "${CONFIG_DATA['version']}"
    fi
}

# =============================================================================
# 函数名称: handler_purge
# 功能描述: 卸载 Xray 核心及其配置。
# 参数: 无
# 返回值: 无 (通过调用外部脚本执行卸载)
# =============================================================================
function handler_purge() {
    # 调用 Xray-install 脚本进行卸载 (带 --purge 参数)
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    # 重置 xray 字段
    SCRIPT_CONFIG=$(reset_json_fields "${SCRIPT_CONFIG}" 'xray')
    # 将重置后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_start
# 功能描述: 启动 Xray 服务。
#           1. 检查 Xray 服务是否已在运行。
#           2. 如果未运行则启动服务。
#           3. 检查 Xray 服务是否已设置开机自启。
#           4. 如果未设置则启用开机自启。
# 参数: 无
# 返回值: 无 (通过 systemctl 命令执行操作)
# =============================================================================
function handler_start() {
    # 检查 Xray 服务是否活跃，如果不活跃则启动
    systemctl -q is-active xray || systemctl -q start xray
    # 检查 Xray 服务是否已启用，如果未启用则启用
    systemctl -q is-enabled xray || systemctl -q enable xray
}

# =============================================================================
# 函数名称: handler_stop
# 功能描述: 停止 Xray 服务。
#           1. 检查 Xray 服务是否正在运行。
#           2. 如果正在运行则停止服务。
#           3. 检查 Xray 服务是否已设置开机自启。
#           4. 如果已设置则禁用开机自启。
# 参数: 无
# 返回值: 无 (通过 systemctl 命令执行操作)
# =============================================================================
function handler_stop() {
    # 检查 Xray 服务是否活跃，如果活跃则停止
    systemctl -q is-active xray && systemctl -q stop xray
    # 检查 Xray 服务是否已启用，如果启用则禁用
    systemctl -q is-enabled xray && systemctl -q disable xray
}

# =============================================================================
# 函数名称: handler_restart
# 功能描述: 重启 Xray 服务。
#           1. 检查 Xray 服务是否正在运行。
#           2. 如果正在运行则重启服务，否则启动服务。
#           3. 检查 Xray 服务是否已设置开机自启。
#           4. 如果未设置则启用开机自启。
# 参数: 无
# 返回值: 无 (通过 systemctl 命令执行操作)
# =============================================================================
function handler_restart() {
    # 检查 Xray 服务是否活跃，如果活跃则重启，否则启动
    systemctl -q is-active xray && systemctl -q restart xray || systemctl -q start xray
    # 检查 Xray 服务是否已启用，如果未启用则启用
    systemctl -q is-enabled xray || systemctl -q enable xray
}

# =============================================================================
# 函数名称: handler_share
# 功能描述: 调用 share.sh 脚本显示分享链接。
# 参数: 无
# 返回值: share.sh 脚本的输出
# =============================================================================
function handler_share() {
    # 执行 share.sh 脚本
    bash "${SHARE_PATH}"
}

# =============================================================================
# 函数名称: handler_traffic
# 功能描述: 调用 traffic.sh 脚本显示流量统计。
# 参数: 无
# 返回值: traffic.sh 脚本的输出
# =============================================================================
function handler_traffic() {
    # 执行 traffic.sh 脚本
    bash "${TRAFFIC_PATH}"
}

# =============================================================================
# 函数名称: handler_geodata_cron
# 功能描述: 管理 GeoData 更新的 Cron 任务。
#           1. 检查 Xray 是否已安装。
#           2. 如果是快速模式 (IS_QUICK=1)，则直接更新 GeoData。
#           3. 否则，检查 Cron 任务是否存在。
#           4. 如果存在则移除，如果不存在则添加，并立即执行一次更新。
# 参数:
#   $1: IS_QUICK - 是否为快速模式 (1 表示是, 0 表示否)，默认为 0
# 返回值: 无 (通过 crontab 命令管理任务，调用 geodata.sh 执行更新)
# =============================================================================
function handler_geodata_cron() {
    local IS_QUICK="${1:-0}" # 获取快速模式参数，默认为 0
    # 从脚本配置中检查 Xray 状态 (版本)
    local XRAY_STATUS="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.version')"
    # 如果 Xray 已安装
    if ! [[ -z "${XRAY_STATUS}" ]]; then
        # 如果是快速模式
        if (("${IS_QUICK}" == 0)) && crontab -l | grep -q "${GEODATA_PATH}"; then
            # 移除现有的 GeoData Cron 任务
            crontab -l | grep -v "${GEODATA_PATH}" | crontab -
            # 打印关闭 Cron 任务的提示
            echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.tip')] ${NC}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.geodata.close_cron")" >&2
        else
            # 设置 geodata.sh 脚本为可执行
            chmod a+x "${GEODATA_PATH}"
            # 添加新的 GeoData Cron 任务 (每天 6:30 执行)
            (
                crontab -l 2>/dev/null
                echo "30 6 * * * ${GEODATA_PATH} >/dev/null 2>&1"
            ) | awk '!x[$0]++' | crontab -
            # 打印开启 Cron 任务的提示
            echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.tip')] ${NC}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.geodata.update")" >&2
            # 立即执行一次 GeoData 更新
            ${GEODATA_PATH}
            # 打印已开启 Cron 任务的提示
            echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.tip')] ${NC}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.geodata.open_cron")" >&2
        fi
    fi
}

# =============================================================================
# 函数名称: handler_docker
# 功能描述: 确保 Docker 已安装。
#           1. 检查系统中是否存在 docker 命令。
#           2. 如果不存在，则调用 exec_docker 安装 Docker。
# 参数: 无
# 返回值: 无 (通过调用其他函数执行操作)
# =============================================================================
function handler_docker() {
    # 检查 docker 命令是否存在
    if ! cmd_exists 'docker'; then
        # 如果不存在，则调用 docker.sh 安装 Docker
        exec_docker '--install'
    fi
}

# =============================================================================
# 函数名称: handler_warp
# 功能描述: 管理 WARP (WireGuard) 配置。
#           1. 确保 Docker 已安装。
#           2. 检查当前 WARP 状态。
#           3. 如果已启用，则禁用并从 Xray 配置中移除相关规则。
#           4. 如果未启用，则启用并添加 WARP 出站和路由规则到 Xray 配置。
#           5. 更新脚本配置中的 WARP 状态。
# 参数: 无
# 返回值: 无 (通过调用其他函数和脚本执行操作，修改配置文件)
# =============================================================================
function handler_warp() {
    # 确保 Docker 已安装
    handler_docker
    # 从脚本配置中读取当前 WARP 状态
    local WARP_STATUS="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp')"
    # 从 Xray 配置文件加载配置
    XRAY_CONFIG="$(jq '.' "${XRAY_CONFIG_PATH}")"
    # 如果 WARP 已启用 (状态为 1)
    if [[ ${WARP_STATUS} -eq 1 ]]; then
        WARP_STATUS=0 # 设置状态为禁用
        # 调用 docker.sh 禁用 WARP 容器
        exec_docker '--disable-warp'
        # 从 Xray 配置中删除 WARP 出站和相关路由规则
        XRAY_CONFIG=$(echo "${XRAY_CONFIG}" | jq 'del(.outbounds[] | select(.tag == "warp")) | del(.routing.rules[] | select(.outboundTag == "warp"))')
    else
        WARP_STATUS=1 # 设置状态为启用
        # 调用 docker.sh 构建并启用 WARP 容器
        exec_docker '--build-warp'
        local container_ip="$(exec_docker '--enable-warp')" # 获取 WARP 容器 IP
        # 构造 WARP Socks 出站配置 JSON
        local socks_config='[{"tag":"warp","protocol":"socks","settings":{"servers":[{"address":"'"${container_ip}"'","port":40001}]}}]'
        # 将 WARP 出站配置添加到 Xray 配置中
        XRAY_CONFIG=$(echo "${XRAY_CONFIG}" | jq --argjson socks_config "${socks_config}" '.outbounds += $socks_config')
    fi
    # 更新脚本配置中的 WARP 状态
    SCRIPT_CONFIG=$(echo "${SCRIPT_CONFIG}" | jq --arg warp "${WARP_STATUS}" '.xray.warp = $warp')
    # 将更新后的脚本配置和 Xray 配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
    echo "${XRAY_CONFIG}" >"${XRAY_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_nginx_install
# 功能描述: 安装 Nginx。
#           1. 检查系统中是否已安装 nginx 命令。
#           2. 如果未安装，则调用 nginx.sh 脚本安装 (带 --brotli 参数)。
#           3. 安装 SSL 证书管理工具。
#           4. 配置 Nginx。
#           5. 获取并保存 Nginx 版本到脚本配置。
# 参数: 无
# 返回值: 无 (通过调用其他脚本执行操作)
# =============================================================================
function handler_nginx_install() {
    # 检查 nginx 命令是否存在
    if ! cmd_exists 'nginx'; then
        # 调用 nginx.sh 脚本安装 Nginx (带 Brotli 支持)
        bash "${NGINX_PATH}" --install --brotli
        # 安装 SSL 证书管理工具
        handler_ssl_install
        # 配置 Nginx
        handler_nginx_config
        # 获取 Nginx 版本
        local NGINX_VERSION="$(nginx -V 2>&1 | grep "^nginx version:.*" | cut -d / -f 2)"
        # 更新脚本配置中的 Nginx 版本
        SCRIPT_CONFIG=$(echo "${SCRIPT_CONFIG}" | jq --arg version "${NGINX_VERSION}" '.nginx.version = $version')
        # 将更新后的脚本配置写入文件
        echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
    fi
}

# =============================================================================
# 函数名称: handler_nginx_update
# 功能描述: 更新 Nginx。
# 参数: 无
# 返回值: 无 (通过调用 nginx.sh 脚本执行更新)
# =============================================================================
function handler_nginx_update() {
    # 调用 nginx.sh 脚本更新 Nginx (带 Brotli 支持)
    bash "${NGINX_PATH}" --update --brotli
}

# =============================================================================
# 函数名称: handler_nginx_purge
# 功能描述: 卸载 Nginx，并重置脚步配置。
# 参数: 无
# 返回值: 无 (通过调用 nginx.sh 脚本执行卸载)
# =============================================================================
function handler_nginx_purge() {
    # 调用 nginx.sh 脚本卸载 Nginx
    bash "${NGINX_PATH}" --purge
    # 重置 nginx 字段
    SCRIPT_CONFIG=$(reset_json_fields "${SCRIPT_CONFIG}" 'nginx')
    # 将重置后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_nginx_cron
# 功能描述: 管理 Nginx 更新的 Cron 任务。
#           1. 检查 Nginx 是否已安装。
#           2. 检查 Cron 任务是否存在。
#           3. 如果存在则移除。
#           4. 如果不存在则添加 (每天 3:00 执行更新)。
# 参数: 无
# 返回值: 无 (通过 crontab 命令管理任务)
# =============================================================================
function handler_nginx_cron() {
    # 从脚本配置中检查 Nginx 状态 (版本)
    local NGINX_STATUS="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.version')"
    # 如果 Nginx 已安装
    if [[ -n "${NGINX_STATUS}" ]]; then
        # 检查是否存在 Nginx 更新的 Cron 任务
        if crontab -l | grep -q "${NGINX_PATH}"; then
            # 移除现有的 Nginx Cron 任务
            crontab -l | grep -v "${NGINX_PATH}" | crontab -
            # 打印关闭 Cron 任务的提示
            echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.tip')] ${NC}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.nginx.close_cron")" >&2
        else
            # 设置 nginx.sh 脚本为可执行
            chmod a+x "${NGINX_PATH}"
            # 添加新的 Nginx 更新 Cron 任务 (每天 3:00 执行)
            (
                crontab -l 2>/dev/null
                echo "0 3 * * * ${NGINX_PATH} --update --brotli >/dev/null 2>&1"
            ) | awk '!x[$0]++' | crontab -
            # 打印开启 Cron 任务的提示
            echo -e "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.tip')] ${NC}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.nginx.open_cron")" >&2
        fi
    fi
}

# =============================================================================
# 函数名称: handler_nginx_start
# 功能描述: 启动 nginx 服务。
#           1. 检查 nginx 服务是否已在运行。
#           2. 如果未运行则启动服务。
#           3. 检查 nginx 服务是否已设置开机自启。
#           4. 如果未设置则启用开机自启。
# 参数: 无
# 返回值: 无 (通过 systemctl 命令执行操作)
# =============================================================================
function handler_nginx_start() {
    # 检查 nginx 服务是否活跃，如果不活跃则启动
    systemctl -q is-active nginx || systemctl -q start nginx
    # 检查 nginx 服务是否已启用，如果未启用则启用
    systemctl -q is-enabled nginx || systemctl -q enable nginx
}

# =============================================================================
# 函数名称: handler_nginx_stop
# 功能描述: 停止 nginx 服务。
#           1. 检查 nginx 服务是否正在运行。
#           2. 如果正在运行则停止服务。
#           3. 检查 nginx 服务是否已设置开机自启。
#           4. 如果已设置则禁用开机自启。
# 参数: 无
# 返回值: 无 (通过 systemctl 命令执行操作)
# =============================================================================
function handler_nginx_stop() {
    # 检查 nginx 服务是否活跃，如果活跃则停止
    systemctl -q is-active nginx && systemctl -q stop nginx
    # 检查 nginx 服务是否已启用，如果启用则禁用
    systemctl -q is-enabled nginx && systemctl -q disable nginx
}

# =============================================================================
# 函数名称: handler_nginx_restart
# 功能描述: 重启 nginx 服务。
#           1. 检查 nginx 服务是否正在运行。
#           2. 如果正在运行则重启服务，否则启动服务。
#           3. 检查 nginx 服务是否已设置开机自启。
#           4. 如果未设置则启用开机自启。
# 参数: 无
# 返回值: 无 (通过 systemctl 命令执行操作)
# =============================================================================
function handler_nginx_restart() {
    # 检查 nginx 服务是否活跃，如果活跃则重启，否则启动
    systemctl -q is-active nginx && systemctl -q restart nginx || systemctl -q start nginx
    # 检查 nginx 服务是否已启用，如果未启用则启用
    systemctl -q is-enabled nginx || systemctl -q enable nginx
}

# =============================================================================
# 函数名称: handler_ssl_install
# 功能描述: 安装 SSL 证书管理工具 (acme.sh)。
#           1. 检查 acme.sh 是否已安装。
#           2. 如果未安装，则从脚本配置中读取 CA 邮箱。
#           3. 调用 ssl.sh 脚本安装 acme.sh。
# 参数: 无
# 返回值: 无 (通过调用 ssl.sh 脚本执行安装)
# =============================================================================
function handler_ssl_install() {
    # 检查 acme.sh 脚本是否存在
    if [[ ! -e "${ACME_PATH}" ]]; then
        # 从脚本配置中读取 CA 邮箱
        local CA_EMAIL="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.ca')"
        # 调用 ssl.sh 脚本安装 acme.sh
        exec_ssl '--install' --email=${CA_EMAIL}
    fi
}

# =============================================================================
# 函数名称: handler_change_domain
# 功能描述: 更改 Nginx 配置中的域名 (包括 SSL 证书)。
#           1. 获取旧域名。
#           2. 读取新域名 (如果未提供)。
#           3. 如果旧域名存在，则停止其证书续签并删除配置文件。
#           4. 复制并修改新的站点配置模板。
#           5. 申请新的 SSL 证书。
#           6. 更新脚本配置中的域名。
#           7. 调用 handler_nginx_restart 重启 Nginx 服务。
# 参数:
#   $1: target_domain - 目标域名类型 ("domain" 或 "cdn")
#   $2: stop_cert_service - 管理停止证书签发服务类型 ("n", 或默认的 "y")
# 返回值: 无 (通过文件操作和调用其他脚本执行)
# =============================================================================
function handler_change_domain() {
    # 获取 XHTTP PATH
    local XHTTP_PATH="$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.path')"
    # 获取目标域名类型参数
    local target_domain="$1"
    # 获取管理停止证书签发服务参数
    local stop_cert_service="${2:-y}"
    # 从脚本配置中获取旧域名
    local old_domain="$(echo "${SCRIPT_CONFIG}" | jq -r --arg key "${target_domain}" '.nginx[$key]')"
    # 如果 CONFIG_DATA 中没有新域名，且 stop_cert_service 为 "y"，则读取用户输入
    if [[ -z "${CONFIG_DATA["${target_domain}"]}" && "${stop_cert_service}" == "y" ]]; then
        exec_read "${target_domain}"
    else
        CONFIG_DATA["${target_domain}"]="${old_domain}"
    fi
    # 如果旧域名存在
    if [[ -n "${old_domain}" && "${stop_cert_service}" == "y" ]] && exec_ssl '--status' --domain=${old_domain}; then
        # 停止旧域名的证书续签
        exec_ssl '--stop-renew' --domain=${old_domain}
        # 删除旧域名的 Nginx 配置文件
        rm -rf ${NGINX_CONFIG_DIR}/sites-{available,enabled}/${old_domain}.conf
    fi
    # 复制站点配置模板到 available 目录
    cp -f "${CONFIG_DIR}/nginx/conf/sites-available/${target_domain}.example.com.conf" "${NGINX_CONFIG_DIR}/sites-available/${CONFIG_DATA["${target_domain}"]}.conf"
    # 替换配置文件中的 example.com 为实际域名
    sed -i "s|example.com|${CONFIG_DATA["${target_domain}"]}|g" "${NGINX_CONFIG_DIR}/sites-available/${CONFIG_DATA["${target_domain}"]}.conf"
    # 替换配置文件中的 /yourpath 为 xhttp path
    sed -i "s|/yourpath|${XHTTP_PATH}|g" "${NGINX_CONFIG_DIR}/sites-available/${CONFIG_DATA["${target_domain}"]}.conf"
    # 创建从 available 到 enabled 的软链接
    ln -sf "${NGINX_CONFIG_DIR}/sites-available/${CONFIG_DATA["${target_domain}"]}.conf" "${NGINX_CONFIG_DIR}/sites-enabled/${CONFIG_DATA["${target_domain}"]}.conf"
    # 为新域名申请 SSL 证书
    exec_ssl '--issue' --domain=${CONFIG_DATA["${target_domain}"]}
    # 更新脚本配置中的域名
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg key "${target_domain}" --arg domain "${CONFIG_DATA["${target_domain}"]}" '.nginx[$key] = $domain')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg key "${target_domain}" --arg domain "${old_domain}" 'if $key == "domain" then del(.target[$key]) else . end')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg key "${target_domain}" --arg domain "${CONFIG_DATA["${target_domain}"]}" 'if $key == "domain" then .xray.target = $domain else . end')"
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg key "${target_domain}" --arg domain "${CONFIG_DATA["${target_domain}"]}" 'if $key == "domain" then .xray.serverNames = [$domain] else . end')"
    # 删除旧域名的 Nginx 配置文件
    rm -rf ${NGINX_CONFIG_DIR}/modules-enabled/stream.conf
    # 复制 stream.conf 配置模板到 modules-enabled 目录
    cp -f "${CONFIG_DIR}/nginx/conf/modules-enabled/stream.conf" "${NGINX_CONFIG_DIR}/modules-enabled/stream.conf"
    # 替换 stream.conf 的 example.com 与 cdn.example.com 为实际域名
    sed -i "s|cdn.example.com|$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn')|g" "${NGINX_CONFIG_DIR}/modules-enabled/stream.conf"
    sed -i "s|example.com|$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain')|g" "${NGINX_CONFIG_DIR}/modules-enabled/stream.conf"
    # 将更新后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
    # 重启或启动 Nginx
    handler_nginx_restart
}

# =============================================================================
# 函数名称: handler_nginx_config
# 功能描述: 配置 Nginx。
#           1. 创建 sites-enabled 目录。
#           2. 备份并复制 Nginx 主配置文件和站点配置模板。
#           3. 从脚本配置中读取域名和 CDN。
#           4. 调用 handler_change_domain 为域名和 CDN 配置 SSL。
# 参数: 无
# 返回值: 无 (通过文件操作执行)
# =============================================================================
function handler_nginx_config() {
    # 创建 Nginx sites-enabled 目录 (如果不存在)
    mkdir -vp ${NGINX_CONFIG_DIR}/sites-enabled
    # 备份原始的 nginx.conf 文件
    mv "${NGINX_CONFIG_DIR}/nginx.conf" "${NGINX_CONFIG_DIR}/default.conf.bak"
    # 复制项目中的 Nginx 配置文件到目标目录
    cp -af ${CONFIG_DIR}/nginx/conf/* ${NGINX_CONFIG_DIR}
}

# =============================================================================
# 函数名称: handler_cloudreve_v3
# 功能描述: 管理 Cloudreve v3 Docker 容器。
#           1. 确保 Docker 已安装。
#           2. 根据传入参数调用 docker.sh 执行对应操作。
# 参数:
#   $1: action - 要执行的操作 (install, get, token, reset, purge, start, stop)
# 返回值: 无 (通过调用 docker.sh 脚本执行操作)
# =============================================================================
function handler_cloudreve_v3() {
    # 确保 Docker 已安装
    handler_docker
    # 根据传入的操作参数执行对应动作
    case "${1}" in
    install) exec_docker '--install-cloudreve-v3' ;;   # 安装 Cloudreve v3
    get) exec_docker '--get-cloudreve-v3-admin' ;;     # 获取 Cloudreve v3 管理员信息
    token) exec_docker '--get-aria2-token' ;;          # 获取 Aria2 Token
    reset) exec_docker '--reset-cloudreve-v3-admin' ;; # 重置 Cloudreve v3 管理员
    purge) exec_docker '--purge-cloudreve-v3' ;;       # 卸载 Cloudreve v3
    start) exec_docker '--start-cloudreve-v3' ;;       # 启动 Cloudreve v3
    stop) exec_docker '--stop-cloudreve-v3' ;;         # 停止 Cloudreve v3
    esac
}

# =============================================================================
# 函数名称: handler_cloudreve_v4
# 功能描述: 管理 Cloudreve v4 Docker 容器。
#           1. 确保 Docker 已安装。
#           2. 根据传入参数调用 docker.sh 执行对应操作。
# 参数:
#   $1: action - 要执行的操作 (install, update, purge, start, stop)
# 返回值: 无 (通过调用 docker.sh 脚本执行操作)
# =============================================================================
function handler_cloudreve_v4() {
    # 确保 Docker 已安装
    handler_docker
    # 根据传入的操作参数执行对应动作
    case "${1}" in
    install) exec_docker '--install-cloudreve-v4' ;; # 安装 Cloudreve v4
    update) exec_docker '--update-cloudreve-v4' ;;   # 更新 Cloudreve v4
    purge) exec_docker '--purge-cloudreve-v4' ;;     # 卸载 Cloudreve v4
    start) exec_docker '--start-cloudreve-v4' ;;     # 启动 Cloudreve v4
    stop) exec_docker '--stop-cloudreve-v4' ;;       # 停止 Cloudreve v4
    esac
}

# =============================================================================
# 函数名称: handler_web
# 功能描述: 配置和管理 Web 服务 (Cloudreve) 与 Nginx 的集成。
#           1. 根据 Web 类型启动/停止对应的 Cloudreve 容器。
#           2. 修改 Nginx 配置文件以包含或排除 Cloudreve 配置片段。
#           3. 调用 handler_nginx_restart 重启 Nginx 服务。
#           4. 调用 handler_restart 重启 Xray 服务。
#           5. 更新脚本配置中的 Web 类型。
# 参数:
#   $1: web - Web 服务类型 ("v3", "v4", 或默认的 "normal")
# 返回值: 无 (通过调用其他函数执行操作)
# =============================================================================
function handler_web() {
    local web="${1:-normal}" # 获取 Web 类型参数，默认为 normal
    # 从脚本配置中读取域名和 CDN
    local domain="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.domain')"
    local cdn="$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.cdn')"
    # 根据 Web 类型启动/停止 Cloudreve 容器
    case "${web}" in
    v3)
        # 启动 v3，停止 v4
        handler_cloudreve_v4 'stop'
        handler_cloudreve_v3 'start'
        ;;
    v4)
        # 启动 v4，停止 v3
        handler_cloudreve_v3 'stop'
        handler_cloudreve_v4 'start'
        ;;
    *)
        # 停止 v3 和 v4
        handler_cloudreve_v3 'stop'
        handler_cloudreve_v4 'stop'
        ;;
    esac
    # 根据 Web 类型修改 Nginx 配置以包含或排除 Cloudreve
    case "${web}" in
    v3 | v4)
        # 启用 Cloudreve 配置 (取消注释)
        sed -i "s|# include web/cloudreve.conf;|include web/cloudreve.conf;|" "${NGINX_CONFIG_DIR}/sites-available/${domain}.conf"
        sed -i "s|# include web/cloudreve.conf;|include web/cloudreve.conf;|" "${NGINX_CONFIG_DIR}/sites-available/${cdn}.conf"
        ;;
    *)
        # 禁用 Cloudreve 配置 (添加注释)
        sed -i "s|[^#] include web/cloudreve.conf;|  # include web/cloudreve.conf;|" "${NGINX_CONFIG_DIR}/sites-available/${domain}.conf"
        sed -i "s|[^#] include web/cloudreve.conf;|  # include web/cloudreve.conf;|" "${NGINX_CONFIG_DIR}/sites-available/${cdn}.conf"
        ;;
    esac
    # 重启或启动 Nginx 与 xray 服务
    handler_nginx_restart
    handler_restart
    # 更新脚本配置中的 Web 类型
    SCRIPT_CONFIG="$(echo "${SCRIPT_CONFIG}" | jq --arg web "${web}" '.nginx.web = $web')"
    # 将更新后的脚本配置写入文件
    echo "${SCRIPT_CONFIG}" >"${SCRIPT_CONFIG_PATH}" && sleep 2
}

# =============================================================================
# 函数名称: handler_quick_install
# 功能描述: 执行一键快速安装流程。
#           1. 调用 handler_script_config 配置脚本。
#           2. 调用 handler_install 安装 Xray。
#           3. 调用 handler_xray_config 配置 Xray。
#           4. 添加默认的阻止规则 (BT, CN IP, AD Domain)。
#           5. 调用 handler_geodata_cron 更新 GeoData 并设置 Cron。
#           6. 调用 handler_restart 重启 Xray 服务。
#           7. 调用 handler_share 显示分享链接。
# 参数:
#   $1: quick_install_type - 速安装类型 (例如 Vision, XHTTP, Fallback)，默认为 Vision
# 返回值: 无 (通过调用一系列处理器函数执行完整安装流程)
# =============================================================================
function handler_quick_install() {
    local quick_install_type="${1:-Vision}" # 获取快速安装类型参数，默认为 Vision
    # 配置脚本 (设置各种参数)
    handler_script_config "${quick_install_type}"
    # 安装 Xray (使用 release 版本)
    handler_install 'release'
    # 生成 x25519 配置
    handler_x25519_config
    # 配置 Xray (生成并写入 config.json)
    handler_xray_config
    # 添加默认的阻止规则
    add_rule "bt" "protocol" "bittorrent" "block" 1
    add_rule "cn-ip" "ip" "geoip:cn" "block" "after" "private-ip"
    add_rule "ad-domain" "domain" "geosite:category-ads-all" "block"
    # 更新 GeoData 并设置 Cron 任务 (快速模式)
    handler_geodata_cron 1
    # 重启 Xray 服务
    handler_restart
    # 显示分享链接
    handler_share
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。
#           1. 加载国际化数据。
#           2. 根据传入的第一个参数 ($1) 调用对应的处理器函数。
#           3. 将剩余参数传递给处理器函数。
# 参数:
#   $@: 命令行参数，第一个参数决定要调用的处理器函数
# 返回值: 无 (通过调用其他函数执行具体操作)
# =============================================================================
function main() {
    # 加载国际化数据
    load_i18n

    local option="$1" # 获取第一个参数作为操作选项
    shift             # 移除第一个参数，剩下的参数留给具体函数处理

    # 根据第一个参数调用对应的处理器函数
    case "${option}" in
    --quick) handler_quick_install "$1" ;;    # 一键快速安装
    --install) handler_install "$@" ;;        # 安装 Xray
    --version) handler_xray_version "$1" ;;   # 设置 Xray 版本
    --purge) handler_purge ;;                 # 卸载 Xray
    --nginx-install) handler_nginx_install ;; # 安装 Nginx
    --nginx-update) handler_nginx_update ;;   # 更新 Nginx
    --nginx-purge) handler_nginx_purge ;;     # 卸载 Nginx
    --script-config)
        handler_read_xray_config "$1" # 读取 Xray 配置输入
        handler_script_config         # 更新脚本配置
        ;;
    --xray-config)
        handler_sni_config "$1" # 处理 SNI 配置
        handler_x25519_config   # 生成 x25519 配置
        handler_xray_config     # 更新 Xray 配置
        ;;
    --routing) handler_routing "$@" ;; # 处理路由规则
    --change-domain)
        handler_change_domain "$1" # 处理域名配置
        handler_xray_config        # 更新 Xray 配置
        # 还原 Web 服务
        handler_web "$(echo "${SCRIPT_CONFIG}" | jq -r '.nginx.web')"
        ;;                                      # 更改域名
    --web) handler_web "$1" ;;                  # 配置 Web 服务
    --v3-reset) handler_cloudreve_v3 'reset' ;; # 重置 Cloudreve v3
    --share) handler_share ;;                   # 显示分享链接
    --nginx-cron) handler_nginx_cron ;;         # 管理 Nginx Cron
    --geodata-cron) handler_geodata_cron ;;     # 管理 GeoData Cron
    --warp) handler_warp ;;                     # 管理 WARP
    --traffic) handler_traffic ;;               # 显示流量统计
    --start) handler_start ;;                   # 启动 Xray
    --stop) handler_stop ;;                     # 停止 Xray
    --restart) handler_restart ;;               # 重启 Xray
    esac
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
