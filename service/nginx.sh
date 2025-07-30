#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Rocky 8+, Debian10+, Ubuntu20+
# Description:      Script to Nginx manage
#
# Copyright (C) 2025 zxcvos
#
# optimized by AI(Qwen2.5-Max-QwQ)
#
# Xray-script: https://github.com/zxcvos/Xray-script
#
# NGINX:
#   documentation: https://nginx.org/en/linux_packages.html
#   update: https://zhuanlan.zhihu.com/p/193078620
#   gcc: https://github.com/kirin10000/Xray-script
#   brotli: https://www.nodeseek.com/post-37224-1
#   ngx_brotli: https://github.com/google/ngx_brotli

# set -Eeuxo pipefail

# 设置基础环境路径
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin:/snap/bin
export PATH

trap egress EXIT

# 定义ANSI颜色代码
readonly RED='\033[31m'    # 红色 - 用于警告/错误
readonly GREEN='\033[32m'  # 绿色 - 用于正常提示
readonly YELLOW='\033[33m' # 黄色 - 用于强调重点
readonly NC='\033[0m'      # 重置颜色

# 定义当前脚本（service目录）的绝对路径
readonly CUR_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
# 定位项目根目录（父目录）
readonly PROJECT_ROOT="$(cd -P -- "${CUR_DIR}/.." && pwd -P)"
# 临时目录
readonly TMPFILE_DIR="$(mktemp -d -p "${PROJECT_ROOT}" -t nginxtemp.XXXXXXXX)" || exit 1

# 全局常量
readonly NGINX_PATH="/usr/local/nginx"
readonly NGINX_LOG_PATH="/var/log/nginx"

# 全局变量
declare is_enable_brotli=""

# 退出处理
function egress() {
    [[ -e "${TMPFILE_DIR}/swap" ]] && swapoff "${TMPFILE_DIR}/swap"
    rm -rf "${TMPFILE_DIR}"
}

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

# 工具函数
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
    print_info "正在执行命令: ${cmd}"
    eval ${cmd}
    if [[ $? -ne 0 ]]; then
        print_error "执行命令 (${cmd}) 失败，请检查并重试。"
    fi
}

function _version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

function _install() {
    local packages_name="$@"
    local installed_packages=""
    case "$(_os)" in
    centos)
        if _exists "dnf"; then
            packages_name="dnf-plugins-core epel-release epel-next-release ${packages_name}"
            installed_packages="$(dnf list installed 2>/dev/null)"
            if [[ -n "$(_os_ver)" && "$(_os_ver)" -eq 9 ]]; then
                # 启用 EPEL 和 Remi 仓库
                if [[ "${packages_name}" =~ geoip\-devel ]] && ! echo "${installed_packages}" | grep -iwq "geoip-devel"; then
                    dnf update -y
                    _error_detect "dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm"
                    _error_detect "dnf install -y https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-9.noarch.rpm"
                    _error_detect "dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm"
                    # 启用 Remi 模块化仓库
                    _error_detect "dnf config-manager --set-enabled remi-modular"
                    # 刷新包信息
                    _error_detect "dnf update --refresh"
                    # 安装 GeoIP-devel，指定使用 Remi 仓库
                    dnf update -y
                    _error_detect "dnf --enablerepo=remi install -y GeoIP-devel"
                fi
            elif [[ -n "$(_os_ver)" && "$(_os_ver)" -eq 8 ]]; then
                if ! dnf module list 2>/dev/null | grep container-tools | grep -iwq "\[x\]"; then
                    _error_detect "dnf module disable -y container-tools"
                fi
            fi
            dnf update -y
            for package_name in ${packages_name}; do
                if ! echo "${installed_packages}" | grep -iwq "${package_name}"; then
                    _error_detect "dnf install -y "${package_name}""
                fi
            done
        else
            packages_name="epel-release yum-utils ${packages_name}"
            installed_packages="$(yum list installed 2>/dev/null)"
            yum update -y
            for package_name in ${packages_name}; do
                if ! echo "${installed_packages}" | grep -iwq "${package_name}"; then
                    _error_detect "yum install -y "${package_name}""
                fi
            done
        fi
        ;;
    ubuntu | debian)
        apt update -y
        installed_packages="$(apt list --installed 2>/dev/null)"
        for package_name in ${packages_name}; do
            if ! echo "${installed_packages}" | grep -iwq "${package_name}"; then
                _error_detect "apt install -y "${package_name}""
            fi
        done
        ;;
    esac
}

