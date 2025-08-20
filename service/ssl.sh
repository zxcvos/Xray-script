#!/usr/bin/env bash
# =============================================================================
# 注释: 通过 Qwen3-Coder 生成。
# 脚本名称: ssl.sh
# 脚本仓库: https://github.com/zxcvos/Xray-script
# 功能描述: 使用 acme.sh 管理 SSL 证书的脚本。
#           支持安装/更新/卸载 acme.sh，签发/续期/停止续期证书，
#           检查证书状态和信息，以及管理 Nginx 配置。
# 作者: zxcvos
# 时间: 2025-07-25
# 版本: 1.0.0
# 依赖: bash, curl, wget, git, jq, sed, awk, grep, nginx, systemctl, acme.sh
# 配置:
#   - ${HOME}/.acme.sh/: acme.sh 的默认安装和数据目录
#   - ${NGINX_CONFIG_PATH}/: Nginx 配置文件目录
#   - ${ACME_WEBROOT_PATH}/: 用于 HTTP-01 挑战的临时 webroot 目录
#   - ${SSL_CERT_PATH}/: 存放签发证书的目录
#   - ${SCRIPT_CONFIG_DIR}/config.json: 用于读取语言设置 (language)
#   - ${I18N_DIR}/${lang}.json: 用于读取具体的提示文本 (i18n 数据文件)
# 相关链接:
#   - acme.sh 官方仓库: https://github.com/acmesh-official/acme.sh
#   - ZeroSSL CA: https://zerossl.com/
#
# Copyright (C) 2025 zxcvos
# =============================================================================

# set -Eeuxo pipefail

# --- 环境与常量设置 ---
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

# 定义项目中各个重要目录与配置文件的路径
readonly SCRIPT_CONFIG_DIR="${HOME}/.xray-script"              # 主配置文件目录
readonly I18N_DIR="${PROJECT_ROOT}/i18n"                       # 国际化文件目录
readonly SCRIPT_CONFIG_PATH="${SCRIPT_CONFIG_DIR}/config.json" # 脚本主要配置文件路径

# 定义 Nginx 配置、ACME 验证、 SSL 证书的路径
readonly NGINX_CONFIG_PATH='/usr/local/nginx/conf'  # Nginx 配置目录
readonly ACME_WEBROOT_PATH='/var/www/_zerossl'      # ACME HTTP 验证 webroot 目录
readonly SSL_CERT_PATH="${NGINX_CONFIG_PATH}/certs" # SSL 证书存储目录

# --- 全局变量声明 ---
# 声明用于存储脚本操作、域名、邮箱、存储语言参数和国际化数据的全局变量
declare ACTION=''        # 存储用户请求的操作 (如 install, issue)
declare DOMAIN=''        # 存储要操作的域名
declare ACCOUNT_EMAIL='' # 存储 acme.sh 账户邮箱
declare LANG_PARAM=''    # (未在脚本中实际使用，可能是预留)
declare I18N_DATA=''     # 存储从 i18n JSON 文件中读取的全部数据

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
# 函数名称: print_info
# 功能描述: 以绿色打印信息级别的提示消息。
# 参数:
#   $@: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function print_info() {
    # 从 i18n 数据中读取 "信息" 标题，然后用绿色打印消息
    printf "${GREEN}[$(echo "$I18N_DATA" | jq -r '.title.info')] ${NC}%s\n" "$*" >&2
}

# =============================================================================
# 函数名称: print_warn
# 功能描述: 以黄色打印警告级别的提示消息。
# 参数:
#   $@: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2)
# =============================================================================
function print_warn() {
    # 从 i18n 数据中读取 "警告" 标题，然后用黄色打印消息
    printf "${YELLOW}[$(echo "$I18N_DATA" | jq -r '.title.warn')] ${NC}%s\n" "$*" >&2
}

# =============================================================================
# 函数名称: print_error
# 功能描述: 以红色打印错误级别的提示消息，并退出脚本。
# 参数:
#   $@: 消息内容 (msg)
# 返回值: 无 (直接打印到标准错误输出 >&2，然后 exit 1)
# =============================================================================
function print_error() {
    # 从 i18n 数据中读取 "错误" 标题，然后用红色打印消息
    printf "${RED}[$(echo "$I18N_DATA" | jq -r '.title.error')] ${NC}%s\n" "$*" >&2
    # 打印错误信息后退出脚本，错误码为 1
    exit 1
}

