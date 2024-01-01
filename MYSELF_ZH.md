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

## 注意事项

1. 此脚本需要一个解析到服务器的域名。

2. 此脚本安装时间较长。

3. 此脚本设计为个人VPS用户使用。

4. 建议在纯净的系统上使用此脚本 (VPS控制台-重置系统，或使用 DD 脚本重装系统)。

## 已测试系统

| Platform | Version  |
| -------- | -------- |
| Debian   | 10,11,12 |
| Ubuntu   | 20,22,23 |
| CentOS   | 7,8,9    |
| Rocky    | 8,9      |

以上发行版均通过 Vultr 测试安装。

其他 Debian 基系统与 Red Hat 基系统可能能用，但未测试过，可能存在问题。

如果遇到 Docker 安装失败问题，请自行安装 Docker 后，将代码 `function install()` 函数中的 `install_docker` 注释再运行即可。

例如:

```sh
sed -i 's/install_docker$/# install_docker/' ${HOME}/Xray-script.sh
```

## 安装时长说明

此脚本适合安装一次后长期使用，不适合反复重置系统安装，这会消耗您的大量时间。如果需要更换配置和域名等，在管理界面都有相应的选项。

### 安装时长参考

安装流程：

更新系统管理包->安装依赖->安装Docker->安装Cloudreve->安装Cloudflare-warp->安装Xray->安装Nginx->申请证书->配置文件

**这是一台单核1G的服务器的平均安装时长，仅供参考：**

| 项目                | 时长      |
| ------------------- | --------- |
| 更新系统管理包      | 0-10分钟  |
| 安装依赖            | 0-5分钟   |
| 安装Docker          | 1-2分钟   |
| 安装Cloudreve       | 3-5分钟   |
| 安装Cloudflare-warp | 3-5分钟   |
| 安装Xray            | <半分钟   |
| 安装Nginx           | 13-15分钟 |
| 申请证书            | 1-2分钟   |
| 配置文件            | <100毫秒  |

### 为什么脚本安装时间那么长？

脚本的Nginx是采用源码编译的形式进行管理安装。

编译相比直接安装二进制文件的优点有：

1. 运行效率高 (编译时采用了-O3优化)
2. 软件版本新

缺点就是编译耗时长。

## 如何使用

### 1.获取/更新脚本

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/myself.sh
  ```

### 2.执行脚本

```sh
bash ${HOME}/Xray-script.sh
```

### 3.脚本界面

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

## 安装位置

**Xray-script:** `/usr/local/etc/zxcvos_xray_script`

**Nginx:** `/usr/local/nginx`

**Cloudreve:** `/usr/local/cloudreve`

**Cloudflare-warp:** `/usr/local/cloudflare_warp`

**Xray:** 见 **[Xray-install](https://github.com/XTLS/Xray-install)**

## 依赖列表

脚本可能自动安装以下依赖：
| 用途                            | Debian基系统                         | Red Hat基系统       |
| ------------------------------- | ------------------------------------ | ------------------- |
| yumdb set(标记包手动安装)       |                                      | yum-utils           |
| dnf config-manager              |                                      | dnf-plugins-core    |
| IP 获取                         | iproute2                             | iproute             |
| DNS 解析                        | dnsutils                             | bind-utils          |
| wget                            | wget                                 | wget                |
| curl                            | curl                                 | curl                |
| wget/curl https                 | ca-certificates                      | ca-certificates     |
| kill/pkill/ps/sysctl/free       | procps                               | procps-ng           |
| epel源                          |                                      | epel-release        |
| epel源                          |                                      | epel-next-release   |
| remi源                          |                                      | remi-release        |
| 防火墙                          | ufw                                  | firewalld           |
| **编译基础：**                  |                                      |                     |
| 下载源码文件                    | wget                                 | wget                |
| 解压tar源码文件                 | tar                                  | tar                 |
| 解压tar.gz源码文件              | gzip                                 | gzip                |
| gcc                             | gcc                                  | gcc                 |
| g++                             | g++                                  | gcc-c++             |
| make                            | make                                 | make                |
| **acme.sh依赖：**               |                                      |                     |
|                                 | curl                                 | curl                |
|                                 | openssl                              | openssl             |
|                                 | cron                                 | crontabs            |
| **编译openssl：**               |                                      |                     |
|                                 | perl-base(包含于libperl-dev)         | perl-IPC-Cmd        |
|                                 | perl-modules-5.32(包含于libperl-dev) | perl-Getopt-Long    |
|                                 | libperl5.32(包含于libperl-dev)       | perl-Data-Dumper    |
|                                 |                                      | perl-FindBin        |
| **编译Brotli：**                |                                      |                     |
|                                 | git                                  | git                 |
|                                 | libbrotli-dev                        | brotli-devel        |
| **编译Nginx：**                 |                                      |                     |
|                                 | libpcre2-dev                         | pcre2-devel         |
|                                 | zlib1g-dev                           | zlib-devel          |
| --with-http_xslt_module         | libxml2-dev                          | libxml2-devel       |
| --with-http_xslt_module         | libxslt1-dev                         | libxslt-devel       |
| --with-http_image_filter_module | libgd-dev                            | gd-devel            |
| --with-google_perftools_module  | libgoogle-perftools-dev              | gperftools-devel    |
| --with-http_geoip_module        | libgeoip-dev                         | geoip-devel         |
| --with-http_perl_module         |                                      | perl-ExtUtils-Embed |
|                                 | libperl-dev                          | perl-devel          |

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
[v2ray-rules-dat]: https://github.com/Loyalsoldier/v2ray-rules-dat (V2Ray 路由规则文件加强版)
[kirin10000/Xray-script]: https://github.com/kirin10000/Xray-script (kirin10000/Xray-script)
[nginx-sni-dispatcher]: https://blog.xmgspace.me/archives/nginx-sni-dispatcher.html (使用Nginx进行SNI分流并完美和网站共存)
[post-37224-1]: https://www.nodeseek.com/post-37224-1 (第〇篇 手搓 Nginx 安装)
[cloudreve]: https://github.com/cloudreve/cloudreve (cloudreve)
