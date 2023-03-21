
#!/usr/bin/env bash

# This script is used to manage xray configuration
#
# Usage:
#   ./script.sh [-t TAG] [-e EMAIL] [-p PORT] [-prcl PROTOCOL]
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
declare setPort=443
declare setProto='vless'
declare matchEmail='vless@xtls.reality'

while [[ $# -ge 1 ]]; do
  case $1 in
  -t | --tag)
    shift
    [ "$1" ] || (echo 'Error: tag not provided' && exit 1)
    matchTag="$1"
    shift
    ;;
  -p | --port)
    shift
    [ "$1" ] || (echo 'Error: port not provided' && exit 1)
    setPort="$1"
    shift
    ;;
  -prcl | --protocol)
    shift
    [ "$1" ] || (echo 'Error: protocol not provided' && exit 1)
    setProto="$1"
    shift
    ;;
  -e | --email)
    shift
    [ "$1" ] || (echo 'Error: email not provided' && exit 1)
    matchEmail="$1"
    shift
    ;;
  esac
done
