# Xray-REALITY 管理脚本

* 一个纯 Shell 编写的 REALITY 管理脚本
* 使用 VLESS-XTLS-uTLS-REALITY 配置
* 实现 xray 监听端口的自填
* 实现 dest 的自选与自填
* 实现自填 dest 的 TLSv1.3 与 H2 验证
* 实现自填 dest 的 serverNames 自动获取
* 实现自动获取的 serverNames 通配符域名与 CDN SNI 域名的过滤
  * dest 可以设置为目标网站的子域名，但如果该域名在 SNI 属于通配符匹配的域名的话，将不会自动进入到 serverNames
  * 如果需要使用的话请编辑 `/usr/local/etc/xray/config.json` 配置文件
  * 或者编辑 `/usr/local/etc/xray-script/config.json` 后使用 `104. 修改 dest` 重新选择对应的 dest 实现需求
* 实现自填 dest 的 spiderX 的自定义，例如：fmovies.to/home
  ```sh
  # 该 SpiderX 仅适用于和 dest 一致的 serverName
  SNI     : fmovies.to
  SpiderX : /home
  
  # 由于通配符原因不适配子域名，可能造成一些问题，例如：toarumajutsunoindex.fandom.com/wiki/Toaru_Majutsu_no_Index_Wiki
  # 虽然 SpiderX 还是展示了 /wiki/Toaru_Majutsu_no_Index_Wiki
  SpiderX : /wiki/Toaru_Majutsu_no_Index_Wiki
  
  # 但因实现了通配符域名与 CDN SNI 域名的过滤缘故无法将 toarumajutsunoindex.fandom.com 添加到 serverNames 中
  # 如果 serverName 为 fandom.com 的时候强行使用 /wiki/Toaru_Majutsu_no_Index_Wiki 我也不知道会不会有什么问题
  # 想要了解请看 REALITY 源码或问一下 @rprx or @nekohasekai or @yuhan6665
  # 如有需求请编辑 `/usr/local/etc/xray-script/config.json` 后使用 `104. 修改 dest` 重新选择对应的 dest 实现需求
  ```
* 默认配置禁回国流量、广告、bt
* 实现 geo 文件的自动更新

## 如何使用

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh
  bash ${HOME}/Xray-script.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh
  bash ${HOME}/Xray-script.sh
  ```

## 脚本界面

```sh
--------------- Xray-script ---------------
 Version      : v2023-03-15(beta)
 Description  : Xray 管理脚本
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
102. 信息统计
103. 修改 id
104. 修改 dest
105. 修改 x25519 key
106. 修改 shortIds
107. 修改 xray 监听端口
----------------- 其他选项 ----------------
201. 更新至最新稳定版内核
202. 卸载多余内核
203. 修改 ssh 端口
204. 网络连接优化
-------------------------------------------
```

## 客户端配置

| 名称 | 值 |
| :--- | :--- |
| 地址 | IP 或服务端的域名 |
| 端口 | 443 |
| 用户ID | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx |
| 流控 | xtls-rprx-vision |
| 传输协议 | tcp |
| 传输层安全 | reality |
| SNI | learn.microsoft.com |
| Fingerprint | chrome |
| PublicKey | wC-8O2vI-7OmVq4TVNBA57V_g4tMDM7jRXkcBYGMYFw |
| shortId | 6ba85179e30d4fc2 |
| spiderX | / |

## 致谢

[Xray-core][Xray-core]

[REALITY][REALITY]

[chika0801 Xray 配置文件模板][chika0801-Xray-examples]

[Xray-core]: https://github.com/XTLS/Xray-core (THE NEXT FUTURE)
[REALITY]: https://github.com/XTLS/REALITY (THE NEXT FUTURE)
[chika0801-Xray-examples]: https://github.com/chika0801/Xray-examples (chika0801 Xray 配置文件模板)

**此脚本仅供交流学习使用，请勿使用此脚本行违法之事。网络非法外之地，行非法之事，必将接受法律制裁。**