# 检查操作系统
function check_os() {
    [[ -z "$(_os)" ]] && print_error "不支持的操作系统。"
    case "$(_os)" in
    ubuntu)
        [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 20 ]] && print_error "不支持的操作系统，请切换到 Ubuntu 20+ 并重试。"
        ;;
    debian)
        [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 10 ]] && print_error "不支持的操作系统，请切换到 Debian 10+ 并重试。"
        ;;
    centos)
        [[ -n "$(_os_ver)" && "$(_os_ver)" -lt 7 ]] && print_error "不支持的操作系统，请切换到 CentOS 7+ 并重试。"
        ;;
    *)
        print_error "不支持的操作系统。"
        ;;
    esac
}

# 启用交换分区
function swap_on() {
    local mem=${1}
    if [[ ${mem} -ne '0' ]]; then
        if dd if=/dev/zero of="${TMPFILE_DIR}/swap" bs=1M count=${mem} 2>&1; then
            chmod 0600 "${TMPFILE_DIR}/swap"
            mkswap "${TMPFILE_DIR}/swap"
            swapon "${TMPFILE_DIR}/swap"
        fi
    fi
}

# 备份文件
function backup_files() {
    local backup_dir="$1"
    local current_date="$(date +%F)"
    for file in "${backup_dir}/"*; do
        if [[ -f "$file" ]]; then
            local file_name="$(basename "$file")"
            local backup_file="${backup_dir}/${file_name}_${current_date}"
            mv "$file" "$backup_file"
            echo "备份: ${file} -> ${backup_file}。"
        fi
    done
}

# 编译依赖项
function compile_dependencies() {
    # 常规依赖
    _install ca-certificates curl wget gcc make git openssl tzdata
    case "$(_os)" in
    centos)
        # 工具链
        _install gcc-c++ perl-IPC-Cmd perl-Getopt-Long perl-Data-Dumper
        # 编译依赖
        _install pcre2-devel zlib-devel libxml2-devel libxslt-devel gd-devel geoip-devel perl-ExtUtils-Embed gperftools-devel perl-devel brotli-devel
        if ! perl -e "use FindBin" &>/dev/null; then
            _install perl-FindBin
        fi
        ;;
    debian | ubuntu)
        # 工具链
        _install g++ perl-base perl
        # 编译依赖
        _install libpcre2-dev zlib1g-dev libxml2-dev libxslt1-dev libgd-dev libgeoip-dev libgoogle-perftools-dev libperl-dev libbrotli-dev
        ;;
    esac
}

# 生成编译选项
function gen_cflags() {
    cflags=('-g0' '-O3')
    if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-reuse"; then
        cflags+=('-fstack-reuse=all')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fdwarf2\\-cfi\\-asm"; then
        cflags+=('-fdwarf2-cfi-asm')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fplt"; then
        cflags+=('-fplt')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-ftrapv"; then
        cflags+=('-fno-trapv')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fexceptions"; then
        cflags+=('-fno-exceptions')
    elif gcc -v --help 2>&1 | grep -qw "\\-fhandle\\-exceptions"; then
        cflags+=('-fno-handle-exceptions')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-funwind\\-tables"; then
        cflags+=('-fno-unwind-tables')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fasynchronous\\-unwind\\-tables"; then
        cflags+=('-fno-asynchronous-unwind-tables')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-check"; then
        cflags+=('-fno-stack-check')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-clash\\-protection"; then
        cflags+=('-fno-stack-clash-protection')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fstack\\-protector"; then
        cflags+=('-fno-stack-protector')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fcf\\-protection="; then
        cflags+=('-fcf-protection=none')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fsplit\\-stack"; then
        cflags+=('-fno-split-stack')
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-fsanitize"; then
        >temp.c
        if gcc -E -fno-sanitize=all temp.c >/dev/null 2>&1; then
            cflags+=('-fno-sanitize=all')
        fi
        rm temp.c
    fi
    if gcc -v --help 2>&1 | grep -qw "\\-finstrument\\-functions"; then
        cflags+=('-fno-instrument-functions')
    fi
}

