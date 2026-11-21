# 锚点分类表（第 3 步，2026-11-21）

上游基线：`yonggekkk/argosbx main@7497089`。运行时锚点总数 **238**（`python3 build/build.py --check-anchors`）。

类别定义：

- **A 模块插入**——`insert_after` 插整个模块文件（或插入一个函数调用行），落函数边界/稳定行：已是 hook 式插入，保留锚点。
- **B 直接内容 patch**——改上游现有文本（URL、版本号、路径、条件、JSON 值）：必须保留锚点，没有可挂的 hook 点。
- **C 可转 hook**——往上游的列表/组装点追加我们条目，或往分发链插子命令：迁移候选。
- **D 其他**——逐项判断，判不了就保留并写原因。

## 汇总

| 类别 | 数量 | 决定 |
| --- | --- | --- |
| A 模块插入 | 55 | 全部保留 |
| B 直接内容 patch | 169 | 全部保留 |
| C 可转 hook | 19 | 迁移 7（分发链），保留 12（订阅/分组列表，见原因） |
| D 其他 | 1 | 保留 |
| **合计** | **244** | **迁移后 238**（7 个分发锚点 → 1 个 `dispatch-hook`；auto-sni 2026-11-21 加 2 个 A 锚点） |

第 3 步第 1 批（已做，见下）：子命令分发 7 个锚点 → 1 个 `run_hook dispatch` 调用锚点 + 9 个 handler（写进对应 `modules/*.sh`，`register_hook dispatch` 注册）。`BUDGET` 由 242 改为 236。

未迁移的 C（12 个）保留原因：订阅组装行 `sbxy/clxy/sbgz/clgz` 与分组列表里，我们的条目与上游条目**交错**排列（例如最终 sbxy 顺序是 `sbvlpt; sbvlpt_more; sbsnpt; sbsspt_more; sbsspt; sbanpt_more; …`——我们的条目分处 3 个不同位置）。追加式 hook 只能把条目放列表末尾，会改变订阅文件里的节点顺序，违反行为等价；运行时字符串手术（在 handler 里按模式插入）只是把脆弱的模式匹配从构建时移到运行时，失败时静默出错订阅而非构建时大声报错，更差。所以这 12 个锚点保留：它们每个都有名字与 expected 计数，上游改行时构建即报错，是当前最诚实的形式。

不计入 242 的：`index-cert-ui` 与 `egress-module-anchor` 两个 `insert_after` 是 `if False` 死调用，不进注册表；另有若干内联 `BUILD FAIL` 检查（`ca.log`、`grep-ygkkkca`、`vmtls-call`、`pin-clash`、`pin-singbox`、`container-vmtls-call`、`container-vmtls-display-anchor`、`index-layout-swap`、`index-layout-columns`）不走注册表（第 1 步已知局限）。

## core（11：B 11）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| script-url | B | 保留：上游 raw 链接改自家仓库 |
| agsbxurl | B | 保留：同上 |
| showmode-main-url | B | 保留：显示文本改自家链接 |
| generator-url | B | 保留：生成器链接改自家 Pages |
| banner-project-url | B | 保留：作者署名改自家项目 |
| farewell-line | B | 保留：去掉作者名字 |
| showmode-acme-line | B | 保留：acme-yg 说明改证书来源说明 |
| kernel-verify-xray | B | 保留：下载失败中止，插在上游下载行中间 |
| kernel-verify-sb | B | 保留：同上 |
| kernel-startup-diagnostics | B | 保留：整段诊断替换上游一行报错 |
| script-copy-priority | B | 保留：安装命令改本地优先 |

