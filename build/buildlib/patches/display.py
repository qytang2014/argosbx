"""Status display, res subcommand. Moved verbatim from main() in build/build.py."""
from ..util import replace


def apply(t, ctx):
    # --- status display: alert if configured kernel is stopped/dead ---
    old_status = """argosbxstatus(){
echo "=========当前三大内核运行状态========="
procs=$(find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null)
if echo "$procs" | grep -Eq 'agsbx/s' || pgrep -f 'agsbx/s' >/dev/null 2>&1; then
echo "Sing-box (版本V$("$HOME/agsbx/sing-box" version 2>/dev/null | awk '/version/{print $NF}'))：运行中"
else
echo "Sing-box：未启用"
fi
if echo "$procs" | grep -Eq 'agsbx/x' || pgrep -f 'agsbx/x' >/dev/null 2>&1; then
echo "Xray (版本V$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}'))：运行中"
else
echo "Xray：未启用"
fi
if echo "$procs" | grep -Eq 'agsbx/c' || pgrep -f 'agsbx/c' >/dev/null 2>&1; then
echo "Argo (版本V$("$HOME/agsbx/cloudflared" version 2>/dev/null | awk '{print $3}'))：运行中"
else
echo "Argo：未启用"
fi
}"""
    new_status = """argosbxstatus(){
echo "=========当前三大内核运行状态========="
local _warn_dead=0
procs=$(find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null)
if echo "$procs" | grep -Eq 'agsbx/s' || pgrep -f 'agsbx/s' >/dev/null 2>&1; then
echo "Sing-box (版本V$("$HOME/agsbx/sing-box" version 2>/dev/null | awk '/version/{print $NF}'))：运行中"
elif [ -f "$HOME/agsbx/sb.json" ]; then
echo "Sing-box：⚠️ 已配置但未在运行 (异常/停止)"
_warn_dead=1
else
echo "Sing-box：未启用"
fi
if echo "$procs" | grep -Eq 'agsbx/x' || pgrep -f 'agsbx/x' >/dev/null 2>&1; then
echo "Xray (版本V$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}'))：运行中"
elif [ -f "$HOME/agsbx/xr.json" ]; then
echo "Xray：⚠️ 已配置但未在运行 (异常/停止)"
_warn_dead=1
else
echo "Xray：未启用"
fi
if echo "$procs" | grep -Eq 'agsbx/c' || pgrep -f 'agsbx/c' >/dev/null 2>&1; then
echo "Argo (版本V$("$HOME/agsbx/cloudflared" version 2>/dev/null | awk '{print $3}'))：运行中"
elif [ -e "$HOME/agsbx/sbargotoken.log" ] || [ -e "$HOME/agsbx/argoport.log" ]; then
echo "Argo：⚠️ 已配置但未在运行 (异常/停止)"
_warn_dead=1
else
echo "Argo：未启用"
fi
if [ "$_warn_dead" = "1" ]; then
echo
echo "⚠️  【告警】检测到已配置的内核未在运行！"
echo "👉 可尝试执行 agsbx res 重启内核，或执行 agsbx check 进行深度诊断排查。"
fi
}"""
    t = replace(t, old_status, new_status, "argosbxstatus-enhanced", 1)

    # --- res subcommand: unconditionally restart configured kernels even if dead ---
    old_res = """elif [ "$1" = "res" ]; then
for P in /proc/[0-9]*; do
[ -L "$P/exe" ] || continue
TARGET=$(readlink -f "$P/exe" 2>/dev/null) || continue
case "$TARGET" in
*"/agsbx/s"*)
kill "$(basename "$P")" 2>/dev/null
sbrestart
;;
*"/agsbx/x"*)
kill "$(basename "$P")" 2>/dev/null
xrestart
;;
*"/agsbx/c"*)
kill "$(basename "$P")" 2>/dev/null
kill -15 $(pgrep -f 'agsbx/c' 2>/dev/null) >/dev/null 2>&1
if [ -e "$HOME/agsbx/sbargotoken.log" ]; then
if pidof systemd >/dev/null 2>&1; then
systemctl restart argo >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
rc-service argo restart >/dev/null 2>&1
else
nohup $HOME/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol $(cat $HOME/agsbx/cftupr.log 2>/dev/null) run --token $(cat $HOME/agsbx/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 &
fi
else
nohup $HOME/agsbx/cloudflared tunnel --url http://localhost:$(cat $HOME/agsbx/argoport.log 2>/dev/null) --edge-ip-version auto --no-autoupdate --protocol $(cat $HOME/agsbx/cftupr.log 2>/dev/null) > $HOME/agsbx/argo.log 2>&1 &
fi
;;
esac
done
sleep 5 && echo "重启完成" && sleep 3 && cip
exit"""
    new_res = """elif [ "$1" = "res" ]; then
for P in /proc/[0-9]*; do
[ -L "$P/exe" ] || continue
TARGET=$(readlink -f "$P/exe" 2>/dev/null) || continue
case "$TARGET" in
*"$HOME/agsbx/s"*|*"$HOME/agsbx/x"*|*"$HOME/agsbx/c"*)
kill "$(basename "$P")" 2>/dev/null
;;
esac
done
if [ -f "$HOME/agsbx/sb.json" ]; then
sbrestart
fi
if [ -f "$HOME/agsbx/xr.json" ]; then
xrestart
fi
if [ -e "$HOME/agsbx/sbargotoken.log" ] || [ -e "$HOME/agsbx/argoport.log" ]; then
kill -15 $(pgrep -f 'agsbx/c' 2>/dev/null) >/dev/null 2>&1
if [ -e "$HOME/agsbx/sbargotoken.log" ]; then
if pidof systemd >/dev/null 2>&1; then
systemctl restart argo >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
rc-service argo restart >/dev/null 2>&1
else
nohup "$HOME/agsbx/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol $(cat "$HOME/agsbx/cftupr.log" 2>/dev/null) run --token $(cat "$HOME/agsbx/sbargotoken.log" 2>/dev/null) >/dev/null 2>&1 &
fi
else
nohup "$HOME/agsbx/cloudflared" tunnel --url http://localhost:$(cat "$HOME/agsbx/argoport.log" 2>/dev/null) --edge-ip-version auto --no-autoupdate --protocol $(cat "$HOME/agsbx/cftupr.log" 2>/dev/null) > "$HOME/agsbx/argo.log" 2>&1 &
fi
fi
sleep 5 && echo "重启完成" && sleep 3 && cip
exit"""
    t = replace(t, old_res, new_res, "res-deterministic-restart", 1)
    return t
