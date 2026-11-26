"""Identity, kernel download verification/diagnostics, CLI install. Moved verbatim from main() in build/build.py."""
from ..util import replace


def apply(t, ctx):
    # --- identity: script URL only (binary download URLs stay upstream) ---
    t = replace(t, "url='https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh'",
                "url='https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh'", "script-url", 1)
    t = replace(t, 'agsbxurl="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"',
                'agsbxurl="https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh"', "agsbxurl", 1)
    t = replace(t, "echo \"主脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)\"",
                "echo \"主脚本：bash <(curl -Ls https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/qytang2014/argosbx/main/argosbx.sh)\"", "showmode-main-url", 1)
    t = replace(t, "https://yonggekkk.github.io/argosbx/", "https://qytang2014.github.io/argosbx/", "generator-url", 1)
    t = replace(t, 'echo "甬哥Github项目 ：github.com/yonggekkk"\necho "甬哥Blogger博客 ：ygkkk.blogspot.com"\necho "甬哥YouTube频道 ：www.youtube.com/@ygkkk"', 'echo "项目地址：github.com/qytang2014/argosbx"', "banner-project-url", 1)
    t = replace(t, 'echo "欢迎继续使用甬哥侃侃侃ygkkk的Argosbx一键无交互小钢炮脚本💣" && sleep 2', 'echo "欢迎继续使用Argosbx一键无交互小钢炮脚本💣" && sleep 2', "farewell-line", 1)
    t = replace(t, "echo \"申请本地IP域名证书脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)\"",
                "echo \"域名证书：由 Caddy 或 acme.sh 申请（certsrc 自动：低内存走 acme，否则走 Caddy；certmode 自动：未代理用 HTTP，已代理/Argo 用 DNS），固定目录 $HOME/agsbx/cert\"", "showmode-acme-line", 1)

    # --- kernel download verification (private): abort on failed download ---
    # upxray/upsingbox silently continued when curl/wget both failed (the
    # version probe swallowed errors with 2>/dev/null), surfacing much later
    # as a confusing "process not started" failure. Verify the binary exists,
    # is executable and reports its version; otherwise abort with a clear
    # message instead of limping on.
    t = replace(t, 'chmod +x "$HOME/agsbx/xray"\nsbcore=$("$HOME/agsbx/xray" version 2>/dev/null | awk \'/^Xray/{print $2}\')',
                'chmod +x "$HOME/agsbx/xray"\nif [ ! -x "$HOME/agsbx/xray" ] || ! "$HOME/agsbx/xray" version 2>/dev/null | grep -q \'^Xray\'; then echo "Xray 内核下载失败，安装中止"; rm -f "$HOME/agsbx/xray"; exit 1; fi\nsbcore=$("$HOME/agsbx/xray" version 2>/dev/null | awk \'/^Xray/{print $2}\')', "kernel-verify-xray", 1)
    t = replace(t, 'chmod +x "$HOME/agsbx/sing-box"\nsbcore=$("$HOME/agsbx/sing-box" version 2>/dev/null | awk \'/version/{print $NF}\')',
                'chmod +x "$HOME/agsbx/sing-box"\nif [ ! -x "$HOME/agsbx/sing-box" ] || ! "$HOME/agsbx/sing-box" version 2>/dev/null | grep -q \'sing-box version\'; then echo "Sing-box 内核下载失败，安装中止"; rm -f "$HOME/agsbx/sing-box"; exit 1; fi\nsbcore=$("$HOME/agsbx/sing-box" version 2>/dev/null | awk \'/version/{print $NF}\')', "kernel-verify-sb", 1)

    # --- kernel startup failure diagnostics (private): detailed diagnostics on failure ---
    startup_diag = '''echo "------------------------------------------------------------"
echo "❌ Argosbx脚本进程未启动，安装失败"
echo "正在诊断失败原因..."
echo "------------------------------------------------------------"
if command -v ss >/dev/null 2>&1; then
  echo "当前系统监听的 TCP 端口及对应进程:"
  ss -tlnp 2>/dev/null | head -n 25 || true
elif command -v netstat >/dev/null 2>&1; then
  echo "当前系统监听的 TCP 端口及对应进程:"
  netstat -tlnp 2>/dev/null | head -n 25 || true
fi
if [ -f "$HOME/agsbx/xr.json" ] && [ -x "$HOME/agsbx/xray" ]; then
  echo "--- Xray 配置校验测试 ---"
  env XRAY_LOCATION_ASSET="$HOME/agsbx/geo/xray" "$HOME/agsbx/xray" run -test -c "$HOME/agsbx/xr.json" 2>&1 || true
  if pidof systemd >/dev/null 2>&1; then
    echo "--- systemctl status xr ---"
    systemctl status xr --no-pager -l 2>&1 | tail -n 15 || true
    echo "--- journalctl -u xr ---"
    journalctl -u xr -n 15 --no-pager 2>&1 || true
  fi
fi
if [ -f "$HOME/agsbx/sb.json" ] && [ -x "$HOME/agsbx/sing-box" ]; then
  echo "--- Sing-box 配置校验测试 ---"
  "$HOME/agsbx/sing-box" check -c "$HOME/agsbx/sb.json" 2>&1 || true
  if pidof systemd >/dev/null 2>&1; then
    echo "--- systemctl status sb ---"
    systemctl status sb --no-pager -l 2>&1 | tail -n 15 || true
    echo "--- journalctl -u sb ---"
    journalctl -u sb -n 15 --no-pager 2>&1 || true
  fi
fi
echo "------------------------------------------------------------"
exit 1'''
    t = replace(t, 'echo "Argosbx脚本进程未启动，安装失败" && exit', startup_diag, "kernel-startup-diagnostics", 1)

    # --- CLI binary installation: prioritize local running script over remote curl ---
    script_install_cmd = '''if [ -n "$0" ] && [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ] && [ "$0" != "sh" ] && [ -s "$0" ]; then
cp -f "$0" "$SCRIPT_PATH" 2>/dev/null || (command -v curl >/dev/null 2>&1 && curl -sL "$agsbxurl" -o "$SCRIPT_PATH") || (command -v wget >/dev/null 2>&1 && wget -qO "$SCRIPT_PATH" "$agsbxurl")
else
(command -v curl >/dev/null 2>&1 && curl -sL "$agsbxurl" -o "$SCRIPT_PATH") || (command -v wget >/dev/null 2>&1 && wget -qO "$SCRIPT_PATH" "$agsbxurl")
fi'''
    t = replace(t, '(command -v curl >/dev/null 2>&1 && curl -sL "$agsbxurl" -o "$SCRIPT_PATH") || (command -v wget >/dev/null 2>&1 && wget -qO "$SCRIPT_PATH" "$agsbxurl")', script_install_cmd, "script-copy-priority", 1)

    # --- Migrate CLI target path from $HOME/bin/agsbx to $HOME/.local/bin/agsbx ---
    t = replace(t, '$HOME/bin/agsbx', '$HOME/.local/bin/agsbx', "agsbx-local-bin-refs", 5)
    t = replace(t, 'mkdir -p "$HOME/bin"', 'mkdir -p "$HOME/.local/bin"', "agsbx-local-bin-mkdir", 1)

    # dead-private-key-block REMOVED: upstream d4f4b91 deleted the
    # commented-out private.key/cert.crt block itself; nothing left
    # to strip (final state already matches).
    return t
