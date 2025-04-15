#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian 10+, Ubuntu 20+
# Description:      Script to SSL manage
#
# Copyright (C) 2025 zxcvos
#
# optimized by AI(Qwen2.5-Max-QwQ)
#
# acme.sh: https://github.com/acmesh-official/acme.sh

# 颜色定义
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

# 可选参数正则表达式
readonly OP_REGEX='(^--(help|update|purge|issue|(stop-)?renew|check-cron|info|www|domain|email|nginx|webroot|tls)$)|(^-[upirscdenwt]$)'

# 用户操作
declare action=''

# 可选值
declare -a domains=()
declare account_email=''
declare nginx_config_path=''
declare acme_webroot_path=''
declare ssl_cert_path=''

# 状态打印函数
function print_info() {
  printf "${GREEN}[信息] ${NC}%s\n" "$*"
}

function print_warn() {
  printf "${YELLOW}[警告] ${NC}%s\n" "$*"
}

function print_error() {
  printf "${RED}[错误] ${NC}%s\n" "$*"
  exit 1
}

# 安装 acme.sh
function install_acme_sh() {
  [[ -e "${HOME}/.acme.sh/acme.sh" ]] && exit 0
  print_info "正在安装 acme.sh..."
  curl https://get.acme.sh | sh -s email=${account_email} || print_error "acme.sh 安装失败。"
  "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade || print_error "acme.sh 自动升级设置失败。"
  "${HOME}/.acme.sh/acme.sh" --set-default-ca --server zerossl || print_error "设置默认 CA 失败。"
}

# 更新 acme.sh
function update_acme_sh() {
  print_info "正在更新 acme.sh..."
  "${HOME}/.acme.sh/acme.sh" --upgrade || print_error "acme.sh 更新失败。"
}

# 卸载 acme.sh
function purge_acme_sh() {
  print_info "正在卸载 acme.sh..."
  "${HOME}/.acme.sh/acme.sh" --upgrade --auto-upgrade 0 || print_error "禁用 acme.sh 自动升级失败。"
  "${HOME}/.acme.sh/acme.sh" --uninstall || print_error "acme.sh 卸载失败。"
  rm -rf "${HOME}/.acme.sh" "${acme_webroot_path}" "${nginx_config_path}/certs"
}

# 签发证书
function issue_certificate() {
  print_info "正在签发 SSL 证书..."

  # 创建必要的目录
  [[ -d "${acme_webroot_path}" ]] || mkdir -vp "${acme_webroot_path}" || print_error "无法创建 ACME 验证目录: ${acme_webroot_path}"
  [[ -d "${ssl_cert_path}" ]] || mkdir -vp "${ssl_cert_path}" || print_error "无法创建 SSL 证书目录: ${ssl_cert_path}"

  # 备份原始配置
  mv -f /usr/local/nginx/conf/nginx.conf /usr/local/nginx/conf/nginx.conf.bak

  # 创建申请证书专用配置
  cat >/usr/local/nginx/conf/nginx.conf <<EOF
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
            root /var/www/_zerossl;
        }
    }
}
EOF

  # 确保 Nginx 正在运行
  if systemctl is-active --quiet nginx; then
    nginx -t && systemctl reload nginx || print_error "Nginx 启动失败，请检查配置文件。"
  else
    nginx -t && systemctl start nginx || print_error "Nginx 启动失败，请检查配置文件。"
  fi

  # 签发证书
  "${HOME}/.acme.sh/acme.sh" --issue $(printf -- " -d %s" "${domains[@]}") \
    --webroot "${acme_webroot_path}" \
    --keylength ec-256 \
    --accountkeylength ec-256 \
    --server zerossl \
    --ocsp

  if [[ $? -ne 0 ]]; then
    print_warn "首次签发失败，尝试启用调试模式重新签发..."
    "${HOME}/.acme.sh/acme.sh" --issue $(printf -- " -d %s" "${domains[@]}") \
      --webroot "${acme_webroot_path}" \
      --keylength ec-256 \
      --accountkeylength ec-256 \
      --server zerossl \
      --ocsp \
      --debug
    # 恢复原始配置
    mv -f /usr/local/nginx/conf/nginx.conf.bak /usr/local/nginx/conf/nginx.conf
    print_error "ECC 证书申请失败。"
  fi

  # 恢复原始配置
  mv -f /usr/local/nginx/conf/nginx.conf.bak /usr/local/nginx/conf/nginx.conf

  # 重启 nginx
  nginx -t && systemctl reload nginx || print_error "Nginx 启动失败，请检查配置文件。"

  # 安装证书
  "${HOME}/.acme.sh/acme.sh" --install-cert --ecc $(printf -- " -d %s" "${domains[@]}") \
    --key-file "${ssl_cert_path}/privkey.pem" \
    --fullchain-file "${ssl_cert_path}/fullchain.pem" \
    --reloadcmd "nginx -t && systemctl reload nginx" || print_error "安装证书失败。"
}