# =============================================================================
# 函数名称: install_acme_sh
# 功能描述: 安装 acme.sh 脚本。
# 参数: 无 (使用全局变量 ACCOUNT_EMAIL)
# 返回值: 无 (安装成功或失败后退出)
# =============================================================================
function install_acme_sh() {
    # 检查 acme.sh 是否已经安装
    if [[ -e "${HOME}/.acme.sh/acme.sh" ]]; then
        print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.install.already_installed")"
        return 0
    fi

    # 打印安装信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.install.start")"

    # 使用 curl 下载并运行 acme.sh 安装脚本，设置账户邮箱
    curl https://get.acme.sh | sh -s email="${ACCOUNT_EMAIL}" || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.install.fail_download")"

    # 启用 acme.sh 的自动升级功能
    "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.install.fail_autoupgrade")"

    # 设置 acme.sh 的默认 CA 为 ZeroSSL
    "${HOME}/.acme.sh/acme.sh" --set-default-ca --server zerossl || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.install.fail_set_ca")"
}

# =============================================================================
# 函数名称: update_acme_sh
# 功能描述: 更新 acme.sh 脚本。
# 参数: 无
# 返回值: 无 (更新成功或失败后退出)
# =============================================================================
function update_acme_sh() {
    # 打印更新信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.update.start")"

    # 执行 acme.sh 的升级命令
    "${HOME}/.acme.sh/acme.sh" --upgrade || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.update.fail")"
}

# =============================================================================
# 函数名称: purge_acme_sh
# 功能描述: 卸载 acme.sh 并删除相关目录。
# 参数: 无
# 返回值: 无 (卸载成功后打印信息并退出)
# =============================================================================
function purge_acme_sh() {
    # 打印卸载信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.purge.start")"

    # 检查 acme.sh 是否存在
    if [[ -e "${HOME}/.acme.sh/acme.sh" ]]; then
        # 禁用 acme.sh 的自动升级
        "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade 0 || print_warn "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.purge.fail_disable_autoupgrade")"
        # 执行 acme.sh 的卸载命令
        "${HOME}/.acme.sh/acme.sh" --uninstall || print_warn "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.purge.fail_uninstall_cmd")"
    fi

    # 删除 acme.sh 相关目录和文件
    rm -rf "${HOME}/.acme.sh" "${ACME_WEBROOT_PATH}" "${NGINX_CONFIG_PATH}/certs"
    # 打印删除成功信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.purge.success")"
}

# =============================================================================
# 函数名称: issue_certificate
# 功能描述: 为指定域名签发 SSL 证书。
# 参数: 无 (使用全局变量 DOMAIN)
# 返回值: 无 (签发成功或失败后退出)
# =============================================================================
function issue_certificate() {
    # 检查是否提供了域名
    if [[ ${#DOMAIN} -eq 0 ]]; then
        print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.no_domain")"
    fi

    # 定义证书存储路径
    local cert_path="${SSL_CERT_PATH}/${DOMAIN}"

    # 打印签发信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.start")"

    # 创建 ACME 验证目录
    [[ -d "${ACME_WEBROOT_PATH}" ]] || mkdir -vp "${ACME_WEBROOT_PATH}" || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_create_acme_dir" | sed "s|\${ACME_WEBROOT_PATH}|${ACME_WEBROOT_PATH}|")"
    # 创建证书存储目录
    [[ -d "${cert_path}" ]] || mkdir -vp "${cert_path}" || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_create_cert_dir" | sed "s|\${cert_path}|${cert_path}|")"

    # 定义 Nginx 配置文件及其备份路径
    local nginx_conf="${NGINX_CONFIG_PATH}/nginx.conf"
    local nginx_conf_bak="${nginx_conf}.ssl_script.bak"

    # 如果原 Nginx 配置文件存在，则备份
    if [[ -f "${nginx_conf}" ]]; then
        cp -f "${nginx_conf}" "${nginx_conf_bak}" || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_backup_nginx" | sed "s|\${nginx_conf}|${nginx_conf}|")"
    fi

    # 生成一个临时的 Nginx 配置文件，用于 ACME HTTP-01 验证
    cat >"${nginx_conf}" <<EOF
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
            root ${ACME_WEBROOT_PATH};
        }
    }
}
EOF

    # 检查 Nginx 是否正在运行
    if systemctl is-active --quiet nginx; then
        # 如果运行，则测试配置并重载
        nginx -t && systemctl reload nginx || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_reload_nginx")"
    else
        # 如果未运行，则测试配置并启动
        nginx -t && systemctl start nginx || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_start_nginx")"
    fi

    # 使用 acme.sh 签发 ECC 证书
    "${HOME}/.acme.sh/acme.sh" --issue -d ${DOMAIN} \
        --webroot "${ACME_WEBROOT_PATH}" \
        --keylength ec-256 \
        --accountkeylength ec-256 \
        --server zerossl \
        --ocsp

    # 检查签发命令的退出状态
    local issue_status=$?
    if [[ ${issue_status} -ne 0 ]]; then
        # 如果首次签发失败，则尝试启用调试模式重新签发
        print_warn "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_first_attempt")"
        "${HOME}/.acme.sh/acme.sh" --issue -d ${DOMAIN} \
            --webroot "${ACME_WEBROOT_PATH}" \
            --keylength ec-256 \
            --accountkeylength ec-256 \
            --server zerossl \
            --ocsp \
            --debug
        # 恢复原始 Nginx 配置
        mv -f "${nginx_conf_bak}" "${nginx_conf}"
        # 打印错误并退出
        print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_ecc_issue")"
    fi

    # 签发成功后，恢复原始 Nginx 配置
    mv -f "${nginx_conf_bak}" "${nginx_conf}"

    # 安装签发的证书到指定路径，并设置 Nginx 重载命令
    "${HOME}/.acme.sh/acme.sh" --install-cert --ecc -d ${DOMAIN} \
        --key-file "${cert_path}/privkey.pem" \
        --fullchain-file "${cert_path}/fullchain.pem" \
        --reloadcmd "nginx -t && systemctl reload nginx" || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.issue.fail_install_cert")"
}