## topmods（23：A 14，B 9）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| vmtls-top-list | B | 保留：上游顶层变量循环加 `vmtls` |
| warp-no-empty | B | 保留：上游 warp case 分支改空值行为 |
| warp-off-branch | B | 保留：同上，加 off/no/direct 分支 |
| warp-detect-wg | B | 保留：上游 WARP 检测条件改 WireGuard 检查 |
| vmtls-flag | B | 保留：上游 flag 处理加 `vmt=yes` |
| vmtls-rep-guard | B | 保留：rep/install 守卫条件加 `$vmt` |
| vmtls-port-export | B | 保留：端口 export 加 `port_vm_tls` |
| vmtls-recovery | B | 保留：恢复行加 `$vmt` |
| vars-module-anchor | A | 保留：hook+vars+proxy-script 模块插入 |
| ufw-module-anchor | A | 保留：模块插入 |
| subhttps-module-anchor | A | 保留：模块插入 |
| backup-module-anchor | A | 保留：模块插入 |
| check-module-anchor | A | 保留：模块插入 |
| help-module-anchor | A | 保留：模块插入 |
| audit-module-anchor | A | 保留：模块插入 |
| update-module-anchor | A | 保留：模块插入 |
| rep-inherit-anchor | A | 保留：模块插入 |
| ports-module-anchor | A | 保留：模块插入 |
| webserver-module-anchor | A | 保留：模块插入 |
| vlpt-coexistence-module-anchor | A | 保留：模块插入 |
| auto-sni-module-anchor | A | 保留：auto-sni.sh 模块插入（调用点在 vlpt 区的 auto-sni-call） |
| camouflage-module-anchor | A | 保留：模块插入 |
| export-list | B | 保留：上游 export 循环加私有变量 |

## vlpt（26：A 8，B 13，C 4，D 1）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| vmtls-inbound | A | 保留：vmtls.sh 模块插入 |
| recovery-line | B | 保留：恢复行 export 加私有变量 |
| vlpt-on-compute | A | 保留：vlpt_on 计算块插 ins() 顶部 |
| auto-sni-call | A | 保留：ins() 内调 auto_sni_resolve 一次（vlpt_on 算完、installxray/installsb 之前）；ins() 内无 hook 点，无法转 hook |
| vlpt-ins-xray-only | B | 保留：ins() 分支条件改 vlpt_on |
| vlpt-ins-sb-only | B | 保留：同上 |
| vlpt-sb-only-targo | B | 保留：Argo 变量赋值条件改 vlpt_on |
| vlpt-xray-guard | B | 保留：installxray vlpt 条件改 vlpt_on |
| vlpt-xray-else | B | 保留：同上 else 分支 |
| vlpt-sb-block | A | 保留：vlpt-sb.sh 模块插入 |
| vlpt-display-pbk | B | 保留：显示区 pbk/sid 赋值行插入（无 hook 点） |
| vlpt-display-guard | B | 保留：显示条件加 sb.json 检查 |
| vlpt-link-pbk | B | 保留：vlpt 链接 pbk/sid 改内核感知变量 |
| vlpt-link-name-vision | B | 保留：链接名 reality-enc 改回 vision |
| vlpt-inbound-decryption-none | B | 保留：入站 JSON decryption 改 none |
| sbvlpt-restore | A | 保留：sbvlpt-restore.sh 模块插入 |
| vlpt-clash-pbk | B | 保留：Clash 条目 pbk/sid 改变量 |
| vlpt-display-guard-tighten | B | 保留：显示守卫改精确 tag 匹配 |
| vlpt-comma-expand | A | 保留：vlpt-comma.sh 模块插入 |
| vlpt-more-xray-block | A | 保留：vlpt-more-xray.sh 模块插入 |
| vlpt-more-sb-block | A | 保留：vlpt-more-sb.sh 模块插入 |
| vlpt-more-display-block | D | 保留：混合——插显示模块 + 改 clvlpt1 的 reality-enc→vision；拆成两个锚点无收益 |
| vlpt-more-sbxy | C | 保留：交错顺序（sbvlpt/sbvlpt_more 在 sbsnpt 之前），追加 hook 会改订阅顺序 |
| vlpt-more-clxy | C | 保留：同上 |
| vlpt-more-sbgz | C | 保留：同上 |
| vlpt-more-clgz | C | 保留：同上 |

