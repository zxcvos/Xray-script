<!-- Translated by AI -->
# Xray-XHTTP Management Script :sparkles:

* A pure Shell-written XHTTP management script for Xray
* Optional configurations:
  * mKCP (VLESS-mKCP-seed)
  * Vision (VLESS-Vision-REALITY)
  * XHTTP (VLESS-XHTTP-REALITY)
  * trojan (Trojan-XHTTP-REALITY)
  * Fallback (includes VLESS-Vision-REALITY, VLESS-XHTTP-REALITY)
  * SNI (includes Vision_REALITY, XHTTP_REALITY, XHTTP_TLS)
* SNI configuration uses Nginx for SNI traffic splitting, ideal for CDN traversal, upstream/downstream separation, and multi-site coexistence
* SNI share links implement bidirectional separation (upstream: xhttp+TLS+CDN | downstream: xhttp+Reality, upstream: xhttp+Reality | downstream: xhttp+TLS+CDN)
* Rule configurations and custom entries:
  * Block BitTorrent traffic (optional)
  * Block China IP traffic (optional)
  * Ad blocking (optional)
  * Add custom WARP Proxy rules
  * Add custom block rules
* Cloudflare WARP Proxy toggle (🐳 Docker deployment)
* Geodata auto-update toggle
* Xray ports default/fill:
  * VLESS-mKCP: Randomly generated
  * ALL-REALITY: 443
* UUID default/fill:
  * Randomly generated
  * Custom standard UUID input
  * Non-standard UUID mapping conversion