# =============================================================================
# 函数名称: renew_certificates
# 功能描述: 强制续期所有由 acme.sh 管理的 SSL 证书。
# 参数: 无
# 返回值: 无 (续期成功或失败后退出)
# =============================================================================
function renew_certificates() {
    # 打印续期信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.renew.start")"

    # 执行 acme.sh 的强制续期命令
    "${HOME}/.acme.sh/acme.sh" --cron --force || print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.renew.fail")"
}

# =============================================================================
# 函数名称: stop_renew_certificates
# 功能描述: 停止对指定域名的证书续期。
# 参数: 无 (使用全局变量 DOMAIN)
# 返回值: 无 (操作成功或失败后打印信息)
# =============================================================================
function stop_renew_certificates() {
    # 打印停止续期信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.stop_renew.start")"

    # 检查是否提供了域名
    if [[ ${#DOMAIN} -gt 0 ]]; then
        # 执行 acme.sh 的移除命令（停止续期）
        "${HOME}/.acme.sh/acme.sh" --remove -d ${DOMAIN} --ecc || print_warn "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.stop_renew.fail_cmd")"
        # 删除该域名的 acme.sh 本地存储目录
        rm -rf "${HOME}/.acme.sh/${DOMAIN}_ecc" # 更健壮的路径处理
        # 删除该域名的本地证书目录
        rm -rf "${NGINX_CONFIG_PATH}/certs/${DOMAIN}" # 更健壮的路径处理
    else
        # 如果未提供域名，则打印警告
        print_warn "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.stop_renew.no_domain")"
    fi
}

# =============================================================================
# 函数名称: check_cron_jobs
# 功能描述: 检查 acme.sh 的自动续期定时任务设置。
# 参数: 无
# 返回值: 无 (打印检查信息)
# =============================================================================
function check_cron_jobs() {
    # 打印检查信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.check_cron.start")"

    # 执行 acme.sh 的 cron 检查命令
    "${HOME}/.acme.sh/acme.sh" --cron --home "${HOME}/.acme.sh"
}

# =============================================================================
# 函数名称: check_certificate_status
# 功能描述: 检查指定域名的证书是否已由 acme.sh 管理。
# 参数: 无 (使用全局变量 DOMAIN)
# 返回值: 0-证书存在 1-证书不存在 (由命令检查结果决定)
# =============================================================================
function check_certificate_status() {
    # 检查是否提供了域名
    if [[ ${#DOMAIN} -eq 0 ]]; then
        print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.status.no_domain")"
    fi

    # 从 acme.sh 列表中查找匹配的域名
    local main_domain=$(
        "${HOME}/.acme.sh/acme.sh" --list --home "${HOME}/.acme.sh" |
            grep -E "^${DOMAIN}" |
            awk '{print $1}'
    )

    # 比较找到的域名与提供的域名
    [[ "${main_domain}" == "${DOMAIN}" ]]
}

# =============================================================================
# 函数名称: show_certificate_info
# 功能描述: 显示指定域名证书的详细信息。
# 参数: 无 (使用全局变量 DOMAIN)
# 返回值: 无 (打印证书信息)
# =============================================================================
function show_certificate_info() {
    # 检查是否提供了域名
    if [[ ${#DOMAIN} -eq 0 ]]; then
        print_error "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.info.no_domain")"
    fi

    # 打印显示信息
    print_info "$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.info.start")"

    # 执行 acme.sh 的信息显示命令
    "${HOME}/.acme.sh/acme.sh" --info -d ${DOMAIN}
}

# =============================================================================
# 函数名称: show_help
# 功能描述: 显示脚本的使用帮助信息。
# 参数: 无
# 返回值: 无 (打印帮助信息后 exit 0)
# =============================================================================
function show_help() {
    # 从 i18n 数据中读取帮助信息的各个部分
    local usage="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.usage" | sed "s|\${script_name}|$0|")"
    local commands_title="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.commands_title")"
    local cmd_install="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_install")"
    local cmd_update="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_update")"
    local cmd_purge="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_purge")"
    local cmd_issue="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_issue")"
    local cmd_renew="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_renew")"
    local cmd_stop_renew="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_stop_renew")"
    local cmd_check_cron="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_check_cron")"
    local cmd_info="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_info")"
    local cmd_status="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_status")"
    local cmd_help="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.cmd_help")"
    local options_title="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.options_title")"
    local opt_domain="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.opt_domain")"
    local opt_email="$(echo "$I18N_DATA" | jq -r ".${CUR_FILE}.help.opt_email")"

    # 使用 here document 打印帮助信息
    cat <<EOF
