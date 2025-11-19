#!/usr/bin/env bash
#
# Copyright (C) 2025 zxcvos
#
# Xray-script:
#   https://github.com/zxcvos/Xray-script
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: menu.sh
# 功能描述: 提供交互式菜单界面，用于 Xray-script 项目的主控制台。
#           显示各种配置选项、状态信息和操作菜单，支持多语言。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, jq, sed, base64
# 配置:
#   - ${SCRIPT_CONFIG_DIR}/config.json: 用于读取语言、Xray 版本、配置标签等设置
#   - ${I18N_DIR}/${lang}.json: 用于读取具体的菜单文本 (i18n 数据文件)
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
readonly GENERATE_PATH="${CUR_DIR}/generate.sh"                # 项目中的 generate.sh 脚本路径
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
# 函数名称: menu_language
# 功能描述: 显示语言选择菜单。
# 参数: 无
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_language() {
    # 打印中文选项
    echo -e "${GREEN}1.${NC}中文"
    # 打印英文选项
    echo -e "${GREEN}2.${NC}English"
}

# =============================================================================
# 函数名称: menu_index
# 功能描述: 显示主菜单。
# 参数: 无 (直接使用全局变量 SCRIPT_CONFIG_PATH 和 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_index() {
    # 从配置文件中读取脚本版本号
    local version=$(jq -r '.version' "${SCRIPT_CONFIG_PATH}")

    # 打印主菜单标题和版本信息
    echo -e "--------------- Xray-script ------------------"
    echo -e "Version      : ${GREEN}${version}${NC}"
    # 从 i18n 数据中读取描述信息
    echo -e "Description  : $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.description")"

    # 打印安装选项部分
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.installation") ------------------"
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option1")"
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option2")"
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option3")"

    # 打印操作选项部分
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.operation") ------------------"
    echo -e "${GREEN}4.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option4")"
    echo -e "${GREEN}5.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option5")"
    echo -e "${GREEN}6.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option6")"

    # 打印配置选项部分
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.configuration") ------------------"
    echo -e "${GREEN}7.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option7")"
    echo -e "${GREEN}8.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option8")"
    echo -e "${GREEN}9.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option9")"

    # 打印退出选项
    echo -e "------------------------------------------------------"
    echo -e "${RED}0.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.index.option0")"
}

# =============================================================================
# 函数名称: menu_full_installation
# 功能描述: 显示完整安装选项菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_full_installation() {
    # 打印完整安装菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.full_installation.title") ------------------"
    # 打印选项 1 (默认)
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.full_installation.option1")(${GREEN}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.default")${NC})"
    # 打印选项 2
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.full_installation.option2")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 1 的说明信息
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.full_installation.info1")"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.full_installation.info2")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: menu_xray
# 功能描述: 显示 Xray 版本选择菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_xray() {
    # 打印 Xray 版本菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.title") ------------------"
    # 打印选项 1
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.option1")"
    # 打印选项 2 (默认)
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.option2")(${GREEN}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.default")${NC})"
    # 打印选项 3
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.option3")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 1 的说明信息
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.info1")"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.info2")"
    # 打印选项 3 的说明信息
    echo -e "3. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.xray_version.info3")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: menu_xray_config
# 功能描述: 显示 Xray 协议配置菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_xray_config() {
    # 打印协议配置菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.title") ------------------"
    # 打印选项 1
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.option1")"
    # 打印选项 2 (默认)
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.option2")(${GREEN}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.default")${NC})"
    # 打印选项 3
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.option3")"
    # 打印选项 4
    echo -e "${GREEN}4.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.option4")"
    # 打印选项 5
    echo -e "${GREEN}5.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.option5")"
    # 打印选项 6
    echo -e "${GREEN}6.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.option6")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 1 的说明信息
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info1")"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info2")"
    # 打印选项 3 的说明信息
    echo -e "3. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info3")"
    # 打印选项 3.1 的说明信息
    echo -e "3.1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info3_1")"
    # 打印选项 3.2 的说明信息
    echo -e "3.2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info3_2")"
    # 打印选项 4 的说明信息
    echo -e "4. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info4")"
    # 打印选项 5 的说明信息
    echo -e "5. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info5")"
    # 打印选项 6 的说明信息
    echo -e "6. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.protocol_config.info6")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: menu_web_config
