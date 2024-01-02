# Xray-REALITY Management Script

* A purely Shell-scripted REALITY management script
* Configured with VLESS-XTLS-uTLS-REALITY
* Achieves the use of Xray frontend to stealthily employ self-signed certificates, suitable for scenarios with no other website requirements
* Implements Nginx SNI-based traffic shunting, with Xray backend for stealthy use of self-signed certificates, suitable for scenarios with multiple websites coexisting
* Allows custom input of UUID; non-standard UUIDs will be mapped and converted to UUIDv5 using `Xray uuid -i "custom string"`
* Default configuration blocks ads and BitTorrent traffic
* Default deployment of Cloudreve using Docker as a personal cloud drive
* Default deployment of Cloudflare WARP Proxy using Docker
* Traffic to China is routed through Cloudflare WARP Proxy by default
* Implements automatic updating of the geo file

## Notes

1. This script requires a domain name that resolves to the server.

2. The installation process of this script may take a long time.

3. This script is designed for individual VPS users.

4. It is recommended to use this script on a clean system (VPS console - reset system, or use a DD script to reinstall the system).

## Tested Systems

| Platform | Version  |
| -------- | -------- |
| Debian   | 10, 11, 12 |
| Ubuntu   | 20, 22, 23 |
| CentOS   | 7, 8, 9    |
| Rocky    | 8, 9      |

The above distributions have been tested for installation on Vultr.

Other Debian-based systems and Red Hat-based systems may work but have not been tested and may encounter issues.

If there are issues with Docker installation, please install Docker manually and comment out the `install_docker` code in the `install()` function, then run it:

```sh
sed -i 's/install_docker$/# install_docker/' ${HOME}/Xray-script.sh
```

## Installation Duration Explanation

This script is intended for long-term use after installation and is not suitable for repeated system resets and installations, which can consume a significant amount of your time. If you need to change configurations, domains, etc., corresponding options are available in the management interface.

### Installation Duration Reference

Installation process:

Update system management packages -> Install dependencies -> Install Docker -> Install Cloudreve -> Install Cloudflare-warp -> Install Xray -> Install Nginx -> Issue certificates -> Configuration files

**This is the average installation time for a single-core 1G server and is for reference only:**

| Task                   | Duration    |
| ---------------------- | ----------- |
| Update system packages | 0-10 minutes |
| Install dependencies   | 0-5 minutes  |
| Install Docker         | 1-2 minutes  |
| Install Cloudreve      | 3-5 minutes  |
| Install Cloudflare-warp| 3-5 minutes  |
| Install Xray           | < half a minute |
| Install Nginx          | 13-15 minutes |
| Issue certificates | 1-2 minutes  |
| Configuration files    | < 100 milliseconds |

### Why does the script installation take so long?

Nginx in the script is managed by compiling from source.

The advantages of compiling include:

1. High runtime efficiency (optimized with -O3 during compilation)
2. Newer software versions

The drawback is that compilation takes a long time.

## How to Use

### 1. Get/Update the Script

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh
  ```

### 2. Execute the Script

```sh
bash ${HOME}/Xray-script.sh
```

### 3. Script Interface

```sh
--------------- Xray-script ---------------
 Version      : v2023-12-31(beta)
 Title        : Xray Management Script
 Description  : Xray frontend or Nginx SNI shunting
              : reality dest points to a self-built camouflage site