${usage}
${commands_title}:
  --install           ${cmd_install}
  --update            ${cmd_update}
  --purge             ${cmd_purge}
  --issue             ${cmd_issue}
  --renew             ${cmd_renew}
  --stop-renew        ${cmd_stop_renew}
  --check-cron        ${cmd_check_cron}
  --info              ${cmd_info}
  --status            ${cmd_status}
  --help              ${cmd_help}
${options_title}:
  --domain            ${opt_domain}
  --email             ${opt_email}
EOF
    # 退出脚本，状态码为 0 (成功)
    exit 0
}

# =============================================================================
# 函数名称: main
# 功能描述: 脚本的主入口函数。
#           1. 加载国际化数据。
#           2. 解析命令行参数。
#           3. 根据参数执行相应的操作函数。
# 参数:
#   $@: 所有命令行参数
# 返回值: 无 (协调调用其他函数完成操作)
# =============================================================================
function main() {
    # 加载国际化数据
    load_i18n

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        # 匹配操作命令
        --install | --update | --purge | --issue | --renew | --stop-renew | --check-cron | --status | --info)
            ACTION="${1#--}" # 提取操作名称
            ;;
        # 匹配域名选项
        --domain=*)
            DOMAIN="${1#*=}" # 提取域名
            ;;
        # 匹配邮箱选项
        --email=*)
            ACCOUNT_EMAIL="${1#*=}" # 提取邮箱
            ;;
        # 匹配帮助或未知选项
        --help | *)
            show_help # 显示帮助并退出
            ;;
        esac
        shift # 移动到下一个参数
    done

    # 如果没有提供操作命令，则显示帮助
    [[ -z ${ACTION} ]] && show_help

    # 根据 ACTION 变量的值调用相应的函数
    case "${ACTION}" in
    install) install_acme_sh ;;            # 安装 acme.sh
    update) update_acme_sh ;;              # 更新 acme.sh
    purge) purge_acme_sh ;;                # 卸载 acme.sh
    issue) issue_certificate ;;            # 签发证书
    renew) renew_certificates ;;           # 续期证书
    stop-renew) stop_renew_certificates ;; # 停止续期
    check-cron) check_cron_jobs ;;         # 检查 cron
    status) check_certificate_status ;;    # 检查状态
    info) show_certificate_info ;;         # 显示信息
    esac
}

# --- 脚本执行入口 ---
# 将脚本接收到的所有参数传递给 main 函数开始执行
main "$@"