# 功能描述: 显示 Web 服务器配置菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_web_config() {
    # 打印 Web 配置菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.web_config.title") ------------------"
    # 打印选项 1 (默认)
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.web_config.option1")(${GREEN}$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.default")${NC})"
    # 打印选项 2
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.web_config.option2")"
    # 打印选项 3
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.web_config.option3")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.web_config.info1")"
    # 打印选项 3 的说明信息
    echo -e "3. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.web_config.info2")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: menu_config
# 功能描述: 显示配置管理菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_config() {
    # 打印配置管理菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.title") ------------------"
    # 打印选项 1
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.option1")"
    # 打印选项 2
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.option2")"
    # 打印选项 3
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.option3")"
    # 打印选项 4
    echo -e "${GREEN}4.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.option4")"
    # 打印选项 5
    echo -e "${GREEN}5.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.option5")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 1 的说明信息
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.info1")"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.info2")"
    # 打印选项 3 的说明信息
    echo -e "3. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.info3")"
    # 打印选项 4 的说明信息
    echo -e "4. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.config_management.info4")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: menu_route
# 功能描述: 显示路由规则管理菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_route() {
    # 打印路由管理菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.title") ------------------"
    # 打印选项 1
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.option1")"
    # 打印选项 2
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.option2")"
    # 打印选项 3
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.option3")"
    # 打印选项 4
    echo -e "${GREEN}4.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.option4")"
    # 打印选项 5
    echo -e "${GREEN}5.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.option5")"
    # 打印选项 6
    echo -e "${GREEN}5.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.option6")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 1 的说明信息 (有重复)
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info1")"
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info2")"
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info3")"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info4")"
    # 打印选项 3 的说明信息
    echo -e "3. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info5")"
    # 打印选项 4 的说明信息
    echo -e "4. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info6")"
    # 打印选项 5 的说明信息
    echo -e "5. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info7")"
    # 打印选项 6 的说明信息
    echo -e "6. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.route_management.info8")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: menu_sni_config
# 功能描述: 显示 SNI 配置菜单。
# 参数: 无 (直接使用全局变量 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function menu_sni_config() {
    # 打印 SNI 配置菜单标题
    echo -e "------------------ $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.title") ------------------"
    # 打印选项 1
    echo -e "${GREEN}1.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.option1")"
    # 打印选项 2
    echo -e "${GREEN}2.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.option2")"
    # 打印选项 3
    echo -e "${GREEN}3.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.option3")"
    # 打印选项 4
    echo -e "${GREEN}4.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.option4")"
    # 打印选项 5
    echo -e "${GREEN}5.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.option5")"
    # 打印选项 6
    echo -e "${GREEN}6.${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.option6")"

    # 打印分隔线
    echo -e "------------------------------------------------------"
    # 打印选项 1 的说明信息
    echo -e "1. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.info1")"
    # 打印选项 2 的说明信息
    echo -e "2. $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.sni_config.info2")"
    # 打印分隔线
    echo -e "------------------------------------------------------"
}

