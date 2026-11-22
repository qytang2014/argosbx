#!/bin/bash
# Test: camouflage blog module - deploy works, personas deterministic, no placeholders left.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Extract the camouflage module (from _camouflage_personas to end of deploy_camouflage_blog)
python3 - "$ROOT/argosbx.sh" "$TMP" << 'PY'
import re, sys
t = open(sys.argv[1]).read()
start = t.find("_camouflage_personas() {")
assert start >= 0, "camouflage module not found"
# End: everything up to the next top-level comment (# HTTPS domain
# subscription starts the upstream subscription section after all
# inserted modules). Do NOT match the exact line before the comment:
# it is the last inserted module's closing line, whose form varies
# (e.g. `}` vs `} || true` after the step-3 registration guards).
cmt = t.find('\n# HTTPS domain subscription', start)
assert cmt >= 0, "module end not found"
open(sys.argv[2] + "/module.sh", "w").write(t[start:cmt] + "\n")
PY

# Deploy twice, verify determinism and completeness
# (source hook.sh first: the extracted range also covers other modules'
# register_hook blocks, which need the engine defined for `source` to
# return 0; since step 3 the range ends with a registration block)
bash -c "source $ROOT/modules/hook.sh; source $TMP/module.sh && deploy_camouflage_blog $TMP/out1" > "$TMP/log1" 2>&1
P1=$(grep -o "人设：.*" "$TMP/log1" | head -1)
bash -c "source $ROOT/modules/hook.sh; source $TMP/module.sh && deploy_camouflage_blog $TMP/out2" > "$TMP/log2" 2>&1
P2=$(grep -o "人设：.*" "$TMP/log2" | head -1)
[ "$P1" = "$P2" ] || { echo "FAIL: persona not deterministic: $P1 vs $P2"; exit 1; }
echo "persona deterministic: $P1"

# 14 files expected: style.css + index/about/archive + 10 posts
N=$(find "$TMP/out1" -type f | wc -l)
[ "$N" = "14" ] || { echo "FAIL: expected 14 files, got $N"; exit 1; }

# No leftover placeholders
[ -z "$(grep -rl "{{" "$TMP/out1" 2>/dev/null)" ] || { echo "FAIL: leftover placeholders"; exit 1; }

# Persona actually substituted (title should not contain {{)
grep -q "{{" "$TMP/out1/index.html" && { echo "FAIL: index has placeholder"; exit 1; }
grep -q "<title>.* - .*的技术笔记</title>" "$TMP/out1/index.html" || { echo "FAIL: title not substituted"; exit 1; }

# HTML balanced (simple check)
python3 - "$TMP/out1" << 'PY'
import html.parser, glob, sys
class P(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(); self.stack=[]
    def handle_starttag(self, tag, attrs):
        if tag not in ('meta','link','br','img','input','hr'): self.stack.append(tag)
    def handle_endtag(self, tag):
        if self.stack and self.stack[-1]==tag: self.stack.pop()
for f in glob.glob(sys.argv[1] + '/**/*.html', recursive=True):
    p=P(); p.feed(open(f).read())
    assert not p.stack, f'{f}: unbalanced {p.stack}'
print("HTML balanced OK")
PY

# ym != reym 时默认跳过（硬伤 3）；camouflage=1 可强制；ym == reym 正常部署
# （ym/reym/camouflage 以环境变量传入子 shell；函数读全局变量）
ym="example.com" reym="other.example" bash -c "source $ROOT/modules/hook.sh; source $TMP/module.sh && deploy_camouflage_blog $TMP/out-skip" > "$TMP/log-skip" 2>&1
grep -q "伪装博客跳过" "$TMP/log-skip" || { echo "FAIL: ym != reym 时应跳过并提示"; exit 1; }
[ ! -e "$TMP/out-skip/index.html" ] || { echo "FAIL: ym != reym 时不应部署博客"; exit 1; }

ym="example.com" reym="other.example" camouflage="1" bash -c "source $ROOT/modules/hook.sh; source $TMP/module.sh && deploy_camouflage_blog $TMP/out-force" > "$TMP/log-force" 2>&1
N_FORCE=$(find "$TMP/out-force" -type f | wc -l)
[ "$N_FORCE" = "14" ] || { echo "FAIL: camouflage=1 强制部署应得 14 个文件，实际 $N_FORCE"; exit 1; }

ym="example.com" reym="example.com" bash -c "source $ROOT/modules/hook.sh; source $TMP/module.sh && deploy_camouflage_blog $TMP/out-same" > "$TMP/log-same" 2>&1
N_SAME=$(find "$TMP/out-same" -type f | wc -l)
[ "$N_SAME" = "14" ] || { echo "FAIL: ym == reym 时应正常部署，实际 $N_SAME"; exit 1; }

echo "PASS: camouflage blog"
