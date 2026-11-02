## Argosbx一键无交互小钢炮脚本💣：极简 + 轻量 + 快速

> vincent 修改版：基于 yonggekkk/argosbx（main@08c5416，2026-10-23）修改，功能介绍如下。


---------------------------------------

<img width="757" height="255" alt="d89e2542c513e705106371acc7fa1d33" src="https://github.com/user-attachments/assets/7d7a4678-4223-478c-afe2-d303ba0f85a4" />

---------------------------------------

#### 1、基于Sing-box + Xray + Cloudflared-Argo 三内核自动分配

#### 2、支持主流VPS系统（推荐Ubuntu系统），SSH脚本支持非root环境运行，无脑一次回车搞定

#### 3、支持各种容器系统，Docker镜像部署，公开镜像库：```ghcr.io/qytang2014/argosbx```

#### 4、根据Sing-box与Xray不同内核，可选15种WARP出站组合，更换落地IP为WARP的IP，解锁流媒体

#### 5、客户端支持方面，各类单协议分享、clash/mihomo/singbox聚合订阅分享都可支持

#### 6、所有代理协议都无需域名（除了argo固定隧道、IP端口CDN），支持单个或多个代理协议任意组合并快速重置更换
【 已支持：Naiveproxy、Vless-xhttp-tls、AnyTLS、Any-reality、Vless-xhttp-reality-vison-enc、Vless-tcp-reality-vision、Vless-xhttp-vison-enc、Vless-ws-vision-enc、Shadowsocks-2022、Vmess-ws、Socks5、Hysteria2、Tuic、Argo临时/固定隧道支持Vless-ws-vision-enc或Vmess-ws 】

#### 7、建议配合SSH一键脚本命令生成器网页使用：https://qytang2014.github.io/argosbx/

#### 8、Argosbx客户端推荐：

安卓手机客户端：[Nekobox-starifly版(全协议支持)](https://github.com/starifly/NekoBoxForAndroid/releases)、[V2rayNG官方版](https://github.com/2dust/v2rayNG/releases)、[Singbox官方版](https://github.com/SagerNet/sing-box/releases)、Clash/Mihomo客户端随意

电脑win客户端：[V2rayN官方版(全协议支持)](https://github.com/2dust/v2rayN/releases)、[Singbox官方版](https://github.com/SagerNet/sing-box/releases)、Clash/Mihomo客户端随意

苹果IOS客户端：小火箭Shadowrocket、Onexray、Sing-bos MT、Clash mi

注：个别协议仅支持某些客户端

#### 9、vincent 修改版新增功能

**动态出口（egress）**：`egress_nodes` 配置落地节点（socks/vless/trojan/hy2/tuic/anytls/naive，`;` 分隔），`egress_rules` 按域名/IP/geo 分流，`egress_bind` 绑定出口 IP。Xray 与 sing-box 双内核自动适配。

**逗号多实例**：任一协议端口支持逗号列表，如 `vlpt="10001,10002,"` 表示实例1用10001、实例2随机。空项=随机端口。

**备份恢复**：`agsbx backup --webdav` 加密备份到 WebDAV，`agsbx restore --webdav` 恢复（uuid/密钥/证书重生成）。详见 `agsbx backup --help`。

**自检与审计**：`agsbx check` 检查进程/端口/证书/DNS/订阅/防火墙；`agsbx audit` 检查 SSH/防火墙/证书有效期/端口暴露。

**防火墙**：支持 ufw/firewalld 自动放行代理端口，从不开关你的防火墙。`agsbx fwsync` 手动同步，`agsbx fwstatus` 查看状态。
