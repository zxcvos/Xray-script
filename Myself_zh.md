# Xray-REALITY 管理脚本

* 一个纯 Shell 编写的 REALITY 管理脚本
* 使用 VLESS-XTLS-uTLS-REALITY 配置
* 实现使用 Xray 前置偷自己证书，适合没有其他网站需求
* 实现使用 Nginx SNI 分流，Xray 后置偷自己证书，适合多网站共存需求
* 可自定义输入 UUID ，非标准 UUID 将使用 `Xray uuid -i "自定义字符串"` 进行映射转化为 UUIDv5
* 默认配置禁广告、bt
* 默认使用 Docker 部署 Cloudreve 作为个人网盘使用
* 默认使用 Docker 部署 Cloudflare WARP Proxy
* 回国流量默认走 Cloudflare WARP Proxy
* 实现 geo 文件的自动更新

## 如何使用

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh && bash ${HOME}/Xray-script.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh && bash ${HOME}/Xray-script.sh
  ```

## 脚本界面

```sh
--------------- Xray-script ---------------
 Version      : v2023-12-31(beta)
 Title        : Xray 管理脚本
 Description  : Xray 前置或 Nginx 分流
              : reality dest 目标为自建伪装站
----------------- 装载管理 ----------------
1. 安装
2. 更新
3. 卸载
----------------- 操作管理 ----------------
4. 启动
5. 停止
6. 重启
----------------- 配置管理 ----------------
101. 查看配置
----------------- 其他选项 ----------------
201. 更新至最新稳定版内核
202. 卸载多余内核
203. 修改 ssh 端口
204. 内核参数调优
-------------------------------------------
```

## 致谢

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

**此脚本仅供交流学习使用，请勿使用此脚本行违法之事。网络非法外之地，行非法之事，必将接受法律制裁。**

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
