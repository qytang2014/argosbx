#!/bin/bash
# Test: SAP pass-through + private image. No network, no cf, no Docker.
set -u
cd "$(dirname "$0")/.." || exit 1
FAIL=0
for f in sap.sh saph.sh sapsbx.sh sapsbxh.sh; do
  bash -n "$f" || { echo "FAIL: $f syntax"; FAIL=1; }
done
# Old variable line numbers in sapsbx.sh must not move (sap.sh seds by line)
for spec in "50:CF_USERNAMES" "53:CF_PASSWORDS" "56:REGIONS" "59:UUIDS" "62:APP_NAMES" "65:VMPTS" "68:AGNS" "71:AGKS" "74:crontime" "79:DELAPP"; do
  ln="${spec%%:*}"; var="${spec#*:}"
  [ "$(sed -n "${ln}p" sapsbx.sh | cut -d= -f1)" = "$var" ] || { echo "FAIL: sapsbx.sh line $ln is not $var"; FAIL=1; }
done
# New variables are after DELAPP, so old seds still work
for var in YMS EGRESS_NODES EGRESS_BINDS EGRESS_RULES; do
  ln=$(grep -n "^$var=" sapsbx.sh | cut -d: -f1 | head -1)
  [ -n "$ln" ] && [ "$ln" -gt 79 ] || { echo "FAIL: $var not after DELAPP"; FAIL=1; }
  grep -q "read -ra $var" sapsbx.sh || { echo "FAIL: $var not read into array"; FAIL=1; }
done
# Per-account assignment + no -> empty
grep -q 'YM="${YMS\[$i\]}"' sapsbx.sh || { echo "FAIL: YM per-account"; FAIL=1; }
grep -q 'EGRESS_NODE="${EGRESS_NODES\[$i\]}"' sapsbx.sh || { echo "FAIL: EGRESS_NODE per-account"; FAIL=1; }
# sapcfevn sets the new env vars, and only when non-empty
grep -q 'cf set-env "$APP_NAME" ym "$YM"' sapsbx.sh || { echo "FAIL: cf set-env ym"; FAIL=1; }
grep -q 'cf set-env "$APP_NAME" egress_nodes "$EGRESS_NODE"' sapsbx.sh || { echo "FAIL: cf set-env egress_nodes"; FAIL=1; }
grep -q 'cf set-env "$APP_NAME" egress_bind "$EGRESS_BIND"' sapsbx.sh || { echo "FAIL: cf set-env egress_bind"; FAIL=1; }
grep -q 'cf set-env "$APP_NAME" egress_rules "$EGRESS_RULE"' sapsbx.sh || { echo "FAIL: cf set-env egress_rules"; FAIL=1; }
# Private image, not upstream
grep -q 'cf push "$APP_NAME" --docker-image qytang2014/argosbx' sapsbx.sh || { echo "FAIL: cf push image not private"; FAIL=1; }
grep -q 'ygkkk/argosbx' sapsbx.sh && { echo "FAIL: sapsbx.sh still references upstream image"; FAIL=1; }
# sap.sh prompts for new vars, name-based sed (not line-number)
for var in YMS EGRESS_NODES EGRESS_BINDS EGRESS_RULES; do
  grep -q "s/^$var=.*\$/$var=" sap.sh || { echo "FAIL: sap.sh name-based sed for $var"; FAIL=1; }
done
# Dockerfile: node base, copies generated start.sh, runs index.js
grep -q '^FROM node:' container/nodejs/Dockerfile || { echo "FAIL: Dockerfile base"; FAIL=1; }
grep -q 'COPY package.json index.js start.sh' container/nodejs/Dockerfile || { echo "FAIL: Dockerfile copy"; FAIL=1; }
grep -q 'CMD \["node", "index.js"\]' container/nodejs/Dockerfile || { echo "FAIL: Dockerfile cmd"; FAIL=1; }
# sapcfevn isolation: mock cf, check set-env calls and empty-skip
python3 - << 'PY'
import re
t = open("sapsbx.sh").read()
m = re.search(r"sapcfevn\(\) \{.*?\n\}\n", t, re.S)
assert m, "sapcfevn not found"
open("/tmp/sapcfevn.sh", "w").write(m.group(0))
PY
cat > /tmp/run_sapcfevn.sh << 'RUN'
#!/bin/bash
cf() { echo "cf $*"; }
source /tmp/sapcfevn.sh
export APP_NAME=testapp UUID=u1 VMPT="" YM=node.example.com EGRESS_NODE='socks5://a@1.1.1.1:1080#t1' EGRESS_BIND="" EGRESS_RULE='geoip:cn=>direct'
out=$(sapcfevn 2>/dev/null)
echo "$out" | grep -q 'cf set-env testapp ym node.example.com' || { echo "FAIL: mock ym"; exit 1; }
echo "$out" | grep -q 'cf set-env testapp egress_nodes socks5://a@1.1.1.1:1080#t1' || { echo "FAIL: mock egress_nodes"; exit 1; }
echo "$out" | grep -q 'cf set-env testapp egress_bind' && { echo "FAIL: empty egress_bind should be skipped"; exit 1; }
echo "$out" | grep -q 'cf set-env testapp egress_rules geoip:cn=>direct' || { echo "FAIL: mock egress_rules"; exit 1; }
RUN
bash /tmp/run_sapcfevn.sh || FAIL=1
[ $FAIL -eq 0 ] && echo "PASS: sap (pass-through, line numbers, private image, Dockerfile, sapcfevn)"
exit $FAIL
