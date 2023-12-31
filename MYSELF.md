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

## How to Use

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh && bash ${HOME}/Xray-script.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh && bash ${HOME}/Xray-script.sh
  ```

## Script Interface

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
