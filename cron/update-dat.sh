#!/usr/bin/env bash

set -e

XRAY_DIR="/usr/local/share/xray"

GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geosite.dat"

[ -d $XRAY_DIR ] || mkdir -p $XRAY_DIR
cd $XRAY_DIR

curl -L -o geoip.dat.new $GEOIP_URL
curl -L -o geosite.dat.new $GEOSITE_URL

rm -f geoip.dat geosite.dat

mv geoip.dat.new geoip.dat
mv geosite.dat.new geosite.dat

systemctl -q is-active xray && systemctl restart xray
