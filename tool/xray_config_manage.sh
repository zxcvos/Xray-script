#!/usr/bin/env bash

# This script is used to manage xray configuration
#
# Usage:
#   ./script.sh [-t TAG] [-e EMAIL] [-p [PORT]] [-prcl [PROTOCOL]]
#
# Options:
#   -h, --help           Display help message.
#   -t, --tag            The inbounds match tag. default: xray-script-xtls-reality
#   -p, --port           Set port, default: 443
#   -prcl, --protocol    Set protocol, default: vless
#
# Dependencies: [jq]
#
# Author: zxcvos
# Version: 0.1
# Date: 2023-03-21

declare configPath='/usr/local/etc/xray/config.json'
declare matchTag='xray-script-xtls-reality'
declare isSetListen=0
declare setListen="0.0.0.0"
declare isSetPort=0
declare setPort=443
declare isSetProto=0
declare setProto='vless'
declare matchEmail='vless@xtls.reality'
declare isResetUUID=0
declare resetUUID=''
declare isPickNetwork=0
declare pickNetwork=1

while [[ $# -ge 1 ]]; do
  case $1 in
  -t | --tag)
    shift
    [ "$1" ] || (echo 'Error: tag not provided' && exit 1)
    matchTag="$1"
    shift
    ;;
  -l | --listen)
    shift
    isSetListen=1
    [ "$1" ] && setListen="$1" && shift
    ;;
  -p | --port)
    shift
    isSetPort=1
    [ "$1" ] && setPort="$1" && shift
    ;;
  -prcl | --protocol)
    shift
    isSetProto=1
    [ "$1" ] && setProto="$1" && shift
    ;;
  -e | --email)
    shift
    [ "$1" ] || (echo 'Error: email not provided' && exit 1)
    matchEmail="$1"
    shift
    ;;
  -u | --uuid)
    shift
    isResetUUID=1
    [ "$1" ] && resetUUID="$1" && shift
    ;;
  -n | --network)
    shift
    isPickNetwork=1
    if [ "$1" ]; then
      [[ "$1" -lt 1 || "$1" -gt 3 ]] && echo 'Error: -n|--network 1|2|3' && exit 1
      pickNetwork="$1"
      shift
    fi
    ;;
  esac
done

function is_digit() {
  local input="${1}"
  if [[ "${input}" =~ ^[0-9]+$ ]]; then
    return 0
  else
    return 1
  fi
}

function is_valid_IPv4_address() {
  local ip_regex='^((2(5[0-5]|[0-4][0-9]))|[0-1]?[0-9]{1,2})(\.((2(5[0-5]|[0-4][0-9]))|[0-1]?[0-9]{1,2})){3}$'
  local IPv4="${1}"
  if [[ ! "${IPv4}" =~ ${ip_regex} ]]; then
    echo "Invalid IPv4 address format: ${IPv4}"
    return 1
  fi
  IFS='.' read -ra fields <<<"${IPv4}"
  for field in "${fields[@]}"; do
    if ((field > 255)); then
      echo "Invalid IPv4 address: ${IPv4} (field $field is out of range)"
      return 1
    fi
  done
  if ((${#fields[@]} != 4)); then
    echo "Invalid IPv4 address: ${IPv4} (does not contain 4 fields)"
    return 1
  fi
  return 0
}

function is_valid_IPv6_address() {
  local ip_regex='^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$'
  local IPv6="${1}"
  if [[ "${IPv6}" =~ ${ip_regex} ]]; then
    return 0
  else
    echo "Invalid IPv6 address format: ${IPv6}"
    return 1
  fi
}

function is_UDS() {
  local input="${1}"
  if echo "${input}" | grep -Eq "^(\/[a-zA-Z0-9\_\-\+\.]+)*\/[a-zA-Z0-9\_\-\+]+\.sock$" || echo "${input}" | grep -Eq "^@{1,2}[a-zA-Z0-9\_\-\+\.]+$"; then
    return 0
  else
    echo "Error: Please enter a valid UDS file path, or a valid abstract socket"
    return 1
  fi
}

function set_listen() {
  local in_tag="${1}"
  local in_listen="${2}"
  if is_valid_IPv4_address "${in_listen}" || is_valid_IPv6_address "${in_listen}" || is_UDS "${in_listen}"; then
    jq --arg in_tag "${in_tag}" --arg in_listen "${in_listen}" '.inbounds |= map(if .tag == $in_tag then .listen = $in_listen else . end)' "${configPath}" >"${HOME}"/new.json && mv -f "${HOME}"/new.json "${configPath}"
  fi
}

function set_port() {
  local in_tag="${1}"
  local in_port="${2}"
  if is_digit "${in_port}" && [ ${in_port} -gt 0 ] && [ ${in_port} -lt 65536 ]; then
    jq --arg in_tag "${in_tag}" --argjson in_port ${in_port} '.inbounds |= map(if .tag == $in_tag then .port = $in_port else . end)' "${configPath}" >"${HOME}"/new.json && mv -f "${HOME}"/new.json "${configPath}"
  else
    echo "Error: Please enter a valid port number between 1-65535"
  fi
}

function set_proto() {
  local in_tag="${1}"
  local in_proto="${2}"
  jq --arg in_tag "${in_tag}" --arg in_proto "${in_proto}" '.inbounds |= map(if .tag == $in_tag then .protocol = $in_proto else . end)' "${configPath}" >"${HOME}"/new.json && mv -f "${HOME}"/new.json "${configPath}"
}

function reset_uuid() {
  local in_tag="${1}"
  local c_email="${2}"
  local c_id="${3}"
  jq --arg in_tag "${in_tag}" --arg c_email "${c_email}" --arg c_id "${c_id}" '.inbounds |= map(if .tag == $in_tag then .settings.clients |= map(if .email == $c_email then .id = $c_id else . end) else . end)' "${configPath}" >"${HOME}"/new.json && mv -f "${HOME}"/new.json "${configPath}"
}