----------------- Installation Management ----------------
1. Install
2. Update
3. Uninstall
----------------- Operation Management ----------------
4. Start
5. Stop
6. Restart
----------------- Configuration Management ----------------
101. View Configuration
----------------- Other Options ----------------
201. Update to Latest Stable Kernel
202. Remove Extra Kernels
203. Change SSH Port
204. Optimize Kernel Parameters
-------------------------------------------
```

## Installation Paths

**Xray-script:** `/usr/local/etc/zxcvos_xray_script`

**Nginx:** `/usr/local/nginx`

**Cloudreve:** `/usr/local/cloudreve`

**Cloudflare

-warp:** `/usr/local/cloudflare_warp`

**Xray:** See **[Xray-install](https://github.com/XTLS/Xray-install)**

## Dependency List

The script may automatically install the following dependencies:
| Purpose                       | Debian-based Systems                | Red Hat-based Systems   |
| ----------------------------- | ----------------------------------- | ----------------------- |
| yumdb set (mark packages for manual installation) |                                   | yum-utils               |
| dnf config-manager            |                                   | dnf-plugins-core        |
| IP retrieval                  | iproute2                          | iproute                 |
| DNS resolution                | dnsutils                          | bind-utils              |
| wget                          | wget                              | wget                    |
| curl                          | curl                              | curl                    |
| wget/curl https               | ca-certificates                   | ca-certificates         |
| kill/pkill/ps/sysctl/free     | procps                            | procps-ng               |
| epel repository               |                                   | epel-release            |
| epel repository               |                                   | epel-next-release       |
| remi repository               |                                   | remi-release            |
| Firewall                      | ufw                               | firewalld               |
| **Compilation Basics:**       |                                   |                         |
| Download source files         | wget                              | wget                    |
| Unzip tar source files        | tar                               | tar                     |
| Unzip tar.gz source files     | gzip                              | gzip                    |
| gcc                            | gcc                               | gcc                     |
| g++                            | g++                               | gcc-c++                 |
| make                           | make                              | make                    |
| **acme.sh Dependencies:**     |                                   |                         |
|                               | curl                              | curl                    |
|                               | openssl                           | openssl                 |
|                               | cron                              | crontabs                |
| **Compile openssl:**          |                                   |                         |
|                               | perl-base (included in libperl-dev)| perl-IPC-Cmd            |
|                               | perl-modules-5.32 (included in libperl-dev)| perl-Getopt-Long    |
|                               | libperl5.32 (included in libperl-dev)| perl-Data-Dumper        |
|                               |                                   | perl-FindBin            |
| **Compile Brotli:**           |                                   |                         |
|                               | git                               | git                     |
|                               | libbrotli-dev                     | brotli-devel            |
| **Compile Nginx:**            |                                   |                         |
|                               | libpcre2-dev                      | pcre2-devel             |
|                               | zlib1g-dev                        | zlib-devel              |
| --with-http_xslt_module       | libxml2-dev                       | libxml2-devel           |
| --with-http_xslt_module       | libxslt1-dev                      | libxslt-devel           |
| --with-http_image_filter_module| libgd-dev                         | gd-devel                |
| --with-google_perftools_module | libgoogle-perftools-dev           | gperftools-devel        |
| --with-http_geoip_module       | libgeoip-dev                      | geoip-devel             |
| --with-http_perl_module        |                                   | perl-ExtUtils-Embed     |
|                               | libperl-dev                       | perl-devel              |

## Credits

[Xray-core][Xray-core]

[REALITY][REALITY]

[chika0801 Xray 配置文件模板][chika0801-Xray-examples]

[部署 Cloudflare WARP Proxy][haoel]

[cloudflare-warp 镜像][e7h4n]

[WARP 一键脚本][fscarmen]

[V2Ray 路由规则文件加强版][v2ray-rules-dat]

[kirin10000/Xray-script][kirin10000/Xray-script]

[使用Nginx进行SNI分流并完美和网站共存][nginx-sni-dispatcher]

[[小白参阅系列] 第〇篇 手搓 Nginx 安装][post-37224-1]

[Cloudreve][cloudreve]

**This script is for educational purposes only. Do not use it for illegal activities.**

[Xray-core]: https://github.com/XTLS/Xray-core (THE NEXT FUTURE)
[REALITY]: https://github.com/XTLS/REALITY (THE NEXT FUTURE)
[chika0801-Xray-examples]: https://github.com/chika0801/Xray-examples (chika0801 Xray 配置文件模板)
[haoel]: https://github.com/haoel/haoel.github.io#943-docker-%E4%BB%A3%E7%90%86 (使用 Docker 快速部署 Cloudflare WARP Proxy)
[e7h4n]: https://github.com/e7h4n/cloudflare-warp (cloudflare-warp 镜像)
[fscarmen]: https://github.com/fscarmen/warp (WARP 一键脚本)
[fscarmen-warpproxy]: https://github.com/fscarmen/warp/blob/main/README.md#Netflix-%E5%88%86%E6%B5%81%E5%88%B0-WARP-Client-ProxyWireProxy-%E7%9A%84%E6%96%B9%E6%B3%95 (Netflix 分流到 WARP Client Proxy、WireProxy 的方法)
[v2ray-rules-dat]: https://github.com/Loyalsoldier/v2ray-rules-dat (V2Ray 路由规则文件加强版)
[kirin10000/Xray-script]: https://github.com/kirin10000/Xray-script (kirin10000/Xray-script)
[nginx-sni-dispatcher]: https://blog.xmgspace.me/archives/nginx-sni-dispatcher.html (使用Nginx进行SNI分流并完美和网站共存)
[post-37224-1]: https://www.nodeseek.com/post-37224-1 (第〇篇 手搓 Nginx 安装)
[cloudreve]: https://github.com/cloudreve/cloudreve (cloudreve)
