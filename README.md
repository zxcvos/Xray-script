# Xray-REALITY 管理脚本

* 一个纯 Shell 编写的 REALITY 管理脚本
* 使用 VLESS-XTLS-uTLS-REALITY 配置
* 实现 xray 监听端口的自填
* 实现 dest 的自选与自填
* 实现自填 dest 的 TLSv1.3 与 H2 验证
* 实现自填 dest 的 serverNames 自动获取
* 实现自动获取的 serverNames 通配符域名与 CDN SNI 域名的过滤，dest 如果是子域名将会自动加入到 serverNames 中
* 实现自填 dest 的 spiderX 的自定义显示，例如：自填 dest 为 `fmovies.to/home` 时，client config 会显示 `spiderX: /home`
* 默认配置禁回国流量、广告、bt
* 实现 geo 文件的自动更新

## 如何使用

* wget

  ```sh
  wget --no-check-certificate -O ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash ${HOME}/Xray-script.sh
  ```

* curl

  ```sh
  curl -fsSL -o ${HOME}/Xray-script.sh https://raw.githubusercontent.com/zxcvos/Xray-script/main/reality.sh && bash ${HOME}/Xray-script.sh
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
