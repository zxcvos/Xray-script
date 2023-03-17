#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian10+, Ubuntu16+
# Description:      Script to Xray manage
#
# Copyright (C) 2023 zxcvos
#
# Xray-script: https://github.com/zxcvos/Xray-script
# Xray-core: https://github.com/XTLS/Xray-core
# REALITY: https://github.com/XTLS/REALITY
# Xray-examples: https://github.com/chika0801/Xray-examples
# Nginx Config: https://www.digitalocean.com/community/tools/nginx?domains.0.server.wwwSubdomain=true&domains.0.https.hstsPreload=true&domains.0.php.php=false&domains.0.reverseProxy.reverseProxy=true&domains.0.reverseProxy.proxyHostHeader=%24proxy_host&domains.0.routing.root=false&domains.0.logging.accessLogEnabled=false&domains.0.logging.errorLogEnabled=false&global.https.portReuse=true&global.nginx.user=root&global.nginx.clientMaxBodySize=50&global.app.lang=zhCN
# Nginx Install: https://nginx.org/en/linux_packages.html
# ACME: https://github.com/acmesh-official/acme.sh
# Cloudreve: https://github.com/cloudreve/cloudreve

readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

declare domain
declare new_ssh_port

function _info() {
    printf "${GREEN}[Info] ${NC}"
    printf -- "%s" "$1"
    printf "\n"
}

function _warn() {
    printf "${YELLOW}[Warning] ${NC}"
    printf -- "%s" "$1"
    printf "\n"
}

function _error() {
    printf "${RED}[Error] ${NC}"
    printf -- "%s" "$1"
    printf "\n"
    exit 1
}

function _exists() {
    local cmd="$1"
    if eval type type > /dev/null 2>&1; then
        eval type "$cmd" > /dev/null 2>&1
    elif command > /dev/null 2>&1; then
        command -v "$cmd" > /dev/null 2>&1
    else
        which "$cmd" > /dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

function _os() {
    local os=""
    [ -f "/etc/debian_version" ] && source /etc/os-release && os="${ID}" && printf -- "%s" "${os}" && return
    [ -f "/etc/redhat-release" ] && os="centos" && printf -- "%s" "${os}" && return
}

function _os_full() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

function _os_ver() {
    local main_ver="$( echo $(_os_full) | grep -oE "[0-9.]+")"
    printf -- "%s" "${main_ver%%.*}"
}

function _error_detect() {
    local cmd="$1"
    _info "${cmd}"
    eval ${cmd}
    if [ $? -ne 0 ]; then
        _error "Execution command (${cmd}) failed, please check it and try again."
    fi
}

function _install_update() {
    local package_name="$@"
    case "$(_os)" in
        centos)
            if _exists "yum"; then
                yum update -y
                _error_detect "yum install -y epel-release yum-utils"
                yum update -y
                _error_detect "yum install -y ${package_name}"
            elif _exists "dnf"; then
                dnf update -y
                _error_detect "dnf install -y dnf-plugins-core"
                dnf update -y
                _error_detect "dnf install -y ${package_name}"
            fi
            ;;
        ubuntu|debian)
            apt update -y
            _error_detect "apt install -y ${package_name}"
            ;;
    esac
}

function _purge() {
    local package_name="$@"
    case "$(_os)" in
        centos)
            if _exists "yum"; then
                yum purge -y ${package_name}
                yum autoremove -y
            elif _exists "dnf"; then
                dnf purge -y ${package_name}
                dnf autoremove -y
            fi
            ;;
        ubuntu|debian)
            apt purge -y ${package_name}
            apt autoremove -y
            ;;
    esac
}

function _systemctl() {
    local cmd="$1"
    local server_name="$2"
    case "${cmd}" in
        start)
            systemctl -q is-active ${server_name} || systemctl -q start ${server_name}
            systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
            sleep 2
        ;;
        stop)
            systemctl -q is-active ${server_name} && systemctl -q stop ${server_name}
            systemctl -q is-enabled ${server_name} && systemctl -q disable ${server_name}
        ;;
        restart)
            systemctl -q is-active ${server_name} && systemctl -q restart ${server_name} || systemctl -q start ${server_name}
            systemctl -q is-enabled ${server_name} || systemctl -q enable ${server_name}
            sleep 2
        ;;
        dr)
            systemctl daemon-reload
        ;;
    esac
}

