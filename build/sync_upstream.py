#!/usr/bin/env python3
"""Sync and verify upstream repository (yonggekkk/argosbx) with local upstream/ directory.

Usage:
    python3 build/sync_upstream.py [--check] [--sync] [--simulate-drill]

Options:
    --check            Check upstream commit status and sha256 without modifying files (Default).
    --sync             Fetch and update upstream/ files, then trigger rebuild and full test suite.
    --simulate-drill   Run an automated upstream merge exercise demonstrating resilience and error reporting.
"""

import hashlib
import os
import pathlib
import subprocess
import sys
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent

UPSTREAM_FILES = [
    ("upstream/argosbx.sh", "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"),
    ("upstream/index.html", "https://raw.githubusercontent.com/yonggekkk/argosbx/main/index.html"),
    ("upstream/container/nodejs/start.sh", "https://raw.githubusercontent.com/yonggekkk/argosbx/main/container/nodejs/start.sh"),
]

def get_upstream_head():
    try:
        res = subprocess.run(
            ["git", "ls-remote", "https://github.com/yonggekkk/argosbx.git", "HEAD"],
            capture_output=True, text=True, timeout=15
        )
        if res.returncode == 0 and res.stdout:
            return res.stdout.split()[0]
    except Exception as e:
        print(f"Warning: Failed to fetch upstream HEAD via git: {e}", file=sys.stderr)
    return "unknown"

def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def check_status():
    head = get_upstream_head()
    print(f"=== 上游状态检查 (yonggekkk/argosbx) ===")
    print(f"当前上游 HEAD Commit: {head}\n")

    all_matched = True
    for local_path, url in UPSTREAM_FILES:
        full_local = ROOT / local_path
        if not full_local.exists():
            print(f"[-] 本地文件不存在: {local_path}")
            all_matched = False
            continue

        local_bytes = full_local.read_bytes()
        local_hash = sha256_bytes(local_bytes)

        try:
            req = urllib.request.urlopen(url, timeout=15)
            remote_bytes = req.read()
            remote_hash = sha256_bytes(remote_bytes)
        except Exception as e:
            print(f"[-] 拉取失败: {url} ({e})")
            all_matched = False
            continue

        if local_hash == remote_hash:
            print(f"[✓] {local_path:35} : 一致 (SHA256: {local_hash[:10]}...)")
        else:
            print(f"[!] {local_path:35} : 发现上游更新! (本地: {local_hash[:10]}... 远端: {remote_hash[:10]}...)")
            all_matched = False

    print("\n" + ("=" * 40))
    if all_matched:
        print("结论：本地 upstream/ 代码与上游最新版本 100% 同步，无需更新。")
    else:
        print("结论：检测到上游有更新，可运行 python3 build/sync_upstream.py --sync 进行同步。")
    return all_matched

def sync_upstream():
    print("=== 开始同步上游最新代码 ===")
    updated = False
    for local_path, url in UPSTREAM_FILES:
        full_local = ROOT / local_path
        print(f"正在下载 {url} ...")
        try:
            remote_bytes = urllib.request.urlopen(url, timeout=30).read()
        except Exception as e:
            print(f"下载失败: {e}", file=sys.stderr)
            sys.exit(1)

        if not full_local.exists() or full_local.read_bytes() != remote_bytes:
            full_local.parent.mkdir(parents=True, exist_ok=True)
            full_local.write_bytes(remote_bytes)
            print(f"[+] 已更新: {local_path}")
            updated = True
        else:
            print(f"[=] 无变动: {local_path}")

    print("\n=== 执行自动化构建与全量测试 ===")
    res_build = subprocess.run([sys.executable, "build/build.py"], cwd=ROOT)
    if res_build.returncode != 0:
        print("❌ 构建失败：上游修改破坏了部分锚点，请排查 build/build.py 报错信息！", file=sys.stderr)
        sys.exit(1)

    res_test = subprocess.run(["bash", "tests/run_all.sh"], cwd=ROOT)
    if res_test.returncode != 0:
        print("❌ 测试套件执行失败，请排查具体测试项！", file=sys.stderr)
        sys.exit(1)

    print("\n🎉 同步成功：代码构建与全量测试 100% 通过！")

def simulate_drill():
    print("=== 启动 Phase 3: 上游代码合入实操演练 ===\n")
    original_argosbx = (ROOT / "upstream/argosbx.sh").read_text(encoding="utf-8")

    try:
        # --- 演练场景 1: 上游进行常规内部逻辑微调 (格式化/注释/输出文本改动) ---
        print("【演练 1：上游常规逻辑微调测试 (Non-breaking Upstream Changes)】")
        print("说明：模拟上游作者在 installsb、installxray 或其他核心函数内部调整提示文字与缩进。")
        
        simulated_text = original_argosbx.replace(
            'echo "HY2/TUIC/Anytls/Xhttp-tls将使用自签证书的TLS"',
            'echo "HY2/TUIC/Anytls/Xhttp-tls将使用自签证书的TLS [上游 v2.1 更新测试]"'
        )
        (ROOT / "upstream/argosbx.sh").write_text(simulated_text, encoding="utf-8")

        res = subprocess.run([sys.executable, "build/build.py"], cwd=ROOT, capture_output=True, text=True)
        if res.returncode == 0:
            print("  ✓ 演练 1 构建通过！生命周期 Hook 架构成功防御了上游常规业务改动的冲击。")
        else:
            print(f"  ❌ 演练 1 构建失败: {res.stderr}")
            sys.exit(1)

        # --- 演练场景 2: 上游生命周期函数重命名冲突预警 (Breaking Change Detection) ---
        print("\n【演练 2：上游破坏性变更预警测试 (Breaking Change Diagnostic)】")
        print("说明：模拟上游作者重构了核心函数入口（例如将 xrsbout 重构为 xrsbout_new）。")

        breaking_text = original_argosbx.replace(
            'xrsbout(){\nif [ -e "$HOME/agsbx/xr.json" ]; then',
            'xrsbout_new(){\nif [ -e "$HOME/agsbx/xr.json" ]; then'
        )
        (ROOT / "upstream/argosbx.sh").write_text(breaking_text, encoding="utf-8")

        res_break = subprocess.run([sys.executable, "build/build.py"], cwd=ROOT, capture_output=True, text=True)
        if res_break.returncode != 0 and "BUILD FAIL:" in res_break.stderr:
            err_msg = [line for line in res_break.stderr.splitlines() if "BUILD FAIL:" in line][0]
            print("  ✓ 演练 2 预警精准触发！")
            print(f"  ✓ 诊断报告输出：明确指出 `{err_msg.strip()}`，开发者可在 1 分钟内精确定位修改。")
        else:
            print(f"  ❌ 演练 2 未能按预期捕获断裂: {res_break.stderr}")

    finally:
        # 恢复现场
        (ROOT / "upstream/argosbx.sh").write_text(original_argosbx, encoding="utf-8")
        subprocess.run([sys.executable, "build/build.py"], cwd=ROOT, capture_output=True)
        print("\n=== 实操演练完成，本地环境已 100% 干净恢复 ===")

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--sync":
        sync_upstream()
    elif len(sys.argv) > 1 and sys.argv[1] == "--simulate-drill":
        simulate_drill()
    else:
        check_status()

if __name__ == "__main__":
    main()
