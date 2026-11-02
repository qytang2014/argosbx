# help.sh: 顶层帮助（agsbx --help / -h / help）
# 列出所有子命令及用法。不修改系统。

agsbx_help(){
cat <<'HELP_EOF'
argosbx 一键无交互小钢炮脚本💣  项目地址：github.com/qytang2014/argosbx

用法：
  bash argosbx.sh [变量=值 ...] [子命令]
  或安装后：agsbx [子命令]

安装 / 更新：
  vlpt=10001 bash argosbx.sh          安装（vlpt 为示例，按需换协议变量）
  bash argosbx.sh rep                  重置协议（用 sh.txt 的变量重装）
  bash argosbx.sh add                  增量更新（只改给出的变量，其余继承）
  bash argosbx.sh del                  卸载清理

查看：
  bash argosbx.sh list                 显示节点链接与订阅
  agsbx check                          一键自检（进程/端口/证书/DNS/订阅/防火墙）
  agsbx audit                          安全审计（SSH/防火墙/证书/暴露面）

备份恢复：
  agsbx backup [file]                  本地明文备份
  agsbx backup --encrypt [file]        本地加密备份（口令交互或 BACKUP_PASSPHRASE）
  agsbx backup --webdav [远端路径]     加密上传 WebDAV（自动建子目录）
  agsbx backup --webdav-init           配置 WebDAV（URL/用户/密码）
  agsbx backup --webdav-ls [路径]      列出 WebDAV 上的备份
  agsbx restore <备份文件> [--yes]     本地恢复（默认输 yes 确认，清空重装）
  agsbx restore --webdav <远端路径> [--yes]
                                       从 WebDAV 恢复（uuid/密钥/证书重生成）

防火墙：
  agsbx fwsync   (ufwsync)             按记录规则同步放行端口
  agsbx fwstatus                       查看防火墙后端与已记录规则
  注：脚本从不开关防火墙，只在已启用的后端上添加放行规则

订阅：
  agsbx subhttpsync                    手动触发 https 订阅同步

证书：
  bash argosbx.sh certrestart          证书更新后重启内核
  bash argosbx.sh certwatch            手动跑一次证书巡检

其他：
  bash argosbx.sh --help               显示本帮助

协议变量（示例，详见生成器 https://qytang2014.github.io/argosbx/）：
  vlpt=10001                           VLESS Reality（TCP）
  hypt=10002                           Hysteria2（UDP）
  tupt=10003                           TUIC（UDP）
  vmpt="10004,"                        VMess-WS（逗号多实例：10004 + 随机）
  ym=example.com                       节点域名（Reality SNI 自动跟随）
  egress_nodes="socks5://..."          落地出口节点（; 分隔多节点）
HELP_EOF
return 0
}
