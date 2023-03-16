#!/usr/bin/env bash
#
# System Required:  CentOS 7+, Debian10+, Ubuntu16+
# Description:      Script to Xray manage
#
# Copyright (C) 2023 zxcvos
#
# Xray-script: https://github.com/zxcvos/Xray-script

readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

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

[[ $EUID -ne 0 ]] && _error "请使用 root 用户运行此脚本"
check_os
