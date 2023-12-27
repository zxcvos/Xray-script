#!/usr/bin/env bash
#
# Use the curl command to simulate different User-Agents for testing Nginx configuration.
#
# Copyright (C) 2023 zxcvos

# color
readonly RED='\033[1;31;31m'
readonly GREEN='\033[1;31;32m'
readonly YELLOW='\033[1;31;33m'
readonly NC='\033[0m'

declare domain=''

# status print
function _info() {
  printf "${GREEN}[Info] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _warn() {
  printf "${YELLOW}[Warn] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
}

function _error() {
  printf "${RED}[Error] ${NC}"
  printf -- "%s" "$@"
  printf "\n"
  exit 1
}

# Simulate testing with different User-Agents
test_curl() {
  local user_agent=$1
  local protocol=$2

  curl -A "${user_agent}" "${protocol}://${domain}" -s -o /dev/null || return 1
}

test_user_agents() {
  local user_agent=$1

  _info "Simulating access with ${user_agent}"
  test_curl "${user_agent}" "http" && _info "HTTP access allowed" || _warn "HTTP access denied"
  test_curl "${user_agent}" "https" && _info "HTTPS access allowed" || _warn "HTTPS access denied"
  echo
}

function show_help() {
  echo "Usage: $0 -d example.com"
  echo "Options:"
  echo "  -d, --domain        Domain to test the limit.conf configuration"
  echo "  -h, --help          Display this help message"
  exit 0
}

while [[ $# -ge 1 ]]; do
  case "${1}" in
  -d | --domain)
    shift
    [[ -z "$1" ]] && _error 'Domain not provided.'
    domain="$1"
    shift
    ;;
  -h | --help)
    show_help
    ;;
  *)
    _error "Invalid option: '$1'. Use '$0 -h/--help' to see usage information."
    ;;
  esac
done

[[ -z "${domain}" ]] && show_help

# Run tests
test_user_agents "Curl"
test_user_agents "Baiduspider"
test_user_agents "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; .NET CLR 1.1.4322; .NET CLR 2.0.50727)"
test_user_agents "SomeOtherUserAgent"