# 源码编译
function source_compile() {
    cd "${TMPFILE_DIR}"
    # 最新版本
    print_info "检索 Nginx 和 OpenSSL 的最新版本。"
    local nginx_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/nginx/nginx/tags | grep 'name' | cut -d\" -f4 | grep 'release' | head -1 | sed 's/release/nginx/')"
    local openssl_version="openssl-$(wget -qO- --no-check-certificate https://api.github.com/repos/openssl/openssl/tags | grep 'name' | cut -d\" -f4 | grep -Eoi '^openssl-([0-9]\.?){3}$' | head -1)"
    # 生成编译选项
    gen_cflags
    # nginx
    print_info "下载最新版本的 Nginx。"
    _error_detect "curl -fsSL -o ${nginx_version}.tar.gz https://nginx.org/download/${nginx_version}.tar.gz"
    tar -zxf "${nginx_version}.tar.gz"
    # openssl
    print_info "下载最新版本的 OpenSSL。"
    _error_detect "curl -fsSL -o ${openssl_version}.tar.gz https://github.com/openssl/openssl/archive/${openssl_version#*-}.tar.gz"
    tar -zxf "${openssl_version}.tar.gz"
    if [[ "${is_enable_brotli}" =~ ^[Yy]$ ]]; then
        # brotli
        print_info "检索 ngx_brotli 并构建依赖项。"
        _error_detect "git clone https://github.com/google/ngx_brotli && cd ngx_brotli && git submodule update --init"
        cd "${TMPFILE_DIR}"
    fi
    # 配置
    cd "${nginx_version}"
    sed -i "s/OPTIMIZE[ \\t]*=>[ \\t]*'-O'/OPTIMIZE          => '-O3'/g" src/http/modules/perl/Makefile.PL
    sed -i 's/NGX_PERL_CFLAGS="$CFLAGS `$NGX_PERL -MExtUtils::Embed -e ccopts`"/NGX_PERL_CFLAGS="`$NGX_PERL -MExtUtils::Embed -e ccopts` $CFLAGS"/g' auto/lib/perl/conf
    sed -i 's/NGX_PM_CFLAGS=`$NGX_PERL -MExtUtils::Embed -e ccopts`/NGX_PM_CFLAGS="`$NGX_PERL -MExtUtils::Embed -e ccopts` $CFLAGS"/g' auto/lib/perl/conf
    if [[ "${is_enable_brotli}" =~ ^[Yy]$ ]]; then
        ./configure --prefix="${NGINX_PATH}" --user=root --group=root --with-threads --with-file-aio --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_auth_request_module --with-http_random_index_module --with-http_secure_link_module --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-http_perl_module=dynamic --with-mail=dynamic --with-mail_ssl_module --with-stream --with-stream_ssl_module --with-stream_realip_module --with-stream_geoip_module=dynamic --with-stream_ssl_preread_module --with-google_perftools_module --add-module="../ngx_brotli" --with-compat --with-cc-opt="${cflags[*]}" --with-openssl="../${openssl_version}" --with-openssl-opt="${cflags[*]}"
    else
        ./configure --prefix="${NGINX_PATH}" --user=root --group=root --with-threads --with-file-aio --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_auth_request_module --with-http_random_index_module --with-http_secure_link_module --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-http_perl_module=dynamic --with-mail=dynamic --with-mail_ssl_module --with-stream --with-stream_ssl_module --with-stream_realip_module --with-stream_geoip_module=dynamic --with-stream_ssl_preread_module --with-google_perftools_module --with-compat --with-cc-opt="${cflags[*]}" --with-openssl="../${openssl_version}" --with-openssl-opt="${cflags[*]}"
    fi
    print_info "申请 512MB 虚拟内存。"
    swap_on 512
    # 编译
    print_info "编译 Nginx。"
    _error_detect "make -j$(nproc)"
}