## comma（12：A 8，C 4）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| proto-comma-expand | A | 保留：proto-comma.sh 模块插入 |
| proto-more-xray-block | A | 保留：模块插入 |
| proto-more-sb-block | A | 保留：模块插入 |
| proto-more-hy-block | A | 保留：模块插入 |
| proto-more-vm-block | A | 保留：模块插入 |
| proto-more-vmtls-block | A | 保留：模块插入 |
| proto-more-so-block | A | 保留：模块插入 |
| proto-more-display-block | A | 保留：模块插入 |
| proto-more-sbxy | C | 保留：交错顺序（sbsspt_more 在 sbsnpt/sbsspt 之间，其余 _more 在 sbsspt 之后），追加 hook 会改订阅顺序 |
| proto-more-clxy | C | 保留：同上 |
| proto-more-sbgz | C | 保留：同上 |
| proto-more-clgz | C | 保留：同上 |

## cert（18：A 5，B 13）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| cert-module-anchor | A | 保留：cert.sh 模块插入 |
| showmode-add-line | B | 保留：显示文本加新子命令说明 |
| egress-exports-anchor | A | 保留：4 行 egress export 插入 |
| naive-condition | B | 保留：naive 条件改 domain_cert_ready |
| cert-path | B | 保留：证书路径改变量 |
| key-path | B | 保留：密钥路径改变量 |
| vars-save-call | A | 保留：插入 `vars_save` 调用 |
| ufw-sync-call | A | 保留：插入 `run_hook post_start` + `run_hook on_complete`（已是 hook 调用） |
| ym-autosub | B | 保留：订阅条件加 `|| [ -n "$ym" ]` |
| selfsigned-migrate-call | A | 保留：插入 `cert_migrate_paths` 调用 |
| selfsigned-gen-key | B | 保留：自签 key 路径改 selfsigned/ |
| selfsigned-gen-cert | B | 保留：自签 cert 路径改 selfsigned/ |
| selfsigned-san | B | 保留：自签加 SAN 参数 |
| selfsigned-san-migrate | B | 保留：迁移条件加 SAN 检查 |
| selfsigned-sha256 | B | 保留：SHA256 输入路径改 selfsigned/ |
| selfsigned-hta-cert | B | 保留：HTA cert 路径改 selfsigned/ |
| selfsigned-hta-key | B | 保留：HTA key 路径改 selfsigned/ |
| selfsigned-display-grep | B | 保留：显示 grep 路径改 selfsigned/ |

## subcmds（20：A 2，B 11，C 7）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| top-case-exclusion | B | 保留：sh.txt 保存排除 case 加新子命令 |
| installed-gate-check | B | 保留：进程扫描条件改 `agsbx_is_installed` 调用 |
| certwatch-dispatch | C | **迁移**：certwatch/certrestart → `dispatch_cert`（modules/cert-watch.sh） |
| ufwsync-dispatch | C | **迁移**：ufwsync/fwsync/fwstatus → `dispatch_fw`（modules/ufw.sh） |
| subhttpsync-dispatch | C | **迁移**：subhttpsync → `dispatch_subhttpsync`（modules/sub-https.sh） |
| backup-check-dispatch | C | **迁移**：check/backup/restore → `dispatch_check`/`dispatch_backup`/`dispatch_restore`（modules/check.sh、modules/backup.sh） |
| help-dispatch | C | **迁移**：--help/-h/help → `dispatch_help`（modules/help.sh） |
| audit-dispatch | C | **迁移**：audit → `dispatch_audit`（modules/audit.sh） |
| update-dispatch | C | **迁移**：up/update → `dispatch_update`（modules/update.sh） |
| ufw-del-cleanup | A | 保留：del 块插入 `run_hook on_uninstall`（已是 hook 调用；第 3 步因 certwatch-dispatch 移除，锚点旧文本去掉 `cert_remove_watch` 一行，见迁移说明） |
| backup-check-bypass | B | 保留：协议检查 bypass 条件加新子命令 |
| egress-init-call | A | 保留：插入 `run_hook pre_xrsbout`（已是 hook 调用） |
| sb-geo-cfg-hook | B | 保留：sing-box route JSON 插 `${egress_sb_geo_cfg}` 占位（变量由 egress 模块填） |
| xr-systemd-asset | B | 保留：xray systemd unit 加 asset env |
| xr-openrc-asset | B | 保留：同上 OpenRC |
| xr-restart-asset | B | 保留：同上 nohup 重启 |
| xr-outbounds-hook | B | 保留：xray outbounds JSON 插 `${egress_xr_outbounds}` 占位 |
| sb-outbounds-hook | B | 保留：sing-box outbounds JSON 插 `${egress_sb_outbounds}` 占位 |
| xr-routing-hook | B | 保留：xray routing JSON 插 `${egress_xr_rules}` 占位 |
| sb-routing-hook | B | 保留：sing-box routing JSON 插 `${egress_sb_rules}` 占位 |