function _read_domain() {
    until [[ ${is_domain} =~ ^[Yy]$ ]]
    do
        read -p "请输入域名：" domain
        check_domain=$(echo ${domain} | grep -oE '[^/]+(\.[^/]+)+\b' | head -n 1)
        read -r -p  "请确认域名: \"${check_domain}\" [y/n] " is_domain
    done
    domain=${check_domain}
}

function _read_ssh() {
    until [[ ${is_ssh_port} =~ ^[Yy]$ ]]
    do
        echo "当前 ssh 连接端口为: $(sed -En "s/^[#pP].*ort\s*([0-9]*)$/\1/p" /etc/ssh/sshd_config)"
        read -p "请输入新的 ssh 连接端口(1-65535)：" new_ssh_port
        [[ ${new_ssh_port} -lt 1 && ${new_ssh_port} -gt 65535 ]] && continue
        read -r -p  "请确认域名: \"${new_ssh_port}\" [y/n] " is_ssh_port
    done
}

function check_os() {
    [ -z "$(_os)" ] && _error "Not supported OS"
    case "$(_os)" in
        ubuntu)
            [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 16 ] && _error "Not supported OS, please change to Ubuntu 16+ and try again."
            ;;
        debian)
            [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 10 ] &&  _error "Not supported OS, please change to Debian 10+ and try again."
            ;;
        centos)
            [ -n "$(_os_ver)" -a "$(_os_ver)" -lt 7 ] &&  _error "Not supported OS, please change to CentOS 7+ and try again."
            ;;
        *)
            _error "Not supported OS"
            ;;
    esac
}

function install_dependencies() {
    _install_update "ca-certificates openssl lsb-release curl wget jq tzdata"
    case "$(_os)" in
        centos)
            _install_update "crontabs util-linux iproute procps-ng"
            ;;
        debian|ubuntu)
            _install_update "cron bsdmainutils iproute2 procps"
            ;;
    esac
}

function install_nginx_dependencies() {
    case "$(_os)" in
        centos)
            wget -O /etc/yum.repos.d/nginx.repo https://raw.githubusercontent.com/zxcvos/Xray-script/main/repo/nginx.repo
            ;;
        debian|ubuntu)
            [ ${is_mainline} ] && mainline="/mainline"
            [ "debian" -eq "$(_os)" ] && _install_update "debian-archive-keyring" || _install_update "ubuntu-keyring"
            rm -rf /etc/apt/sources.list.d/nginx.list
            curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
                | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
            http://nginx.org/packages${mainline}/$(_os) `lsb_release -cs` nginx" \
                | sudo tee /etc/apt/sources.list.d/nginx.list
            echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
                | sudo tee /etc/apt/preferences.d/99nginx
            ;;
    esac
}

function install_update_xray() {
    _info "installing or updating Xray..."
    _error_detect 'bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --beta'
    jq --arg ver "$(xray version | head -n 1 | cut -d \( -f 1 | grep -Eoi '[0-9.]*')" '.xray.version = $ver' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    wget -O /usr/local/etc/xray-script/update-dat.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/update-dat.sh
    chmod a+x /usr/local/etc/xray-script/update-dat.sh
    crontab -l | { cat; echo "30 22 * * * /usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1"; } | uniq | crontab -
    /usr/local/etc/xray-script/update-dat.sh
}

function purge_xray() {
    _info "removing Xray..."
    crontab -l | grep -v "/usr/local/etc/xray-script/update-dat.sh >/dev/null 2>&1" | crontab -
    _systemctl "stop" "xray"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
    rm -rf ${HOME}/xray_x25519
    rm -rf /etc/systemd/system/xray.service
    rm -rf /etc/systemd/system/xray@.service
    rm -rf /usr/local/bin/xray
    rm -rf /usr/local/etc/xray
    rm -rf /usr/local/share/xray
    rm -rf /var/log/xray
}

