"""Assembly pipeline — formerly main() in build/build.py.

Reads upstream + private modules, runs the patch modules in the
original order, applies the string post-processing, writes
argosbx.sh, then builds index.html and container/nodejs/start.sh.
"""
from . import util
from .container import build_container
from .index import build_index
from .patches import core, topmods, vlpt, comma, cert, egress, subcmds, display, address, links
from .util import ROOT, read

PATCHES = [
    ("core", core),
    ("topmods", topmods),
    ("vlpt", vlpt),
    ("comma", comma),
    ("cert", cert),
    ("egress", egress),
    ("subcmds", subcmds),
    ("display", display),
    ("address", address),
    ("links", links),
]


def build_all(check=False):
    """Run the full pipeline. check=True is --check-anchors mode: anchors
    are verified and reported, but no output file is written.
    Returns exit code (0 ok, 1 stale anchors in check mode)."""
    util.CHECK_MODE = check
    util.WRITE = not check
    util.REGISTRY.clear()
    t = read("upstream/argosbx.sh")
    ctx = {}
    ctx["cert"] = read("modules/cert.sh")
    ctx["egress"] = read("modules/egress.sh")
    ctx["cert_main"] = read("modules/cert-main.sh")
    ctx["cert_watch"] = read("modules/cert-watch.sh")
    ctx["vars_mod"] = read("modules/vars.sh")
    ctx["ufw_mod"] = read("modules/ufw.sh")
    ctx["subhttps_mod"] = read("modules/sub-https.sh")
    ctx["backup_mod"] = read("modules/backup.sh")
    ctx["check_mod"] = read("modules/check.sh")
    ctx["help_mod"] = read("modules/help.sh")
    ctx["audit_mod"] = read("modules/audit.sh")
    ctx["update_mod"] = read("modules/update.sh")
    ctx["repinherit_mod"] = read("modules/rep-inherit.sh")
    ctx["ports_mod"] = read("modules/ports.sh")
    ctx["webserver_mod"] = read("modules/web-server.sh")
    ctx["vlpt_coexistence_mod"] = read("modules/vlpt-coexistence.sh")
    ctx["hook_mod"] = read("modules/hook.sh")
    ctx["proxy_script_mod"] = read("modules/proxy-script.sh")
    for area, mod in PATCHES:
        util.CURRENT_AREA = area
        t = mod.apply(t, ctx)
    # --- consolidate port files to ports.env (string post-process) ---
    _port_vars = ['port_vl_re','port_xh','port_vx','port_xu','port_xc','port_vw',
                  'port_nv','port_tu','port_an','port_ar','port_ss','port_hy2','port_sn',
                  'port_vm_ws','port_vm_tls','port_so']
    _n = 0
    for _pv in _port_vars:
        _key = _pv[5:]
        # 旧块：7行标准模式
        _old = f'if [ -z "${_pv}" ] && [ ! -e "$HOME/agsbx/{_pv}" ];\n'
        # 注意：build.py 里 t 的换行是真实换行符，不是 \n
        # 我们需要构造真实的换行
        _old = _old.replace('\\n', '\n')
        # 实际上更简单：直接用真实字符串
        _old_real = f'if [ -z "${_pv}" ] && [ ! -e "$HOME/agsbx/{_pv}" ]; then\n'.replace('\\n', chr(10))
        _old_real += f'{_pv}=$(shuf -i 10000-65535 -n 1)' + chr(10)
        _old_real += f'echo "${_pv}" > "$HOME/agsbx/{_pv}"' + chr(10)
        _old_real += f'elif [ -n "${_pv}" ]; then' + chr(10)
        _old_real += f'echo "${_pv}" > "$HOME/agsbx/{_pv}"' + chr(10)
        _old_real += 'fi' + chr(10)
        _old_real += f'{_pv}=$(cat "$HOME/agsbx/{_pv}")'
        _new_real = f'{_pv}=$(port_resolve "{_key}" "${_pv}")'
        if _old_real in t:
            t = t.replace(_old_real, _new_real)
            _n += 1
    # ss 的特殊情况（含 sskey 行）
    _ss_old = 'fi\nsskey=$(cat "$HOME/agsbx/sskey")\nport_ss=$(cat "$HOME/agsbx/port_ss")'.replace('\\n', chr(10))
    _ss_new = 'fi\nsskey=$(cat "$HOME/agsbx/sskey")\nport_ss=$(port_resolve "ss" "$port_ss")'.replace('\\n', chr(10))
    if _ss_old in t:
        # ss 的块已经被上面的循环处理了（如果匹配的话），这里处理残留
        pass
    # ss 特例：含 sskey 行
    _ss_old = 'fi' + chr(10) + 'sskey=$(cat "$HOME/agsbx/sskey")' + chr(10) + 'port_ss=$(cat "$HOME/agsbx/port_ss")'
    _ss_new = 'fi' + chr(10) + 'sskey=$(cat "$HOME/agsbx/sskey")' + chr(10) + 'port_ss=$(port_resolve "ss" "$port_ss")'
    if _ss_old in t:
        t = t.replace(_ss_old, _ss_new)
        _n += 1
    # 删除 ss 残留的 6 行 if 块（port_resolve 已接管）
    _ss_if6 = 'if [ -z "$port_ss" ] && [ ! -e "$HOME/agsbx/port_ss" ]; then' + chr(10)
    _ss_if6 += 'port_ss=$(shuf -i 10000-65535 -n 1)' + chr(10)
    _ss_if6 += 'echo "$port_ss" > "$HOME/agsbx/port_ss"' + chr(10)
    _ss_if6 += 'elif [ -n "$port_ss" ]; then' + chr(10)
    _ss_if6 += 'echo "$port_ss" > "$HOME/agsbx/port_ss"' + chr(10)
    _ss_if6 += 'fi' + chr(10)
    if _ss_if6 in t:
        t = t.replace(_ss_if6, '')
        print("removed ss if-block")
    print(f"consolidated {_n} port blocks to ports.env")
    # --- 其他 port 文件读取 -> port_get ---
    _simple_reads = [
        ('port_xh', 'xh'), ('port_vx', 'vx'), ('port_vw', 'vw'), ('port_xc', 'xc'),
        ('port_xu', 'xu'), ('port_vl_re', 'vl_re'), ('port_ss', 'ss'),
        ('port_vm_ws', 'vm_ws'), ('port_vm_tls', 'vm_tls'), ('port_nv', 'nv'),
        ('port_an', 'an'), ('port_ar', 'ar'), ('port_hy2', 'hy2'),
        ('port_tu', 'tu'), ('port_so', 'so'), ('port_sn', 'sn'),
    ]
    _m = 0
    for _var, _key in _simple_reads:
        _p1 = _var + '=$(cat "$HOME/agsbx/' + _var + '")'
        _p2 = _var + '=$(port_get "' + _key + '" 2>/dev/null)'
        if _p1 in t:
            t = t.replace(_p1, _p2)
            _m += 1
        # 带 2>/dev/null 的版本
        _p1d = _var + '=$(cat "$HOME/agsbx/' + _var + '" 2>/dev/null)'
        _p2d = _var + '=$(port_get "' + _key + '" 2>/dev/null)'
        if _p1d in t:
            t = t.replace(_p1d, _p2d)
            _m += 1
    # argo 的特殊读取
    if 'argoport=$(cat "$HOME/agsbx/port_vm_ws" 2>/dev/null)' in t:
        t = t.replace('argoport=$(cat "$HOME/agsbx/port_vm_ws" 2>/dev/null)', 'argoport=$(port_get "vm_ws" 2>/dev/null)')
        _m += 1
    if 'argoport=$(cat "$HOME/agsbx/port_vw" 2>/dev/null)' in t:
        t = t.replace('argoport=$(cat "$HOME/agsbx/port_vw" 2>/dev/null)', 'argoport=$(port_get "vw" 2>/dev/null)')
        _m += 1
    if 'argoport=$(cat "$HOME/agsbx/port_vx" 2>/dev/null)' in t:
        t = t.replace('argoport=$(cat "$HOME/agsbx/port_vx" 2>/dev/null)', 'argoport=$(port_get "vx" 2>/dev/null)')
        _m += 1
    # hyport
    if 'hyport=$(cat "$HOME/agsbx/port_hy2")' in t:
        t = t.replace('hyport=$(cat "$HOME/agsbx/port_hy2")', 'hyport=$(port_get "hy2" 2>/dev/null)')
        _m += 1
    # vlpt 多实例显示 ($_vlpt_more_i)
    if '_vlpt_more_port=$(cat "$HOME/agsbx/port_vl_re$_vlpt_more_i" 2>/dev/null)' in t:
        t = t.replace('_vlpt_more_port=$(cat "$HOME/agsbx/port_vl_re$_vlpt_more_i" 2>/dev/null)', '_vlpt_more_port=$(port_get "vl_re$_vlpt_more_i" 2>/dev/null)')
        _m += 1
    print(f"converted {_m} port reads to port_get")

    # --- generated header (after shebang) ---
    lines = t.split("\n", 1)
    assert lines[0] == "#!/bin/bash"
    out = lines[0] + "\n# GENERATED BY build/build.py - DO NOT EDIT BY HAND - sources: upstream/argosbx.sh + modules/*.sh\n" + lines[1]
    if util.WRITE:
        (ROOT / "argosbx.sh").write_text(out)
        print(f"Built argosbx.sh: {len(out)} bytes, {out.count(chr(10))} lines")
    util.CURRENT_AREA = "index"
    build_index()
    util.CURRENT_AREA = "container"
    build_container()
    if check:
        return util.report_table()
    return 0