### 第 1 批迁移说明（子命令分发 7 → 1）

- 新锚点 `dispatch-hook`（1 个）：在上游 `del` 分发块前插两行——`run_hook dispatch "$@"`，随后 `if [ "$_agsbx_restore_done" = "1" ]; then set --; fi`。
- 9 个 handler（各子命令原分发块 verbatim 移入函数，`exit` 语义不变）：`dispatch_cert`（certwatch/certrestart）、`dispatch_fw`（ufwsync/fwsync/fwstatus）、`dispatch_subhttpsync`、`dispatch_check`、`dispatch_help`、`dispatch_audit`、`dispatch_update`、`dispatch_backup`、`dispatch_restore`。
- 唯一语义特殊点是 restore：原块成功时 `set --` 清空参数后落入安装流；handler 在函数内无法 `set --` 主脚本参数，所以 handler 成功时只设 `_agsbx_restore_done=1` 并返回，由 hook 调用点的 `set --` 完成清空；失败时 handler 内 `exit $rc`，与原来一致。
- handler 间互斥（都按 `$1` 精确匹配），注册顺序不影响行为；新子命令以后只需在模块里加 handler + `register_hook dispatch`，不再动 build.py。
- `ufw-del-cleanup` 锚点旧文本随之改动：原来它的旧文本含 `cert_remove_watch` 一行（那是已删除的 certwatch-dispatch 插的），现改为上游原生的 del 块；新文本不变（`run_hook on_uninstall`），del 时 `cert_remove_watch` 仍经 on_uninstall hook 触发，行为不变。

## display（2：B 2）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| argosbxstatus-enhanced | B | 保留：整个状态函数替换为带告警版 |
| res-deterministic-restart | B | 保留：整个 res 分支替换为确定性重启版 |

## address（22：A 2，B 20）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| install-flow-gate | B | 保留：安装门条件改 `_is_install_run` 调用 |
| reality-addr-insert | A | 保留：reality-addr.sh 模块插入 |
| reality-xhttp-link | B | 保留：链接 `$server_ip` 改 `$reality_addr` |
| reality-tcp-link | B | 保留：同上 |
| reality-any-link | B | 保留：同上 |
| reality-sb-config | B | 保留：sing-box 配置 server 改 `$reality_addr` |
| reality-clash-config | B | 保留：Clash 配置 server 改 `$reality_addr`（兼改名 vision） |
| vlpt-clash-encryption-none | B | 保留：Clash vlpt 条目删 encryption 行 |
| reality-any-sb-config | B | 保留：sing-box any-reality server 改 `$reality_addr` |
| plain-xhttp-enc-link | B | 保留：链接改 `$domain_addr` |
| plain-ws-enc-link | B | 保留：同上 |
| plain-ss-link | B | 保留：同上 |
| plain-vm-link | B | 保留：同上 |
| plain-ss-sb-config | B | 保留：同上 |
| plain-ss-clash-config | B | 保留：同上 |
| plain-sn-link | B | 保留：Snell 链接改 `$domain_addr` |
| plain-sn-link2 | B | 保留：同上（base64 版） |
| plain-sn-sb-config | B | 保留：同上 |
| plain-sn-clash-config | B | 保留：同上 |
| plain-vm-sb-config | B | 保留：同上 |
| plain-vm-clash-config | B | 保留：同上 |
| pin-compute | A | 保留：pin 计算块插入 |