# 安装 nginx
function source_install() {
    source_compile
    print_info "安装 Nginx。"
    make install
    mkdir -p /var/log/nginx
    ln -sf "${NGINX_PATH}/sbin/nginx" /usr/sbin/nginx
}

# 更新 nginx
function source_update() {
    # 最新版本
    print_info "检索 Nginx 和 OpenSSL 的最新版本。"
    local latest_nginx_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/nginx/nginx/tags | grep 'name' | cut -d\" -f4 | grep 'release' | head -1 | sed 's/release/nginx/')"
    local latest_openssl_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/openssl/openssl/tags | grep 'name' | cut -d\" -f4 | grep -Eoi '^openssl-([0-9]\.?){3}$' | head -1)"
    # 当前版本
    print_info "读取 Nginx 和 OpenSSL 的当前版本。"
    local current_version_nginx="$(nginx -V 2>&1 | grep "^nginx version:.*" | cut -d / -f 2)"
    local current_version_openssl="$(nginx -V 2>&1 | grep "^built with OpenSSL" | awk '{print $4}')"
    # 比较
    print_info "判断是否需要更新。"
    if _version_ge "${latest_nginx_version#*-}" "${current_version_nginx}" || _version_ge "${latest_openssl_version#*-}" "${current_version_openssl}"; then
        source_compile
        print_info "更新 Nginx。"
        mv "${NGINX_PATH}/sbin/nginx" "${NGINX_PATH}/sbin/nginx_$(date +%F)"
        backup_files "${NGINX_PATH}/modules"
        cp objs/nginx "${NGINX_PATH}/sbin/"
        cp objs/*.so "${NGINX_PATH}/modules/"
        ln -sf "${NGINX_PATH}/sbin/nginx" /usr/sbin/nginx
        if systemctl is-active --quiet nginx; then
            kill -USR2 $(cat /run/nginx.pid)
            if [[ -e "/run/nginx.pid.oldbin" ]]; then
                kill -WINCH $(cat /run/nginx.pid.oldbin)
                kill -HUP $(cat /run/nginx.pid.oldbin)
                kill -QUIT $(cat /run/nginx.pid.oldbin)
            else
                print_info "未找到旧的 Nginx 进程。跳过后续步骤。"
            fi
        fi
        return 0
    fi
    return 1
}

# 卸载 nginx
function purge_nginx() {
    systemctl stop nginx
    rm -rf "${NGINX_PATH}"
    rm -rf /usr/sbin/nginx
    rm -rf /etc/systemd/system/nginx.service
    rm -rf "${NGINX_LOG_PATH}"
    systemctl daemon-reload
}

function systemctl_config_nginx() {
    cat >/etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/bin/rm -rf /dev/shm/nginx
ExecStartPre=/bin/mkdir /dev/shm/nginx
ExecStartPre=/bin/chmod 711 /dev/shm/nginx
ExecStartPre=/bin/mkdir /dev/shm/nginx/tcmalloc
ExecStartPre=/bin/chmod 0777 /dev/shm/nginx/tcmalloc
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
ExecStopPost=/bin/rm -rf /dev/shm/nginx
TimeoutStopSec=5
KillMode=mixed
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

function show_help() {
    cat <<EOF
用法: $0 [选项]

选项:
  -i, --install      安装 Nginx
  -u, --update       更新 Nginx
  -b, --brotli       启用 Brotli 压缩
  -p, --purge        卸载 Nginx
  -h, --help         显示帮助信息
EOF
    exit 0
}

check_os

# 参数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
    -i | --install)
        action="install"
        ;;
    -u | --update)
        action="update"
        ;;
    -b | --brotli)
        is_enable_brotli='Y'
        ;;
    -p | --purge)
        action="purge"
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

# 执行操作
case "${action}" in
install)
    compile_dependencies
    source_install
    systemctl_config_nginx
    ;;
update)
    compile_dependencies
    source_update
    ;;
purge)
    purge_nginx
    ;;
esac
