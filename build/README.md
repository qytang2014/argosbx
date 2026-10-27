# 构建说明（第 1 阶段：argosbx.sh 分层，第 2 步起含容器）

## 不要手改的文件
- `argosbx.sh`、`index.html`（根目录）、`container/nodejs/start.sh`：**构建产物**，由 `build/build.py` 生成，手改下次构建会被覆盖。
- `upstream/argosbx.sh`、`upstream/index.html`、`upstream/container/nodejs/start.sh`：**上游原版**，现在是 `yonggekkk/argosbx main@08c5416`，不要在里面加私有内容。注意上游 index.html 是 CRLF，构建时会统一转成 LF。容器原版与之前私有版只差项目链接一行（yonggekkk → qytang2014）。

## 可以改的文件
- `modules/cert.sh`：证书 / Caddy / acme 功能。
- `modules/egress.sh`：动态出口功能。
- `modules/cert-main.sh`：主流程里证书那一段的替换块（上游原来是调用外部 acme-yg 脚本）。
- `modules/index-cert.html`：页面里的证书 UI（ym / certmode / certsrc 三行）。
- `modules/index-egress.html`：页面里的出口 UI（egress_nodes / egress_bind / egress_rules 三行）。
- `build/build.py`：锚点替换清单。加新功能时，先加模块文件，再在清单里加锚点，不要直接改生成文件。

## 构建
```
python3 build/build.py  # 同时生成 argosbx.sh、index.html、container/nodejs/start.sh
bash -n argosbx.sh
bash -n container/nodejs/start.sh
```

## 上游同步（以后）
1. 把新上游文件替换 `upstream/argosbx.sh` 和 / 或 `upstream/index.html`。
2. 跑 `python3 build/build.py`。
3. 如果构建报某个锚点缺失，说明上游改了那一行，只修 `build/build.py` 里那一个锚点，不要全文件合并。
4. 跑测试：`bash -n`、出口隔离测试、证书逻辑测试，再推。

## 加新功能（以后）
1. 新建 `modules/<功能>.sh`，只写自己的函数和变量。
2. 在 `build/build.py` 里加插入锚点和钩子（如果需要）。
3. 跑构建和测试，不要直接改 `argosbx.sh`，不要改 `upstream/argosbx.sh`。

## 容器（第 2 步证书 + 域名地址，第 3 步后补 egress 对齐）
- 容器 egress 与主脚本共用 `modules/egress.sh`（最终版，含 trojan / vmess / shadowsocks、xhttp、geoip / geosite / 端口 / 协议规则），在 `xrsbout()` 前插入模块、`xrsbout()` 开头调 `egress_init`，4 个钩子（sing-box / xray 出站 + 路由）与主脚本同构，只是 sing-box 路由锚点按容器格式（6 空格 `{`）匹配。
- 容器没有生成页，egress 变量通过容器环境变量传入：`egress_nodes` / `egress_bind` / `egress_rules`（与主脚本相同的 `;` 格式，已在 `ins()` 导出列表里），空配置时生成的 JSON 与之前一致。
- geo 数据库（主脚本 + 容器共用同一逻辑）：只有规则里出现 `geoip:` / `geosite:` 才触发 `egress_geo_setup`，文件已存在就跳过；sing-box 的 `geoip.db` / `geosite.db`（SagerNet）和 xray 的 `geoip.dat` / `geosite.dat`（Loyalsoldier）都下到 `$HOME/agsbx/`，sing-box route 通过 `egress_sb_geo_cfg` 钩子加 path 配置，xray 通过 `XRAY_LOCATION_ASSET=$HOME/agsbx`；下载失败只告警、不删规则。
- `modules/container-cert.sh`：容器证书选择函数。容器不发证：只有宿主已在 `$HOME/argosbx/cert/` 放好 cert.crt + private.key（且域名匹配 ym）时才用它（软链接到 cert.pem / private.key，容器重启后跟随宿主续期），否则回落本地自签；原版公开密钥下载兜底已删除。
- 容器 TLS 链接（HY2/TUIC/AnyTLS）用 `$add` / `$sni` / `$tls_ins`：域名证书就绪时 `add=ym, sni=ym, insecure=0`，否则 `add=IP, sni=www.bing.com, insecure=1`。
- 容器 Reality 与非 TLS 链接用复用的 `modules/reality-addr.sh`（`domain_addr`），SNI 仍是 `$reym`，CDN / Argo 链接不动，内核（sing-box / xray）仍从原版 release 下载。
- 上游代码本身不做去重 / 优化，那会再次破坏上游同步。构建产物大小和原来基本一致，变小的是每个源文件的规模和改动范围。

## 测试
```
bash tests/run_all.sh
```
先构建，再测构建同步、语法、出口、证书、页面、上游纯净，任何一步失败就停。单独跑某一个见 `tests/README.md`。

## 证书续期自动重启
- acme：`--install-cert` 时带 `--reloadcmd "bash $HOME/bin/agsbx certrestart"`，续期后立即重启。
- Caddy：没有续期钩子，改用每天 03:00 的 cron（`bash $HOME/bin/agsbx certwatch`），检查固定目录证书的 sha256 变化，变化且证书合法才重启。
- 域名证书就绪时安装 watcher 和初始 hash，回落自签或卸载（`del`）时清理 cron。
- 测试见 `tests/test_cert_watch.sh`。
