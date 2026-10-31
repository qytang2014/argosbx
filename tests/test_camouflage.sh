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
# Find end: closing brace of deploy_camouflage_blog (line with just "}")
# The module ends right before the next top-level comment
m = re.search(r'\n\}\n# HTTPS domain subscription', t[start:])
assert m, "module end not found"
open(sys.argv[2] + "/module.sh", "w").write(t[start:start + m.start() + 3])
PY

# Deploy twice, verify determinism and completeness
bash -c "source $TMP/module.sh && deploy_camouflage_blog $TMP/out1" > "$TMP/log1" 2>&1
P1=$(grep -o "人设：.*" "$TMP/log1" | head -1)
bash -c "source $TMP/module.sh && deploy_camouflage_blog $TMP/out2" > "$TMP/log2" 2>&1
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

echo "PASS: camouflage blog"