# =============================================================================
# 函数名称: print_banner
# 功能描述: 随机打印一个 ASCII 艺术风格的 Banner。
# 参数: 无
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function print_banner() {
    # 生成一个 0 或 1 的随机数
    case $(($(bash "${GENERATE_PATH}" '--random' 1 100) % 2)) in
    # 如果是 0，打印第一个 Banner (解码后)
    0)
        echo "IBtbMDsxOzM1Ozk1bV8bWzA7MTszMTs5MW1fG1swbSAgIBtbMDsxOzMyOzkybV9fG1swbSAgG1swOzE7MzQ7OTRtXxtbMG0gICAgG1swOzE7MzE7OTFtXxtbMG0gICAbWzA7MTszMjs5Mm1fG1swOzE7MzY7OTZtX18bWzA7MTszNDs5NG1fXxtbMDsxOzM1Ozk1bV9fG1swbSAgIBtbMDsxOzMzOzkzbV8bWzA7MTszMjs5Mm1fXxtbMDsxOzM2Ozk2bV9fG1swOzE7MzQ7OTRtX18bWzBtICAgG1swOzE7MzE7OTFtXxtbMDsxOzMzOzkzbV9fG1swOzE7MzI7OTJtX18bWzBtICAKIBtbMDsxOzMxOzkxbVwbWzBtIBtbMDsxOzMzOzkzbVwbWzBtIBtbMDsxOzMyOzkybS8bWzBtIBtbMDsxOzM2Ozk2bS8bWzBtIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAbWzA7MTszMzs5M218G1swbSAbWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18XxtbMDsxOzM0Ozk0bV8bWzBtICAgG1swOzE7MzE7OTFtX18bWzA7MTszMzs5M218G1swbSAbWzA7MTszMjs5Mm18XxtbMDsxOzM2Ozk2bV8bWzBtICAgG1swOzE7MzU7OTVtX18bWzA7MTszMTs5MW18G1swbSAbWzA7MTszMzs5M218G1swbSAgG1swOzE7MzI7OTJtXxtbMDsxOzM2Ozk2bV8bWzBtIBtbMDsxOzM0Ozk0bVwbWzBtIAogIBtbMDsxOzMyOzkybVwbWzBtIBtbMDsxOzM2Ozk2bVYbWzBtIBtbMDsxOzM0Ozk0bS8bWzBtICAbWzA7MTszNTs5NW18G1swbSAbWzA7MTszMTs5MW18G1swOzE7MzM7OTNtX18bWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18G1swbSAgICAbWzA7MTszNTs5NW18G1swbSAbWzA7MTszMTs5MW18G1swbSAgICAgICAbWzA7MTszNDs5NG18G1swbSAbWzA7MTszNTs5NW18G1swbSAgICAbWzA7MTszMjs5Mm18G1swbSAbWzA7MTszNjs5Nm18XxtbMDsxOzM0Ozk0bV8pG1swbSAbWzA7MTszNTs5NW18G1swbQogICAbWzA7MTszNjs5Nm0+G1swbSAbWzA7MTszNDs5NG08G1swbSAgIBtbMDsxOzMxOzkxbXwbWzBtICAbWzA7MTszMjs5Mm1fXxtbMG0gIBtbMDsxOzM0Ozk0bXwbWzBtICAgIBtbMDsxOzMxOzkxbXwbWzBtIBtbMDsxOzMzOzkzbXwbWzBtICAgICAgIBtbMDsxOzM1Ozk1bXwbWzBtIBtbMDsxOzMxOzkxbXwbWzBtICAgIBtbMDsxOzM2Ozk2bXwbWzBtICAbWzA7MTszNDs5NG1fG1swOzE7MzU7OTVtX18bWzA7MTszMTs5MW0vG1swbSAKICAbWzA7MTszNDs5NG0vG1swbSAbWzA7MTszNTs5NW0uG1swbSAbWzA7MTszMTs5MW1cG1swbSAgG1swOzE7MzM7OTNtfBtbMG0gG1swOzE7MzI7OTJtfBtbMG0gIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAgIBtbMDsxOzMzOzkzbXwbWzBtIBtbMDsxOzMyOzkybXwbWzBtICAgICAgIBtbMDsxOzMxOzkxbXwbWzBtIBtbMDsxOzMzOzkzbXwbWzBtICAgIBtbMDsxOzM0Ozk0bXwbWzBtIBtbMDsxOzM1Ozk1bXwbWzBtICAgICAKIBtbMDsxOzM0Ozk0bS8bWzA7MTszNTs5NW1fLxtbMG0gG1swOzE7MzE7OTFtXBtbMDsxOzMzOzkzbV9cG1swbSAbWzA7MTszMjs5Mm18G1swOzE7MzY7OTZtX3wbWzBtICAbWzA7MTszNTs5NW18XxtbMDsxOzMxOzkxbXwbWzBtICAgIBtbMDsxOzMyOzkybXwbWzA7MTszNjs5Nm1ffBtbMG0gICAgICAgG1swOzE7MzM7OTNtfBtbMDsxOzMyOzkybV98G1swbSAgICAbWzA7MTszNTs5NW18XxtbMDsxOzMxOzkxbXwbWzBtICAgICAKCkNvcHlyaWdodCAoQykgenhjdm9zIHwgaHR0cHM6Ly9naXRodWIuY29tL3p4Y3Zvcy9YcmF5LXNjcmlwdAoK" | base64 --decode
        ;;
    # 如果是 1，打印第二个 Banner (解码后)
    1)
        echo "IBtbMDsxOzM0Ozk0bV9fG1swbSAgIBtbMDsxOzM0Ozk0bV9fG1swbSAgG1swOzE7MzQ7OTRtXxtbMG0gICAgG1swOzE7MzQ7OTRtXxtbMG0gICAbWzA7MzRtX19fX19fXxtbMG0gICAbWzA7MzRtX19fG1swOzM3bV9fX18bWzBtICAgG1swOzM3bV9fX19fG1swbSAgCiAbWzA7MTszNDs5NG1cG1swbSAbWzA7MTszNDs5NG1cG1swbSAbWzA7MTszNDs5NG0vG1swbSAbWzA7MTszNDs5NG0vG1swbSAbWzA7MzRtfBtbMG0gG1swOzM0bXwbWzBtICAbWzA7MzRtfBtbMG0gG1swOzM0bXwbWzBtIBtbMDszNG18X18bWzBtICAgG1swOzM3bV9ffBtbMG0gG1swOzM3bXxfXxtbMG0gICAbWzA7MzdtX198G1swbSAbWzA7MzdtfBtbMG0gIBtbMDsxOzMwOzkwbV9fG1swbSAbWzA7MTszMDs5MG1cG1swbSAKICAbWzA7MzRtXBtbMG0gG1swOzM0bVYbWzBtIBtbMDszNG0vG1swbSAgG1swOzM0bXwbWzBtIBtbMDszNG18X198G1swbSAbWzA7MzdtfBtbMG0gICAgG1swOzM3bXwbWzBtIBtbMDszN218G1swbSAgICAgICAbWzA7MzdtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfF9fKRtbMG0gG1swOzE7MzA7OTBtfBtbMG0KICAgG1swOzM0bT4bWzBtIBtbMDszNG08G1swbSAgIBtbMDszN218G1swbSAgG1swOzM3bV9fG1swbSAgG1swOzM3bXwbWzBtICAgIBtbMDszN218G1swbSAbWzA7MzdtfBtbMG0gICAgICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gIBtbMDsxOzM0Ozk0bV9fXy8bWzBtIAogIBtbMDszN20vG1swbSAbWzA7MzdtLhtbMG0gG1swOzM3bVwbWzBtICAbWzA7MzdtfBtbMG0gG1swOzM3bXwbWzBtICAbWzA7MzdtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzA7OTBtfBtbMG0gICAgICAgG1swOzE7MzA7OTBtfBtbMG0gG1swOzE7MzQ7OTRtfBtbMG0gICAgG1swOzE7MzQ7OTRtfBtbMG0gG1swOzE7MzQ7OTRtfBtbMG0gICAgIAogG1swOzM3bS9fLxtbMG0gG1swOzM3bVxfXBtbMG0gG1swOzE7MzA7OTBtfF98G1swbSAgG1swOzE7MzA7OTBtfF98G1swbSAgICAbWzA7MTszMDs5MG18X3wbWzBtICAgICAgIBtbMDsxOzM0Ozk0bXxffBtbMG0gICAgG1swOzE7MzQ7OTRtfF8bWzA7MzRtfBtbMG0gICAgIAoKQ29weXJpZ2h0IChDKSB6eGN2b3MgfCBodHRwczovL2dpdGh1Yi5jb20venhjdm9zL1hyYXktc2NyaXB0Cgo=" | base64 --decode
        ;;
    esac
}