# 续期证书
function renew_certificates() {
  print_info "正在强制续期所有 SSL 证书..."
  "${HOME}/.acme.sh/acme.sh" --cron --force || print_error "续期失败。"
}

# 停止续期证书
function stop_renew_certificates() {
  print_info "正在停止续期指定的 SSL 证书..."
  "${HOME}/.acme.sh/acme.sh" --remove $(printf -- " -d %s" "${domains[@]}") --ecc || print_error "停止续期失败。"
  rm -rf $(printf -- " ${HOME}/.acme.sh/%s_ecc" "${domains[@]}")
  rm -rf $(printf -- " ${nginx_config_path}/certs/%s" "${domains[@]}")
}

# 检查定时任务
function check_cron_jobs() {
  print_info "正在检查自动续期的定时任务设置..."
  "${HOME}/.acme.sh/acme.sh" --cron --home "${HOME}/.acme.sh" || print_error "检查定时任务失败。"
}

# 显示证书信息
function show_certificate_info() {
  print_info "正在显示 SSL 证书信息..."
  "${HOME}/.acme.sh/acme.sh" --info $(printf -- " -d %s" "${domains[@]}") || print_error "获取证书信息失败。"
}

# 查询 nginx 配置目录
function find_nginx_config() {
  if [[ -d /etc/nginx ]]; then
    echo "/etc/nginx"
  elif [[ -d /usr/local/nginx/conf ]]; then
    echo "/usr/local/nginx/conf"
  else
    print_error "未找到 Nginx 配置路径"
  fi
}

# 显示帮助信息
function show_help() {
  cat <<EOF
用法: $0 [命令] [选项]

命令:
  --install           安装 acme.sh
  -u, --update        更新 acme.sh
  -p, --purge         卸载 acme.sh 并删除相关目录
  -i, --issue         签发/更新 SSL 证书
  -r, --renew         强制续期所有 SSL 证书
  -s, --stop-renew    停止续期指定的 SSL 证书
  -c, --check-cron    检查自动续期的定时任务设置
      --info          显示 SSL 证书信息

选项:
  -d, --domain        指定域名（可多次使用以指定多个域名）
  -n, --nginx         指定 Nginx 配置路径
  -w, --webroot       指定 ACME 验证目录路径
  -t, --tls           指定 SSL 证书目录路径（默认基于第一个域名）
  -h, --help          显示此帮助信息
EOF
  exit 0
}

# 参数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
  --install)
    action="install"
    ;;
  -u | --update)
    action="update"
    ;;
  -p | --purge)
    action="purge"
    ;;
  -i | --issue)
    action="issue"
    ;;
  -r | --renew)
    action="renew"
    ;;
  -s | --stop-renew)
    action="stop"
    ;;
  -c | --check-cron)
    action="check"
    ;;
  --info)
    action="info"
    ;;
  -d | --domain)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "未提供有效的域名"
    domains+=("$1")
    ;;
  -e | --email)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "未提供邮箱"
    account_email="$1"
    ;;
  -n | --nginx)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "未提供有效的 Nginx 配置路径"
    nginx_config_path="$1"
    ;;
  -w | --webroot)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "未提供有效的 ACME 验证目录路径"
    acme_webroot_path="$1"
    ;;
  -t | --tls)
    shift
    [[ -z "$1" || "$1" =~ ${OP_REGEX} ]] && print_error "未提供有效的 SSL 证书目录路径"
    ssl_cert_path="$1"
    ;;
  -h | --help)
    show_help
    ;;
  *)
    print_error "无效选项: '$1'。使用 '$0 -h/--help' 查看用法信息。"
    ;;
  esac
  shift
done

# 参数验证
[[ -z ${action} ]] && print_error "未指定操作。使用 --help 了解用法"

# 初始化默认值
nginx_config_path=${nginx_config_path:-$(find_nginx_config)}
account_email=${account_email:-my@example.com}
acme_webroot_path=${acme_webroot_path:-/var/www/_zerossl}
ssl_cert_path=${ssl_cert_path:-${nginx_config_path}/certs/${domains[0]:-default}}

# 检查 acme.sh 是否已安装
if [[ ! -e "${HOME}/.acme.sh/acme.sh" && 'install' != ${action} ]]; then
  print_error "请先使用 使用 '$0 --install [--email my@email.com]' 安装 acme.sh"
fi

# 执行操作
case "${action}" in
install) install_acme_sh ;;
update) update_acme_sh ;;
purge) purge_acme_sh ;;
issue) issue_certificate ;;
renew) renew_certificates ;;
stop) stop_renew_certificates ;;
check) check_cron_jobs ;;
info) show_certificate_info ;;
esac
