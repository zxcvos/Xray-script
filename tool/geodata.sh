#!/usr/bin/env bash

set -euo pipefail
umask 077

XRAY_DIR="${XRAY_DIR:-/usr/local/share/xray}"
XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
RELEASE_API="https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest"
RELEASE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download"

log() {
    echo "geodata: $*" >&2
    if command -v logger >/dev/null 2>&1; then
        logger -t xray-geodata -- "$*" || true
    fi
}

download() {
    curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 15 --max-time 120 --output "$2" "$1"
}

mkdir -p "$XRAY_DIR"
cd "$XRAY_DIR"
XRAY_DIR="$PWD"
# Cron and manual updates must not install different releases concurrently.
command -v flock >/dev/null
exec 9>"$XRAY_DIR/.geodata.lock"
flock -n 9 || { log "another update is running"; exit 0; }
STAGE=$(mktemp -d "$XRAY_DIR/.geodata.XXXXXXXX")
INSTALLING=0
WAS_ACTIVE=0
RESTART_ATTEMPTED=0

cleanup() {
    local status=$? file rollback_failed=0
    trap - EXIT
    set +e
    if ((status != 0 && INSTALLING)); then
        for file in geoip.dat geosite.dat; do
            if [[ -f "$STAGE/previous/$file" ]]; then
                if ! command cp -p -f "$STAGE/previous/$file" "$STAGE/$file.restore" ||
                    ! command mv -f "$STAGE/$file.restore" "$XRAY_DIR/$file"; then
                    rollback_failed=1
                fi
            elif ! command rm -f "$XRAY_DIR/$file"; then
                rollback_failed=1
            fi
        done
        if ((rollback_failed)); then
            log "rollback failed; previous files retained in $STAGE/previous"
            exit "$status"
        fi
        log "update failed; restored previous geodata"
        if ((WAS_ACTIVE && RESTART_ATTEMPTED)); then
            systemctl restart xray || log "could not restart Xray with previous geodata"
        fi
    fi
    command rm -rf -- "$STAGE"
    exit "$status"
}
trap cleanup EXIT

# Pin all four downloads to one release, including across a new publication.
download "$RELEASE_API" "$STAGE/release.json"
RELEASE=$(jq -er '.tag_name' "$STAGE/release.json")
[[ "$RELEASE" =~ ^[A-Za-z0-9._-]+$ ]] || { log "invalid release tag"; exit 1; }
for file in geoip.dat geosite.dat; do
    download "$RELEASE_URL/$RELEASE/$file" "$STAGE/$file"
    download "$RELEASE_URL/$RELEASE/$file.sha256sum" "$STAGE/$file.sha256sum"
done
(cd "$STAGE"; sha256sum -c geoip.dat.sha256sum; sha256sum -c geosite.dat.sha256sum)

# Test the actual routing rules against the candidate files, before replacing
# anything or restarting. Keep the existing config and access controls intact.
CONFIG_HASH=$(sha256sum "$XRAY_CONFIG")
if ! XRAY_LOCATION_ASSET="$STAGE" "$XRAY_BIN" run -test -config "$XRAY_CONFIG" >"$STAGE/config-test.log" 2>&1; then
    log "candidate geodata failed Xray config validation; keeping installed data"
    exit 1
fi
[[ $(sha256sum "$XRAY_CONFIG") == "$CONFIG_HASH" ]] || { log "config changed during validation"; exit 1; }
if cmp -s "$STAGE/geoip.dat" "$XRAY_DIR/geoip.dat" && cmp -s "$STAGE/geosite.dat" "$XRAY_DIR/geosite.dat"; then
    log "release $RELEASE already installed"
    exit 0
fi

mkdir "$STAGE/previous"
for file in geoip.dat geosite.dat; do
    if [[ -f "$XRAY_DIR/$file" ]]; then
        command cp -p -f "$XRAY_DIR/$file" "$STAGE/previous/$file"
        cmp -s "$XRAY_DIR/$file" "$STAGE/previous/$file"
    fi
    chmod 0644 "$STAGE/$file"
done
if systemctl -q is-active xray; then WAS_ACTIVE=1; fi
INSTALLING=1
for file in geoip.dat geosite.dat; do
    command mv -f "$STAGE/$file" "$XRAY_DIR/$file"
done
# Independently verify the installed files before restarting the service.
sha256sum -c "$STAGE/geoip.dat.sha256sum"
sha256sum -c "$STAGE/geosite.dat.sha256sum"
if ((WAS_ACTIVE)); then
    RESTART_ATTEMPTED=1
    systemctl restart xray
    sleep 2
    systemctl -q is-active xray
fi
log "installed validated release $RELEASE"
