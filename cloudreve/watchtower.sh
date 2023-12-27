#!/usr/bin/env bash

if [ $# -eq 0 ]; then
  echo "Please enter the zxcvos xray script configuration dirctory path."
  exit 1
fi

declare XRAY_SCRIPT_PATH="$1"
cloudreve_version=$(docker logs cloudreve | grep -Eoi "v[0-9]+.[0-9]+.[0-9]+" | cut -c2-)
jq --arg version "${cloudreve_version}" '.cloudreve.version = $version' ${XRAY_SCRIPT_PATH}/config.json >${XRAY_SCRIPT_PATH}/tmp.json && mv -f ${XRAY_SCRIPT_PATH}/tmp.json ${XRAY_SCRIPT_PATH}/config.json
