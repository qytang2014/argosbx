#!/bin/bash
# Run everything: build first, then all tests. Fails fast on first failure.
# Usage: bash tests/run_all.sh  (from repo root)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if ! command -v shuf >/dev/null 2>&1; then
  SHUF_DIR="$(mktemp -d)"
  cat > "$SHUF_DIR/shuf" << 'EOF'
#!/bin/bash
python3 -c 'import random; print(random.randint(10000, 65535))'
EOF
  chmod +x "$SHUF_DIR/shuf"
  export PATH="$SHUF_DIR:$PATH"
fi
bash tests/test_build.sh
bash tests/test_hook.sh
bash tests/test_hook_once.sh
bash tests/test_egress.sh
bash tests/test_egress_v2.sh
bash tests/test_cert.sh
bash tests/test_cert_migrate.sh
bash tests/test_vars.sh
bash tests/test_sap.sh
bash tests/test_cert_watch.sh
bash tests/test_camouflage.sh
bash tests/test_reality_addr.sh
bash tests/test_plain_addr.sh
bash tests/test_container.sh
bash tests/test_container_egress.sh
bash tests/test_egress_geo.sh
bash tests/test_egress_add.sh
bash tests/test_egress_inbound.sh
bash tests/test_egress_and.sh
bash tests/test_egress_protocols.sh
bash tests/test_egress_misalign.sh
bash tests/test_kernel_verify.sh
bash tests/test_vlpt_more.sh
bash tests/test_proto_more.sh
bash tests/test_container_vars.sh
bash tests/test_vlpt_dual.sh
bash tests/test_vlpt_pbk.sh
bash tests/test_selfsigned_san.sh
bash tests/test_pin_vmtls.sh
bash tests/test_ufw.sh
bash tests/test_firewall.sh
bash tests/test_sub_https.sh
python3 tests/test_index.py
echo "ALL TESTS PASS"