## links（19：A 4，B 11，C 4）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| vmtls-display | A | 保留：vmtls 显示块（原生链接 + sb + Clash 函数定义）插入 |
| vmtls-sb-group | C | 保留：交错顺序（sbvmtlspt 在 sbvmpt 与 sbhypt 之间），追加 hook 会改分组顺序 |
| vmtls-cl-group | C | 保留：同上 |
| vmtls-sb-group1 | C | 保留：同上 |
| vmtls-cl-group1 | C | 保留：同上 |
| cert-main-block | B | 保留：整个 acme-yg 块替换为私有 cert block |
| subhttps-display | B | 保留：整个订阅显示块替换为 sync + display |
| reality-fb-var | B | 保留：回落变量 export 改条件赋值 + 插 web server 调用 |
| hostname-override | B | 保留：hostname 赋值改用户可覆盖 |
| del-symlink | A | 保留：del 块插入删 /usr/local/bin 软链行 |
| agsbx-symlink | A | 保留：插入建软链行 |
| agsbx-path-hint | A | 保留：插入 PATH 提示行（链在 agsbx-symlink 后） |
| no-iptables-persistent-debconf | B | 保留：删 iptables-persistent debconf 行 |
| no-iptables-persistent | B | 保留：apt 安装行删 iptables-persistent |
| name-stale-cleanup | B | 保留：name 为空时清理残留分支 |
| reality-fb-dest | B | 保留：Reality dest 改回落变量 |
| reality-fb-target | B | 保留：同上 target |
| reality-fb-handshake | B | 保留：handshake server 改回落变量 |
| reality-fb-handshake-port | B | 保留：handshake port 改回落变量 |

## index（36：B 36）

生成器是静态 HTML/JS，没有运行时 hook 机制，全部是内容 patch，保留。

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| index-title | B | 保留：标题改 Vincent |
| index-header | B | 保留：头部署名改自家项目 |
| index-reym-hint | B | 保留：reym 输入提示 |
| index-alns-text | B | 保留：alns 开启选项文案 |
| index-alns-closed-naive | B | 保留：alns 关闭选项补 Naive |
| index-grid | B | 保留：布局 CSS 改双列 flex |
| index-grid-mobile | B | 保留：移动端布局 CSS |
| index-card-placement | B | 保留：卡片 grid 定位 CSS |
| index-footer-link | B | 保留：页脚链接改自家仓库 |
| index-footer-acme | B | 保留：页脚 acme 说明改证书说明 |
| index-curl | B | 保留：curl 命令改自家仓库 |
| index-wget | B | 保留：wget 命令改自家仓库 |
| index-optids | B | 保留：optIds 加私有字段 |
| warp-default-no | B | 保留：warp 默认选项 value 改 no |
| index-hostname-field | B | 保留：加 hostname 输入行 |
| index-reset-cert | B | 保留：重置加清证书字段 |
| index-vlpt-out-of-xray | B | 保留：vlpt 复选框移出 Xray 组 |
| index-vlpt-dual-group | B | 保留：加双内核协议组 |
| index-field-note-css | B | 保留：field-note/section-note CSS |
| index-comma-section-note | B | 保留：逗号多实例说明 |
| index-vlpt-kernel-dynamic | B | 保留：vlpt_kernel 联动 JS |
| index-reset-egress | B | 保留：重置加清 egress 字段 |
| index-egress-listeners | B | 保留：egress 输入监听 JS |
| index-reym-autosync | B | 保留：reym 跟随 ym 的 JS |
| index-reym-autosync-enable | B | 保留：同上启用时同步 |
| index-reym-autosync-reset | B | 保留：同上重置清标记 |
| index-reym-autosync-parse | B | 保留：同上粘贴回填重判 |
| index-collect-egress | B | 保留：收集 egress 时多行转 `;` |
| index-tobash-order | B | 保留：生成命令字段顺序加私有字段 |
| index-add-button | B | 保留：加 add 按钮 |
| index-vmtls-checkbox | B | 保留：加 vmtls 复选框 |
| index-vmtls-protokeys | B | 保留：protoKeys 加 vmtls |
| index-add-handler | B | 保留：add 命令处理 |
| index-add-output | B | 保留：add 输出命令 |
| index-stray-cite-line | B | 保留：删上游 stray 行 |
| index-quote-escape-fix | B | 保留：修上游引号转义 typo |