* kcp(seed) and trojan(password) default/fill:
  * Random generation (format: cw-GEMDYgwIV3_g#)
  * Custom input
* target default/fill:
  * Random selection from serverNames.json
  * TLSv1.3 and H2 validation for custom targets
  * Automatic serverNames acquisition for custom targets
* shortId default/fill:
  * Random generation (default two shortIds e.g.: 01234567, 0123456789abcdef)
  * Custom shortId input
  * Numeric input 0-8 generates 0-16 length shortIds
  * Comma-separated multiple values
* path default/fill:
  * Random generation (format: /8ugSUeNJ.9OEnTErb.dVZMUAFu)
  * Custom input (format: /8ugSUeNJ, with/without `/`)

## Issues

1. If installation succeeds but not working, check if server ports are open
2. Before using SNI configuration, ensure VPS HTTP(80) and HTTPS(443) ports are open
3. Before using SNI configuration, disable CDN protection to avoid SSL certificate issues
4. For upstream/downstream separation details, see [XHTTP: Beyond REALITY][XHTTP] and [xhttp 五合一配置][xhttp 五合一配置]

Verify port accessibility via `https://tcp.ping.pe/ip:port`

## Share Links

Based on [VMessAEAD / VLESS 分享链接标准提案](https://github.com/XTLS/Xray-core/discussions/716) and [v2rayN](https://github.com/2dust/v2rayN). Modify links manually if other clients have compatibility issues.

In SNI configurations, CDN share links default Alpn to H2. For H3 requirements, modify client settings manually.

## Usage

* Download:
  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/xhttp.sh
  ```
  
* Execute:
  ```sh
  bash ${HOME}/Xray-script.sh
  ```

* Quick start:
  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/xhttp.sh && bash ${HOME}/Xray-script.sh
  ```

## Script Interface

```sh
 __   __  _    _   _______   _______   _____  
 \ \ / / | |  | | |__   __| |__   __| |  __ \ 
  \ V /  | |__| |    | |       | |    | |__) |
   > <   |  __  |    | |       | |    |  ___/ 
  / . \  | |  | |    | |       | |    | |     
 /_/ \_\ |_|  |_|    |_|       |_|    |_|     

Copyright (C) zxcvos | https://github.com/zxcvos/Xray-script

-------------------------------------------
Xray       : v24.12.31
CONFIG     : VLESS-XHTTP-REALITY
WARP Proxy : Running
-------------------------------------------

--------------- Xray-script ---------------
 Version      : v2024-12-31
 Description  : Xray Management Script
----------------- Installation ----------------
1. Full installation
2. Install/Update only
3. Uninstall
----------------- Operation -----------------
4. Start
5. Stop
6. Restart
----------------- Configuration -------------
7. Share links & QR codes
8. Statistics
9. Manage configuration
-------------------------------------------
0. Exit
```

## Tested Systems

| Platform | Version    |
| -------- | ---------- |
| Debian   | 10, 11, 12 |
| Ubuntu   | 20, 22, 24 |
| CentOS   | 7, 8, 9    |
| Rocky    | 8, 9       |

All tested on Vultr instances. Other Debian/Red Hat derivatives might work but are untested.

## Installation Time Notes

SNI configuration is designed for long-term use after initial setup. Reinstalling systems frequently will consume significant time. Use configuration management options for domain/setting changes.

When switching from SNI configuration, Nginx stops but remains installed. Reactivating SNI won't trigger reinstallation.

### Installation Time Reference (1CPU/1GB)

| Process                 | Duration           |
| ----------------------- | ------------------ |
| Update system packages  | 0-10 minutes       |
| Install dependencies    | 0-5 minutes        |
| Install Docker          | 1-2 minutes        |
| Install Cloudreve       | 3-5 minutes        |
| Install Cloudflare-warp | 3-5 minutes        |
| Install Xray            | < half a minute    |
| Install Nginx           | 13-15 minutes      |
| Issue certificates      | 1-2 minutes        |
| Configuration files     | < 100 milliseconds |

### Why does the script installation take so long?

Nginx in the script is managed by compiling from source.

The advantages of compiling include:

1. High runtime efficiency (optimized with -O3 during compilation)
2. Newer software versions

The drawback is that compilation takes a long time.

## Installation Paths


**Xray-script:** `/usr/local/etc/xray-script`

**Nginx:** `/usr/local/nginx`

**Cloudreve:** `/usr/local/cloudreve`

**Cloudflare-warp:** `/usr/local/cloudflare_warp`

**Xray:** See **[Xray-install](https://github.com/XTLS/Xray-install)**


## Dependencies

SNI configuration may install these dependencies:

| Purpose                                           | Debian-based Systems                        | Red Hat-based Systems |
| ------------------------------------------------- | ------------------------------------------- | --------------------- |
| yumdb set (mark packages for manual installation) |                                             | yum-utils             |
| dnf config-manager                                |                                             | dnf-plugins-core      |
| IP retrieval                                      | iproute2                                    | iproute               |
| DNS resolution                                    | dnsutils                                    | bind-utils            |
| wget                                              | wget                                        | wget                  |
| curl                                              | curl                                        | curl                  |
| wget/curl https                                   | ca-certificates                             | ca-certificates       |
| kill/pkill/ps/sysctl/free                         | procps                                      | procps-ng             |
| epel repository                                   |                                             | epel-release          |
| epel repository                                   |                                             | epel-next-release     |
| remi repository                                   |                                             | remi-release          |
| Firewall                                          | ufw                                         | firewalld             |
| **Compilation Basics:**                           |                                             |                       |
| Download source files                             | wget                                        | wget                  |
| Unzip tar source files                            | tar                                         | tar                   |
| Unzip tar.gz source files                         | gzip                                        | gzip                  |
| gcc                                               | gcc                                         | gcc                   |
| g++                                               | g++                                         | gcc-c++               |
| make                                              | make                                        | make                  |
| **acme.sh Dependencies:**                         |                                             |                       |
|                                                   | curl                                        | curl                  |
|                                                   | openssl                                     | openssl               |
|                                                   | cron                                        | crontabs              |
| **Compile openssl:**                              |                                             |                       |
|                                                   | perl-base (included in libperl-dev)         | perl-IPC-Cmd          |
|                                                   | perl-modules-5.32 (included in libperl-dev) | perl-Getopt-Long      |
|                                                   | libperl5.32 (included in libperl-dev)       | perl-Data-Dumper      |
|                                                   |                                             | perl-FindBin          |
| **Compile Brotli:**                               |                                             |                       |
|                                                   | git                                         | git                   |
|                                                   | libbrotli-dev                               | brotli-devel          |
| **Compile Nginx:**                                |                                             |                       |
|                                                   | libpcre2-dev                                | pcre2-devel           |
|                                                   | zlib1g-dev                                  | zlib-devel            |
| --with-http_xslt_module                           | libxml2-dev                                 | libxml2-devel         |
| --with-http_xslt_module                           | libxslt1-dev                                | libxslt-devel         |
| --with-http_image_filter_module                   | libgd-dev                                   | gd-devel              |
| --with-google_perftools_module                    | libgoogle-perftools-dev                     | gperftools-devel      |
| --with-http_geoip_module                          | libgeoip-dev                                | geoip-devel           |
| --with-http_perl_module                           |                                             | perl-ExtUtils-Embed   |
|                                                   | libperl-dev                                 | perl-devel            |

## Credits

[Xray-core][Xray-core]

[REALITY][REALITY]

[XHTTP: Beyond REALITY][XHTTP]

[integrated-examples][lxhao61/integrated-examples]

[xhttp 五合一配置][xhttp 五合一配置]

[部署 Cloudflare WARP Proxy][haoel]

[cloudflare-warp 镜像][e7h4n]

[V2Ray 路由规则文件加强版][v2ray-rules-dat]

[kirin10000/Xray-script][kirin10000/Xray-script]

[Cloudreve][cloudreve]

**This script is for educational purposes only. Do not use it for illegal activities.**

[Xray-core]: https://github.com/XTLS/Xray-core (THE NEXT FUTURE)
[REALITY]: https://github.com/XTLS/REALITY (THE NEXT FUTURE)
[XHTTP]: https://github.com/XTLS/Xray-core/discussions/4113 (XHTTP: Beyond REALITY)
[lxhao61/integrated-examples]: https://github.com/lxhao61/integrated-examples (以 V2Ray（v4 版） 或 Xray、Nginx 或 Caddy（v2 版）、Hysteria 等打造常用科学上网的优化配置及最优组合示例，且提供集成特定插件的 Caddy（v2 版） 文件，分享给大家食用及自己备份。)
[xhttp 五合一配置]: https://github.com/XTLS/Xray-core/discussions/4118 (xhttp 五合一配置 \( reality 直连与过 CDN 共存, 附小白可抄的配置\))
[haoel]: https://github.com/haoel/haoel.github.io#943-docker-%E4%BB%A3%E7%90%86 (使用 Docker 快速部署 Cloudflare WARP Proxy)
[e7h4n]: https://github.com/e7h4n/cloudflare-warp (cloudflare-warp 镜像)
[v2ray-rules-dat]: https://github.com/Loyalsoldier/v2ray-rules-dat (V2Ray 路由规则文件加强版)
[kirin10000/Xray-script]: https://github.com/kirin10000/Xray-script (kirin10000/Xray-script)
[cloudreve]: https://github.com/cloudreve/cloudreve (cloudreve)
