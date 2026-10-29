#!/bin/bash
# Test: kernel download verification (no network).
# upxray/upsingbox must abort (exit 1) with a clear message when the
# downloaded binary is missing, not executable, or fails its version probe --
# instead of limping on to a confusing "process not started" failure later.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. structural: verification present in both download functions
for fn in upxray upsingbox; do
  python3 - "$ROOT/argosbx.sh" "$fn" << PY
import re, sys
t = open(sys.argv[1]).read()
name = sys.argv[2]
m = re.search(rf"{name}\(\)\{{.*?\n\}}\n", t, re.S)
assert m, f"{name} not found"
body = m.group(0)
assert "内核下载失败" in body, f"{name} missing failure message"
assert "exit 1" in body, f"{name} missing abort"
print(f"{name}: verification present")
PY
done

# 2. functional: extract the actual verification line and run it against
# stub binaries in subshells (exit 1 must not kill the test itself).
verify_line=$(grep -o 'if \[ ! -x "\$HOME/agsbx/xray" \].*exit 1; fi' "$ROOT/argosbx.sh" | head -1)
[ -n "$verify_line" ] || { echo "FAIL: xray verify line not found"; exit 1; }

run_verify() { # $1 = HOME dir; prints exit code
  ( export HOME="$1"; eval "$verify_line" ) >/dev/null 2>&1; echo $?
}

home="$TMP/t"; mkdir -p "$home/agsbx"
# good binary: passes
printf '#!/bin/bash\necho "Xray 26.3.27 (Xray, Penetrates Everything.)"\n' > "$home/agsbx/xray"
chmod +x "$home/agsbx/xray"
[ "$(run_verify "$home")" = "0" ] || { echo "FAIL: good binary should pass"; exit 1; }
# missing binary: fails
rm -f "$home/agsbx/xray"
[ "$(run_verify "$home")" = "1" ] || { echo "FAIL: missing binary should fail"; exit 1; }
# not executable: fails (and the bad binary is removed by the check itself)
printf '#!/bin/bash\necho "Xray 26.3.27"\n' > "$home/agsbx/xray"
[ "$(run_verify "$home")" = "1" ] || { echo "FAIL: non-executable should fail"; exit 1; }
# corrupt download (e.g. 404 HTML): fails version probe
printf '#!/bin/bash\necho "404: Not Found"\n' > "$home/agsbx/xray"
chmod +x "$home/agsbx/xray"
[ "$(run_verify "$home")" = "1" ] || { echo "FAIL: corrupt binary should fail"; exit 1; }
# failed binary is removed
[ ! -e "$home/agsbx/xray" ] || { echo "FAIL: failed binary should be removed"; exit 1; }
echo "PASS: kernel download verification"
