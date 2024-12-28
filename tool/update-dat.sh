#!/usr/bin/env bash

set -e

XRAY_DIR="/usr/local/share/xray"

GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat"

[ -d $XRAY_DIR ] || mkdir -p $XRAY_DIR
cd $XRAY_DIR

curl -L -o geoip.dat.new $GEOIP_URL
if [ $? -ne 0 ]; then
  rm -f geoip.dat.new
  exit 1
fi

curl -L -o geosite.dat.new $GEOSITE_URL
if [ $? -ne 0 ]; then
  rm -f geoip.dat.new geosite.dat.new
  exit 1
fi

rm -f geoip.dat geosite.dat

mv geoip.dat.new geoip.dat
mv geosite.dat.new geosite.dat

systemctl -q is-active xray && systemctl restart xray