function install_update_nginx() {
    _info "installing or updating nignx..."
    install_nginx_dependencies
    _install_update "nginx"
    jq --arg ver "$(nginx -V 2>&1 | grep "^nginx version:.*" | cut -d / -f 2)" '.nginx.version = $ver' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
}

function purge_nginx() {
    _info "removing nignx..."
    _systemctl "stop" "nginx"
    _purge "nginx"
    rm -rf /etc/nginx
    rm -rf /etc/systemd/system/nginx.service
    rm -rf /var/log/nginx
}

function install_update_cloudreve() {
    _info "installing or updating cloudreve..."
    [ -d /usr/local/cloudreve ] || mkdir -p /usr/local/cloudreve
    local cloudreve_version="$(wget -qO- --no-check-certificate https://api.github.com/repos/cloudreve/cloudreve/releases/latest | grep 'tag_name' | cut -d \" -f 4)"
    jq --arg ver "${cloudreve_version}" '.cloudreve.version = $ver' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    local machine
    case "$(uname -m)" in
    'amd64' | 'x86_64')
        machine='amd64'
        ;;
    'armv5tel' | 'armv6l' | 'armv7' | 'armv7l')
        machine='arm'
        ;;
    'armv8' | 'aarch64')
        machine='arm64'
        ;;
    *)
        machine='amd64'
        ;;
    esac
    [ -e /usr/local/cloudreve/cloudreve ] && _systemctl "stop" "cloudreve" && rm -rf /usr/local/cloudreve/cloudreve
    wget -O cloudreve.tar.gz "https://github.com/cloudreve/Cloudreve/releases/download/${cloudreve_version}/cloudreve_${cloudreve_version}_linux_${machine}.tar.gz"
    tar -xzf cloudreve.tar.gz -C /usr/local/cloudreve
    chmod +x /usr/local/cloudreve/cloudreve
    rm -rf cloudreve.tar.gz
}

function purge_cloudreve() {
    _info "removing cloudreve..."
    _systemctl "stop" "cloudreve"
    rm -rf /usr/local/cloudreve
    rm -rf /etc/systemd/system/cloudreve.service
}

function install_acme_sh() {
    curl https://get.acme.sh | sh
    ${HOME}/.acme.sh/acme.sh --upgrade --auto-upgrade
    ${HOME}/.acme.sh/acme.sh --set-default-ca --server letsencrypt
}

function update_acme_sh() {
    ${HOME}/.acme.sh/acme.sh --upgrade
}

function purge_acme_sh() {
    ${HOME}/.acme.sh/acme.sh --upgrade --auto-upgrade 0
    ${HOME}/.acme.sh/acme.sh --uninstall
    rm -rf ${HOME}/.acme.sh
    rm -rf /var/www/_letsencrypt
    rm -rf /etc/nginx/ssl
}

