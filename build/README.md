# 构建说明（第 1 阶段：argosbx.sh 分层，第 2 步起含容器）

## 第 1 步重构后（2026-11-21，build.py 拆包 + 锚点注册表）

本节优先于下面过时的说法（下面仍称 `build/build.py` 为"锚点替换清单"、上游为 08c5416 的地方已过期）。

- 布局：`build/build.py` 是 49 行瘦入口（参数解析 + 调包）；`build/buildlib/` 是包——`util.py`（ROOT/read/replace/insert_after + 锚点注册表）、`compose.py`（流水线）、`index.py`（生成器）、`container.py`（容器）、`patches/`（每区一个 `apply(t, ctx)`，core/topmods/vlpt/comma/cert/egress/subcmds/display/address/links，compose 按原顺序调用）。不要在入口加 patch。
- **第 2 步规则：新功能不新增锚点。** 按顺序选手段，能用前面的就不用后面的：① hook（`register_hook <事件> <函数>`，事件见 modules/hook.sh：on_init、pre_xrsbout、post_start、on_complete、on_uninstall、dispatch（子命令分发，第 3 步）；新协议的订阅/显示条目优先走 hook）；② 变量覆盖（只改变量清单与对应的 ufw/rep-inherit/egress 登记）；③ 锚点（只有必须改上游函数中间时才加，要短、落函数边界或稳定行、有名字、有 expected 计数）。
- 锚点注册表：每次 `replace()` / `insert_after()` 都登记（名字、区、期望数、实际数），`UPSTREAM_VERIFIED`（buildlib/util.py）记本次验证过的上游 HEAD 短 SHA，**每次同步上游时更新它**。检查：`python3 build/build.py --check-anchors`（不写文件，输出每锚点状态表，全 OK exit 0，有 STALE exit 1）。
- 锚点预算：`tests/test_anchor_budget.sh` 是棘轮，当前上限 238 个（第 3 步把 7 个子命令分发锚点转成 1 个 `run_hook dispatch` 调用后为 236；auto-sni 2026-11-21 加 2 个 A 锚点——auto-sni.sh 模块插入 + ins() 内一次调用，调用点必须落在 ins() 内、ins() 没有可挂的 hook 点）。分类见 `build/ANCHORS.md`：A 模块插入 55、B 直接内容 patch 169、C 可转 hook 19（已迁移 7，订阅/分组列表 12 个因交错顺序无法用追加 hook 复现而保留）、D 其他 1。之后再加锚点必须先转 hook，实在转不了才改上限并在提交信息里写理由。
- 局限：少数内联 BUILD FAIL 检查（index-layout-swap、vmtls-call、ca.log、pin-clash 等）不走注册表，check 模式下它们直接 exit 1、不打印表；链式锚点（模式串由前一个 replace 产生）前置失败时会连带报 STALE，先看每区第一个失败的。
- 同步上游：换 `upstream/` → `--check-anchors` 看表修 STALE → 更新 `UPSTREAM_VERIFIED` → `python3 build/build.py` → `bash tests/run_all.sh` 连跑两遍 → push 前按站立规则先说明、等 QUINN 点确认再 push，推完 git fetch/log 复核 HEAD；同步后单独再推 upstream 文件（push 清单排除 upstream/*，漏推会断 GHCR 构建）。

## 不要手改的文件
- `argosbx.sh`、`index.html`（根目录）、`container/nodejs/start.sh`：**构建产物**，由 `build/build.py` 生成，手改下次构建会被覆盖。
- `upstream/argosbx.sh`、`upstream/index.html`、`upstream/container/nodejs/start.sh`：**上游原版**，现在是 `yonggekkk/argosbx main@7497089`，不要在里面加私有内容。注意上游 index.html 是 CRLF，构建时会统一转成 LF。容器原版与之前私有版只差项目链接一行（yonggekkk → qytang2014）。

## 可以改的文件
- `modules/cert.sh`：证书 / Caddy / acme 功能。
- `modules/egress.sh`：动态出口功能。
- `modules/cert-main.sh`：主流程里证书那一段的替换块（上游原来是调用外部 acme-yg 脚本）。
- `modules/index-cert.html`：页面里的证书 UI（ym / certmode / certsrc 三行）。
- `modules/index-egress.html`：页面里的出口 UI（egress_nodes / egress_bind / egress_rules 三行）。
- `build/buildlib/`：锚点替换清单（按区拆在 `patches/`）。加新功能时，先加模块文件，再按上面"第 2 步规则"选手段（hook 优先），不要直接改生成文件。

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
2. 按上面"第 2 步规则"选手段：hook / 变量覆盖优先，锚点是最后手段（并受锚点预算测试约束）。
3. 跑构建和测试，不要直接改 `argosbx.sh`，不要改 `upstream/argosbx.sh`。

## 容器（第 2 步证书 + 域名地址，第 3 步后补 egress 对齐）
- 容器 egress 与主脚本共用 `modules/egress.sh`（最终版，含 trojan / vmess / shadowsocks、xhttp、geoip / geosite / 端口 / 协议规则），在 `xrsbout()` 前插入模块、`xrsbout()` 开头调 `egress_init`，4 个钩子（sing-box / xray 出站 + 路由）与主脚本同构，只是 sing-box 路由锚点按容器格式（6 空格 `{`）匹配。
- 容器没有生成页，egress 变量通过容器环境变量传入：`egress_nodes` / `egress_bind` / `egress_rules`（与主脚本相同的 `;` 格式，已在 `ins()` 导出列表里），空配置时生成的 JSON 与之前一致。
- geo 数据库（主脚本 + 容器共用同一逻辑）：只有规则里出现 `geoip:` / `geosite:` 才触发 `egress_geo_setup`，文件已存在就跳过；sing-box 的 `geoip.db` / `geosite.db`（SagerNet）下到 `$HOME/agsbx/geo/sing-box/`，xray 的 `geoip.dat` / `geosite.dat`（Loyalsoldier）下到 `$HOME/agsbx/geo/xray/`，sing-box route 通过 `egress_sb_geo_cfg` 钩子加 path 配置，xray 通过 `XRAY_LOCATION_ASSET=$HOME/agsbx/geo/xray`；下载失败只告警、不删规则。
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

## 统一路径（$HOME/agsbx 下面）
- 域名证书：`$HOME/agsbx/cert/cert.crt` + `private.key`（Caddy / acme 写这里；旧的 `$HOME/argosbx/cert/` 只在迁移时复制一次，不删除，acme 的安装路径会用新路径重跑一次 `--install-cert`，以后续期写新目录）。
- 自签证书：主脚本 `$HOME/agsbx/selfsigned/cert.crt` + `private.key`；容器里的生效 TLS 对是 `$HOME/agsbx/selfsigned/cert.pem` + `private.key`（域名时是到 `$HOME/agsbx/cert/` 的软链接，自签时是现生成的文件；容器宿主证书先查 `$HOME/agsbx/cert/`，再兜底旧的 `$HOME/argosbx/cert/`）。
- Caddyfile 回落路径：`$HOME/agsbx/Caddyfile`（单个文件，不另建目录；系统路径 `/etc/caddy/argosbx.caddyfile` 不变，那是系统 Caddy 服务的配置位置）。
- geo 数据库：`$HOME/agsbx/geo/sing-box/` 和 `$HOME/agsbx/geo/xray/`（见上）。
- 其它状态文件（`sb.json`、`xr.json`、`uuid`、`ym`、`SHA256.txt` 等）本来就在 `$HOME/agsbx/` 根目录，不动。

## 增量更新（`add`，主脚本）
- 每次成功安装 / `rep` 后，全部变量以 shell 转义形式存到 `$HOME/agsbx/vars.env`（600），失败的安装不覆盖上次的好状态，`list` / `upx` / `ups` / `res` / `del` 不动它。
- `只传新增/修改的变量 + 主脚本 add`：先读 `vars.env`，没传的变量继承旧值，传了的覆盖旧值，再重建配置并重启内核。端口、uuid 不变就复用，传了新端口才换；`ym` 不变不重新发证，`ym` 变了才对新域名重新发证；IP 每次重跑都会重新探测。
- `add` 不删协议（没传 = 继承），删协议仍用 `rep` 全量重置。`vars.env` 缺失、或合并后没有任何协议时，`add` 直接失败退出，不会把旧安装悄悄丢掉。
- 第一版是变量级合并：出口分流还是整串替换，单节点追加（`egress_add`）以后再做；容器暂不做增量（没有生成器页面）。