# =============================================================================
# 函数名称: print_status
# 功能描述: 打印当前脚本配置的状态信息，包括 Xray 版本、配置标签和 WARP 状态。
# 参数: 无 (直接使用全局变量 SCRIPT_CONFIG_PATH 和 I18N_DATA)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function print_status() {
    # 读取脚本配置文件的完整 JSON 内容
    local SCRIPT_CONFIG=$(jq '.' "${SCRIPT_CONFIG_PATH}")

    # 从配置中提取 Xray 版本、配置标签和 WARP 状态
    local XRAY_VERSION=$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.version')
    local CONFIG_TAG=$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.tag')
    local WARP_STATUS=$(echo "${SCRIPT_CONFIG}" | jq -r '.xray.warp')

    # 从 i18n 数据中读取状态描述文本
    local not_installed=$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.not_installed")
    local not_configured=$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.not_configured")
    local enabled=$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.enabled")
    local disabled=$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.disabled")

    # 根据 Xray 版本是否存在，设置显示颜色和文本
    [[ ${XRAY_VERSION} ]] && XRAY_VERSION="${GREEN}${XRAY_VERSION}${NC}" || XRAY_VERSION="${RED}${not_installed}${NC}"
    # 根据配置标签是否存在，设置显示颜色和文本
    [[ ${CONFIG_TAG} ]] && CONFIG_TAG="${GREEN}${CONFIG_TAG}${NC}" || CONFIG_TAG="${RED}${not_configured}${NC}"
    # 根据 WARP 状态 (1 或 0)，设置显示颜色和文本
    [[ ${WARP_STATUS} -eq 1 ]] && WARP_STATUS="${GREEN}${enabled}${NC}" || WARP_STATUS="${RED}${disabled}${NC}"

    # 打印状态信息
    echo -e "------------------------------------------------------"
    echo -e "Xray       : ${XRAY_VERSION}"
    echo -e "CONFIG     : ${CONFIG_TAG}"
    echo -e "WARP Proxy : ${WARP_STATUS}"
    echo -e "------------------------------------------------------"
    echo
}