function config_xray() {
    wget -O ${HOME}/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/VLESS-XTLS-uTLS-REALITY/myself.json
    xray_x25519=$(xray x25519)
    private_key=$(echo ${xray_x25519} | awk '{print $3}')
    public_key=$(echo ${xray_x25519} | awk '{print $6}')
    jq --arg privateKey "${private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    jq --arg publicKey "${public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    jq --arg domain "${domain}" '.nginx.domain = $domain' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
    sed -i "s|xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx|$(cat /proc/sys/kernel/random/uuid)|" ${HOME}/config.json
    sed -i "s|myself_dest|/dev/shm/nginx/h2c.sock|" ${HOME}/config.json
    sed -i "s|myself_domain|${domain}|; s|myself_www_domain|www.${domain}|" ${HOME}/config.json
    sed -i "s|xray x25519 Private key|${private_key}|" ${HOME}/config.json
    sed -i "s|\"22\"|\"$(head -c 20 /dev/urandom | md5sum | head -c 2)\"|; s|\"4444\"|\"$(head -c 20 /dev/urandom | md5sum | head -c 4)\"|; s|\"88888888\"|\"$(head -c 20 /dev/urandom | md5sum | head -c 8)\"|; s|\"1616161616161616\"|\"$(head -c 20 /dev/urandom | md5sum | head -c 16)\"|" ${HOME}/config.json
    mv -f ${HOME}/config.json /usr/local/etc/xray/config.json
    _systemctl "restart" "xray"
    sed -i "/\[::\]:443/d" /etc/nginx/sites-available/${domain}.conf
    sed -i "s|\(listen .*\)443|\1unix:/dev/shm/nginx/h2c.sock|; s|\(http2 .*\)reuseport|\1proxy_protocol|" /etc/nginx/sites-available/${domain}.conf
    sed -i "/h2c.sock/a \    set_real_ip_from        unix:;" /etc/nginx/sites-available/${domain}.conf
    sed -i "/set_real_ip_from/a \    real_ip_header          proxy_protocol;" /etc/nginx/sites-available/${domain}.conf
    _systemctl "restart" "nginx"
}

function config_nginx() {
    [ -d /etc/nginx ] || mkdir -p /etc/nginx
    [ -d /etc/nginx/conf.d ] || mkdir -p /etc/nginx/conf.d
    cd /etc/nginx
    [ -f /etc/nginx/conf.d/default.conf ] && grep -Eqv '^#' /etc/nginx/conf.d/default.conf && sed -i 's/^/#/' /etc/nginx/conf.d/default.conf
    wget -O mime.types https://raw.githubusercontent.com/nginx/nginx/master/conf/mime.types
    wget -O /etc/nginx/conf.d/restrict.conf https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/restrict.conf
    sed -i 's/^/#/' /etc/nginx/conf.d/restrict.conf
    echo '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' | base64 --decode | tee /etc/nginx/nginxconfig.io-example.com.tar.gz > /dev/null
    tar -xzvf nginxconfig.io-example.com.tar.gz | xargs chmod 0644
    rm -rf nginxconfig.io-example.com.tar.gz
    rm -rf sites-enabled/example.com.conf
    mv sites-available/example.com.conf sites-available/${domain}.conf
    ln -s /etc/nginx/sites-available/${domain}.conf /etc/nginx/sites-enabled/${domain}.conf
    sed -i "/worker_connections/a \    use                epoll;" nginx.conf
    sed -i "/ssl_protocols/i \    ssl_prefer_server_ciphers on;" nginx.conf
    sed -i "/# Diffie-Hellman parameter for DHE ciphersuites/,/ssl_dhparam/d" nginx.conf
    sed -i "/# non-www, subdomains redirect/,/# HTTP redirect/d" sites-available/${domain}.conf
    sed -i "/ssl_trusted_certificate/d" sites-available/${domain}.conf
    sed -i "s|https://www.example.com|https://\$host|" sites-available/${domain}.conf
    sed -i "s|127.0.0.1:3000|unix:/dev/shm/cloudreve/cloudreve.sock|" sites-available/${domain}.conf
    sed -i "/proxy_set_header Host/a \        proxy_redirect        off;" sites-available/${domain}.conf
    sed -i "/proxy_redirect/a \        client_max_body_size  0;" sites-available/${domain}.conf
    sed -i "s|www.example.com|${domain} www.${domain}|; s|\.example.com|\.${domain}|" sites-available/${domain}.conf
    sed -i "s|/etc/letsencrypt/live/example.com|/etc/nginx/ssl/${domain}|" sites-available/${domain}.conf
    sed -i "s|max-age=31536000|max-age=63072000|" nginxconfig.io/security.conf
}

function config_cloudreve() {
    wget -O ${HOME}/conf.ini https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/cloudreve.ini
    mv -f ${HOME}/conf.ini /usr/local/cloudreve/conf.ini
    sed -i "s|\$remote_addr|\$proxy_protocol_addr|" /etc/nginx/nginxconfig.io/proxy.conf
}

function service_xray() {
    wget -O ${HOME}/xray.service https://raw.githubusercontent.com/zxcvos/Xray-script/main/service/xray.service
    mv -f ${HOME}/xray.service /etc/systemd/system/xray.service
    _systemctl dr
}

function service_nginx() {
    wget -O ${HOME}/nginx.service https://raw.githubusercontent.com/zxcvos/Xray-script/main/service/nginx.service
    mv -f ${HOME}/nginx.service /etc/systemd/system/nginx.service
    _systemctl dr
}

function service_cloudreve() {
    wget -O ${HOME}/cloudreve.service https://raw.githubusercontent.com/zxcvos/Xray-script/main/service/cloudreve.service
    mv -f ${HOME}/cloudreve.service /etc/systemd/system/cloudreve.service
    _systemctl dr
}

function reset_cloudreve_data() {
    _systemctl "stop" "cloudreve"
    [ -e /usr/local/cloudreve/cloudreve.db ] && rm -rf /usr/local/cloudreve/cloudreve.db
    local cloudreve_init="$(timeout 5s /usr/local/cloudreve/cloudreve)"
    local cloudreve_password=$(printf "${cloudreve_init}" | grep "password" | awk '{print $6}')
    _systemctl "start" "cloudreve"
    _systemctl "restart" "nginx"
    jq --arg password "${cloudreve_password}" '.cloudreve.password = $password' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
}

function issue_cert() {
    [ -d /var/www/_letsencrypt ] || mkdir -p /var/www/_letsencrypt
    [ -d /etc/nginx/ssl/${domain} ] || mkdir -p /etc/nginx/ssl/${domain}
    sed -i -r 's/(listen .*443)/\1; #/g; s/(ssl_(certificate|certificate_key) )/#;#\1/g; s/(server \{)/\1\n    ssl off;/g' /etc/nginx/sites-available/${domain}.conf
    grep -Eqv '^#' /etc/nginx/conf.d/restrict.conf && sed -i 's/^/#/' /etc/nginx/conf.d/restrict.conf
    nginx -t && _systemctl "restart" "nginx"
    _error_detect "${HOME}/.acme.sh/acme.sh --issue --server letsencrypt -d ${domain} -d www.${domain} --webroot /var/www/_letsencrypt --keylength ec-256 --accountkeylength ec-256 --ocsp"
    sed -i -r -z 's/#?; ?#//g; s/(server \{)\n    ssl off;/\1/g' /etc/nginx/sites-available/${domain}.conf
    sed -i 's/^#//' /etc/nginx/conf.d/restrict.conf
    _error_detect "${HOME}/.acme.sh/acme.sh --install-cert --ecc -d ${domain} -d www.${domain} --key-file /etc/nginx/ssl/${domain}/privkey.pem --fullchain-file /etc/nginx/ssl/${domain}/fullchain.pem --reloadcmd \"nginx -t && systemctl reload nginx\""
}

function show_config() {
    local IPv4=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
    local c_ids=$(jq '.inbounds[] | select(.settings != null) | select(.protocol == "vless") | .settings.clients[].id' /usr/local/etc/xray/config.json | tr '\n' ',')
    local public_key=$(jq '.xray.publicKey' /usr/local/etc/xray-script/config.json)
    local SNI=$(jq -r '.nginx.domain' /usr/local/etc/xray-script/config.json)
    local shortIds=$(jq '.inbounds[] | select(.settings != null) | select(.protocol == "vless") | .streamSettings.realitySettings.shortIds[]' /usr/local/etc/xray/config.json | tr '\n' ',')
    echo -e "-------------- client config --------------"
    echo -e "address     : \"${IPv4}\""
    echo -e "port        : 443"
    echo -e "id          : ${c_ids%,}"
    echo -e "flow        : \"xtls-rprx-vision\""
    echo -e "network     : \"tcp\""
    echo -e "TLS         : \"reality\""
    echo -e "SNI         : \"${SNI}\", \"www.${SNI}\""
    echo -e "Fingerprint : \"chrome\""
    echo -e "PublicKey   : ${public_key}"
    echo -e "ShortId     : ${shortIds%,}"
    echo -e "SpiderX     : \"/\""
    echo -e "-------------------------------------------"
    echo -e "${RED}此脚本仅供交流学习使用，请勿使用此脚本行违法之事。${NC}"
    echo -e "${RED}网络非法外之地，行非法之事，必将接受法律制裁。${NC}"
    echo -e "-------------------------------------------"
}

function show_cloudreve_config() {
    local username=$(jq -r '.cloudreve.username' /usr/local/etc/xray-script/config.json)
    local password=$(jq -r '.cloudreve.password' /usr/local/etc/xray-script/config.json)
    echo -e "---------------- cloudreve ----------------"
    echo -e "username    : ${username}"
    echo -e "password    : ${password}"
    echo -e "-------------------------------------------"
}

function menu() {
    clear
    echo -e "--------------- Xray-script ---------------"
    echo -e " Version      : ${GREEN}v2023-03-15${NC}(${RED}beta${NC})"
    echo -e " Description  : Xray 管理脚本"
    echo -e "--------------- 装载管理 ---------------"
    echo -e "${GREEN}1.${NC} 安装"
    echo -e "${GREEN}2.${NC} 更新(待办)"
    echo -e "${GREEN}3.${NC} 卸载"
    echo -e "--------------- 操作管理 ---------------"
    echo -e "${GREEN}4.${NC} 启动"
    echo -e "${GREEN}5.${NC} 停止"
    echo -e "${GREEN}6.${NC} 重启"
    echo -e "--------------- 配置管理 ---------------"
    echo -e "${GREEN}101.${NC} 查看配置"
    echo -e "${GREEN}102.${NC} 信息统计"
    echo -e "${GREEN}103.${NC} 修改 id"
    echo -e "${GREEN}104.${NC} 修改 dest(待办)"
    echo -e "${GREEN}105.${NC} 修改 serverNames(待办)"
    echo -e "${GREEN}106.${NC} 修改 x25519 key"
    echo -e "${GREEN}107.${NC} 修改 shortIds"
    echo -e "${GREEN}108.${NC} 重置 cloudreve 账号密码"
    echo -e "${GREEN}109.${NC} 查看 cloudreve 原始账号密码"
    echo -e "--------------- 其他选项 ---------------"
    echo -e "${GREEN}201.${NC} 更新至最新稳定版内核"
    echo -e "${GREEN}202.${NC} 卸载多余内核"
    echo -e "${GREEN}203.${NC} 修改 ssh 端口"
    echo -e "${GREEN}204.${NC} 网络连接优化"
    echo -e "----------------------------------------"
    echo -e "${RED}0.${NC} 退出"
    read -rp "Choose: " idx
    if [[ ! -d /usr/local/etc/xray-script && (${idx} -ne 0 && ${idx} -ne 1 && ${idx} -lt 201) ]]; then
        _error "未使用 Xray-script 进行安装"
    fi
    case "${idx}" in
        1)
            if [ ! -d /usr/local/etc/xray-script ]; then
                _read_domain
                mkdir -p /usr/local/etc/xray-script
                wget -O /usr/local/etc/xray-script/config.json https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/config.json
                install_dependencies
                install_update_xray
                install_update_nginx
                service_nginx
                install_update_cloudreve
                service_cloudreve
                install_acme_sh
                config_nginx
                config_cloudreve
                issue_cert
                config_xray
                reset_cloudreve_data
                _systemctl "start" "cloudreve"
                show_cloudreve_config
                show_config
            fi
        ;;
        2)
            # TODO: udpate
            echo "TODO: udpate"
        ;;
        3)
            if [ -d /usr/local/etc/xray-script ]; then
                purge_xray
                purge_nginx
                purge_cloudreve
                purge_acme_sh
                rm -rf /usr/local/etc/xray-script
            fi
        ;;
        4)
            _systemctl "start" "xray"
            _systemctl "start" "cloudreve"
            _systemctl "start" "nginx"
        ;;
        5)
            _systemctl "stop" "xray"
            _systemctl "stop" "cloudreve"
            _systemctl "stop" "nginx"
        ;;
        6)
            _systemctl "restart" "xray"
            _systemctl "restart" "cloudreve"
            _systemctl "restart" "nginx"
        ;;
        101)
            show_config
        ;;
        102)
            [ -f /usr/local/etc/xray-script/traffic.sh ] || wget -O /usr/local/etc/xray-script/traffic.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/tool/traffic.sh
            bash /usr/local/etc/xray-script/traffic.sh
        ;;
        103)
            local arr_len=$(jq '.inbounds[] | select(.settings != null) | select(.protocol == "vless") | .settings.clients | length' /usr/local/etc/xray/config.json)
            for i in $(seq 1 $arr_len)
            do
                local c_id=$(jq ".inbounds[] | select(.settings != null) | select(.protocol == \"vless\") | .settings.clients[${i}-1].id" /usr/local/etc/xray/config.json)
                sed -i "s|${c_id}|\"$(cat /proc/sys/kernel/random/uuid)\"|" /usr/local/etc/xray/config.json
            done
            _systemctl "restart" "xray"
            show_config
        ;;
        104)
            # TODO: modify dest
            echo -e "TODO: modify dest"
            show_config
        ;;
        105)
            # TODO: modify serverNames
            echo -e "TODO: modify serverNames"
            show_config
        ;;
        106)
            xray_x25519=$(xray x25519)
            private_key=$(echo ${xray_x25519} | awk '{print $3}')
            public_key=$(echo ${xray_x25519} | awk '{print $6}')
            local old_private_key=$(jq -r '.xray.privateKey' /usr/local/etc/xray-script/config.json)
            sed -i "s|${old_private_key}|${private_key}|" /usr/local/etc/xray/config.json
            jq --arg privateKey "${private_key}" '.xray.privateKey = $privateKey' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
            jq --arg publicKey "${public_key}" '.xray.publicKey = $publicKey' /usr/local/etc/xray-script/config.json > /usr/local/etc/xray-script/new.json && mv -f /usr/local/etc/xray-script/new.json /usr/local/etc/xray-script/config.json
            _systemctl "restart" "xray"
            show_config
        ;;
        107)
            local arr_len=$(jq '.inbounds[] | select(.settings != null) | select(.protocol == "vless") | .streamSettings.realitySettings.shortIds | length' /usr/local/etc/xray/config.json)
            for i in $(seq 1 $arr_len)
            do
                local shortId=$(jq ".inbounds[] | select(.settings != null) | select(.protocol == \"vless\") | .streamSettings.realitySettings.shortIds[${i}-1]" /usr/local/etc/xray/config.json)
                local shortId_len=$(jq ".inbounds[] | select(.settings != null) | select(.protocol == \"vless\") | .streamSettings.realitySettings.shortIds[${i}-1] | length" /usr/local/etc/xray/config.json)
                sed -i "s|${shortId}|\"$(head -c 20 /dev/urandom | md5sum | head -c ${shortId_len})\"|" /usr/local/etc/xray/config.json
            done
            _systemctl "restart" "xray"
            show_config
        ;;
        108)
            reset_cloudreve_data
            show_cloudreve_config
        ;;
        109)
            show_cloudreve_config
        ;;
        201)
            bash <(wget -qO- https://raw.githubusercontent.com/zxcvos/system-automation-scripts/main/update-kernel.sh)
        ;;
        202)
            bash <(wget -qO- https://raw.githubusercontent.com/zxcvos/system-automation-scripts/main/remove-kernel.sh)
        ;;
        203)
            _read_ssh
            sed -i "s/^[#pP].*ort\s*[0-9]*$/Port ${new_ssh_port}/" /etc/ssh/sshd_config
            systemctl restart sshd
        ;;
        204)
            wget -O /etc/sysctl.conf https://raw.githubusercontent.com/zxcvos/Xray-script/main/config/sysctl.conf
            sysctl -p
        ;;
        0)
            exit 0
        ;;
    esac
}

[[ $EUID -ne 0 ]] && _error "This script must be run as root"

menu