## container（55：A 12，B 43）

| 名字 | 类别 | 决定 |
| --- | --- | --- |
| container-vars-module | A | 保留：container-vars.sh 模块插入 |
| container-ufw-module | A | 保留：模块插入 |
| container-comma-module | A | 保留：模块插入 |
| container-banner-project-url | B | 保留：署名改自家项目 |
| container-project-link | B | 保留：项目链接改自家仓库 |
| container-dpdns-cfip | B | 保留：默认 CDN 域名改 icook.tw（5 处） |
| container-dpdns-yg1..11 | B | 保留：同上（11 个锚点） |
| container-dpdns-note | B | 保留：注释文案改 icook.tw（3 处） |
| container-ym-export | B | 保留：export 加 ym/vlpt_kernel |
| container-vmtls-export | B | 保留：export 加 vmtls |
| container-vmtls-inbound | A | 保留：vmtls-container.sh 模块插入 |
| container-vlpt-on-compute | A | 保留：vlpt_on 计算块插入 |
| container-vlpt-ins-xray-only | B | 保留：ins 分支条件改 vlpt_on |
| container-vlpt-ins-sb-only | B | 保留：同上 |
| container-vlpt-xray-guard | B | 保留：installxray vlpt 条件改 vlpt_on |
| container-vlpt-sb-block | A | 保留：vlpt-sb-container.sh 模块插入 |
| container-vlpt-display-pbk | B | 保留：显示区 pbk/sid 赋值 |
| container-vlpt-display-guard | B | 保留：显示条件加 sb.json 检查 |
| container-vlpt-link-pbk | B | 保留：链接 pbk/sid 改变量 |
| container-cert-fn | A | 保留：container-cert.sh 模块插入 |
| container-cert-block | B | 保留：自签生成块替换为 container_cert_setup（含删公开密钥下载兜底） |
| container-display-addr | A | 保留：reality-addr.sh + display_tls 插入 |
| container-reality-xhttp | B | 保留：链接改 `$domain_addr` |
| container-reality-tcp | B | 保留：同上 |
| container-reality-any | B | 保留：同上 |
| container-plain-xhttp | B | 保留：同上 |
| container-plain-ws | B | 保留：同上 |
| container-plain-ss | B | 保留：同上 |
| container-plain-vm | B | 保留：同上 |
| container-tls-hy2 | B | 保留：hy2 链接改 add/sni/pin 变量 |
| container-tls-tuic | B | 保留：tuic 链接改 add/sni/insecure |
| container-tls-any | B | 保留：anytls 链接改 add/insecure |
| container-socks5-addr | B | 保留：显示地址改 `$domain_addr` |
| container-egress-exports | B | 保留：export 加 egress 变量 |
| container-tls-cert-path | B | 保留：证书路径改 selfsigned/（3 处） |
| container-tls-key-path | B | 保留：密钥路径改 selfsigned/（3 处） |
| container-egress-module | A | 保留：egress.sh 模块插入 |
| container-egress-init | A | 保留：插入 egress_init/egress_geo_setup 调用 |
| container-sb-geo-cfg-hook | B | 保留：route JSON 插占位 |
| container-xr-outbounds-hook | B | 保留：outbounds JSON 插占位 |
| container-sb-outbounds-hook | B | 保留：同上 |
| container-xr-routing-hook | B | 保留：routing JSON 插占位 |
| container-sb-routing-hook | B | 保留：同上 |
| container-vars-save | A | 保留：插入 container_vars_save 调用 |
| container-ufw-prompt-call | A | 保留：插入 container_ufw_prompt 调用 |