# =============================================================================
# 函数名称: get_choose
# 功能描述: 提示用户输入选择，并对输入进行基本验证和处理。
# 参数:
#   $1: 用于区分是否是语言选择菜单的标志 (例如 '--language')
# 返回值: 用户输入的选择数字 (通过 return 返回)
# =============================================================================
function get_choose() {
    local i18n="$1" # 获取参数

    # 根据参数决定提示信息
    if [[ "$i18n" == '--language' ]]; then
        printf "请选择你的语言(默认: 中文): " >&2
    else
        # 从 i18n 数据中读取通用提示信息
        printf "${YELLOW}[$(echo "$I18N_DATA" | jq -r '.title.tip')] ${NC} $(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.choose"): " >&2
    fi

    # 从标准输入读取用户输入
    read -r choose

    # 检查输入是否为纯数字
    if [[ ${choose} =~ ^[0-9]+$ ]]; then
        # 移除前导零 (例如 01 -> 1)
        choose=$(echo "${choose}" | sed 's/^0*//')
        # 如果处理后为空 (原输入为 "0" 或 "00")，则返回 0；否则返回处理后的数字
        return "${choose:-0}"
    else
        # 如果不是纯数字，则返回 0
        return "0"
    fi
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。
#           1. 根据传入的第一个参数决定要执行的操作。
#           2. 如果是语言选择，则显示语言菜单；否则加载 i18n 并显示相应菜单。
#           3. 显示指定的菜单或信息。
#           4. 除非是 banner 或 status，否则提示用户输入选择。
# 参数:
#   $@: 所有命令行参数
# 返回值: 无 (协调调用其他函数完成整个流程)
# =============================================================================
function main() {
    # 检查第一个参数是否为 --language，如果是则显示语言菜单
    if [[ "$1" == "--language" ]]; then
        menu_language >&2
    else
        # 否则加载国际化数据
        load_i18n
    fi

    # 使用 case 语句根据第一个参数调用对应的菜单或信息显示函数
    case "$1" in
    --index) menu_index >&2 ;;            # 显示主菜单
    --full) menu_full_installation >&2 ;; # 显示完整安装菜单
    --xray) menu_xray >&2 ;;              # 显示 Xray 版本菜单
    --config) menu_xray_config >&2 ;;     # 显示协议配置菜单
    --web) menu_web_config >&2 ;;         # 显示 Web 配置菜单
    --management) menu_config >&2 ;;      # 显示配置管理菜单
    --route) menu_route >&2 ;;            # 显示路由管理菜单
    --sni) menu_sni_config >&2 ;;         # 显示 SNI 配置菜单
    --banner) print_banner >&2 ;;         # 显示 Banner
    --status) print_status >&2 ;;         # 显示状态信息
    esac

    # 如果不是显示 banner 或状态信息，则提示用户输入选择
    if [[ "$1" != "--banner" && "$1" != "--status" ]]; then
        get_choose "$1"
    fi
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
